// RUN: rm -rf %t
// RUN: split-file %s %t
// RUN: printf '%b\n' '---' "name: ''" 'passes: [ "\"swiftmut\"" ]' > %t/pipeline.yaml
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
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-build-swift -O %t/Value.swift %t/main.swift -module-name SwiftmutBoolCallConditionOwnsValueApply -Xfrontend -external-pass-pipeline-filename -Xfrontend %t/pipeline.yaml -o %t/a.out
// RUN: find %t/fragments -type f -name '*.json' -exec cat {} ';' > %t/all-fragments.json
// RUN: %FileCheck %s --input-file %t/all-fragments.json
// RUN: %FileCheck %s --check-prefix=EVENTS --input-file %t/compiler-events.jsonl

//--- Value.swift
@inline(never)
public func swiftmutBoolCall(_ text: String) -> Bool {
  return text.hasPrefix("@")
}

//--- main.swift
@_silgen_name("__swiftmut_visit")
public func __swiftmut_visit(_ siteID: UInt64) -> UInt32 {
  0
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

// CHECK-DAG: "function":"{{.*}}swiftmutCheckySiSSF"{{.*}}"siteKind":"condition"{{.*}}"sourceOriginal":"swiftmutBoolCall(text)","sourceMutated":"false"{{.*}}"sourceOriginal":"swiftmutBoolCall(text)","sourceMutated":"true"
// CHECK-DAG: "function":"{{.*}}swiftmutDirectPrefixCheckySiSSF"{{.*}}"siteKind":"condition"{{.*}}"sourceOriginal":"text.hasPrefix(\"@\")","sourceMutated":"false"{{.*}}"sourceOriginal":"text.hasPrefix(\"@\")","sourceMutated":"true"
// CHECK-DAG: "function":"{{.*}}swiftmutPrefixClassifierShapeySiSSF"{{.*}}"siteKind":"condition"{{.*}}"sourceOriginal":"text.hasPrefix(\"@\")","sourceMutated":"false"{{.*}}"sourceOriginal":"text.hasPrefix(\"@\")","sourceMutated":"true"
// EVENTS: "event":"metamutantDiscovery","module":"SwiftmutBoolCallConditionOwnsValueApply","function":"{{.*}}swiftmutCheckySiSSF"
// EVENTS-SAME: "conditionSites":"1"
// EVENTS-SAME: "valueApplySites":"0"
// EVENTS: "event":"metamutantDiscovery","module":"SwiftmutBoolCallConditionOwnsValueApply","function":"{{.*}}swiftmutDirectPrefixCheckySiSSF"
// EVENTS-SAME: "conditionSites":"1"
// EVENTS-SAME: "valueApplySites":"0"
// EVENTS: "event":"metamutantDiscovery","module":"SwiftmutBoolCallConditionOwnsValueApply","function":"{{.*}}swiftmutPrefixClassifierShapeySiSSF"
// EVENTS-SAME: "conditionSites":"1"
