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
// RUN:   '  "enabledMutators": ["EMPTY_RETURNS", "PRIMITIVE_RETURNS", "STATEMENT_DELETIONS"],' \
// RUN:   '  "conditionMutationRules": [],' \
// RUN:   '  "arithmeticMutationRules": [],' \
// RUN:   '  "contextualArithmeticMutationRules": [],' \
// RUN:   '  "returnMutationRules": [' \
// RUN:   '    "integerToZero|PRIMITIVE_RETURNS|return_zero|return|return 0|0",' \
// RUN:   '    "stringToEmpty|EMPTY_RETURNS|return_empty_string|return|return \\\"|\\\"\\\""' \
// RUN:   '  ],' \
// RUN:   '  "voidCallMutationRules": [],' \
// RUN:   '  "statementMutationRules": [' \
// RUN:   '    "unusedCall|STATEMENT_DELETIONS|remove_unused_call|call|removed call|removed"' \
// RUN:   '  ],' \
// RUN:   '  "sourceMutationDisplayRules": []' \
// RUN:   '}' > %t/config.json
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-build-swift -O %t/main.swift -module-name SwiftmutOverlappingValueAndCallSites -emit-sil -o %t/output.sil
// RUN: %FileCheck %s --check-prefix=EVENTS --input-file %t/compiler-events.jsonl
// RUN: find %t/fragments -type f -name '*.json' -exec cat {} ';' | sort -u > %t/all-fragments.json
// RUN: %FileCheck %s --check-prefix=MANIFEST --input-file %t/all-fragments.json

// EVENTS: "event":"metamutantDiscovery","module":"SwiftmutOverlappingValueAndCallSites","function":"{{.*}}swiftmutMakeReporter{{.*}}fU_"
// EVENTS-SAME: "valueApplySites":"0"
// EVENTS-SAME: "statementDeletionSites":"1"
// EVENTS: "event":"metamutantInjection","module":"SwiftmutOverlappingValueAndCallSites","function":"{{.*}}swiftmutMakeReporter{{.*}}fU_"
// EVENTS-SAME: "injectedValueApplySites":"0"
// EVENTS-SAME: "injectedStatementDeletionSites":"1"
// MANIFEST: "function":"{{.*}}swiftmutMakeReporter{{.*}}fU_","sourceLocation":{{.*}}"siteKind":"statementDeletion"

//--- main.swift
import Darwin

@inline(never)
public func swiftmutMakeReporter() -> @Sendable (String) -> Void {
  {
    fputs("\($0)\n", stderr)
  }
}

@_silgen_name("__swiftmut_visit")
public func __swiftmut_visit(_ siteID: UInt64) -> UInt32 {
  0
}
