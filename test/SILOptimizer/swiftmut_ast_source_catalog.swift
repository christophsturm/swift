// RUN: rm -rf %t && split-file %s %t
// RUN: %{python} %t/config.py %t
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -emit-sil -Onone -swift-version 6 -module-name Subject -primary-file %t/Subject.swift %t/Empty.swift %t/Runtime.swift -o /dev/null
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -emit-sil -Onone -swift-version 6 -module-name Subject %t/Subject.swift -primary-file %t/Empty.swift %t/Runtime.swift -o /dev/null
// RUN: %{python} %t/check.py %t
// RUN: rm -rf %t/fragments
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -emit-sil -O -swift-version 6 -module-name Subject -primary-file %t/Subject.swift %t/Empty.swift %t/Runtime.swift -o /dev/null
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -emit-sil -O -swift-version 6 -module-name Subject %t/Subject.swift -primary-file %t/Empty.swift %t/Runtime.swift -o /dev/null
// RUN: %{python} %t/check.py %t

//--- Subject.swift
public func gate(_ ready: Bool, _ allowed: Bool) -> Int {
  if ready && allowed { return 7 }
  return 0
}
public func amount(_ input: Int) -> Int { input + 3 }
public func text(_ input: String) -> String { input + "value" }

//--- Empty.swift
// A primary input with no declarations still has catalog evidence.

//--- Runtime.swift
@_silgen_name("__swiftmut_visit")
public func __swiftmut_visit(_ siteID: UInt64) -> UInt32 { 0 }

//--- config.py
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
config = {
    "mode": "metamutant", "packageRoot": str(root),
    "manifestPath": str(root / "mutants.jsonl"),
    "manifestFragmentsDirectory": str(root / "fragments"),
    "compilerEventsPath": str(root / "events.jsonl"),
    "sourceFiles": [str(root / "Subject.swift"), str(root / "Empty.swift")], "excludePaths": [],
    "enabledMutators": ["CONDITION_TRUE", "CONDITION_FALSE", "CHANGE_LOGICAL_CONNECTOR", "MATH", "PRIMITIVE_RETURNS"],
    "conditionMutationRules": ["COMPARISON|CONDITION_TRUE|condition_true|condition|true", "COMPARISON|CONDITION_FALSE|condition_false|condition|false"],
    "arithmeticMutationRules": ["Add|sub|+|-"], "contextualArithmeticMutationRules": [],
    "returnMutationRules": ["integerToZero|PRIMITIVE_RETURNS|return_zero|return|return 0|0", "integerToOne|PRIMITIVE_RETURNS|return_one|return|return 1|1"],
    "voidCallMutationRules": [], "sourceMutationDisplayRules": []}
(root / "config.json").write_text(json.dumps(config))

//--- check.py
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
fragments = [json.loads(path.read_text()) for path in (root / "fragments").glob("*.json")]
inventories = [fragment["sourceMutationInventory"] for fragment in fragments if "statementInventory" in fragment]
assert {file for inventory in inventories for file in inventory["files"]} == {"Subject.swift", "Empty.swift"}, inventories
candidates = [candidate for inventory in inventories for candidate in inventory["candidates"]]
assert len(candidates) == 8, candidates
source = (root / "Subject.swift").read_bytes()
def spelling(site, key="span"):
    span = site[key]
    return source[span["start"]["utf8Offset"]:span["end"]["utf8Offset"]].decode()
actual = {(candidate["site"]["siteKind"], spelling(candidate["site"]), candidate["behavior"]["operation"]) for candidate in candidates}
assert actual == {
    ("condition", "ready", "replaceWithFalse"), ("condition", "ready", "replaceWithTrue"),
    ("condition", "allowed", "replaceWithFalse"), ("condition", "allowed", "replaceWithTrue"),
    ("logicalConnector", "ready && allowed", "logicalOr"), ("arithmetic", "input + 3", "subtract"),
    ("scalarValue", "7", "replaceWithZero"), ("scalarValue", "0", "replaceWithOne")}, actual
for candidate in candidates:
    edit = candidate["sourceEdit"]
    kind = candidate["site"]["siteKind"]
    if kind == "logicalConnector":
        assert spelling(edit) == "&&" and edit["replacement"] == "||", edit
    elif kind == "arithmetic":
        assert spelling(edit) == "+" and edit["replacement"] == "-", edit
    else:
        assert edit["span"] == candidate["site"]["span"], edit
sites = [site for fragment in fragments for site in fragment["sites"]]
assert not any(site["siteKind"] == "condition" and alternative.get("operation") in {"replaceWithTrue", "replaceWithFalse"}
               for site in sites for alternative in site["alternatives"]), sites
