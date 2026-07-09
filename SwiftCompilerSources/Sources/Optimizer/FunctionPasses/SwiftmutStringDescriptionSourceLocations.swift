//===--- SwiftmutStringDescriptionSourceLocations.swift ----------------------------------------------===//
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

func swiftmutFindStringDescriptionValueSourceLocation(
  for apply: ApplyInst,
  path: String,
  preferredLine: Int,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard let ordinal = swiftmutStringInterpolationApplyOrdinalAndCount(
    for: apply,
    mutation: mutation,
    config: config
  ), ordinal.count <= 40,
    let text = swiftmutRead(path) else {
    return nil
  }

  let candidates = swiftmutStringDescriptionExpressionCandidates(
    in: text,
    path: path,
    preferredLine: preferredLine,
    expectedCount: ordinal.count,
    mutation: mutation,
    config: config
  )
  guard candidates.count == ordinal.count,
        ordinal.ordinal > 0,
        ordinal.ordinal <= candidates.count else {
    return nil
  }
  return candidates[ordinal.ordinal - 1]
}

func swiftmutStringDescriptionExpressionCandidates(
  in text: String,
  path: String,
  preferredLine: Int,
  expectedCount: Int,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> [(file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)] {
  guard preferredLine > 0 else {
    return []
  }

  var candidates: [(file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)] = []
  var currentLine = 1
  var lineStart = text.startIndex
  var index = text.startIndex
  var braceDepth = 0
  var sawOpeningBrace = false

  func inspectLine(_ lineText: String, line: Int) {
    guard line >= preferredLine,
          candidates.count <= expectedCount else {
      return
    }
    let expressions = swiftmutStringDescriptionExpressions(on: lineText, mutation: mutation)
    for expression in expressions {
      candidates.append((
        swiftmutTrimPackageRoot(path, config: config),
        line,
        expression.column,
        expression.sourceOriginal,
        expression.sourceMutated
      ))
      if candidates.count > expectedCount {
        return
      }
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
      if currentLine >= preferredLine {
        if sawOpeningBrace && braceDepth > 0 {
          inspectLine(lineText, line: currentLine)
          if candidates.count > expectedCount {
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

  if index == text.endIndex && currentLine >= preferredLine && sawOpeningBrace && braceDepth > 0 {
    inspectLine(String(text[lineStart..<text.endIndex]), line: currentLine)
  }
  return candidates
}

func swiftmutStringDescriptionExpressions(
  on line: String,
  mutation: SwiftmutMutation
) -> [(column: Int, sourceOriginal: String, sourceMutated: String)] {
  let bytes = Array(line.utf8)
  let lineEnd = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  var expressions: [(column: Int, sourceOriginal: String, sourceMutated: String)] = []
  var index = 0
  while index < lineEnd {
    guard swiftmutASCIIHasExactPrefix(bytes, start: index, prefix: "String") else {
      index += 1
      continue
    }
    let afterName = index + 6
    guard index == 0 || !swiftmutIsASCIILetterNumberOrUnderscore(bytes[index - 1]) else {
      index = afterName
      continue
    }
    let open = swiftmutSkipHorizontalWhitespace(bytes, from: afterName)
    guard open < lineEnd,
          bytes[open] == 40,
          let close = swiftmutBalancedExpressionEnd(
            in: bytes,
            openIndex: open,
            close: 41,
            lineEnd: lineEnd
          ) else {
      index = afterName
      continue
    }
    if swiftmutStringDescriptionCallIsEligible(bytes: bytes, open: open, close: close) {
      expressions.append((
        index + 1,
        String(decoding: bytes[index..<close], as: UTF8.self),
        swiftmutImplicitReturnSourceMutation(for: mutation)
      ))
    }
    index = close
  }
  return expressions
}

func swiftmutStringDescriptionCallIsEligible(bytes: [UInt8], open: Int, close: Int) -> Bool {
  let argumentStart = swiftmutSkipHorizontalWhitespace(bytes, from: open + 1)
  let argumentEnd = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: close - 1)
  guard argumentStart < argumentEnd else {
    return false
  }
  if swiftmutASCIIHasPrefix(bytes, start: argumentStart, prefix: "format:") {
    return false
  }
  if swiftmutASCIIHasPrefix(bytes, start: argumentStart, prefix: "repeating:") {
    return false
  }
  if swiftmutASCIIHasPrefix(bytes, start: argumentStart, prefix: "decoding:") {
    return false
  }
  if swiftmutStringDescriptionHasTopLevelComma(bytes: bytes, start: argumentStart, end: argumentEnd) {
    return false
  }
  return true
}

func swiftmutStringDescriptionHasTopLevelComma(bytes: [UInt8], start: Int, end: Int) -> Bool {
  swiftmutFirstTopLevelIndex(bytes, start: start, end: end) { index in
    bytes[index] == 44
  } != nil
}
