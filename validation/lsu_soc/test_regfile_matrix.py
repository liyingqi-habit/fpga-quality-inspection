"""Small generator/oracle tests; not a replacement for CPU simulation."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from regfile_matrix import generate


class MatrixTests(unittest.TestCase):
    def test_default_cross_product(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)
            generate(out)
            cases = json.loads((out / 'cases.json').read_text())
            self.assertEqual(len(cases), 432)
            self.assertEqual(len({(c['context'], c['register'], c['nop_gap'], c['role']) for c in cases}), 432)
            for c in cases:
                if c['register'] == 0:
                    self.assertEqual(c['expected'], {'rs1': 3, 'rs2': 9, 'both': 0}[c['role']])
            # Hand calculated: case18 value=-587; rs1 adds3.
            self.assertEqual(cases[18]['expected'], (-584) & 0xffffffff)
            self.assertIn('`define MATRIX_DIVIDES 144', (out / 'matrix_config.vh').read_text())

    def test_combined_context(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)
            generate(out, (0, 27), (0, 5), ('divide_flush',))
            asm = (out / 'matrix.S').read_text()
            self.assertEqual(asm.count('div x30,x31,x31'), 12)
            self.assertEqual(asm.count('beq x31,x31,'), 12)
            self.assertEqual((out / 'matrix_context.hex').read_text().splitlines(), ['3'] * 12)

    def test_reserved_register_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            result = subprocess.run([sys.executable, str(Path(__file__).with_name('regfile_matrix.py')),
                                     tmp, '--registers', '28'], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('reserved', result.stderr)

    def test_oversized_result_region_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaisesRegex(ValueError, '512'):
                generate(Path(tmp), range(28), range(6))


if __name__ == '__main__':
    unittest.main()
