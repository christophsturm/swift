// RUN: rm -rf %t
// RUN: mkdir -p %t
// RUN: %sil-passpipeline-dumper --Diagnostic > %t/diagnostic-pipeline.yaml
// RUN: %FileCheck %s --check-prefix=PIPELINE --input-file %t/diagnostic-pipeline.yaml
// RUN: %sil-passpipeline-dumper --Performance > %t/performance-pipeline.yaml
// RUN: %FileCheck %s --check-prefix=NO-PIPELINE --input-file %t/performance-pipeline.yaml
// RUN: %sil-passpipeline-dumper --Onone > %t/onone-pipeline.yaml
// RUN: %FileCheck %s --check-prefix=NO-PIPELINE --input-file %t/onone-pipeline.yaml
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
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -emit-sil -O -module-name SwiftmutNativePipeline %s -o /dev/null
// RUN: find %t/fragments -type f -name '*.json' -exec cat {} ';' > %t/performance-fragments.json
// RUN: %FileCheck %s --check-prefix=PERFORMANCE-MANIFEST --input-file %t/performance-fragments.json
// RUN: rm -rf %t/fragments
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -emit-sil -Onone -module-name SwiftmutNativePipeline %s -o /dev/null
// RUN: find %t/fragments -type f -name '*.json' -exec cat {} ';' > %t/onone-fragments.json
// RUN: %FileCheck %s --check-prefix=ONONE-MANIFEST --input-file %t/onone-fragments.json
// RUN: diff -u %t/performance-fragments.json %t/onone-fragments.json
// RUN: env SWIFTMUT_CONFIG= %target-swift-frontend -emit-sil -O -module-name SwiftmutNativePerformancePipelineNoSession %s -o /dev/null
// RUN: env SWIFTMUT_CONFIG= %target-swift-frontend -emit-sil -Onone -module-name SwiftmutNativeOnonePipelineNoSession %s -o /dev/null

// PIPELINE: "inline-always-inlining",
// PIPELINE-NEXT: "swiftmut" ]

// NO-PIPELINE-NOT: "swiftmut"

// PERFORMANCE-MANIFEST: "module":"SwiftmutNativePipeline"
// PERFORMANCE-MANIFEST-SAME: "function":"{{[^"]+}}"
// PERFORMANCE-MANIFEST-SAME: "siteKind":"returnValue"
// PERFORMANCE-MANIFEST-SAME: "sourceOriginal":"value"
// PERFORMANCE-MANIFEST-SAME: "sourceMutated":"false"

// ONONE-MANIFEST: "module":"SwiftmutNativePipeline"
// ONONE-MANIFEST-SAME: "function":"{{[^"]+}}"
// ONONE-MANIFEST-SAME: "siteKind":"returnValue"
// ONONE-MANIFEST-SAME: "sourceOriginal":"value"
// ONONE-MANIFEST-SAME: "sourceMutated":"false"

public func swiftmutNativePipeline(_ value: Bool) -> Bool {
  value
}
