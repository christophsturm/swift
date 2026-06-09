// RUN: rm -rf %t
// RUN: mkdir -p %t
// RUN: printf '%b\n' '---' "name: ''" 'passes: [ "\"swiftmut\"" ]' > %t/pipeline.yaml
// RUN: printf '%b\n' \
// RUN:   '{' \
// RUN:   '  "mode": "discover",' \
// RUN:   '  "manifestPath": "%t/mutants.jsonl",' \
// RUN:   '  "manifestFragmentsDirectory": "%t/fragments",' \
// RUN:   '  "compilerEventsPath": "%t/compiler-events.jsonl",' \
// RUN:   '  "packageRoot": "%S",' \
// RUN:   '  "excludePaths": [],' \
// RUN:   '  "sourceFiles": ["%s"],' \
// RUN:   '  "enabledMutators": ["FALSE_RETURNS", "PRIMITIVE_RETURNS"],' \
// RUN:   '  "conditionMutationRules": [],' \
// RUN:   '  "arithmeticMutationRules": [],' \
// RUN:   '  "contextualArithmeticMutationRules": [],' \
// RUN:   '  "returnMutationRules": [' \
// RUN:   '    "boolToFalse|FALSE_RETURNS|return_false|return|return false|false",' \
// RUN:   '    "integerToZero|PRIMITIVE_RETURNS|return_zero|return|return 0|0"' \
// RUN:   '  ],' \
// RUN:   '  "voidCallMutationRules": [],' \
// RUN:   '  "sourceMutationDisplayRules": []' \
// RUN:   '}' > %t/config.json
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -emit-sil -O -module-name SwiftmutStoredPropertyReturnSourceLocations -external-pass-pipeline-filename %t/pipeline.yaml %s -o /dev/null
// RUN: %FileCheck %s --input-file %t/mutants.jsonl

public struct SwiftmutFeatureFlag {
  public let isEnabled = true
}

public struct SwiftmutCoverageFileSummary {
  public let totalLines: Int
  public let missedLines: Int

  public static func summaries(for lines: [SwiftmutCoverageLine]) -> [SwiftmutCoverageFileSummary] {
    Dictionary(grouping: lines, by: \.file)
      .map { file, lines in
        SwiftmutCoverageFileSummary(totalLines: lines.count, missedLines: file.count)
      }
      .sorted { $0.totalLines < $1.totalLines }
  }
}

public struct SwiftmutCoverageLine {
  public let file: String
}

// CHECK: "sourceOriginal":"true","sourceMutated":"false"
// CHECK-NOT: V10totalLinesSivg{{.*}}"sourceOriginal":"Dictionary(grouping: lines, by: \\.file)"
// CHECK-NOT: V11missedLinesSivg{{.*}}"sourceOriginal":"Dictionary(grouping: lines, by: \\.file)"
// CHECK: V10totalLinesSivg
// CHECK-SAME: "sourceOriginal":"totalLines","sourceMutated":"0"
// CHECK: V11missedLinesSivg
// CHECK-SAME: "sourceOriginal":"missedLines","sourceMutated":"0"
