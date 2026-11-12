"""In-memory output cap for a future owned-child capture."""

LIMIT = 4096


class BoundedOutput:
    def __init__(self):
        self._streams = {"stdout": bytearray(), "stderr": bytearray()}
        self.overflowed = False

    def append(self, stream, value):
        if type(stream) is not str or stream not in self._streams or type(value) is not bytes:
            raise ValueError("invalid output")
        current = self._streams[stream]
        available = LIMIT - len(current)
        if len(value) > available:
            self.overflowed = True
        current.extend(value[:available])

    def data(self, stream):
        if type(stream) is not str or stream not in self._streams:
            raise ValueError("invalid stream")
        return bytes(self._streams[stream])

    @property
    def empty(self):
        return not self.overflowed and not any(self._streams.values())

    def receipt(self):
        return {"empty": self.empty, "overflowed": self.overflowed}
