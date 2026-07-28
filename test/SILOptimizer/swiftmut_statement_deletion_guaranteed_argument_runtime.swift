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
// RUN:   '  "enabledMutators": ["STATEMENT_DELETIONS"],' \
// RUN:   '  "conditionMutationRules": [],' \
// RUN:   '  "arithmeticMutationRules": [],' \
// RUN:   '  "contextualArithmeticMutationRules": [],' \
// RUN:   '  "returnMutationRules": [],' \
// RUN:   '  "voidCallMutationRules": [],' \
// RUN:   '  "statementMutationRules": [' \
// RUN:   '    "unusedCall|STATEMENT_DELETIONS|remove_unused_call|call|removed call|removed"' \
// RUN:   '  ],' \
// RUN:   '  "sourceMutationDisplayRules": []' \
// RUN:   '}' > %t/config.json
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-build-swift -O %t/main.swift -module-name SwiftmutStatementDeletionGuaranteedArgumentRuntime -o %t/a.out
// RUN: %target-codesign %t/a.out
// RUN: %target-run %t/a.out | %FileCheck %s
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-build-swift -O -D SWIFTMUT_BASELINE %t/main.swift -module-name SwiftmutStatementDeletionGuaranteedArgumentRuntime -o %t/baseline.out
// RUN: %target-codesign %t/baseline.out
// RUN: %target-run %t/baseline.out | %FileCheck %s --check-prefix=BASELINE
// RUN: %FileCheck %s --check-prefix=EVENTS --input-file %t/compiler-events.jsonl
// RUN: find %t/fragments -type f -name '*.json' -exec cat {} ';' | sort -u > %t/all-fragments.json
// RUN: %FileCheck %s --check-prefix=MANIFEST --input-file %t/all-fragments.json

// CHECK: 0
// BASELINE: 2
// EVENTS: "event":"metamutantDiscovery","module":"SwiftmutStatementDeletionGuaranteedArgumentRuntime","function":"{{.*}}swiftmutInvoke
// EVENTS-SAME: "statementDeletionSites":"1"
// EVENTS-SAME: "statementDeletionUnusedResultApplyInstructions":"1"
// EVENTS-SAME: "statementDeletionMutationEligibleApplyInstructions":"1"
// EVENTS-SAME: "statementDeletionSourceLocationMisses":"0"
// EVENTS-SAME: "statementDeletionNonStatementSourceLocations":"0"
// EVENTS: "event":"metamutantInjection","module":"SwiftmutStatementDeletionGuaranteedArgumentRuntime","function":"{{.*}}swiftmutInvoke
// EVENTS-SAME: "attemptedStatementDeletionSites":"1"
// EVENTS-SAME: "injectedStatementDeletionSites":"1"
// MANIFEST-NOT: "siteKind":"statementDeletion"
// MANIFEST: "function":"{{.*}}swiftmutInvoke{{.*}}","sourceLocation":{{.*}}"siteKind":"statementDeletion"
// MANIFEST-SAME: "mutator":"STATEMENT_DELETIONS"
// MANIFEST-SAME: "sourceMutated":"removed call"
// MANIFEST-NOT: "siteKind":"statementDeletion"

//--- main.swift
public final class SwiftmutToken {
  public let value: Int

  public init(value: Int) {
    self.value = value
  }
}

public var swiftmutObserved = 0

@discardableResult
@inline(never)
public func swiftmutRecordAndReturn(_ token: SwiftmutToken) -> Int {
  swiftmutObserved = token.value
  return token.value
}

@inline(never)
public func swiftmutInvoke() {
  let token = SwiftmutToken(value: 2)
  swiftmutRecordAndReturn(token)
}

@_silgen_name("__swiftmut_visit")
public func __swiftmut_visit(_ siteID: UInt64) -> UInt32 {
#if SWIFTMUT_BASELINE
  0
#else
  1
#endif
}

swiftmutInvoke()
print(swiftmutObserved)
