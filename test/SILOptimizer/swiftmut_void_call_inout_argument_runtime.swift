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
// RUN:   '  "enabledMutators": ["VOID_METHOD_CALLS"],' \
// RUN:   '  "conditionMutationRules": [],' \
// RUN:   '  "arithmeticMutationRules": [],' \
// RUN:   '  "contextualArithmeticMutationRules": [],' \
// RUN:   '  "returnMutationRules": [],' \
// RUN:   '  "voidCallMutationRules": [' \
// RUN:   '    "VOID_METHOD_CALLS|remove_void_call|call|removed call|noop"' \
// RUN:   '  ],' \
// RUN:   '  "statementMutationRules": [],' \
// RUN:   '  "sourceMutationDisplayRules": []' \
// RUN:   '}' > %t/config.json
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-build-swift -Onone %t/main.swift -module-name SwiftmutVoidCallInoutArgumentRuntime -o %t/a.out
// RUN: %target-codesign %t/a.out
// RUN: %target-run %t/a.out | %FileCheck %s
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-build-swift -Onone -D SWIFTMUT_BASELINE %t/main.swift -module-name SwiftmutVoidCallInoutArgumentRuntime -o %t/baseline.out
// RUN: %target-codesign %t/baseline.out
// RUN: %target-run %t/baseline.out | %FileCheck %s --check-prefix=BASELINE
// RUN: %FileCheck %s --check-prefix=EVENTS --input-file %t/compiler-events.jsonl
// RUN: find %t/fragments -type f -name '*.json' -exec cat {} ';' | sort -u > %t/all-fragments.json
// RUN: %FileCheck %s --check-prefix=MANIFEST --input-file %t/all-fragments.json

// CHECK: 0
// BASELINE: 7
// EVENTS: "event":"metamutantDiscovery","module":"SwiftmutVoidCallInoutArgumentRuntime","function":"{{.*}}swiftmutInvoke
// EVENTS-SAME: "voidCallSites":"1"
// EVENTS-SAME: "voidCallVoidApplyInstructions":"1"
// EVENTS-SAME: "voidCallMutationEligibleApplyInstructions":"1"
// EVENTS-SAME: "voidCallSourceLocationMisses":"0"
// EVENTS-SAME: "voidCallNonStatementSourceLocations":"0"
// EVENTS: "event":"metamutantInjection","module":"SwiftmutVoidCallInoutArgumentRuntime","function":"{{.*}}swiftmutInvoke
// EVENTS-SAME: "attemptedVoidCallSites":"1"
// EVENTS-SAME: "injectedVoidCallSites":"1"
// MANIFEST-NOT: "siteKind":"voidCall"
// MANIFEST: "function":"{{.*}}swiftmutInvoke{{.*}}","sourceLocation":{{.*}}"siteKind":"voidCall"
// MANIFEST-SAME: "mutator":"VOID_METHOD_CALLS"
// MANIFEST-SAME: "sourceMutated":"removed call"
// MANIFEST-NOT: "siteKind":"voidCall"

//--- main.swift
@inline(never)
public func swiftmutRecord(_ total: inout Int, _ value: Int) {
  total += value
}

@inline(never)
public func swiftmutInvoke() -> Int {
  var total = 0
  swiftmutRecord(&total, 7)
  return total
}

@_silgen_name("__swiftmut_visit")
public func __swiftmut_visit(_ siteID: UInt64) -> UInt32 {
#if SWIFTMUT_BASELINE
  0
#else
  1
#endif
}

print(swiftmutInvoke())
