//===--- SwiftmutExplicitReturnSourceLocations.swift ----------------------------------------------===//
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

func swiftmutReturnSourceLocationIsUsable(
  _ location: (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String),
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> Bool {
  if mutation.sourceOriginal == "return" {
    return swiftmutReturnSourceLooksLikeStatement(file: location.file, line: location.line, config: config)
  }
  return true
}

func swiftmutFindUniqueExplicitReturnSourceLocation(
  path: String,
  preferredLine: Int,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard preferredLine > 0,
        let text = swiftmutRead(path) else {
    return nil
  }

  if let exactLine = swiftmutAbsoluteSourceLine(path: path, line: preferredLine) {
    let bytes = Array(exactLine.utf8)
    let start = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
    if swiftmutReturnLineIsEligible(bytes: bytes, start: start, mutation: mutation) {
      return (
        swiftmutTrimPackageRoot(path, config: config),
        preferredLine,
        start + 1,
        mutation.sourceOriginal,
        mutation.sourceMutated)
    }
  }

  var matches: [(line: Int, column: Int)] = []
  var currentLine = 1
  var lineStart = text.startIndex
  var index = text.startIndex
  var braceDepth = 0
  var sawOpeningBrace = false

  func inspectLine(_ lineText: String, line: Int) {
    guard line >= preferredLine,
          line <= preferredLine + 120,
          matches.count < 2 else {
      return
    }
    let bytes = Array(lineText.utf8)
    let start = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
    if swiftmutReturnLineIsEligible(bytes: bytes, start: start, mutation: mutation) {
      matches.append((line, start + 1))
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
      inspectLine(lineText, line: currentLine)
      if currentLine >= preferredLine {
        updateBraceDepth(lineText)
        if sawOpeningBrace && braceDepth <= 0 {
          break
        }
        if currentLine >= preferredLine + 120 {
          break
        }
      }
      currentLine += 1
      lineStart = text.index(after: index)
    }
    index = text.index(after: index)
  }

  if index == text.endIndex && currentLine >= preferredLine {
    let lineText = String(text[lineStart..<text.endIndex])
    inspectLine(lineText, line: currentLine)
  }

  guard matches.count == 1,
        let match = matches.first else {
    return nil
  }
  return (
    swiftmutTrimPackageRoot(path, config: config),
    match.line,
    match.column,
    mutation.sourceOriginal,
    mutation.sourceMutated)
}

func swiftmutFindNearestPriorExplicitReturnSourceLocation(
  path: String,
  preferredLine: Int,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard preferredLine > 1,
        let text = swiftmutRead(path) else {
    return nil
  }

  let firstLine = preferredLine > 8 ? preferredLine - 8 : 1
  var nearest: (line: Int, column: Int)?
  var currentLine = 1
  var lineStart = text.startIndex
  var index = text.startIndex

  func inspectLine(_ lineText: String, line: Int) {
    guard line >= firstLine,
          line < preferredLine else {
      return
    }
    let bytes = Array(lineText.utf8)
    let start = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
    if swiftmutReturnLineIsEligible(bytes: bytes, start: start, mutation: mutation) {
      nearest = (line, start + 1)
    }
  }

  while index < text.endIndex {
    if text[index] == "\n" {
      inspectLine(String(text[lineStart..<index]), line: currentLine)
      if currentLine >= preferredLine {
        break
      }
      currentLine += 1
      lineStart = text.index(after: index)
    }
    index = text.index(after: index)
  }

  guard let nearest else {
    return nil
  }
  return (
    swiftmutTrimPackageRoot(path, config: config),
    nearest.line,
    nearest.column,
    mutation.sourceOriginal,
    mutation.sourceMutated)
}

func swiftmutFindDescribedExplicitReturnSourceLocation(
  path: String,
  preferredLine: Int,
  locationDescription: String,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard preferredLine > 0,
        let snippet = swiftmutQuotedSourceSnippetPrefix(locationDescription),
        snippet.hasPrefix("return "),
        let text = swiftmutRead(path) else {
    return nil
  }

  var matches: [(line: Int, column: Int)] = []
  var currentLine = 1
  var lineStart = text.startIndex
  var index = text.startIndex
  var braceDepth = 0
  var sawOpeningBrace = false

  func inspectLine(_ lineText: String, line: Int) {
    guard line >= preferredLine,
          line <= preferredLine + 120,
          matches.count < 2 else {
      return
    }
    let bytes = Array(lineText.utf8)
    let start = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
    guard swiftmutReturnLineIsEligible(bytes: bytes, start: start, mutation: mutation) else {
      return
    }
    let trimmed = String(decoding: bytes[start..<swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)], as: UTF8.self)
    if trimmed.hasPrefix(snippet) {
      matches.append((line, start + 1))
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
        inspectLine(lineText, line: currentLine)
        updateBraceDepth(lineText)
        if matches.count >= 2 {
          break
        }
        if sawOpeningBrace && braceDepth <= 0 {
          break
        }
        if currentLine >= preferredLine + 120 {
          break
        }
      }
      currentLine += 1
      lineStart = text.index(after: index)
    }
    index = text.index(after: index)
  }

  if index == text.endIndex && currentLine >= preferredLine {
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
    mutation.sourceOriginal,
    mutation.sourceMutated)
}

func swiftmutFindDescribedDefaultArgumentReturnSourceLocation(
  functionName: String,
  locationDescription: String,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard let rawSnippet = swiftmutQuotedSourceSearchSnippet(locationDescription),
        rawSnippet.count >= 4 else {
    return nil
  }

  let snippet = swiftmutDecodedSourceSnippet(rawSnippet)
  guard swiftmutDefaultArgumentSnippetLooksMappable(snippet, functionName: functionName) else {
    return nil
  }

  var matches: [(path: String, line: Int, column: Int, sourceOriginal: String, score: Int)] = []
  for path in swiftmutSwiftSourcePaths(config: config) {
    guard let text = swiftmutRead(path) else {
      continue
    }
    let fileMatches = swiftmutSourceSnippetMatches(snippet, in: text)
    for match in fileMatches {
      guard let expression = swiftmutDefaultArgumentSourceExpression(
        in: text,
        matchOffset: match.offset,
        mutation: mutation
      ) else {
        continue
      }
      let score = swiftmutDefaultArgumentDeclarationScore(
        functionName: functionName,
        sourceText: text,
        line: match.line
      )
      matches.append((
        path,
        match.line,
        match.column + expression.columnOffset,
        expression.text,
        score))
    }
  }

  guard !matches.isEmpty else {
    return nil
  }
  let bestScore = matches.map { $0.score }.max() ?? 0
  let bestMatches = matches.filter { $0.score == bestScore }
  guard bestMatches.count == 1,
        let match = bestMatches.first else {
    return nil
  }

  return (
    swiftmutTrimPackageRoot(match.path, config: config),
    match.line,
    match.column,
    match.sourceOriginal,
    swiftmutImplicitReturnSourceMutation(for: mutation))
}

func swiftmutQuotedSourceSearchSnippet(_ description: String) -> String? {
  let bytes = Array(description.utf8)
  guard bytes.count > 1,
        bytes[0] == 34 else {
    return nil
  }

  var end = 1
  while end < bytes.count {
    if end + 4 <= bytes.count,
       bytes[end] == 91,
       bytes[end + 1] == 46,
       bytes[end + 2] == 46,
       bytes[end + 3] == 46 {
      break
    }
    if end + 9 <= bytes.count,
       bytes[end] == 34,
       bytes[end + 1] == 44,
       bytes[end + 2] == 32,
       bytes[end + 3] == 115,
       bytes[end + 4] == 99,
       bytes[end + 5] == 111,
       bytes[end + 6] == 112,
       bytes[end + 7] == 101,
       bytes[end + 8] == 61 {
      break
    }
    end += 1
  }

  let trimmedEnd = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: end)
  guard trimmedEnd > 1 else {
    return nil
  }
  return String(decoding: bytes[1..<trimmedEnd], as: UTF8.self)
}

func swiftmutDecodedSourceSnippet(_ snippet: String) -> String {
  let bytes = Array(snippet.utf8)
  var decoded: [UInt8] = []
  var index = 0
  while index < bytes.count {
    if bytes[index] == 92,
       index + 1 < bytes.count {
      let next = bytes[index + 1]
      switch next {
      case 34, 92:
        decoded.append(next)
        index += 2
        continue
      case 110:
        decoded.append(10)
        index += 2
        continue
      case 116:
        decoded.append(9)
        index += 2
        continue
      default:
        break
      }
    }
    decoded.append(bytes[index])
    index += 1
  }
  return String(decoding: decoded, as: UTF8.self)
}

func swiftmutDefaultArgumentSnippetLooksMappable(
  _ snippet: String,
  functionName: String
) -> Bool {
  let bytes = Array(snippet.utf8)
  guard bytes.count >= 4 else {
    return false
  }
  for byte in bytes where byte == 10 || byte == 13 {
    return true
  }
  guard swiftmutFunctionNameLooksDefaultArgumentThunk(functionName) else {
    return false
  }
  for byte in bytes where byte == 41 || byte == 44 {
    return true
  }
  return false
}

func swiftmutFunctionNameLooksDefaultArgumentThunk(_ functionName: String) -> Bool {
  let bytes = Array(functionName.utf8)
  guard bytes.count >= 3 else {
    return false
  }
  for index in 0..<(bytes.count - 2) {
    if bytes[index] == 102,
       bytes[index + 1] == 65,
       swiftmutIsASCIILetterNumberOrUnderscore(bytes[index + 2]) {
      return true
    }
  }
  return false
}

func swiftmutDefaultArgumentSnippetExpression(
  _ snippet: String,
  mutation: SwiftmutMutation
) -> String? {
  swiftmutDefaultArgumentExpression(
    bytes: Array(snippet.utf8),
    from: 0,
    mutation: mutation
  )?.text
}

func swiftmutDefaultArgumentSourceExpression(
  in sourceText: String,
  matchOffset: Int,
  mutation: SwiftmutMutation
) -> (columnOffset: Int, text: String)? {
  let bytes = Array(sourceText.utf8)
  guard matchOffset >= 0,
        matchOffset < bytes.count,
        let expression = swiftmutDefaultArgumentExpression(
          bytes: bytes,
          from: matchOffset,
          mutation: mutation
        ) else {
    return nil
  }
  return (expression.start - matchOffset, expression.text)
}

func swiftmutDefaultArgumentExpression(
  bytes: [UInt8],
  from offset: Int,
  mutation: SwiftmutMutation
) -> (start: Int, text: String)? {
  let tokenStart = swiftmutSkipHorizontalWhitespace(bytes, from: offset)
  let start = swiftmutDefaultArgumentExpressionStart(bytes: bytes, tokenStart: tokenStart)
  guard start < bytes.count else {
    return nil
  }

  var index = start
  var inString = false
  var escaped = false
  var squareDepth = 0
  var parenDepth = 0
  var braceDepth = 0
  while index < bytes.count {
    let byte = bytes[index]
    if inString {
      if escaped {
        escaped = false
      } else if byte == 92 {
        escaped = true
      } else if byte == 34 {
        inString = false
      }
      index += 1
      continue
    }

    if byte == 34 {
      inString = true
    } else if byte == 91 {
      squareDepth += 1
    } else if byte == 93 {
      squareDepth -= 1
    } else if byte == 123 {
      braceDepth += 1
    } else if byte == 125 {
      if braceDepth == 0 {
        break
      }
      braceDepth -= 1
    } else if byte == 40 {
      parenDepth += 1
    } else if byte == 41 {
      if parenDepth == 0 {
        break
      }
      parenDepth -= 1
    } else if squareDepth == 0 && parenDepth == 0 && braceDepth == 0
                && (byte == 44 || byte == 10 || byte == 13) {
      break
    }
    if squareDepth < 0 || parenDepth < 0 || braceDepth < 0 {
      return nil
    }
    index += 1
  }

  let end = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: index)
  guard end > start else {
    return nil
  }
  let expression = String(decoding: bytes[start..<end], as: UTF8.self)
  let expressionBytes = Array(expression.utf8)
  guard swiftmutImplicitReturnExpressionIsEligible(
    bytes: expressionBytes,
    start: swiftmutSkipHorizontalWhitespace(expressionBytes, from: 0),
      mutation: mutation,
      allowsInlineBraces: true
  ), swiftmutSourceOriginalIsComplete(expression) else {
    return nil
  }
  return (start, expression)
}

func swiftmutDefaultArgumentExpressionStart(bytes: [UInt8], tokenStart: Int) -> Int {
  var start = tokenStart
  while start > 0 && swiftmutIsSourceExpressionPrefixByte(bytes[start - 1]) {
    start -= 1
  }
  return start
}

func swiftmutSourceSnippetMatches(
  _ snippet: String,
  in text: String
) -> [(line: Int, column: Int, offset: Int)] {
  let source = Array(text.utf8)
  let pattern = Array(snippet.utf8)
  guard !pattern.isEmpty,
        pattern.count <= source.count else {
    return []
  }

  var matches: [(line: Int, column: Int, offset: Int)] = []
  var index = 0
  while index + pattern.count <= source.count {
    var matched = true
    for offset in 0..<pattern.count where source[index + offset] != pattern[offset] {
      matched = false
      break
    }
    if matched {
      let location = swiftmutSourceLineAndColumn(source, offset: index)
      matches.append((line: location.line, column: location.column, offset: index))
      if matches.count > 8 {
        return matches
      }
      index += pattern.count
    } else {
      index += 1
    }
  }
  return matches
}

func swiftmutSnippetExpressionStartOffset(_ snippet: String) -> Int {
  swiftmutSkipHorizontalWhitespace(Array(snippet.utf8), from: 0)
}

func swiftmutSourceLine(_ text: String, line targetLine: Int) -> String? {
  guard targetLine > 0 else {
    return nil
  }

  var currentLine = 1
  var lineStart = text.startIndex
  var index = text.startIndex
  while index < text.endIndex {
    if text[index] == "\n" {
      if currentLine == targetLine {
        return String(text[lineStart..<index])
      }
      currentLine += 1
      lineStart = text.index(after: index)
    }
    index = text.index(after: index)
  }

  if currentLine == targetLine {
    return String(text[lineStart..<text.endIndex])
  }
  return nil
}

func swiftmutSourceLineAndColumn(
  _ bytes: [UInt8],
  offset: Int
) -> (line: Int, column: Int) {
  var line = 1
  var column = 1
  var index = 0
  while index < offset && index < bytes.count {
    if bytes[index] == 10 {
      line += 1
      column = 1
    } else {
      column += 1
    }
    index += 1
  }
  return (line, column)
}

func swiftmutDefaultArgumentDeclarationScore(
  functionName: String,
  sourceText: String,
  line: Int
) -> Int {
  guard line > 0 else {
    return 0
  }
  let lines = sourceText.split(separator: "\n", omittingEmptySubsequences: false)
  let startLine = max(1, line - 160)
  let endLine = min(lines.count, line)
  var signature = ""
  if startLine <= endLine {
    for currentLine in startLine...endLine {
      signature += String(lines[currentLine - 1])
      signature += "\n"
    }
  }

  var score = 0
  if let functionIdentifier = swiftmutNearestFunctionIdentifier(in: signature),
     swiftmutMangledNameContainsIdentifier(functionName, identifier: functionIdentifier) {
    score += 2
  }
  if let typeIdentifier = swiftmutNearestTypeIdentifier(in: signature),
     swiftmutMangledNameContainsIdentifier(functionName, identifier: typeIdentifier) {
    score += 1
  }
  let signatureBytes = Array(signature.utf8)
  if swiftmutASCIIContains(signatureBytes, start: 0, end: signatureBytes.count, pattern: "init("),
     functionName.contains("cf") {
    score += 1
  }
  return score
}

func swiftmutNearestFunctionIdentifier(in signature: String) -> String? {
  let lines = signature.split(separator: "\n", omittingEmptySubsequences: false)
  var index = lines.count
  while index > 0 {
    index -= 1
    let line = String(lines[index])
    if let identifier = swiftmutDeclarationIdentifier(after: "public static func ", in: line) {
      return identifier
    }
    if let identifier = swiftmutDeclarationIdentifier(after: "static func ", in: line) {
      return identifier
    }
    if let identifier = swiftmutDeclarationIdentifier(after: "public func ", in: line) {
      return identifier
    }
    if let identifier = swiftmutDeclarationIdentifier(after: "private func ", in: line) {
      return identifier
    }
    if let identifier = swiftmutDeclarationIdentifier(after: "func ", in: line) {
      return identifier
    }
    let bytes = Array(line.utf8)
    if swiftmutASCIIContains(bytes, start: 0, end: bytes.count, pattern: "init(") {
      return "init"
    }
  }
  return nil
}

func swiftmutNearestTypeIdentifier(in signature: String) -> String? {
  let lines = signature.split(separator: "\n", omittingEmptySubsequences: false)
  var index = lines.count
  while index > 0 {
    index -= 1
    let line = String(lines[index])
    if let identifier = swiftmutDeclarationIdentifier(after: "struct ", in: line) {
      return identifier
    }
    if let identifier = swiftmutDeclarationIdentifier(after: "enum ", in: line) {
      return identifier
    }
    if let identifier = swiftmutDeclarationIdentifier(after: "class ", in: line) {
      return identifier
    }
  }
  return nil
}

func swiftmutDeclarationIdentifier(after marker: String, in line: String) -> String? {
  let bytes = Array(line.utf8)
  guard let markerStart = swiftmutASCIIIndex(bytes, start: 0, end: bytes.count, pattern: marker) else {
    return nil
  }
  var index = markerStart + marker.utf8.count
  index = swiftmutSkipHorizontalWhitespace(bytes, from: index)
  let start = index
  while index < bytes.count && swiftmutIsIdentifierByte(bytes[index]) {
    index += 1
  }
  guard index > start else {
    return nil
  }
  return String(decoding: bytes[start..<index], as: UTF8.self)
}
