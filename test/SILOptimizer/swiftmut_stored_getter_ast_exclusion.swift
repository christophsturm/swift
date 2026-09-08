// RUN: rm -rf %t && mkdir -p %t
// RUN: echo '{"mode":"metamutant","manifestPath":"%t/manifest.jsonl","manifestFragmentsDirectory":"%t/fragments","compilerEventsPath":"%t/events.jsonl","packageRoot":"%S","sourceFiles":["%s"],"excludePaths":[],"returnMutationRules":["boolToFalse|FALSE_RETURNS|return_false|return|return false|false"],"conditionMutationRules":[],"arithmeticMutationRules":[],"contextualArithmeticMutationRules":[],"voidCallMutationRules":[],"sourceMutationDisplayRules":[]}' > %t/config.json
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -emit-sil -Onone -module-name SwiftmutStoredGetterAST %s -o /dev/null
// RUN: %FileCheck %s --input-file %t/events.jsonl
// RUN: rm %t/events.jsonl
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -emit-sil -O -module-name SwiftmutStoredGetterAST %s -o /dev/null
// RUN: %FileCheck %s --input-file %t/events.jsonl

@_silgen_name("__swiftmut_visit")
public func __swiftmut_visit(_ siteID: UInt64) -> UInt32 { 0 }

public struct SwiftmutAccessorShapes {
  public var stored: Bool = true { didSet {} }
  public var computed: Bool
  {
    true
  }
  public var sameLineStored = true; public var sameLineComputed: Bool { true }
}

// CHECK-DAG: "event":"functionSkip","reason":"generatedStoredPropertyGetter"{{.*}}"function":"{{.*}}V6storedSbvg"
// CHECK-DAG: "event":"functionSkip","reason":"generatedStoredPropertyGetter"{{.*}}"function":"{{.*}}V08sameLineB0Sbvg"
// CHECK-DAG: "event":"metamutantDiscovery"{{.*}}"function":"{{.*}}V8computedSbvg"
// CHECK-DAG: "event":"metamutantDiscovery"{{.*}}"function":"{{.*}}V16sameLineComputedSbvg"
