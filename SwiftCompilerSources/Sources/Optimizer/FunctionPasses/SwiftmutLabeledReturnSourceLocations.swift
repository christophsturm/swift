//===--- SwiftmutLabeledReturnSourceLocations.swift ----------------------------------------------===//
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

func swiftmutBalancedExpressionEnd(
  in bytes: [UInt8],
  openIndex: Int,
  close: UInt8,
  lineEnd: Int
) -> Int? {
  let open = bytes[openIndex]
  var depth = 0
  var index = openIndex
  var quote: UInt8?
  var escaped = false
  while index < lineEnd {
    let byte = bytes[index]
    if let activeQuote = quote {
      if escaped {
        escaped = false
      } else if byte == 92 {
        escaped = true
      } else if byte == activeQuote {
        quote = nil
      }
      index += 1
      continue
    }
    if byte == 34 || byte == 39 {
      quote = byte
      index += 1
      continue
    }
    if byte == open {
      depth += 1
    } else if byte == close {
      depth -= 1
      if depth == 0 {
        return index + 1
      }
    }
    index += 1
  }
  return nil
}

func swiftmutFindLabeledValueExpressionSourceLocation(
  path: String,
  preferredLine: Int,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard preferredLine > 0,
        let text = swiftmutRead(path) else {
    return nil
  }

  if let exact = swiftmutLabeledValueExpressionSourceLocation(
    in: text,
    path: path,
    lineRange: preferredLine...preferredLine,
    mutation: mutation,
    config: config
  ) {
    return exact
  }

  let firstLine = preferredLine > 2 ? preferredLine - 2 : 1
  return swiftmutLabeledValueExpressionSourceLocation(
    in: text,
    path: path,
    lineRange: firstLine...(preferredLine + 24),
    mutation: mutation,
    config: config
  )
}

func swiftmutLabeledValueExpressionSourceLocation(
  in text: String,
  path: String,
  lineRange: ClosedRange<Int>,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  var matches: [(line: Int, column: Int, sourceOriginal: String, sourceMutated: String)] = []
  var currentLine = 1
  var lineStart = text.startIndex
  var index = text.startIndex

  func inspectLine(_ lineText: String, line: Int) {
    guard lineRange.contains(line),
          matches.count < 2,
          let expression = swiftmutStandaloneLabeledValueExpression(lineText, mutation: mutation) else {
      return
    }
    matches.append((line, expression.column, expression.sourceOriginal, expression.sourceMutated))
  }

  while index < text.endIndex {
    if text[index] == "\n" {
      inspectLine(String(text[lineStart..<index]), line: currentLine)
      if currentLine >= lineRange.upperBound || matches.count >= 2 {
        break
      }
      currentLine += 1
      lineStart = text.index(after: index)
    }
    index = text.index(after: index)
  }

  if index == text.endIndex && currentLine <= lineRange.upperBound {
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

func swiftmutStandaloneLabeledValueExpression(
  _ line: String,
  mutation: SwiftmutMutation,
  requiresCallExpression: Bool = true
) -> (column: Int, sourceOriginal: String, sourceMutated: String)? {
  let bytes = Array(line.utf8)
  let lineStart = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
  let lineEnd = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  guard lineStart < lineEnd,
        !swiftmutLineStartsWithAssignmentReturnBlockedPrefix(bytes: bytes, start: lineStart),
        swiftmutSourceLineLooksLikeArgumentLabel(bytes: bytes, start: lineStart, end: lineEnd),
        let colon = swiftmutFirstLabeledArgumentSeparator(bytes: bytes, start: lineStart, end: lineEnd) else {
    return nil
  }

  let valueStart = swiftmutSkipHorizontalWhitespace(bytes, from: colon + 1)
  var valueEnd = lineEnd
  if valueEnd > valueStart && bytes[valueEnd - 1] == 44 {
    valueEnd = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: valueEnd - 1)
  }
  guard valueStart < valueEnd,
        swiftmutLabeledArgumentRHSLooksLikeValueExpression(bytes: bytes, start: valueStart, end: valueEnd),
        (!requiresCallExpression || swiftmutLabeledArgumentRHSLooksLikeCallExpression(bytes: bytes, start: valueStart, end: valueEnd)),
        swiftmutReturnValueIsEligible(bytes: bytes, start: valueStart, mutation: mutation) else {
    return nil
  }

  let sourceOriginal = String(decoding: bytes[valueStart..<valueEnd], as: UTF8.self)
  return (
    valueStart + 1,
    sourceOriginal,
    swiftmutImplicitReturnSourceMutation(for: mutation))
}

func swiftmutStandaloneValueExpression(
  _ line: String,
  mutation: SwiftmutMutation
) -> (column: Int, sourceOriginal: String, sourceMutated: String)? {
  let bytes = Array(line.utf8)
  let lineStart = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
  let lineEnd = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  guard lineStart < lineEnd,
        swiftmutLineLooksLikeImplicitReturnExpression(bytes: bytes, start: lineStart, end: lineEnd),
        !swiftmutLineLooksLikeImplicitReturnContinuation(bytes: bytes, start: lineStart),
        swiftmutReturnValueIsEligible(bytes: bytes, start: lineStart, mutation: mutation) else {
    return nil
  }

  let sourceOriginal = String(decoding: bytes[lineStart..<lineEnd], as: UTF8.self)
  return (
    lineStart + 1,
    sourceOriginal,
    swiftmutImplicitReturnSourceMutation(for: mutation))
}

