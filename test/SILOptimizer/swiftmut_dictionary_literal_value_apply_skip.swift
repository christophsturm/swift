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
// RUN:   '  "enabledMutators": ["EMPTY_RETURNS"],' \
// RUN:   '  "conditionMutationRules": [],' \
// RUN:   '  "arithmeticMutationRules": [],' \
// RUN:   '  "contextualArithmeticMutationRules": [],' \
// RUN:   '  "returnMutationRules": [' \
// RUN:   '    "dictionaryToEmpty|EMPTY_RETURNS|return_empty_dictionary|return|return [:]|[:]"' \
// RUN:   '  ],' \
// RUN:   '  "voidCallMutationRules": [],' \
// RUN:   '  "sourceMutationDisplayRules": []' \
// RUN:   '}' > %t/config.json
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -emit-sil -O -module-name SwiftmutDictionaryLiteralValueApplySkip -external-pass-pipeline-filename %t/pipeline.yaml %s -o /dev/null
// RUN: %FileCheck %s --input-file %t/compiler-events.jsonl

public func swiftmutDictionaryLiteral() -> [String: Int] {
  ["shipping": 5, "tax": 2]
}

@_silgen_name("__swiftmut_visit")
public func __swiftmut_visit(_ siteID: UInt64) -> UInt32 {
  0
}

@_silgen_name("__swiftmut_empty_dictionary")
public func __swiftmut_empty_dictionary<Key: Hashable, Value>() -> [Key: Value] {
  [:]
}

// CHECK: "event":"metamutantDiscovery"
// CHECK-SAME: "valueApplySites":"0"
// CHECK-SAME: "valueApplyInstructions":"5"
// CHECK-SAME: "valueApplyMutationEligibleInstructions":"0"
