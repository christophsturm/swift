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
// RUN:   '  "enabledMutators": ["EMPTY_RETURNS"],' \
// RUN:   '  "conditionMutationRules": [],' \
// RUN:   '  "arithmeticMutationRules": [],' \
// RUN:   '  "contextualArithmeticMutationRules": [],' \
// RUN:   '  "returnMutationRules": [' \
// RUN:   '    "arrayToEmpty|EMPTY_RETURNS|return_empty_array|return|return []|[]"' \
// RUN:   '  ],' \
// RUN:   '  "voidCallMutationRules": [],' \
// RUN:   '  "sourceMutationDisplayRules": []' \
// RUN:   '}' > %t/config.json
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-build-swift -O %t/Value.swift %t/main.swift -module-name SwiftmutNontrivialValueApplyRuntime -o %t/a.out
// RUN: %target-codesign %t/a.out
// RUN: %target-run %t/a.out | %FileCheck %s
// RUN: %FileCheck %s --check-prefix=EVENTS --input-file %t/compiler-events.jsonl
// RUN: %FileCheck %s --check-prefix=NESTED --input-file %t/compiler-events.jsonl
// RUN: find %t/fragments -type f -name '*.json' -exec cat {} ';' > %t/all-fragments.json
// RUN: %FileCheck %s --check-prefix=MANIFEST --input-file %t/all-fragments.json

// CHECK: 0
// EVENTS: "event":"metamutantInjection"
// EVENTS-SAME: "function":"{{.*}}swiftmutProbeyyF"
// EVENTS-SAME: "attemptedValueApplySites":"1"
// EVENTS-SAME: "injectedValueApplySites":"1"
// NESTED: "event":"metamutantDiscovery","module":"SwiftmutNontrivialValueApplyRuntime","function":"{{.*}}swiftmutNestedProbeyyF"
// NESTED-SAME: "valueApplySites":"1"
// MANIFEST: "siteKind":"valueApply"
// MANIFEST-SAME: "valueTypeKind":"array"
// MANIFEST: "sourceOriginal":"swiftmutLoadedValues()"
// MANIFEST-SAME: "sourceMutated":"[]"

//--- Value.swift
@inline(never)
public func swiftmutLoadedValues() -> [Int] {
  [1, 2, 3]
}

//--- main.swift
@_silgen_name("__swiftmut_visit")
public func __swiftmut_visit(_ siteID: UInt64) -> UInt32 {
  1
}

@_silgen_name("__swiftmut_empty_array")
public func __swiftmut_empty_array<Element>() -> [Element] {
  []
}

public func swiftmutProbe() {
  let values = swiftmutLoadedValues()
  print(values.count)
}

public func swiftmutNestedProbe() {
  print(swiftmutLoadedValues().count)
}

swiftmutProbe()
