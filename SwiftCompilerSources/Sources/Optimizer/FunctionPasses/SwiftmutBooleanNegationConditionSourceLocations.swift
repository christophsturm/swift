//===--- SwiftmutBooleanNegationConditionSourceLocations.swift -----------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2026 swiftmut contributors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

func swiftmutFindBooleanNegatedConditionSourceLocation(
  moduleName: String,
  functionLocation: String,
  locationDescription: String,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard mutation.sourceOriginal == "==",
        mutation.sourceMutated == "!=",
        let snippet = swiftmutQuotedSourceSnippetPrefix(locationDescription),
        let needle = swiftmutBooleanNegatedConditionNeedle(snippet) else {
    return nil
  }

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
    let result = swiftmutFindBooleanNegatedConditionInFunctionBody(
      path: path,
      preferredLine: preferredLine,
      needle: needle,
      mutation: mutation,
      config: config
    ) ?? swiftmutFindBooleanNegatedConditionInFile(
      path: path,
      needle: needle,
      mutation: mutation,
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

func swiftmutBooleanNegatedConditionNeedle(_ snippet: String) -> String? {
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
  guard start < end,
        bytes[start] == 33 else {
    return nil
  }
  start = swiftmutSkipHorizontalWhitespace(bytes, from: start + 1)
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
  guard end - start >= 2 else {
    return nil
  }
  return String(decoding: bytes[start..<end], as: UTF8.self)
}

func swiftmutFindBooleanNegatedConditionInFunctionBody(
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

  var matches: [(line: Int, column: Int, sourceOriginal: String, sourceMutated: String)] = []
  var currentLine = 1
  var lineStart = text.startIndex
  var index = text.startIndex
  var braceDepth = 0
  var sawOpeningBrace = false

  func inspectLine(_ lineText: String, line: Int) {
    guard line >= preferredLine,
          matches.count < 2,
          let expression = swiftmutBooleanNegatedConditionExpression(
            lineText,
            needle: needle,
            mutation: mutation
          ) else {
      return
    }
    matches.append((line, expression.column, expression.sourceOriginal, expression.sourceMutated))
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
    match.sourceMutated)
}

func swiftmutFindBooleanNegatedConditionInFile(
  path: String,
  needle: String,
  mutation: SwiftmutMutation,
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
          let expression = swiftmutBooleanNegatedConditionExpression(
            lineText,
            needle: needle,
            mutation: mutation
          ) else {
      return
    }
    matches.append((line, expression.column, expression.sourceOriginal, expression.sourceMutated))
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

func swiftmutBooleanNegatedConditionExpression(
  _ line: String,
  needle: String,
  mutation: SwiftmutMutation
) -> (column: Int, sourceOriginal: String, sourceMutated: String)? {
  let negatedNeedle = "!" + needle
  guard line.contains(negatedNeedle),
        let expression = swiftmutDescribedGenericConditionExpression(line, needle: needle),
        let sourceMutated = swiftmutBooleanNegatedConditionSourceMutated(
          expression.sourceOriginal,
          needle: needle,
          mutation: mutation
        ) else {
    return nil
  }
  return (expression.column, expression.sourceOriginal, sourceMutated)
}

func swiftmutBooleanNegatedConditionSourceMutated(
  _ sourceOriginal: String,
  needle: String?,
  mutation: SwiftmutMutation
) -> String? {
  guard mutation.sourceOriginal == "==",
        mutation.sourceMutated == "!=" else {
    return nil
  }
  if let needle {
    return swiftmutRemoveFirstBooleanNegation(
      "!" + needle,
      replacement: needle,
      from: sourceOriginal)
  }
  return swiftmutRemoveFirstTopLevelBooleanNegation(from: sourceOriginal)
}

func swiftmutRemoveFirstBooleanNegation(
  _ negatedNeedle: String,
  replacement: String,
  from expression: String
) -> String? {
  let bytes = Array(expression.utf8)
  let needleBytes = Array(negatedNeedle.utf8)
  guard let index = swiftmutFind(needleBytes, in: bytes, startingAt: 0) else {
    return nil
  }
  let prefix = String(decoding: bytes[0..<index], as: UTF8.self)
  let suffix = String(decoding: bytes[(index + needleBytes.count)..<bytes.count], as: UTF8.self)
  return prefix + replacement + suffix
}

func swiftmutRemoveFirstTopLevelBooleanNegation(from expression: String) -> String? {
  let bytes = Array(expression.utf8)
  guard let index = swiftmutFirstTopLevelIndex(bytes, start: 0, end: bytes.count, matches: { index in
    bytes[index] == 33 && (index + 1 >= bytes.count || bytes[index + 1] != 61)
  }) else {
    return nil
  }
  let valueStart = swiftmutSkipHorizontalWhitespace(bytes, from: index + 1)
  let prefix = String(decoding: bytes[0..<index], as: UTF8.self)
  let suffix = String(decoding: bytes[valueStart..<bytes.count], as: UTF8.self)
  return prefix + suffix
}
