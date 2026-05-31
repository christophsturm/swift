//===--- SwiftmutStatementSourceLocations.swift ----------------------------------------------===//
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

func swiftmutVoidCallSourceLocation(
  for apply: ApplyInst,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> SwiftmutVoidCallSourceLocationResult {
  let functionSourceLocation = swiftmutFunctionSourceLocation(
    for: apply.parentFunction,
    config: config
  )
  if let fileNameAndPosition = apply.location.fileNameAndPosition {
    let path = fileNameAndPosition.path.string
    if let matchedPath = swiftmutIncludedSourcePath(path, config: config) {
      let candidate = (
        swiftmutTrimPackageRoot(matchedPath, config: config),
        fileNameAndPosition.line,
        fileNameAndPosition.column,
        mutation.sourceOriginal,
        mutation.sourceMutated)
      if swiftmutVoidCallSourceLooksLikeStatement(file: candidate.0, line: candidate.1, config: config) {
        return .found(
          file: candidate.0,
          line: candidate.1,
          column: candidate.2,
          sourceOriginal: candidate.3,
          sourceMutated: candidate.4
        )
      }
      if let anchored = swiftmutFindUniqueVoidCallSourceLocation(
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        mutation: mutation,
        config: config
      ) {
        return .found(
          file: anchored.file,
          line: anchored.line,
          column: anchored.column,
          sourceOriginal: anchored.sourceOriginal,
          sourceMutated: anchored.sourceMutated
        )
      }
      if let functionSourceLocation,
         functionSourceLocation.path == matchedPath,
         let anchored = swiftmutFindCalleeOrdinalVoidCallSourceLocation(
           for: apply,
           path: matchedPath,
           preferredLine: functionSourceLocation.line,
           mutation: mutation,
           config: config
         ) {
        return .found(
          file: anchored.file,
          line: anchored.line,
          column: anchored.column,
          sourceOriginal: anchored.sourceOriginal,
          sourceMutated: anchored.sourceMutated
        )
      }
    }
  }

  if let fallback = swiftmutInstructionSourceLocation(
    for: apply,
    mutation: mutation,
    config: config
  ) {
    if swiftmutVoidCallSourceLooksLikeStatement(file: fallback.file, line: fallback.line, config: config) {
      return .found(
        file: fallback.file,
        line: fallback.line,
        column: fallback.column,
        sourceOriginal: fallback.sourceOriginal,
        sourceMutated: fallback.sourceMutated
      )
    }
    let fallbackPath = fallback.file.hasPrefix("/") || config.packageRoot.isEmpty
      ? fallback.file
      : config.packageRoot + "/" + fallback.file
    if let anchored = swiftmutFindUniqueVoidCallSourceLocation(
      path: fallbackPath,
      preferredLine: fallback.line,
      mutation: mutation,
      config: config
    ) {
      return .found(
        file: anchored.file,
        line: anchored.line,
        column: anchored.column,
        sourceOriginal: anchored.sourceOriginal,
        sourceMutated: anchored.sourceMutated
      )
    }
    if let functionSourceLocation,
       functionSourceLocation.path == fallbackPath,
       let anchored = swiftmutFindCalleeOrdinalVoidCallSourceLocation(
         for: apply,
         path: fallbackPath,
         preferredLine: functionSourceLocation.line,
         mutation: mutation,
         config: config
       ) {
      return .found(
        file: anchored.file,
        line: anchored.line,
        column: anchored.column,
        sourceOriginal: anchored.sourceOriginal,
        sourceMutated: anchored.sourceMutated
      )
    }
    return .nonStatement
  }

  if let functionSourceLocation,
     let anchored = swiftmutFindCalleeOrdinalVoidCallSourceLocation(
       for: apply,
       path: functionSourceLocation.path,
       preferredLine: functionSourceLocation.line,
       mutation: mutation,
       config: config
     ) {
    return .found(
      file: anchored.file,
      line: anchored.line,
      column: anchored.column,
      sourceOriginal: anchored.sourceOriginal,
      sourceMutated: anchored.sourceMutated
    )
  }

  return .missing
}

func swiftmutFindCalleeOrdinalVoidCallSourceLocation(
  for apply: ApplyInst,
  path: String,
  preferredLine: Int,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  let identifiers = swiftmutSourceExpressionIdentifiers(for: apply)
  guard !identifiers.isEmpty,
        let ordinal = swiftmutVoidCallOrdinal(for: apply, matchingAnyOf: identifiers, config: config),
        let text = swiftmutRead(path) else {
    return nil
  }

  let candidates = swiftmutCalleeVoidCallSourceCandidates(
    in: text,
    path: path,
    preferredLine: preferredLine,
    identifiers: identifiers,
    mutation: mutation,
    config: config
  )
  guard ordinal > 0,
        ordinal <= candidates.count else {
    return nil
  }
  return candidates[ordinal - 1]
}

func swiftmutVoidCallOrdinal(
  for apply: ApplyInst,
  matchingAnyOf identifiers: [String],
  config: SwiftmutConfig
) -> Int? {
  var ordinal = 0
  for block in apply.parentFunction.blocks {
    for instruction in block.instructions {
      guard let candidate = instruction as? ApplyInst,
            candidate.type.isVoid,
            swiftmutVoidCallMutation(for: candidate, config: config) != nil,
            swiftmutSourceCalleeIdentifiers(for: candidate).contains(where: { identifiers.contains($0) }) else {
        continue
      }
      ordinal += 1
      if candidate === apply {
        return ordinal
      }
    }
  }
  return nil
}

func swiftmutCalleeVoidCallSourceCandidates(
  in text: String,
  path: String,
  preferredLine: Int,
  identifiers: [String],
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> [(file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)] {
  guard preferredLine > 0 else {
    return []
  }
  let lastLine = preferredLine + 220
  var candidates: [(file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)] = []
  var currentLine = 1
  var lineStart = text.startIndex
  var index = text.startIndex

  func inspectLine(_ lineText: String, line: Int) {
    guard line >= preferredLine,
          line <= lastLine,
          swiftmutSourceLineLooksLikeVoidCallStatement(lineText),
          swiftmutSourceLineContainsExpressionIdentifier(lineText, identifiers: identifiers) else {
      return
    }
    let bytes = Array(lineText.utf8)
    let start = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
    candidates.append((
      swiftmutTrimPackageRoot(path, config: config),
      line,
      start + 1,
      mutation.sourceOriginal,
      mutation.sourceMutated
    ))
  }

  while index < text.endIndex {
    if text[index] == "\n" {
      inspectLine(String(text[lineStart..<index]), line: currentLine)
      if currentLine >= lastLine {
        break
      }
      currentLine += 1
      lineStart = text.index(after: index)
    }
    index = text.index(after: index)
  }

  if index == text.endIndex && currentLine <= lastLine {
    inspectLine(String(text[lineStart..<text.endIndex]), line: currentLine)
  }
  return candidates
}

func swiftmutFindUniqueVoidCallSourceLocation(
  path: String,
  preferredLine: Int,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard preferredLine > 0,
        let text = swiftmutRead(path) else {
    return nil
  }

  let firstLine = preferredLine > 8 ? preferredLine - 8 : 1
  let lastLine = preferredLine + 40
  var matches: [(line: Int, column: Int)] = []
  var currentLine = 1
  var lineStart = text.startIndex
  var index = text.startIndex

  func inspectLine(_ lineText: String, line: Int) {
    guard line >= firstLine,
          line <= lastLine,
          matches.count < 2,
          swiftmutSourceLineLooksLikeVoidCallStatement(lineText) else {
      return
    }
    let bytes = Array(lineText.utf8)
    let start = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
    matches.append((line, start + 1))
  }

  while index < text.endIndex {
    if text[index] == "\n" {
      let lineText = String(text[lineStart..<index])
      inspectLine(lineText, line: currentLine)
      if currentLine >= lastLine || matches.count >= 2 {
        break
      }
      currentLine += 1
      lineStart = text.index(after: index)
    }
    index = text.index(after: index)
  }

  if index == text.endIndex && currentLine <= lastLine {
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

func swiftmutBranchSourceLocation(
  for branch: CondBranchInst,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  if let fileNameAndPosition = branch.location.fileNameAndPosition {
    let path = fileNameAndPosition.path.string
    if let matchedPath = swiftmutIncludedSourcePath(path, config: config) {
      if let sourceLocation = swiftmutGenericConditionSourceLocation(
        path: matchedPath,
        line: fileNameAndPosition.line,
        fallbackColumn: fileNameAndPosition.column,
        mutation: mutation,
        config: config
      ) {
        return sourceLocation
      }
      return (
        swiftmutTrimPackageRoot(matchedPath, config: config),
        fileNameAndPosition.line,
        fileNameAndPosition.column,
        mutation.sourceOriginal,
        mutation.sourceMutated)
    }
  }

  let location = branch.parentFunction.location.description
  for path in swiftmutSwiftSourcePaths(config: config) {
    guard location.contains(path),
          let line = swiftmutPreferredLine(in: location, path: path) else {
      continue
    }
    if let anchored = swiftmutFindUniqueExplicitConditionSourceLocation(
      path: path,
      preferredLine: line,
      mutation: mutation,
      config: config
    ) {
      return anchored
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

func swiftmutFindUniqueExplicitConditionSourceLocation(
  path: String,
  preferredLine: Int,
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
          line <= preferredLine + 120,
          matches.count < 2,
          let expression = swiftmutGenericConditionExpression(lineText) else {
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
    match.sourceOriginal,
    mutation.sourceMutated)
}

