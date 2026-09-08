import json
import pathlib
import sys

sites = [site for line in pathlib.Path(sys.argv[1]).read_text().splitlines() if line.strip()
         for site in json.loads(line).get("sites", []) if site["siteKind"] == "logicalConnector"]
expected = [tuple(position) for position in json.loads(sys.argv[2])]
observed = []
for site in sites:
    owner = site["sourceSpan"]
    alternative, = site["alternatives"]
    edit = alternative["sourceEdit"]
    span = edit["span"]
    assert owner["start"]["utf8Offset"] <= span["start"]["utf8Offset"] < span["end"]["utf8Offset"] <= owner["end"]["utf8Offset"]
    assert span["end"]["utf8Offset"] - span["start"]["utf8Offset"] == 2
    assert (alternative["operation"], edit["replacement"]) in [("logicalAnd", "&&"), ("logicalOr", "||")]
    observed.append((span["start"]["line"], span["start"]["column"]))
assert sorted(observed) == sorted(expected), (observed, expected)
assert len({site["siteID"] for site in sites}) == len(sites)
