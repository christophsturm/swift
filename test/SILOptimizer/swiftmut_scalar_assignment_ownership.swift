// RUN: rm -rf %t
// RUN: mkdir -p %t
// RUN: printf '%%s\n' '---' "name: ''" 'passes: [ "\"swiftmut\"" ]' > %t/pipeline.yaml
// RUN: printf '%b\n' \
// RUN:   '{' \
// RUN:   '  "mode": "metamutant",' \
// RUN:   '  "manifestPath": "%t/mutants.jsonl",' \
// RUN:   '  "manifestFragmentsDirectory": "%t/fragments",' \
// RUN:   '  "compilerEventsPath": "%t/compiler-events.jsonl",' \
// RUN:   '  "packageRoot": "%S",' \
// RUN:   '  "excludePaths": [],' \
// RUN:   '  "sourceFiles": ["%s"],' \
// RUN:   '  "enabledMutators": ["FALSE_RETURNS", "TRUE_RETURNS", "PRIMITIVE_RETURNS"],' \
// RUN:   '  "conditionMutationRules": [],' \
// RUN:   '  "arithmeticMutationRules": [],' \
// RUN:   '  "contextualArithmeticMutationRules": [],' \
// RUN:   '  "returnMutationRules": [' \
// RUN:   '    "boolToFalse|FALSE_RETURNS|return_false|return|return false|false",' \
// RUN:   '    "boolToTrue|TRUE_RETURNS|return_true|return|return true|true",' \
// RUN:   '    "integerToZero|PRIMITIVE_RETURNS|return_zero|return|return 0|0"' \
// RUN:   '  ],' \
// RUN:   '  "voidCallMutationRules": [],' \
// RUN:   '  "sourceMutationDisplayRules": []' \
// RUN:   '}' > %t/config.json
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -emit-sil -O -module-name SwiftmutScalarAssignmentOwnership -external-pass-pipeline-filename %t/pipeline.yaml %s -o /dev/null
// RUN: find %t/fragments -type f -name '*.json' -exec cat {} ';' > %t/all-fragments.json
// RUN: %FileCheck %s --input-file %t/all-fragments.json
// RUN: %FileCheck %s --check-prefix=EVENTS --input-file %t/compiler-events.jsonl

public struct SwiftmutEditPlan {
  public var operations: [SwiftmutEditOperation]
}

public enum SwiftmutEditOperation {
  case addFile(path: String, content: String)
  case deleteFile(path: String)
  case updateFile(path: String, movePath: String?)
}

public enum SwiftmutEditChange {
  case added(path: String, content: String)
  case deleted(path: String, content: String)
  case moved(oldPath: String, newPath: String, content: String)
}

public enum SwiftmutEditError: Error {
  case emptyPlan
  case fileAlreadyExists(String)
  case missingFile(String)
}

public func swiftmutApplyEdits(
  plan: SwiftmutEditPlan,
  to files: [String: String]
) throws -> [SwiftmutEditChange] {
  guard !plan.operations.isEmpty else {
    throw SwiftmutEditError.emptyPlan
  }

  var working = files
  var changes: [SwiftmutEditChange] = []
  for operation in plan.operations {
    switch operation {
    case .addFile(let path, let content):
      guard working[path] == nil else {
        throw SwiftmutEditError.fileAlreadyExists(path)
      }
      working[path] = content
      changes.append(.added(path: path, content: content))
    case .deleteFile(let path):
      guard let before = working.removeValue(forKey: path) else {
        throw SwiftmutEditError.missingFile(path)
      }
      changes.append(.deleted(path: path, content: before))
    case .updateFile(let path, let movePath):
      guard let before = working.removeValue(forKey: path) else {
        throw SwiftmutEditError.missingFile(path)
      }
      let destination = movePath ?? path
      guard working[destination] == nil else {
        throw SwiftmutEditError.fileAlreadyExists(destination)
      }
      working[destination] = before
      changes.append(.moved(oldPath: path, newPath: destination, content: before))
    }
  }
  return changes
}

@_silgen_name("__swiftmut_visit")
public func __swiftmut_visit(_ siteID: UInt64) -> UInt32 {
  0
}

// CHECK-NOT: "siteKind":"scalarValue"{{.*}}"sourceOriginal":"files"

// EVENTS: "event":"metamutantDiscovery","module":"SwiftmutScalarAssignmentOwnership","function":"{{.*}}swiftmutApplyEdits
// EVENTS-SAME: "scalarValueMutationEligibleStructInstructions":"{{[1-9][0-9]*}}"
// EVENTS-SAME: "scalarValueSourceLocationMisses":"{{[1-9][0-9]*}}"
