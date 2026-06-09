//===--- SwiftmutGenericConditionSourceMutationText.swift ----------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2026 swiftmut contributors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

func swiftmutGenericConditionSourceMutationText(
  _ sourceOriginal: String,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> String? {
  if let sourceMutated = swiftmutBooleanNegatedConditionSourceMutated(
    sourceOriginal,
    needle: nil,
    mutation: mutation
  ) {
    return sourceMutated
  }
  if let sourceMutated = swiftmutSourceComparisonMutationText(
    sourceOriginal,
    mutation: mutation,
    config: config
  ) {
    return sourceMutated
  }
  if let sourceMutated = swiftmutWrappedBooleanConditionMutationText(
    sourceOriginal,
    mutation: mutation
  ) {
    return sourceMutated
  }
  return nil
}

func swiftmutSourceComparisonMutationText(
  _ sourceOriginal: String,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> String? {
  let rules = config.sourceMutationDisplayRules.filter { rule in
    rule.mutator == mutation.mutator
  }
  for rule in rules {
    let sourceMutated = rule.sourceMutatedOverride.isEmpty
      ? rule.sourceMutated
      : rule.sourceMutatedOverride
    if let mutated = swiftmutReplaceFirstSourceOperator(
      rule.sourceOriginal,
      with: sourceMutated,
      in: sourceOriginal
    ) {
      return mutated
    }
  }
  return nil
}

func swiftmutWrappedBooleanConditionMutationText(
  _ sourceOriginal: String,
  mutation: SwiftmutMutation
) -> String? {
  guard mutation.sourceOriginal == "==",
        mutation.sourceMutated == "!=" else {
    return nil
  }
  let bytes = Array(sourceOriginal.utf8)
  let start = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
  guard start < bytes.count,
        bytes[start] != 33 else {
    return nil
  }
  return swiftmutPrefixBooleanNegation(sourceOriginal)
}

func swiftmutPrefixBooleanNegation(_ expression: String) -> String {
  let bytes = Array(expression.utf8)
  let start = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
  let prefix = String(decoding: bytes[0..<start], as: UTF8.self)
  let value = String(decoding: bytes[start..<bytes.count], as: UTF8.self)
  return prefix + "!" + value
}
