// REQUIRES: executable_test
// RUN: rm -rf %t && split-file %s %t
// RUN: %{python} %t/config.py %t
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-build-swift -Onone -swift-version 6 %t/Subject.swift %t/main.swift -module-name Subject -o %t/a.out
// RUN: %target-codesign %t/a.out
// RUN: %{python} %t/check.py %t
// RUN: rm -rf %t/fragments
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-build-swift -O -swift-version 6 %t/Subject.swift %t/main.swift -module-name Subject -o %t/a.out
// RUN: %target-codesign %t/a.out
// RUN: %{python} %t/check.py %t

//--- Subject.swift
@inline(never)
public func comma(_ left: Bool, _ right: Bool) -> Int {
  guard left, right else { return 0 }
  return 1
}
@inline(never)
public func compared(_ value: Int, _ limit: Int) -> Int {
  if value >= limit { return 1 }
  return 0
}
@inline(never)
public func comparedStrings(_ left: String, _ right: String) -> Int {
  if left == right { return 1 }
  return 0
}

//--- main.swift
import Foundation

@_silgen_name("__swiftmut_visit")
public func __swiftmut_visit(_ siteID: UInt64) -> UInt32 {
  let environment = ProcessInfo.processInfo.environment
  guard let selected = environment["SWIFTMUT_TEST_SITE"], UInt64(selected) == siteID,
        let alternative = environment["SWIFTMUT_TEST_ALTERNATIVE"] else { return 0 }
  return UInt32(alternative) ?? 0
}

print(comma(false, true), comma(true, false), compared(2, 2), comparedStrings("same", "same"))

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
        "ICMP_EQ|NEGATE_CONDITIONALS|cmp_ne|==|!="],
    "arithmeticMutationRules": [], "contextualArithmeticMutationRules": [],
    "returnMutationRules": [], "voidCallMutationRules": [], "sourceMutationDisplayRules": []}
(root / "config.json").write_text(json.dumps(config))

//--- check.py
import json, os, pathlib, subprocess, sys
root = pathlib.Path(sys.argv[1])
sites = [site for path in (root / "fragments").glob("*.json")
         for site in json.loads(path.read_text()).get("sites", []) if site["siteKind"] == "condition"]
assert len(sites) == 4, sites
assert subprocess.check_output([str(root / "a.out")], text=True).strip() == "0 0 1 1"
for line, column, operation, expected in [(3, 9, "replaceWithTrue", "1 0 1 1"),
                                          (3, 15, "replaceWithTrue", "0 1 1 1"),
                                          (8, 6, "greaterThan", "0 0 0 1"),
                                          (13, 6, "replaceWithFalse", "0 0 1 0"),
                                          (13, 6, "notEqual", "0 0 1 0")]:
    site = next(s for s in sites if (s["sourceSpan"]["start"]["line"], s["sourceSpan"]["start"]["column"]) == (line, column))
    alternative = next(a for a in site["alternatives"] if a["operation"] == operation)
    environment = dict(os.environ, SWIFTMUT_TEST_SITE=str(site["siteID"]),
                       SWIFTMUT_TEST_ALTERNATIVE=str(alternative["alternativeIndex"]))
    actual = subprocess.check_output([str(root / "a.out")], env=environment, text=True).strip()
    assert actual == expected, (line, column, operation, actual, expected)
