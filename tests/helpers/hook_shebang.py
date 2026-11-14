"""Pure, bounded first-line decoding; this does not resolve executable paths."""
import re

MAX_HEADER_BYTES = 256
_INTERPRETER = re.compile(rb"/(?:[A-Za-z0-9_.+-]+/)*[A-Za-z0-9_.+-]+")
_ARGUMENT = re.compile(rb"[A-Za-z0-9_.+-]+")


def decode_header(data):
    """Return (status, interpreter, argument); never inspect files or run tools."""
    if not isinstance(data, bytes) or len(data) > MAX_HEADER_BYTES:
        return "unsupported", None, None
    if not data.startswith(b"#!"):
        return "not_script", None, None
    newline = data.find(b"\n")
    if newline < 0:
        return "unsupported", None, None
    header = data[2:newline]
    if b"\0" in header or header.count(b" ") > 1:
        return "unsupported", None, None
    parts = header.split(b" ")
    interpreter = parts[0]
    if not _INTERPRETER.fullmatch(interpreter):
        return "unsupported", None, None
    components = interpreter.split(b"/")[1:]
    if any(part in (b".", b"..") for part in components) or components[-1] == b"env":
        return "unsupported", None, None
    if len(parts) == 2 and not _ARGUMENT.fullmatch(parts[1]):
        return "unsupported", None, None
    return "script", interpreter.decode("ascii"), parts[1].decode("ascii") if len(parts) == 2 else None
