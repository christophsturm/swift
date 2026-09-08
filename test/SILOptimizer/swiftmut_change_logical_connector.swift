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
// RUN: %{python} %S/Inputs/swiftmut-check-logical-ranges.py %t/all-fragments.json '[[41,7],[42,7],[50,7],[51,7],[62,17],[62,31],[76,9],[76,19],[76,28],[88,16],[88,35],[88,56]]'
// RUN: %FileCheck %s --check-prefix=EVENTS --input-file %t/compiler-events.jsonl

@_silgen_name("__swiftmut_visit")
public func __swiftmut_visit(_ siteID: UInt64) -> UInt32 {
  0
}

// The MutationResultClassifier shape: a multiline disjunction whose chain
// branches carry no ordinary file position. A branch may also be a condition
// site, but every operator-prefixed source description must still become its
// own CHANGE_LOGICAL_CONNECTOR site.
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

// Compiler descriptions for an inline connector begin at the operator, not
// at the beginning of the physical source line. An identical string literal
// must not consume the source occurrence.
public func swiftmutInlineConnector(_ byte: UInt8, _ next: UInt8) -> Bool {
  _ = "&& next != 0 {"
  if byte == 35 && next == 42 && next != 0 {
    return true
  }
  return false
}

// Each branch in a longer conjunction must retain the identity of the
// connector it actually changes, even when the whole expression is inline.
public func swiftmutConnectorIdentityChain(
  _ first: Bool,
  _ second: Bool,
  _ third: Bool,
  _ fourth: Bool
) -> Bool {
  first && second && third && fourth
}

// An optional comparison reaches the first connector through a multi-block
// equality implementation. All three connectors must still retain their own
// source identities.
public func swiftmutOptionalConnectorIdentity(
  _ quote: UInt8?,
  _ parenDepth: Int,
  _ bracketDepth: Int,
  _ braceDepth: Int
) -> Bool {
  quote == nil && parenDepth == 0 && bracketDepth == 0 && braceDepth == 0
}

// EVENTS-DAG: "function":"{{.*}}swiftmutClassifierShape{{.*}}"logicalConnectorSites":"2"
// EVENTS-DAG: "function":"{{.*}}swiftmutConjunctionChain{{.*}}"logicalConnectorSites":"2"
// EVENTS-DAG: "function":"{{.*}}swiftmutInline{{.*}}"logicalConnectorSites":"2"
// EVENTS-DAG: "function":"{{.*}}swiftmutD13IdentityChain{{.*}}"logicalConnectorSites":"3"
// EVENTS-DAG: "function":"{{.*}}swiftmutOptionalD8Identity{{.*}}"logicalConnectorSites":"3"{{.*}}"logicalConnectorDiamondBranches":"3"
// Optimized short-circuit expressions retain transparent autoclosure bodies
// after their uses have been inlined. An unreferenced retained copy is not an
// executable source site.
// EVENTS-DAG: "event":"functionSkip","reason":"generatedUnreferencedClosure","module":"SwiftmutChangeLogicalConnector","function":"{{.*}}KXEfu{{.*}}"
