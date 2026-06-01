//===--- SwiftmutDefaultArgumentValueApplySourceLocations.swift -----------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2026 swiftmut contributors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

func swiftmutFindDefaultArgumentValueApplySourceLocation(
  functionName: String,
  locationDescription: String,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard swiftmutFunctionNameLooksDefaultArgumentThunk(functionName),
        let rawSnippet = swiftmutQuotedSourceSnippetPrefix(locationDescription) else {
    return nil
  }

  let snippet = swiftmutDecodedSourceSnippet(rawSnippet)
  guard swiftmutDefaultArgumentValueApplySnippetLooksMappable(snippet) else {
    return nil
  }

  var matches: [(path: String, line: Int, column: Int, sourceOriginal: String, score: Int)] = []
  for path in swiftmutSwiftSourcePaths(config: config) {
    guard let text = swiftmutRead(path) else {
      continue
    }
    for match in swiftmutSourceSnippetMatches(snippet, in: text) {
      guard let sourceLine = swiftmutSourceLine(text, line: match.line),
            let expression = swiftmutDefaultArgumentValueApplyExpression(
              line: sourceLine,
              matchColumn: match.column,
              mutation: mutation
            ) else {
        continue
      }
      let score = swiftmutDefaultArgumentDeclarationScore(
        functionName: functionName,
        sourceText: text,
        line: match.line
      )
      guard score > 0 else {
        continue
      }
      matches.append((
        path,
        match.line,
        expression.column,
        expression.sourceOriginal,
        score))
    }
  }

  guard !matches.isEmpty else {
    return nil
  }
  let bestScore = matches.map { $0.score }.max() ?? 0
  let bestMatches = matches.filter { $0.score == bestScore }
  guard bestMatches.count == 1,
        let match = bestMatches.first else {
    return nil
  }

  return (
    swiftmutTrimPackageRoot(match.path, config: config),
    match.line,
    match.column,
    match.sourceOriginal,
    swiftmutImplicitReturnSourceMutation(for: mutation))
}

func swiftmutDefaultArgumentValueApplySnippetLooksMappable(_ snippet: String) -> Bool {
  let bytes = Array(snippet.utf8)
  let start = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
  let end = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  guard start < end,
        end - start >= 3,
        !swiftmutASCIIHasExactPrefix(bytes, start: start, prefix: "()") else {
    return false
  }
  for index in start..<end where bytes[index] == 10 || bytes[index] == 13 {
    return false
  }
  let first = bytes[start]
  return swiftmutIsASCIIIdentifierStart(first) || first == 36
}

func swiftmutDefaultArgumentValueApplyExpression(
  line: String,
  matchColumn: Int,
  mutation: SwiftmutMutation
) -> (column: Int, sourceOriginal: String)? {
  let bytes = Array(line.utf8)
  let lineEnd = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  let matchStart = max(0, matchColumn - 1)
  guard matchStart < lineEnd else {
    return nil
  }

  var tokenEnd = matchStart
  while tokenEnd < lineEnd && swiftmutIsSourceExpressionPrefixByte(bytes[tokenEnd]) {
    tokenEnd += 1
  }
  if tokenEnd == matchStart {
    tokenEnd = swiftmutDefaultArgumentValueApplyTokenEnd(bytes: bytes, start: matchStart, end: lineEnd)
  }
  let afterToken = swiftmutSkipHorizontalWhitespace(bytes, from: tokenEnd)
  if afterToken < lineEnd && bytes[afterToken] == 58 {
    return nil
  }
  guard tokenEnd > matchStart,
        let expressionRange = swiftmutSourceExpressionRange(
          around: (matchStart, tokenEnd),
          in: bytes,
          lineEnd: lineEnd
        ),
        swiftmutReturnValueIsEligible(bytes: bytes, start: expressionRange.start, mutation: mutation) else {
    return nil
  }

  return (
    expressionRange.start + 1,
    String(decoding: bytes[expressionRange.start..<expressionRange.end], as: UTF8.self))
}

func swiftmutDefaultArgumentValueApplyTokenEnd(bytes: [UInt8], start: Int, end: Int) -> Int {
  var index = start
  while index < end && swiftmutIsASCIILetterNumberOrUnderscore(bytes[index]) {
    index += 1
  }
  return index
}
