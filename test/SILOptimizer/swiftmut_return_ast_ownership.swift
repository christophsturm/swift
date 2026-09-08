// RUN: rm -rf %t && split-file %s %t
// RUN: %{python} %t/config.py %t
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -emit-sil -Onone -swift-version 6 -g -module-name Subject %t/Subject.swift -o /dev/null
// RUN: %{python} %t/check.py %t
// RUN: rm -rf %t/fragments
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -emit-sil -O -swift-version 6 -module-name Subject %t/Subject.swift -o /dev/null
// RUN: %{python} %t/check.py %t

//--- Subject.swift
public func explicit(_ flag: Bool) -> Bool {
  return flag
}
public func implicit(_ flag: Bool) -> Bool {
  flag
}
public func branches(_ flag: Bool, _ left: String, _ right: String) -> String {
  if flag { return left }; return right
}
public func constantFalse() -> Bool { false }
public func constantZero() -> Int { 0x0 }
public func rawString() -> String { #"café"# }
public func interpolated(_ value: Int) -> String { "value: \(value)" }
public func negativeOne() -> Int { -1 }
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
    "enabledMutators": ["FALSE_RETURNS", "TRUE_RETURNS", "PRIMITIVE_RETURNS", "EMPTY_RETURNS"],
    "conditionMutationRules": [], "arithmeticMutationRules": [], "contextualArithmeticMutationRules": [],
    "returnMutationRules": [
        "boolToFalse|FALSE_RETURNS|return_false|return|return false|false",
        "boolToTrue|TRUE_RETURNS|return_true|return|return true|true",
        "integerToZero|PRIMITIVE_RETURNS|return_zero|return|return 0|0",
        "integerToOne|PRIMITIVE_RETURNS|return_one|return|return 1|1",
        'stringToEmpty|EMPTY_RETURNS|return_empty_string|return|return ""|""'],
    "voidCallMutationRules": [], "sourceMutationDisplayRules": []}
(root / "config.json").write_text(json.dumps(config))

//--- check.py
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
sites = [site for path in (root / "fragments").glob("*.json")
         for site in json.loads(path.read_text()).get("sites", [])
         if site["siteKind"] in ("returnValue", "returnBranchValue")]
observed = {}
string_ranges = {}
negative_sites = 0
source = (root / "Subject.swift").read_bytes()
for site in sites:
    span = site["sourceSpan"]
    start, end = span["start"], span["end"]
    key = (start["line"], start["column"], end["column"])
    if start["line"] == 14:
        negative_sites += 1
        assert source[start["utf8Offset"]:end["utf8Offset"]] == b"-1", site
        # Existing rule policy replaces only zero with one; other integers
        # receive the zero alternative, regardless of their source spelling.
        assert {a["operation"] for a in site["alternatives"]} == {"replaceWithZero"}, site
        continue
    if start["line"] in (12, 13):
        string_ranges[start["line"]] = source[start["utf8Offset"]:end["utf8Offset"]].decode()
        assert {a["operation"] for a in site["alternatives"]} == {"replaceWithEmptyString"}, site
        continue
    assert key not in observed, (key, sites)
    observed[key] = {a["operation"] for a in site["alternatives"]}
    for alternative in site["alternatives"]:
        assert alternative["sourceEdit"]["span"] == span, alternative
        assert alternative["sourceOriginal"] == "return", alternative
assert observed == {
    (2, 10, 14): {"replaceWithFalse", "replaceWithTrue"},
    (5, 3, 7): {"replaceWithFalse", "replaceWithTrue"},
    (8, 20, 24): {"replaceWithEmptyString"},
    (8, 35, 40): {"replaceWithEmptyString"},
    (10, 39, 44): {"replaceWithTrue"},
    (11, 37, 40): {"replaceWithOne"}}, observed
assert string_ranges == {12: '#"café"#', 13: '"value: \\(value)"'}, string_ranges
assert negative_sites == 1, sites
