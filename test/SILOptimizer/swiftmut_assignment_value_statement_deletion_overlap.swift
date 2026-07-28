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
// RUN:   '  "enabledMutators": ["PRIMITIVE_RETURNS", "STATEMENT_DELETIONS"],' \
// RUN:   '  "conditionMutationRules": [],' \
// RUN:   '  "arithmeticMutationRules": [],' \
// RUN:   '  "contextualArithmeticMutationRules": [],' \
// RUN:   '  "returnMutationRules": [' \
// RUN:   '    "integerToZero|PRIMITIVE_RETURNS|return_zero|return|return 0|0"' \
// RUN:   '  ],' \
// RUN:   '  "voidCallMutationRules": [],' \
// RUN:   '  "statementMutationRules": [' \
// RUN:   '    "assignment|STATEMENT_DELETIONS|remove_assignment|assignment|removed assignment|removed"' \
// RUN:   '  ],' \
// RUN:   '  "sourceMutationDisplayRules": []' \
// RUN:   '}' > %t/config.json
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -emit-sil -Onone -module-name SwiftmutAssignmentValueStatementDeletionOverlap %s -o /dev/null
// RUN: %FileCheck %s --check-prefix=EVENTS --input-file %t/compiler-events.jsonl
// RUN: find %t/fragments -type f -name '*.json' -exec cat {} ';' > %t/all-fragments.json
// RUN: %FileCheck %s --check-prefix=MANIFEST --input-file %t/all-fragments.json

// EVENTS: "event":"metamutantDiscovery","module":"SwiftmutAssignmentValueStatementDeletionOverlap","function":"{{.*}}swiftmutReassign
// EVENTS-SAME: "assignmentValueSites":"1"
// EVENTS-SAME: "statementDeletionSites":"1"
// EVENTS: "event":"metamutantInjection","module":"SwiftmutAssignmentValueStatementDeletionOverlap","function":"{{.*}}swiftmutReassign
// EVENTS-SAME: "injectedAssignmentValueSites":"1"
// EVENTS-SAME: "injectedStatementDeletionSites":"1"
// MANIFEST-DAG: "siteKind":"assignmentValue"
// MANIFEST-DAG: "siteKind":"statementDeletion"

@inline(never)
public func swiftmutReassign(_ box: SwiftmutBox, replacement: Int) {
  box.value = replacement
}

public final class SwiftmutBox {
  public var value: Int

  public init(_ value: Int) {
    self.value = value
  }
}

@_silgen_name("__swiftmut_visit")
public func __swiftmut_visit(_ siteID: UInt64) -> UInt32 {
  0
}
