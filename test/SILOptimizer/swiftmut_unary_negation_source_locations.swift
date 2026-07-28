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
// RUN:   '  "enabledMutators": ["INVERT_NEGS"],' \
// RUN:   '  "conditionMutationRules": [],' \
// RUN:   '  "arithmeticMutationRules": [],' \
// RUN:   '  "contextualArithmeticMutationRules": [' \
// RUN:   '    "SSubOver|unaryNegation|INVERT_NEGS|sadd_with_overflow|-|"' \
// RUN:   '  ],' \
// RUN:   '  "returnMutationRules": [],' \
// RUN:   '  "voidCallMutationRules": [],' \
// RUN:   '  "sourceMutationDisplayRules": []' \
// RUN:   '}' > %t/config.json
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -emit-sil -O -module-name SwiftmutUnaryNegationSourceLocations %s -o /dev/null
// RUN: find %t/fragments -type f -name '*.json' -exec cat {} ';' > %t/all-fragments.json
// RUN: %FileCheck %s --input-file %t/all-fragments.json
// RUN: %FileCheck %s --check-prefix=EVENTS --input-file %t/compiler-events.jsonl

public func swiftmutUnaryNegation(_ value: Int) -> Int {
  return -value
}

@_silgen_name("__swiftmut_visit")
public func __swiftmut_visit(_ siteID: UInt64) -> UInt32 {
  0
}

// CHECK: "sourceLocation":{"file":"swiftmut_unary_negation_source_locations.swift","line":29,"column":10}
// CHECK-SAME: "siteKind":"arithmetic"
// CHECK-SAME: "mutator":"INVERT_NEGS"
// CHECK-SAME: "sourceOriginal":"-value","sourceMutated":"value"

// EVENTS: "event":"metamutantDiscovery","module":"SwiftmutUnaryNegationSourceLocations","function":"$s36SwiftmutUnaryNegationSourceLocations08swiftmutbC0yS2iF"
// EVENTS-SAME: "arithmeticSites":"1"
// EVENTS: "event":"metamutantInjection","module":"SwiftmutUnaryNegationSourceLocations","function":"$s36SwiftmutUnaryNegationSourceLocations08swiftmutbC0yS2iF"
// EVENTS-SAME: "attemptedArithmeticSites":"1"
// EVENTS-SAME: "injectedArithmeticSites":"1"
