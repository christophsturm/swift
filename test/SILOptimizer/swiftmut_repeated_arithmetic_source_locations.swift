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
// MANIFEST-DAG: "siteKind":"arithmetic"{{.*}}"sourceOriginal":"result + y","sourceMutated":"result - y"
// MANIFEST-DAG: "siteKind":"arithmetic"{{.*}}"sourceOriginal":"result + z","sourceMutated":"result - z"
// MANIFEST-DAG: "siteKind":"arithmetic"{{.*}}"sourceOriginal":"result - 1","sourceMutated":"result + 1"
