// RUN: rm -rf %t
// RUN: mkdir -p %t
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
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -emit-ir -O -swift-version 6 -module-name SwiftmutChangeLogicalConnectorLadder %s -o /dev/null
// RUN: find %t/fragments -type f -name '*.json' -exec cat {} ';' > %t/all-fragments.json
// RUN: %{python} %S/Inputs/swiftmut-check-logical-ranges.py %t/all-fragments.json '[[36,7],[37,7]]'
// RUN: %FileCheck %s --check-prefix=EVENTS --input-file %t/compiler-events.jsonl

@_silgen_name("__swiftmut_visit")
public func __swiftmut_visit(_ siteID: UInt64) -> UInt32 {
  0
}

// The common mandatory pipeline represents these source connectors as
// short-circuit diamonds. Both source operators remain independently
// discoverable before optimization-specific lowering begins.
public func swiftmutChainShape(_ stdout: String, _ stderr: String) -> Int {
  let combinedOutput = stdout + "\n" + stderr
  if combinedOutput.contains("compilation failed")
      || combinedOutput.contains("compile command failed")
      || combinedOutput.contains("no such module") {
    return 1
  }
  return 2
}

// A mixed short-circuit expression contains compiler-generated control flow
// whose outer source span cannot be proven at the common hook. It must not be
// misclassified as another source connector. The Optional call also exercises
// an earlier value-site CFG split before logical-connector injection.
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

// EVENTS-DAG: "function":"{{.*}}swiftmutChainShape{{.*}}"logicalConnectorSites":"2"
// EVENTS-DAG: "function":"{{.*}}swiftmutMixed{{.*}}Shape{{.*}}"{{.*}}"logicalConnectorSites":"0"{{.*}}"logicalConnectorSourceLocationMisses":"1"
