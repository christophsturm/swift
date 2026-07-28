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
// RUN:   '  "enabledMutators": ["VOID_METHOD_CALLS"],' \
// RUN:   '  "conditionMutationRules": [],' \
// RUN:   '  "arithmeticMutationRules": [],' \
// RUN:   '  "contextualArithmeticMutationRules": [],' \
// RUN:   '  "returnMutationRules": [],' \
// RUN:   '  "voidCallMutationRules": [' \
// RUN:   '    "VOID_METHOD_CALLS|remove_void_call|call|/* removed */|noop"' \
// RUN:   '  ],' \
// RUN:   '  "sourceMutationDisplayRules": []' \
// RUN:   '}' > %t/config.json
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -emit-sil -O -module-name SwiftmutVoidCallSourceLocations %s -o /dev/null
// RUN: find %t/fragments -type f -name '*.json' -exec cat {} ';' > %t/all-fragments.json
// RUN: %FileCheck %s --input-file %t/all-fragments.json
// RUN: %FileCheck %s --check-prefix=EVENTS --input-file %t/compiler-events.jsonl

@_silgen_name("swiftmutExternalRecordVoidCall")
public func swiftmutRecordVoidCall(_ value: Int)

public func swiftmutVoidCallStatement(_ input: Int) {
  swiftmutRecordVoidCall(input)
}

public func swiftmutVoidCallExpressionPosition(_ input: Int) {
  let _: Void = swiftmutRecordVoidCall(input)
}

public func swiftmutVoidCallExpressionBeforeStatement(_ input: Int) {
  let _: Void = swiftmutRecordVoidCall(input)
  swiftmutRecordVoidCall(input + 1)
}

@_silgen_name("__swiftmut_visit")
public func __swiftmut_visit(_ siteID: UInt64) -> UInt32 {
  0
}

// CHECK: "sourceLocation":{"file":"swiftmut_void_call_source_locations.swift","line":32,"column":3}
// CHECK-SAME: "siteKind":"voidCall"
// CHECK-SAME: "resultKind":"statement"
// CHECK-SAME: "sourceOriginal":"call","sourceMutated":"/* removed */"
// CHECK-NOT: "line":36
// CHECK-NOT: "line":40
// CHECK-NOT: "line":41

// EVENTS: "event":"metamutantDiscovery"
// EVENTS-SAME: "function":"$s31SwiftmutVoidCallSourceLocations08swiftmutbC9StatementyySiF"
// EVENTS-SAME: "voidCallSites":"1"
// EVENTS-SAME: "voidCallMutationEligibleApplyInstructions":"1"
// EVENTS-SAME: "voidCallNonStatementSourceLocations":"0"
// EVENTS: "event":"metamutantDiscovery"
// EVENTS-SAME: "function":"$s31SwiftmutVoidCallSourceLocations08swiftmutbC18ExpressionPositionyySiF"
// EVENTS-SAME: "voidCallSites":"0"
// EVENTS-SAME: "voidCallMutationEligibleApplyInstructions":"1"
// EVENTS-SAME: "voidCallNonStatementSourceLocations":"1"
// EVENTS: "event":"metamutantDiscovery"
// EVENTS-SAME: "function":"$s31SwiftmutVoidCallSourceLocations08swiftmutbC25ExpressionBeforeStatementyySiF"
// EVENTS-SAME: "voidCallSites":"0"
// EVENTS-SAME: "voidCallMutationEligibleApplyInstructions":"2"
// EVENTS-SAME: "voidCallNonStatementSourceLocations":"2"
