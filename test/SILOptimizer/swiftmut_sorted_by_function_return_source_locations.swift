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
// RUN:   '  "enabledMutators": ["FALSE_RETURNS", "TRUE_RETURNS"],' \
// RUN:   '  "conditionMutationRules": [],' \
// RUN:   '  "arithmeticMutationRules": [],' \
// RUN:   '  "contextualArithmeticMutationRules": [],' \
// RUN:   '  "returnMutationRules": [' \
// RUN:   '    "boolToFalse|FALSE_RETURNS|return_false|return|return false|false",' \
// RUN:   '    "boolToTrue|TRUE_RETURNS|return_true|return|return true|true"' \
// RUN:   '  ],' \
// RUN:   '  "voidCallMutationRules": [],' \
// RUN:   '  "sourceMutationDisplayRules": []' \
// RUN:   '}' > %t/config.json
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -emit-sil -O -module-name SwiftmutSortedByFunctionReturnSourceLocations %s -o /dev/null
// RUN: find %t/fragments -type f -name '*.json' -exec cat {} ';' | %{python} %S/Inputs/swiftmut-render-condition-ranges.py %S > %t/all-fragments.json
// RUN: %FileCheck %s --input-file %t/all-fragments.json
// RUN: %FileCheck %s --check-prefix=EVENTS --input-file %t/compiler-events.jsonl

public struct SwiftmutSortGroup {
  public let weight: Int
  public let name: String
}

public func swiftmutSortGroupPrecedes(_ lhs: SwiftmutSortGroup, _ rhs: SwiftmutSortGroup) -> Bool {
  lhs.weight < rhs.weight
}

public func swiftmutSortGroups(_ groups: [SwiftmutSortGroup]) -> [SwiftmutSortGroup] {
  groups.sorted(by: swiftmutSortGroupPrecedes)
}

@_silgen_name("__swiftmut_visit")
public func __swiftmut_visit(_ siteID: UInt64) -> UInt32 {
  0
}

// CHECK: "siteKind":"scalarValue"
// CHECK: "sourceOriginal":"lhs.weight < rhs.weight","sourceMutated":"false"
// CHECK: "sourceOriginal":"lhs.weight < rhs.weight","sourceMutated":"true"
// CHECK: "siteKind":"returnValue"
// CHECK-SAME: "valueNominalType":{"module":"Swift","name":"Bool"}
// CHECK: "sourceOriginal":"lhs.weight < rhs.weight","sourceMutated":"false"
// CHECK: "sourceOriginal":"lhs.weight < rhs.weight","sourceMutated":"true"
// EVENTS: "event":"functionVisit"
// EVENTS-NOT: "event":"returnSourceLocationMiss"
// EVENTS-NOT: "event":"valueApplySourceLocationMiss"
