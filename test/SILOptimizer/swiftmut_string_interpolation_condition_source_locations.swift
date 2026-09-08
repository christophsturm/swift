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
// RUN:   '    "COMPARISON|NEGATE_CONDITIONALS|cmp_ne|count == 1|count != 1",' \
// RUN:   '    "COMPARISON|CONDITION_FALSE|condition_false|count == 1|false",' \
// RUN:   '    "COMPARISON|CONDITION_TRUE|condition_true|count == 1|true"' \
// RUN:   '  ],' \
// RUN:   '  "arithmeticMutationRules": [],' \
// RUN:   '  "contextualArithmeticMutationRules": [],' \
// RUN:   '  "returnMutationRules": [],' \
// RUN:   '  "voidCallMutationRules": [],' \
// RUN:   '  "sourceMutationDisplayRules": []' \
// RUN:   '}' > %t/config.json
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -emit-sil -O -module-name SwiftmutStringInterpolationConditionSourceLocations %s -o /dev/null
// RUN: find %t/fragments -type f -name '*.json' -exec cat {} ';' > %t/all-fragments.json
// RUN: %FileCheck %s --input-file %t/all-fragments.json

public func swiftmutCountLabel(_ count: Int, singular: String, plural: String) -> String {
  "\(count) \(count == 1 ? singular : plural)"
}

@_silgen_name("__swiftmut_visit")
public func __swiftmut_visit(_ siteID: UInt64) -> UInt32 {
  0
}

// CHECK: "siteKind":"condition",{{.*}}"resultKind":"condition"
// CHECK-SAME: "sourceOriginal":"count == 1","sourceMutated":"count != 1"
// CHECK-SAME: "sourceOriginal":"count == 1","sourceMutated":"false"
// CHECK-SAME: "sourceOriginal":"count == 1","sourceMutated":"true"
