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
// RUN:   '  "enabledMutators": ["CONDITION_FALSE", "CONDITION_TRUE"],' \
// RUN:   '  "conditionMutationRules": [' \
// RUN:   '    "COMPARISON|CONDITION_FALSE|condition_false|condition|false",' \
// RUN:   '    "COMPARISON|CONDITION_TRUE|condition_true|condition|true"' \
// RUN:   '  ],' \
// RUN:   '  "arithmeticMutationRules": [],' \
// RUN:   '  "contextualArithmeticMutationRules": [],' \
// RUN:   '  "returnMutationRules": [],' \
// RUN:   '  "voidCallMutationRules": [],' \
// RUN:   '  "sourceMutationDisplayRules": []' \
// RUN:   '}' > %t/config.json
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -emit-sil -O -module-name SwiftmutPredicateCallConditionSourceLocations -external-pass-pipeline-filename %t/pipeline.yaml %s -o /dev/null
// RUN: find %t/fragments -type f -name '*.json' -exec cat {} ';' > %t/all-fragments.json
// RUN: %FileCheck %s --input-file %t/all-fragments.json
// RUN: %FileCheck %s --check-prefix=EVENTS --input-file %t/compiler-events.jsonl

public struct SwiftmutPredicateSite {
  public let function: String
}

@inline(never)
public func swiftmutIsGeneratedClone(_ function: String) -> Bool {
  function.hasPrefix("clone")
}

@inline(never)
public func swiftmutIsGeneratedThunk(_ function: String) -> Bool {
  function.hasSuffix("Thunk")
}

public func swiftmutPredicateReason(_ site: SwiftmutPredicateSite) -> Int {
  if swiftmutIsGeneratedClone(site.function)
      || swiftmutIsGeneratedThunk(site.function) {
    return 1
  }

  if swiftmutIsGeneratedThunk(site.function) {
    return 2
  }

  return 0
}

@_silgen_name("__swiftmut_visit")
public func __swiftmut_visit(_ siteID: UInt64) -> UInt32 {
  0
}

// CHECK-DAG: "line":44,"column":6
// CHECK-DAG: "sourceOriginal":"swiftmutIsGeneratedClone(site.function)","sourceMutated":"false"
// CHECK-DAG: "sourceOriginal":"swiftmutIsGeneratedClone(site.function)","sourceMutated":"true"
// CHECK-DAG: "line":49,"column":6
// CHECK-DAG: "sourceOriginal":"swiftmutIsGeneratedThunk(site.function)","sourceMutated":"false"
// CHECK-DAG: "sourceOriginal":"swiftmutIsGeneratedThunk(site.function)","sourceMutated":"true"

// EVENTS: "event":"metamutantDiscovery"{{.*}}"conditionBranches":"3"{{.*}}"conditionSites":"2"{{.*}}"conditionSourceLocationMisses":"0"
