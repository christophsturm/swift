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
// RUN:   '  "enabledMutators": ["FALSE_RETURNS", "TRUE_RETURNS"],' \
// RUN:   '  "conditionMutationRules": [],' \
// RUN:   '  "arithmeticMutationRules": [],' \
// RUN:   '  "contextualArithmeticMutationRules": [],' \
// RUN:   '  "returnMutationRules": [' \
// RUN:   '    "boolToFalse|FALSE_RETURNS|return_false|return|return false|false",' \
// RUN:   '    "boolToTrue|TRUE_RETURNS|return_true|return|return true|true"' \
// RUN:   '  ],' \
// RUN:   '  "voidCallMutationRules": [],' \
// RUN:   '  "sourceMutationDisplayRules": []' \
// RUN:   '}' > %t/config.json
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -emit-sil -O -module-name SwiftmutLabeledArgumentValueApplySourceLocations -external-pass-pipeline-filename %t/pipeline.yaml %s -o /dev/null
// RUN: find %t/fragments -type f -name '*.json' -exec cat {} ';' > %t/all-fragments.json
// RUN: %FileCheck %s --input-file %t/all-fragments.json

public struct SwiftmutTaggedPath {
  public var path: String { "" }

  public func deletingLastPathComponent() -> SwiftmutTaggedPath {
    self
  }
}

public enum SwiftmutDirectory {
  public static func createDirectory(
    at path: SwiftmutTaggedPath,
    withIntermediateDirectories: Bool
  ) throws {}

  public static func fileExists(atPath path: String) -> Bool {
    path.isEmpty
  }

  public static func destinationOfSymbolicLink(atPath path: String) -> String? {
    path.isEmpty ? nil : path
  }
}

@_silgen_name("__swiftmut_visit")
public func __swiftmut_visit(_ siteID: UInt64) -> UInt32 {
  0
}

public func swiftmutLabeledArgumentThenBoolApply(_ taggedPath: SwiftmutTaggedPath) throws -> Int {
  try SwiftmutDirectory.createDirectory(
    at: taggedPath.deletingLastPathComponent(),
    withIntermediateDirectories: true
  )
  if SwiftmutDirectory.fileExists(atPath: taggedPath.path)
      || SwiftmutDirectory.destinationOfSymbolicLink(atPath: taggedPath.path) != nil {
    return 1
  }
  return 0
}

// CHECK: "sites"
// CHECK-NOT: "sourceOriginal":"taggedPath.deletingLastPathComponent()"
// CHECK: "function":"{{.*}}swiftmutbc8ThenBoolE0{{.*}}"siteKind":"valueApply"{{.*}}"sourceOriginal":"SwiftmutDirectory.destinationOfSymbolicLink(atPath: taggedPath.path) != nil","sourceMutated":"false"
