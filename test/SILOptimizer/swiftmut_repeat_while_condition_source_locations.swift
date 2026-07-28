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
// RUN:   '    "ICMP_SLT|CONDITIONALS_BOUNDARY|cmp_sle|<|<=",' \
// RUN:   '    "ICMP_SLT|NEGATE_CONDITIONALS|cmp_sge|<|>=",' \
// RUN:   '    "COMPARISON|CONDITION_FALSE|condition_false|condition|false",' \
// RUN:   '    "COMPARISON|CONDITION_TRUE|condition_true|condition|true"' \
// RUN:   '  ],' \
// RUN:   '  "arithmeticMutationRules": [],' \
// RUN:   '  "contextualArithmeticMutationRules": [],' \
// RUN:   '  "returnMutationRules": [],' \
// RUN:   '  "voidCallMutationRules": [],' \
// RUN:   '  "sourceMutationDisplayRules": []' \
// RUN:   '}' > %t/config.json
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -emit-sil -O -module-name SwiftmutRepeatWhileConditionSourceLocations -external-pass-pipeline-filename %t/pipeline.yaml %s -o /dev/null
// RUN: find %t/fragments -type f -name '*.json' -exec cat {} ';' > %t/all-fragments.json
// RUN: %FileCheck %s --input-file %t/all-fragments.json

public func swiftmutRepeatWhileTotal(_ values: [Int]) -> Int {
  var total = 0
  var index = 0
  repeat {
    total += index
    index += 1
  } while index < values.count
  return total
}

@inline(never)
public func swiftmutRepeatWhileAccepts(_ index: Int, _ count: Int) -> Bool {
  index != count
}

public func swiftmutRepeatWhileGenericTotal(_ values: [Int]) -> Int {
  var total = 0
  var index = 0
  repeat {
    total += index
    index += 1
  } while swiftmutRepeatWhileAccepts(index, values.count)
  return total
}

@_silgen_name("__swiftmut_visit")
public func __swiftmut_visit(_ siteID: UInt64) -> UInt32 {
  0
}

// Fragment files concatenate in filesystem order, so the two sites may
// appear in either order; match each on its own line.
// CHECK-DAG: "sourceLocation":{"file":"swiftmut_repeat_while_condition_source_locations.swift","line":36,"column":11}{{.*}}"siteKind":"condition"{{.*}}"sourceOriginal":"index < values.count","sourceMutated":"index <= values.count"{{.*}}"sourceOriginal":"index < values.count","sourceMutated":"index >= values.count"{{.*}}"sourceOriginal":"index < values.count","sourceMutated":"false"{{.*}}"sourceOriginal":"index < values.count","sourceMutated":"true"
// CHECK-DAG: "sourceLocation":{"file":"swiftmut_repeat_while_condition_source_locations.swift","line":51,"column":11}{{.*}}"siteKind":"condition"{{.*}}"sourceOriginal":"swiftmutRepeatWhileAccepts(index, values.count)","sourceMutated":"false"{{.*}}"sourceOriginal":"swiftmutRepeatWhileAccepts(index, values.count)","sourceMutated":"true"
