// RUN: rm -rf %t
// RUN: mkdir -p %t
// RUN: printf '%%s\n' '---' "name: ''" 'passes: [ "\"allocbox-to-stack\"", "\"lower-aggregate-instrs\"", "\"mem2reg\"", "\"performance-constant-propagation\"", "\"simplify-cfg\"", "\"condition-forwarding\"", "\"sil-combine\"", "\"simplify-cfg\"", "\"inline\"", "\"copy-propagation\"", "\"semantic-arc-opts\"", "\"copy-to-borrow-optimization\"", "\"mem2reg\"", "\"performance-constant-propagation\"", "\"jumpthread-simplify-cfg\"", "\"phi-expansion\"", "\"sil-combine\"", "\"simplify-cfg\"", "\"cse\"", "\"dce\"", "\"string-optimization\"", "\"simplify-cfg\"", "\"swiftmut\"" ]' > %t/pipeline.yaml
// RUN: printf '%b\n' \
// RUN:   '{' \
// RUN:   '  "mode": "metamutant",' \
// RUN:   '  "manifestPath": "%t/mutants.jsonl",' \
// RUN:   '  "manifestFragmentsDirectory": "%t/fragments",' \
// RUN:   '  "compilerEventsPath": "%t/compiler-events.jsonl",' \
// RUN:   '  "packageRoot": "%S",' \
// RUN:   '  "excludePaths": [],' \
// RUN:   '  "sourceFiles": ["%s"],' \
// RUN:   '  "enabledMutators": ["CHANGE_LOGICAL_CONNECTOR", "EMPTY_RETURNS"],' \
// RUN:   '  "conditionMutationRules": [],' \
// RUN:   '  "arithmeticMutationRules": [],' \
// RUN:   '  "contextualArithmeticMutationRules": [],' \
// RUN:   '  "returnMutationRules": ["optionalToNil|EMPTY_RETURNS|return_nil|return|return nil|Optional.none"],' \
// RUN:   '  "voidCallMutationRules": [],' \
// RUN:   '  "sourceMutationDisplayRules": []' \
// RUN:   '}' > %t/config.json
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -emit-ir -O -swift-version 6 -module-name SwiftmutChangeLogicalConnectorLadder -external-pass-pipeline-filename %t/pipeline.yaml %s -o /dev/null
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

// String equality inside a mixed short-circuit expression optimizes into a
// fast-path/slow-path CFG that resembles a logical ladder. The fast-path
// condition does not dominate the shared slow-path branch, so it must not be
// instrumented as a connector. The Optional call also exercises an earlier
// value-site CFG split before logical-connector injection.
public func swiftmutMixedLadderShape(
  _ isConversationRunning: Bool,
  _ isBackendReady: Bool,
  _ status: String,
  _ preparationLabel: String?
) -> String? {
  let effectivePreparationLabel =
    preparationLabel ?? swiftmutPreparationLabel(status, isReady: isBackendReady)
  let message = isConversationRunning
    || (!isBackendReady && status == "Idle" && effectivePreparationLabel == nil)
    ? nil : status
  return message
}

@inline(never)
public func swiftmutPreparationLabel(_ status: String, isReady: Bool) -> String? {
  isReady ? nil : status
}

// CHECK-DAG: "sourceLocation":{"file":"swiftmut_change_logical_connector_ladder.swift","line":38,"column":7},"siteKind":"logicalConnector","resultKind":"condition","alternatives":[{"mutantID":"{{[^"]*}}","alternativeIndex":1,"mutator":"CHANGE_LOGICAL_CONNECTOR","sourceOriginal":"||","sourceMutated":"&&"
// CHECK-DAG: "sourceLocation":{"file":"swiftmut_change_logical_connector_ladder.swift","line":39,"column":7},"siteKind":"logicalConnector","resultKind":"condition","alternatives":[{"mutantID":"{{[^"]*}}","alternativeIndex":1,"mutator":"CHANGE_LOGICAL_CONNECTOR","sourceOriginal":"||","sourceMutated":"&&"

// EVENTS-DAG: "function":"{{.*}}swiftmutChainShape{{.*}}"logicalConnectorSites":"2"
// EVENTS-DAG: "function":"{{.*}}swiftmutMixed{{.*}}Shape{{.*}}"{{.*}}"logicalConnectorSites":"0"{{.*}}"logicalConnectorNonDominatingLadderPairBranches":"1"
