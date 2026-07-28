// RUN: rm -rf %t
// RUN: mkdir -p %t
// swiftmut runs in the native Diagnostic pipeline.
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
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -emit-sil -O -module-name SwiftmutStoredPropertyReturnSourceLocations %s -o /dev/null
// RUN: %FileCheck %s --check-prefix=EVENTS --input-file %t/compiler-events.jsonl

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

// EVENTS-DAG: "event":"functionSkip","reason":"generatedStoredPropertyGetter","module":"SwiftmutStoredPropertyReturnSourceLocations","function":"{{.*}}V9isEnabledSbvg"
// EVENTS-DAG: "event":"functionSkip","reason":"generatedStoredPropertyGetter","module":"SwiftmutStoredPropertyReturnSourceLocations","function":"{{.*}}V10totalLinesSivg"
// EVENTS-DAG: "event":"functionSkip","reason":"generatedStoredPropertyGetter","module":"SwiftmutStoredPropertyReturnSourceLocations","function":"{{.*}}V11missedLinesSivg"
