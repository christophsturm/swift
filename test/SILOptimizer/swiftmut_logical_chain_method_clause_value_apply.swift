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
// RUN:   '  "enabledMutators": ["FALSE_RETURNS", "TRUE_RETURNS"],' \
// RUN:   '  "conditionMutationRules": [],' \
// RUN:   '  "arithmeticMutationRules": [],' \
// RUN:   '  "contextualArithmeticMutationRules": [],' \
// RUN:   '  "returnMutationRules": [' \
// RUN:   '    "boolToFalse|FALSE_RETURNS|return_false|return|return false|false",' \
// RUN:   '    "boolToTrue|TRUE_RETURNS|return_true|return|return true|true"' \
// RUN:   '  ],' \
// RUN:   '  "voidCallMutationRules": [],' \
// RUN:   '  "sourceMutationDisplayRules": []' \
// RUN:   '}' > %t/config.json
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -emit-sil -O -module-name SwiftmutLogicalChainMethodClauseValueApply %s -o /dev/null
// RUN: find %t/fragments -type f -name '*.json' -exec cat {} ';' | %{python} %S/Inputs/swiftmut-render-condition-ranges.py %S > %t/all-fragments.json
// RUN: %FileCheck %s --input-file %t/all-fragments.json
// RUN: %FileCheck %s --check-prefix=EVENTS --input-file %t/compiler-events.jsonl

@_silgen_name("__swiftmut_visit")
public func __swiftmut_visit(_ siteID: UInt64) -> UInt32 {
  0
}

// The MutationResultClassifier shape: a multiline disjunction of method
// calls on a local String. The chain clauses after the first are autoclosure
// right-hand sides whose applies take an owned receiver, so they cannot be
// bypassed; the mutation must keep the call and replace only its result.
public func swiftmutClassifierShape(_ stdout: String, _ stderr: String) -> Int {
  let combinedOutput = stdout + "\n" + stderr
  if combinedOutput.contains("compilation failed")
      || combinedOutput.contains("compile command failed")
      || combinedOutput.contains("no such module") {
    return 1
  }
  return 2
}

// CHECK-DAG: "siteKind":"valueApply"{{.*}}"sourceOriginal":"combinedOutput.contains(\"compile command failed\")","sourceMutated":"false"{{.*}}"sourceOriginal":"combinedOutput.contains(\"compile command failed\")","sourceMutated":"true"
// CHECK-DAG: "siteKind":"valueApply"{{.*}}"sourceOriginal":"combinedOutput.contains(\"no such module\")","sourceMutated":"false"{{.*}}"sourceOriginal":"combinedOutput.contains(\"no such module\")","sourceMutated":"true"

// EVENTS: "event":"metamutantDiscovery","module":"SwiftmutLogicalChainMethodClauseValueApply","function":"{{.*}}swiftmutClassifierShape
// EVENTS-SAME: "valueApplySites":"2"
