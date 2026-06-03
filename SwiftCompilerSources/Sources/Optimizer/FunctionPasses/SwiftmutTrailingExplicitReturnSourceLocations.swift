//===--- SwiftmutTrailingExplicitReturnSourceLocations.swift -------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2026 swiftmut contributors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

func swiftmutFindTrailingExplicitReturnSourceLocation(
  path: String,
  functionLine: Int,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard functionLine > 0,
        let text = swiftmutRead(path) else {
    return nil
  }
  let bytes = Array(text.utf8)
  guard let body = swiftmutFunctionBodyByteRange(bytes: bytes, functionLine: functionLine),
        let match = swiftmutTrailingExplicitReturnLine(
          bytes: bytes,
          bodyStart: body.start,
          bodyEnd: body.end,
          mutation: mutation
        ) else {
    return nil
  }
  return (
    swiftmutTrimPackageRoot(path, config: config),
    match.line,
    match.column,
    mutation.sourceOriginal,
    mutation.sourceMutated)
}

func swiftmutTrailingExplicitReturnLine(
  bytes: [UInt8],
  bodyStart: Int,
  bodyEnd: Int,
  mutation: SwiftmutMutation
) -> (line: Int, column: Int)? {
  let start = swiftmutSkipWhitespace(bytes, from: bodyStart)
  let end = swiftmutTrimTrailingWhitespace(bytes, end: bodyEnd)
  guard start < end else {
    return nil
  }

  var lineStart = start
  var index = start
  var parenDepth = 0
  var bracketDepth = 0
  var braceDepth = 0
  var quote: UInt8?
  var escaped = false
  var lastReturn: (line: Int, column: Int)?
  var lastTopLevelStatementWasReturn = false

  func inspectLine(lineStart: Int, lineEnd: Int) {
    guard lineStart < lineEnd,
          parenDepth == 0,
          bracketDepth == 0,
          braceDepth == 0 else {
      return
    }
    let token = swiftmutSkipHorizontalWhitespace(bytes, from: lineStart)
    guard token < lineEnd else {
      return
    }
    if swiftmutLineStartsWithExpressionContinuation(bytes[token]) {
      return
    }
    let lineBytes = Array(bytes[lineStart..<lineEnd])
    let localStart = token - lineStart
    if swiftmutReturnLineIsEligible(bytes: lineBytes, start: localStart, mutation: mutation) {
      let location = swiftmutSourceLineAndColumn(bytes, offset: token)
      lastReturn = (location.line, location.column)
      lastTopLevelStatementWasReturn = true
    } else {
      lastTopLevelStatementWasReturn = false
    }
  }

  while index < end {
    let byte = bytes[index]
    if byte == 10 || byte == 13 {
      inspectLine(lineStart: lineStart, lineEnd: index)
      swiftmutTrailingExplicitReturnUpdateDepths(
        bytes: bytes,
        start: lineStart,
        end: index,
        parenDepth: &parenDepth,
        bracketDepth: &bracketDepth,
        braceDepth: &braceDepth,
        quote: &quote,
        escaped: &escaped
      )
      index += 1
      lineStart = index
      continue
    }
    index += 1
  }

  if lineStart < end {
    inspectLine(lineStart: lineStart, lineEnd: end)
    swiftmutTrailingExplicitReturnUpdateDepths(
      bytes: bytes,
      start: lineStart,
      end: end,
      parenDepth: &parenDepth,
      bracketDepth: &bracketDepth,
      braceDepth: &braceDepth,
      quote: &quote,
      escaped: &escaped
    )
  }

  guard quote == nil,
        parenDepth == 0,
        bracketDepth == 0,
        braceDepth == 0,
        lastTopLevelStatementWasReturn else {
    return nil
  }
  return lastReturn
}

func swiftmutTrailingExplicitReturnUpdateDepths(
  bytes: [UInt8],
  start: Int,
  end: Int,
  parenDepth: inout Int,
  bracketDepth: inout Int,
  braceDepth: inout Int,
  quote: inout UInt8?,
  escaped: inout Bool
) {
  var index = start
  while index < end {
    let byte = bytes[index]
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

    switch byte {
    case 34:
      quote = byte
    case 40:
      parenDepth += 1
    case 41:
      parenDepth -= 1
    case 91:
      bracketDepth += 1
    case 93:
      bracketDepth -= 1
    case 123:
      braceDepth += 1
    case 125:
      braceDepth -= 1
    default:
      break
    }
    index += 1
  }
}
