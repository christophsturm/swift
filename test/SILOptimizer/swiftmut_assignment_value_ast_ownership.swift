// RUN: rm -rf %t && split-file %s %t
// RUN: %{python} %t/config.py %t
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -emit-sil -Onone -swift-version 6 -g -module-name Subject %t/Subject.swift -o /dev/null
// RUN: %{python} %t/check.py %t
// RUN: rm -rf %t/fragments
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -emit-sil -O -swift-version 6 -module-name Subject %t/Subject.swift -o /dev/null
// RUN: %{python} %t/check.py %t

//--- Subject.swift
public func bindings(_ input: Int) -> Int {
  var first = input
  var second: Int = input
  return first + second
}
public func accumulate(_ input: Int) -> Int {
  var total = 0
  total += input
  return total
}
public struct Box {
  public let stored: Int
  public init(_ input: Int) { stored = input }
}
public func literalInitializers(_ suffix: String) -> (String, [String]) {
  var text = "prefix"
  var texts = ["prefix"]
  text += suffix
  texts.append(suffix)
  return (text, texts)
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
    "enabledMutators": ["PRIMITIVE_RETURNS", "EMPTY_RETURNS"],
    "conditionMutationRules": [], "arithmeticMutationRules": [], "contextualArithmeticMutationRules": [],
    "returnMutationRules": ["integerToZero|PRIMITIVE_RETURNS|return_zero|return|return 0|0",
                            'stringToEmpty|EMPTY_RETURNS|return_empty_string|return|return ""|""',
                            "arrayToEmpty|EMPTY_RETURNS|return_empty_array|return|return []|[]"],
    "voidCallMutationRules": [], "sourceMutationDisplayRules": []}
(root / "config.json").write_text(json.dumps(config))

//--- check.py
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
sites = [site for path in (root / "fragments").glob("*.json")
         for site in json.loads(path.read_text()).get("sites", []) if site["siteKind"] == "assignmentValue"]
source = (root / "Subject.swift").read_bytes()
observed = {}
for site in sites:
    span = site["sourceSpan"]
    start, end = span["start"], span["end"]
    text = source[start["utf8Offset"]:end["utf8Offset"]].decode()
    for alternative in site["alternatives"]:
        assert alternative["operation"] in ("replaceWithZero", "replaceWithEmptyString", "replaceWithEmptyArray"), alternative
        edit = alternative["sourceEdit"]
        left, right = edit["span"]["start"]["utf8Offset"], edit["span"]["end"]["utf8Offset"]
        assert start["utf8Offset"] <= left <= right <= end["utf8Offset"], edit
        replacement = source[start["utf8Offset"]:left].decode() + edit["replacement"] + source[right:end["utf8Offset"]].decode()
        observed[(start["line"], text)] = replacement
assert observed == {(2, "input"): "0", (3, "input"): "0", (8, "total += input"): "total = 0",
                    (13, "input"): "0", (16, '"prefix"'): '""', (17, '["prefix"]'): "[]"}, observed
