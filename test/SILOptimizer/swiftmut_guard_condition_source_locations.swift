// RUN: rm -rf %t
// RUN: mkdir -p %t
// RUN: printf '%b\n' '---' "name: ''" 'passes: [ "\"swiftmut\"" ]' > %t/pipeline.yaml
// RUN: printf '%b\n' \
// RUN:   '{' \
// RUN:   '  "mode": "metamutant",' \
// RUN:   '  "manifestPath": "%t/mutants.jsonl",' \
// RUN:   '  "manifestFragmentsDirectory": "%t/fragments",' \
// RUN:   '  "compilerEventsPath": "%t/compiler-events.jsonl",' \
// RUN:   '  "packageRoot": "%S",' \
// RUN:   '  "excludePaths": [],' \
// RUN:   '  "sourceFiles": ["%s"],' \
// RUN:   '  "enabledMutators": ["CONDITION_FALSE", "CONDITION_TRUE", "NEGATE_CONDITIONALS"],' \
// RUN:   '  "conditionMutationRules": [' \
// RUN:   '    "COMPARISON|CONDITION_FALSE|condition_false|condition|false",' \
// RUN:   '    "COMPARISON|CONDITION_TRUE|condition_true|condition|true",' \
// RUN:   '    "ICMP_EQ|NEGATE_CONDITIONALS|cmp_ne|==|!="' \
// RUN:   '  ],' \
// RUN:   '  "arithmeticMutationRules": [],' \
// RUN:   '  "contextualArithmeticMutationRules": [],' \
// RUN:   '  "returnMutationRules": [],' \
// RUN:   '  "voidCallMutationRules": [],' \
// RUN:   '  "sourceMutationDisplayRules": []' \
// RUN:   '}' > %t/config.json
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -emit-sil -O -module-name SwiftmutGuardConditionSourceLocations -external-pass-pipeline-filename %t/pipeline.yaml %s -o /dev/null
// RUN: find %t/fragments -type f -name '*.json' -exec cat {} ';' > %t/all-fragments.json
// RUN: %FileCheck %s --input-file %t/all-fragments.json
// RUN: %FileCheck %s --check-prefix=OPTIONAL --input-file %t/all-fragments.json
// RUN: %FileCheck %s --check-prefix=EVENTS --input-file %t/compiler-events.jsonl

import Foundation

public func swiftmutGuardDetails(_ includeDetails: Bool, line: String) -> Int {
  let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
  guard includeDetails, !trimmed.isEmpty else {
    return 0
  }
  return trimmed.count
}

public func swiftmutGuardOptionalBinding(_ value: String?) -> Int {
  guard let text = value, !text.isEmpty else {
    return 0
  }
  return text.count
}

public struct SwiftmutLongGenericConditionSubject {
  public let functionName: String
  public let sourceName: String
}

public func swiftmutMultilineGuardConditionClauses(_ subject: SwiftmutLongGenericConditionSubject) -> Bool {
  guard subject.functionName.hasPrefix("$s"),
        !subject.functionName.contains("cfu_"),
        subject.sourceName.hasSuffix("Scope") else {
    return false
  }
  return true
}

@_silgen_name("__swiftmut_visit")
public func __swiftmut_visit(_ siteID: UInt64) -> UInt32 {
  0
}

// CHECK-DAG: "siteKind":"condition"{{.*}}"sourceOriginal":"subject.functionName.hasPrefix(\"$s\")","sourceMutated":"false"{{.*}}"sourceOriginal":"subject.functionName.hasPrefix(\"$s\")","sourceMutated":"true"
// CHECK-DAG: "siteKind":"condition"{{.*}}"sourceOriginal":"!subject.functionName.contains(\"cfu_\")","sourceMutated":"false"{{.*}}"sourceOriginal":"!subject.functionName.contains(\"cfu_\")","sourceMutated":"true"
// CHECK-DAG: "siteKind":"condition"{{.*}}"sourceOriginal":"subject.sourceName.hasSuffix(\"Scope\")","sourceMutated":"false"{{.*}}"sourceOriginal":"subject.sourceName.hasSuffix(\"Scope\")","sourceMutated":"true"
// CHECK-DAG: "sourceLocation":{"file":"swiftmut_guard_condition_source_locations.swift","line":35,"column":9}
// CHECK-DAG: "sourceOriginal":"includeDetails, !trimmed.isEmpty","sourceMutated":"false"{{.*}}"sourceOriginal":"includeDetails, !trimmed.isEmpty","sourceMutated":"true"
// OPTIONAL: "sourceLocation":{"file":"swiftmut_guard_condition_source_locations.swift","line":42,"column":27}
// OPTIONAL-SAME: "siteKind":"condition"
// OPTIONAL-SAME: "sourceOriginal":"!text.isEmpty","sourceMutated":"false"
// OPTIONAL-SAME: "sourceOriginal":"!text.isEmpty","sourceMutated":"true"

// EVENTS: "event":"metamutantDiscovery","module":"SwiftmutGuardConditionSourceLocations","function":"$s37SwiftmutGuardConditionSourceLocations08swiftmutB7Details
// EVENTS-SAME: "conditionSourceLocationMisses":"0"
// EVENTS: "event":"metamutantDiscovery","module":"SwiftmutGuardConditionSourceLocations","function":"$s37SwiftmutGuardConditionSourceLocations08swiftmutB15OptionalBinding
// EVENTS-SAME: "conditionSourceLocationMisses":"0"
// EVENTS: "event":"metamutantDiscovery","module":"SwiftmutGuardConditionSourceLocations","function":"$s37SwiftmutGuardConditionSourceLocations017swiftmutMultilinebC7Clauses
// EVENTS-SAME: "conditionSourceLocationMisses":"0"
// EVENTS-SAME: "conditionGenericNonExplicitSourceLocations":"0"
