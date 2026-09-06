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
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -emit-sil -O -module-name SwiftmutStringDescriptionOverloadSourceLocations %s -o /dev/null
// RUN: cat %t/fragments/*.json | %FileCheck %s
// RUN: cat %t/fragments/*.json | not %FileCheck %s --check-prefix=NO-REPEATING
// RUN: cat %t/fragments/*.json | not %FileCheck %s --check-prefix=NO-DECODING

@inline(never)
public func swiftmutConsumeString(_ value: String) {
  _ = value.isEmpty
}

public func swiftmutStringDescriptionOverloads(_ value: Int, _ bytes: [UInt8]) -> String {
  swiftmutConsumeString(String(repeating: "x", count: value))
  swiftmutConsumeString(String(decoding: bytes, as: UTF8.self))
  return String(value)
}

// CHECK: "sourceOriginal":"String(value)","sourceMutated":"\"\""
// NO-REPEATING: "sourceOriginal":"String(repeating:
// NO-DECODING: "sourceOriginal":"String(decoding:
