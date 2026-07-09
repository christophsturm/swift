//===--- SwiftmutDescribedOperatorSourceLocations.swift ----------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2026 swiftmut contributors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

import SwiftmutSupport

func swiftmutFindDescribedSourceOperator(
  moduleName: String,
  functionLocation: String,
  locationDescription: String,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard let snippet = swiftmutQuotedSourceSnippetPrefix(locationDescription),
        let needle = swiftmutDescribedSourceOperatorNeedle(snippet) else {
    return nil
  }

  let displayRules = swiftmutSourceMutationDisplayRules(for: mutation, config: config)
  let preferredPrefix = config.packageRoot + "/Sources/" + moduleName + "/"
  let locatedSourcePaths = swiftmutSwiftSourcePaths(config: config).compactMap { path
    -> (path: String, preferredLine: Int)? in
    guard functionLocation.contains(path),
          let preferredLine = swiftmutPreferredLine(in: functionLocation, path: path) else {
      return nil
    }
    return (path, preferredLine)
  }.sorted { lhs, rhs in
    lhs.path < rhs.path
  }
  guard !locatedSourcePaths.isEmpty else {
    return nil
  }

  var fallback: (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)?
  for (path, preferredLine) in locatedSourcePaths {
    let result = swiftmutFindDescribedSourceOperatorInFunctionBody(
      path: path,
      preferredLine: preferredLine,
      displayRules: displayRules,
      needle: needle,
      config: config
    ) ?? swiftmutFindDescribedSourceOperatorInFile(
      path: path,
      displayRules: displayRules,
      needle: needle,
      config: config
    )
    guard let result else { continue }
    if path.hasPrefix(preferredPrefix) {
      return result
    }
    if fallback == nil {
      fallback = result
    }
  }
  return fallback
}

func swiftmutFindDescribedGenericConditionInFunctionBody(
  path: String,
  preferredLine: Int,
  needle: String,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard preferredLine > 0,
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
    guard line >= preferredLine,
          matches.count < 2,
          let expression = swiftmutDescribedGenericConditionExpression(
            lineText,
            needle: needle
          ) ?? swiftmutGenericConditionClauseExpression(lineText, needle: needle) else {
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
      if currentLine >= preferredLine {
        inspectLine(lineText, line: currentLine)
        updateBraceDepth(lineText)
        if matches.count >= 2 {
          break
        }
        if sawOpeningBrace && braceDepth <= 0 {
          break
        }
        if currentLine >= preferredLine + 300 {
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
    match.sourceOriginal,
    swiftmutBooleanNegatedConditionSourceMutated(
      match.sourceOriginal,
      needle: needle,
      mutation: mutation
    ) ?? swiftmutGenericConditionSourceMutated(
      match.sourceOriginal,
      mutation: mutation,
      config: config))
}

func swiftmutFindDescribedGenericConditionInFile(
  path: String,
  needle: String,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard let text = swiftmutRead(path) else {
    return nil
  }

  var matches: [(line: Int, column: Int, sourceOriginal: String)] = []
  var currentLine = 1
  var lineStart = text.startIndex
  var index = text.startIndex

  func inspectLine(_ lineText: String, line: Int) {
    guard matches.count < 2,
          let expression = swiftmutDescribedGenericConditionExpression(
            lineText,
            needle: needle
          ) else {
      return
    }
    matches.append((line, expression.column, expression.sourceOriginal))
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

  if index == text.endIndex {
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
    swiftmutBooleanNegatedConditionSourceMutated(
      match.sourceOriginal,
      needle: needle,
      mutation: mutation
    ) ?? swiftmutGenericConditionSourceMutated(
      match.sourceOriginal,
      mutation: mutation,
      config: config))
}

func swiftmutFindDescribedSourceOperatorInFile(
  path: String,
  displayRules: [SwiftmutSourceMutationDisplayRule],
  needle: String,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard let text = swiftmutRead(path) else {
    return nil
  }

  var matches: [(line: Int, column: Int, sourceOriginal: String, sourceMutated: String)] = []
  var currentLine = 1
  var lineStart = text.startIndex
  var index = text.startIndex

  func inspectLine(_ lineText: String, line: Int) {
    guard matches.count < 2,
          lineText.contains(needle) else {
      return
    }

    var lineMatches: [(line: Int, column: Int, sourceOriginal: String, sourceMutated: String)] = []
    for rule in displayRules {
      let sourceMutatedOverride = rule.sourceMutatedOverride
      for position in swiftmutFindOperatorMatches(
        rule.sourceOriginal,
        mutatedOperator: rule.sourceMutated,
        in: lineText
      ) {
        let sourceMutated = sourceMutatedOverride.isEmpty
          ? position.sourceMutated
          : sourceMutatedOverride
        lineMatches.append((line, position.column, position.sourceOriginal, sourceMutated))
      }
    }

    let filtered = lineMatches.filter { $0.sourceOriginal.contains(needle) }
    if filtered.count == 1,
       let only = filtered.first {
      matches.append(only)
    } else if lineMatches.count == 1,
              let only = lineMatches.first {
      matches.append(only)
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

  if index == text.endIndex {
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

func swiftmutDescribedSourceOperatorNeedle(_ snippet: String) -> String? {
  if snippet.contains("\n") {
    for line in snippet.split(separator: "\n", omittingEmptySubsequences: false) {
      if let needle = swiftmutSingleLineDescribedSourceOperatorNeedle(String(line)) {
        return needle
      }
      if let needle = swiftmutTruncatedDescribedSourceOperatorNeedle(String(line)) {
        return needle
      }
    }
    return nil
  }
  return swiftmutSingleLineDescribedSourceOperatorNeedle(snippet)
    ?? swiftmutTruncatedDescribedSourceOperatorNeedle(snippet)
}

func swiftmutSingleLineDescribedSourceOperatorNeedle(_ snippet: String) -> String? {
  let bytes = Array(snippet.utf8)
  var start = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
  var end = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  guard start < end else {
    return nil
  }
  if start + 1 < end
      && (bytes[start] == 38 || bytes[start] == 124)
      && bytes[start + 1] == bytes[start] {
    start = swiftmutSkipHorizontalWhitespace(bytes, from: start + 2)
  }
  while end > start {
    let byte = bytes[end - 1]
    if byte == 44 || byte == 123 || byte == 125 {
      end = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: end - 1)
      continue
    }
    break
  }
  guard end - start >= 2 else {
    return nil
  }
  let result = String(decoding: bytes[start..<end], as: UTF8.self)
  return swiftmutSourceOperatorNeedleContainsOperator(result) ? result : nil
}

func swiftmutTruncatedDescribedSourceOperatorNeedle(_ snippet: String) -> String? {
  let bytes = Array(snippet.utf8)
  var start = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
  var end = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  guard start < end else {
    return nil
  }
  if start + 1 < end
      && (bytes[start] == 38 || bytes[start] == 124)
      && bytes[start + 1] == bytes[start] {
    start = swiftmutSkipHorizontalWhitespace(bytes, from: start + 2)
  }
  if start < end && bytes[start] == 33 {
    start = swiftmutSkipHorizontalWhitespace(bytes, from: start + 1)
  }
  while end > start {
    let byte = bytes[end - 1]
    if byte == 44 || byte == 123 || byte == 125 {
      end = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: end - 1)
      continue
    }
    break
  }
  guard end - start >= 8 else {
    return nil
  }
  let result = String(decoding: bytes[start..<end], as: UTF8.self)
  guard !swiftmutSourceOperatorNeedleContainsOperator(result),
        swiftmutTruncatedOperatorNeedleLooksLikeExpressionPrefix(bytes, start: start, end: end) else {
    return nil
  }
  return result
}

func swiftmutTruncatedOperatorNeedleLooksLikeExpressionPrefix(
  _ bytes: [UInt8],
  start: Int,
  end: Int
) -> Bool {
  var hasIdentifier = false
  var hasSelector = false
  for index in start..<end {
    let byte = bytes[index]
    if swiftmutIsIdentifierByte(byte) {
      hasIdentifier = true
    } else if byte == 46 || byte == 91 {
      hasSelector = true
    }
  }
  return hasIdentifier && hasSelector
}

func swiftmutDescribedGenericConditionNeedle(_ snippet: String) -> String? {
  let bytes = Array(snippet.utf8)
  var start = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
  var end = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  guard start < end else {
    return nil
  }
  if start + 1 < end
      && (bytes[start] == 38 || bytes[start] == 124)
      && bytes[start + 1] == bytes[start] {
    start = swiftmutSkipHorizontalWhitespace(bytes, from: start + 2)
  }
  if start < end && bytes[start] == 33 {
    start = swiftmutSkipHorizontalWhitespace(bytes, from: start + 1)
  }
  if let elseIndex = swiftmutTopLevelASCIIIndex(bytes, start: start, end: end, pattern: " else") {
    end = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: elseIndex)
  } else if let elseIndex = swiftmutTopLevelASCIIIndex(bytes, start: start, end: end, pattern: " els") {
    end = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: elseIndex)
  }
  while end > start {
    let byte = bytes[end - 1]
    if byte == 44 || byte == 123 || byte == 125 {
      end = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: end - 1)
      continue
    }
    break
  }
  guard end - start >= 3 else {
    return nil
  }
  return String(decoding: bytes[start..<end], as: UTF8.self)
}

func swiftmutDescribedGenericConditionExpression(
  _ line: String,
  needle: String
) -> (column: Int, sourceOriginal: String)? {
  guard line.contains(needle) else {
    return nil
  }
  if let expression = swiftmutGenericConditionExpression(line) {
    return expression
  }
  return swiftmutTernaryConditionExpression(line, needle: needle)
}

func swiftmutTernaryConditionExpression(
  _ line: String,
  needle: String
) -> (column: Int, sourceOriginal: String)? {
  let bytes = Array(line.utf8)
  let lineStart = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
  let lineEnd = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  let needleBytes = Array(needle.utf8)
  guard lineStart < lineEnd,
        !needleBytes.isEmpty,
        let needleIndex = swiftmutFind(needleBytes, in: bytes, startingAt: lineStart),
        let ternary = swiftmutTopLevelTernaryParts(bytes: bytes, start: lineStart, end: lineEnd),
        needleIndex <= ternary.question else {
    return nil
  }

  var boundary = -1
  if let assignment = ternary.assignmentBeforeQuestion {
    boundary = max(boundary, assignment)
  }
  if let comma = ternary.commaBeforeQuestion {
    boundary = max(boundary, comma)
  }

  var start = boundary >= lineStart ? boundary + 1 : lineStart
  start = swiftmutSkipHorizontalWhitespace(bytes, from: start)
  let end = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: ternary.question)
  guard start < end,
        swiftmutSourceExpressionIsSingleLineComplete(bytes: bytes, start: start, end: end) else {
    return nil
  }
  return (
    start + 1,
    String(decoding: bytes[start..<end], as: UTF8.self))
}

func swiftmutSourceOperatorNeedleContainsOperator(_ needle: String) -> Bool {
  let operators = ["!=", "==", ">=", "<=", ">", "<"]
  let bytes = Array(needle.utf8)
  let start = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
  let end = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  guard start < end else {
    return false
  }
  for operatorText in operators where swiftmutASCIIContains(bytes, start: start, end: end, pattern: operatorText) {
    return true
  }
  return false
}

func swiftmutFindDescribedSourceOperatorInFunctionBody(
  path: String,
  preferredLine: Int,
  displayRules: [SwiftmutSourceMutationDisplayRule],
  needle: String,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard preferredLine > 0,
        let text = swiftmutRead(path) else {
    return nil
  }

  var matches: [(line: Int, column: Int, sourceOriginal: String, sourceMutated: String)] = []
  var currentLine = 1
  var lineStart = text.startIndex
  var index = text.startIndex
  var braceDepth = 0
  var sawOpeningBrace = false

  func inspectLine(_ lineText: String, line: Int) {
    guard line >= preferredLine,
          matches.count < 2,
          lineText.contains(needle) else {
      return
    }

    var lineMatches: [(line: Int, column: Int, sourceOriginal: String, sourceMutated: String)] = []
    for rule in displayRules {
      let sourceMutatedOverride = rule.sourceMutatedOverride
      for position in swiftmutFindOperatorMatches(
        rule.sourceOriginal,
        mutatedOperator: rule.sourceMutated,
        in: lineText
      ) {
        let sourceMutated = sourceMutatedOverride.isEmpty
          ? position.sourceMutated
          : sourceMutatedOverride
        lineMatches.append((line, position.column, position.sourceOriginal, sourceMutated))
      }
    }

    if lineMatches.count == 1,
       let only = lineMatches.first {
      matches.append(only)
      return
    }

    let filtered = lineMatches.filter { $0.sourceOriginal.contains(needle) }
    if filtered.count == 1,
       let only = filtered.first {
      matches.append(only)
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
        if currentLine >= preferredLine + 300 {
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
    match.sourceOriginal,
    match.sourceMutated)
}
