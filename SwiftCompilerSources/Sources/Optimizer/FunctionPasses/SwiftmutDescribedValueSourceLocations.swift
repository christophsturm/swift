//===--- SwiftmutDescribedValueSourceLocations.swift ----------------------------------------------===//
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

func swiftmutFindDescribedValueExpressionSourceLocation(
  for apply: ApplyInst,
  path: String,
  functionLine: Int,
  locationDescription: String,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard functionLine > 0,
        let snippet = swiftmutQuotedSourceSnippetPrefix(locationDescription),
        swiftmutDescribedValueSnippetLooksMappable(snippet),
        let text = swiftmutRead(path) else {
    return nil
  }

  let prefixes = swiftmutDescribedValueSnippetPrefixes(snippet)
  guard !prefixes.isEmpty else {
    return nil
  }

  let identifiers = swiftmutSourceExpressionIdentifiers(for: apply)
  var matches: [(line: Int, column: Int, sourceOriginal: String, sourceMutated: String)] = []
  var currentLine = 1
  var lineStart = text.startIndex
  var index = text.startIndex
  var braceDepth = 0
  var sawOpeningBrace = false

  func inspectLine(_ lineText: String, line: Int) {
    guard line >= functionLine,
          matches.count < 2 else {
      return
    }
    let bytes = Array(lineText.utf8)
    let start = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
    let end = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
    guard start < end else {
      return
    }

    for prefix in prefixes {
      guard let matchStart = swiftmutASCIIIndex(bytes, start: start, end: end, pattern: prefix),
            let expression = swiftmutDescribedValueExpression(
              bytes: bytes,
              matchStart: matchStart,
              lineEnd: end,
              identifiers: identifiers,
              mutation: mutation
            ) else {
        continue
      }
      matches.append((line, expression.column, expression.sourceOriginal, expression.sourceMutated))
      return
    }
  }

  func updateBraceDepth(_ lineText: String) {
    for byte in lineText.utf8 {
      if byte == 123 {
        braceDepth += 1
        sawOpeningBrace = true
      } else if byte == 125 {
        braceDepth -= 1
      }
    }
  }

  while index < text.endIndex {
    if text[index] == "\n" {
      let lineText = String(text[lineStart..<index])
      if currentLine >= functionLine {
        if sawOpeningBrace && braceDepth > 0 {
          inspectLine(lineText, line: currentLine)
          if matches.count >= 2 {
            break
          }
        }
        updateBraceDepth(lineText)
        if sawOpeningBrace && braceDepth <= 0 {
          break
        }
      }
      currentLine += 1
      lineStart = text.index(after: index)
    }
    index = text.index(after: index)
  }

  if index == text.endIndex && currentLine >= functionLine && sawOpeningBrace && braceDepth > 0 {
    inspectLine(String(text[lineStart..<text.endIndex]), line: currentLine)
  }

  guard matches.count == 1,
        let match = matches.first else {
    return nil
  }
  return (
    swiftmutTrimPackageRoot(path, config: config),
    match.line,
    match.column,
    match.sourceOriginal,
    match.sourceMutated)
}

func swiftmutFindUniqueDescribedValueExpressionSourceLocation(
  for apply: ApplyInst,
  path: String,
  locationDescription: String,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard let snippet = swiftmutQuotedSourceSnippetPrefix(locationDescription),
        swiftmutDescribedValueSnippetLooksMappable(snippet),
        let text = swiftmutRead(path) else {
    return nil
  }

  let prefixes = swiftmutDescribedValueSnippetPrefixes(snippet)
  guard !prefixes.isEmpty else {
    return nil
  }

  let identifiers = swiftmutSourceExpressionIdentifiers(for: apply)
  var matches: [(line: Int, column: Int, sourceOriginal: String, sourceMutated: String)] = []
  var currentLine = 1
  var lineStart = text.startIndex
  var index = text.startIndex

  func inspectLine(_ lineText: String, line: Int) {
    guard matches.count < 2 else {
      return
    }
    let bytes = Array(lineText.utf8)
    let start = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
    let end = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
    guard start < end else {
      return
    }

    for prefix in prefixes {
      guard let matchStart = swiftmutASCIIIndex(bytes, start: start, end: end, pattern: prefix),
            let expression = swiftmutDescribedValueExpression(
              bytes: bytes,
              matchStart: matchStart,
              lineEnd: end,
              identifiers: identifiers,
              mutation: mutation
            ) else {
        continue
      }
      matches.append((line, expression.column, expression.sourceOriginal, expression.sourceMutated))
      return
    }
  }

  while index < text.endIndex {
    if text[index] == "\n" {
      inspectLine(String(text[lineStart..<index]), line: currentLine)
      if matches.count >= 2 {
        break
      }
      currentLine += 1
      lineStart = text.index(after: index)
    }
    index = text.index(after: index)
  }

  if index == text.endIndex && matches.count < 2 {
    inspectLine(String(text[lineStart..<text.endIndex]), line: currentLine)
  }

  guard matches.count == 1,
        let match = matches.first else {
    return nil
  }
  return (
    swiftmutTrimPackageRoot(path, config: config),
    match.line,
    match.column,
    match.sourceOriginal,
    match.sourceMutated)
}

func swiftmutDescribedValueSnippetLooksMappable(_ snippet: String) -> Bool {
  let bytes = Array(snippet.utf8)
  var start = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
  guard start < bytes.count else {
    return false
  }
  if start + 1 < bytes.count
      && (bytes[start] == 38 || bytes[start] == 124)
      && bytes[start + 1] == bytes[start] {
    start = swiftmutSkipHorizontalWhitespace(bytes, from: start + 2)
  }
  if start < bytes.count && bytes[start] == 33 {
    start = swiftmutSkipHorizontalWhitespace(bytes, from: start + 1)
  }
  if swiftmutDescribedSnippetStartsWithOperator(bytes: bytes, start: start, end: bytes.count) {
    return true
  }
  guard start < bytes.count,
        !swiftmutASCIIHasExactPrefix(bytes, start: start, prefix: "()") else {
    return false
  }
  let first = bytes[start]
  return (first >= 65 && first <= 90) || (first >= 97 && first <= 122) || first == 95
}

func swiftmutDescribedValueSnippetPrefixes(_ snippet: String) -> [String] {
  let bytes = Array(snippet.utf8)
  let start = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
  let end = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  guard start < end else {
    return []
  }

  var prefixes: [String] = []
  func appendPrefix(start: Int) {
    let trimmedStart = swiftmutSkipHorizontalWhitespace(bytes, from: start)
    guard trimmedStart < end,
          end - trimmedStart >= 5 else {
      return
    }
    let prefix = String(decoding: bytes[trimmedStart..<end], as: UTF8.self)
    if !prefixes.contains(prefix) {
      prefixes.append(prefix)
    }
  }

  appendPrefix(start: start)
  if start + 1 < end
      && (bytes[start] == 38 || bytes[start] == 124)
      && bytes[start + 1] == bytes[start] {
    appendPrefix(start: start + 2)
  }
  if start < end && bytes[start] == 33 {
    appendPrefix(start: start + 1)
  }
  return prefixes
}

func swiftmutDescribedValueExpression(
  bytes: [UInt8],
  matchStart: Int,
  lineEnd: Int,
  identifiers: [String],
  mutation: SwiftmutMutation
) -> (column: Int, sourceOriginal: String, sourceMutated: String)? {
  let expressionSearchStart = swiftmutDescribedValueExpressionSearchStart(
    bytes: bytes,
    matchStart: matchStart,
    lineEnd: lineEnd
  )

  if let expression = swiftmutDescribedOperatorValueExpression(
    bytes: bytes,
    matchStart: matchStart,
    lineEnd: lineEnd,
    mutation: mutation
  ) {
    return expression
  }

  for identifier in identifiers {
    guard let tokenRange = swiftmutFindSourceIdentifier(
      identifier,
      in: bytes,
      start: expressionSearchStart,
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
    return swiftmutDescribedValueExpressionResult(
      bytes: bytes,
      expressionRange: expressionRange,
      mutation: mutation
    )
  }

  guard let tokenRange = swiftmutFirstCallLikeSourceIdentifier(
    bytes: bytes,
    start: expressionSearchStart,
    end: lineEnd
  ),
  let expressionRange = swiftmutSourceExpressionRange(
    around: tokenRange,
    in: bytes,
    lineEnd: lineEnd
  ),
  swiftmutReturnValueIsEligible(bytes: bytes, start: expressionRange.start, mutation: mutation) else {
    return nil
  }
  return swiftmutDescribedValueExpressionResult(
    bytes: bytes,
    expressionRange: expressionRange,
    mutation: mutation
  )
}

func swiftmutDescribedOperatorValueExpression(
  bytes: [UInt8],
  matchStart: Int,
  lineEnd: Int,
  mutation: SwiftmutMutation
) -> (column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard swiftmutDescribedSnippetStartsWithOperator(bytes: bytes, start: matchStart, end: lineEnd) else {
    return nil
  }
  let lhsEnd = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: matchStart)
  guard lhsEnd > 0 else {
    return nil
  }

  var expressionStart = lhsEnd
  while expressionStart > 0 {
    let previous = bytes[expressionStart - 1]
    if previous == 123 || previous == 40 || previous == 91 || previous == 44 || previous == 61 {
      break
    }
    expressionStart -= 1
  }
  expressionStart = swiftmutSkipHorizontalWhitespace(bytes, from: expressionStart)

  guard expressionStart < lhsEnd,
        swiftmutReturnValueIsEligible(bytes: bytes, start: expressionStart, mutation: mutation) else {
    return nil
  }

  let expressionEnd = swiftmutDescribedOperatorExpressionEnd(
    bytes: bytes,
    start: matchStart,
    lineEnd: lineEnd
  )
  guard expressionEnd > matchStart else {
    return nil
  }

  let sourceOriginal = String(decoding: bytes[expressionStart..<expressionEnd], as: UTF8.self)
  return (
    expressionStart + 1,
    sourceOriginal,
    swiftmutImplicitReturnSourceMutation(for: mutation))
}

func swiftmutDescribedSnippetStartsWithOperator(bytes: [UInt8], start: Int, end: Int) -> Bool {
  let index = swiftmutSkipHorizontalWhitespace(bytes, from: start)
  guard index + 1 < end else {
    return false
  }
  if bytes[index] == 61 && bytes[index + 1] == 61 {
    return true
  }
  if bytes[index] == 33 && bytes[index + 1] == 61 {
    return true
  }
  return bytes[index] == 60 || bytes[index] == 62
}

func swiftmutDescribedOperatorExpressionEnd(
  bytes: [UInt8],
  start: Int,
  lineEnd: Int
) -> Int {
  var index = start
  var parenDepth = 0
  var bracketDepth = 0
  var inString = false
  while index < lineEnd {
    let byte = bytes[index]
    if byte == 34 {
      inString = !inString
    } else if !inString {
      if byte == 40 {
        parenDepth += 1
      } else if byte == 41 {
        if parenDepth == 0 {
          break
        }
        parenDepth -= 1
      } else if byte == 91 {
        bracketDepth += 1
      } else if byte == 93 {
        if bracketDepth == 0 {
          break
        }
        bracketDepth -= 1
      } else if parenDepth == 0 && bracketDepth == 0 {
        if byte == 123 || byte == 125 || byte == 44 {
          break
        }
        if index + 1 < lineEnd,
           (byte == 38 || byte == 124),
           bytes[index + 1] == byte {
          break
        }
      }
    }
    index += 1
  }
  return swiftmutTrimTrailingHorizontalWhitespace(bytes, end: index)
}

func swiftmutDescribedValueExpressionSearchStart(
  bytes: [UInt8],
  matchStart: Int,
  lineEnd: Int
) -> Int {
  var start = swiftmutSkipHorizontalWhitespace(bytes, from: matchStart)
  if start + 1 < lineEnd
      && (bytes[start] == 38 || bytes[start] == 124)
      && bytes[start + 1] == bytes[start] {
    start = swiftmutSkipHorizontalWhitespace(bytes, from: start + 2)
  }
  if start < lineEnd && bytes[start] == 33 {
    start = swiftmutSkipHorizontalWhitespace(bytes, from: start + 1)
  }
  return start
}

func swiftmutDescribedValueExpressionResult(
  bytes: [UInt8],
  expressionRange: (start: Int, end: Int),
  mutation: SwiftmutMutation
) -> (column: Int, sourceOriginal: String, sourceMutated: String) {
  let sourceOriginal = String(decoding: bytes[expressionRange.start..<expressionRange.end], as: UTF8.self)
  return (
    expressionRange.start + 1,
    sourceOriginal,
    swiftmutImplicitReturnSourceMutation(for: mutation))
}
