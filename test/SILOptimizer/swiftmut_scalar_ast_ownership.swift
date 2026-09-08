// RUN: rm -rf %t && split-file %s %t
// RUN: %{python} %t/config.py %t
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -emit-sil -Onone -swift-version 6 -g -module-name Subject %t/Subject.swift -o /dev/null
// RUN: %{python} %t/check.py %t
// RUN: rm -rf %t/fragments
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -emit-sil -O -swift-version 6 -module-name Subject %t/Subject.swift -o /dev/null
// RUN: %{python} %t/check.py %t

//--- Subject.swift
@inline(never) public func sink(_ first: Int, _ second: Int) {}
public func literals() { sink(0x1, 0x0) }
public func computed(_ count: Int) -> Bool { count == 0 }
public func bindings(_ flag: Bool) -> Int {
  var first = 0
  var second = 0
  if flag { first = 1; second = 1 }
  return first + second
}
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
    "sourceFiles": [str(root / "Subject.swift")], "excludePaths": [],
    "enabledMutators": ["FALSE_RETURNS", "TRUE_RETURNS", "PRIMITIVE_RETURNS"],
    "conditionMutationRules": [], "arithmeticMutationRules": [], "contextualArithmeticMutationRules": [],
    "returnMutationRules": [
        "boolToFalse|FALSE_RETURNS|return_false|return|return false|false",
        "boolToTrue|TRUE_RETURNS|return_true|return|return true|true",
        "integerToZero|PRIMITIVE_RETURNS|return_zero|return|return 0|0",
        "integerToOne|PRIMITIVE_RETURNS|return_one|return|return 1|1"],
    "voidCallMutationRules": [], "sourceMutationDisplayRules": []}
(root / "config.json").write_text(json.dumps(config))

//--- check.py
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
sites = [site for path in (root / "fragments").glob("*.json")
         for site in json.loads(path.read_text()).get("sites", []) if site["siteKind"] == "scalarValue"]
source = (root / "Subject.swift").read_bytes()
observed = {}
for site in sites:
    span = site["sourceSpan"]
    start, end = span["start"], span["end"]
    text = source[start["utf8Offset"]:end["utf8Offset"]].decode()
    key = (start["line"], start["column"], text)
    assert key not in observed, (key, sites)
    observed[key] = {a["operation"] for a in site["alternatives"]}
    for alternative in site["alternatives"]:
        assert alternative["sourceEdit"]["span"] == span, alternative
assert observed == {
    (2, 31, "0x1"): {"replaceWithZero"},
    (2, 36, "0x0"): {"replaceWithOne"},
    (3, 46, "count == 0"): {"replaceWithFalse", "replaceWithTrue"},
    (3, 55, "0"): {"replaceWithOne"},
    (5, 15, "0"): {"replaceWithOne"},
    (6, 16, "0"): {"replaceWithOne"},
    (7, 21, "1"): {"replaceWithZero"},
    (7, 33, "1"): {"replaceWithZero"},
    (8, 10, "first + second"): {"replaceWithZero"}}, observed
