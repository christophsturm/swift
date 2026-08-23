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
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -emit-sil -Onone -module-name SwiftmutScalarAssignmentStoreOverlap %s -o /dev/null
// RUN: %FileCheck %s --check-prefix=EVENTS --input-file %t/compiler-events.jsonl
// RUN: find %t/fragments -type f -name '*.json' -exec cat {} ';' > %t/all-fragments.json
// RUN: %FileCheck %s --check-prefix=MANIFEST --input-file %t/all-fragments.json

// A literal whose lowered StructInst has direct store uses is owned by the
// scalar-value site. Discovering an assignment-value site for the same store
// used to retain that StoreInst after scalar injection erased it and crashed
// the frontend with an invalid bridged value reference.
// EVENTS: "event":"metamutantDiscovery","module":"SwiftmutScalarAssignmentStoreOverlap","function":"{{.*}}swiftmutByteOffset
// EVENTS-SAME: "scalarValueDirectStoreUses":"2"
// EVENTS-SAME: "assignmentValueSites":"3"
// EVENTS: "event":"metamutantInjection","module":"SwiftmutScalarAssignmentStoreOverlap","function":"{{.*}}swiftmutByteOffset
// EVENTS-SAME: "injectedScalarValueSites":"3"
// EVENTS-SAME: "injectedAssignmentValueSites":"3"
// MANIFEST-DAG: "siteKind":"scalarValue"
// MANIFEST-DAG: "siteKind":"assignmentValue"

private func swiftmutByteOffset(
  of patternBytes: UnsafeBufferPointer<UInt8>,
  in bytes: UnsafeBufferPointer<UInt8>
) -> Int? {
  guard !patternBytes.isEmpty else {
    return nil
  }
  let firstPatternByte = patternBytes[0]
  var index = bytes.startIndex
  while index + patternBytes.count <= bytes.endIndex {
    while index + patternBytes.count <= bytes.endIndex && bytes[index] != firstPatternByte {
      index += 1
    }
    guard index + patternBytes.count <= bytes.endIndex else {
      break
    }
    var offset = 1
    while offset < patternBytes.count, bytes[index + offset] == patternBytes[offset] {
      offset += 1
    }
    if offset == patternBytes.count {
      return index
    }
    index += 1
  }
  return nil
}

@_silgen_name("__swiftmut_visit")
public func __swiftmut_visit(_ siteID: UInt64) -> UInt32 {
  0
}
