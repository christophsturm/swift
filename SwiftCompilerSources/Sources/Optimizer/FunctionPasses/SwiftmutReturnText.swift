// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for Swift project authors

func swiftmutImplicitReturnSourceMutation(for mutation: SwiftmutMutation) -> String {
  switch mutation.mutatedBuiltinName {
  case "return_false":
    return "false"
  case "return_true":
    return "true"
  case "return_nil":
    return "nil"
  case "return_zero":
    return "0"
  case "return_empty_string":
    return #""""#
  case "return_empty_array", "return_empty_set":
    return "[]"
  case "return_empty_dictionary":
    return "[:]"
  default:
    return mutation.sourceMutated
  }
}

func swiftmutReturnLineIsEligible(
  bytes: [UInt8],
  start: Int,
  mutation: SwiftmutMutation
) -> Bool {
  guard swiftmutASCIIHasExactPrefix(bytes, start: start, prefix: "return ") else {
    return false
  }
  let valueStart = swiftmutSkipHorizontalWhitespace(bytes, from: start + 7)
  return swiftmutReturnValueIsEligible(bytes: bytes, start: valueStart, mutation: mutation)
}

func swiftmutReturnValueIsEligible(
  bytes: [UInt8],
  start: Int,
  mutation: SwiftmutMutation
) -> Bool {
  switch mutation.mutatedBuiltinName {
  case "return_false":
    return !swiftmutASCIIHasToken(bytes, start: start, token: "false")
  case "return_true":
    return !swiftmutASCIIHasToken(bytes, start: start, token: "true")
  case "return_nil":
    return !swiftmutASCIIHasToken(bytes, start: start, token: "nil")
  case "return_zero":
    return !swiftmutASCIIHasNumericZeroToken(bytes, start: start)
  case "return_empty_string":
    return !swiftmutASCIIHasEmptyStringLiteral(bytes, start: start)
  case "return_empty_array", "return_empty_set":
    return !swiftmutASCIIHasEmptyArrayLiteral(bytes, start: start)
  case "return_empty_dictionary":
    return !swiftmutASCIIHasEmptyDictionaryLiteral(bytes, start: start)
  default:
    return true
  }
}

private func swiftmutASCIIHasEmptyArrayLiteral(_ bytes: [UInt8], start: Int) -> Bool {
  guard start >= 0 && start + 2 <= bytes.count,
        bytes[start] == 91,
        bytes[start + 1] == 93 else {
    return false
  }
  let end = start + 2
  return end == bytes.count || !swiftmutIsASCIILetterNumberOrUnderscore(bytes[end])
}

private func swiftmutASCIIHasEmptyDictionaryLiteral(_ bytes: [UInt8], start: Int) -> Bool {
  guard start >= 0 && start + 3 <= bytes.count,
        bytes[start] == 91,
        bytes[start + 1] == 58,
        bytes[start + 2] == 93 else {
    return false
  }
  let end = start + 3
  return end == bytes.count || !swiftmutIsASCIILetterNumberOrUnderscore(bytes[end])
}

private func swiftmutASCIIHasEmptyStringLiteral(_ bytes: [UInt8], start: Int) -> Bool {
  guard start >= 0 && start + 2 <= bytes.count,
        bytes[start] == 34,
        bytes[start + 1] == 34 else {
    return false
  }
  let end = start + 2
  return end == bytes.count || !swiftmutIsASCIILetterNumberOrUnderscore(bytes[end])
}

private func swiftmutASCIIHasToken(_ bytes: [UInt8], start: Int, token: String) -> Bool {
  let tokenBytes = Array(token.utf8)
  guard start >= 0 && start + tokenBytes.count <= bytes.count else {
    return false
  }
  for offset in 0..<tokenBytes.count {
    if bytes[start + offset] != tokenBytes[offset] {
      return false
    }
  }
  let end = start + tokenBytes.count
  return end == bytes.count || !swiftmutIsASCIILetterNumberOrUnderscore(bytes[end])
}

private func swiftmutASCIIHasNumericZeroToken(_ bytes: [UInt8], start: Int) -> Bool {
  guard start >= 0 && start < bytes.count && bytes[start] == 48 else {
    return false
  }
  let end = start + 1
  return end == bytes.count || bytes[end] < 48 || bytes[end] > 57
}
