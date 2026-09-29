"""Protect the reference comparison gate from accepting corrupt backend results."""
from decimal import Decimal
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from check_compat import compare, load_results


class ConformanceGateTests(unittest.TestCase):
    def test_boolean_is_not_a_number(self):
        self.assertFalse(compare({'a': True}, {'a': Decimal(1)})['matches'])

    def test_null_is_not_missing_and_missing_cases_fail(self):
        self.assertFalse(compare({'a': {'x': None}}, {'a': {}})['matches'])
        self.assertFalse(compare({'a': None}, {})['matches'])

    def test_exact_numbers_preserve_small_differences(self):
        self.assertFalse(compare({'a': Decimal('1.0000000000000001')},
                                 {'a': Decimal('1.0000000000000002')})['matches'])
        self.assertTrue(compare({'a': Decimal('1.0')}, {'a': Decimal('1')})['matches'])

    def test_array_order_and_escaped_nested_path(self):
        report = compare({'a': {'x/y~': [1, 2]}}, {'a': {'x/y~': [2, 1]}})
        self.assertEqual(report['differences'], [{'case': 'a', 'path': '/x~1y~0/0'}])

    def test_case_and_object_order_do_not_matter(self):
        self.assertTrue(compare({'b': 3, 'a': {'x': 1, 'y': 2}},
                                {'a': {'y': 2, 'x': 1}, 'b': 3})['matches'])

    def test_invalid_transcripts_are_rejected(self):
        invalid = [
            '{"suite":"wrong","cases":[{"id":"a","value":1}]}',
            '{"suite":"jsonlogic-2.0.5","cases":[]}',
            '{"suite":"jsonlogic-2.0.5","cases":[{"id":"a"}]}',
            '{"suite":"jsonlogic-2.0.5","cases":[{"id":"a","value":NaN}]}',
            '{"suite":"jsonlogic-2.0.5","cases":[{"id":"a","value":1,"value":2}]}',
            json.dumps({'suite': 'jsonlogic-2.0.5', 'cases': [
                {'id': 'a', 'value': 1}, {'id': 'a', 'value': 2}]}),
        ]
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'results.json'
            for text in invalid:
                with self.subTest(text=text):
                    path.write_text(text)
                    with self.assertRaises(ValueError):
                        load_results(path)


if __name__ == '__main__':
    unittest.main()
