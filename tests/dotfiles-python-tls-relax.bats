#!/usr/bin/env bats
# dotfiles #349: clear only VERIFY_X509_STRICT in one opted-in venv.

setup() {
  TEST_DIR="$(mktemp -d)"
  python3 -m venv --without-pip "$TEST_DIR/venv"
  TOOL="$BATS_TEST_DIRNAME/../bin/dotfiles-python-tls-relax"
}

teardown() { rm -rf "$TEST_DIR"; }

@test "an opted-in venv clears VERIFY_X509_STRICT and keeps chain and hostname checks" {
  run "$TOOL" "$TEST_DIR/venv"
  [ "$status" -eq 0 ]
  run "$TEST_DIR/venv/bin/python" -c '
import ssl
c = ssl.create_default_context()
h = ssl._create_default_https_context()
assert not (c.verify_flags & ssl.VERIFY_X509_STRICT)
assert not (h.verify_flags & ssl.VERIFY_X509_STRICT)
assert c.verify_mode == ssl.CERT_REQUIRED and c.check_hostname
print("ok")'
  [ "$status" -eq 0 ]
  [ "$output" = ok ]
}

@test "a venv that did not opt in keeps VERIFY_X509_STRICT" {
  run "$TEST_DIR/venv/bin/python" -c 'import ssl; print(bool(ssl.create_default_context().verify_flags & ssl.VERIFY_X509_STRICT))'
  [ "$output" = True ]
}

@test "a module that binds create_urllib3_context at import gets the relaxed one" {
  "$TOOL" "$TEST_DIR/venv"
  site="$("$TEST_DIR/venv/bin/python" -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])')"
  mkdir -p "$site/urllib3/util"
  : > "$site/urllib3/__init__.py"
  printf 'import ssl\ndef create_urllib3_context():\n    c = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)\n    c.verify_flags |= ssl.VERIFY_X509_STRICT\n    return c\n' > "$site/urllib3/util/ssl_.py"
  printf 'from .ssl_ import create_urllib3_context\n' > "$site/urllib3/util/__init__.py"
  printf 'from .util.ssl_ import create_urllib3_context\n' > "$site/urllib3/connection.py"
  run "$TEST_DIR/venv/bin/python" -c '
import ssl, urllib3.connection as c, urllib3.util as u
for f in (c.create_urllib3_context, u.create_urllib3_context):
    assert not (f().verify_flags & ssl.VERIFY_X509_STRICT)
print("ok")'
  [ "$output" = ok ]
}

@test "httplib2 uses SSL_CERT_FILE when it is set" {
  "$TOOL" "$TEST_DIR/venv"
  site="$("$TEST_DIR/venv/bin/python" -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])')"
  printf 'CA_CERTS = "/default/bundle"\n' > "$site/httplib2.py"
  : > "$TEST_DIR/ca.pem"
  run env SSL_CERT_FILE="$TEST_DIR/ca.pem" "$TEST_DIR/venv/bin/python" -c 'import httplib2; print(httplib2.CA_CERTS)'
  [ "$output" = "$TEST_DIR/ca.pem" ]
}

@test "--remove takes it out again" {
  "$TOOL" "$TEST_DIR/venv"
  "$TOOL" --remove "$TEST_DIR/venv"
  run "$TEST_DIR/venv/bin/python" -c 'import ssl; print(bool(ssl.create_default_context().verify_flags & ssl.VERIFY_X509_STRICT))'
  [ "$output" = True ]
}

@test "bad input exits 2" {
  run "$TOOL"
  [ "$status" -eq 2 ]
}
