// RUN: rm -rf %t
// RUN: mkdir -p %t
// swiftmut runs in the native Diagnostic pipeline.
// RUN: printf '%b\n' \
// RUN:   '{' \
// RUN:   '  "mode": "discover",' \
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
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -emit-sil -O -module-name SwiftmutDefaultArgumentReturnSourceLocations %s -o /dev/null
// RUN: %FileCheck %s --input-file %t/mutants.jsonl

public func swiftmutUseDefaultReturn(_ value: Int = 7) -> Int {
  value
}

public func swiftmutCallDefaultReturn() -> Int {
  swiftmutUseDefaultReturn()
}

// The optimized SIL inlines the default argument into the caller. Keep the
// mutation anchored to the outer call rather than claiming the declaration's
// default expression as a separately instrumented site.
// CHECK-NOT: "sourceOriginal":"7","sourceMutated":"0"
// CHECK: "sourceOriginal":"swiftmutUseDefaultReturn()","sourceMutated":"0"
