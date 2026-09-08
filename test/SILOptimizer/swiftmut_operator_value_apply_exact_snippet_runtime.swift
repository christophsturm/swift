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
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-build-swift -Onone -D SWIFTMUT_DISCOVERY %t/main.swift -module-name SwiftmutOperatorValueApplyExactSnippetRuntime -emit-sil -o /dev/null
// RUN: find %t/fragments -type f -name '*.json' -exec cat {} ';' | %{python} %S/Inputs/swiftmut-render-condition-ranges.py %t | %{python} -c 'import json, sys; sites = (site for line in sys.stdin if line.strip() for site in json.loads(line)["sites"]); site = next(site for site in sites if site["siteKind"] == "valueApply" and any(alternative["sourceOriginal"] == "left < right" and alternative["sourceMutated"] == "right < left" for alternative in site["alternatives"])); alternative = next(alternative for alternative in site["alternatives"] if alternative["sourceMutated"] == "right < left"); print("public let swiftmutTargetSiteID: UInt64 = {}\npublic let swiftmutTargetAlternative: UInt32 = {}".format(site["siteID"], alternative["alternativeIndex"]))' > %t/target.swift
// RUN: test -s %t/target.swift
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-build-swift -Onone %t/main.swift %t/target.swift -module-name SwiftmutOperatorValueApplyExactSnippetRuntime -o %t/a.out
// RUN: %target-codesign %t/a.out
// RUN: %target-run %t/a.out | %FileCheck %s
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-build-swift -Onone -D SWIFTMUT_BASELINE %t/main.swift -module-name SwiftmutOperatorValueApplyExactSnippetRuntime -o %t/baseline.out
// RUN: %target-codesign %t/baseline.out
// RUN: %target-run %t/baseline.out | %FileCheck %s --check-prefix=BASELINE
// RUN: find %t/fragments -type f -name '*.json' -exec cat {} ';' | %{python} %S/Inputs/swiftmut-render-condition-ranges.py %t | sort -u > %t/all-fragments.json
// RUN: %FileCheck %s --check-prefix=MANIFEST --input-file %t/all-fragments.json

// CHECK: true
// BASELINE: false
// MANIFEST: "siteKind":"valueApply"
// MANIFEST-SAME: "sourceOriginal":"left < right"
// MANIFEST-SAME: "sourceMutated":"right < left"

//--- main.swift
@inline(never)
public func swiftmutRuleNameOrder(_ left: String, _ right: String) -> Bool {
  if left.count != right.count {
    return left.count < right.count
  }
  return left < right
}

@_silgen_name("__swiftmut_visit")
public func __swiftmut_visit(_ siteID: UInt64) -> UInt32 {
#if SWIFTMUT_DISCOVERY || SWIFTMUT_BASELINE
  return 0
#else
  return siteID == swiftmutTargetSiteID ? swiftmutTargetAlternative : 0
#endif
}

print(swiftmutRuleNameOrder("b", "a"))
