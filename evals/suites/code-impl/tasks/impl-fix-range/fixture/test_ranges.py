import unittest

from ranges import parse_range


class TestParseRange(unittest.TestCase):
    def test_single(self):
        self.assertEqual(parse_range("5"), [5])

    def test_range_inclusive(self):
        self.assertEqual(parse_range("1-3"), [1, 2, 3])

    def test_mixed(self):
        self.assertEqual(parse_range("1-3,5,7-9"), [1, 2, 3, 5, 7, 8, 9])

    def test_single_element_range(self):
        self.assertEqual(parse_range("4-4"), [4])

    def test_spaces(self):
        self.assertEqual(parse_range(" 1-2 , 4 "), [1, 2, 4])


if __name__ == "__main__":
    unittest.main()
