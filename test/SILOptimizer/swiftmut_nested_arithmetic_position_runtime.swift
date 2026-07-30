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
// RUN:   '  "enabledMutators": ["MATH"],' \
// RUN:   '  "conditionMutationRules": [],' \
// RUN:   '  "arithmeticMutationRules": [],' \
// RUN:   '  "contextualArithmeticMutationRules": [' \
// RUN:   '    "SAddOver|otherwise|MATH|ssub_with_overflow|+|-"' \
// RUN:   '  ],' \
// RUN:   '  "returnMutationRules": [],' \
// RUN:   '  "voidCallMutationRules": [],' \
// RUN:   '  "sourceMutationDisplayRules": [' \
// RUN:   '    "MATH|SAddOver|+|-|"' \
// RUN:   '  ]' \
// RUN:   '}' > %t/config.json
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-build-swift -Onone -D SWIFTMUT_DISCOVERY %t/main.swift -module-name SwiftmutNestedArithmeticPositionRuntime -emit-sil -o /dev/null
// RUN: find %t/fragments -type f -name '*.json' -exec cat {} ';' | %{python} -c 'import json, sys; sites = (site for line in sys.stdin if line.strip() for site in json.loads(line)["sites"]); site = next(site for site in sites if any(alternative["sourceOriginal"] == "b + c" for alternative in site["alternatives"])); print("public let swiftmutTargetSiteID: UInt64 = {}".format(site["siteID"]))' > %t/target.swift
// RUN: test -s %t/target.swift
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-build-swift -Onone %t/main.swift %t/target.swift -module-name SwiftmutNestedArithmeticPositionRuntime -o %t/a.out
// RUN: %target-codesign %t/a.out
// RUN: %target-run %t/a.out | %FileCheck %s

// CHECK: 12

//--- main.swift
@inline(never)
public func swiftmutNestedArithmeticPosition(_ a: Int, _ b: Int, _ c: Int) -> Int {
  a + (b + c)
}

@_silgen_name("__swiftmut_visit")
public func __swiftmut_visit(_ siteID: UInt64) -> UInt32 {
#if SWIFTMUT_DISCOVERY
  return 0
#else
  return siteID == swiftmutTargetSiteID ? 1 : 0
#endif
}

#if !SWIFTMUT_DISCOVERY
print(swiftmutNestedArithmeticPosition(10, 3, 1))
#endif
