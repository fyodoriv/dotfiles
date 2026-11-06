#!/usr/bin/env ruby
# A one-shot private-log writer. The caller supplies a trusted home directory.

require "fiddle/import"

module Glove80PrivateLog
  module Native
    extend Fiddle::Importer
    dlload Fiddle.dlopen(nil)
    extern "int fchdir(int)"
  end

  def self.change_directory(io)
    raise SystemCallError.new("fchdir", Fiddle.last_error) unless Native.fchdir(io.fileno).zero?
  end

  def self.check_directory(io)
    stat = io.stat
    raise SecurityError, "unsafe directory" unless stat.directory? && stat.uid == Process.euid && (stat.mode & 0o022).zero?
    io.close_on_exec = true
  end

  def self.open_child(parent, name)
    change_directory(parent)
    begin
      io = File.open(name, File::RDONLY | File::NOFOLLOW | File::NONBLOCK)
    rescue Errno::ENOENT
      begin
        Dir.mkdir(name, 0o700)
      rescue Errno::EEXIST
        # Another creator won; the no-follow open below still decides safety.
      end
      io = File.open(name, File::RDONLY | File::NOFOLLOW | File::NONBLOCK)
    end
    begin
      check_directory(io)
    rescue Exception
      io.close
      raise
    end
    io
  end

  def self.append(home:, path:, text:)
    raise SecurityError, "single-thread process required" unless Thread.list.length == 1
    root = File.expand_path(home)
    raise SecurityError, "log must be inside home" unless path.start_with?(root + "/")
    parts = path.delete_prefix(root + "/").split("/", -1)
    raise SecurityError, "invalid log path" if parts.empty? || parts.any? { |part| part.empty? || part == "." || part == ".." }
    name = parts.pop
    original = File.open(".", File::RDONLY | File::NOFOLLOW | File::NONBLOCK)
    original.close_on_exec = true
    directory = nil
    begin
      directory = File.open(root, File::RDONLY | File::NOFOLLOW | File::NONBLOCK)
      check_directory(directory)
      parts.each do |part|
        child = open_child(directory, part)
        directory.close
        directory = child
      end
      yield directory if block_given?
      change_directory(directory)
      flags = File::WRONLY | File::APPEND | File::CREAT | File::NOFOLLOW | File::NONBLOCK
      file = File.open(name, flags, 0o600)
      begin
        file.close_on_exec = true
        stat = file.stat
        raise SecurityError, "unsafe log file" unless stat.file? && stat.uid == Process.euid && stat.nlink == 1 && (stat.mode & 0o077).zero?
        file.write(text)
        file.flush
      ensure
        file.close
      end
    ensure
      begin
        change_directory(original)
      ensure
        directory.close if directory && !directory.closed?
        original.close
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    raise ArgumentError, "expected home, path and line" unless ARGV.length == 3
    Glove80PrivateLog.append(home: ARGV[0], path: ARGV[1], text: ARGV[2] + "\n")
  rescue SecurityError, SystemCallError, ArgumentError => e
    warn "private log unavailable: #{e.class}"
    exit 1
  end
end
