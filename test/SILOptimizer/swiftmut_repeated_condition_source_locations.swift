// RUN: rm -rf %t
// RUN: mkdir -p %t
// swiftmut runs in the native Diagnostic pipeline.
// RUN: printf '%b\n' \
// RUN:   '{' \
// RUN:   '  "mode": "metamutant",' \
// RUN:   '  "manifestPath": "%t/mutants.jsonl",' \
// RUN:   '  "manifestFragmentsDirectory": "%t/fragments",' \
// RUN:   '  "compilerEventsPath": "%t/compiler-events.jsonl",' \
// RUN:   '  "packageRoot": "%S",' \
// RUN:   '  "excludePaths": [],' \
// RUN:   '  "sourceFiles": ["%s"],' \
// RUN:   '  "enabledMutators": ["CONDITION_FALSE", "CONDITION_TRUE", "NEGATE_CONDITIONALS"],' \
// RUN:   '  "conditionMutationRules": [' \
// RUN:   '    "COMPARISON|NEGATE_CONDITIONALS|cmp_ne|swiftmutConditionValue(count) == 1|swiftmutConditionValue(count) != 1",' \
// RUN:   '    "COMPARISON|CONDITION_FALSE|condition_false|swiftmutConditionValue(count) == 1|false",' \
// RUN:   '    "COMPARISON|CONDITION_TRUE|condition_true|swiftmutConditionValue(count) == 1|true"' \
// RUN:   '  ],' \
// RUN:   '  "arithmeticMutationRules": [],' \
// RUN:   '  "contextualArithmeticMutationRules": [],' \
// RUN:   '  "returnMutationRules": [],' \
// RUN:   '  "voidCallMutationRules": [],' \
// RUN:   '  "sourceMutationDisplayRules": []' \
// RUN:   '}' > %t/config.json
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -emit-sil -O -module-name SwiftmutRepeatedConditionSourceLocations %s -o /dev/null
// RUN: find %t/fragments -type f -name '*.json' -exec cat {} ';' | %{python} %S/Inputs/swiftmut-render-condition-ranges.py %S > %t/all-fragments.json
// RUN: %FileCheck %s --input-file %t/all-fragments.json

@inline(never)
public func swiftmutConditionSink(_ value: Int) {}

@inline(never)
public func swiftmutConditionValue(_ value: Int) -> Int {
  value
}

public func swiftmutRepeatedCondition(_ count: Int) {
  if swiftmutConditionValue(count) == 1 {
    swiftmutConditionSink(1)
  }
  if swiftmutConditionValue(count) == 1 {
    swiftmutConditionSink(2)
  }
  if swiftmutOtherCondition(
    count
  ) {
    swiftmutConditionSink(3)
  }
}

@inline(never)
public func swiftmutOtherCondition(_ value: Int) -> Bool {
  value > 0
}

@_silgen_name("__swiftmut_visit")
public func __swiftmut_visit(_ siteID: UInt64) -> UInt32 {
  0
}

// CHECK: "line":38,"column":6},"siteKind":"condition",{{.*}}"resultKind":"condition","alternatives":[{{.*}}"sourceOriginal":"swiftmutConditionValue(count) == 1","sourceMutated":"swiftmutConditionValue(count) != 1"{{.*}}"sourceOriginal":"swiftmutConditionValue(count) == 1","sourceMutated":"false"{{.*}}"sourceOriginal":"swiftmutConditionValue(count) == 1","sourceMutated":"true"{{.*}}"line":41,"column":6},"siteKind":"condition",{{.*}}"resultKind":"condition","alternatives":[{{.*}}"sourceOriginal":"swiftmutConditionValue(count) == 1","sourceMutated":"swiftmutConditionValue(count) != 1"{{.*}}"sourceOriginal":"swiftmutConditionValue(count) == 1","sourceMutated":"false"{{.*}}"sourceOriginal":"swiftmutConditionValue(count) == 1","sourceMutated":"true"
