use strict;
use warnings;
use Cwd qw(realpath);
use Errno qw(EAGAIN ENOENT EWOULDBLOCK);
use Fcntl qw(:DEFAULT :flock :mode);
use File::Basename qw(basename dirname);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempfile);

sub refuse { die "Shared plugin signer registry: $_[0]\n"; }

sub same_file {
    my ($left, $right) = @_;
    return @$left && @$right && $left->[0] == $right->[0] && $left->[1] == $right->[1];
}

sub load_registry {
    my ($path) = @_;
    my @entry = lstat($path);
    return ([], []) if !@entry && $! == ENOENT;
    refuse("registry ownership or file type is unknown")
        unless @entry && S_ISREG($entry[2]) && $entry[3] == 1 && $entry[4] == $> && !($entry[2] & 0022);
    sysopen(my $input, $path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK) or refuse("cannot open registry");
    my @held = stat($input);
    refuse("registry identity changed") unless same_file(\@entry, \@held);
    my @lines = <$input>;
    close($input) or refuse("cannot close registry");
    return (\@lines, \@entry);
}

sub matches {
    my ($line, $name, $key) = @_;
    my ($principal, @fields) = split(' ', $line, 5);
    return 0 unless defined $principal && $principal eq $name;
    shift @fields if @fields && $fields[0] =~ /^namespaces=/;
    return @fields >= 2 && "$fields[0] $fields[1]" eq $key;
}

my ($action, $requested, $name, $key) = @ARGV;
refuse("invalid signer write")
    unless @ARGV == 4 && ($action eq 'trust' || $action eq 'revoke')
    && $name =~ /\A[a-z0-9][a-z0-9-]{0,63}\z/ && $key =~ /\A(?:ssh-|ecdsa-|sk-)\S+ [A-Za-z0-9+\/=]+\z/;

my $parent = dirname(File::Spec->rel2abs($requested));
make_path($parent, { mode => 0700 }) if $action eq 'trust' && !-d $parent;
my $directory = realpath($parent);
my @directory = defined $directory ? stat($directory) : ();
refuse("registry directory ownership is unknown")
    unless @directory && S_ISDIR($directory[2]) && $directory[4] == $> && !($directory[2] & 0022);

my $registry = File::Spec->catfile($directory, basename($requested));
my $fence = "$registry.agentbrew-signer-v1.lock";
sysopen(my $owner, $fence, O_RDWR | O_CREAT | O_NOFOLLOW | O_NONBLOCK, 0600) or refuse("cannot open commit lock");
my @held = stat($owner);
my @named = lstat($fence);
refuse("commit lock ownership or file type is unknown")
    unless same_file(\@held, \@named) && S_ISREG($held[2]) && $held[3] == 1 && $held[4] == $>
    && ($held[2] & 0777) == 0600;
if (!flock($owner, LOCK_EX | LOCK_NB)) {
    if ($! == EAGAIN || $! == EWOULDBLOCK) {
        warn "Shared plugin signer registry is busy. Retry after publication finishes.\n";
        exit 75;
    }
    refuse("cannot obtain commit lock");
}

my ($lines, $identity) = load_registry($registry);
my @other_signers = grep { !matches($_, $name, $key) } @$lines;
my $already_trusted = @other_signers < @$lines;
exit 0 if $action eq 'trust' && $already_trusted;
refuse("signer is not trusted for $name") if $action eq 'revoke' && !$already_trusted;

if ($action eq 'trust') {
    $other_signers[-1] .= "\n" if @other_signers && $other_signers[-1] !~ /\n\z/;
    push @other_signers, "$name namespaces=\"git\" $key\n";
}
my ($staged, $temp) = tempfile(".plugin-signers-XXXXXX", DIR => $directory, UNLINK => 1);
print {$staged} @other_signers or refuse("cannot stage registry");
chmod(@$identity ? $identity->[2] & 0777 : 0600, $temp) or refuse("cannot preserve registry permissions");
close($staged) or refuse("cannot close staged registry");

my ($current, $now) = load_registry($registry);
@named = lstat($fence);
refuse("registry or lock changed during staging")
    unless same_file(\@held, \@named)
    && ((!@$identity && !@$now) || same_file($identity, $now))
    && join('', @$current) eq join('', @$lines);
rename($temp, $registry) or refuse("cannot replace registry");
