import importlib.util
from pathlib import Path
import struct
import tempfile
import unittest


path = Path(__file__).with_name('judge-reader-build-runner-id-v3.py')
spec = importlib.util.spec_from_file_location('judge_reader_build_runner', path)
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


def sample(machine=183, kind=1):
    data = bytearray(120)
    data[:6] = b'\x7fELF\x02\x01'
    struct.pack_into('<HH', data, 16, 3, machine)
    struct.pack_into('<Q', data, 32, 64)
    struct.pack_into('<HH', data, 54, 56, 1)
    struct.pack_into('<I', data, 64, kind)
    return bytes(data)


class ElfControls(unittest.TestCase):
    def test_valid_headers_for_both_machines(self):
        for machine in (62, 183):
            with self.subTest(machine=machine):
                runner.inspect_elf(sample(machine), machine)

    def test_wrong_machine_is_refused(self):
        with self.assertRaises(RuntimeError):
            runner.inspect_elf(sample(62), 183)

    def test_interpreter_segment_is_refused(self):
        with self.assertRaises(RuntimeError):
            runner.inspect_elf(sample(183, 3), 183)

    def test_bad_header_is_refused(self):
        with self.assertRaises(RuntimeError):
            runner.inspect_elf(b'bad', 183)

    def test_truncated_program_table_is_refused(self):
        with self.assertRaises(RuntimeError):
            runner.inspect_elf(sample()[:-1], 183)


class ReceiptControls(unittest.TestCase):
    def test_publishes_complete_record(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            runner.publish_record(root, 'receipt.json', b'{"status":"ok"}\n')
            self.assertEqual((root / 'receipt.json').read_bytes(), b'{"status":"ok"}\n')
            self.assertFalse((root / 'receipt.json.pending').exists())

    def test_existing_record_is_not_replaced(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'receipt.json').write_bytes(b'existing')
            with self.assertRaises(FileExistsError):
                runner.publish_record(root, 'receipt.json', b'new')
            self.assertEqual((root / 'receipt.json').read_bytes(), b'existing')


if __name__ == '__main__':
    unittest.main()
