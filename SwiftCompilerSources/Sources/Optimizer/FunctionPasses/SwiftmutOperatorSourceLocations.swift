//===--- SwiftmutOperatorSourceLocations.swift ----------------------------------------------===//
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

func swiftmutExclusionReason(
  function: Function,
  config: SwiftmutConfig
) -> String? {
  if swiftmutIsGeneratedInvalidLocationFunction(function) {
    return "generatedInvalidLocation"
  }
  if swiftmutIsGeneratedSpecializationFunctionName(function.name.string) {
    return "generatedSpecialization"
  }
  let location = function.location.description
  for fragment in config.excludePathFragments {
    if location.contains(fragment) {
      return "excludedPath"
    }
  }
  return nil
}

func swiftmutIsGeneratedInvalidLocationFunction(_ function: Function) -> Bool {
  let location = function.location.description
  guard location.contains("<invalid loc>") else {
    return false
  }

  let name = function.name.string
  return name.contains("__derived_")
    || name.contains("CodingKeys")
    || swiftmutIsGeneratedHashValueFunctionName(name)
    || swiftmutIsGeneratedDerivedEnumFunctionName(name)
    || swiftmutIsGeneratedRawRepresentableFunctionName(name)
    || name.hasSuffix("TW")
}

func swiftmutIsGeneratedHashValueFunctionName(_ name: String) -> Bool {
  name.contains("9hashValueSivg")
}

func swiftmutIsGeneratedDerivedEnumFunctionName(_ name: String) -> Bool {
  name.contains("O9hashValueSivg")
    || name.contains("O8allCasesSay")
}

func swiftmutIsGeneratedRawRepresentableFunctionName(_ name: String) -> Bool {
  guard name.contains("O8rawValue") else {
    return false
  }
  return name.hasSuffix("SSvg")
    || name.contains("SgSS_tcfC")
}

func swiftmutIsGeneratedSpecializationFunctionName(_ name: String) -> Bool {
  swiftmutIsMangledFunctionName(name)
    && (name.contains("FTf")
      || name.contains("Tf2")
      || name.contains("Tf3")
      || name.contains("Tf4"))
}

func swiftmutIsMangledFunctionName(_ name: String) -> Bool {
  name.hasPrefix("$s") || name.hasPrefix("@$s")
}

func swiftmutFindSourceOperator(
  moduleName: String,
  functionLocation: String,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard !config.packageRoot.isEmpty else {
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
    guard let text = swiftmutRead(path) else {
      continue
    }
    var bestForPath: (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)?
    for rule in displayRules {
      if let position = swiftmutFindOperator(
        rule.sourceOriginal,
        mutatedOperator: rule.sourceMutated,
        in: text,
        preferredLine: preferredLine,
        maxPreferredLineDistance: 4
      ) {
        guard position.line >= preferredLine else {
          continue
        }
        let sourceMutated = rule.sourceMutatedOverride.isEmpty
          ? position.sourceMutated
          : rule.sourceMutatedOverride
        let result = (
          swiftmutTrimPackageRoot(path, config: config),
          position.line,
          position.column,
          position.sourceOriginal,
          sourceMutated)
        if let existing = bestForPath,
           swiftmutLineDistance(existing.line, preferredLine) <= swiftmutLineDistance(result.1, preferredLine) {
          continue
        }
        bestForPath = result
      }
    }
    if let result = bestForPath {
      if path.hasPrefix(preferredPrefix) {
        return result
      }
      if fallback == nil {
        fallback = result
      }
      continue
    }

    if let result = swiftmutFindUniqueSourceOperatorInFunctionBody(
      path: path,
      preferredLine: preferredLine,
      displayRules: displayRules,
      config: config
    ) {
      if path.hasPrefix(preferredPrefix) {
        return result
      }
      if fallback == nil {
        fallback = result
      }
    }
  }

  return fallback
}

func swiftmutFindUniqueSourceOperatorInFunctionBody(
  path: String,
  preferredLine: Int,
  displayRules: [SwiftmutSourceMutationDisplayRule],
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
          matches.count < 2 else {
      return
    }
    for rule in displayRules {
      guard let position = swiftmutFindOperator(
        rule.sourceOriginal,
        mutatedOperator: rule.sourceMutated,
        in: lineText,
        preferredLine: nil
      ) else {
        continue
      }
      let sourceMutated = rule.sourceMutatedOverride.isEmpty
        ? position.sourceMutated
        : rule.sourceMutatedOverride
      matches.append((line, position.column, position.sourceOriginal, sourceMutated))
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
      if currentLine >= preferredLine {
        inspectLine(lineText, line: currentLine)
        updateBraceDepth(lineText)
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
        let questionIndex = swiftmutTopLevelByteIndex(bytes, start: needleIndex, end: lineEnd, byte: 63) else {
    return nil
  }

  var start = swiftmutTernaryConditionStart(bytes: bytes, before: questionIndex, lineStart: lineStart)
  start = swiftmutSkipHorizontalWhitespace(bytes, from: start)
  let end = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: questionIndex)
  guard start < end,
        swiftmutSourceExpressionIsSingleLineComplete(bytes: bytes, start: start, end: end) else {
    return nil
  }
  return (
    start + 1,
    String(decoding: bytes[start..<end], as: UTF8.self))
}

func swiftmutTernaryConditionStart(
  bytes: [UInt8],
  before questionIndex: Int,
  lineStart: Int
) -> Int {
  var index = questionIndex
  var parenDepth = 0
  var bracketDepth = 0
  var braceDepth = 0
  var quote: UInt8?
  var escaped = false
  while index > lineStart {
    index -= 1
    let byte = bytes[index]
    if let activeQuote = quote {
      if escaped {
        escaped = false
      } else if byte == 92 {
        escaped = true
      } else if byte == activeQuote {
        quote = nil
      }
      continue
    }
    if byte == 34 || byte == 39 {
      quote = byte
      continue
    }
    switch byte {
    case 41:
      parenDepth += 1
    case 40:
      if parenDepth > 0 {
        parenDepth -= 1
      }
    case 93:
      bracketDepth += 1
    case 91:
      if bracketDepth > 0 {
        bracketDepth -= 1
      }
    case 125:
      braceDepth += 1
    case 123:
      if braceDepth > 0 {
        braceDepth -= 1
      }
    case 61:
      if parenDepth == 0 && bracketDepth == 0 && braceDepth == 0 {
        return index + 1
      }
    case 44:
      if parenDepth == 0 && bracketDepth == 0 && braceDepth == 0 {
        return index + 1
      }
    default:
      break
    }
  }
  return lineStart
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

func swiftmutComparisonOrdinalAndCount(
  for comparison: BuiltinInst,
  in function: Function
) -> (ordinal: Int, count: Int)? {
  guard let targetID = swiftmutComparisonBuiltinIDName(comparison) else {
    return nil
  }

  var ordinal = 0
  var count = 0
  for block in function.blocks {
    for instruction in block.instructions {
      guard let candidate = instruction as? BuiltinInst,
            swiftmutComparisonBuiltinIDName(candidate) == targetID else {
        continue
      }
      count += 1
      if candidate === comparison {
        ordinal = count
      }
    }
  }
  guard ordinal > 0 else {
    return nil
  }
  return (ordinal, count)
}

func swiftmutFindOrdinalSourceOperator(
  moduleName: String,
  functionLocation: String,
  ordinal: Int,
  expectedCount: Int,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard ordinal > 0, expectedCount > 0 else {
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
    guard let result = swiftmutFindOrdinalSourceOperatorInFunctionBody(
      path: path,
      preferredLine: preferredLine,
      displayRules: displayRules,
      ordinal: ordinal,
      expectedCount: expectedCount,
      config: config
    ) else {
      continue
    }
    if path.hasPrefix(preferredPrefix) {
      return result
    }
    if fallback == nil {
      fallback = result
    }
  }
  return fallback
}

func swiftmutFindOrdinalSourceOperatorInFunctionBody(
  path: String,
  preferredLine: Int,
  displayRules: [SwiftmutSourceMutationDisplayRule],
  ordinal: Int,
  expectedCount: Int,
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
          matches.count <= expectedCount else {
      return
    }
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
        let duplicate = matches.contains {
          $0.line == line
            && $0.column == position.column
            && $0.sourceOriginal == position.sourceOriginal
            && $0.sourceMutated == sourceMutated
        }
        if !duplicate {
          matches.append((line, position.column, position.sourceOriginal, sourceMutated))
        }
      }
    }
    matches.sort {
      if $0.line != $1.line {
        return $0.line < $1.line
      }
      return $0.column < $1.column
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

  guard matches.count == expectedCount,
        ordinal <= matches.count else {
    return nil
  }
  let match = matches[ordinal - 1]
  return (
    swiftmutTrimPackageRoot(path, config: config),
    match.line,
    match.column,
    match.sourceOriginal,
    match.sourceMutated)
}
