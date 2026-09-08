// RUN: rm -rf %t && split-file %s %t
// RUN: %{python} %t/config.py %t
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -emit-sil -Onone -swift-version 6 -g -module-name Subject %t/Subject.swift -o /dev/null
// RUN: %{python} %t/check.py %t
// RUN: rm -rf %t/fragments
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -emit-sil -O -swift-version 6 -module-name Subject %t/Subject.swift -o /dev/null
// RUN: %{python} %t/check.py %t

//--- Subject.swift
@inline(never) public func amount(_ value: Int) -> Int { value + 1 }
public func repeated(_ text: String) -> Int {
  let first = amount(2)
  let second = amount(3)
  let count = text.count
  return first + second + count
}
public func logical(_ flag: Bool, _ text: String) -> Int {
  if flag && text.contains("x") { return 7 }
  return 8
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
    "enabledMutators": ["PRIMITIVE_RETURNS", "FALSE_RETURNS"],
    "conditionMutationRules": [], "arithmeticMutationRules": [], "contextualArithmeticMutationRules": [],
    "returnMutationRules": ["integerToZero|PRIMITIVE_RETURNS|return_zero|return|return 0|0",
                            "boolToFalse|FALSE_RETURNS|return_false|return|return false|false"],
    "voidCallMutationRules": [], "sourceMutationDisplayRules": []}
(root / "config.json").write_text(json.dumps(config))

//--- check.py
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
sites = [site for path in (root / "fragments").glob("*.json")
         for site in json.loads(path.read_text()).get("sites", []) if site["siteKind"] == "valueApply"]
source = (root / "Subject.swift").read_bytes()
observed = {}
for site in sites:
    span = site["sourceSpan"]
    start, end = span["start"], span["end"]
    text = source[start["utf8Offset"]:end["utf8Offset"]].decode()
    for alternative in site["alternatives"]:
        assert alternative["operation"] in ("replaceWithZero", "replaceWithFalse"), alternative
        assert alternative["sourceEdit"]["span"] == span, alternative
        observed[(start["line"], text)] = alternative["sourceEdit"]["replacement"]
assert observed == {(3, "amount(2)"): "0", (4, "amount(3)"): "0", (5, "text.count"): "0",
                    (9, 'text.contains("x")'): "false"}, observed
