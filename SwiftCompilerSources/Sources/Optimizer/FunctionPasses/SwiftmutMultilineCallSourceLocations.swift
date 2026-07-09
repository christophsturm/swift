//===--- SwiftmutMultilineCallSourceLocations.swift ----------------------------------------------===//
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

func swiftmutFindMultilineCallValueSourceLocation(
  path: String,
  functionLine: Int,
  locationDescription: String,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard functionLine > 0,
        let snippet = swiftmutQuotedSourceSnippetPrefix(locationDescription),
        let prefix = swiftmutMultilineCallPrefix(from: snippet),
        let text = swiftmutRead(path) else {
    return nil
  }

  var matches: [(line: Int, column: Int, sourceOriginal: String)] = []
  var currentLine = 1
  var lineStart = text.startIndex
  var lineStartUTF8Offset = 0
  var index = text.startIndex
  var braceDepth = 0
  var sawOpeningBrace = false

  func inspectLine(_ lineText: String, line: Int, lineStartUTF8Offset: Int) {
    guard line >= functionLine,
          matches.count < 2 else {
      return
    }
    let bytes = Array(lineText.utf8)
    let lineEnd = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
    var searchStart = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
    while let matchStart = swiftmutASCIIIndex(bytes, start: searchStart, end: lineEnd, pattern: prefix) {
      guard let expression = swiftmutMultilineCallExpression(
        text: text,
        lineBytes: bytes,
        lineStartUTF8Offset: lineStartUTF8Offset,
        matchStart: matchStart,
        lineEnd: lineEnd,
        mutation: mutation
      ) else {
        searchStart = matchStart + prefix.utf8.count
        continue
      }
      matches.append((line, expression.column, expression.sourceOriginal))
      if matches.count >= 2 {
        return
      }
      searchStart = matchStart + prefix.utf8.count
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
          inspectLine(lineText, line: currentLine, lineStartUTF8Offset: lineStartUTF8Offset)
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
      lineStartUTF8Offset += lineText.utf8.count + 1
      lineStart = text.index(after: index)
    }
    index = text.index(after: index)
  }

  if index == text.endIndex && currentLine >= functionLine && sawOpeningBrace && braceDepth > 0 {
    inspectLine(
      String(text[lineStart..<text.endIndex]),
      line: currentLine,
      lineStartUTF8Offset: lineStartUTF8Offset
    )
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

func swiftmutMultilineCallPrefix(from snippet: String) -> String? {
  let bytes = Array(snippet.utf8)
  let start = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
  let end = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  guard start < end else {
    return nil
  }
  let prefix: String
  if let open = swiftmutASCIIIndex(bytes, start: start, end: end, pattern: "(") {
    guard open > start else {
      return nil
    }
    prefix = String(decoding: bytes[start...open], as: UTF8.self)
  } else {
    prefix = String(decoding: bytes[start..<end], as: UTF8.self)
  }
  guard prefix.count >= 5 else {
    return nil
  }
  return prefix
}

func swiftmutMultilineCallExpression(
  text: String,
  lineBytes: [UInt8],
  lineStartUTF8Offset: Int,
  matchStart: Int,
  lineEnd: Int,
  mutation: SwiftmutMutation
) -> (column: Int, sourceOriginal: String)? {
  guard matchStart < lineEnd,
        let open = swiftmutASCIIIndex(lineBytes, start: matchStart, end: lineEnd, pattern: "(") else {
    return nil
  }
  let expressionStart = swiftmutMultilineCallExpressionStart(
    lineBytes: lineBytes,
    matchStart: matchStart
  )
  guard swiftmutReturnValueIsEligible(bytes: lineBytes, start: expressionStart, mutation: mutation) else {
    return nil
  }

  let absoluteOpenOffset = lineStartUTF8Offset + open
  guard let absoluteOpen = swiftmutStringIndex(in: text, utf8Offset: absoluteOpenOffset) else {
    return nil
  }
  guard let expressionEnd = swiftmutMultilineCallEnd(in: text, openIndex: absoluteOpen) else {
    return nil
  }
  guard let expressionStartIndex = swiftmutStringIndex(
    in: text,
    utf8Offset: lineStartUTF8Offset + expressionStart
  ) else {
    return nil
  }
  let sourceOriginal = String(text[expressionStartIndex..<expressionEnd])
  return (expressionStart + 1, sourceOriginal)
}

func swiftmutStringIndex(in text: String, utf8Offset: Int) -> String.Index? {
  guard utf8Offset >= 0,
        utf8Offset <= text.utf8.count else {
    return nil
  }
  let utf8Index = text.utf8.index(text.utf8.startIndex, offsetBy: utf8Offset)
  return utf8Index.samePosition(in: text)
}

func swiftmutMultilineCallExpressionStart(lineBytes: [UInt8], matchStart: Int) -> Int {
  var start = matchStart
  while start > 0 {
    let previous = lineBytes[start - 1]
    if swiftmutIsSourceExpressionPrefixByte(previous) {
      start -= 1
      continue
    }
    if previous == 41,
       let open = swiftmutMatchingOpenDelimiterBefore(
         in: lineBytes,
         closeIndex: start - 1,
         open: 40,
         close: 41
       ) {
      start = open
      continue
    }
    if previous == 93,
       let open = swiftmutMatchingOpenDelimiterBefore(
         in: lineBytes,
         closeIndex: start - 1,
         open: 91,
         close: 93
       ) {
      start = open
      continue
    }
    break
  }
  return swiftmutSkipHorizontalWhitespace(lineBytes, from: start)
}

func swiftmutMatchingOpenDelimiterBefore(
  in bytes: [UInt8],
  closeIndex: Int,
  open: UInt8,
  close: UInt8
) -> Int? {
  var depth = 0
  var index = closeIndex
  var quote: UInt8?
  var escaped = false
  while index >= 0 {
    let byte = bytes[index]
    if let activeQuote = quote {
      if escaped {
        escaped = false
      } else if byte == 92 {
        escaped = true
      } else if byte == activeQuote {
        quote = nil
      }
    } else if byte == 34 || byte == 39 {
      quote = byte
    } else if byte == close {
      depth += 1
    } else if byte == open {
      depth -= 1
      if depth == 0 {
        return index
      }
    }
    if index == 0 {
      break
    }
    index -= 1
  }
  return nil
}

func swiftmutMultilineCallEnd(in text: String, openIndex: String.Index) -> String.Index? {
  var depth = 0
  var index = openIndex
  var quote: Character?
  var escaped = false
  while index < text.endIndex {
    let character = text[index]
    if let activeQuote = quote {
      if escaped {
        escaped = false
      } else if character == "\\" {
        escaped = true
      } else if character == activeQuote {
        quote = nil
      }
      index = text.index(after: index)
      continue
    }
    if character == "\"" || character == "'" {
      quote = character
    } else if character == "(" {
      depth += 1
    } else if character == ")" {
      depth -= 1
      if depth == 0 {
        return text.index(after: index)
      }
    }
    index = text.index(after: index)
  }
  return nil
}
