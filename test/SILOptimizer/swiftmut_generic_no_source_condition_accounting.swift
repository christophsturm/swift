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
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -emit-sil -O -module-name SwiftmutGenericNoSourceConditionAccounting -external-pass-pipeline-filename %t/pipeline.yaml %s -o /dev/null
// RUN: %FileCheck %s --input-file %t/compiler-events.jsonl

public struct SwiftmutGenericNoSourceSelection {
  public let siteID: UInt64

  public init(siteID: UInt64) {
    self.siteID = siteID
  }
}

public struct SwiftmutGeneratedGenericBranchValue {
  public let selections: [SwiftmutGenericNoSourceSelection]
  public let reportedSelections: [SwiftmutGenericNoSourceSelection]

  public init(
    selections: [SwiftmutGenericNoSourceSelection],
    reportedSelections: [SwiftmutGenericNoSourceSelection]
  ) {
    self.selections = selections
    self.reportedSelections = reportedSelections
  }

  public var activationSlotCount: Int {
    max(Set(selections.map(\.siteID)).count, 1)
  }

  public var hiddenActivationSelectionCount: Int {
    let reportedSiteIDs = Set(reportedSelections.map(\.siteID))
    let hiddenSiteIDs = Set(selections.filter { selection in
      !reportedSiteIDs.contains(selection.siteID)
    }.map(\.siteID))
    return hiddenSiteIDs.count
  }
}

@_silgen_name("__swiftmut_visit")
public func __swiftmut_visit(_ siteID: UInt64) -> UInt32 {
  0
}

// CHECK: "event":"metamutantDiscovery","module":"SwiftmutGenericNoSourceConditionAccounting","function":"{{.*}}activationSlotCountSivg"
// CHECK-SAME: "conditionSourceLocationMisses":"0"
// CHECK: "event":"metamutantDiscovery","module":"SwiftmutGenericNoSourceConditionAccounting","function":"{{.*}}hiddenActivationSelectionCountSivg"
// CHECK-SAME: "conditionSourceLocationMisses":"0"
