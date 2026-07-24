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
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-build-swift -O %t/main.swift -module-name SwiftmutSetterCallOwnedArgumentRuntime -Xfrontend -external-pass-pipeline-filename -Xfrontend %t/pipeline.yaml -o %t/a.out
// RUN: %target-codesign %t/a.out
// RUN: %target-run %t/a.out | %FileCheck %s
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-build-swift -O -D SWIFTMUT_BASELINE %t/main.swift -module-name SwiftmutSetterCallOwnedArgumentRuntime -Xfrontend -external-pass-pipeline-filename -Xfrontend %t/pipeline.yaml -o %t/baseline.out
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
// EVENTS-SAME: "voidCallSites":"1"
// EVENTS-SAME: "voidCallVoidApplyInstructions":"1"
// EVENTS-SAME: "voidCallMutationEligibleApplyInstructions":"1"
// EVENTS-SAME: "voidCallSourceLocationMisses":"0"
// EVENTS-SAME: "voidCallNonStatementSourceLocations":"0"
// EVENTS: "event":"metamutantInjection","module":"SwiftmutSetterCallOwnedArgumentRuntime","function":"{{.*}}swiftmutInvoke
// EVENTS-SAME: "attemptedVoidCallSites":"1"
// EVENTS-SAME: "injectedVoidCallSites":"1"
// MANIFEST-NOT: "siteKind":"voidCall"
// MANIFEST: "function":"{{.*}}swiftmutInvoke{{.*}}","sourceLocation":{{.*}}"siteKind":"voidCall"
// MANIFEST-SAME: "mutator":"VOID_METHOD_CALLS"
// MANIFEST-SAME: "sourceOriginal":"SwiftmutToken(value: 2)"
// MANIFEST-SAME: "sourceMutated":"removed call"
// MANIFEST-NOT: "siteKind":"voidCall"

//--- main.swift
public var swiftmutObserved = 0
public var swiftmutDeinitCount = 0

public final class SwiftmutToken {
  public let value: Int

  public init(value: Int) {
    self.value = value
  }

  deinit {
    swiftmutDeinitCount += 1
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
