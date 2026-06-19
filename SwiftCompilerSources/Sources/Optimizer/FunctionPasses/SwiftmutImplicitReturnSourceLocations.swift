//===--- SwiftmutImplicitReturnSourceLocations.swift ----------------------------------------------===//
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
import SwiftmutSupport

func swiftmutMangledNameContainsIdentifier(
  _ functionName: String,
  identifier: String
) -> Bool {
  SwiftmutSupport.swiftmutMangledNameContainsIdentifier(functionName, identifier: identifier)
}

func swiftmutMangledNameContainsIdentifierWords(
  _ functionName: String,
  identifier: String
) -> Bool {
  SwiftmutSupport.swiftmutMangledNameContainsIdentifierWords(functionName, identifier: identifier)
}

func swiftmutCamelCaseIdentifierWords(_ identifier: String) -> [String] {
  SwiftmutSupport.swiftmutCamelCaseIdentifierWords(identifier)
}

func swiftmutIsASCIIUppercase(_ byte: UInt8) -> Bool {
  SwiftmutSupport.swiftmutIsASCIIUppercase(byte)
}

func swiftmutIsASCIILowercase(_ byte: UInt8) -> Bool {
  SwiftmutSupport.swiftmutIsASCIILowercase(byte)
}

func swiftmutFindNearestPriorImplicitReturnSourceLocation(
  path: String,
  preferredLine: Int,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard mutation.sourceOriginal == "return",
        preferredLine > 1,
        let text = swiftmutRead(path) else {
    return nil
  }

  let firstLine = preferredLine > 8 ? preferredLine - 8 : 1
  var nearest: (line: Int, column: Int, sourceOriginal: String, sourceMutated: String)?
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
    let end = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
    guard start < end,
          !swiftmutLineLooksLikeImplicitReturnContinuation(bytes: bytes, start: start),
          swiftmutImplicitReturnExpressionIsEligible(
            bytes: bytes,
            start: start,
            mutation: mutation,
            allowsInlineBraces: true
          ) else {
      return
    }
    nearest = (
      line,
      start + 1,
      String(decoding: bytes[start..<end], as: UTF8.self),
      swiftmutImplicitReturnSourceMutation(for: mutation))
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
    nearest.sourceOriginal,
    nearest.sourceMutated)
}

func swiftmutFindOrdinalExplicitReturnSourceLocation(
  path: String,
  preferredLine: Int,
  ordinal: Int,
  expectedCount: Int,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard preferredLine > 0,
        ordinal > 0,
        ordinal <= expectedCount,
        expectedCount > 1,
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
          matches.count <= expectedCount else {
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
      if currentLine >= preferredLine {
        inspectLine(lineText, line: currentLine)
        updateBraceDepth(lineText)
        if matches.count > expectedCount {
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
    let lineText = String(text[lineStart..<text.endIndex])
    inspectLine(lineText, line: currentLine)
  }

  guard matches.count == expectedCount else {
    return nil
  }
  let match = matches[ordinal - 1]
  return (
    swiftmutTrimPackageRoot(path, config: config),
    match.line,
    match.column,
    mutation.sourceOriginal,
    mutation.sourceMutated)
}

func swiftmutFindUniqueImplicitReturnSourceLocation(
  path: String,
  preferredLine: Int,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard mutation.sourceOriginal == "return",
        preferredLine > 0,
        let text = swiftmutRead(path) else {
    return nil
  }

  var matches: [(line: Int, column: Int, sourceOriginal: String, sourceMutated: String)] = []
  var currentLine = 1
  var lineStart = text.startIndex
  var index = text.startIndex
  var braceDepth = 0
  var sawOpeningBrace = false
  var sawInvalidTopLevelBodyLine = false

  func recordExpression(_ expression: String, line: Int, column: Int) {
    guard matches.count < 2 else {
      return
    }
    let bytes = Array(expression.utf8)
    let start = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
    guard swiftmutImplicitReturnExpressionIsEligible(
      bytes: bytes,
      start: start,
      mutation: mutation,
      allowsInlineBraces: true
    ) else {
      return
    }
    let trimmedStart = expression.index(expression.startIndex, offsetBy: start)
    let sourceOriginal = String(expression[trimmedStart...])
    matches.append((
      line,
      column + start,
      sourceOriginal,
      swiftmutImplicitReturnSourceMutation(for: mutation)
    ))
  }

  func inspectLine(_ lineText: String, line: Int) {
    guard line >= preferredLine,
          line <= preferredLine + 80,
          matches.count < 2 else {
      return
    }

    let bytes = Array(lineText.utf8)
    let start = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
    let end = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
    guard start < end else {
      return
    }
    if swiftmutLineLooksLikeImplicitReturnContinuation(bytes: bytes, start: start) {
      return
    }

    if line == preferredLine,
       let expression = swiftmutInlineImplicitReturnExpression(lineText) {
      recordExpression(expression.text, line: line, column: expression.column)
      return
    }

    guard sawOpeningBrace,
          braceDepth == 1 else {
      return
    }
    if bytes[start] == 125 {
      return
    }
    guard swiftmutLineLooksLikeImplicitReturnExpression(
      bytes: bytes,
      start: start,
      end: end,
      allowsInlineBraces: true
    ) else {
      sawInvalidTopLevelBodyLine = true
      return
    }
    recordExpression(lineText, line: line, column: 1)
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
        if sawOpeningBrace && braceDepth <= 0 {
          break
        }
        if currentLine >= preferredLine + 80 {
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

  guard !sawInvalidTopLevelBodyLine,
        matches.count == 1,
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

func swiftmutInlineImplicitReturnExpression(_ line: String) -> (text: String, column: Int)? {
  guard let openBrace = line.firstIndex(of: "{"),
        let closeBrace = line.lastIndex(of: "}"),
        openBrace < closeBrace else {
    return nil
  }
  let expressionStart = line.index(after: openBrace)
  let text = String(line[expressionStart..<closeBrace])
  let bytes = Array(text.utf8)
  let start = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
  let end = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  guard start < end else {
    return nil
  }
  return (String(text), line.distance(from: line.startIndex, to: expressionStart) + 1)
}

func swiftmutLineLooksLikeImplicitReturnExpression(
  bytes: [UInt8],
  start: Int,
  end: Int,
  allowsInlineBraces: Bool = false
) -> Bool {
  if bytes[start] == 125 || bytes[start] == 123 || bytes[start] == 47 {
    return false
  }
  let blockedPrefixes = [
    "return ", "let ", "var ", "if ", "if(", "guard ", "guard(",
    "for ", "for(", "while ", "while(", "switch ", "switch(",
    "case ", "default:", "do ", "catch ", "defer ", "throw ",
    "self.", "_ = "
  ]
  for prefix in blockedPrefixes {
    if swiftmutASCIIHasPrefix(bytes, start: start, prefix: prefix) {
      return false
    }
  }
  if swiftmutPropertyDeclarationKeyword(bytes: bytes, start: start, end: end) != nil {
    return false
  }
  if swiftmutLineContainsTopLevelAssignmentOperator(bytes: bytes, start: start, end: end) {
    return false
  }
  for index in start..<end {
    if bytes[index] == 59 {
      return false
    }
    if !allowsInlineBraces && (bytes[index] == 123 || bytes[index] == 125) {
      return false
    }
  }
  if allowsInlineBraces && !swiftmutLineHasBalancedInlineBraces(bytes: bytes, start: start, end: end) {
    return false
  }
  if !allowsInlineBraces && swiftmutASCIIContains(bytes, start: start, end: end, pattern: " in ") {
    return false
  }
  return true
}

func swiftmutLineHasBalancedInlineBraces(bytes: [UInt8], start: Int, end: Int) -> Bool {
  var depth = 0
  var sawBrace = false
  for index in start..<end {
    if bytes[index] == 123 {
      if index == start {
        return false
      }
      depth += 1
      sawBrace = true
    } else if bytes[index] == 125 {
      depth -= 1
      if depth < 0 {
        return false
      }
      sawBrace = true
    }
  }
  return !sawBrace || depth == 0
}

func swiftmutLineLooksLikeImplicitReturnContinuation(bytes: [UInt8], start: Int) -> Bool {
  guard start < bytes.count else {
    return false
  }
  switch bytes[start] {
  case 38, 43, 45, 46, 47, 60, 61, 62, 63, 124:
    return true
  default:
    return false
  }
}

func swiftmutImplicitReturnExpressionIsEligible(
  bytes: [UInt8],
  start: Int,
  mutation: SwiftmutMutation,
  allowsInlineBraces: Bool = false
) -> Bool {
  start < bytes.count
    && swiftmutLineLooksLikeImplicitReturnExpression(
      bytes: bytes,
      start: start,
      end: swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count),
      allowsInlineBraces: allowsInlineBraces
    )
    && swiftmutReturnValueIsEligible(bytes: bytes, start: start, mutation: mutation)
}

func swiftmutInstructionSourceLocation(
  for instruction: Instruction,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  if let fileNameAndPosition = instruction.location.fileNameAndPosition {
    let path = fileNameAndPosition.path.string
    if let matchedPath = swiftmutIncludedSourcePath(path, config: config) {
      return (
        swiftmutTrimPackageRoot(matchedPath, config: config),
        fileNameAndPosition.line,
        fileNameAndPosition.column,
        mutation.sourceOriginal,
        mutation.sourceMutated)
    }
  }

  let location = instruction.parentFunction.location.description
  for path in swiftmutSwiftSourcePaths(config: config) {
    guard location.contains(path),
          let line = swiftmutPreferredLine(in: location, path: path) else {
      continue
    }
    return (
      swiftmutTrimPackageRoot(path, config: config),
      line,
      1,
      mutation.sourceOriginal,
      mutation.sourceMutated)
  }
  return nil
}
