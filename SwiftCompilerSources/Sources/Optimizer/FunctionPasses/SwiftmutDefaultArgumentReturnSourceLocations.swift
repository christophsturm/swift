//===--- SwiftmutDefaultArgumentReturnSourceLocations.swift ---------------===//
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

func swiftmutFindOrdinalDefaultArgumentReturnSourceLocation(
  functionName: String,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard let parameterIndex = swiftmutDefaultArgumentThunkSourceParameterIndex(functionName) else {
    return nil
  }

  var matches: [(path: String, line: Int, column: Int, sourceOriginal: String, score: Int)] = []
  for path in swiftmutSwiftSourcePaths(config: config) {
    guard let text = swiftmutRead(path) else {
      continue
    }
    for expression in swiftmutDefaultArgumentExpressions(
      in: text,
      parameterIndex: parameterIndex,
      mutation: mutation
    ) {
      let score = swiftmutDefaultArgumentDeclarationScore(
        functionName: functionName,
        sourceText: text,
        line: expression.line
      )
      matches.append((
        path,
        expression.line,
        expression.column,
        expression.sourceOriginal,
        score))
    }
  }

  guard !matches.isEmpty else {
    return nil
  }
  let bestScore = matches.map { $0.score }.max() ?? 0
  let bestMatches = bestScore > 0
    ? matches.filter { $0.score == bestScore }
    : matches
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

func swiftmutDefaultArgumentThunkSourceParameterIndex(_ functionName: String) -> Int? {
  let bytes = Array(functionName.utf8)
  guard bytes.count >= 4 else {
    return nil
  }
  var index = 0
  while index + 2 < bytes.count {
    if bytes[index] == 102,
       bytes[index + 1] == 65 {
      if bytes[index + 2] == 95 {
        return 0
      }
      guard swiftmutIsASCIIDigit(bytes[index + 2]) else {
        index += 1
        continue
      }
      var number = 0
      var cursor = index + 2
      while cursor < bytes.count && swiftmutIsASCIIDigit(bytes[cursor]) {
        number = number * 10 + Int(bytes[cursor] - 48)
        cursor += 1
      }
      if cursor < bytes.count && bytes[cursor] == 95 {
        return number + 1
      }
    }
    index += 1
  }
  return nil
}

func swiftmutDefaultArgumentExpressions(
  in text: String,
  parameterIndex: Int,
  mutation: SwiftmutMutation
) -> [(line: Int, column: Int, sourceOriginal: String)] {
  let bytes = Array(text.utf8)
  guard parameterIndex >= 0, !bytes.isEmpty else {
    return []
  }

  var expressions: [(line: Int, column: Int, sourceOriginal: String)] = []
  var index = 0
  while index < bytes.count {
    if swiftmutSourceDeclarationKeywordAt(bytes: bytes, index: index) {
      if let list = swiftmutSourceDeclarationParameterList(bytes: bytes, from: index),
         let expression = swiftmutDefaultArgumentExpression(
           in: bytes,
           parameterListStart: list.start,
           parameterListEnd: list.end,
           parameterIndex: parameterIndex,
           mutation: mutation
         ) {
        let location = swiftmutSourceLineAndColumn(bytes, offset: expression.offset)
        expressions.append((location.line, location.column, expression.sourceOriginal))
      }
      index += 4
      continue
    }
    index += 1
  }
  return expressions
}

func swiftmutSourceDeclarationKeywordAt(bytes: [UInt8], index: Int) -> Bool {
  SwiftmutSupport.swiftmutSourceDeclarationKeywordAt(bytes: bytes, index: index)
}

func swiftmutSourceDeclarationParameterList(
  bytes: [UInt8],
  from keywordStart: Int
) -> (start: Int, end: Int)? {
  SwiftmutSupport.swiftmutSourceDeclarationParameterList(bytes: bytes, from: keywordStart)
}

func swiftmutFindDeclarationOpenParen(bytes: [UInt8], from offset: Int) -> Int? {
  SwiftmutSupport.swiftmutFindDeclarationOpenParen(bytes: bytes, from: offset)
}

func swiftmutFindMatchingSourceDelimiter(
  bytes: [UInt8],
  openOffset: Int,
  open: UInt8,
  close: UInt8
) -> Int? {
  SwiftmutSupport.swiftmutFindMatchingSourceDelimiter(
    bytes: bytes,
    openOffset: openOffset,
    open: open,
    close: close)
}

func swiftmutDefaultArgumentExpression(
  in bytes: [UInt8],
  parameterListStart: Int,
  parameterListEnd: Int,
  parameterIndex: Int,
  mutation: SwiftmutMutation
) -> (offset: Int, sourceOriginal: String)? {
  var parameterStart = parameterListStart
  var currentParameter = 0
  var index = parameterListStart
  var squareDepth = 0
  var parenDepth = 0
  var braceDepth = 0
  var inString = false
  var escaped = false

  func parameterExpression(end: Int) -> (offset: Int, sourceOriginal: String)? {
    guard currentParameter == parameterIndex,
          let equals = swiftmutTopLevelEquals(bytes: bytes, start: parameterStart, end: end),
          let expression = swiftmutDefaultArgumentExpression(
            bytes: bytes,
            from: equals + 1,
            mutation: mutation
          ) else {
      return nil
    }
    return (expression.start, expression.text)
  }

  while index <= parameterListEnd {
    let byte = index < parameterListEnd ? bytes[index] : 44
    if inString {
      if escaped {
        escaped = false
      } else if byte == 92 {
        escaped = true
      } else if byte == 34 {
        inString = false
      }
      index += 1
      continue
    }

    if byte == 34 {
      inString = true
    } else if byte == 91 {
      squareDepth += 1
    } else if byte == 93 {
      squareDepth -= 1
    } else if byte == 40 {
      parenDepth += 1
    } else if byte == 41 {
      parenDepth -= 1
    } else if byte == 123 {
      braceDepth += 1
    } else if byte == 125 {
      braceDepth -= 1
    } else if byte == 44 && squareDepth == 0 && parenDepth == 0 && braceDepth == 0 {
      if let expression = parameterExpression(end: index) {
        return expression
      }
      currentParameter += 1
      parameterStart = index + 1
    }
    index += 1
  }
  return nil
}

func swiftmutTopLevelEquals(bytes: [UInt8], start: Int, end: Int) -> Int? {
  SwiftmutSupport.swiftmutTopLevelEquals(bytes: bytes, start: start, end: end)
}

func swiftmutIsASCIIDigit(_ byte: UInt8) -> Bool {
  byte >= 48 && byte <= 57
}
