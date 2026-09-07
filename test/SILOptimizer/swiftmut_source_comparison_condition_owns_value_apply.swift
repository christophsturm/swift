// RUN: rm -rf %t
// RUN: mkdir -p %t
// swiftmut runs once before mandatory redundant-load elimination.
// RUN: printf '%b\n' \
// RUN:   '{' \
// RUN:   '  "mode": "metamutant",' \
// RUN:   '  "manifestPath": "%t/mutants.jsonl",' \
// RUN:   '  "manifestFragmentsDirectory": "%t/fragments",' \
// RUN:   '  "compilerEventsPath": "%t/compiler-events.jsonl",' \
// RUN:   '  "packageRoot": "%S",' \
// RUN:   '  "excludePaths": [],' \
// RUN:   '  "sourceFiles": ["%s"],' \
// RUN:   '  "enabledMutators": ["CONDITION_FALSE", "CONDITION_TRUE", "NEGATE_CONDITIONALS", "FALSE_RETURNS", "TRUE_RETURNS"],' \
// RUN:   '  "conditionMutationRules": [' \
// RUN:   '    "COMPARISON|CONDITION_FALSE|condition_false|condition|false",' \
// RUN:   '    "COMPARISON|CONDITION_TRUE|condition_true|condition|true",' \
// RUN:   '    "ICMP_EQ|NEGATE_CONDITIONALS|cmp_ne|==|!="' \
// RUN:   '  ],' \
// RUN:   '  "arithmeticMutationRules": [],' \
// RUN:   '  "contextualArithmeticMutationRules": [],' \
// RUN:   '  "returnMutationRules": [' \
// RUN:   '    "boolToFalse|FALSE_RETURNS|return_false|return|return false|false",' \
// RUN:   '    "boolToTrue|TRUE_RETURNS|return_true|return|return true|true"' \
// RUN:   '  ],' \
// RUN:   '  "voidCallMutationRules": [],' \
// RUN:   '  "statementMutationRules": [],' \
// RUN:   '  "sourceMutationDisplayRules": []' \
// RUN:   '}' > %t/config.json
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -emit-sil -Onone -module-name SwiftmutSourceComparisonConditionOwnsValueApply %s -o /dev/null
// RUN: find %t/fragments -type f -name '*.json' -exec cat {} ';' > %t/all-fragments.json
// RUN: %FileCheck %s --input-file %t/all-fragments.json
// RUN: %FileCheck %s --check-prefix=EVENTS --input-file %t/compiler-events.jsonl

public struct SwiftmutSourceTextIndex {
  public func functionEndLine(functionLocationLine: Int) -> Int? {
    nil
  }
}

public final class SwiftmutSourceLookupCache {
  private var lastFunctionRange: (path: String, startLine: Int, endLine: Int)?
  private var functionEndLineByPathAndStartLine: [String: [Int: Int]] = [:]

  private func readIndex(_ path: String) -> SwiftmutSourceTextIndex? {
    nil
  }

  public func sourceLineBelongsToFunction(
    _ line: Int,
    path: String,
    functionLocation: (path: String, line: Int)?
  ) -> Bool {
    guard let functionLocation,
          functionLocation.path == path else {
      return true
    }
    guard line >= functionLocation.line else {
      return false
    }
    if let lastFunctionRange,
       lastFunctionRange.path == path,
       lastFunctionRange.startLine == functionLocation.line {
      return line <= lastFunctionRange.endLine
    }
    if let endLine = functionEndLineByPathAndStartLine[path]?[functionLocation.line] {
      lastFunctionRange = (path, functionLocation.line, endLine)
      return line <= endLine
    }
    guard let sourceTextIndex = readIndex(path) else {
      return true
    }
    guard let endLine = sourceTextIndex.functionEndLine(
      functionLocationLine: functionLocation.line
    ) else {
      return true
    }
    var endLineByStartLine = functionEndLineByPathAndStartLine[path] ?? [:]
    endLineByStartLine[functionLocation.line] = endLine
    functionEndLineByPathAndStartLine[path] = endLineByStartLine
    lastFunctionRange = (path, functionLocation.line, endLine)
    return line <= endLine
  }
}

@_silgen_name("__swiftmut_visit")
public func __swiftmut_visit(_ siteID: UInt64) -> UInt32 {
  0
}

// CHECK: "siteKind":"valueApply"{{.*}}"sourceOriginal":"lastFunctionRange.path == path"

// EVENTS: "event":"metamutantDiscovery","module":"SwiftmutSourceComparisonConditionOwnsValueApply"{{.*}}"conditionBranches":"5","conditionSites":"1"
// EVENTS-SAME: "valueApplySites":"1"
// EVENTS: "event":"metamutantInjection","module":"SwiftmutSourceComparisonConditionOwnsValueApply"{{.*}}"attemptedConditionSites":"1"
