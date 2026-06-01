//===--- SwiftmutDescribedValueSourceLocations.swift ----------------------------------------------===//
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

func swiftmutFindDescribedValueExpressionSourceLocation(
  for apply: ApplyInst,
  path: String,
  functionLine: Int,
  locationDescription: String,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard functionLine > 0,
        let snippet = swiftmutQuotedSourceSnippetPrefix(locationDescription),
        swiftmutDescribedValueSnippetLooksMappable(snippet),
        let text = swiftmutRead(path) else {
    return nil
  }

  let prefixes = swiftmutDescribedValueSnippetPrefixes(snippet)
  guard !prefixes.isEmpty else {
    return nil
  }

  let identifiers = swiftmutSourceExpressionIdentifiers(for: apply)
  let ordinal = swiftmutDescribedApplySnippetOrdinalAndCount(
    for: apply,
    snippet: snippet,
    mutation: mutation,
    config: config
  )
  var matches: [(line: Int, column: Int, sourceOriginal: String, sourceMutated: String)] = []
  var currentLine = 1
  var lineStart = text.startIndex
  var index = text.startIndex
  var braceDepth = 0
  var sawOpeningBrace = false

  func inspectLine(_ lineText: String, line: Int) {
    guard line >= functionLine,
          matches.count < swiftmutDescribedMatchLimit(for: ordinal) else {
      return
    }
    let bytes = Array(lineText.utf8)
    let start = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
    let end = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
    guard start < end else {
      return
    }

    for prefix in prefixes {
      guard let matchStart = swiftmutASCIIIndex(bytes, start: start, end: end, pattern: prefix),
            let expression = swiftmutDescribedValueExpression(
              bytes: bytes,
              matchStart: matchStart,
              lineEnd: end,
              identifiers: identifiers,
              mutation: mutation,
              allowsInfix: true
            ) else {
        continue
      }
      matches.append((line, expression.column, expression.sourceOriginal, expression.sourceMutated))
      return
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
          if matches.count >= swiftmutDescribedMatchLimit(for: ordinal) {
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

  let selected = swiftmutSelectedDescribedMatch(matches: matches, ordinal: ordinal)
  guard let match = selected else {
    return nil
  }
  return (
    swiftmutTrimPackageRoot(path, config: config),
    match.line,
    match.column,
    match.sourceOriginal,
    match.sourceMutated)
}

func swiftmutDescribedApplySnippetOrdinalAndCount(
  for apply: ApplyInst,
  snippet: String,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (ordinal: Int, count: Int)? {
  var ordinal = 0
  var count = 0
  var foundApply = false

  for block in apply.parentFunction.blocks {
    for instruction in block.instructions {
      guard let candidate = instruction as? ApplyInst,
            !candidate.type.isVoid,
            swiftmutQuotedSourceSnippetPrefix(candidate.location.description) == snippet else {
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

  guard foundApply,
        count > 1,
        count <= 20 else {
    return nil
  }
  return (ordinal, count)
}

func swiftmutDescribedMatchLimit(for ordinal: (ordinal: Int, count: Int)?) -> Int {
  if let ordinal {
    return ordinal.count + 1
  }
  return 2
}

func swiftmutSelectedDescribedMatch(
  matches: [(line: Int, column: Int, sourceOriginal: String, sourceMutated: String)],
  ordinal: (ordinal: Int, count: Int)?
) -> (line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  if matches.count == 1 {
    return matches.first
  }
  guard let ordinal,
        matches.count == ordinal.count,
        ordinal.ordinal > 0,
        ordinal.ordinal <= matches.count else {
    return nil
  }
  return matches[ordinal.ordinal - 1]
}

func swiftmutFindUniqueDescribedValueExpressionSourceLocation(
  for apply: ApplyInst,
  path: String,
  locationDescription: String,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard let snippet = swiftmutQuotedSourceSnippetPrefix(locationDescription),
        swiftmutDescribedValueSnippetLooksMappable(snippet),
        let text = swiftmutRead(path) else {
    return nil
  }

  let prefixes = swiftmutDescribedValueSnippetPrefixes(snippet)
  guard !prefixes.isEmpty else {
    return nil
  }

  let identifiers = swiftmutSourceExpressionIdentifiers(for: apply)
  var matches: [(line: Int, column: Int, sourceOriginal: String, sourceMutated: String)] = []
  var currentLine = 1
  var lineStart = text.startIndex
  var index = text.startIndex

  func inspectLine(_ lineText: String, line: Int) {
    guard matches.count < 2 else {
      return
    }
    let bytes = Array(lineText.utf8)
    let start = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
    let end = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
    guard start < end else {
      return
    }

    for prefix in prefixes {
      guard let matchStart = swiftmutASCIIIndex(bytes, start: start, end: end, pattern: prefix),
            let expression = swiftmutDescribedValueExpression(
              bytes: bytes,
              matchStart: matchStart,
              lineEnd: end,
              identifiers: identifiers,
              mutation: mutation,
              allowsInfix: false
            ) else {
        continue
      }
      matches.append((line, expression.column, expression.sourceOriginal, expression.sourceMutated))
      return
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

  if index == text.endIndex && matches.count < 2 {
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

func swiftmutDescribedValueSnippetLooksMappable(_ snippet: String) -> Bool {
  let bytes = Array(snippet.utf8)
  let start = swiftmutDescribedValuePayloadStart(bytes: bytes, start: 0, end: bytes.count)
  guard start < bytes.count else {
    return false
  }
  if swiftmutDescribedSnippetStartsWithOperator(bytes: bytes, start: start, end: bytes.count) {
    return true
  }
  guard start < bytes.count,
        !swiftmutASCIIHasExactPrefix(bytes, start: start, prefix: "()") else {
    return false
  }
  let first = bytes[start]
  return (first >= 65 && first <= 90) || (first >= 97 && first <= 122) || first == 95
}

func swiftmutDescribedValueSnippetPrefixes(_ snippet: String) -> [String] {
  let bytes = Array(snippet.utf8)
  let start = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
  let end = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  guard start < end else {
    return []
  }

  var prefixes: [String] = []
  func appendPrefix(start: Int) {
    let trimmedStart = swiftmutSkipHorizontalWhitespace(bytes, from: start)
    guard trimmedStart < end,
          end - trimmedStart >= 5 else {
      return
    }
    let prefix = String(decoding: bytes[trimmedStart..<end], as: UTF8.self)
    if !prefixes.contains(prefix) {
      prefixes.append(prefix)
    }
  }

  appendPrefix(start: start)
  if start + 1 < end
      && (bytes[start] == 38 || bytes[start] == 124)
      && bytes[start + 1] == bytes[start] {
    appendPrefix(start: start + 2)
  }
  if start < end && bytes[start] == 33 {
    appendPrefix(start: start + 1)
  }
  return prefixes
}

func swiftmutDescribedValueExpression(
  bytes: [UInt8],
  matchStart: Int,
  lineEnd: Int,
  identifiers: [String],
  mutation: SwiftmutMutation,
  allowsInfix: Bool
) -> (column: Int, sourceOriginal: String, sourceMutated: String)? {
  let expressionSearchStart = swiftmutDescribedValueExpressionSearchStart(
    bytes: bytes,
    matchStart: matchStart,
    lineEnd: lineEnd
  )

  if let expression = swiftmutDescribedOperatorValueExpression(
    bytes: bytes,
    matchStart: matchStart,
    lineEnd: lineEnd,
    mutation: mutation
  ) {
    return expression
  }
  if let expression = swiftmutDescribedOptionalBindingValueExpression(
    bytes: bytes,
    matchStart: matchStart,
    lineEnd: lineEnd,
    mutation: mutation
  ) {
    return expression
  }
  if let expression = swiftmutDescribedCatchPatternValueExpression(
    bytes: bytes,
    matchStart: matchStart,
    lineEnd: lineEnd,
    mutation: mutation
  ) {
    return expression
  }
  if allowsInfix,
     let expression = swiftmutDescribedInfixValueExpression(
    bytes: bytes,
    matchStart: matchStart,
    lineEnd: lineEnd,
    mutation: mutation
  ) {
    return expression
  }

  for identifier in identifiers {
    guard let tokenRange = swiftmutFindSourceIdentifier(
      identifier,
      in: bytes,
      start: expressionSearchStart,
      end: lineEnd
    ),
    let expressionRange = swiftmutSourceExpressionRange(
      around: tokenRange,
      in: bytes,
      lineEnd: lineEnd
    ),
    swiftmutReturnValueIsEligible(bytes: bytes, start: expressionRange.start, mutation: mutation) else {
      continue
    }
    return swiftmutDescribedValueExpressionResult(
      bytes: bytes,
      expressionRange: expressionRange,
      mutation: mutation
    )
  }

  if let expression = swiftmutDescribedIdentifierValueExpression(
    bytes: bytes,
    matchStart: matchStart,
    lineEnd: lineEnd,
    mutation: mutation
  ) {
    return expression
  }

  guard let tokenRange = swiftmutFirstCallLikeSourceIdentifier(
    bytes: bytes,
    start: expressionSearchStart,
    end: lineEnd
  ),
  let expressionRange = swiftmutSourceExpressionRange(
    around: tokenRange,
    in: bytes,
    lineEnd: lineEnd
  ),
  swiftmutReturnValueIsEligible(bytes: bytes, start: expressionRange.start, mutation: mutation) else {
    return nil
  }
  return swiftmutDescribedValueExpressionResult(
    bytes: bytes,
    expressionRange: expressionRange,
    mutation: mutation
  )
}

func swiftmutDescribedIdentifierValueExpression(
  bytes: [UInt8],
  matchStart: Int,
  lineEnd: Int,
  mutation: SwiftmutMutation
) -> (column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard matchStart < lineEnd,
        swiftmutIsASCIIIdentifierStart(bytes[matchStart]) else {
    return nil
  }

  var tokenEnd = matchStart + 1
  while tokenEnd < lineEnd && swiftmutIsASCIILetterNumberOrUnderscore(bytes[tokenEnd]) {
    tokenEnd += 1
  }
  if tokenEnd < lineEnd && !swiftmutIsDescribedIdentifierTerminator(bytes[tokenEnd]) {
    return nil
  }
  guard matchStart == 0 || !swiftmutIsASCIILetterNumberOrUnderscore(bytes[matchStart - 1]),
        let expressionRange = swiftmutSourceExpressionRange(
          around: (matchStart, tokenEnd),
          in: bytes,
          lineEnd: lineEnd
        ),
        swiftmutReturnValueIsEligible(bytes: bytes, start: expressionRange.start, mutation: mutation) else {
    return nil
  }
  return swiftmutDescribedValueExpressionResult(
    bytes: bytes,
    expressionRange: expressionRange,
    mutation: mutation
  )
}

func swiftmutIsDescribedIdentifierTerminator(_ byte: UInt8) -> Bool {
  swiftmutIsHorizontalWhitespace(byte)
    || byte == 41
    || byte == 44
    || byte == 93
    || byte == 123
}

func swiftmutDescribedOptionalBindingValueExpression(
  bytes: [UInt8],
  matchStart: Int,
  lineEnd: Int,
  mutation: SwiftmutMutation
) -> (column: Int, sourceOriginal: String, sourceMutated: String)? {
  let lineStart = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
  guard swiftmutDescribedLineStartsWithOptionalBinding(bytes: bytes, lineStart: lineStart) else {
    return nil
  }
  guard let equals = swiftmutLastTopLevelEqualsBefore(
    bytes: bytes,
    start: lineStart,
    end: matchStart
  ), equals < matchStart else {
    return nil
  }

  var expressionStart = matchStart
  while expressionStart > equals + 1 && swiftmutIsSourceExpressionPrefixByte(bytes[expressionStart - 1]) {
    expressionStart -= 1
  }
  expressionStart = swiftmutSkipHorizontalWhitespace(bytes, from: expressionStart)

  var expressionEnd = matchStart
  while expressionEnd < lineEnd {
    let byte = bytes[expressionEnd]
    if swiftmutIsHorizontalWhitespace(byte) || byte == 123 || byte == 44 {
      break
    }
    expressionEnd += 1
  }

  guard expressionStart < expressionEnd,
        swiftmutReturnValueIsEligible(bytes: bytes, start: expressionStart, mutation: mutation) else {
    return nil
  }

  let sourceOriginal = String(decoding: bytes[expressionStart..<expressionEnd], as: UTF8.self)
  return (
    expressionStart + 1,
    sourceOriginal,
    swiftmutImplicitReturnSourceMutation(for: mutation))
}

func swiftmutDescribedLineStartsWithOptionalBinding(bytes: [UInt8], lineStart: Int) -> Bool {
  if swiftmutASCIIHasExactPrefix(bytes, start: lineStart, prefix: "if let ") {
    return true
  }
  if swiftmutASCIIHasExactPrefix(bytes, start: lineStart, prefix: "if var ") {
    return true
  }
  if swiftmutASCIIHasExactPrefix(bytes, start: lineStart, prefix: "guard let ") {
    return true
  }
  if swiftmutASCIIHasExactPrefix(bytes, start: lineStart, prefix: "guard var ") {
    return true
  }
  return false
}

func swiftmutLastTopLevelEqualsBefore(bytes: [UInt8], start: Int, end: Int) -> Int? {
  var index = start
  var parenDepth = 0
  var bracketDepth = 0
  var quote: UInt8?
  var escaped = false
  var lastEquals: Int?
  while index < end {
    let byte = bytes[index]
    if let activeQuote = quote {
      if escaped {
        escaped = false
      } else if byte == 92 {
        escaped = true
      } else if byte == activeQuote {
        quote = nil
      }
    } else if byte == 34 || byte == 39 {
      quote = byte
    } else if byte == 40 {
      parenDepth += 1
    } else if byte == 41 {
      parenDepth -= 1
    } else if byte == 91 {
      bracketDepth += 1
    } else if byte == 93 {
      bracketDepth -= 1
    } else if byte == 61 && parenDepth == 0 && bracketDepth == 0 {
      lastEquals = index
    }
    index += 1
  }
  return lastEquals
}

func swiftmutDescribedCatchPatternValueExpression(
  bytes: [UInt8],
  matchStart: Int,
  lineEnd: Int,
  mutation: SwiftmutMutation
) -> (column: Int, sourceOriginal: String, sourceMutated: String)? {
  let lineStart = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
  guard swiftmutDescribedLineHasCatchBeforeExpression(
    bytes: bytes,
    lineStart: lineStart,
    expressionStart: matchStart
  ) else {
    return nil
  }

  var expressionStart = matchStart
  while expressionStart > lineStart && swiftmutIsSourceExpressionPrefixByte(bytes[expressionStart - 1]) {
    expressionStart -= 1
  }
  var expressionEnd = matchStart
  while expressionEnd < lineEnd {
    let byte = bytes[expressionEnd]
    if swiftmutIsHorizontalWhitespace(byte) || byte == 123 || byte == 44 {
      break
    }
    expressionEnd += 1
  }
  guard expressionStart < expressionEnd,
        swiftmutReturnValueIsEligible(bytes: bytes, start: expressionStart, mutation: mutation) else {
    return nil
  }

  let sourceOriginal = String(decoding: bytes[expressionStart..<expressionEnd], as: UTF8.self)
  return (
    expressionStart + 1,
    sourceOriginal,
    swiftmutImplicitReturnSourceMutation(for: mutation))
}

func swiftmutDescribedLineHasCatchBeforeExpression(
  bytes: [UInt8],
  lineStart: Int,
  expressionStart: Int
) -> Bool {
  guard lineStart < expressionStart else {
    return false
  }
  if swiftmutASCIIHasExactPrefix(bytes, start: lineStart, prefix: "catch ") {
    return true
  }
  if swiftmutASCIIHasExactPrefix(bytes, start: lineStart, prefix: "} catch ") {
    return true
  }
  return false
}

func swiftmutDescribedInfixValueExpression(
  bytes: [UInt8],
  matchStart: Int,
  lineEnd: Int,
  mutation: SwiftmutMutation
) -> (column: Int, sourceOriginal: String, sourceMutated: String)? {
  let expressionStart = swiftmutDescribedValuePayloadStart(
    bytes: bytes,
    start: matchStart,
    end: lineEnd
  )
  guard expressionStart < lineEnd,
        !swiftmutDescribedSnippetStartsWithOperator(bytes: bytes, start: expressionStart, end: lineEnd),
        let comparison = swiftmutFirstDescribedInfixComparison(
          bytes: bytes,
          start: expressionStart,
          end: lineEnd
        ) else {
    return nil
  }

  let expressionEnd = swiftmutTrimTrailingElseKeyword(
    bytes: bytes,
    end: swiftmutDescribedInfixExpressionEnd(
      bytes: bytes,
      start: comparison.end,
      lineEnd: lineEnd
    )
  )
  guard expressionStart < comparison.start,
        comparison.end < expressionEnd,
        swiftmutReturnValueIsEligible(bytes: bytes, start: expressionStart, mutation: mutation) else {
    return nil
  }

  let sourceOriginal = String(decoding: bytes[expressionStart..<expressionEnd], as: UTF8.self)
  return (
    expressionStart + 1,
    sourceOriginal,
    swiftmutImplicitReturnSourceMutation(for: mutation))
}

func swiftmutFirstDescribedInfixComparison(
  bytes: [UInt8],
  start: Int,
  end: Int
) -> (start: Int, end: Int)? {
  guard let index = swiftmutFirstTopLevelIndex(bytes, start: start, end: end, matches: { index in
    guard index + 1 < end else {
      return false
    }
    if bytes[index] == 61 && bytes[index + 1] == 61 {
      return true
    }
    return bytes[index] == 33 && bytes[index + 1] == 61
  }) else {
    return nil
  }
  return (index, index + 2)
}

func swiftmutDescribedInfixExpressionEnd(bytes: [UInt8], start: Int, lineEnd: Int) -> Int {
  var index = start
  var parenDepth = 0
  var bracketDepth = 0
  var quote: UInt8?
  var escaped = false

  while index < lineEnd {
    let byte = bytes[index]
    if let activeQuote = quote {
      if escaped {
        escaped = false
      } else if byte == 92 {
        escaped = true
      } else if byte == activeQuote {
        quote = nil
      }
      index += 1
      continue
    }
    if byte == 34 || byte == 39 {
      quote = byte
    } else if byte == 40 {
      parenDepth += 1
    } else if byte == 41 {
      if parenDepth == 0 {
        break
      }
      parenDepth -= 1
    } else if byte == 91 {
      bracketDepth += 1
    } else if byte == 93 {
      if bracketDepth == 0 {
        break
      }
      bracketDepth -= 1
    } else if parenDepth == 0 && bracketDepth == 0 {
      if byte == 123 || byte == 125 || byte == 44 {
        break
      }
      if index + 1 < lineEnd,
         (byte == 38 || byte == 124),
         bytes[index + 1] == byte {
        break
      }
    }
    index += 1
  }
  return swiftmutTrimTrailingHorizontalWhitespace(bytes, end: index)
}

func swiftmutTrimTrailingElseKeyword(bytes: [UInt8], end: Int) -> Int {
  let trimmedEnd = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: end)
  guard trimmedEnd >= 5,
        bytes[trimmedEnd - 4] == 101,
        bytes[trimmedEnd - 3] == 108,
        bytes[trimmedEnd - 2] == 115,
        bytes[trimmedEnd - 1] == 101,
        swiftmutIsHorizontalWhitespace(bytes[trimmedEnd - 5]) else {
    return trimmedEnd
  }
  return swiftmutTrimTrailingHorizontalWhitespace(bytes, end: trimmedEnd - 4)
}

func swiftmutDescribedOperatorValueExpression(
  bytes: [UInt8],
  matchStart: Int,
  lineEnd: Int,
  mutation: SwiftmutMutation
) -> (column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard swiftmutDescribedSnippetStartsWithOperator(bytes: bytes, start: matchStart, end: lineEnd) else {
    return nil
  }
  let lhsEnd = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: matchStart)
  guard lhsEnd > 0 else {
    return nil
  }

  let expressionStart = swiftmutDescribedOperatorExpressionStart(bytes: bytes, lhsEnd: lhsEnd)

  guard expressionStart < lhsEnd,
        swiftmutReturnValueIsEligible(bytes: bytes, start: expressionStart, mutation: mutation) else {
    return nil
  }

  let expressionEnd = swiftmutDescribedOperatorExpressionEnd(
    bytes: bytes,
    start: matchStart,
    lineEnd: lineEnd
  )
  guard expressionEnd > matchStart,
        !swiftmutDescribedSnippetStartsWithOperator(bytes: bytes, start: expressionStart, end: expressionEnd) else {
    return nil
  }

  let sourceOriginal = String(decoding: bytes[expressionStart..<expressionEnd], as: UTF8.self)
  return (
    expressionStart + 1,
    sourceOriginal,
    swiftmutImplicitReturnSourceMutation(for: mutation))
}

func swiftmutDescribedOperatorExpressionStart(bytes: [UInt8], lhsEnd: Int) -> Int {
  var expressionStart = lhsEnd
  while expressionStart > 0 {
    let previous = bytes[expressionStart - 1]
    if previous == 41,
       let open = swiftmutMatchingOpenDelimiterBefore(
         in: bytes,
         closeIndex: expressionStart - 1,
         open: 40,
         close: 41
       ) {
      expressionStart = open
      continue
    }
    if previous == 93,
       let open = swiftmutMatchingOpenDelimiterBefore(
         in: bytes,
         closeIndex: expressionStart - 1,
         open: 91,
         close: 93
       ) {
      expressionStart = open
      continue
    }
    if swiftmutIsSourceExpressionPrefixByte(previous) {
      expressionStart -= 1
      continue
    }
    if previous == 123 || previous == 40 || previous == 91 || previous == 44 || previous == 61 {
      break
    }
    break
  }
  return swiftmutSkipHorizontalWhitespace(bytes, from: expressionStart)
}

func swiftmutDescribedSnippetStartsWithOperator(bytes: [UInt8], start: Int, end: Int) -> Bool {
  let index = swiftmutSkipHorizontalWhitespace(bytes, from: start)
  guard index + 1 < end else {
    return false
  }
  if bytes[index] == 61 && bytes[index + 1] == 61 {
    return true
  }
  if bytes[index] == 33 && bytes[index + 1] == 61 {
    return true
  }
  return bytes[index] == 60 || bytes[index] == 62
}

func swiftmutDescribedOperatorExpressionEnd(
  bytes: [UInt8],
  start: Int,
  lineEnd: Int
) -> Int {
  var index = start
  var parenDepth = 0
  var bracketDepth = 0
  var inString = false
  while index < lineEnd {
    let byte = bytes[index]
    if byte == 34 {
      inString = !inString
    } else if !inString {
      if byte == 40 {
        parenDepth += 1
      } else if byte == 41 {
        if parenDepth == 0 {
          break
        }
        parenDepth -= 1
      } else if byte == 91 {
        bracketDepth += 1
      } else if byte == 93 {
        if bracketDepth == 0 {
          break
        }
        bracketDepth -= 1
      } else if parenDepth == 0 && bracketDepth == 0 {
        if byte == 123 || byte == 125 || byte == 44 {
          break
        }
        if index + 1 < lineEnd,
           (byte == 38 || byte == 124),
           bytes[index + 1] == byte {
          break
        }
      }
    }
    index += 1
  }
  return swiftmutTrimTrailingHorizontalWhitespace(bytes, end: index)
}

func swiftmutDescribedValueExpressionSearchStart(
  bytes: [UInt8],
  matchStart: Int,
  lineEnd: Int
) -> Int {
  swiftmutDescribedValuePayloadStart(bytes: bytes, start: matchStart, end: lineEnd)
}

func swiftmutDescribedValuePayloadStart(bytes: [UInt8], start: Int, end: Int) -> Int {
  var start = swiftmutSkipHorizontalWhitespace(bytes, from: start)
  if start + 1 < end
      && (bytes[start] == 38 || bytes[start] == 124)
      && bytes[start + 1] == bytes[start] {
    start = swiftmutSkipHorizontalWhitespace(bytes, from: start + 2)
  }
  if start < end && bytes[start] == 33 {
    start = swiftmutSkipHorizontalWhitespace(bytes, from: start + 1)
  }
  while start < end && bytes[start] == 40 {
    start = swiftmutSkipHorizontalWhitespace(bytes, from: start + 1)
  }
  return start
}

func swiftmutDescribedValueExpressionResult(
  bytes: [UInt8],
  expressionRange: (start: Int, end: Int),
  mutation: SwiftmutMutation
) -> (column: Int, sourceOriginal: String, sourceMutated: String) {
  let sourceOriginal = String(decoding: bytes[expressionRange.start..<expressionRange.end], as: UTF8.self)
  return (
    expressionRange.start + 1,
    sourceOriginal,
    swiftmutImplicitReturnSourceMutation(for: mutation))
}
