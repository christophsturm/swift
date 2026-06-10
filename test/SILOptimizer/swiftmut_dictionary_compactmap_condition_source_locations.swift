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
// RUN:   '  "enabledMutators": ["NEGATE_CONDITIONALS", "CONDITION_FALSE", "CONDITION_TRUE"],' \
// RUN:   '  "conditionMutationRules": [' \
// RUN:   '    "ICMP_NE|NEGATE_CONDITIONALS|cmp_eq|!=|==",' \
// RUN:   '    "COMPARISON|CONDITION_FALSE|condition_false|condition|false",' \
// RUN:   '    "COMPARISON|CONDITION_TRUE|condition_true|condition|true"' \
// RUN:   '  ],' \
// RUN:   '  "arithmeticMutationRules": [],' \
// RUN:   '  "contextualArithmeticMutationRules": [],' \
// RUN:   '  "returnMutationRules": [],' \
// RUN:   '  "voidCallMutationRules": [],' \
// RUN:   '  "sourceMutationDisplayRules": [' \
// RUN:   '    "NEGATE_CONDITIONALS|ICMP_NE|!=|==|",' \
// RUN:   '    "CONDITION_FALSE|ICMP_NE|!=|!=|false",' \
// RUN:   '    "CONDITION_TRUE|ICMP_NE|!=|!=|true"' \
// RUN:   '  ]' \
// RUN:   '}' > %t/config.json
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -emit-sil -O -module-name SwiftmutDictionaryCompactMapConditionSourceLocations -external-pass-pipeline-filename %t/pipeline.yaml %s -o /dev/null
// RUN: find %t/fragments -type f -name '*.json' -exec cat {} ';' > %t/all-fragments.json
// RUN: %FileCheck %s --input-file %t/all-fragments.json
// RUN: %FileCheck %s --check-prefix=EVENTS --input-file %t/compiler-events.jsonl

public struct SwiftmutEvidence {
  public let functions: Set<String>
  public let siteIDs: Set<String>
}

@inline(never)
public func swiftmutLooksLikeInitializer(_ name: String) -> Bool {
  name.hasSuffix(".init")
}

public func swiftmutDictionaryCompactMapKeys(
  _ evidenceByKey: [String: SwiftmutEvidence]
) -> Set<String> {
  Set(evidenceByKey.compactMap { key, evidence in
    if evidence.functions.count != 1 || evidence.siteIDs.count != 1 {
      return key
    }
    return evidence.functions.contains(where: swiftmutLooksLikeInitializer) ? key : nil
  })
}

@_silgen_name("__swiftmut_visit")
public func __swiftmut_visit(_ siteID: UInt64) -> UInt32 {
  0
}

// CHECK-DAG: "line":48,"column":8
// CHECK-DAG: "sourceOriginal":"evidence.functions.count != 1 || evidence.siteIDs.count != 1","sourceMutated":"evidence.functions.count == 1 || evidence.siteIDs.count != 1"
// CHECK-DAG: "sourceOriginal":"evidence.functions.count != 1 || evidence.siteIDs.count != 1","sourceMutated":"false"
// CHECK-DAG: "sourceOriginal":"evidence.functions.count != 1 || evidence.siteIDs.count != 1","sourceMutated":"true"

// EVENTS: "event":"metamutantDiscovery"{{.*}}"conditionSourceLocationMisses":"0"
