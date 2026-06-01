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
      guard score > 0 else {
        continue
      }
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

func swiftmutDefaultArgumentThunkSourceParameterIndex(_ functionName: String) -> Int? {
  let bytes = Array(functionName.utf8)
  guard bytes.count >= 4 else {
    return nil
  }
  var index = 0
  while index + 3 < bytes.count {
    if bytes[index] == 102,
       bytes[index + 1] == 65,
       swiftmutIsASCIIDigit(bytes[index + 2]) {
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
  if swiftmutASCIIHasExactPrefix(bytes, start: index, prefix: "func ") {
    return index == 0 || !swiftmutIsASCIILetterNumberOrUnderscore(bytes[index - 1])
  }
  if swiftmutASCIIHasExactPrefix(bytes, start: index, prefix: "init(") {
    return index == 0 || !swiftmutIsASCIILetterNumberOrUnderscore(bytes[index - 1])
  }
  if swiftmutASCIIHasExactPrefix(bytes, start: index, prefix: "init?(") {
    return index == 0 || !swiftmutIsASCIILetterNumberOrUnderscore(bytes[index - 1])
  }
  if swiftmutASCIIHasExactPrefix(bytes, start: index, prefix: "init!(") {
    return index == 0 || !swiftmutIsASCIILetterNumberOrUnderscore(bytes[index - 1])
  }
  return false
}

func swiftmutSourceDeclarationParameterList(
  bytes: [UInt8],
  from keywordStart: Int
) -> (start: Int, end: Int)? {
  guard let openParen = swiftmutFindDeclarationOpenParen(bytes: bytes, from: keywordStart),
        let closeParen = swiftmutFindMatchingSourceDelimiter(
          bytes: bytes,
          openOffset: openParen,
          open: 40,
          close: 41
        ) else {
    return nil
  }
  return (openParen + 1, closeParen)
}

func swiftmutFindDeclarationOpenParen(bytes: [UInt8], from offset: Int) -> Int? {
  var index = offset
  let limit = min(bytes.count, offset + 320)
  var angleDepth = 0
  var inString = false
  var escaped = false
  while index < limit {
    let byte = bytes[index]
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
    } else if byte == 10 || byte == 123 {
      return nil
    } else if byte == 60 {
      angleDepth += 1
    } else if byte == 62 && angleDepth > 0 {
      angleDepth -= 1
    } else if byte == 40 && angleDepth == 0 {
      return index
    }
    index += 1
  }
  return nil
}

func swiftmutFindMatchingSourceDelimiter(
  bytes: [UInt8],
  openOffset: Int,
  open: UInt8,
  close: UInt8
) -> Int? {
  var depth = 0
  var index = openOffset
  var inString = false
  var escaped = false
  while index < bytes.count {
    let byte = bytes[index]
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
    } else if byte == open {
      depth += 1
    } else if byte == close {
      depth -= 1
      if depth == 0 {
        return index
      }
    }
    index += 1
  }
  return nil
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
  var index = start
  var squareDepth = 0
  var parenDepth = 0
  var braceDepth = 0
  var inString = false
  var escaped = false
  while index < end {
    let byte = bytes[index]
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
    } else if byte == 61 && squareDepth == 0 && parenDepth == 0 && braceDepth == 0 {
      return index
    }
    index += 1
  }
  return nil
}

func swiftmutIsASCIIDigit(_ byte: UInt8) -> Bool {
  byte >= 48 && byte <= 57
}
