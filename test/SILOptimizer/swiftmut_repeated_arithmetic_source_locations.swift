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
// RUN:   '  "enabledMutators": ["MATH"],' \
// RUN:   '  "conditionMutationRules": [],' \
// RUN:   '  "arithmeticMutationRules": [],' \
// RUN:   '  "contextualArithmeticMutationRules": [' \
// RUN:   '    "SAddOver|otherwise|MATH|ssub_with_overflow|+|-",' \
// RUN:   '    "SSubOver|otherwise|MATH|sadd_with_overflow|-|+"' \
// RUN:   '  ],' \
// RUN:   '  "returnMutationRules": [],' \
// RUN:   '  "voidCallMutationRules": [],' \
// RUN:   '  "sourceMutationDisplayRules": [' \
// RUN:   '    "MATH|SAddOver|+|-|",' \
// RUN:   '    "MATH|SSubOver|-|+|"' \
// RUN:   '  ]' \
// RUN:   '}' > %t/config.json
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -emit-sil -Onone -module-name SwiftmutRepeatedArithmeticSourceLocations %s -o /dev/null
// RUN: %FileCheck %s --input-file %t/compiler-events.jsonl
// RUN: find %t/fragments -type f -name '*.json' -exec cat {} ';' > %t/all-fragments.json
// RUN: %FileCheck %s --check-prefix=MANIFEST --input-file %t/all-fragments.json

public func swiftmutRepeatedArithmetic(_ x: Int, _ y: Int, _ z: Int) -> Int {
  var result = 0
  if x > 0 { result = result + y }; if y > 0 { result = result + z }
  return result - 1
}

@_silgen_name("__swiftmut_visit")
public func __swiftmut_visit(_ siteID: UInt64) -> UInt32 {
  0
}

// CHECK: "event":"metamutantDiscovery","module":"SwiftmutRepeatedArithmeticSourceLocations"
// CHECK-SAME: "arithmeticSites":"3"
// MANIFEST-DAG: "sourceSpan":{"start":{"line":34,"column":23,{{[^}]*}}},"end":{"line":34,"column":33,{{[^}]*}}}{{[^]]*}}"operation":"subtract","sourceEdit":{"span":{"start":{"line":34,"column":30,{{[^}]*}}},"end":{"line":34,"column":31,{{[^}]*}}}},"replacement":"-"}
// MANIFEST-DAG: "sourceSpan":{"start":{"line":34,"column":57,{{[^}]*}}},"end":{"line":34,"column":67,{{[^}]*}}}{{[^]]*}}"operation":"subtract","sourceEdit":{"span":{"start":{"line":34,"column":64,{{[^}]*}}},"end":{"line":34,"column":65,{{[^}]*}}}},"replacement":"-"}
// MANIFEST-DAG: "sourceSpan":{"start":{"line":35,"column":10,{{[^}]*}}},"end":{"line":35,"column":20,{{[^}]*}}}{{[^]]*}}"operation":"add","sourceEdit":{"span":{"start":{"line":35,"column":17,{{[^}]*}}},"end":{"line":35,"column":18,{{[^}]*}}}},"replacement":"+"}
