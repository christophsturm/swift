// RUN: rm -rf %t
// RUN: split-file %s %t
// RUN: printf '%b\n' '---' "name: ''" 'passes: [ "\"swiftmut\"" ]' > %t/pipeline.yaml
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
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-build-swift -O %t/main.swift -module-name SwiftmutStatementDeletionUnusedResultRuntime -Xfrontend -external-pass-pipeline-filename -Xfrontend %t/pipeline.yaml -o %t/a.out
// RUN: %target-codesign %t/a.out
// RUN: %target-run %t/a.out | %FileCheck %s
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-build-swift -O -D SWIFTMUT_BASELINE %t/main.swift -module-name SwiftmutStatementDeletionUnusedResultRuntime -Xfrontend -external-pass-pipeline-filename -Xfrontend %t/pipeline.yaml -o %t/baseline.out
// RUN: %target-codesign %t/baseline.out
// RUN: %target-run %t/baseline.out | %FileCheck %s --check-prefix=BASELINE
// RUN: %FileCheck %s --check-prefix=EVENTS --input-file %t/compiler-events.jsonl
// RUN: find %t/fragments -type f -name '*.json' -exec cat {} ';' | sort -u > %t/all-fragments.json
// RUN: %FileCheck %s --check-prefix=MANIFEST --input-file %t/all-fragments.json

// CHECK: 1
// BASELINE: 2
// EVENTS: "event":"metamutantDiscovery","module":"SwiftmutStatementDeletionUnusedResultRuntime","function":"{{.*}}swiftmutInvoke
// EVENTS-SAME: "statementDeletionSites":"1"
// EVENTS-SAME: "statementDeletionApplyInstructions":"1"
// EVENTS-SAME: "statementDeletionUnusedResultApplyInstructions":"1"
// EVENTS-SAME: "statementDeletionMutationEligibleApplyInstructions":"1"
// EVENTS-SAME: "statementDeletionSourceLocationMisses":"0"
// EVENTS-SAME: "statementDeletionNonStatementSourceLocations":"0"
// EVENTS: "event":"metamutantInjection","module":"SwiftmutStatementDeletionUnusedResultRuntime","function":"{{.*}}swiftmutInvoke
// EVENTS-SAME: "attemptedStatementDeletionSites":"1"
// EVENTS-SAME: "injectedStatementDeletionSites":"1"
// EVENTS: "event":"metamutantDiscovery","module":"SwiftmutStatementDeletionUnusedResultRuntime","function":"{{.*}}swiftmutDoNotInstrumentNoReturn
// EVENTS-SAME: "statementDeletionSites":"0"
// EVENTS-SAME: "statementDeletionApplyInstructions":"1"
// EVENTS-SAME: "statementDeletionUnusedResultApplyInstructions":"1"
// EVENTS-SAME: "statementDeletionMutationEligibleApplyInstructions":"0"
// EVENTS: "event":"metamutantDiscovery","module":"SwiftmutStatementDeletionUnusedResultRuntime","function":"{{.*}}swiftmutDiscard{{.*}}InCase
// EVENTS-SAME: "statementDeletionSites":"1"
// EVENTS-SAME: "statementDeletionApplyInstructions":"1"
// EVENTS-SAME: "statementDeletionUnusedResultApplyInstructions":"1"
// EVENTS-SAME: "statementDeletionMutationEligibleApplyInstructions":"1"
// EVENTS-SAME: "statementDeletionNonStatementSourceLocations":"0"
// EVENTS: "event":"metamutantDiscovery","module":"SwiftmutStatementDeletionUnusedResultRuntime","function":"{{.*}}swiftmutDiscard{{.*}}AcrossLines
// EVENTS-SAME: "statementDeletionSites":"1"
// EVENTS-SAME: "statementDeletionApplyInstructions":"1"
// EVENTS-SAME: "statementDeletionUnusedResultApplyInstructions":"1"
// EVENTS-SAME: "statementDeletionMutationEligibleApplyInstructions":"1"
// EVENTS-SAME: "statementDeletionNonStatementSourceLocations":"0"
// MANIFEST-NOT: "line":32
// MANIFEST-DAG: "function":"{{.*}}swiftmutInvoke{{.*}}","sourceLocation":{{.*}}"siteKind":"statementDeletion","resultKind":"statement"
// MANIFEST-DAG: "function":"{{.*}}swiftmutDiscard{{.*}}InCase{{.*}}","sourceLocation":{{.*}}main.swift","line":33,"column":13{{.*}},"siteKind":"statementDeletion","resultKind":"statement"
// MANIFEST-DAG: "function":"{{.*}}swiftmutDiscard{{.*}}AcrossLines{{.*}}","sourceLocation":{{.*}}main.swift","line":49,"column":6{{.*}},"siteKind":"statementDeletion","resultKind":"statement"
// MANIFEST: "mutator":"STATEMENT_DELETIONS"
// MANIFEST-SAME: "sourceOriginal":"call"
// MANIFEST-SAME: "sourceMutated":"removed call"
// MANIFEST-NOT: "line":32

//--- main.swift
public var swiftmutObserved = 0

@discardableResult
@inline(never)
public func swiftmutRecordAndReturn(_ value: Int) -> Int {
  swiftmutObserved = value
  return value
}

@inline(never)
public func swiftmutInvoke() {
  swiftmutRecordAndReturn(2)
}

@inline(never)
public func swiftmutAbort() -> Never {
  fatalError("not called")
}

@inline(never)
public func swiftmutDoNotInstrumentNoReturn() {
  swiftmutAbort()
}

public enum SwiftmutPayload {
  case number(Int)
}

@inline(never)
public func swiftmutDiscardResultInCase(_ payload: SwiftmutPayload) {
  switch payload {
  case .number(let value):
    let _ = swiftmutRecordAndReturn(value)
  }
}

public struct SwiftmutReceiver {
  public let value: Int

  @inline(never)
  public func result() -> Int {
    value
  }
}

@inline(never)
public func swiftmutDiscardResultAcrossLines(_ receiver: SwiftmutReceiver) {
  _ = receiver
    .result()
}

@_silgen_name("__swiftmut_visit")
public func __swiftmut_visit(_ siteID: UInt64) -> UInt32 {
#if SWIFTMUT_BASELINE
  0
#else
  1
#endif
}

swiftmutObserved = 1
swiftmutInvoke()
print(swiftmutObserved)
