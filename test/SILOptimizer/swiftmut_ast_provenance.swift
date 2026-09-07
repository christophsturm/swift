// RUN: rm -rf %t
// RUN: split-file %s %t
// RUN: %{python} %t/check.py configure %t
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -parse-as-library -emit-sil -O %t/Subject.swift -module-name SwiftmutASTProvenance -o %t/output.sil
// RUN: %{python} %t/check.py verify %t

//--- Subject.swift
public func first(_ value: Int) -> Int {
  // } func second() { and += inside a comment are not compiler nodes.
  return value
}
public func second(_ value: Int) -> Int {
  return value
}

//--- check.py
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[2])
if sys.argv[1] == "configure":
    (root / "config.json").write_text(json.dumps({
        "mode": "metamutant",
        "manifestFragmentsDirectory": str(root / "fragments"),
        "compilerEventsPath": str(root / "events.jsonl"),
        "packageRoot": str(root),
        "sourceFiles": [str(root / "Subject.swift")],
        "enabledMutators": ["PRIMITIVE_RETURNS"],
        "returnMutationRules": ["integerToZero|PRIMITIVE_RETURNS|return_zero|return|return 0|0"],
    }))
else:
    events = [json.loads(line) for line in (root / "events.jsonl").read_text().splitlines()]
    functions = [event for event in events if event["event"] == "functionVisit"]
    first = next(event for event in functions if "5first" in event["function"])
    second = next(event for event in functions if "6second" in event["function"])
    assert first["astKind"] == second["astKind"] == "Func", (first, second)
    assert (first["astStartLine"], first["astEndLine"]) == ("1", "4"), first
    assert (second["astStartLine"], second["astEndLine"]) == ("5", "7"), second
    assert first["location"].endswith("Subject.swift:1:13"), first
    assert second["location"].endswith("Subject.swift:5:13"), second
    assert first["astEndColumn"] == second["astEndColumn"] == "2", (first, second)
    sites = [site for fragment in (root / "fragments").glob("*.json")
             for site in json.loads(fragment.read_text())["sites"]]
    returned = [site for site in sites if site["siteKind"] == "returnValue"]
    assert sorted(site["sourceLocation"]["line"] for site in returned) == [3, 6], returned
    assert all(site["alternatives"][0]["sourceOriginal"] == "value" for site in returned), returned
    assert all(site["alternatives"][0]["sourceMutated"] == "0" for site in returned), returned
