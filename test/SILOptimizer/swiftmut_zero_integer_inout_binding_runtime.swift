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
// RUN:   '  "enabledMutators": ["PRIMITIVE_RETURNS"],' \
// RUN:   '  "conditionMutationRules": [],' \
// RUN:   '  "arithmeticMutationRules": [],' \
// RUN:   '  "contextualArithmeticMutationRules": [],' \
// RUN:   '  "returnMutationRules": [' \
// RUN:   '    "integerToZero|PRIMITIVE_RETURNS|return_zero|return|return 0|0",' \
// RUN:   '    "integerToOne|PRIMITIVE_RETURNS|return_one|return|return 1|1"' \
// RUN:   '  ],' \
// RUN:   '  "voidCallMutationRules": [],' \
// RUN:   '  "statementMutationRules": [],' \
// RUN:   '  "sourceMutationDisplayRules": []' \
// RUN:   '}' > %t/config.json
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-build-swift -Onone -D SWIFTMUT_DISCOVERY %t/main.swift -module-name SwiftmutZeroIntegerInoutBindingRuntime -emit-sil -o /dev/null
// RUN: find %t/fragments -type f -name '*.json' -exec cat {} ';' | %{python} -c 'import json, sys; sites = (site for line in sys.stdin if line.strip() for site in json.loads(line)["sites"]); site = next(site for site in sites if site["siteKind"] == "scalarValue" and site["sourceLocation"]["line"] == 10 and any(alternative["sourceOriginal"] == "0" and alternative["sourceMutated"] == "1" for alternative in site["alternatives"])); print("public let swiftmutTargetSiteID: UInt64 = {}".format(site["siteID"]))' > %t/target.swift
// RUN: test -s %t/target.swift
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-build-swift -Onone %t/main.swift %t/target.swift -module-name SwiftmutZeroIntegerInoutBindingRuntime -o %t/a.out
// RUN: %target-codesign %t/a.out
// RUN: %target-run %t/a.out | %FileCheck %s
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-build-swift -Onone -D SWIFTMUT_BASELINE %t/main.swift -module-name SwiftmutZeroIntegerInoutBindingRuntime -o %t/baseline.out
// RUN: %target-codesign %t/baseline.out
// RUN: %target-run %t/baseline.out | %FileCheck %s --check-prefix=BASELINE

// CHECK: 15
// BASELINE: 14

//--- main.swift
@inline(never)
func swiftmutRecordAudit(_ total: inout Int, _ value: Int) {
  total += value
}

@inline(never)
public func swiftmutAudited(_ value: Int) -> Int {
  var total = 0
  total += value
  var audit = 0
  swiftmutRecordAudit(&audit, value)
  return total + audit
}

@_silgen_name("__swiftmut_visit")
public func __swiftmut_visit(_ siteID: UInt64) -> UInt32 {
#if SWIFTMUT_DISCOVERY || SWIFTMUT_BASELINE
  return 0
#else
  return siteID == swiftmutTargetSiteID ? 1 : 0
#endif
}

print(swiftmutAudited(7))
