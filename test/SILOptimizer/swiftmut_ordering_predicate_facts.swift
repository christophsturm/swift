// RUN: rm -rf %t && split-file %s %t
// RUN: %{python} %t/config.py %t
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -emit-sil -Onone -swift-version 6 -module-name Subject -primary-file %t/Predicates.swift %t/Uses.swift -o /dev/null
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -emit-sil -Onone -swift-version 6 -module-name Subject %t/Predicates.swift -primary-file %t/Uses.swift -o /dev/null
// RUN: %{python} %t/check.py %t

//--- Predicates.swift
public func compare(_ left: String, _ right: String) -> Bool { left < right }
public struct Other {
  public static func compare(_ left: String, _ right: String) -> Bool { left == right }
}

//--- Uses.swift
public func usesNamed(_ values: [String]) -> [String] { values.sorted(by: compare) }
public func usesClosure(_ values: [String]) -> [String] {
  values.sorted { left, right in left < right }
}
public func usesOther(_ values: [String]) -> [String] {
  values.filter { Other.compare($0, "sample") }
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
    "sourceFiles": [str(root / "Predicates.swift"), str(root / "Uses.swift")], "excludePaths": [],
    "enabledMutators": ["FALSE_RETURNS"],
    "conditionMutationRules": [], "arithmeticMutationRules": [], "contextualArithmeticMutationRules": [],
    "returnMutationRules": ["boolToFalse|FALSE_RETURNS|return_false|return|return false|false"],
    "voidCallMutationRules": [], "sourceMutationDisplayRules": []}
(root / "config.json").write_text(json.dumps(config))

//--- check.py
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
functions = {name for path in (root / "fragments").glob("*.json")
             for name in json.loads(path.read_text()).get("orderingPredicateFunctions", [])}
assert any(name.startswith("$s7Subject7compare") for name in functions), functions
assert any("usesClosure" in name for name in functions), functions
assert not any("Other" in name or "usesOther" in name for name in functions), functions
