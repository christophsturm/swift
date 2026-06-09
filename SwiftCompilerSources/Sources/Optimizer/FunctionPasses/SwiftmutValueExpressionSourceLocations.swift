//===--- SwiftmutValueExpressionSourceLocations.swift ----------------------------------------------===//
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

func swiftmutLineColumn(
  ofTarget targetName: String,
  followedBy comparison: (operatorText: String, rhsText: String),
  in line: String
) -> Int? {
  let bytes = Array(line.utf8)
  let targetBytes = Array(targetName.utf8)
  let operatorBytes = Array(comparison.operatorText.utf8)
  let rhsBytes = Array(comparison.rhsText.utf8)
  guard !targetBytes.isEmpty,
        !operatorBytes.isEmpty,
        !rhsBytes.isEmpty,
        bytes.count >= targetBytes.count else {
    return nil
  }

  var index = 0
  while index + targetBytes.count <= bytes.count {
    if swiftmutIdentifierTokenMatches(bytes, index: index, end: bytes.count, tokenBytes: targetBytes) {
      var cursor = swiftmutSkipHorizontalWhitespace(bytes, from: index + targetBytes.count)
      if swiftmutBytesMatch(bytes, start: cursor, pattern: operatorBytes) {
        cursor = swiftmutSkipHorizontalWhitespace(bytes, from: cursor + operatorBytes.count)
        if swiftmutBytesMatch(bytes, start: cursor, pattern: rhsBytes) {
          return index + 1
        }
      }
    }
    index += 1
  }
  return nil
}

func swiftmutIdentifierTokenMatches(
  _ bytes: [UInt8],
  index: Int,
  end: Int,
  tokenBytes: [UInt8]
) -> Bool {
  guard index + tokenBytes.count <= end else {
    return false
  }
  if index > 0 && swiftmutIsIdentifierByte(bytes[index - 1]) {
    return false
  }
  let after = index + tokenBytes.count
  if after < end && swiftmutIsIdentifierByte(bytes[after]) {
    return false
  }
  return swiftmutBytesMatch(bytes, start: index, pattern: tokenBytes)
}

func swiftmutBytesMatch(_ bytes: [UInt8], start: Int, pattern: [UInt8]) -> Bool {
  guard start >= 0,
        start + pattern.count <= bytes.count else {
    return false
  }
  for offset in 0..<pattern.count where bytes[start + offset] != pattern[offset] {
    return false
  }
  return true
}

func swiftmutQuotedSourceSnippetPrefix(_ description: String) -> String? {
  let bytes = Array(description.utf8)
  guard bytes.count > 1,
        bytes[0] == 34 else {
    return nil
  }

  var end = 1
  while end < bytes.count {
    if bytes[end] == 10 || bytes[end] == 13 {
      break
    }
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

func swiftmutFindScalarLiteralSourceLocation(
  path: String,
  preferredLine: Int,
  preferredColumn: Int,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard preferredLine > 0,
        preferredColumn > 0,
        let line = swiftmutAbsoluteSourceLine(path: path, line: preferredLine),
        let token = swiftmutScalarLiteralToken(
          in: line,
          preferredColumn: preferredColumn,
          mutation: mutation
        ) else {
    return nil
  }
  return (
    swiftmutTrimPackageRoot(path, config: config),
    preferredLine,
    token.column,
    token.sourceOriginal,
    swiftmutImplicitReturnSourceMutation(for: mutation))
}

func swiftmutFindDescribedScalarLiteralSourceLocation(
  path: String,
  preferredLine: Int,
  locationDescription: String,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard preferredLine > 0,
        let snippet = swiftmutQuotedSourceSnippetPrefix(locationDescription),
        let text = swiftmutRead(path) else {
    return nil
  }

  var currentLine = 1
  var lineStart = text.startIndex
  var index = text.startIndex
  while index < text.endIndex {
    if text[index] == "\n" {
      if let match = swiftmutScalarLiteralToken(
        in: String(text[lineStart..<index]),
        sourceLine: currentLine,
        preferredLine: preferredLine,
        snippet: snippet,
        mutation: mutation
      ) {
        return (
          swiftmutTrimPackageRoot(path, config: config),
          match.line,
          match.column,
          match.sourceOriginal,
          swiftmutImplicitReturnSourceMutation(for: mutation))
      }
      currentLine += 1
      lineStart = text.index(after: index)
    }
    index = text.index(after: index)
  }

  if index == text.endIndex,
     let match = swiftmutScalarLiteralToken(
       in: String(text[lineStart..<text.endIndex]),
       sourceLine: currentLine,
       preferredLine: preferredLine,
       snippet: snippet,
       mutation: mutation
     ) {
    return (
      swiftmutTrimPackageRoot(path, config: config),
      match.line,
      match.column,
      match.sourceOriginal,
      swiftmutImplicitReturnSourceMutation(for: mutation))
  }
  return nil
}

func swiftmutScalarLiteralToken(
  in lineText: String,
  sourceLine: Int,
  preferredLine: Int,
  snippet: String,
  mutation: SwiftmutMutation
) -> (line: Int, column: Int, sourceOriginal: String)? {
  guard sourceLine >= preferredLine,
        sourceLine <= preferredLine + 120,
        let column = swiftmutColumn(of: snippet, in: lineText) else {
    return nil
  }
  guard let token = swiftmutScalarLiteralToken(
    in: lineText,
    preferredColumn: column,
    mutation: mutation
  ) else {
    return nil
  }
  return (sourceLine, token.column, token.sourceOriginal)
}

func swiftmutColumn(of snippet: String, in line: String) -> Int? {
  let bytes = Array(line.utf8)
  let snippetBytes = Array(snippet.utf8)
  guard !snippetBytes.isEmpty,
        bytes.count >= snippetBytes.count else {
    return nil
  }
  var index = 0
  while index + snippetBytes.count <= bytes.count {
    if swiftmutBytesMatch(bytes, start: index, pattern: snippetBytes) {
      return index + 1
    }
    index += 1
  }
  return nil
}

func swiftmutScalarLiteralToken(
  in line: String,
  preferredColumn: Int,
  mutation: SwiftmutMutation
) -> (column: Int, sourceOriginal: String)? {
  let bytes = Array(line.utf8)
  var start = preferredColumn - 1
  guard start >= 0,
        start < bytes.count else {
    return nil
  }
  start = swiftmutSkipHorizontalWhitespace(bytes, from: start)

  switch mutation.mutatedBuiltinName {
  case "return_false", "return_true":
    return swiftmutBoolLiteralToken(bytes: bytes, start: start, mutation: mutation)
  case "return_zero":
    return swiftmutIntegerLiteralToken(bytes: bytes, start: start, mutation: mutation)
  default:
    return nil
  }
}

func swiftmutBoolLiteralToken(
  bytes: [UInt8],
  start: Int,
  mutation: SwiftmutMutation
) -> (column: Int, sourceOriginal: String)? {
  if mutation.mutatedBuiltinName == "return_false",
     swiftmutIdentifierTokenMatches(bytes, index: start, end: bytes.count, tokenBytes: Array("true".utf8)) {
    return (start + 1, "true")
  }
  if mutation.mutatedBuiltinName == "return_true",
     swiftmutIdentifierTokenMatches(bytes, index: start, end: bytes.count, tokenBytes: Array("false".utf8)) {
    return (start + 1, "false")
  }
  return nil
}

func swiftmutIntegerLiteralToken(
  bytes: [UInt8],
  start: Int,
  mutation: SwiftmutMutation
) -> (column: Int, sourceOriginal: String)? {
  guard start < bytes.count,
        swiftmutIsIntegerLiteralStart(bytes[start]) else {
    return nil
  }

  var end = start + 1
  while end < bytes.count && swiftmutIsIntegerLiteralBody(bytes[end]) {
    end += 1
  }

  guard swiftmutReturnValueIsEligible(bytes: bytes, start: start, mutation: mutation) else {
    return nil
  }
  return (start + 1, String(decoding: bytes[start..<end], as: UTF8.self))
}

func swiftmutIsIntegerLiteralStart(_ byte: UInt8) -> Bool {
  (byte >= 48 && byte <= 57) || byte == 45
}

func swiftmutIsIntegerLiteralBody(_ byte: UInt8) -> Bool {
  (byte >= 48 && byte <= 57) || byte == 95
}

func swiftmutFindValueExpressionSourceLocation(
  for apply: ApplyInst,
  path: String,
  preferredLine: Int,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  if let anchored = swiftmutFindAssignmentValueSourceLocation(
    path: path,
    preferredLine: preferredLine,
    mutation: mutation,
    config: config
  ) {
    return anchored
  }
  if let anchored = swiftmutFindLabeledValueExpressionSourceLocation(
    path: path,
    preferredLine: preferredLine,
    mutation: mutation,
    config: config
  ) {
    return anchored
  }
  if let anchored = swiftmutFindStandaloneValueExpressionSourceLocation(
    path: path,
    preferredLine: preferredLine,
    mutation: mutation,
    config: config
  ) {
    return anchored
  }
  if let anchored = swiftmutFindCalleeOrdinalValueExpressionSourceLocation(
    for: apply,
    path: path,
    preferredLine: preferredLine,
    mutation: mutation,
    config: config
  ) {
    return anchored
  }
  if let anchored = swiftmutFindUniqueExplicitReturnValueExpressionSourceLocation(
    path: path,
    preferredLine: preferredLine,
    mutation: mutation,
    config: config
  ) {
    return anchored
  }
  if let anchored = swiftmutFindUniqueImplicitReturnSourceLocation(
    path: path,
    preferredLine: preferredLine,
    mutation: mutation,
    config: config
  ) {
    return anchored
  }
  return nil
}

func swiftmutFindOrdinalValueExpressionSourceLocation(
  for apply: ApplyInst,
  path: String,
  preferredLine: Int,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard let ordinal = swiftmutValueApplyOrdinalAndCount(
    for: apply,
    mutation: mutation,
    config: config
  ), ordinal.count <= 200 else {
    return nil
  }
  return swiftmutFindOrdinalValueExpressionSourceLocation(
    path: path,
    preferredLine: preferredLine,
    ordinal: ordinal.ordinal,
    expectedCount: ordinal.count,
    mutation: mutation,
    config: config
  )
}

func swiftmutValueApplyOrdinalAndCount(
  for apply: ApplyInst,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (ordinal: Int, count: Int)? {
  var ordinal = 0
  var count = 0
  var foundApply = false

  for block in apply.parentFunction.blocks {
    for instruction in block.instructions {
      guard let candidate = instruction as? ApplyInst,
            !candidate.type.isVoid else {
        continue
      }
      let mutations = swiftmutValueReplacementMutations(
        for: candidate,
        valueType: candidate.type,
        config: config
      )
      guard mutations.contains(where: { $0.mutatedBuiltinName == mutation.mutatedBuiltinName }) else {
        continue
      }
      count += 1
      if candidate === apply {
        ordinal = count
        foundApply = true
      }
    }
  }

  guard foundApply else {
    return nil
  }
  return (ordinal, count)
}

func swiftmutFindOrdinalValueExpressionSourceLocation(
  path: String,
  preferredLine: Int,
  ordinal: Int,
  expectedCount: Int,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig,
  requiresMultipleMatches: Bool = true
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard preferredLine > 0,
        ordinal > 0,
        ordinal <= expectedCount,
        (!requiresMultipleMatches || expectedCount > 1),
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
          let expression = swiftmutOrdinalValueExpression(lineText, mutation: mutation) else {
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
        if sawOpeningBrace && braceDepth > 0 {
          inspectLine(lineText, line: currentLine)
          if matches.count > expectedCount {
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

  if index == text.endIndex && currentLine >= preferredLine && sawOpeningBrace && braceDepth > 0 {
    inspectLine(String(text[lineStart..<text.endIndex]), line: currentLine)
  }

  guard matches.count == expectedCount else {
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

func swiftmutFindCalleeOrdinalValueExpressionSourceLocation(
  for apply: ApplyInst,
  path: String,
  preferredLine: Int,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  let identifiers = swiftmutSourceExpressionIdentifiers(for: apply)
  guard !identifiers.isEmpty,
        let ordinal = swiftmutValueApplyOrdinal(for: apply, matchingAnyOf: identifiers, config: config),
        let text = swiftmutRead(path) else {
    return nil
  }

  let candidates = swiftmutCalleeExpressionSourceCandidates(
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

func swiftmutFindStandaloneValueExpressionSourceLocation(
  path: String,
  preferredLine: Int,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard preferredLine > 0,
        let sourceLine = swiftmutAbsoluteSourceLine(path: path, line: preferredLine),
        let expression = swiftmutStandaloneValueExpression(sourceLine, mutation: mutation) else {
    return nil
  }
  return (
    swiftmutTrimPackageRoot(path, config: config),
    preferredLine,
    expression.column,
    expression.sourceOriginal,
    expression.sourceMutated)
}

func swiftmutFindUniqueExplicitReturnValueExpressionSourceLocation(
  path: String,
  preferredLine: Int,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard preferredLine > 0,
        let text = swiftmutRead(path) else {
    return nil
  }

  if let exactLine = swiftmutAbsoluteSourceLine(path: path, line: preferredLine),
     let expression = swiftmutExplicitReturnValueExpression(exactLine, mutation: mutation) {
    return (
      swiftmutTrimPackageRoot(path, config: config),
      preferredLine,
      expression.column,
      expression.sourceOriginal,
      expression.sourceMutated)
  }

  var matches: [(line: Int, column: Int, sourceOriginal: String, sourceMutated: String)] = []
  var currentLine = 1
  var lineStart = text.startIndex
  var index = text.startIndex
  var braceDepth = 0
  var sawOpeningBrace = false

  func inspectLine(_ lineText: String, line: Int) {
    guard line >= preferredLine,
          line <= preferredLine + 120,
          matches.count < 2,
          let expression = swiftmutExplicitReturnValueExpression(lineText, mutation: mutation) else {
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

func swiftmutValueApplyOrdinal(
  for apply: ApplyInst,
  matchingAnyOf identifiers: [String],
  config: SwiftmutConfig
) -> Int? {
  var ordinal = 0
  for block in apply.parentFunction.blocks {
    for instruction in block.instructions {
      guard let candidate = instruction as? ApplyInst,
            !candidate.type.isVoid,
            !swiftmutValueReplacementMutations(
              for: candidate,
              valueType: candidate.type,
              config: config
            ).isEmpty,
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

func swiftmutCalleeExpressionSourceCandidates(
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
          swiftmutSourceLineContainsExpressionIdentifier(lineText, identifiers: identifiers),
          let expression = swiftmutValueExpressionOnLine(
            lineText,
            identifiers: identifiers,
            mutation: mutation
          ) else {
      return
    }
    candidates.append((
      swiftmutTrimPackageRoot(path, config: config),
      line,
      expression.column,
      expression.sourceOriginal,
      expression.sourceMutated
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

func swiftmutFirstCallLikeSourceIdentifier(
  bytes: [UInt8],
  start: Int,
  end: Int
) -> (start: Int, end: Int)? {
  var index = start
  while index < end {
    guard swiftmutIsASCIIIdentifierStart(bytes[index]) else {
      index += 1
      continue
    }
    let tokenStart = index
    index += 1
    while index < end && swiftmutIsASCIILetterNumberOrUnderscore(bytes[index]) {
      index += 1
    }
    let suffixStart = swiftmutSkipHorizontalWhitespace(bytes, from: index)
    if suffixStart < end && (bytes[suffixStart] == 40 || bytes[suffixStart] == 123) {
      return (tokenStart, index)
    }
  }
  return nil
}

func swiftmutValueExpressionOnLine(
  _ line: String,
  identifiers: [String],
  mutation: SwiftmutMutation
) -> (column: Int, sourceOriginal: String, sourceMutated: String)? {
  if let expression = swiftmutOrdinalValueExpression(line, mutation: mutation) {
    return expression
  }
  if let expression = swiftmutIdentifierValueExpression(line, identifiers: identifiers, mutation: mutation) {
    return expression
  }
  return nil
}

func swiftmutOrdinalValueExpression(
  _ line: String,
  mutation: SwiftmutMutation
) -> (column: Int, sourceOriginal: String, sourceMutated: String)? {
  if let expression = swiftmutAssignmentValueExpression(line, mutation: mutation) {
    return expression
  }
  if let expression = swiftmutStandaloneLabeledValueExpression(line, mutation: mutation) {
    return expression
  }
  if let expression = swiftmutStandaloneValueExpression(line, mutation: mutation) {
    return expression
  }
  if let expression = swiftmutExplicitReturnValueExpression(line, mutation: mutation) {
    return expression
  }
  return nil
}

func swiftmutExplicitReturnValueExpression(
  _ line: String,
  mutation: SwiftmutMutation
) -> (column: Int, sourceOriginal: String, sourceMutated: String)? {
  let bytes = Array(line.utf8)
  let lineStart = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
  let lineEnd = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  guard lineStart < lineEnd,
        swiftmutASCIIHasExactPrefix(bytes, start: lineStart, prefix: "return ") else {
    return nil
  }

  let valueStart = swiftmutSkipHorizontalWhitespace(bytes, from: lineStart + 7)
  guard valueStart < lineEnd,
        swiftmutReturnValueIsEligible(bytes: bytes, start: valueStart, mutation: mutation) else {
    return nil
  }

  let sourceOriginal = String(decoding: bytes[valueStart..<lineEnd], as: UTF8.self)
  return (
    valueStart + 1,
    sourceOriginal,
    swiftmutImplicitReturnSourceMutation(for: mutation))
}
