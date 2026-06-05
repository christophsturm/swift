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
// RUN:   '  "enabledMutators": ["NULL_RETURNS"],' \
// RUN:   '  "conditionMutationRules": [],' \
// RUN:   '  "arithmeticMutationRules": [],' \
// RUN:   '  "contextualArithmeticMutationRules": [],' \
// RUN:   '  "returnMutationRules": [' \
// RUN:   '    "optionalToNil|NULL_RETURNS|return_nil|return|return nil|nil"' \
// RUN:   '  ],' \
// RUN:   '  "voidCallMutationRules": [],' \
// RUN:   '  "sourceMutationDisplayRules": []' \
// RUN:   '}' > %t/config.json
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -emit-sil -O -module-name SwiftmutOptionalBindingValueApplySourceLocations -external-pass-pipeline-filename %t/pipeline.yaml %s -o /dev/null
// RUN: find %t/fragments -type f -name '*.json' -print -exec %FileCheck %s --input-file {} ';'

@inline(never)
public func swiftmutOptionalNumber() -> Int? {
  7
}

@_silgen_name("__swiftmut_visit")
public func __swiftmut_visit(_ siteID: UInt64) -> UInt32 {
  0
}

public func swiftmutOptionalBinding() -> Int {
  if let number = swiftmutOptionalNumber() {
    return number
  }
  return 0
}

// CHECK: "siteKind":"valueApply"
// CHECK: "sourceOriginal":"swiftmutOptionalNumber()","sourceMutated":"nil"
