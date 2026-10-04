# Generic private-reference markers that need no private pattern file.
# Used by lib/gh-public-leak.sh (public gh writes) and git-hooks/pre-push
# (lines added by pushed commits). Prints "<file><TAB><class>" once per file
# and class. Variables: home (this machine's $HOME), me (its user name),
# ent (space-separated enterprise gh hosts).
#
# Placeholders are not matches: /Users/<you>/, /Users/$USER/, common sample
# user names, *.example.* hosts, sample company hosts such as
# github.acme.com, reverse-DNS ids such as com.github.x, editor setting keys
# such as github.copilot.x, and GitHub Actions expressions such as
# github.event.x.
function hit(cls) {
  if (!((FILENAME SUBSEP cls) in seen)) { seen[FILENAME SUBSEP cls] = 1; print FILENAME "\t" cls }
}
function placeholder(h) {
  return (("." h ".") ~ /\.(example|your-?company|my-?company|your-?org|my-?org|acme|globex|initech|contoso|fabrikam)\./) || (h ~ /\.(test|invalid|localhost|local)$/)
}
function labels(s,   n, parts, i) {
  n = split(s, parts, ".")
  for (i = 1; i <= n; i++) if (parts[i] !~ /^[a-z0-9-]+$/) return 0
  return n
}
BEGIN {
  nent = split(ent, ents, " ")
  split("shared runner user username you me example linuxbrew test x alice bob alex other jdoe", ok, " ")
  for (i in ok) homeok[ok[i]] = 1
  me = tolower(me)
}
{
  line = $0
  lc = tolower(line)
  if (home != "" && index(line, home "/") > 0) hit("home path")
  s = line; off = 0
  while (match(s, /\/(Users|home)\/[^\/ \t<>$*{}%~]+\//)) {
    pos = off + RSTART
    pre = (pos > 1) ? substr(line, pos - 1, 1) : ""
    name = tolower(substr(s, RSTART, RLENGTH))
    sub(/^\/(users|home)\//, "", name); sub(/\/$/, "", name)
    if (pre !~ /[A-Za-z0-9._-]/ && name !~ /^\./ && name !~ /[][()+?|\\^]/ && !(name in homeok) && name != me) { hit("user home path"); break }
    off = pos; s = substr(s, RSTART + 1)
  }
  n = split(lc, toks, /[^a-z0-9._-]+/)
  for (i = 1; i <= n; i++) {
    t = toks[i]; sub(/\.+$/, "", t)
    p = index("." t, ".github.")
    if (p > 0) {
      h = substr(t, p)
      # Reverse-DNS ids (com.github.x) name a bundle, not a host.
      rdns = (p > 1) && (substr(t, 1, p - 2) ~ /(^|\.)(com|org|net|io|dev|app)$/)
      if (!rdns && labels(substr(h, 8)) >= 2 && !placeholder(h) \
          && h !~ /^github\.(event|ref|repository|actor|sha|workflow|job|token|workspace|action|env|path|copilot)\./ \
          && h !~ /(\.githubassets\.com|^github\.global\.ssl\.fastly\.net)$/ \
          && h !~ /\.(json|yml|yaml|md|txt|toml|lock|xml|html|css|js|ts|sh|py|rb|go|rs|conf|cfg|ini|log|tmpl)$/)
        hit("enterprise-style host")
    }
    if (t ~ /[a-z0-9-]\.ghe\.com$/) {
      name = t; sub(/\.ghe\.com$/, "", name); sub(/^.*\./, "", name)
      if (name !~ /^(example|subdomain|tenant|octocorp)$/) hit("enterprise-style host")
    }
  }
  s = lc
  while (match(s, /(ssh:\/\/)?git@[a-z0-9.-]+/)) {
    m = substr(s, RSTART, RLENGTH); nxt = substr(s, RSTART + RLENGTH, 1)
    viassh = (m ~ /^ssh:/)
    sub(/^(ssh:\/\/)?git@/, "", m)
    if ((viassh || nxt == ":") && m !~ /^(github\.com|ssh\.github\.com|gitlab\.com|bitbucket\.org|codeberg\.org|host|hostname)$/ && !placeholder(m)) { hit("ssh host"); break }
    s = substr(s, RSTART + RLENGTH)
  }
  for (i = 1; i <= nent; i++) if (ents[i] != "" && ents[i] != "github.com" && index(lc, ents[i]) > 0) hit("enterprise host")
}
