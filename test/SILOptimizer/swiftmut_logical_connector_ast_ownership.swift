// RUN: rm -rf %t && split-file %s %t
// RUN: %{python} %t/config.py %t
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -emit-sil -Onone -module-name Subject %t/Subject.swift -o /dev/null
// RUN: %{python} %t/check.py %t
// RUN: rm -rf %t/fragments
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -emit-sil -O -module-name Subject %t/Subject.swift -o /dev/null
// RUN: %{python} %t/check.py %t

//--- Subject.swift
public func mixed(_ a: Bool, _ b: Bool, _ c: Bool) -> Bool {
  a && b || c
}
public func nested(_ a: Bool, _ b: Bool, _ c: Bool) -> Bool {
  a || (b && c)
}
@_silgen_name("__swiftmut_visit")
public func __swiftmut_visit(_ siteID: UInt64) -> UInt32 { 0 }

//--- config.py
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
(root / "config.json").write_text(json.dumps({
    "mode": "metamutant", "packageRoot": str(root), "sourceFiles": [str(root / "Subject.swift")],
    "manifestPath": str(root / "manifest.jsonl"), "manifestFragmentsDirectory": str(root / "fragments"),
    "compilerEventsPath": str(root / "events.jsonl"),
    "excludePaths": [], "enabledMutators": ["CHANGE_LOGICAL_CONNECTOR"],
    "conditionMutationRules": [], "arithmeticMutationRules": [], "contextualArithmeticMutationRules": [],
    "returnMutationRules": [], "voidCallMutationRules": [], "sourceMutationDisplayRules": []}))

//--- check.py
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
sites = [s for path in (root / "fragments").glob("*.json")
         for s in json.loads(path.read_text()).get("sites", []) if s["siteKind"] == "logicalConnector"]
assert len(sites) == 2, sites
observed = set()
for site in sites:
    span = site["sourceSpan"]
    alternative, = site["alternatives"]
    edit = alternative["sourceEdit"]
    observed.add((span["start"]["line"], span["start"]["column"], span["end"]["column"],
                  edit["span"]["start"]["column"], edit["span"]["end"]["column"],
                  alternative["operation"], edit["replacement"]))
assert observed == {(2, 3, 9, 5, 7, "logicalOr", "||"), (2, 3, 14, 10, 12, "logicalAnd", "&&")}, observed
# The right-hand nested expression has only a partial supported CFG shape.
# Mandatory inlining retains its outer || location for the inner && branch;
# that mismatch cannot establish ownership of either operator.
events = [json.loads(line) for line in (root / "events.jsonl").read_text().splitlines()]
nested = [event for event in events if event["event"] == "metamutantDiscovery" and "6nested" in event["function"]]
assert nested and all(e["logicalConnectorSites"] == "0" and e["logicalConnectorSourceLocationMisses"] == "1" for e in nested), nested
