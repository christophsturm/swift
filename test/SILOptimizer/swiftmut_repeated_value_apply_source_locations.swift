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
// RUN:   '  "enabledMutators": ["PRIMITIVE_RETURNS", "FALSE_RETURNS", "TRUE_RETURNS"],' \
// RUN:   '  "conditionMutationRules": [],' \
// RUN:   '  "arithmeticMutationRules": [],' \
// RUN:   '  "contextualArithmeticMutationRules": [],' \
// RUN:   '  "returnMutationRules": [' \
// RUN:   '    "integerToZero|PRIMITIVE_RETURNS|return_zero|return|return 0|0",' \
// RUN:   '    "boolToFalse|FALSE_RETURNS|return_false|return|return false|false",' \
// RUN:   '    "boolToTrue|TRUE_RETURNS|return_true|return|return true|true"' \
// RUN:   '  ],' \
// RUN:   '  "voidCallMutationRules": [],' \
// RUN:   '  "statementMutationRules": [],' \
// RUN:   '  "sourceMutationDisplayRules": []' \
// RUN:   '}' > %t/config.json
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -emit-sil -O -module-name SwiftmutRepeatedValueApplySourceLocations %s -o /dev/null
// RUN: find %t/fragments -type f -name '*.json' -exec cat {} ';' > %t/all-fragments.json
// RUN: %FileCheck %s --input-file %t/all-fragments.json

@inline(never)
public func swiftmutContribution(_ value: Int) -> Int {
  value
}

@inline(never)
public func swiftmutCompoundCalls(_ first: Int, _ second: Int) -> Int {
  var total = 0
  total += swiftmutContribution(first)
  total += swiftmutContribution(second)
  return total
}

@inline(never)
public func swiftmutCompareLengths(_ left: String, _ right: String) -> Bool {
  left.count < right.count
}

@inline(never)
public func swiftmutComparePrefixes(_ value: String) -> Bool {
  value.hasPrefix("$s") || value.hasPrefix("@$s")
}

@_silgen_name("__swiftmut_visit")
public func __swiftmut_visit(_ siteID: UInt64) -> UInt32 {
  0
}

// CHECK-DAG: "siteKind":"valueApply"{{.*}}"sourceOriginal":"swiftmutContribution(first)","sourceMutated":"0"
// CHECK-DAG: "siteKind":"valueApply"{{.*}}"sourceOriginal":"swiftmutContribution(second)","sourceMutated":"0"
// CHECK-DAG: "siteKind":"valueApply"{{.*}}"sourceOriginal":"left.count","sourceMutated":"0"
// CHECK-DAG: "siteKind":"valueApply"{{.*}}"sourceOriginal":"right.count","sourceMutated":"0"
// CHECK-DAG: "function":"{{.*}}swiftmutComparePrefixesySbSSF"{{.*}}"siteKind":"valueApply"{{.*}}"sourceOriginal":"value.hasPrefix(\"@$s\")","sourceMutated":"false"{{.*}}"sourceOriginal":"value.hasPrefix(\"@$s\")","sourceMutated":"true"
