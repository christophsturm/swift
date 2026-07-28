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
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -emit-sil -O -module-name SwiftmutMultilineConditionSourceLocations -external-pass-pipeline-filename %t/pipeline.yaml %s -o /dev/null
// RUN: find %t/fragments -type f -name '*.json' -exec cat {} ';' > %t/all-fragments.json
// RUN: %FileCheck %s --input-file %t/all-fragments.json
// RUN: %FileCheck %s --check-prefix=EVENTS --input-file %t/compiler-events.jsonl

@inline(never)
public func swiftmutAccepts(_ value: Int, flag: Bool) -> Bool {
  flag
}

public func swiftmutMultilineCondition(_ value: Int, flag: Bool) -> Int {
  if swiftmutAccepts(
    value,
    flag: flag
  ) {
    return 1
  }
  return 0
}

@_silgen_name("__swiftmut_visit")
public func __swiftmut_visit(_ siteID: UInt64) -> UInt32 {
  0
}

// CHECK: "sourceLocation":{"file":"swiftmut_multiline_condition_source_locations.swift","line":35,"column":6}
// CHECK-SAME: "siteKind":"condition"
// CHECK-SAME: "sourceOriginal":"swiftmutAccepts( value, flag: flag )","sourceMutated":"false"
// CHECK-SAME: "sourceOriginal":"swiftmutAccepts( value, flag: flag )","sourceMutated":"true"

// EVENTS: "event":"metamutantDiscovery","module":"SwiftmutMultilineConditionSourceLocations","function":"$s41SwiftmutMultilineConditionSourceLocations08swiftmutbC0
// EVENTS-SAME: "conditionSites":"1"
// EVENTS-SAME: "conditionSourceLocationMisses":"0"
