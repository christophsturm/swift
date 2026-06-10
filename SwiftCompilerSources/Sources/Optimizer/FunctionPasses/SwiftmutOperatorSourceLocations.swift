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
  if swiftmutIsGeneratedReabstractionThunk(function) {
    return "generatedReabstractionThunk"
  }
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

func swiftmutIsGeneratedReabstractionThunk(_ function: Function) -> Bool {
  let location = function.location.description
  guard location.contains("<compiler-generated>") else {
    return false
  }
  return function.name.string.hasSuffix("TR")
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
