import unittest

from slugify import slugify


class TestSlugify(unittest.TestCase):
    def test_basic(self):
        self.assertEqual(slugify("Hello World"), "hello-world")

    def test_extra_whitespace(self):
        self.assertEqual(slugify("  Hello,   World!  "), "hello-world")

    def test_already_slug(self):
        self.assertEqual(slugify("already-slugged"), "already-slugged")

    def test_non_ascii_removed(self):
        self.assertEqual(slugify("日本語123 abc"), "123-abc")

    def test_symbols(self):
        self.assertEqual(slugify("C++ & Rust: A Comparison"), "c-rust-a-comparison")

    def test_empty(self):
        self.assertEqual(slugify(""), "")

    def test_only_symbols(self):
        self.assertEqual(slugify("!!!"), "")


if __name__ == "__main__":
    unittest.main()
