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
// RUN:   '  "enabledMutators": ["PRIMITIVE_RETURNS"],' \
// RUN:   '  "conditionMutationRules": [],' \
// RUN:   '  "arithmeticMutationRules": [],' \
// RUN:   '  "contextualArithmeticMutationRules": [],' \
// RUN:   '  "returnMutationRules": [' \
// RUN:   '    "integerToZero|PRIMITIVE_RETURNS|return_zero|return|return 0|0"' \
// RUN:   '  ],' \
// RUN:   '  "voidCallMutationRules": [],' \
// RUN:   '  "sourceMutationDisplayRules": []' \
// RUN:   '}' > %t/config.json
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -emit-sil -O -module-name SwiftmutDescribedValueApplyOrdinalSourceLocations %s -o /dev/null
// RUN: find %t/fragments -type f -name '*.json' -exec cat {} ';' | %{python} %S/Inputs/swiftmut-render-condition-ranges.py %S > %t/all-fragments.json
// RUN: %FileCheck %s --input-file %t/all-fragments.json

@inline(never)
public func swiftmutRepeatedNumber() -> Int {
  7
}

@_silgen_name("__swiftmut_visit")
public func __swiftmut_visit(_ siteID: UInt64) -> UInt32 {
  0
}

public func swiftmutRepeatedDescribedValueApply(_ flag: Bool) -> Int {
  if flag {
    return swiftmutRepeatedNumber()
  }
  return swiftmutRepeatedNumber()
}

// CHECK: "line":39,"column":12},"siteKind":"valueApply","resultKind":"value",{{.*}}"valueNominalType":{"module":"Swift","name":"Int"},{{.*}}"alternatives":[{{.*}}"sourceOriginal":"swiftmutRepeatedNumber()","sourceMutated":"0"{{.*}}"line":41,"column":10},"siteKind":"valueApply","resultKind":"value",{{.*}}"valueNominalType":{"module":"Swift","name":"Int"},{{.*}}"alternatives":[{{.*}}"sourceOriginal":"swiftmutRepeatedNumber()","sourceMutated":"0"
