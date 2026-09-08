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
// RUN:   '  "enabledMutators": ["CONDITIONALS_BOUNDARY", "NEGATE_CONDITIONALS", "CONDITION_FALSE", "CONDITION_TRUE"],' \
// RUN:   '  "conditionMutationRules": [' \
// RUN:   '    "ICMP_SLT|CONDITIONALS_BOUNDARY|cmp_sle|<|<=",' \
// RUN:   '    "ICMP_SLT|NEGATE_CONDITIONALS|cmp_sge|<|>=",' \
// RUN:   '    "COMPARISON|CONDITION_FALSE|condition_false|condition|false",' \
// RUN:   '    "COMPARISON|CONDITION_TRUE|condition_true|condition|true"' \
// RUN:   '  ],' \
// RUN:   '  "arithmeticMutationRules": [],' \
// RUN:   '  "contextualArithmeticMutationRules": [],' \
// RUN:   '  "returnMutationRules": [],' \
// RUN:   '  "voidCallMutationRules": [],' \
// RUN:   '  "sourceMutationDisplayRules": [' \
// RUN:   '    "CONDITIONALS_BOUNDARY|ICMP_SLT|<|<=|",' \
// RUN:   '    "NEGATE_CONDITIONALS|ICMP_SLT|<|>=|",' \
// RUN:   '    "CONDITION_FALSE|ICMP_SLT|<|<|false",' \
// RUN:   '    "CONDITION_TRUE|ICMP_SLT|<|<|true"' \
// RUN:   '  ]' \
// RUN:   '}' > %t/config.json
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -emit-sil -O -module-name SwiftmutCompactMapClosureConditionSourceLocations %s -o /dev/null
// RUN: find %t/fragments -type f -name '*.json' -exec cat {} ';' | %{python} %S/Inputs/swiftmut-render-condition-ranges.py %S > %t/all-fragments.json
// RUN: %FileCheck %s --input-file %t/all-fragments.json
// RUN: %FileCheck %s --check-prefix=EVENTS --input-file %t/compiler-events.jsonl

public struct SwiftmutVisibleMutation {
  public let id: String
  public let reportedSelections: [Int]
  public let values: [Int]
}

public struct SwiftmutVisiblePlan {
  public let mutations: [SwiftmutVisibleMutation]

  public func filteringVisibleMutants(ids: Set<String>) -> [SwiftmutVisibleMutation] {
    mutations.compactMap { mutation in
      var selectedIDs: [String] = []
      var selectedValues: [Int] = []

      for index in mutation.values.indices {
        guard ids.contains(mutation.id) else {
          continue
        }
        selectedIDs.append(mutation.id)
        if index < mutation.reportedSelections.count {
          selectedValues.append(mutation.values[index])
        }
      }

      guard !selectedIDs.isEmpty else {
        return nil
      }

      return SwiftmutVisibleMutation(
        id: mutation.id,
        reportedSelections: selectedValues,
        values: selectedValues)
    }
  }
}

@_silgen_name("__swiftmut_visit")
public func __swiftmut_visit(_ siteID: UInt64) -> UInt32 {
  0
}

// CHECK-DAG: "line":51,"column":15
// CHECK-DAG: "sourceOriginal":"ids.contains(mutation.id)","sourceMutated":"false"
// CHECK-DAG: "sourceOriginal":"ids.contains(mutation.id)","sourceMutated":"true"
// CHECK-DAG: "line":55,"column":12
// CHECK-DAG: "sourceOriginal":"index < mutation.reportedSelections.count","sourceMutated":"false"
// CHECK-DAG: "sourceOriginal":"index < mutation.reportedSelections.count","sourceMutated":"true"

// CHECK-DAG: "line":60,"column":13
// CHECK-DAG: "sourceOriginal":"!selectedIDs.isEmpty","sourceMutated":"false"
// CHECK-DAG: "sourceOriginal":"!selectedIDs.isEmpty","sourceMutated":"true"

// EVENTS: "event":"metamutantDiscovery"{{.*}}"conditionBranches":"3"{{.*}}"conditionSites":"3"{{.*}}"conditionSourceLocationMisses":"0"
