// RUN: rm -rf %t
// RUN: split-file %s %t
// swiftmut runs once before mandatory redundant-load elimination.
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
// RUN:   '    "integerToZero|PRIMITIVE_RETURNS|return_zero|return|return 0|0"' \
// RUN:   '  ],' \
// RUN:   '  "voidCallMutationRules": [],' \
// RUN:   '  "statementMutationRules": [],' \
// RUN:   '  "sourceMutationDisplayRules": []' \
// RUN:   '}' > %t/config.json
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-build-swift -O -D SWIFTMUT_DISCOVERY %t/main.swift -module-name SwiftmutSharedProducerBindingsRuntime -emit-sil -o /dev/null
// RUN: find %t/fragments -type f -name '*.json' -exec cat {} ';' | %{python} -c 'import json, sys; sites = [site for line in sys.stdin if line.strip() for site in json.loads(line)["sites"] if site["siteKind"] == "assignmentValue" and any(alternative["sourceOriginal"] == "start" and alternative["sourceMutated"] == "0" for alternative in site["alternatives"])]; sites.sort(key=lambda site: site["sourceLocation"]["line"]); assert [site["sourceLocation"]["line"] for site in sites] == [9, 10], sites; print("public let swiftmutComponentStartSiteID: UInt64 = {}\npublic let swiftmutIndexSiteID: UInt64 = {}".format(sites[0]["siteID"], sites[1]["siteID"]))' > %t/target.swift
// RUN: test -s %t/target.swift
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-build-swift -O %t/main.swift %t/target.swift -module-name SwiftmutSharedProducerBindingsRuntime -o %t/a.out
// RUN: %target-codesign %t/a.out
// RUN: %target-run %t/a.out component | %FileCheck %s --check-prefix=COMPONENT
// RUN: %target-run %t/a.out index | %FileCheck %s --check-prefix=INDEX
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-build-swift -O -D SWIFTMUT_BASELINE %t/main.swift -module-name SwiftmutSharedProducerBindingsRuntime -o %t/baseline.out
// RUN: %target-codesign %t/baseline.out
// RUN: %target-run %t/baseline.out | %FileCheck %s --check-prefix=BASELINE

// COMPONENT: 1003
// INDEX: 1201
// BASELINE: 1203

//--- main.swift
@inline(never)
public func swiftmutProducer(_ value: Int) -> Int {
  value
}

@inline(never)
public func swiftmutSharedProducer(_ value: Int) -> Int {
  let start = swiftmutProducer(value)
  var componentStart = start
  var index = start
  componentStart += 10
  index += 1
  return componentStart * 100 + index
}

@_silgen_name("__swiftmut_visit")
public func __swiftmut_visit(_ siteID: UInt64) -> UInt32 {
#if SWIFTMUT_DISCOVERY || SWIFTMUT_BASELINE
  return 0
#else
  let selectedSiteID = CommandLine.arguments.contains("index")
    ? swiftmutIndexSiteID
    : swiftmutComponentStartSiteID
  return siteID == selectedSiteID ? 1 : 0
#endif
}

print(swiftmutSharedProducer(2))
