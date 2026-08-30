// RUN: rm -rf %t
// RUN: mkdir -p %t
// swiftmut runs in the native Diagnostic pipeline.
// RUN: printf '%b\n' \
// RUN:   '{' \
// RUN:   '  "mode": "metamutant",' \
// RUN:   '  "manifestPath": "%t/mutants.jsonl",' \
// RUN:   '  "manifestFragmentsDirectory": "%t/fragments",' \
// RUN:   '  "compilerEventsPath": "%t/compiler-events.jsonl",' \
// RUN:   '  "packageRoot": "%S",' \
// RUN:   '  "excludePaths": [],' \
// RUN:   '  "sourceFiles": ["%s"],' \
// RUN:   '  "enabledMutators": ["CHANGE_LOGICAL_CONNECTOR"],' \
// RUN:   '  "conditionMutationRules": [],' \
// RUN:   '  "arithmeticMutationRules": [],' \
// RUN:   '  "contextualArithmeticMutationRules": [],' \
// RUN:   '  "returnMutationRules": [],' \
// RUN:   '  "voidCallMutationRules": [],' \
// RUN:   '  "statementMutationRules": [],' \
// RUN:   '  "sourceMutationDisplayRules": []' \
// RUN:   '}' > %t/config.json
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -emit-sil -O -module-name SwiftmutReferencedAutoclosure %s -o /dev/null
// RUN: find %t/fragments -type f -name '*.json' -exec cat {} ';' > %t/all-fragments.json
// RUN: %FileCheck %s --input-file %t/all-fragments.json
// RUN: %FileCheck %s --check-prefix=EVENTS --input-file %t/compiler-events.jsonl

@inline(never)
public func swiftmutRetainAutoclosure(
  _ value: @escaping @autoclosure () -> Bool
) -> () -> Bool {
  value
}

public func swiftmutMakeAutoclosure(
  _ left: Bool,
  _ right: Bool
) -> () -> Bool {
  swiftmutRetainAutoclosure(left && right)
}

// CHECK: "function":"{{.*}}Sbycfu_"{{.*}}"siteKind":"logicalConnector"

// EVENTS: "event":"functionVisit"{{.*}}"function":"{{.*}}Sbycfu_"
// EVENTS-NOT: "event":"functionSkip"{{.*}}"reason":"generatedUnreferencedClosure"{{.*}}"function":"{{.*}}Sbycfu_"
// EVENTS: "function":"{{.*}}Sbycfu_"{{.*}}"logicalConnectorSites":"1"
