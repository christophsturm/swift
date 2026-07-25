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
// RUN:   '  "enabledMutators": ["NULL_RETURNS"],' \
// RUN:   '  "conditionMutationRules": [],' \
// RUN:   '  "arithmeticMutationRules": [],' \
// RUN:   '  "contextualArithmeticMutationRules": [],' \
// RUN:   '  "returnMutationRules": [' \
// RUN:   '    "optionalToNil|NULL_RETURNS|return_nil|return|return nil|nil"' \
// RUN:   '  ],' \
// RUN:   '  "voidCallMutationRules": [],' \
// RUN:   '  "statementMutationRules": [],' \
// RUN:   '  "sourceMutationDisplayRules": []' \
// RUN:   '}' > %t/config.json
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-build-swift -O %t/main.swift -module-name SwiftmutNontrivialReturnBranchRuntime -Xfrontend -external-pass-pipeline-filename -Xfrontend %t/pipeline.yaml -o %t/a.out
// RUN: %target-codesign %t/a.out
// RUN: %target-run %t/a.out | %FileCheck %s
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-build-swift -O -D SWIFTMUT_BASELINE %t/main.swift -module-name SwiftmutNontrivialReturnBranchRuntime -Xfrontend -external-pass-pipeline-filename -Xfrontend %t/pipeline.yaml -o %t/baseline.out
// RUN: %target-codesign %t/baseline.out
// RUN: %target-run %t/baseline.out | %FileCheck %s --check-prefix=BASELINE
// RUN: %FileCheck %s --check-prefix=EVENTS --input-file %t/compiler-events.jsonl
// RUN: find %t/fragments -type f -name '*.json' -exec cat {} ';' | sort -u > %t/all-fragments.json
// RUN: %FileCheck %s --check-prefix=MANIFEST --input-file %t/all-fragments.json

// CHECK: true
// CHECK-NEXT: 1
// CHECK-NEXT: 1
// BASELINE: false
// BASELINE-NEXT: 1
// BASELINE-NEXT: 1
// EVENTS: "event":"metamutantDiscovery","module":"SwiftmutNontrivialReturnBranchRuntime","function":"{{.*}}swiftmutChoose
// EVENTS-SAME: "returnSites":"0"
// EVENTS-SAME: "returnBranchSites":"1"
// EVENTS-SAME: "returnBranchMutationEligibleBranches":"1"
// EVENTS-SAME: "returnBranchMutationAlternatives":"1"
// EVENTS-SAME: "returnBranchSourceLocationMisses":"0"
// EVENTS: "event":"metamutantInjection","module":"SwiftmutNontrivialReturnBranchRuntime","function":"{{.*}}swiftmutChoose
// EVENTS-SAME: "attemptedReturnBranchSites":"1"
// EVENTS-SAME: "injectedReturnBranchSites":"1"
// MANIFEST: "siteKind":"returnBranchValue"
// MANIFEST-SAME: "sourceOriginal":"SwiftmutToken()"
// MANIFEST-SAME: "sourceMutated":"nil"

//--- main.swift
public var swiftmutDeinitCount = 0
public var swiftmutVisitCount = 0

public final class SwiftmutToken {
  deinit {
    swiftmutDeinitCount += 1
  }
}

@inline(never)
public func swiftmutChoose(_ flag: Bool) -> SwiftmutToken? {
  if flag {
    return SwiftmutToken()
  }
  return nil
}

@_silgen_name("__swiftmut_visit")
public func __swiftmut_visit(_ siteID: UInt64) -> UInt32 {
  swiftmutVisitCount += 1
#if SWIFTMUT_BASELINE
  return 0
#else
  return swiftmutVisitCount == 1 ? 1 : 0
#endif
}

do {
  let result = swiftmutChoose(true)
  print(result == nil)
}
print(swiftmutDeinitCount)
print(swiftmutVisitCount)
