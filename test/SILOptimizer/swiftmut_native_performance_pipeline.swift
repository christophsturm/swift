// RUN: rm -rf %t
// RUN: mkdir -p %t
// RUN: %sil-passpipeline-dumper --Performance > %t/performance-pipeline.yaml
// RUN: %FileCheck %s --check-prefix=PIPELINE --input-file %t/performance-pipeline.yaml
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
// RUN:   '  "statementMutationRules": [],' \
// RUN:   '  "sourceMutationDisplayRules": []' \
// RUN:   '}' > %t/config.json
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -emit-sil -O -module-name SwiftmutNativePerformancePipeline %s -o /dev/null
// RUN: find %t/fragments -type f -name '*.json' -exec cat {} ';' > %t/all-fragments.json
// RUN: %FileCheck %s --check-prefix=MANIFEST --input-file %t/all-fragments.json
// RUN: env SWIFTMUT_CONFIG=%t/missing-config.json %target-swift-frontend -emit-sil -O -module-name SwiftmutNativePerformancePipelineNoSession %s -o /dev/null

// PIPELINE: name:            LateLoopOpt
// PIPELINE-NEXT: passes:          [ "swiftmut", "late-deadfuncelim", "code-sinking",

// MANIFEST: "module":"SwiftmutNativePerformancePipeline"
// MANIFEST-SAME: "function":"{{[^"]+}}"
// MANIFEST-SAME: "siteKind":"returnValue"
// MANIFEST-SAME: "sourceOriginal":"value"
// MANIFEST-SAME: "sourceMutated":"false"

public func swiftmutNativePipeline(_ value: Bool) -> Bool {
  value
}
