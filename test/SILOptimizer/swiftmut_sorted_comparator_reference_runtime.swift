// RUN: rm -rf %t
// RUN: split-file %s %t
// swiftmut runs in the native Diagnostic pipeline.
// RUN: printf '%b\n' \
// RUN:   '{' \
// RUN:   '  "mode": "metamutant",' \
// RUN:   '  "manifestPath": "%t/mutants.jsonl",' \
// RUN:   '  "manifestFragmentsDirectory": "%t/fragments",' \
// RUN:   '  "compilerEventsPath": "%t/compiler-events.jsonl",' \
// RUN:   '  "packageRoot": "%t",' \
// RUN:   '  "excludePaths": [],' \
// RUN:   '  "sourceFiles": ["%t/main.swift"],' \
// RUN:   '  "enabledMutators": ["NEGATE_CONDITIONALS"],' \
// RUN:   '  "conditionMutationRules": [],' \
// RUN:   '  "arithmeticMutationRules": [],' \
// RUN:   '  "contextualArithmeticMutationRules": [],' \
// RUN:   '  "returnMutationRules": [],' \
// RUN:   '  "voidCallMutationRules": [],' \
// RUN:   '  "statementMutationRules": [],' \
// RUN:   '  "sourceMutationDisplayRules": []' \
// RUN:   '}' > %t/config.json
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-build-swift -Onone -D SWIFTMUT_DISCOVERY %t/main.swift -module-name SwiftmutSortedComparatorReferenceRuntime -emit-sil -o /dev/null
// RUN: find %t/fragments -type f -name '*.json' -exec cat {} ';' | %{python} %S/Inputs/swiftmut-render-condition-ranges.py %t | %{python} -c 'import json, sys; sites = (site for line in sys.stdin if line.strip() for site in json.loads(line)["sites"]); site = next(site for site in sites if site["siteKind"] == "valueApply" and any(alternative["sourceOriginal"] == "Self.swiftmutOrder" and alternative["sourceMutated"] == "{ left, right in (Self.swiftmutOrder)(right, left) }" for alternative in site["alternatives"])); alternative = next(alternative for alternative in site["alternatives"] if alternative["sourceOriginal"] == "Self.swiftmutOrder" and alternative["sourceMutated"] == "{ left, right in (Self.swiftmutOrder)(right, left) }"); print("public let swiftmutTargetSiteID: UInt64 = {}\npublic let swiftmutTargetAlternative: UInt32 = {}".format(site["siteID"], alternative["alternativeIndex"]))' > %t/target.swift
// RUN: test -s %t/target.swift
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-build-swift -Onone %t/main.swift %t/target.swift -module-name SwiftmutSortedComparatorReferenceRuntime -o %t/a.out
// RUN: %target-codesign %t/a.out
// RUN: %target-run %t/a.out | %FileCheck %s
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-build-swift -Onone -D SWIFTMUT_BASELINE %t/main.swift -module-name SwiftmutSortedComparatorReferenceRuntime -o %t/baseline.out
// RUN: %target-codesign %t/baseline.out
// RUN: %target-run %t/baseline.out | %FileCheck %s --check-prefix=BASELINE
// RUN: find %t/fragments -type f -name '*.json' -exec cat {} ';' | %{python} %S/Inputs/swiftmut-render-condition-ranges.py %t | sort -u > %t/all-fragments.json
// RUN: %FileCheck %s --check-prefix=MANIFEST --input-file %t/all-fragments.json

// CHECK: ba
// BASELINE: ab
// MANIFEST: "siteKind":"valueApply"{{.*}}"sourceOriginal":"Self.swiftmutOrder","sourceMutated":"{ left, right in (Self.swiftmutOrder)(right, left) }"

//--- main.swift
public struct SwiftmutOrdering {
  public let values: [String]

  @inline(never)
  public init(values: [String]) {
    self.values = values.sorted(by: Self.swiftmutOrder)
  }

  @inline(never)
  static func swiftmutOrder(_ left: String, _ right: String) -> Bool {
    left < right
  }
}

@_silgen_name("__swiftmut_visit")
public func __swiftmut_visit(_ siteID: UInt64) -> UInt32 {
#if SWIFTMUT_DISCOVERY || SWIFTMUT_BASELINE
  return 0
#else
  return siteID == swiftmutTargetSiteID ? swiftmutTargetAlternative : 0
#endif
}

print(SwiftmutOrdering(values: ["b", "a"]).values.joined())
