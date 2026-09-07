// RUN: rm -rf %t && split-file %s %t
// RUN: %{python} %t/config.py %t
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -emit-sil -Onone -swift-version 6 -g -module-name Subject %t/Subject.swift -o /dev/null
// RUN: %{python} %t/check.py %t
// RUN: rm -rf %t/fragments
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -emit-sil -O -swift-version 6 -module-name Subject %t/Subject.swift -o /dev/null
// RUN: %{python} %t/check.py %t

//--- Subject.swift
public func nested(_ x: Int, _ y: Int, _ z: Int) -> Int {
  x + (y + z)
}
public func compound(_ value: inout Int, _ next: Int) {
  value += next
}
public func negate(_ value: Int) -> Int {
  -value
}

//--- config.py
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
config = {
    "mode": "metamutant", "packageRoot": str(root),
    "manifestPath": str(root / "mutants.jsonl"),
    "manifestFragmentsDirectory": str(root / "fragments"),
    "compilerEventsPath": str(root / "events.jsonl"),
    "sourceFiles": [str(root / "Subject.swift")], "excludePaths": [],
    "enabledMutators": ["MATH", "INVERT_NEGS"],
    "conditionMutationRules": [], "arithmeticMutationRules": [],
    "contextualArithmeticMutationRules": [
        "SAddOver|otherwise|MATH|ssub_with_overflow|+|-",
        "SSubOver|unaryNegation|INVERT_NEGS|sadd_with_overflow|-|+"],
    "returnMutationRules": [], "voidCallMutationRules": [],
    "sourceMutationDisplayRules": []}
(root / "config.json").write_text(json.dumps(config))

//--- check.py
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
sites = [site for path in (root / "fragments").glob("*.json")
         for site in json.loads(path.read_text()).get("sites", []) if site["siteKind"] == "arithmetic"]
assert len(sites) == 4, sites
observed = set()
for site in sites:
    span = site["sourceSpan"]
    for alt in site["alternatives"]:
        edit = alt["sourceEdit"]
        observed.add((span["start"]["line"], span["start"]["column"], span["end"]["column"],
                      edit["span"]["start"]["column"], edit["span"]["end"]["column"],
                      alt["operation"], edit["replacement"]))
assert observed == {(2, 3, 14, 5, 6, "subtract", "-"),
                    (2, 8, 13, 10, 11, "subtract", "-"),
                    (5, 3, 16, 9, 11, "subtract", "-="),
                    (8, 3, 9, 3, 4, "removeNegation", "")}, observed
