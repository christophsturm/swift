//===--- SwiftmutOperatorText.swift ----------------------------------------------===//
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

func swiftmutSourceMutationDisplayRules(
  for mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> [SwiftmutSourceMutationDisplayRule] {
  let builtinID = swiftmutBuiltinIDName(mutation.originalID) ?? ""
  let rules = config.sourceMutationDisplayRules.filter {
    $0.mutator == mutation.mutator && $0.builtinID == builtinID
  }
  if !rules.isEmpty {
    return rules
  }
  return [
    SwiftmutSourceMutationDisplayRule(
      mutator: mutation.mutator,
      builtinID: builtinID,
      sourceOriginal: mutation.sourceOriginal,
      sourceMutated: mutation.sourceMutated,
      sourceMutatedOverride: ""
    )
  ]
}

func swiftmutFindOperator(
  _ op: String,
  mutatedOperator: String,
  in text: String,
  preferredLine: Int?,
  maxPreferredLineDistance: Int? = nil
) -> (line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  let bytes = Array(text.utf8)
  let opBytes = Array(op.utf8)
  guard !opBytes.isEmpty else {
    return nil
  }

  var line = 1
  var column = 1
  var index = 0
  var best: (line: Int, column: Int, sourceOriginal: String, sourceMutated: String)?
  while index <= bytes.count - opBytes.count {
    var matched = true
    for opIndex in 0..<opBytes.count {
      if bytes[index + opIndex] != opBytes[opIndex] {
        matched = false
        break
      }
    }
    if matched {
      if !swiftmutIsSourceComparisonOperator(
        bytes: bytes,
        operatorStart: index,
        operatorEnd: index + opBytes.count
      ) {
        if bytes[index] == 10 {
          line += 1
          column = 1
        } else {
          column += 1
        }
        index += 1
        continue
      }
      let expression = swiftmutSourceExpression(
        in: bytes,
        operatorStart: index,
        operatorEnd: index + opBytes.count,
        mutatedOperator: mutatedOperator)
      let candidate = (line, column, expression.original, expression.mutated)
      guard let preferredLine = preferredLine else {
        return candidate
      }
      if let maxPreferredLineDistance = maxPreferredLineDistance,
         swiftmutLineDistance(line, preferredLine) > maxPreferredLineDistance {
        if bytes[index] == 10 {
          line += 1
          column = 1
        } else {
          column += 1
        }
        index += 1
        continue
      }
      if line == preferredLine {
        return candidate
      }
      if let existing = best {
        if swiftmutLineDistance(line, preferredLine) < swiftmutLineDistance(existing.line, preferredLine) {
          best = candidate
        }
      } else {
        best = candidate
      }
    }
    if bytes[index] == 10 {
      line += 1
      column = 1
    } else {
      column += 1
    }
    index += 1
  }
  return best
}

func swiftmutFindOperatorMatches(
  _ op: String,
  mutatedOperator: String,
  in text: String
) -> [(column: Int, sourceOriginal: String, sourceMutated: String)] {
  let bytes = Array(text.utf8)
  let opBytes = Array(op.utf8)
  guard !opBytes.isEmpty,
        opBytes.count <= bytes.count else {
    return []
  }

  var matches: [(column: Int, sourceOriginal: String, sourceMutated: String)] = []
  var column = 1
  var index = 0
  while index <= bytes.count - opBytes.count {
    var matched = true
    for opIndex in 0..<opBytes.count where bytes[index + opIndex] != opBytes[opIndex] {
      matched = false
      break
    }
    if matched,
       swiftmutIsSourceComparisonOperator(
        bytes: bytes,
        operatorStart: index,
        operatorEnd: index + opBytes.count
       ) {
      let expression = swiftmutSourceExpression(
        in: bytes,
        operatorStart: index,
        operatorEnd: index + opBytes.count,
        mutatedOperator: mutatedOperator)
      matches.append((column, expression.original, expression.mutated))
    }
    column += 1
    index += 1
  }
  return matches
}

func swiftmutPreferredLine(in location: String, path: String) -> Int? {
  let locationBytes = Array(location.utf8)
  let pathBytes = Array(path.utf8)
  guard let pathIndex = swiftmutFind(pathBytes, in: locationBytes, startingAt: 0) else {
    return nil
  }
  var index = pathIndex + pathBytes.count
  guard index < locationBytes.count, locationBytes[index] == 58 else {
    return nil
  }
  index += 1
  var value = 0
  var hasDigit = false
  while index < locationBytes.count {
    let byte = locationBytes[index]
    guard byte >= 48 && byte <= 57 else {
      break
    }
    value = value * 10 + Int(byte - 48)
    hasDigit = true
    index += 1
  }
  return hasDigit ? value : nil
}

func swiftmutLineDistance(_ lhs: Int, _ rhs: Int) -> Int {
  lhs >= rhs ? lhs - rhs : rhs - lhs
}

func swiftmutIsSourceComparisonOperator(
  bytes: [UInt8],
  operatorStart: Int,
  operatorEnd: Int
) -> Bool {
  if operatorStart > 0 && bytes[operatorStart - 1] == 45 {
    return false
  }
  if operatorStart > 0 && swiftmutIsOperatorByte(bytes[operatorStart - 1]) {
    return false
  }
  if operatorEnd < bytes.count && swiftmutIsOperatorByte(bytes[operatorEnd]) {
    return false
  }
  if swiftmutIsOperatorFunctionDeclaration(bytes: bytes, operatorStart: operatorStart) {
    return false
  }
  if swiftmutIsLikelyGenericAngleBracket(
    bytes: bytes,
    operatorStart: operatorStart,
    operatorEnd: operatorEnd
  ) {
    return false
  }
  return true
}

func swiftmutIsLikelyGenericAngleBracket(
  bytes: [UInt8],
  operatorStart: Int,
  operatorEnd: Int
) -> Bool {
  guard operatorEnd == operatorStart + 1 else {
    return false
  }
  if bytes[operatorStart] == 60 {
    return swiftmutHasIdentifierBefore(bytes: bytes, index: operatorStart)
      && swiftmutHasIdentifierAfter(bytes: bytes, index: operatorEnd)
      && swiftmutHasClosingAngleBeforeExpressionDelimiter(bytes: bytes, index: operatorEnd)
  }
  if bytes[operatorStart] == 62 {
    return swiftmutHasIdentifierBefore(bytes: bytes, index: operatorStart)
      && swiftmutHasOpeningAngleBeforeExpressionDelimiter(bytes: bytes, index: operatorStart)
  }
  return false
}

func swiftmutHasIdentifierBefore(bytes: [UInt8], index: Int) -> Bool {
  index > 0 && swiftmutIsExpressionByte(bytes[index - 1])
}

func swiftmutIsOperatorFunctionDeclaration(bytes: [UInt8], operatorStart: Int) -> Bool {
  var offset = operatorStart
  while offset > 0 && swiftmutIsHorizontalWhitespace(bytes[offset - 1]) {
    offset -= 1
  }

  let tokenEnd = offset
  while offset > 0 && swiftmutIsExpressionByte(bytes[offset - 1]) {
    offset -= 1
  }

  guard tokenEnd > offset else {
    return false
  }
  return String(decoding: bytes[offset..<tokenEnd], as: UTF8.self) == "func"
}

func swiftmutHasIdentifierAfter(bytes: [UInt8], index: Int) -> Bool {
  index < bytes.count && swiftmutIsExpressionByte(bytes[index])
}

func swiftmutHasClosingAngleBeforeExpressionDelimiter(bytes: [UInt8], index: Int) -> Bool {
  var offset = index
  while offset < bytes.count {
    let byte = bytes[offset]
    if byte == 62 {
      return true
    }
    if byte == 10 || byte == 59 || byte == 123 || byte == 125 || byte == 61 {
      return false
    }
    offset += 1
  }
  return false
}

func swiftmutHasOpeningAngleBeforeExpressionDelimiter(bytes: [UInt8], index: Int) -> Bool {
  var offset = index
  while offset > 0 {
    offset -= 1
    let byte = bytes[offset]
    if byte == 60 {
      return true
    }
    if byte == 10 || byte == 59 || byte == 123 || byte == 125 || byte == 61 {
      return false
    }
  }
  return false
}

func swiftmutIsOperatorByte(_ byte: UInt8) -> Bool {
  switch byte {
  case 33, 37, 38, 42, 43, 45, 47, 58, 60, 61, 62, 63, 94, 124, 126:
    return true
  default:
    return false
  }
}

func swiftmutSourceExpression(
  in bytes: [UInt8],
  operatorStart: Int,
  operatorEnd: Int,
  mutatedOperator: String
) -> (original: String, mutated: String) {
  var leftStart = operatorStart
  if !mutatedOperator.isEmpty {
    while leftStart > 0 && swiftmutIsHorizontalWhitespace(bytes[leftStart - 1]) {
      leftStart -= 1
    }
    while leftStart > 0 && swiftmutIsExpressionByte(bytes[leftStart - 1]) {
      leftStart -= 1
    }
  }

  var rightEnd = operatorEnd
  while rightEnd < bytes.count && swiftmutIsHorizontalWhitespace(bytes[rightEnd]) {
    rightEnd += 1
  }
  if rightEnd < bytes.count && bytes[rightEnd] == 34 {
    rightEnd = swiftmutStringLiteralEnd(bytes: bytes, start: rightEnd)
  } else {
    while rightEnd < bytes.count && swiftmutIsExpressionByte(bytes[rightEnd]) {
      rightEnd += 1
    }
  }

  let original = String(decoding: bytes[leftStart..<rightEnd], as: UTF8.self)
  let mutatedPrefix = String(decoding: bytes[leftStart..<operatorStart], as: UTF8.self)
  let mutatedSuffix = String(decoding: bytes[operatorEnd..<rightEnd], as: UTF8.self)
  return (original, mutatedPrefix + mutatedOperator + mutatedSuffix)
}

func swiftmutIsExpressionByte(_ byte: UInt8) -> Bool {
  if byte >= 48 && byte <= 57 {
    return true
  }
  if byte >= 65 && byte <= 90 {
    return true
  }
  if byte >= 97 && byte <= 122 {
    return true
  }
  switch byte {
  case 36, 46, 95:
    return true
  default:
    return false
  }
}
