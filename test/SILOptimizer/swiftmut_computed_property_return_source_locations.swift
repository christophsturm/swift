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
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -emit-sil -O -module-name SwiftmutComputedPropertyReturnSourceLocations %s -o /dev/null
// RUN: cat %t/fragments/*.json | %{python} %S/Inputs/swiftmut-render-condition-ranges.py %S | %FileCheck %s

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
// CHECK-DAG: RepeatedbD7SummaryV15rejectedMutantsSivg{{.*}}"line":35{{.*}}"sourceOriginal":"totalMutants - keptMutants","sourceMutated":"0"
// Metamutant fragments are independently emitted and have no global ordering.
// Both computed properties must retain their own source identity.
// CHECK-DAG: RepeatedbD7SummaryV08rejectedE5LinesSivg{{.*}}"line":39{{.*}}"sourceOriginal":"totalSourceLines - keptSourceLines","sourceMutated":"0"
// Stored-property getters must not borrow either computed expression.
// The trailing guard return remains independently represented.
// CHECK-DAG: RunHistoryEntryV06isFull{{.*}}SelectionSbvg{{.*}}"line":57{{.*}}"sourceOriginal":"return","sourceMutated":"return false"
