"""Read pinned blob contents in one checked Git process."""
import re
import subprocess


def read_blobs(blobs):
    if any(not re.fullmatch(r"[0-9a-f]{40,64}", blob) for blob in blobs):
        raise ValueError("invalid blob identity")
    result = subprocess.run(["git", "cat-file", "--batch"],
                            input=("".join(blob + "\n" for blob in blobs)).encode("ascii"),
                            stdout=subprocess.PIPE, check=True)
    remaining = result.stdout
    contents = []
    for blob in blobs:
        header, separator, remaining = remaining.partition(b"\n")
        fields = header.split(b" ")
        if (not separator or len(fields) != 3 or fields[0] != blob.encode("ascii") or
                fields[1] != b"blob" or not fields[2].isdigit()):
            raise ValueError("invalid batch response")
        size = int(fields[2])
        if len(remaining) <= size or remaining[size:size + 1] != b"\n":
            raise ValueError("truncated batch response")
        contents.append(remaining[:size])
        remaining = remaining[size + 1:]
    if remaining:
        raise ValueError("unexpected batch response")
    return contents
