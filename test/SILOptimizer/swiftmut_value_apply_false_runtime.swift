// RUN: rm -rf %t
// RUN: split-file %s %t
// RUN: printf '%%s\n' '---' "name: ''" 'passes: [ "\"swiftmut\"" ]' > %t/pipeline.yaml
// RUN: printf '%b\n' \
// RUN:   '{' \
// RUN:   '  "mode": "metamutant",' \
// RUN:   '  "manifestPath": "%t/mutants.jsonl",' \
// RUN:   '  "manifestFragmentsDirectory": "%t/fragments",' \
// RUN:   '  "compilerEventsPath": "%t/compiler-events.jsonl",' \
// RUN:   '  "packageRoot": "%t",' \
// RUN:   '  "excludePaths": [],' \
// RUN:   '  "sourceFiles": ["%t/main.swift"],' \
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
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-build-swift -O %t/Value.swift %t/main.swift -module-name SwiftmutValueApplyFalseRuntime -Xfrontend -external-pass-pipeline-filename -Xfrontend %t/pipeline.yaml -o %t/a.out
// RUN: %target-codesign %t/a.out
// RUN: %target-run %t/a.out | %FileCheck %s
// RUN: %FileCheck %s --check-prefix=EVENTS --input-file %t/compiler-events.jsonl

// CHECK: false
// EVENTS: "event":"metamutantInjection"
// EVENTS-SAME: "function":"{{.*}}swiftmutProbeyySSF"
// EVENTS-SAME: "attemptedValueApplySites":"1"
// EVENTS-SAME: "injectedValueApplySites":"1"

//--- Value.swift
@inline(never)
public func swiftmutIsAtPrefix(_ text: String) -> Bool {
  return text.hasPrefix("@")
}

//--- main.swift
@_silgen_name("__swiftmut_visit")
public func __swiftmut_visit(_ siteID: UInt64) -> UInt32 {
  return 1
}

public func swiftmutProbe(_ text: String) {
  print(swiftmutIsAtPrefix(text))
}

swiftmutProbe("@flag")
