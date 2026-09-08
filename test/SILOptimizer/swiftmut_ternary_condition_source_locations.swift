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
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -emit-sil -O -module-name SwiftmutTernaryConditionSourceLocations %s -o /dev/null
// RUN: find %t/fragments -type f -name '*.json' -exec cat {} ';' | %{python} %S/Inputs/swiftmut-render-condition-ranges.py %S > %t/all-fragments.json
// RUN: %FileCheck %s --input-file %t/all-fragments.json
// RUN: %FileCheck %s --check-prefix=EVENTS --input-file %t/compiler-events.jsonl

public func swiftmutTernaryLimit(_ value: Int, limit: Int) -> Int {
  value >= limit ? 10 : 0
}

public func swiftmutTernaryFlag(_ includeColumn: Bool, value: String) -> String {
  let selected = includeColumn ? value : "fallback"
  return selected
}

@_silgen_name("__swiftmut_visit")
public func __swiftmut_visit(_ siteID: UInt64) -> UInt32 {
  0
}

// CHECK-DAG: "sourceOriginal":"value >= limit","sourceMutated":"false"
// CHECK-DAG: "sourceOriginal":"value >= limit","sourceMutated":"true"
// CHECK-DAG: "sourceOriginal":"includeColumn","sourceMutated":"false"
// CHECK-DAG: "sourceOriginal":"includeColumn","sourceMutated":"true"

// EVENTS: "event":"metamutantDiscovery","module":"SwiftmutTernaryConditionSourceLocations","function":"$s39SwiftmutTernaryConditionSourceLocations08swiftmutB5Limit
// EVENTS-SAME: "conditionSourceLocationMisses":"0"
