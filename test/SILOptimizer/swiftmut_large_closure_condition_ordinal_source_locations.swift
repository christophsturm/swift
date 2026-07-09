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
// RUN:   '  "enabledMutators": ["CONDITION_FALSE", "CONDITION_TRUE", "NEGATE_CONDITIONALS"],' \
// RUN:   '  "conditionMutationRules": [' \
// RUN:   '    "COMPARISON|NEGATE_CONDITIONALS|cmp_ne|swiftmutLargeConditionValue(value) == 1|swiftmutLargeConditionValue(value) != 1",' \
// RUN:   '    "COMPARISON|CONDITION_FALSE|condition_false|condition|false",' \
// RUN:   '    "COMPARISON|CONDITION_TRUE|condition_true|condition|true"' \
// RUN:   '  ],' \
// RUN:   '  "arithmeticMutationRules": [],' \
// RUN:   '  "contextualArithmeticMutationRules": [],' \
// RUN:   '  "returnMutationRules": [],' \
// RUN:   '  "voidCallMutationRules": [],' \
// RUN:   '  "sourceMutationDisplayRules": [' \
// RUN:   '    "NEGATE_CONDITIONALS|ICMP_EQ|==|!=|",' \
// RUN:   '    "CONDITION_FALSE|ICMP_EQ|==|==|false",' \
// RUN:   '    "CONDITION_TRUE|ICMP_EQ|==|==|true"' \
// RUN:   '  ]' \
// RUN:   '}' > %t/config.json
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -emit-sil -O -module-name SwiftmutLargeClosureConditionOrdinalSourceLocations -external-pass-pipeline-filename %t/pipeline.yaml %s -o /dev/null
// RUN: find %t/fragments -type f -name '*.json' -exec cat {} ';' > %t/all-fragments.json
// RUN: %FileCheck %s --input-file %t/all-fragments.json
// RUN: %FileCheck %s --check-prefix=EVENTS --input-file %t/compiler-events.jsonl

@inline(never)
public func swiftmutLargeConditionSink(_ value: Int) {}

@inline(never)
public func swiftmutLargeConditionValue(_ value: Int) -> Int {
  value
}

public func swiftmutLargeClosureCondition(_ values: [Int]) {
  _ = values.compactMap { value -> Int? in
    if swiftmutLargeConditionValue(value) == 1 { swiftmutLargeConditionSink(1) }
    if swiftmutLargeConditionValue(value) == 1 { swiftmutLargeConditionSink(2) }
    if swiftmutLargeConditionValue(value) == 1 { swiftmutLargeConditionSink(3) }
    if swiftmutLargeConditionValue(value) == 1 { swiftmutLargeConditionSink(4) }
    if swiftmutLargeConditionValue(value) == 1 { swiftmutLargeConditionSink(5) }
    if swiftmutLargeConditionValue(value) == 1 { swiftmutLargeConditionSink(6) }
    if swiftmutLargeConditionValue(value) == 1 { swiftmutLargeConditionSink(7) }
    if swiftmutLargeConditionValue(value) == 1 { swiftmutLargeConditionSink(8) }
    if swiftmutLargeConditionValue(value) == 1 { swiftmutLargeConditionSink(9) }
    if swiftmutLargeConditionValue(value) == 1 { swiftmutLargeConditionSink(10) }
    if swiftmutLargeConditionValue(value) == 1 { swiftmutLargeConditionSink(11) }
    if swiftmutLargeConditionValue(value) == 1 { swiftmutLargeConditionSink(12) }
    if swiftmutLargeConditionValue(value) == 1 { swiftmutLargeConditionSink(13) }
    return value
  }
}

@_silgen_name("__swiftmut_visit")
public func __swiftmut_visit(_ siteID: UInt64) -> UInt32 {
  0
}

// CHECK-DAG: "line":44,"column":8
// CHECK-DAG: "line":56,"column":8
// CHECK-DAG: "sourceOriginal":"swiftmutLargeConditionValue(value) == 1","sourceMutated":"swiftmutLargeConditionValue(value) != 1"
// CHECK-DAG: "sourceOriginal":"swiftmutLargeConditionValue(value) == 1","sourceMutated":"false"
// CHECK-DAG: "sourceOriginal":"swiftmutLargeConditionValue(value) == 1","sourceMutated":"true"

// EVENTS: "event":"metamutantDiscovery"{{.*}}"conditionBranches":"13"{{.*}}"conditionSites":"13"{{.*}}"conditionSourceLocationMisses":"0"
