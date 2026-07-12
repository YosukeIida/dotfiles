import unittest

from users import create_user, display_name, update_email


class TestUsers(unittest.TestCase):
    def test_create_normalizes(self):
        u = create_user("Yosuke", "  Yosuke@Example.COM ")
        self.assertEqual(u["email"], "yosuke@example.com")

    def test_create_invalid_no_at(self):
        with self.assertRaises(ValueError):
            create_user("x", "not-an-email")

    def test_create_invalid_no_dot_domain(self):
        with self.assertRaises(ValueError):
            create_user("x", "a@localhost")

    def test_update_normalizes(self):
        u = create_user("Yosuke", "a@b.com")
        u2 = update_email(u, " NEW@Example.Org ")
        self.assertEqual(u2["email"], "new@example.org")
        self.assertEqual(u["email"], "a@b.com")

    def test_update_invalid(self):
        u = create_user("Yosuke", "a@b.com")
        with self.assertRaises(ValueError):
            update_email(u, "bad")

    def test_display(self):
        u = create_user("Yosuke", "a@b.com")
        self.assertEqual(display_name(u), "Yosuke <a@b.com>")


if __name__ == "__main__":
    unittest.main()
