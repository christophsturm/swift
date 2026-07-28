// RUN: rm -rf %t
// RUN: mkdir -p %t
// RUN: printf '%%s\n' '---' "name: ''" 'passes: [ "\"swiftmut\"" ]' > %t/pipeline.yaml
// RUN: printf '%b\n' \
// RUN:   '{' \
// RUN:   '  "mode": "metamutant",' \
// RUN:   '  "manifestPath": "%t/mutants.jsonl",' \
// RUN:   '  "manifestFragmentsDirectory": "%t/fragments",' \
// RUN:   '  "compilerEventsPath": "%t/compiler-events.jsonl",' \
// RUN:   '  "packageRoot": "%S",' \
// RUN:   '  "excludePaths": [],' \
// RUN:   '  "sourceFiles": ["%s"],' \
// RUN:   '  "enabledMutators": ["FALSE_RETURNS", "TRUE_RETURNS", "CONDITION_FALSE", "CONDITION_TRUE"],' \
// RUN:   '  "conditionMutationRules": [' \
// RUN:   '    "COMPARISON|CONDITION_FALSE|condition_false|condition|false",' \
// RUN:   '    "COMPARISON|CONDITION_TRUE|condition_true|condition|true"' \
// RUN:   '  ],' \
// RUN:   '  "arithmeticMutationRules": [],' \
// RUN:   '  "contextualArithmeticMutationRules": [],' \
// RUN:   '  "returnMutationRules": [' \
// RUN:   '    "boolToFalse|FALSE_RETURNS|return_false|return|return false|false",' \
// RUN:   '    "boolToTrue|TRUE_RETURNS|return_true|return|return true|true"' \
// RUN:   '  ],' \
// RUN:   '  "voidCallMutationRules": [],' \
// RUN:   '  "sourceMutationDisplayRules": []' \
// RUN:   '}' > %t/config.json
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -emit-sil -O -module-name SwiftmutClosureArgumentReturnSourceLocations -external-pass-pipeline-filename %t/pipeline.yaml %s -o /dev/null
// RUN: find %t/fragments -type f -name '*.json' -exec cat {} ';' > %t/all-fragments.json
// RUN: %FileCheck %s --input-file %t/all-fragments.json
// RUN: %FileCheck %s --check-prefix=EVENTS --input-file %t/compiler-events.jsonl

public func swiftmutClosureArgumentSplit(_ text: String) -> [Substring] {
  text.split(whereSeparator: \.isNewline)
}

public func swiftmutClosureArgumentSplitInFor(_ text: String) -> Int {
  var count = 0
  for line in text.split(whereSeparator: \.isNewline) {
    count += line.count
  }
  return count
}

@_silgen_name("__swiftmut_visit")
public func __swiftmut_visit(_ siteID: UInt64) -> UInt32 {
  0
}

// CHECK-NOT: "siteKind":"valueApply"
// CHECK: "siteKind":"returnValue"
// CHECK: "sourceOriginal":"\\.isNewline","sourceMutated":"{ _ in false }"
// CHECK: "sourceOriginal":"\\.isNewline","sourceMutated":"{ _ in true }"
// CHECK-NOT: "siteKind":"valueApply"
// CHECK: "siteKind":"returnValue"
// CHECK: "sourceOriginal":"\\.isNewline","sourceMutated":"{ _ in false }"
// CHECK: "sourceOriginal":"\\.isNewline","sourceMutated":"{ _ in true }"
// CHECK-NOT: "siteKind":"valueApply"
// EVENTS: "event":"functionVisit"
// EVENTS-NOT: "event":"valueApplySourceLocationMiss"
// EVENTS-NOT: "event":"scalarValueSourceLocationMiss"
// EVENTS-NOT: "event":"conditionSourceLocationMiss"
