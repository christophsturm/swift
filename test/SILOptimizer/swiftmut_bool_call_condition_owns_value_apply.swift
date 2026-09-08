// REQUIRES: executable_test
// RUN: rm -rf %t
// RUN: split-file %s %t
// swiftmut runs in the native Diagnostic pipeline.
// RUN: printf '%b\n' \
// RUN:   '{' \
// RUN:   '  "mode": "metamutant",' \
// RUN:   '  "manifestPath": "%t/mutants.jsonl",' \
// RUN:   '  "manifestFragmentsDirectory": "%t/fragments",' \
// RUN:   '  "compilerEventsPath": "%t/compiler-events.jsonl",' \
// RUN:   '  "packageRoot": "%t",' \
// RUN:   '  "excludePaths": [],' \
// RUN:   '  "sourceFiles": ["%t/main.swift"],' \
// RUN:   '  "enabledMutators": ["CONDITION_FALSE", "CONDITION_TRUE", "FALSE_RETURNS", "TRUE_RETURNS"],' \
// RUN:   '  "conditionMutationRules": [' \
// RUN:   '    "COMPARISON|CONDITION_FALSE|condition_false|condition|false",' \
// RUN:   '    "COMPARISON|CONDITION_TRUE|condition_true|condition|true"' \
// RUN:   '  ],' \
// RUN:   '  "arithmeticMutationRules": [],' \
// RUN:   '  "contextualArithmeticMutationRules": [],' \
// RUN:   '  "returnMutationRules": [' \
// RUN:   '    "boolToFalse|FALSE_RETURNS|return_false|return|return false|false",' \
// RUN:   '    "boolToTrue|TRUE_RETURNS|return_true|return|return true|true"' \
// RUN:   '  ],' \
// RUN:   '  "voidCallMutationRules": [],' \
// RUN:   '  "sourceMutationDisplayRules": []' \
// RUN:   '}' > %t/config.json
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-build-swift -O %t/Value.swift %t/main.swift -module-name SwiftmutBoolCallConditionOwnsValueApply -o %t/a.out
// RUN: find %t/fragments -type f -name '*.json' -exec cat {} ';' | %{python} %S/Inputs/swiftmut-render-condition-ranges.py %t > %t/all-fragments.json
// RUN: %FileCheck %s --input-file %t/all-fragments.json
// RUN: %FileCheck %s --check-prefix=NOCHAIN --input-file %t/all-fragments.json
// RUN: %FileCheck %s --check-prefix=EVENTS --input-file %t/compiler-events.jsonl
// RUN: %FileCheck %s --check-prefix=RUNTIME-SKIP --input-file %t/compiler-events.jsonl
// RUN: %target-codesign %t/a.out
// RUN: %{python} %t/check.py %t

//--- Value.swift
@inline(never)
public func swiftmutBoolCall(_ text: String) -> Bool {
  return text.hasPrefix("@")
}

@inline(never)
public func swiftmutCandidateCount(_ values: [Int]) -> Int {
  return values.count
}

//--- main.swift
import Foundation

@_silgen_name("__swiftmut_visit")
public func __swiftmut_visit(_ siteID: UInt64) -> UInt32 {
  let environment = ProcessInfo.processInfo.environment
  guard UInt64(environment["SWIFTMUT_TEST_SITE"] ?? "") == siteID else { return 0 }
  return UInt32(environment["SWIFTMUT_TEST_ALTERNATIVE"] ?? "") ?? 0
}

public func swiftmutCheck(_ text: String) -> Int {
  if swiftmutBoolCall(text) {
    return 1
  }
  return 0
}

public func swiftmutDirectPrefixCheck(_ text: String) -> Int {
  if text.hasPrefix("@") {
    return 1
  }
  return 0
}

public func swiftmutCountComparisonCheck(_ values: [Int]) -> Int {
  if swiftmutCandidateCount(values) == 0 {
    return 1
  }
  return 0
}

public func swiftmutPrefixClassifierShape(_ text: String) -> Int {
  if text.hasPrefix("//") || text.hasPrefix("/*") || text.hasPrefix("*") {
    return 1
  }
  if text.hasPrefix("import ") || text == "import" {
    return 2
  }
  if text.hasPrefix("@") {
    return 3
  }
  return 0
}

print(swiftmutPrefixClassifierShape("/*"), swiftmutPrefixClassifierShape("*"),
      swiftmutPrefixClassifierShape("import"), swiftmutPrefixClassifierShape("@"))

// CHECK-DAG: "function":"{{.*}}swiftmutCheckySiSSF"{{.*}}"siteKind":"condition"{{.*}}"sourceOriginal":"swiftmutBoolCall(text)","sourceMutated":"false"{{.*}}"sourceOriginal":"swiftmutBoolCall(text)","sourceMutated":"true"
// CHECK-DAG: "function":"{{.*}}swiftmutDirectPrefixCheckySiSSF"{{.*}}"siteKind":"condition"{{.*}}"sourceOriginal":"text.hasPrefix(\"@\")","sourceMutated":"false"{{.*}}"sourceOriginal":"text.hasPrefix(\"@\")","sourceMutated":"true"
// CHECK-DAG: "function":"{{.*}}swiftmutCountComparisonCheckySiSaySiGF"{{.*}}"siteKind":"condition"{{.*}}"sourceOriginal":"swiftmutCandidateCount(values) == 0","sourceMutated":"false"{{.*}}"sourceOriginal":"swiftmutCandidateCount(values) == 0","sourceMutated":"true"
// CHECK-DAG: "function":"{{.*}}swiftmutPrefixClassifierShapeySiSSF"{{.*}}"siteKind":"condition"{{.*}}"sourceOriginal":"text.hasPrefix(\"@\")","sourceMutated":"false"{{.*}}"sourceOriginal":"text.hasPrefix(\"@\")","sourceMutated":"true"
// NOCHAIN: "sites"
// NOCHAIN-NOT: "sourceOriginal":"text.hasPrefix(\"//\")"
// NOCHAIN-NOT: "sourceOriginal":"text.hasPrefix(\"import \")"
// NOCHAIN-NOT: "siteKind":"condition"{{.*}}"sourceOriginal":"text == \"import\""
// NOCHAIN-NOT: "siteKind":"valueApply"{{.*}}"sourceOriginal":"swiftmutCandidateCount(values)"
// EVENTS-DAG: "event":"metamutantDiscovery","module":"SwiftmutBoolCallConditionOwnsValueApply","function":"{{.*}}swiftmutCheckySiSSF"{{.*}}"conditionSites":"1"{{.*}}"valueApplySites":"0"
// RUNTIME-SKIP: "event":"functionSkip","reason":"generatedRuntimeSupport","module":"SwiftmutBoolCallConditionOwnsValueApply","function":"__swiftmut_visit"
// EVENTS-DAG: "event":"metamutantDiscovery","module":"SwiftmutBoolCallConditionOwnsValueApply","function":"{{.*}}swiftmutDirectPrefixCheckySiSSF"{{.*}}"conditionSites":"1"{{.*}}"valueApplySites":"0"
// EVENTS-DAG: "event":"metamutantDiscovery","module":"SwiftmutBoolCallConditionOwnsValueApply","function":"{{.*}}swiftmutCountComparisonCheckySiSaySiGF"{{.*}}"conditionSites":"1"{{.*}}"valueApplySites":"0"
// EVENTS-DAG: "event":"metamutantDiscovery","module":"SwiftmutBoolCallConditionOwnsValueApply","function":"{{.*}}swiftmutPrefixClassifierShapeySiSSF"{{.*}}"conditionSites":"1"{{.*}}"conditionCompoundSourceConstantAlternatives":"10"{{.*}}"valueApplySites":"3"

//--- check.py
import json, os, pathlib, subprocess, sys
root = pathlib.Path(sys.argv[1])
sites = [site for path in (root / "fragments").glob("*.json")
         for site in json.loads(path.read_text()).get("sites", [])
         if "swiftmutPrefixClassifierShape" in site["function"] and site["siteKind"] == "valueApply"]
assert len(sites) == 3, sites
assert subprocess.check_output([str(root / "a.out")], text=True).strip() == "1 1 2 3"
for original, expected in [('text.hasPrefix("/*")', "0 1 2 3"),
                           ('text.hasPrefix("*")', "1 0 2 3"),
                           ('text == "import"', "1 1 0 3")]:
    site = next(s for s in sites if s["alternatives"][0]["sourceOriginal"] == original)
    alternative = next(a for a in site["alternatives"] if a["operation"] == "replaceWithFalse")
    environment = dict(os.environ, SWIFTMUT_TEST_SITE=str(site["siteID"]),
                       SWIFTMUT_TEST_ALTERNATIVE=str(alternative["alternativeIndex"]))
    actual = subprocess.check_output([str(root / "a.out")], env=environment, text=True).strip()
    assert actual == expected, (original, actual, expected)
