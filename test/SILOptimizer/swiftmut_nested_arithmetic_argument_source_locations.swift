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
// RUN:   '    "SAddOver|otherwise|MATH|ssub_with_overflow|+|-"' \
// RUN:   '  ],' \
// RUN:   '  "returnMutationRules": [],' \
// RUN:   '  "voidCallMutationRules": [],' \
// RUN:   '  "sourceMutationDisplayRules": [' \
// RUN:   '    "MATH|SAddOver|+|-|"' \
// RUN:   '  ]' \
// RUN:   '}' > %t/config.json
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -emit-sil -Onone -module-name SwiftmutNestedArithmeticArgumentSourceLocations %s -o /dev/null
// RUN: %FileCheck %s --input-file %t/compiler-events.jsonl
// RUN: find %t/fragments -type f -name '*.json' -exec cat {} ';' > %t/all-fragments.json
// RUN: %FileCheck %s --check-prefix=MANIFEST --input-file %t/all-fragments.json

public func swiftmutNestedArithmeticArguments(_ x: Int, _ y: Int, _ z: Int) -> Int {
  var total = 0
  total += swiftmutArithmeticIdentity(x)
  total += swiftmutArithmeticIdentity(y)
  total += swiftmutArithmeticIdentity(x + y)
  total += swiftmutArithmeticIdentity(y + z)
  return total
}

@inline(never)
func swiftmutArithmeticIdentity(_ value: Int) -> Int {
  value
}

@_silgen_name("__swiftmut_visit")
public func __swiftmut_visit(_ siteID: UInt64) -> UInt32 {
  0
}

// CHECK: "event":"metamutantDiscovery","module":"SwiftmutNestedArithmeticArgumentSourceLocations","function":"{{[^"]*}}Arguments{{[^"]*}}"
// CHECK-SAME: "arithmeticSites":"2"
// MANIFEST-DAG: "siteKind":"arithmetic"{{.*}}"sourceOriginal":"x + y","sourceMutated":"x - y"
// MANIFEST-DAG: "siteKind":"arithmetic"{{.*}}"sourceOriginal":"y + z","sourceMutated":"y - z"
