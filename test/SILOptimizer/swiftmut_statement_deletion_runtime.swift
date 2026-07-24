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
// RUN:   '    "assignment|STATEMENT_DELETIONS|remove_assignment|assignment|removed assignment|removed"' \
// RUN:   '  ],' \
// RUN:   '  "sourceMutationDisplayRules": []' \
// RUN:   '}' > %t/config.json
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-build-swift -O %t/main.swift -module-name SwiftmutStatementDeletionRuntime -Xfrontend -external-pass-pipeline-filename -Xfrontend %t/pipeline.yaml -o %t/a.out
// RUN: %target-codesign %t/a.out
// RUN: %target-run %t/a.out | %FileCheck %s
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-build-swift -O -D SWIFTMUT_BASELINE %t/main.swift -module-name SwiftmutStatementDeletionRuntime -Xfrontend -external-pass-pipeline-filename -Xfrontend %t/pipeline.yaml -o %t/baseline.out
// RUN: %target-codesign %t/baseline.out
// RUN: %target-run %t/baseline.out | %FileCheck %s --check-prefix=BASELINE
// RUN: %FileCheck %s --check-prefix=EVENTS --input-file %t/compiler-events.jsonl
// RUN: find %t/fragments -type f -name '*.json' -exec cat {} ';' | sort -u > %t/all-fragments.json
// RUN: %FileCheck %s --check-prefix=MANIFEST --input-file %t/all-fragments.json

// CHECK: before
// BASELINE: after
// EVENTS: "event":"metamutantDiscovery","module":"SwiftmutStatementDeletionRuntime","function":"{{.*}}swiftmutUpdate
// EVENTS-SAME: "statementDeletionSites":"1"
// EVENTS-SAME: "statementDeletionAssignmentStoreInstructions":"1"
// EVENTS-SAME: "statementDeletionMutationEligibleInstructions":"1"
// EVENTS-SAME: "statementDeletionSourceLocationMisses":"0"
// EVENTS: "event":"metamutantInjection","module":"SwiftmutStatementDeletionRuntime","function":"{{.*}}swiftmutUpdate
// EVENTS-SAME: "attemptedStatementDeletionSites":"1"
// EVENTS-SAME: "injectedStatementDeletionSites":"1"
// MANIFEST-NOT: "siteKind":"statementDeletion"
// MANIFEST: "function":"{{.*}}swiftmutUpdate{{.*}}","sourceLocation":{{.*}}"siteKind":"statementDeletion"
// MANIFEST-SAME: "resultKind":"statement"
// MANIFEST-SAME: "mutator":"STATEMENT_DELETIONS"
// MANIFEST-SAME: "sourceOriginal":"replacement"
// MANIFEST-SAME: "sourceMutated":"removed assignment"
// MANIFEST-NOT: "siteKind":"statementDeletion"

//--- main.swift
public final class SwiftmutBox {
  public var value: String

  public init(_ value: String) {
    self.value = value
  }
}

@inline(never)
public func swiftmutUpdate(_ box: SwiftmutBox, replacement: String) {
  box.value = replacement
}

@_silgen_name("__swiftmut_visit")
public func __swiftmut_visit(_ siteID: UInt64) -> UInt32 {
#if SWIFTMUT_BASELINE
  0
#else
  1
#endif
}

let box = SwiftmutBox("before")
swiftmutUpdate(box, replacement: "after")
print(box.value)
