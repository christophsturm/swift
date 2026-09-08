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
// RUN:   '  "enabledMutators": ["NULL_RETURNS", "EMPTY_RETURNS"],' \
// RUN:   '  "conditionMutationRules": [],' \
// RUN:   '  "arithmeticMutationRules": [],' \
// RUN:   '  "contextualArithmeticMutationRules": [],' \
// RUN:   '  "returnMutationRules": [' \
// RUN:   '    "optionalToNil|NULL_RETURNS|return_nil|return|return nil|nil",' \
// RUN:   '    "stringToEmpty|EMPTY_RETURNS|return_empty_string|return|return \\\"\\\"|\\\"\\\"",' \
// RUN:   '    "arrayToEmpty|EMPTY_RETURNS|return_empty_array|return|return []|[]",' \
// RUN:   '    "dictionaryToEmpty|EMPTY_RETURNS|return_empty_dictionary|return|return [:]|[:]",' \
// RUN:   '    "setToEmpty|EMPTY_RETURNS|return_empty_set|return|return []|[]"' \
// RUN:   '  ],' \
// RUN:   '  "voidCallMutationRules": [],' \
// RUN:   '  "statementMutationRules": [],' \
// RUN:   '  "sourceMutationDisplayRules": []' \
// RUN:   '}' > %t/config.json
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-build-swift -O %t/main.swift -module-name SwiftmutNontrivialReturnRuntime -o %t/a.out
// RUN: %target-codesign %t/a.out
// RUN: %target-run %t/a.out | %FileCheck %s
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-build-swift -O -D SWIFTMUT_BASELINE %t/main.swift -module-name SwiftmutNontrivialReturnRuntime -o %t/baseline.out
// RUN: %target-codesign %t/baseline.out
// RUN: %target-run %t/baseline.out | %FileCheck %s --check-prefix=BASELINE
// RUN: %FileCheck %s --check-prefix=EVENTS --input-file %t/compiler-events.jsonl
// RUN: find %t/fragments -type f -name '*.json' -exec cat {} ';' | %{python} %S/Inputs/swiftmut-render-condition-ranges.py %t | sort -u > %t/all-fragments.json
// RUN: %FileCheck %s --check-prefix=MANIFEST --input-file %t/all-fragments.json

// CHECK: true
// CHECK-NEXT: 0
// CHECK-NEXT: 0
// CHECK-NEXT: 0
// CHECK-NEXT: 0
// CHECK-NEXT: 1
// BASELINE: false
// BASELINE-NEXT: 5
// BASELINE-NEXT: 3
// BASELINE-NEXT: 1
// BASELINE-NEXT: 2
// BASELINE-NEXT: 1
// EVENTS: "event":"metamutantDiscovery","module":"SwiftmutNontrivialReturnRuntime","function":"{{.*}}swiftmutOptional
// EVENTS-SAME: "returnSites":"1"
// EVENTS-SAME: "returnOptionalTerminators":"1"
// EVENTS-SAME: "returnMutationEligibleTerminators":"1"
// EVENTS-SAME: "returnSourceLocationMisses":"0"
// EVENTS: "event":"metamutantDiscovery","module":"SwiftmutNontrivialReturnRuntime","function":"{{.*}}swiftmutString
// EVENTS-SAME: "returnSites":"1"
// EVENTS-SAME: "returnStringTerminators":"1"
// EVENTS-SAME: "returnMutationEligibleTerminators":"1"
// EVENTS-SAME: "returnSourceLocationMisses":"0"
// EVENTS: "event":"metamutantDiscovery","module":"SwiftmutNontrivialReturnRuntime","function":"{{.*}}swiftmutArray
// EVENTS-SAME: "returnSites":"1"
// EVENTS-SAME: "returnCollectionTerminators":"1"
// EVENTS-SAME: "returnMutationEligibleTerminators":"1"
// EVENTS-SAME: "returnSourceLocationMisses":"0"
// EVENTS: "event":"metamutantInjection","module":"SwiftmutNontrivialReturnRuntime","function":"{{.*}}swiftmutOptional
// EVENTS-SAME: "attemptedReturnSites":"1"
// EVENTS-SAME: "injectedReturnSites":"1"
// EVENTS: "event":"metamutantInjection","module":"SwiftmutNontrivialReturnRuntime","function":"{{.*}}swiftmutString
// EVENTS-SAME: "attemptedReturnSites":"1"
// EVENTS-SAME: "injectedReturnSites":"1"
// EVENTS: "event":"metamutantInjection","module":"SwiftmutNontrivialReturnRuntime","function":"{{.*}}swiftmutArray
// EVENTS-SAME: "attemptedReturnSites":"1"
// EVENTS-SAME: "injectedReturnSites":"1"
// EVENTS: "event":"metamutantDiscovery","module":"SwiftmutNontrivialReturnRuntime","function":"{{.*}}swiftmutDictionary
// EVENTS-SAME: "returnSites":"1"
// EVENTS-SAME: "returnCollectionTerminators":"1"
// EVENTS-SAME: "returnMutationEligibleTerminators":"1"
// EVENTS-SAME: "returnSourceLocationMisses":"0"
// EVENTS: "event":"metamutantInjection","module":"SwiftmutNontrivialReturnRuntime","function":"{{.*}}swiftmutDictionary
// EVENTS-SAME: "attemptedReturnSites":"1"
// EVENTS-SAME: "injectedReturnSites":"1"
// EVENTS: "event":"metamutantDiscovery","module":"SwiftmutNontrivialReturnRuntime","function":"{{.*}}swiftmutSet
// EVENTS-SAME: "returnSites":"1"
// EVENTS-SAME: "returnCollectionTerminators":"1"
// EVENTS-SAME: "returnMutationEligibleTerminators":"1"
// EVENTS-SAME: "returnSourceLocationMisses":"0"
// EVENTS: "event":"metamutantInjection","module":"SwiftmutNontrivialReturnRuntime","function":"{{.*}}swiftmutSet
// EVENTS-SAME: "attemptedReturnSites":"1"
// EVENTS-SAME: "injectedReturnSites":"1"
// MANIFEST-DAG: "function":"{{[^"]*}}swiftmutOptional{{[^"]*}}"{{.*}}"siteKind":"returnValue"{{.*}}"sourceOriginal":"value","sourceMutated":"nil"
// MANIFEST-DAG: "function":"{{[^"]*}}swiftmutString{{[^"]*}}"{{.*}}"siteKind":"returnValue"{{.*}}"sourceOriginal":"value","sourceMutated":"\"\""
// MANIFEST-DAG: "function":"{{[^"]*}}swiftmutArray{{[^"]*}}"{{.*}}"siteKind":"returnValue"{{.*}}"sourceOriginal":"value","sourceMutated":"[]"

//--- main.swift
public var swiftmutDeinitCount = 0

public final class SwiftmutToken {
  deinit {
    swiftmutDeinitCount += 1
  }
}

@inline(never)
public func swiftmutOptional(_ value: consuming SwiftmutToken?) -> SwiftmutToken? {
  value
}

@inline(never)
public func swiftmutString(_ value: consuming String) -> String {
  value
}

@inline(never)
public func swiftmutArray(_ value: consuming [Int]) -> [Int] {
  value
}

@inline(never)
public func swiftmutDictionary(_ value: consuming [String: Int]) -> [String: Int] {
  value
}

@inline(never)
public func swiftmutSet(_ value: consuming Set<Int>) -> Set<Int> {
  value
}

@_silgen_name("__swiftmut_visit")
public func __swiftmut_visit(_ siteID: UInt64) -> UInt32 {
#if SWIFTMUT_BASELINE
  0
#else
  1
#endif
}

@_silgen_name("__swiftmut_empty_string")
public func __swiftmut_empty_string() -> String {
  ""
}

@_silgen_name("__swiftmut_empty_array")
public func __swiftmut_empty_array<Element>() -> [Element] {
  []
}

@_silgen_name("__swiftmut_empty_dictionary")
public func __swiftmut_empty_dictionary<Key: Hashable, Value>() -> [Key: Value] {
  [:]
}

@_silgen_name("__swiftmut_empty_set")
public func __swiftmut_empty_set<Element: Hashable>() -> Set<Element> {
  []
}

do {
  let result = swiftmutOptional(SwiftmutToken())
  print(result == nil)
}
print(swiftmutString("hello").count)
print(swiftmutArray([1, 2, 3]).count)
print(swiftmutDictionary(["answer": 42]).count)
print(swiftmutSet([1, 2]).count)
print(swiftmutDeinitCount)
