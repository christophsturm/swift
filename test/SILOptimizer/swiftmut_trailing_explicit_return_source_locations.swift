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
// RUN:   '  "enabledMutators": ["FALSE_RETURNS"],' \
// RUN:   '  "conditionMutationRules": [],' \
// RUN:   '  "arithmeticMutationRules": [],' \
// RUN:   '  "contextualArithmeticMutationRules": [],' \
// RUN:   '  "returnMutationRules": [' \
// RUN:   '    "boolToFalse|FALSE_RETURNS|return_false|return|return false|false"' \
// RUN:   '  ],' \
// RUN:   '  "voidCallMutationRules": [],' \
// RUN:   '  "sourceMutationDisplayRules": []' \
// RUN:   '}' > %t/config.json
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -emit-sil -O -module-name SwiftmutTrailingExplicitReturnSourceLocations %s -o /dev/null
// RUN: cat %t/fragments/*.json | %{python} %S/Inputs/swiftmut-render-condition-ranges.py %S | %FileCheck %s
// RUN: %FileCheck %s --check-prefix=EVENTS --input-file %t/compiler-events.jsonl

public func swiftmutTrailingExplicitReturn(_ enabled: Bool, fallback: Bool) -> Bool {
  if fallback {
    return false
  }
  return enabled
}

// CHECK: "line":31,"column":10
// CHECK-SAME: "sourceOriginal":"enabled","sourceMutated":"false"
// EVENTS: "event":"functionVisit"
// The shared SIL exit has two AST returns; only the nonconstant branch owns
// a replacement, so activation cannot affect both source returns.
// EVENTS: "event":"metamutantDiscovery"
// EVENTS-SAME: "returnSites":"0"
// EVENTS-SAME: "returnBranchSites":"1"
// EVENTS: "event":"metamutantInjection"
// EVENTS-SAME: "injectedReturnBranchSites":"1"
