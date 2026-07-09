//===--- SwiftmutLogicalRHSValueApplySourceLocations.swift ----------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2026 swiftmut contributors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

func swiftmutFindLogicalRHSValueApplySourceLocation(
  path: String,
  functionLine: Int,
  locationDescription: String,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard functionLine > 0,
        let snippet = swiftmutQuotedSourceSnippetPrefix(locationDescription),
        swiftmutLogicalRHSSnippetLooksMappable(snippet),
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
          let expression = swiftmutLogicalRHSValueExpression(
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
        if braceDepth > 0 {
          inspectLine(lineText, line: currentLine)
          if matches.count >= 2 {
            break
          }
        }
      }
      updateBraceDepth(lineText)
      if currentLine >= functionLine && sawOpeningBrace && braceDepth <= 0 {
        break
      }
      currentLine += 1
      lineStart = text.index(after: index)
    }
    index = text.index(after: index)
  }

  if index == text.endIndex && currentLine >= functionLine && braceDepth > 0 {
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

func swiftmutLogicalRHSSnippetLooksMappable(_ snippet: String) -> Bool {
  let bytes = Array(snippet.utf8)
  let start = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
  let end = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  guard start < end else {
    return false
  }
  return swiftmutLogicalRHSOperatorIndex(bytes: bytes, start: start, end: end) != nil
    || swiftmutIsASCIIIdentifierStart(bytes[start])
}

func swiftmutLogicalRHSValueExpression(
  _ line: String,
  snippet: String,
  mutation: SwiftmutMutation
) -> (column: Int, sourceOriginal: String)? {
  let bytes = Array(line.utf8)
  let start = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
  let end = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  let snippetBytes = Array(snippet.utf8)
  guard start < end,
        let matchStart = swiftmutASCIIIndex(bytes, start: start, end: end, pattern: snippet) else {
    return nil
  }
  if let operatorOffset = swiftmutLogicalRHSOperatorIndex(
    bytes: snippetBytes,
    start: 0,
    end: snippetBytes.count
  ),
     let expression = swiftmutDescribedLogicalOperatorRHSValueExpression(
       bytes: bytes,
       matchStart: matchStart + operatorOffset,
       lineEnd: end,
       mutation: mutation
     ) {
    return (expression.column, expression.sourceOriginal)
  }
  guard swiftmutLogicalRHSOperatorPrecedes(bytes: bytes, expressionStart: matchStart) else {
    return nil
  }
  let expressionEnd = swiftmutTrimTrailingElseKeyword(
    bytes: bytes,
    end: swiftmutDescribedOperatorExpressionEnd(
      bytes: bytes,
      start: matchStart,
      lineEnd: end
    )
  )
  guard matchStart < expressionEnd,
        swiftmutReturnValueIsEligible(bytes: bytes, start: matchStart, mutation: mutation) else {
    return nil
  }
  return (
    matchStart + 1,
    String(decoding: bytes[matchStart..<expressionEnd], as: UTF8.self))
}

func swiftmutLogicalRHSOperatorIndex(bytes: [UInt8], start: Int, end: Int) -> Int? {
  var index = swiftmutSkipHorizontalWhitespace(bytes, from: start)
  while index + 1 < end {
    if (bytes[index] == 38 || bytes[index] == 124),
       bytes[index + 1] == bytes[index] {
      return index
    }
    index += 1
  }
  return nil
}

func swiftmutLogicalRHSOperatorPrecedes(bytes: [UInt8], expressionStart: Int) -> Bool {
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
    let operatorByte = bytes[index - 1]
    return (operatorByte == 38 || operatorByte == 124) && bytes[index - 2] == operatorByte
  }
  return false
}
