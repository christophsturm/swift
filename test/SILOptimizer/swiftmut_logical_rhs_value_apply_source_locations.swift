// RUN: rm -rf %t
// XFAIL: *
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
// RUN:   '  "enabledMutators": ["FALSE_RETURNS"],' \
// RUN:   '  "conditionMutationRules": [],' \
// RUN:   '  "arithmeticMutationRules": [],' \
// RUN:   '  "contextualArithmeticMutationRules": [],' \
// RUN:   '  "returnMutationRules": [' \
// RUN:   '    "boolToFalse|FALSE_RETURNS|return_false|return|return false|false"' \
// RUN:   '  ],' \
// RUN:   '  "voidCallMutationRules": [],' \
// RUN:   '  "sourceMutationDisplayRules": []' \
// RUN:   '}' > %t/config.json
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -emit-sil -O -module-name SwiftmutLogicalRHSValueApplySourceLocations -external-pass-pipeline-filename %t/pipeline.yaml %s -o /dev/null
// RUN: find %t/fragments -type f -name '*.json' -exec cat {} ';' > %t/all-fragments.json
// RUN: %FileCheck %s --input-file %t/all-fragments.json

@inline(never)
public func swiftmutIsPaid() -> Bool {
  true
}

public func swiftmutLogicalRHS(_ enabled: Bool) -> Bool {
  enabled && swiftmutIsPaid()
}

@_silgen_name("__swiftmut_visit")
public func __swiftmut_visit(_ siteID: UInt64) -> UInt32 {
  0
}

// CHECK: "siteKind":"valueApply"
// CHECK: "sourceOriginal":"swiftmutIsPaid()","sourceMutated":"false"
