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
// RUN:   '  "enabledMutators": ["CONDITIONALS_BOUNDARY", "CONDITION_FALSE", "CONDITION_TRUE", "NEGATE_CONDITIONALS"],' \
// RUN:   '  "conditionMutationRules": [' \
// RUN:   '    "ICMP_SGE|CONDITIONALS_BOUNDARY|cmp_sgt|>=|>",' \
// RUN:   '    "ICMP_SGE|NEGATE_CONDITIONALS|cmp_slt|>=|<",' \
// RUN:   '    "COMPARISON|CONDITION_FALSE|condition_false|condition|false",' \
// RUN:   '    "COMPARISON|CONDITION_TRUE|condition_true|condition|true"' \
// RUN:   '  ],' \
// RUN:   '  "arithmeticMutationRules": [],' \
// RUN:   '  "contextualArithmeticMutationRules": [],' \
// RUN:   '  "returnMutationRules": [],' \
// RUN:   '  "voidCallMutationRules": [],' \
// RUN:   '  "sourceMutationDisplayRules": []' \
// RUN:   '}' > %t/config.json
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -emit-sil -O -module-name SwiftmutForWhereConditionSourceLocations %s -o /dev/null
// RUN: find %t/fragments -type f -name '*.json' -exec cat {} ';' > %t/all-fragments.json
// RUN: %FileCheck %s --input-file %t/all-fragments.json

public func swiftmutForWhereTotal(_ values: [Int], limit: Int) -> Int {
  var total = 0
  for value in values where value >= limit {
    total += value
  }
  return total
}

@_silgen_name("__swiftmut_visit")
public func __swiftmut_visit(_ siteID: UInt64) -> UInt32 {
  0
}

// CHECK: "sourceLocation":{"file":"swiftmut_for_where_condition_source_locations.swift","line":32,"column":29}
// CHECK-SAME: "siteKind":"condition"
// CHECK-SAME: "sourceOriginal":"value >= limit","sourceMutated":"value > limit"
// CHECK-SAME: "sourceOriginal":"value >= limit","sourceMutated":"value < limit"
// CHECK-SAME: "sourceOriginal":"value >= limit","sourceMutated":"false"
// CHECK-SAME: "sourceOriginal":"value >= limit","sourceMutated":"true"
