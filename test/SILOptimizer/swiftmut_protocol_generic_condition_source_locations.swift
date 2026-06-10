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
// RUN:   '  "enabledMutators": ["NEGATE_CONDITIONALS"],' \
// RUN:   '  "conditionMutationRules": [' \
// RUN:   '    "ICMP_EQ|NEGATE_CONDITIONALS|cmp_ne|==|!="' \
// RUN:   '  ],' \
// RUN:   '  "arithmeticMutationRules": [],' \
// RUN:   '  "contextualArithmeticMutationRules": [],' \
// RUN:   '  "returnMutationRules": [],' \
// RUN:   '  "voidCallMutationRules": [],' \
// RUN:   '  "sourceMutationDisplayRules": [' \
// RUN:   '    "NEGATE_CONDITIONALS|ICMP_EQ|==|!=|"' \
// RUN:   '  ]' \
// RUN:   '}' > %t/config.json
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -emit-sil -O -wmo -cross-module-optimization -module-name SwiftmutProtocolGenericConditionSourceLocations -external-pass-pipeline-filename %t/pipeline.yaml %s -o /dev/null
// RUN: %FileCheck %s --input-file %t/compiler-events.jsonl
// RUN: find %t/fragments -type f -name '*.json' -exec cat {} ';' > %t/all-fragments.json
// RUN: %FileCheck %s --check-prefix=MANIFEST --input-file %t/all-fragments.json

public protocol SwiftmutProtocolGenericIdentified {
  var siteID: UInt64 { get }
}

public struct SwiftmutProtocolGenericSelection: SwiftmutProtocolGenericIdentified {
  public let siteID: UInt64
  public let alternativeIndex: UInt32

  public init(siteID: UInt64, alternativeIndex: UInt32) {
    self.siteID = siteID
    self.alternativeIndex = alternativeIndex
  }
}

@_specialize(where T == SwiftmutProtocolGenericSelection)
public func swiftmutProtocolGenericContains<T: SwiftmutProtocolGenericIdentified>(
  _ values: [T],
  siteID: UInt64
) -> Bool {
  for value in values {
    if value.siteID == siteID {
      return true
    }
  }
  return false
}

public func swiftmutProtocolGenericContainsSite(
  _ selections: [SwiftmutProtocolGenericSelection],
  siteID: UInt64
) -> Bool {
  swiftmutProtocolGenericContains(selections, siteID: siteID)
}

@_silgen_name("__swiftmut_visit")
public func __swiftmut_visit(_ siteID: UInt64) -> UInt32 {
  0
}

// CHECK: "event":"metamutantDiscovery","module":"SwiftmutProtocolGenericConditionSourceLocations","function":"{{[^\"]*}}swiftmutbC8Contains{{[^\"]*}}"
// CHECK-SAME: "conditionSites":"1"
// CHECK-SAME: "conditionSourceLocationMisses":"0"
// MANIFEST: "siteKind":"condition"
// MANIFEST-SAME: "sourceOriginal":"value.siteID == siteID","sourceMutated":"value.siteID != siteID"
