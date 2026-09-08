"""Render compiler ranges for readable FileCheck assertions in native tests.

This is test infrastructure only. Production report rendering lives in swiftmut;
the compiler publishes ranges and typed operations without reading source text.
Every condition or return assertion requires exact compiler ranges and a bounded edit.
"""

import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])


def offset(position, lines):
    line, column = position["line"] - 1, position["column"] - 1
    assert 0 <= line < len(lines), position
    assert 0 <= column <= len(lines[line]), position
    result = sum(map(len, lines[:line])) + column
    assert result == position["utf8Offset"], position
    return result


for record in sys.stdin:
    if not record.strip():
        continue
    fragment = json.loads(record)
    for site in fragment.get("sites", []):
        if site["siteKind"] not in ("condition", "returnValue", "returnBranchValue", "scalarValue", "assignmentValue"):
            continue
        source = (root / site["sourceLocation"]["file"]).read_bytes()
        lines = source.splitlines(keepends=True)
        span = site["sourceSpan"]
        start, end = offset(span["start"], lines), offset(span["end"], lines)
        assert start < end, site
        for alternative in site["alternatives"]:
            assert alternative["operation"], alternative
            edit = alternative["sourceEdit"]
            edit_start = offset(edit["span"]["start"], lines)
            edit_end = offset(edit["span"]["end"], lines)
            assert start <= edit_start <= edit_end <= end, alternative
            alternative["sourceOriginal"] = source[start:end].decode()
            alternative["sourceMutated"] = (source[start:edit_start].decode()
                                              + edit["replacement"] + source[edit_end:end].decode())
    print(json.dumps(fragment, separators=(",", ":"), ensure_ascii=False))
