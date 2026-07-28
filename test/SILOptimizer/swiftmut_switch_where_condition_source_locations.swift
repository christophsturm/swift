// RUN: rm -rf %t
// RUN: mkdir -p %t
// RUN: printf '%%s\n' '---' "name: ''" 'passes: [ "\"swiftmut\"" ]' > %t/pipeline.yaml
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
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -emit-sil -O -module-name SwiftmutSwitchWhereConditionSourceLocations -external-pass-pipeline-filename %t/pipeline.yaml %s -o /dev/null
// RUN: find %t/fragments -type f -name '*.json' -exec cat {} ';' > %t/all-fragments.json
// RUN: %FileCheck %s --input-file %t/all-fragments.json

public enum SwiftmutSwitchWhereMode {
  case amount(Int)
  case disabled
}

@inline(never)
public func swiftmutSwitchWhereAccepts(_ total: Int) -> Bool {
  total > 0
}

public func swiftmutSwitchWhereTotal(_ mode: SwiftmutSwitchWhereMode, limit: Int) -> Int {
  switch mode {
  case .amount(let total) where total >= limit:
    return total
  case .amount(let total):
    return total / 2
  case .disabled:
    return 0
  }
}

public func swiftmutSwitchWhereGenericTotal(_ mode: SwiftmutSwitchWhereMode) -> Int {
  switch mode {
  case .amount(let total) where swiftmutSwitchWhereAccepts(total):
    return total
  default:
    return 0
  }
}

@_silgen_name("__swiftmut_visit")
public func __swiftmut_visit(_ siteID: UInt64) -> UInt32 {
  0
}

// CHECK-DAG: "sourceLocation":{"file":"swiftmut_switch_where_condition_source_locations.swift","line":42,"column":39}{{.*}}"siteKind":"condition"{{.*}}"sourceOriginal":"total >= limit","sourceMutated":"total > limit"{{.*}}"sourceOriginal":"total >= limit","sourceMutated":"total < limit"{{.*}}"sourceOriginal":"total >= limit","sourceMutated":"false"{{.*}}"sourceOriginal":"total >= limit","sourceMutated":"true"
// CHECK-DAG: "sourceLocation":{"file":"swiftmut_switch_where_condition_source_locations.swift","line":53,"column":33}{{.*}}"siteKind":"condition"{{.*}}"sourceOriginal":"swiftmutSwitchWhereAccepts(total)","sourceMutated":"false"{{.*}}"sourceOriginal":"swiftmutSwitchWhereAccepts(total)","sourceMutated":"true"
