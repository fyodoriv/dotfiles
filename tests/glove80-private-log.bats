#!/usr/bin/env bats

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR/home"
  export LOG_HELPER="$BATS_TEST_DIRNAME/../lib/glove80-private-log.rb"
  mkdir -p "$HOME" "$TEST_DIR/sentinel"
  chmod 700 "$HOME" "$TEST_DIR/sentinel"
  if [ ! -f "$LOG_HELPER" ]; then
    if [ "${GLOVE80_REQUIRE_LOG_HELPER:-0}" = 1 ]; then
      echo "private-log helper is not implemented" >&2
      return 1
    fi
    skip "private-log helper is not implemented yet"
  fi
}

teardown() { rm -rf "$TEST_DIR"; }

@test "private log appends to an owned file with mode 600" {
  run gtimeout --kill-after=1s 10s ruby -e '
    require ENV.fetch("LOG_HELPER")
    Glove80PrivateLog.append(home: ENV.fetch("HOME"), path: ENV.fetch("HOME") + "/logs/log", text: "first\n")
    Glove80PrivateLog.append(home: ENV.fetch("HOME"), path: ENV.fetch("HOME") + "/logs/log", text: "second\n")
  '
  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/logs/log")" = $'first\nsecond' ]
  [ "$(stat -f '%Lp' "$HOME/logs/log")" = 600 ]
}

@test "replacing an opened parent cannot redirect a log write" {
  mkdir -p "$HOME/logs"
  chmod 700 "$HOME/logs"
  printf 'untouched\n' > "$TEST_DIR/sentinel/log"
  export SENTINEL_DIR="$TEST_DIR/sentinel"
  run gtimeout --kill-after=1s 10s ruby -e '
    require ENV.fetch("LOG_HELPER")
    home = ENV.fetch("HOME")
    begin
      Glove80PrivateLog.append(home: home, path: home + "/logs/log", text: "new\n") do |directory|
        raise "missing open directory descriptor" unless directory.is_a?(IO) && !IO.instance_method(:closed?).bind(directory).call
        raise "invalid descriptor" unless IO.instance_method(:fileno).bind(directory).call >= 0
        opened = IO.instance_method(:stat).bind(directory).call
        expected = File.stat(home + "/logs")
        raise "wrong directory descriptor" unless opened.directory? && [opened.dev, opened.ino] == [expected.dev, expected.ino]
        File.rename(home + "/logs", home + "/original")
        File.symlink(ENV.fetch("SENTINEL_DIR"), home + "/logs")
        File.write(home + "/swap-complete", "yes")
      end
    rescue SecurityError, SystemCallError
      exit 0
    end
    exit 2 unless File.file?(home + "/original/log") && File.read(home + "/original/log") == "new\n"
  '
  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/swap-complete")" = yes ]
  [ "$(cat "$TEST_DIR/sentinel/log")" = untouched ]
}

@test "private log restores the working directory after success and failure" {
  run gtimeout --kill-after=1s 10s ruby -e '
    require ENV.fetch("LOG_HELPER")
    home = ENV.fetch("HOME")
    before = Dir.pwd
    Glove80PrivateLog.append(home: home, path: home + "/logs/log", text: "ok\n")
    raise "cwd changed" unless Dir.pwd == before
    File.symlink(home + "/logs/log", home + "/logs/link")
    begin
      Glove80PrivateLog.append(home: home, path: home + "/logs/link", text: "bad\n")
      raise "symlink accepted"
    rescue SecurityError, SystemCallError
      raise "cwd changed after refusal" unless Dir.pwd == before
    end
  '
  [ "$status" -eq 0 ]
}

@test "private log refuses a multi-threaded caller" {
  run gtimeout --kill-after=1s 10s ruby -e '
    require ENV.fetch("LOG_HELPER")
    ready = Queue.new
    thread = Thread.new { ready << true; sleep 10 }
    ready.pop
    begin
      Glove80PrivateLog.append(home: ENV.fetch("HOME"), path: ENV.fetch("HOME") + "/logs/log", text: "bad\n")
      raise "multi-threaded caller accepted"
    rescue SecurityError
      exit 0
    ensure
      thread.kill
      thread.join
    end
  '
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/logs/log" ]
}

@test "private log refuses a FIFO without blocking" {
  mkdir -p "$HOME/logs"
  chmod 700 "$HOME/logs"
  mkfifo "$HOME/logs/log"
  run gtimeout --kill-after=1s 10s ruby -e '
    require ENV.fetch("LOG_HELPER")
    begin
      Glove80PrivateLog.append(home: ENV.fetch("HOME"), path: ENV.fetch("HOME") + "/logs/log", text: "bad\n")
      raise "FIFO accepted"
    rescue SecurityError, SystemCallError
      exit 0
    end
  '
  [ "$status" -eq 0 ]
}

@test "a failed directory change never falls back to pathname writes" {
  run gtimeout --kill-after=1s 10s ruby -e '
    require ENV.fetch("LOG_HELPER")
    Glove80PrivateLog::Native.define_singleton_method(:fchdir) { |_| -1 }
    begin
      Glove80PrivateLog.append(home: ENV.fetch("HOME"), path: ENV.fetch("HOME") + "/logs/log", text: "bad\n")
      raise "failed directory change accepted"
    rescue SecurityError, SystemCallError
      exit 0
    end
  '
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/logs/log" ]
}
