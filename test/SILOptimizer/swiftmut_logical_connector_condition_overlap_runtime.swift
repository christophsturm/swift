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
// RUN:   '  "enabledMutators": ["CHANGE_LOGICAL_CONNECTOR", "CONDITION_FALSE", "CONDITION_TRUE"],' \
// RUN:   '  "conditionMutationRules": [' \
// RUN:   '    "COMPARISON|CONDITION_FALSE|condition_false|condition|false",' \
// RUN:   '    "COMPARISON|CONDITION_TRUE|condition_true|condition|true"' \
// RUN:   '  ],' \
// RUN:   '  "arithmeticMutationRules": [],' \
// RUN:   '  "contextualArithmeticMutationRules": [],' \
// RUN:   '  "returnMutationRules": [],' \
// RUN:   '  "voidCallMutationRules": [],' \
// RUN:   '  "statementMutationRules": [],' \
// RUN:   '  "sourceMutationDisplayRules": []' \
// RUN:   '}' > %t/config.json
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-build-swift -O -D SWIFTMUT_DISCOVERY %t/main.swift -module-name SwiftmutLogicalConnectorConditionOverlapRuntime -emit-sil -o /dev/null
// RUN: find %t/fragments -type f -name '*.json' -exec cat {} ';' | %{python} -c 'import json, sys; sites = (site for line in sys.stdin if line.strip() for site in json.loads(line)["sites"]); site = next(site for site in sites if site["siteKind"] == "logicalConnector"); alternative = site["alternatives"][0]; print("public let swiftmutTargetSiteID: UInt64 = {}\npublic let swiftmutTargetAlternative: UInt32 = {}".format(site["siteID"], alternative["alternativeIndex"]))' > %t/target.swift
// RUN: test -s %t/target.swift
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-build-swift -O %t/main.swift %t/target.swift -module-name SwiftmutLogicalConnectorConditionOverlapRuntime -o %t/a.out
// RUN: %target-codesign %t/a.out
// RUN: %target-run %t/a.out | %FileCheck %s
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-build-swift -O -D SWIFTMUT_BASELINE %t/main.swift -module-name SwiftmutLogicalConnectorConditionOverlapRuntime -o %t/baseline.out
// RUN: %target-codesign %t/baseline.out
// RUN: %target-run %t/baseline.out | %FileCheck %s --check-prefix=BASELINE
// RUN: find %t/fragments -type f -name '*.json' -exec cat {} ';' | sort -u > %t/all-fragments.json
// RUN: %{python} -c 'import json, sys; sites = [site for line in open(sys.argv[1]) if line.strip() for site in json.loads(line)["sites"]]; compound = [site for site in sites if site["siteKind"] == "condition"]; assert not compound, compound' %t/all-fragments.json
// RUN: %FileCheck %s --check-prefix=MANIFEST --input-file %t/all-fragments.json

// CHECK: true
// BASELINE: false
// MANIFEST: "siteKind":"logicalConnector",{{.*}}"resultKind":"condition"
// MANIFEST-SAME: "sourceOriginal":"&&"
// MANIFEST-SAME: "sourceMutated":"||"

//--- main.swift
@inline(never)
public func swiftmutConditionWithConnector(_ left: Bool, _ right: Bool) -> Bool {
  if left && right {
    return true
  }
  return false
}

@_silgen_name("__swiftmut_visit")
public func __swiftmut_visit(_ siteID: UInt64) -> UInt32 {
#if SWIFTMUT_DISCOVERY || SWIFTMUT_BASELINE
  return 0
#else
  return siteID == swiftmutTargetSiteID ? swiftmutTargetAlternative : 0
#endif
}

print(swiftmutConditionWithConnector(false, true))
