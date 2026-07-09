// RUN: rm -rf %t
// RUN: split-file %s %t
// RUN: printf '%b\n' '---' "name: ''" 'passes: [ "\"swiftmut\"" ]' > %t/pipeline.yaml
// RUN: printf '%b\n' \
// RUN:   '{' \
// RUN:   '  "mode": "metamutant",' \
// RUN:   '  "manifestPath": "%t/mutants.jsonl",' \
// RUN:   '  "manifestFragmentsDirectory": "%t/fragments",' \
// RUN:   '  "compilerEventsPath": "%t/compiler-events.jsonl",' \
// RUN:   '  "packageRoot": "%t",' \
// RUN:   '  "excludePaths": [],' \
// RUN:   '  "sourceFiles": ["%t/Classifier.swift", "%t/main.swift"],' \
// RUN:   '  "enabledMutators": ["CONDITION_FALSE", "CONDITION_TRUE", "FALSE_RETURNS", "TRUE_RETURNS"],' \
// RUN:   '  "conditionMutationRules": [' \
// RUN:   '    "COMPARISON|CONDITION_FALSE|condition_false|condition|false",' \
// RUN:   '    "COMPARISON|CONDITION_TRUE|condition_true|condition|true"' \
// RUN:   '  ],' \
// RUN:   '  "arithmeticMutationRules": [],' \
// RUN:   '  "contextualArithmeticMutationRules": [],' \
// RUN:   '  "returnMutationRules": [' \
// RUN:   '    "boolToFalse|FALSE_RETURNS|return_false|return|return false|false",' \
// RUN:   '    "boolToTrue|TRUE_RETURNS|return_true|return|return true|true"' \
// RUN:   '  ],' \
// RUN:   '  "voidCallMutationRules": [],' \
// RUN:   '  "sourceMutationDisplayRules": []' \
// RUN:   '}' > %t/config.json
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-build-swift -O %t/Classifier.swift %t/main.swift -module-name SwiftmutSameTypeInlinedPredicateSourceLocations -Xfrontend -external-pass-pipeline-filename -Xfrontend %t/pipeline.yaml -o %t/a.out
// RUN: find %t/fragments -type f -name '*.json' -exec cat {} ';' > %t/all-fragments.json
// RUN: %FileCheck %s --input-file %t/all-fragments.json
// RUN: %FileCheck %s --check-prefix=NO-WRONG-RETURN --input-file %t/all-fragments.json
// RUN: %FileCheck %s --check-prefix=CLONES --input-file %t/all-fragments.json
// RUN: %FileCheck %s --check-prefix=EVENTS --input-file %t/compiler-events.jsonl

//--- Classifier.swift
@_silgen_name("__swiftmut_visit")
public func __swiftmut_visit(_ siteID: UInt64) -> UInt32 {
  0
}

public struct SwiftmutMangledFunctionClassifier {
  @inline(__always)
  public static func swiftmutIsClone(function: String) -> Bool {
    guard swiftmutIsMangledSwiftFunction(function) else {
      return false
    }
    return function.hasSuffix("Clone")
  }

  @inline(__always)
  public static func swiftmutIsMangledSwiftFunction(_ function: String) -> Bool {
    return function.hasPrefix("$s") || function.hasPrefix("@$s")
  }

  @inline(__always)
  public static func swiftmutIsGeneratedReabstractionThunk(function: String) -> Bool {
    return swiftmutIsMangledSwiftFunction(function) && function.hasSuffix("TR")
  }

  @inline(never)
  public static func swiftmutDirectProbe(_ function: String) -> Bool {
    return swiftmutIsMangledSwiftFunction(function)
  }

  public static func swiftmutReason(function: String) -> Int {
    if swiftmutIsClone(function: function) {
      return 3
    }
    if swiftmutIsGeneratedReabstractionThunk(function: function) {
      return 1
    }
    if swiftmutDirectProbe(function) {
      return 2
    }
    return 0
  }
}

//--- main.swift
public func swiftmutClassify(_ function: String) -> Int {
  SwiftmutMangledFunctionClassifier.swiftmutReason(function: function)
}

// CHECK-DAG: "function":"{{.*}}0A25MangledFunctionClassifierV010swiftmutIsh5SwiftI0ySbSSFZ"{{.*}}"siteKind":"returnValue"{{.*}}"sourceOriginal":"function.hasPrefix(\"$s\") || function.hasPrefix(\"@$s\")","sourceMutated":"false"{{.*}}"sourceOriginal":"function.hasPrefix(\"$s\") || function.hasPrefix(\"@$s\")","sourceMutated":"true"
// CHECK-DAG: "function":"{{.*}}0A25MangledFunctionClassifierV37swiftmutIsGeneratedReabstractionThunk8functionSbSS_tFZ"{{.*}}"siteKind":"valueApply"{{.*}}"sourceOriginal":"swiftmutIsMangledSwiftFunction(function) && function.hasSuffix(\"TR\")","sourceMutated":"false"{{.*}}"sourceOriginal":"swiftmutIsMangledSwiftFunction(function) && function.hasSuffix(\"TR\")","sourceMutated":"true"
// CHECK-DAG: "function":"{{.*}}0A25MangledFunctionClassifierV19swiftmutDirectProbeySbSSFZ"{{.*}}"siteKind":"valueApply"{{.*}}"sourceOriginal":"swiftmutIsMangledSwiftFunction(function)","sourceMutated":"false"{{.*}}"sourceOriginal":"swiftmutIsMangledSwiftFunction(function)","sourceMutated":"true"
// CHECK-DAG: "function":"{{.*}}0A25MangledFunctionClassifierV14swiftmutReason8functionSiSS_tFZ"{{.*}}"siteKind":"condition"{{.*}}"sourceOriginal":"swiftmutIsGeneratedReabstractionThunk(function: function)","sourceMutated":"false"{{.*}}"sourceOriginal":"swiftmutIsGeneratedReabstractionThunk(function: function)","sourceMutated":"true"
// CHECK-DAG: "function":"{{.*}}0A25MangledFunctionClassifierV14swiftmutReason8functionSiSS_tFZ"{{.*}}"siteKind":"condition"{{.*}}"sourceOriginal":"swiftmutDirectProbe(function)","sourceMutated":"false"{{.*}}"sourceOriginal":"swiftmutDirectProbe(function)","sourceMutated":"true"

// NO-WRONG-RETURN-NOT: "function":"{{.*}}0A25MangledFunctionClassifierV010swiftmutIsh5SwiftI0ySbSSFZ"{{.*}}"sourceLocation":{"file":"Classifier.swift","line":12,"column":5},"siteKind":"returnValue"

// CLONES-NOT: Tf4
// CLONES: "siteKind"

// EVENTS-DAG: "event":"metamutantDiscovery","module":"SwiftmutSameTypeInlinedPredicateSourceLocations","function":"{{.*}}0A25MangledFunctionClassifierV010swiftmutIsh5SwiftI0ySbSSFZ"
// EVENTS-DAG: "event":"metamutantDiscovery","module":"SwiftmutSameTypeInlinedPredicateSourceLocations","function":"{{.*}}0A25MangledFunctionClassifierV15swiftmutIsClone8functionSbSS_tFZ"
// EVENTS-DAG: "event":"metamutantDiscovery","module":"SwiftmutSameTypeInlinedPredicateSourceLocations","function":"{{.*}}0A25MangledFunctionClassifierV37swiftmutIsGeneratedReabstractionThunk8functionSbSS_tFZ"
// EVENTS-DAG: "event":"metamutantDiscovery","module":"SwiftmutSameTypeInlinedPredicateSourceLocations","function":"{{.*}}0A25MangledFunctionClassifierV19swiftmutDirectProbeySbSSFZ"
// EVENTS-DAG: "event":"metamutantDiscovery","module":"SwiftmutSameTypeInlinedPredicateSourceLocations","function":"{{.*}}0A25MangledFunctionClassifierV14swiftmutReason8functionSiSS_tFZ"
