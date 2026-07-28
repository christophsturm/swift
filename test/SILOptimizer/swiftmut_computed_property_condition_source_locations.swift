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
// RUN:   '  "enabledMutators": ["CONDITIONALS_BOUNDARY", "CONDITION_FALSE", "CONDITION_TRUE", "NEGATE_CONDITIONALS"],' \
// RUN:   '  "conditionMutationRules": [' \
// RUN:   '    "ICMP_SGE|CONDITIONALS_BOUNDARY|cmp_sgt|>=|>",' \
// RUN:   '    "ICMP_SGE|NEGATE_CONDITIONALS|cmp_slt|>=|<",' \
// RUN:   '    "COMPARISON|CONDITION_FALSE|condition_false|condition|false",' \
// RUN:   '    "COMPARISON|CONDITION_TRUE|condition_true|condition|true"' \
// RUN:   '  ],' \
// RUN:   '  "arithmeticMutationRules": [],' \
// RUN:   '  "contextualArithmeticMutationRules": [],' \
// RUN:   '  "returnMutationRules": [],' \
// RUN:   '  "voidCallMutationRules": [],' \
// RUN:   '  "sourceMutationDisplayRules": []' \
// RUN:   '}' > %t/config.json
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -emit-sil -O -module-name SwiftmutComputedPropertyConditionSourceLocations %s -o /dev/null
// RUN: find %t/fragments -type f -name '*.json' -exec cat {} ';' > %t/all-fragments.json
// RUN: %FileCheck %s --input-file %t/all-fragments.json

public struct SwiftmutSelection {
  public let siteID: UInt64

  public init(siteID: UInt64) {
    self.siteID = siteID
  }
}

public struct SwiftmutSourceEquivalentMutation {
  public let selections: [SwiftmutSelection]

  public init(selections: [SwiftmutSelection]) {
    self.selections = selections
  }

  public var swiftmutSelectionBucket: Int {
    if Set(selections.map(\.siteID)).count >= 2 {
      return 2
    }
    return 1
  }
}

@_silgen_name("__swiftmut_visit")
public func __swiftmut_visit(_ siteID: UInt64) -> UInt32 {
  0
}

// CHECK: "file":"swiftmut_computed_property_condition_source_locations.swift","line":46,"column":8},"siteKind":"condition","resultKind":"condition","alternatives":[{{.*}}"sourceOriginal":"Set(selections.map(\\.siteID)).count >= 2","sourceMutated":"Set(selections.map(\\.siteID)).count > 2"{{.*}}"sourceOriginal":"Set(selections.map(\\.siteID)).count >= 2","sourceMutated":"Set(selections.map(\\.siteID)).count < 2"{{.*}}"sourceOriginal":"Set(selections.map(\\.siteID)).count >= 2","sourceMutated":"false"{{.*}}"sourceOriginal":"Set(selections.map(\\.siteID)).count >= 2","sourceMutated":"true"
