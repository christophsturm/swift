//===--- SwiftmutMultilineImplicitReturnSourceLocations.swift -------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2026 swiftmut contributors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

func swiftmutFindMultilineImplicitReturnSourceLocation(
  path: String,
  functionLine: Int,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard mutation.sourceOriginal == "return",
        functionLine > 0,
        let text = swiftmutRead(path) else {
    return nil
  }
  let bytes = Array(text.utf8)
  guard let body = swiftmutFunctionBodyByteRange(bytes: bytes, functionLine: functionLine) else {
    return nil
  }
  let start = swiftmutSkipWhitespace(bytes, from: body.start)
  let end = swiftmutTrimTrailingWhitespace(bytes, end: body.end)
  guard start < end,
        swiftmutMultilineImplicitReturnExpressionIsMappable(
          bytes: bytes,
          start: start,
          end: end,
          mutation: mutation
        ) else {
    return nil
  }

  let location = swiftmutSourceLineAndColumn(bytes, offset: start)
  return (
    swiftmutTrimPackageRoot(path, config: config),
    location.line,
    location.column,
    String(decoding: bytes[start..<end], as: UTF8.self),
    swiftmutImplicitReturnSourceMutation(for: mutation))
}

func swiftmutFunctionBodyByteRange(bytes: [UInt8], functionLine: Int) -> (start: Int, end: Int)? {
  guard let lineStart = swiftmutLineStartOffset(bytes: bytes, line: functionLine),
        swiftmutFunctionDeclarationLineContainsFunc(bytes: bytes, lineStart: lineStart),
        let open = swiftmutFirstFunctionBodyBrace(bytes: bytes, from: lineStart),
        let close = swiftmutMatchingCloseBrace(bytes: bytes, open: open) else {
    return nil
  }
  return (open + 1, close)
}

func swiftmutFunctionDeclarationLineContainsFunc(bytes: [UInt8], lineStart: Int) -> Bool {
  var lineEnd = lineStart
  while lineEnd < bytes.count && bytes[lineEnd] != 10 && bytes[lineEnd] != 13 {
    lineEnd += 1
  }
  return swiftmutASCIIContains(bytes, start: lineStart, end: lineEnd, pattern: "func ")
}

func swiftmutLineStartOffset(bytes: [UInt8], line targetLine: Int) -> Int? {
  guard targetLine > 0 else {
    return nil
  }
  if targetLine == 1 {
    return 0
  }
  var line = 1
  var index = 0
  while index < bytes.count {
    if bytes[index] == 10 {
      line += 1
      if line == targetLine {
        return index + 1
      }
    }
    index += 1
  }
  return nil
}

func swiftmutFirstFunctionBodyBrace(bytes: [UInt8], from start: Int) -> Int? {
  var index = start
  var lineCount = 0
  var quote: UInt8?
  var escaped = false
  while index < bytes.count {
    let byte = bytes[index]
    if let currentQuote = quote {
      if escaped {
        escaped = false
      } else if byte == 92 {
        escaped = true
      } else if byte == currentQuote {
        quote = nil
      }
    } else if byte == 34 {
      quote = byte
    } else if byte == 123 {
      return index
    } else if byte == 10 {
      lineCount += 1
      if lineCount > 80 {
        return nil
      }
    }
    index += 1
  }
  return nil
}

func swiftmutMatchingCloseBrace(bytes: [UInt8], open: Int) -> Int? {
  var index = open
  var depth = 0
  var quote: UInt8?
  var escaped = false
  while index < bytes.count {
    let byte = bytes[index]
    if let currentQuote = quote {
      if escaped {
        escaped = false
      } else if byte == 92 {
        escaped = true
      } else if byte == currentQuote {
        quote = nil
      }
    } else if byte == 34 {
      quote = byte
    } else if byte == 123 {
      depth += 1
    } else if byte == 125 {
      depth -= 1
      if depth == 0 {
        return index
      }
      if depth < 0 {
        return nil
      }
    }
    index += 1
  }
  return nil
}

func swiftmutSkipWhitespace(_ bytes: [UInt8], from offset: Int) -> Int {
  var index = max(0, offset)
  while index < bytes.count && swiftmutIsWhitespace(bytes[index]) {
    index += 1
  }
  return index
}

func swiftmutTrimTrailingWhitespace(_ bytes: [UInt8], end: Int) -> Int {
  var index = min(end, bytes.count)
  while index > 0 && swiftmutIsWhitespace(bytes[index - 1]) {
    index -= 1
  }
  return index
}

func swiftmutIsWhitespace(_ byte: UInt8) -> Bool {
  byte == 32 || byte == 9 || byte == 10 || byte == 13
}

func swiftmutMultilineImplicitReturnExpressionIsMappable(
  bytes: [UInt8],
  start: Int,
  end: Int,
  mutation: SwiftmutMutation
) -> Bool {
  guard swiftmutFirstLineLooksLikeImplicitReturnExpression(
    bytes: bytes,
    start: start,
    end: end,
    mutation: mutation
  ) else {
    return false
  }
  return swiftmutBodySliceContainsOneExpression(bytes: bytes, start: start, end: end)
}

func swiftmutFirstLineLooksLikeImplicitReturnExpression(
  bytes: [UInt8],
  start: Int,
  end: Int,
  mutation: SwiftmutMutation
) -> Bool {
  var lineEnd = start
  while lineEnd < end && bytes[lineEnd] != 10 && bytes[lineEnd] != 13 {
    lineEnd += 1
  }
  let trimmedEnd = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: lineEnd)
  guard start < trimmedEnd else {
    return false
  }
  return swiftmutLineLooksLikeImplicitReturnExpression(
    bytes: bytes,
    start: start,
    end: trimmedEnd,
    allowsInlineBraces: true
  ) && swiftmutReturnValueIsEligible(bytes: bytes, start: start, mutation: mutation)
}

func swiftmutBodySliceContainsOneExpression(bytes: [UInt8], start: Int, end: Int) -> Bool {
  var index = start
  var atLineStart = true
  var sawLine = false
  var parenDepth = 0
  var bracketDepth = 0
  var braceDepth = 0
  var quote: UInt8?
  var escaped = false

  while index < end {
    let byte = bytes[index]
    if atLineStart {
      let token = swiftmutSkipHorizontalWhitespace(bytes, from: index)
      if token >= end {
        return true
      }
      if bytes[token] == 10 || bytes[token] == 13 {
        index = token
      } else {
        let atTopLevel = parenDepth == 0 && bracketDepth == 0 && braceDepth == 0
        if sawLine && atTopLevel && !swiftmutLineStartsWithExpressionContinuation(bytes[token]) {
          return false
        }
        sawLine = true
        atLineStart = false
        index = token
      }
      continue
    }

    if let currentQuote = quote {
      if escaped {
        escaped = false
      } else if byte == 92 {
        escaped = true
      } else if byte == currentQuote {
        quote = nil
      }
      index += 1
      continue
    }

    if byte == 34 {
      quote = byte
    } else if byte == 40 {
      parenDepth += 1
    } else if byte == 41 {
      parenDepth -= 1
    } else if byte == 91 {
      bracketDepth += 1
    } else if byte == 93 {
      bracketDepth -= 1
    } else if byte == 123 {
      braceDepth += 1
    } else if byte == 125 {
      braceDepth -= 1
    } else if byte == 59 && parenDepth == 0 && bracketDepth == 0 && braceDepth == 0 {
      return false
    } else if byte == 10 || byte == 13 {
      atLineStart = true
    }

    if parenDepth < 0 || bracketDepth < 0 || braceDepth < 0 {
      return false
    }
    index += 1
  }

  return quote == nil && parenDepth == 0 && bracketDepth == 0 && braceDepth == 0 && sawLine
}

func swiftmutLineStartsWithExpressionContinuation(_ byte: UInt8) -> Bool {
  switch byte {
  case 33, 37, 38, 42, 43, 45, 46, 47, 58, 60, 61, 62, 63, 93, 124:
    return true
  default:
    return false
  }
}
