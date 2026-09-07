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
// RUN:   '    "assignment|STATEMENT_DELETIONS|remove_assignment|assignment|removed assignment|removed",' \
// RUN:   '    "unusedCall|STATEMENT_DELETIONS|remove_unused_call|call|removed call|removed"' \
// RUN:   '  ],' \
// RUN:   '  "sourceMutationDisplayRules": []' \
// RUN:   '}' > %t/config.json
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-build-swift -O %t/main.swift %t/Support.swift -module-name SwiftmutSetterCallOwnedArgumentRuntime -o %t/a.out
// RUN: %target-codesign %t/a.out
// RUN: %target-run %t/a.out | %FileCheck %s
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-build-swift -O -D SWIFTMUT_BASELINE %t/main.swift %t/Support.swift -module-name SwiftmutSetterCallOwnedArgumentRuntime -o %t/baseline.out
// RUN: %target-codesign %t/baseline.out
// RUN: %target-run %t/baseline.out | %FileCheck %s --check-prefix=BASELINE
// RUN: %FileCheck %s --check-prefix=EVENTS --input-file %t/compiler-events.jsonl
// RUN: find %t/fragments -type f -name '*.json' -exec cat {} ';' | sort -u > %t/all-fragments.json
// RUN: %FileCheck %s --check-prefix=MANIFEST --input-file %t/all-fragments.json

// CHECK: 0
// CHECK-NEXT: 1
// BASELINE: 2
// BASELINE-NEXT: 1
// EVENTS: "event":"metamutantDiscovery","module":"SwiftmutSetterCallOwnedArgumentRuntime","function":"{{.*}}swiftmutInvoke
// EVENTS-SAME: "voidCallSites":"0"
// EVENTS-SAME: "statementDeletionSites":"1"
// EVENTS-SAME: "statementDeletionApplyInstructions":"3"
// EVENTS-SAME: "statementDeletionSetterApplyInstructions":"1"
// EVENTS-SAME: "statementDeletionMutationEligibleApplyInstructions":"1"
// EVENTS-SAME: "statementDeletionSourceLocationMisses":"0"
// EVENTS-SAME: "statementDeletionNonStatementSourceLocations":"0"
// EVENTS: "event":"metamutantInjection","module":"SwiftmutSetterCallOwnedArgumentRuntime","function":"{{.*}}swiftmutInvoke
// EVENTS-SAME: "attemptedStatementDeletionSites":"1"
// EVENTS-SAME: "injectedStatementDeletionSites":"1"
// MANIFEST-NOT: "siteKind":"statementDeletion"
// MANIFEST: "function":"{{.*}}swiftmutInvoke{{.*}}","sourceLocation":{{.*}}"siteKind":"statementDeletion"
// MANIFEST-SAME: "mutator":"STATEMENT_DELETIONS"
// MANIFEST-SAME: "sourceOriginal":"assignment"
// MANIFEST-SAME: "sourceMutated":"removed assignment"
// MANIFEST-SAME: "operation":"removeAssignment"
// MANIFEST-SAME: "sourceSpan":
// MANIFEST-NOT: "siteKind":"statementDeletion"

//--- main.swift
public var swiftmutObserved = 0
public var swiftmutDeinitCount = 0

public final class SwiftmutToken {
  public let value: Int

  public init(value: Int) {
    self.value = value
  }

  deinit {
    swiftmutRecordDeinit()
  }
}

public final class SwiftmutSink {
  public var token: SwiftmutToken {
    @inline(never)
    get {
      fatalError("not called")
    }
    @inline(never)
    set {
      swiftmutObserved = newValue.value
    }
  }
}

@propertyWrapper
public struct SwiftmutPublished<Value> {
  public var wrappedValue: Value

  public init(wrappedValue: Value) {
    self.wrappedValue = wrappedValue
  }
}

public protocol SwiftmutModeSink {
  var mode: Int { get set }
}

public final class SwiftmutWrappedSink: SwiftmutModeSink {
  @SwiftmutPublished public var mode: Int = 1
}

@inline(never)
public func swiftmutInvoke() {
  let sink = SwiftmutSink()
  sink.token = SwiftmutToken(value: 2)
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
print(swiftmutDeinitCount)

//--- Support.swift
// Keep test accounting outside the configured mutation sources.
@inline(never)
public func swiftmutRecordDeinit() {
  swiftmutDeinitCount += 1
}
