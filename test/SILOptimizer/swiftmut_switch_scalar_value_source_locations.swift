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
// RUN:   '  "enabledMutators": ["FALSE_RETURNS", "TRUE_RETURNS"],' \
// RUN:   '  "conditionMutationRules": [],' \
// RUN:   '  "arithmeticMutationRules": [],' \
// RUN:   '  "contextualArithmeticMutationRules": [],' \
// RUN:   '  "returnMutationRules": [' \
// RUN:   '    "boolToFalse|FALSE_RETURNS|return_false|return|return false|false",' \
// RUN:   '    "boolToTrue|TRUE_RETURNS|return_true|return|return true|true"' \
// RUN:   '  ],' \
// RUN:   '  "voidCallMutationRules": [],' \
// RUN:   '  "sourceMutationDisplayRules": []' \
// RUN:   '}' > %t/config.json
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -emit-sil -O -module-name SwiftmutSwitchScalarValueSourceLocations -external-pass-pipeline-filename %t/pipeline.yaml %s -o /dev/null
// RUN: find %t/fragments -type f -name '*.json' -exec cat {} ';' > %t/all-fragments.json
// RUN: %FileCheck %s --input-file %t/all-fragments.json

public enum SwiftmutMode {
  case buildOnly
  case test
}

public func swiftmutClassifyScalarValue(_ mode: SwiftmutMode, exitCode: Int) -> Bool {
  switch mode {
  case .buildOnly:
    return exitCode == 0
  case .test:
    if exitCode == 0 {
      return true
    }
    return false
  }
}

@_silgen_name("__swiftmut_visit")
public func __swiftmut_visit(_ siteID: UInt64) -> UInt32 {
  0
}

// CHECK: "sourceLocation":{"file":"swiftmut_switch_scalar_value_source_locations.swift","line":36,"column":5}
// CHECK: "siteKind":"scalarValue"
// CHECK: "sourceOriginal":"return","sourceMutated":"return false"
// CHECK: "sourceLocation":{"file":"swiftmut_switch_scalar_value_source_locations.swift","line":39,"column":7}
// CHECK: "sourceOriginal":"return","sourceMutated":"return false"
// CHECK: "sourceLocation":{"file":"swiftmut_switch_scalar_value_source_locations.swift","line":41,"column":5}
// CHECK: "sourceOriginal":"return","sourceMutated":"return true"
