# SPDX-License-Identifier: AGPL-3.0-or-later
"""The restricted YAML loader."""

import unittest

from solver.yamlsub import YamlSubsetError, loads

DOC = """\
# comment
schema_version: 1
name: Cookie Machine   # trailing comment
quoted: "a: b # not a comment"
single: 'it''s ok'
flag: true
nothing: null
negative: -1
nested:
  inner: value
list:
  - id: a
    n: 1
  - id: b
    n: 2
scalars:
  - one
  - "two"
same_indent:
- x
- y
after: end
"""


class YamlSubsetTests(unittest.TestCase):
    def test_parses_document(self):
        self.assertEqual(
            loads(DOC),
            {
                "schema_version": 1,
                "name": "Cookie Machine",
                "quoted": "a: b # not a comment",
                "single": "it's ok",
                "flag": True,
                "nothing": None,
                "negative": -1,
                "nested": {"inner": "value"},
                "list": [{"id": "a", "n": 1}, {"id": "b", "n": 2}],
                "scalars": ["one", "two"],
                "same_indent": ["x", "y"],
                "after": "end",
            },
        )

    def test_escapes(self):
        self.assertEqual(loads('k: "say \\"hi\\""'), {"k": 'say "hi"'})

    def test_rejects_unsupported(self):
        for bad in (
            "k: [1, 2]",
            "k: {a: 1}",
            "k: |\n  text",
            "k: &a 1",
            "k: a: b",
            "k: 1\nk: 2",
            "k:\n\t- 1",
            'k: "open',
            "a: 1\n  b: 2",
        ):
            with self.assertRaises(YamlSubsetError, msg=bad):
                loads(bad)


if __name__ == "__main__":
    unittest.main()
