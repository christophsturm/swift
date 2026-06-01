//===--- SwiftmutOperatorValueApplySourceLocations.swift ------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2026 swiftmut contributors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

func swiftmutFindOperatorValueApplySourceLocation(
  path: String,
  functionLine: Int,
  locationDescription: String,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard functionLine > 0,
        let snippet = swiftmutQuotedSourceSnippetPrefix(locationDescription),
        swiftmutOperatorValueApplySnippetLooksMappable(snippet),
        let text = swiftmutRead(path) else {
    return nil
  }

  var matches: [(line: Int, column: Int, sourceOriginal: String)] = []
  var currentLine = 1
  var lineStart = text.startIndex
  var index = text.startIndex
  var braceDepth = 0
  var sawOpeningBrace = false

  func inspectLine(_ lineText: String, line: Int) {
    guard line >= functionLine,
          matches.count < 2,
          let expression = swiftmutOperatorValueApplyExpression(
            lineText,
            snippet: snippet,
            mutation: mutation
          ) else {
      return
    }
    matches.append((line, expression.column, expression.sourceOriginal))
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
    swiftmutImplicitReturnSourceMutation(for: mutation))
}

func swiftmutOperatorValueApplySnippetLooksMappable(_ snippet: String) -> Bool {
  let bytes = Array(snippet.utf8)
  let start = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
  return swiftmutDescribedSnippetStartsWithOperator(bytes: bytes, start: start, end: bytes.count)
}

func swiftmutOperatorValueApplyExpression(
  _ line: String,
  snippet: String,
  mutation: SwiftmutMutation
) -> (column: Int, sourceOriginal: String)? {
  let bytes = Array(line.utf8)
  let start = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
  let end = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  guard start < end,
        let matchStart = swiftmutASCIIIndex(bytes, start: start, end: end, pattern: snippet),
        let expression = swiftmutDescribedOperatorValueExpression(
          bytes: bytes,
          matchStart: matchStart,
          lineEnd: end,
          mutation: mutation
        ),
        !swiftmutOperatorValueApplyIsLogicalRHS(bytes: bytes, expressionStart: expression.column - 1) else {
    return nil
  }
  return (expression.column, expression.sourceOriginal)
}

func swiftmutOperatorValueApplyIsLogicalRHS(bytes: [UInt8], expressionStart: Int) -> Bool {
  var index = expressionStart
  while index > 0 {
    let previous = bytes[index - 1]
    if swiftmutIsHorizontalWhitespace(previous) {
      index -= 1
      continue
    }
    guard index >= 2 else {
      return false
    }
    let lhs = bytes[index - 2]
    return (lhs == 38 || lhs == 124) && bytes[index - 1] == lhs
  }
  return false
}
