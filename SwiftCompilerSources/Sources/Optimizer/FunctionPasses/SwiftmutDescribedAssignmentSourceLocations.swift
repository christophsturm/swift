//===--- SwiftmutDescribedAssignmentSourceLocations.swift ----------------------------------------------===//
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

func swiftmutFindDescribedAssignmentValueSourceLocation(
  locationDescription: String,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig,
  targetNames: [String]
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard !targetNames.isEmpty,
        let snippetInfo = swiftmutDescribedAssignmentSnippetInfo(
          locationDescription: locationDescription,
          mutation: mutation
        ) else {
    return nil
  }

  var matches: [(path: String, line: Int, column: Int)] = []
  for path in swiftmutSwiftSourcePaths(config: config) {
    for match in swiftmutSourceSnippetMatches(snippetInfo.snippet, path: path) {
      let expressionColumn = match.column + snippetInfo.expressionStart
      guard let lineText = swiftmutAbsoluteSourceLine(path: path, line: match.line),
            swiftmutDescribedAssignmentLineIsMappable(
              lineText,
              expression: snippetInfo.expression,
              expressionColumn: expressionColumn,
              targetNames: targetNames
            ) else {
        continue
      }
      matches.append((path, match.line, expressionColumn))
      if matches.count >= 2 {
        break
      }
    }
    if matches.count >= 2 {
      break
    }
  }

  guard matches.count == 1,
        let match = matches.first else {
    return nil
  }
  return (
    swiftmutTrimPackageRoot(match.path, config: config),
    match.line,
    match.column,
    snippetInfo.expression,
    swiftmutImplicitReturnSourceMutation(for: mutation))
}

func swiftmutFindScopedDescribedAssignmentValueSourceLocation(
  path: String,
  functionLine: Int,
  locationDescription: String,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig,
  targetNames: [String]
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard functionLine > 0,
        !targetNames.isEmpty,
        let snippetInfo = swiftmutDescribedAssignmentSnippetInfo(
          locationDescription: locationDescription,
          mutation: mutation
        ),
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
    guard line >= functionLine,
          matches.count < 2 else {
      return
    }
    for match in swiftmutSourceSnippetMatches(snippetInfo.snippet, in: lineText) {
      let expressionColumn = match.column + snippetInfo.expressionStart
      guard swiftmutDescribedAssignmentLineIsMappable(
        lineText,
        expression: snippetInfo.expression,
        expressionColumn: expressionColumn,
        targetNames: targetNames
      ) else {
        continue
      }
      matches.append((line, expressionColumn))
      if matches.count >= 2 {
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
    snippetInfo.expression,
    swiftmutImplicitReturnSourceMutation(for: mutation))
}

private func swiftmutDescribedAssignmentSnippetInfo(
  locationDescription: String,
  mutation: SwiftmutMutation
) -> (snippet: String, expression: String, expressionStart: Int)? {
  guard let rawSnippet = swiftmutQuotedSourceSearchSnippet(locationDescription),
        rawSnippet.count >= 2 else {
    return nil
  }
  let snippet = swiftmutDecodedSourceSnippet(rawSnippet)
  if let expression = swiftmutStoreLocationAssignedExpression(locationDescription) {
    let bytes = Array(snippet.utf8)
    guard bytes.first == 61 else {
      return nil
    }
    return (snippet, expression, swiftmutSkipHorizontalWhitespace(bytes, from: 1))
  }
  guard let expression = swiftmutDefaultArgumentSnippetExpression(snippet, mutation: mutation) else {
    return nil
  }
  return (snippet, expression, swiftmutSnippetExpressionStartOffset(snippet))
}

func swiftmutDescribedAssignmentLineIsMappable(
  _ line: String,
  expression: String,
  expressionColumn: Int,
  targetNames: [String]
) -> Bool {
  guard swiftmutLineContainsAnyIdentifier(line, identifiers: targetNames) else {
    return false
  }

  let bytes = Array(line.utf8)
  let expressionStart = max(0, min(bytes.count, expressionColumn - 1))
  if expressionStart > 0 {
    for index in 0..<expressionStart where bytes[index] == 61 {
      return true
    }
  }

  if targetNames.contains(expression) {
    return false
  }

  for targetName in targetNames {
    guard let targetRange = swiftmutFindSourceIdentifier(
      targetName,
      in: bytes,
      start: 0,
      end: expressionStart
    ) else {
      continue
    }
    let colonIndex = swiftmutSkipHorizontalWhitespace(bytes, from: targetRange.end)
    if colonIndex < expressionStart && bytes[colonIndex] == 58 {
      return true
    }
  }
  return false
}
