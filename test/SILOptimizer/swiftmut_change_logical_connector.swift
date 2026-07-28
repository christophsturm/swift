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
// RUN:   '  "enabledMutators": ["CHANGE_LOGICAL_CONNECTOR", "CONDITION_FALSE", "CONDITION_TRUE"],' \
// RUN:   '  "conditionMutationRules": [' \
// RUN:   '    "COMPARISON|CONDITION_FALSE|condition_false|condition|false",' \
// RUN:   '    "COMPARISON|CONDITION_TRUE|condition_true|condition|true"' \
// RUN:   '  ],' \
// RUN:   '  "arithmeticMutationRules": [],' \
// RUN:   '  "contextualArithmeticMutationRules": [],' \
// RUN:   '  "returnMutationRules": [],' \
// RUN:   '  "voidCallMutationRules": [],' \
// RUN:   '  "sourceMutationDisplayRules": []' \
// RUN:   '}' > %t/config.json
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -emit-sil -O -module-name SwiftmutChangeLogicalConnector %s -o /dev/null
// RUN: find %t/fragments -type f -name '*.json' -exec cat {} ';' > %t/all-fragments.json
// RUN: %FileCheck %s --input-file %t/all-fragments.json
// RUN: %FileCheck %s --check-prefix=EVENTS --input-file %t/compiler-events.jsonl

@_silgen_name("__swiftmut_visit")
public func __swiftmut_visit(_ siteID: UInt64) -> UInt32 {
  0
}

// The MutationResultClassifier shape: a multiline disjunction whose chain
// branches carry no per-clause source location. The first clause's branch
// is owned by the condition mutator; each later connector becomes a
// CHANGE_LOGICAL_CONNECTOR site.
public func swiftmutClassifierShape(_ stdout: String, _ stderr: String) -> Int {
  let combinedOutput = stdout + "\n" + stderr
  if combinedOutput.contains("compilation failed")
      || combinedOutput.contains("compile command failed")
      || combinedOutput.contains("no such module") {
    return 1
  }
  return 2
}

public func swiftmutConjunctionChain(_ text: String) -> Int {
  if text.hasPrefix("@")
      && text.hasSuffix("!")
      && text.contains("#") {
    return 1
  }
  return 0
}

// CHECK-DAG: "sourceLocation":{"file":"swiftmut_change_logical_connector.swift","line":42,{{.*}}"siteKind":"logicalConnector"{{.*}}"sourceOriginal":"||","sourceMutated":"&&"
// CHECK-DAG: "sourceLocation":{"file":"swiftmut_change_logical_connector.swift","line":51,{{.*}}"siteKind":"logicalConnector"{{.*}}"sourceOriginal":"&&","sourceMutated":"||"

// EVENTS-DAG: "function":"{{.*}}swiftmutClassifierShape{{.*}}"logicalConnectorSites":"1"
// EVENTS-DAG: "function":"{{.*}}swiftmutConjunctionChain{{.*}}"logicalConnectorSites":"1"
