//===--- SwiftmutOrdinalOperatorSourceLocations.swift ----------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2026 swiftmut contributors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

import SIL

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
