//===--- SwiftmutOrdinalConditionSourceLocations.swift -------------------===//
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

func swiftmutFindOrdinalDescribedConditionSourceLocation(
  moduleName: String,
  function: Function,
  branch: CondBranchInst,
  locationDescription: String,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard let snippet = swiftmutQuotedSourceSnippetPrefix(locationDescription),
        let needle = swiftmutDescribedSourceOperatorNeedle(snippet),
        let ordinal = swiftmutDescribedBranchOrdinal(function: function, branch: branch, needle: needle) else {
    return nil
  }

  let displayRules = swiftmutSourceMutationDisplayRules(for: mutation, config: config)
  let preferredPrefix = config.packageRoot + "/Sources/" + moduleName + "/"
  let locatedSourcePaths = swiftmutSwiftSourcePaths(config: config).compactMap { path
    -> (path: String, preferredLine: Int)? in
    guard function.location.description.contains(path),
          let preferredLine = swiftmutPreferredLine(in: function.location.description, path: path) else {
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
    guard let result = swiftmutFindOrdinalDescribedConditionInFunctionBody(
      path: path,
      preferredLine: preferredLine,
      needle: needle,
      ordinal: ordinal.ordinal,
      expectedCount: ordinal.count,
      displayRules: displayRules,
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

func swiftmutDescribedBranchOrdinal(
  function: Function,
  branch: CondBranchInst,
  needle: String
) -> (ordinal: Int, count: Int)? {
  var ordinal = 0
  var count = 0
  for block in function.blocks {
    guard let candidate = block.terminator as? CondBranchInst,
          let snippet = swiftmutQuotedSourceSnippetPrefix(candidate.location.description),
          swiftmutDescribedSourceOperatorNeedle(snippet) == needle else {
      continue
    }
    count += 1
    if candidate === branch {
      ordinal = count
    }
  }
  guard ordinal > 0, count > 1, count <= 16 else {
    return nil
  }
  return (ordinal, count)
}

func swiftmutFindOrdinalDescribedConditionInFunctionBody(
  path: String,
  preferredLine: Int,
  needle: String,
  ordinal: Int,
  expectedCount: Int,
  displayRules: [SwiftmutSourceMutationDisplayRule],
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard preferredLine > 0,
        ordinal > 0,
        expectedCount > 0,
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
          matches.count <= expectedCount,
          lineText.contains(needle),
          let match = swiftmutSingleDescribedConditionMatch(
            lineText,
            needle: needle,
            displayRules: displayRules
          ) else {
      return
    }
    matches.append((line, match.column, match.sourceOriginal, match.sourceMutated))
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

func swiftmutSingleDescribedConditionMatch(
  _ lineText: String,
  needle: String,
  displayRules: [SwiftmutSourceMutationDisplayRule]
) -> (column: Int, sourceOriginal: String, sourceMutated: String)? {
  var lineMatches: [(column: Int, sourceOriginal: String, sourceMutated: String)] = []
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
      lineMatches.append((position.column, position.sourceOriginal, sourceMutated))
    }
  }

  let filtered = lineMatches.filter { $0.sourceOriginal.contains(needle) }
  if filtered.count == 1 {
    return filtered[0]
  }
  if lineMatches.count == 1 {
    return lineMatches[0]
  }
  return nil
}
