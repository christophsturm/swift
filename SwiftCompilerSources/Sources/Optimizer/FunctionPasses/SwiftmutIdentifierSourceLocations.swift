//===--- SwiftmutIdentifierSourceLocations.swift ----------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2026 swiftmut contributors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

import AST
import SIL

func swiftmutSourceExpressionIdentifiers(for apply: ApplyInst) -> [String] {
  swiftmutSourceCalleeIdentifiers(for: apply).filter(swiftmutIdentifierLooksLikeSourceExpression)
}

func swiftmutSourceCalleeIdentifiers(for apply: ApplyInst) -> [String] {
  guard let name = apply.referencedFunction?.name.string else {
    return []
  }
  return swiftmutMangledIdentifiers(in: name).filter { identifier in
    identifier.count >= 3 && !identifier.hasPrefix("__")
  }
}

func swiftmutMangledIdentifiers(in name: String) -> [String] {
  let bytes = Array(name.utf8)
  var identifiers: [String] = []
  var index = 0
  while index < bytes.count {
    guard bytes[index] >= 48 && bytes[index] <= 57 else {
      index += 1
      continue
    }
    var length = 0
    var cursor = index
    while cursor < bytes.count && bytes[cursor] >= 48 && bytes[cursor] <= 57 {
      length = (length * 10) + Int(bytes[cursor] - 48)
      cursor += 1
    }
    guard length > 0,
          cursor + length <= bytes.count,
          swiftmutBytesAreIdentifier(bytes, start: cursor, end: cursor + length) else {
      index += 1
      continue
    }
    let identifier = String(decoding: bytes[cursor..<(cursor + length)], as: UTF8.self)
    if !identifiers.contains(identifier) {
      identifiers.append(identifier)
    }
    index = cursor + length
  }
  return identifiers
}

func swiftmutIdentifierLooksLikeSourceExpression(_ identifier: String) -> Bool {
  guard let first = identifier.utf8.first else {
    return false
  }
  return (first >= 97 && first <= 122) || first == 95
}

func swiftmutBytesAreIdentifier(_ bytes: [UInt8], start: Int, end: Int) -> Bool {
  guard start < end else {
    return false
  }
  for index in start..<end {
    if !swiftmutIsASCIILetterNumberOrUnderscore(bytes[index]) {
      return false
    }
  }
  return true
}

func swiftmutSourceLineContainsExpressionIdentifier(_ line: String, identifiers: [String]) -> Bool {
  let bytes = Array(line.utf8)
  let start = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
  let end = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  guard start < end else {
    return false
  }
  for identifier in identifiers where swiftmutSourceLineContainsExpressionIdentifier(
    bytes,
    start: start,
    end: end,
    identifier: identifier
  ) {
    return true
  }
  return false
}

func swiftmutSourceLineContainsExpressionIdentifier(
  _ bytes: [UInt8],
  start: Int,
  end: Int,
  identifier: String
) -> Bool {
  let token = Array(identifier.utf8)
  guard !token.isEmpty,
        token.count <= end - start else {
    return false
  }

  var index = start
  while index <= end - token.count {
    var matched = true
    for offset in 0..<token.count where bytes[index + offset] != token[offset] {
      matched = false
      break
    }
    if matched {
      let before = index > start ? bytes[index - 1] : 0
      let tokenEnd = index + token.count
      let after = tokenEnd < end ? bytes[tokenEnd] : 0
      if !swiftmutIsASCIILetterNumberOrUnderscore(before)
          && !swiftmutIsASCIILetterNumberOrUnderscore(after) {
        let callStart = swiftmutSkipHorizontalWhitespace(bytes, from: tokenEnd)
        if callStart < end && bytes[callStart] == 123 {
          return true
        }
        if callStart < end && bytes[callStart] == 40 {
          return true
        }
        if index > start && bytes[index - 1] == 46 {
          return true
        }
      }
    }
    index += 1
  }
  return false
}

func swiftmutIdentifierValueExpression(
  _ line: String,
  identifiers: [String],
  mutation: SwiftmutMutation
) -> (column: Int, sourceOriginal: String, sourceMutated: String)? {
  let bytes = Array(line.utf8)
  let lineStart = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
  let lineEnd = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  guard lineStart < lineEnd else {
    return nil
  }

  for identifier in identifiers {
    guard let tokenRange = swiftmutFindSourceIdentifier(
      identifier,
      in: bytes,
      start: lineStart,
      end: lineEnd
    ),
    let expressionRange = swiftmutSourceExpressionRange(
      around: tokenRange,
      in: bytes,
      lineEnd: lineEnd
    ),
    swiftmutReturnValueIsEligible(bytes: bytes, start: expressionRange.start, mutation: mutation) else {
      continue
    }
    let sourceOriginal = String(decoding: bytes[expressionRange.start..<expressionRange.end], as: UTF8.self)
    return (
      expressionRange.start + 1,
      sourceOriginal,
      swiftmutImplicitReturnSourceMutation(for: mutation))
  }
  return nil
}

func swiftmutLineContainsAnyIdentifier(_ line: String, identifiers: [String]) -> Bool {
  let bytes = Array(line.utf8)
  let start = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
  let end = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  guard start < end else {
    return false
  }
  for identifier in identifiers where swiftmutFindSourceIdentifier(identifier, in: bytes, start: start, end: end) != nil {
    return true
  }
  return false
}

func swiftmutFindSourceIdentifier(
  _ identifier: String,
  in bytes: [UInt8],
  start: Int,
  end: Int
) -> (start: Int, end: Int)? {
  let token = Array(identifier.utf8)
  guard !token.isEmpty,
        token.count <= end - start else {
    return nil
  }

  var index = start
  while index <= end - token.count {
    var matched = true
    for offset in 0..<token.count where bytes[index + offset] != token[offset] {
      matched = false
      break
    }
    if matched {
      let before = index > start ? bytes[index - 1] : 0
      let tokenEnd = index + token.count
      let after = tokenEnd < end ? bytes[tokenEnd] : 0
      if !swiftmutIsASCIILetterNumberOrUnderscore(before)
          && !swiftmutIsASCIILetterNumberOrUnderscore(after) {
        return (index, tokenEnd)
      }
    }
    index += 1
  }
  return nil
}

func swiftmutSourceExpressionRange(
  around tokenRange: (start: Int, end: Int),
  in bytes: [UInt8],
  lineEnd: Int
) -> (start: Int, end: Int)? {
  var expressionStart = tokenRange.start
  while expressionStart > 0 && swiftmutIsSourceExpressionPrefixByte(bytes[expressionStart - 1]) {
    expressionStart -= 1
  }

  let suffixStart = swiftmutSkipHorizontalWhitespace(bytes, from: tokenRange.end)
  if suffixStart < lineEnd && bytes[suffixStart] == 40 {
    guard let callEnd = swiftmutBalancedExpressionEnd(
      in: bytes,
      openIndex: suffixStart,
      close: 41,
      lineEnd: lineEnd
    ) else {
      return nil
    }
    return (expressionStart, callEnd)
  }
  if suffixStart < lineEnd && bytes[suffixStart] == 123 {
    guard let closureEnd = swiftmutBalancedExpressionEnd(
      in: bytes,
      openIndex: suffixStart,
      close: 125,
      lineEnd: lineEnd
    ) else {
      return nil
    }
    return (expressionStart, closureEnd)
  }

  return (expressionStart, tokenRange.end)
}

func swiftmutIsSourceExpressionPrefixByte(_ byte: UInt8) -> Bool {
  swiftmutIsASCIILetterNumberOrUnderscore(byte) || byte == 46 || byte == 63 || byte == 33
}

