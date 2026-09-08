// RUN: rm -rf %t && split-file %s %t
// RUN: %{python} %t/config.py %t
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -emit-sil -Onone -swift-version 6 -g -module-name Subject %t/Subject.swift -o /dev/null
// RUN: %{python} %t/check.py %t
// RUN: rm -rf %t/fragments
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -emit-sil -O -swift-version 6 -module-name Subject %t/Subject.swift -o /dev/null
// RUN: %{python} %t/check.py %t

//--- Subject.swift
public func comma(_ left: Bool, _ right: Bool) -> Int {
  guard left, right else { return 0 }
  return 1
}
public func ternary(_ flag: Bool) -> Int {
  flag ? 1 : 0
}
public func comparison(_ value: Int, _ limit: Int) -> Int {
  if value >= limit { return 1 }
  return 0
}
public func negation(_ flag: Bool) -> Int {
  if !flag { return 1 }
  return 0
}
public func filtered(_ values: [Int], _ limit: Int) -> Int {
  var total = 0
  for value in values where value >= limit { total += value }
  return total
}
public enum Mode { case amount(Int), disabled }
public func matched(_ mode: Mode, _ limit: Int) -> Int {
  switch mode {
  case .amount(let value) where value >= limit: return value
  default: return 0
  }
}
public func parenthesized(_ value: Int, _ limit: Int) -> Int {
  if (value >= limit) { return 1 }
  return 0
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
    "enabledMutators": ["CONDITION_TRUE", "CONDITION_FALSE", "CONDITIONALS_BOUNDARY", "NEGATE_CONDITIONALS"],
    "conditionMutationRules": [
        "COMPARISON|CONDITION_FALSE|condition_false|condition|false",
        "COMPARISON|CONDITION_TRUE|condition_true|condition|true",
        "ICMP_SGE|CONDITIONALS_BOUNDARY|cmp_sgt|>=|>",
        "ICMP_SGE|NEGATE_CONDITIONALS|cmp_slt|>=|<",
        "ICMP_EQ|NEGATE_CONDITIONALS|cmp_ne|==|!="],
    "arithmeticMutationRules": [], "contextualArithmeticMutationRules": [],
    "returnMutationRules": [], "voidCallMutationRules": [], "sourceMutationDisplayRules": []}
(root / "config.json").write_text(json.dumps(config))

//--- check.py
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
sites = [site for path in (root / "fragments").glob("*.json")
         for site in json.loads(path.read_text()).get("sites", []) if site["siteKind"] == "condition"]
assert len(sites) == 8, sites
observed = set()
for site in sites:
    span = site["sourceSpan"]
    start, end = span["start"], span["end"]
    observed.add((start["line"], start["column"], end["column"]))
    assert {"replaceWithFalse", "replaceWithTrue"} <= {a["operation"] for a in site["alternatives"]}, site
    if start["line"] in (9, 18, 24, 29):
        assert {"greaterThan", "lessThan"} <= {a["operation"] for a in site["alternatives"]}, site
    for alt in site["alternatives"]:
        edit = alt["sourceEdit"]
        if alt["operation"] in ("replaceWithFalse", "replaceWithTrue"):
            assert edit["span"] == span, alt
        assert start["utf8Offset"] <= edit["span"]["start"]["utf8Offset"] < edit["span"]["end"]["utf8Offset"] <= end["utf8Offset"], alt
assert observed == {(2, 9, 13), (2, 15, 20), (6, 3, 7), (9, 6, 20),
                    (13, 6, 11), (18, 29, 43), (24, 33, 47), (29, 6, 22)}, observed
