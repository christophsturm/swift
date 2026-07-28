// RUN: rm -rf %t
// RUN: mkdir -p %t
// RUN: printf '%%s\n' '---' "name: ''" 'passes: [ "\"swiftmut\"" ]' > %t/pipeline.yaml
// RUN: printf '%b\n' \
// RUN:   '{' \
// RUN:   '  "mode": "discover",' \
// RUN:   '  "manifestPath": "%t/mutants.jsonl",' \
// RUN:   '  "manifestFragmentsDirectory": "%t/fragments",' \
// RUN:   '  "compilerEventsPath": "%t/compiler-events.jsonl",' \
// RUN:   '  "packageRoot": "%S",' \
// RUN:   '  "excludePaths": [],' \
// RUN:   '  "sourceFiles": ["%s"],' \
// RUN:   '  "enabledMutators": ["PRIMITIVE_RETURNS", "FALSE_RETURNS", "TRUE_RETURNS"],' \
// RUN:   '  "conditionMutationRules": [],' \
// RUN:   '  "arithmeticMutationRules": [],' \
// RUN:   '  "contextualArithmeticMutationRules": [],' \
// RUN:   '  "returnMutationRules": [' \
// RUN:   '    "integerToZero|PRIMITIVE_RETURNS|return_zero|return|return 0|0",' \
// RUN:   '    "boolToFalse|FALSE_RETURNS|return_false|return|return false|false",' \
// RUN:   '    "boolToTrue|TRUE_RETURNS|return_true|return|return true|true"' \
// RUN:   '  ],' \
// RUN:   '  "voidCallMutationRules": [],' \
// RUN:   '  "sourceMutationDisplayRules": []' \
// RUN:   '}' > %t/config.json
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -emit-sil -O -module-name SwiftmutComputedPropertyReturnSourceLocations -external-pass-pipeline-filename %t/pipeline.yaml %s -o /dev/null
// RUN: %FileCheck %s --input-file %t/mutants.jsonl

public struct SwiftmutRepeatedComputedReturnSummary {
  public let totalMutants: Int
  public let keptMutants: Int
  public let totalSourceLines: Int
  public let keptSourceLines: Int

  public var rejectedMutants: Int {
    totalMutants - keptMutants
  }

  public var rejectedSourceLines: Int {
    totalSourceLines - keptSourceLines
  }
}

public func swiftmutUseRepeatedComputedReturnSummary(
  _ summary: SwiftmutRepeatedComputedReturnSummary
) -> Int {
  summary.keptSourceLines + summary.rejectedMutants + summary.rejectedSourceLines
}

public struct MutationRunHistoryEntry {
  public let selectedMutants: Int
  public let rawMutants: Int?

  public var isFullMutationSelection: Bool {
    guard let rawMutants else {
      return true
    }
    return selectedMutants == rawMutants
  }
}

@_silgen_name("__swiftmut_visit")
public func __swiftmut_visit(_ siteID: UInt64) -> UInt32 {
  0
}

// CHECK-NOT: RepeatedbD7SummaryV04keptE5LinesSivg{{.*}}"line":35
// CHECK-NOT: RepeatedbD7SummaryV05totalE5LinesSivg{{.*}}"line":39
// CHECK: RepeatedbD7SummaryV15rejectedMutantsSivg
// CHECK-SAME: "line":35
// CHECK-SAME: "sourceOriginal":"totalMutants - keptMutants","sourceMutated":"0"
// CHECK: RepeatedbD7SummaryV08rejectedE5LinesSivg
// CHECK-SAME: "line":39
// CHECK-SAME: "sourceOriginal":"totalSourceLines - keptSourceLines","sourceMutated":"0"
// CHECK: RunHistoryEntryV06isFull{{.*}}SelectionSbvg
// CHECK-SAME: "line":57
// CHECK-SAME: "sourceOriginal":"return","sourceMutated":"return false"
