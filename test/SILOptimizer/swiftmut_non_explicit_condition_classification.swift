// RUN: rm -rf %t
// RUN: mkdir -p %t
// RUN: printf '%%s\n' '---' "name: ''" 'passes: [ "\"swiftmut\"" ]' > %t/pipeline.yaml
// RUN: printf '%b\n' \
// RUN:   '{' \
// RUN:   '  "mode": "metamutant",' \
// RUN:   '  "manifestPath": "%t/mutants.jsonl",' \
// RUN:   '  "manifestFragmentsDirectory": "%t/fragments",' \
// RUN:   '  "compilerEventsPath": "%t/compiler-events.jsonl",' \
// RUN:   '  "packageRoot": "%S",' \
// RUN:   '  "excludePaths": [],' \
// RUN:   '  "sourceFiles": ["%s"],' \
// RUN:   '  "enabledMutators": ["CONDITION_FALSE", "CONDITION_TRUE"],' \
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
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -emit-sil -O -module-name SwiftmutNonExplicitConditionClassification -external-pass-pipeline-filename %t/pipeline.yaml %s -o /dev/null
// RUN: find %t/fragments -type f -name '*.json' -exec cat {} ';' > %t/all-fragments.json
// RUN: %FileCheck %s --input-file %t/all-fragments.json
// RUN: %FileCheck %s --check-prefix=EVENTS --input-file %t/compiler-events.jsonl

public struct SwiftmutClassifierProcessResult {
  public let exitCode: Int
  public let timedOut: Bool
  public let stdout: String
  public let stderr: String

  public init(exitCode: Int, timedOut: Bool, stdout: String, stderr: String) {
    self.exitCode = exitCode
    self.timedOut = timedOut
    self.stdout = stdout
    self.stderr = stderr
  }
}

public enum SwiftmutClassifierMode {
  case buildOnly
  case test
}

public enum SwiftmutClassifierStatus {
  case timeout
  case compiled
  case survived
  case invalid
  case killed
}

public func swiftmutClassify(_ result: SwiftmutClassifierProcessResult, mode: SwiftmutClassifierMode) -> SwiftmutClassifierStatus {
  if result.timedOut {
    return .timeout
  }
  if result.exitCode == 0 {
    if mode == .buildOnly {
      return .compiled
    }
    return .survived
  }
  let combinedOutput = result.stdout + "\n" + result.stderr
  if combinedOutput.contains("compilation failed")
      || combinedOutput.contains("compile command failed")
      || combinedOutput.contains("error: fatalError")
      || combinedOutput.contains("Usage: swift test") {
    return .invalid
  }
  return .killed
}

@_silgen_name("__swiftmut_visit")
public func __swiftmut_visit(_ siteID: UInt64) -> UInt32 {
  0
}

// CHECK: "sourceLocation":{"file":"swiftmut_non_explicit_condition_classification.swift","line":57,"column":6}
// CHECK-SAME: "siteKind":"condition"
// CHECK-SAME: "sourceOriginal":"result.timedOut","sourceMutated":"false"
// CHECK-SAME: "sourceOriginal":"result.timedOut","sourceMutated":"true"
// CHECK: "sourceLocation":{"file":"swiftmut_non_explicit_condition_classification.swift","line":60,"column":6}
// CHECK-SAME: "siteKind":"condition"
// CHECK-SAME: "sourceOriginal":"result.exitCode == 0","sourceMutated":"false"
// CHECK-SAME: "sourceOriginal":"result.exitCode == 0","sourceMutated":"true"
// CHECK: "sourceLocation":{"file":"swiftmut_non_explicit_condition_classification.swift","line":61,"column":8}
// CHECK-SAME: "siteKind":"condition"
// CHECK-SAME: "sourceOriginal":"mode == .buildOnly","sourceMutated":"false"
// CHECK-SAME: "sourceOriginal":"mode == .buildOnly","sourceMutated":"true"
// CHECK: "sourceLocation":{"file":"swiftmut_non_explicit_condition_classification.swift","line":67,"column":6}
// CHECK-SAME: "siteKind":"condition"
// CHECK-SAME: "sourceOriginal":"combinedOutput.contains(\"compilation failed\")","sourceMutated":"false"
// CHECK-SAME: "sourceOriginal":"combinedOutput.contains(\"compilation failed\")","sourceMutated":"true"
// CHECK-NOT: "line":68
// CHECK-NOT: "line":69
// CHECK-NOT: "line":70

// EVENTS: "event":"metamutantDiscovery","module":"SwiftmutNonExplicitConditionClassification","function":"$s42SwiftmutNonExplicitConditionClassification16swiftmutClassify
// EVENTS-SAME: "conditionBranches":"7"
// EVENTS-SAME: "conditionSites":"4"
// EVENTS-SAME: "conditionSourceLocationMisses":"0"
// EVENTS-SAME: "conditionGenericNonExplicitSourceLocations":"0"
