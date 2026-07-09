// RUN: rm -rf %t
// RUN: mkdir -p %t
// RUN: printf '%b\n' '---' "name: ''" 'passes: [ "\"mem2reg\"", "\"simplify-cfg\"", "\"condition-forwarding\"", "\"phi-expansion\"", "\"sil-combine\"", "\"simplify-cfg\"", "\"condition-forwarding\"", "\"swiftmut\"" ]' > %t/pipeline.yaml
// RUN: printf '%b\n' \
// RUN:   '{' \
// RUN:   '  "mode": "metamutant",' \
// RUN:   '  "manifestPath": "%t/mutants.jsonl",' \
// RUN:   '  "manifestFragmentsDirectory": "%t/fragments",' \
// RUN:   '  "compilerEventsPath": "%t/compiler-events.jsonl",' \
// RUN:   '  "packageRoot": "%S",' \
// RUN:   '  "excludePaths": [],' \
// RUN:   '  "sourceFiles": ["%s"],' \
// RUN:   '  "enabledMutators": ["CHANGE_LOGICAL_CONNECTOR"],' \
// RUN:   '  "conditionMutationRules": [],' \
// RUN:   '  "arithmeticMutationRules": [],' \
// RUN:   '  "contextualArithmeticMutationRules": [],' \
// RUN:   '  "returnMutationRules": [],' \
// RUN:   '  "voidCallMutationRules": [],' \
// RUN:   '  "sourceMutationDisplayRules": []' \
// RUN:   '}' > %t/config.json
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -emit-sil -O -module-name SwiftmutChangeLogicalConnectorLadder -external-pass-pipeline-filename %t/pipeline.yaml %s -o /dev/null
// RUN: find %t/fragments -type f -name '*.json' -exec cat {} ';' > %t/all-fragments.json
// RUN: %FileCheck %s --input-file %t/all-fragments.json
// RUN: %FileCheck %s --check-prefix=EVENTS --input-file %t/compiler-events.jsonl

@_silgen_name("__swiftmut_visit")
public func __swiftmut_visit(_ siteID: UInt64) -> UInt32 {
  0
}

// The fully optimized pipeline lowers || chains to branch ladders: each
// clause branches through a cleanup trampoline to the shared then-target,
// or falls through to the next clause. Every consecutive rung pair is a
// connector.
public func swiftmutChainShape(_ stdout: String, _ stderr: String) -> Int {
  let combinedOutput = stdout + "\n" + stderr
  if combinedOutput.contains("compilation failed")
      || combinedOutput.contains("compile command failed")
      || combinedOutput.contains("no such module") {
    return 1
  }
  return 2
}

// CHECK-DAG: "sourceLocation":{"file":"swiftmut_change_logical_connector_ladder.swift","line":38,"column":7},"siteKind":"logicalConnector","resultKind":"condition","alternatives":[{"mutantID":"{{[^"]*}}","alternativeIndex":1,"mutator":"CHANGE_LOGICAL_CONNECTOR","sourceOriginal":"||","sourceMutated":"&&"
// CHECK-DAG: "sourceLocation":{"file":"swiftmut_change_logical_connector_ladder.swift","line":39,"column":7},"siteKind":"logicalConnector","resultKind":"condition","alternatives":[{"mutantID":"{{[^"]*}}","alternativeIndex":1,"mutator":"CHANGE_LOGICAL_CONNECTOR","sourceOriginal":"||","sourceMutated":"&&"

// EVENTS-DAG: "function":"{{.*}}swiftmutChainShape{{.*}}"logicalConnectorSites":"2"
