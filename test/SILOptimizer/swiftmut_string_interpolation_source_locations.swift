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
// RUN:   '    "stringToEmpty|EMPTY_RETURNS|return_empty_string|return|return \\\"\\\"|\\\"\\\""' \
// RUN:   '  ],' \
// RUN:   '  "voidCallMutationRules": [],' \
// RUN:   '  "sourceMutationDisplayRules": []' \
// RUN:   '}' > %t/config.json
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -emit-sil -O -module-name SwiftmutStringInterpolationSourceLocations -external-pass-pipeline-filename %t/pipeline.yaml %s -o /dev/null
// RUN: %FileCheck %s --input-file %t/compiler-events.jsonl
// RUN: find %t/fragments -type f -name '*.json' -exec cat {} ';' > %t/all-fragments.json
// RUN: %FileCheck %s --check-prefix=MANIFEST --input-file %t/all-fragments.json

public func swiftmutInterpolatedDescription(_ value: Int) -> String {
  "value: \(value)"
}

@_silgen_name("__swiftmut_visit")
public func __swiftmut_visit(_ siteID: UInt64) -> UInt32 {
  0
}

@_silgen_name("__swiftmut_empty_string")
public func __swiftmut_empty_string() -> String {
  ""
}

// CHECK: "event":"metamutantDiscovery"
// CHECK-SAME: "valueApplySites":"0"
// CHECK-SAME: "valueApplyInstructions":"7"
// CHECK-SAME: "valueApplyValueInstructions":"4"
// CHECK-SAME: "valueApplyMutationEligibleInstructions":"2"
// CHECK-SAME: "valueApplySourceLocationMisses":"2"
// CHECK-SAME: "returnSites":"1"
// CHECK-SAME: "returnTerminators":"1"
// CHECK-SAME: "returnStringTerminators":"1"
// CHECK-SAME: "returnMutationEligibleTerminators":"1"
// CHECK-SAME: "returnSourceLocationMisses":"0"
// MANIFEST: "sourceLocation":{"file":"swiftmut_string_interpolation_source_locations.swift","line":29,"column":3}
// MANIFEST-SAME: "siteKind":"returnValue"
// MANIFEST-SAME: "sourceOriginal":"\"value: \\(value)\""
// MANIFEST-SAME: "sourceMutated":"\"\""
