//===--- SwiftmutClosureArgumentReturnSourceLocations.swift -------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2026 swiftmut contributors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

func swiftmutFindClosureArgumentReturnSourceLocation(
  path: String,
  preferredLine: Int,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard mutation.sourceOriginal == "return",
        let replacement = swiftmutClosureArgumentReturnReplacement(for: mutation),
        preferredLine > 0,
        let text = swiftmutRead(path) else {
    return nil
  }

  if let exact = swiftmutClosureArgumentReturnSourceLocation(
    in: text,
    path: path,
    lineRange: preferredLine...preferredLine,
    replacement: replacement,
    mutation: mutation,
    config: config
  ) {
    return exact
  }

  let firstLine = preferredLine > 2 ? preferredLine - 2 : 1
  return swiftmutClosureArgumentReturnSourceLocation(
    in: text,
    path: path,
    lineRange: firstLine...(preferredLine + 2),
    replacement: replacement,
    mutation: mutation,
    config: config
  )
}

func swiftmutClosureArgumentReturnSourceLocation(
  in text: String,
  path: String,
  lineRange: ClosedRange<Int>,
  replacement: String,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  var matches: [(line: Int, column: Int, sourceOriginal: String, sourceMutated: String)] = []
  var currentLine = 1
  var lineStart = text.startIndex
  var index = text.startIndex

  func inspectLine(_ lineText: String, line: Int) {
    guard lineRange.contains(line),
          matches.count < 2,
          let expression = swiftmutClosureArgumentReturnExpression(
            lineText,
            replacement: replacement,
            mutation: mutation
          ) else {
      return
    }
    matches.append((line, expression.column, expression.sourceOriginal, expression.sourceMutated))
  }

  while index < text.endIndex {
    if text[index] == "\n" {
      inspectLine(String(text[lineStart..<index]), line: currentLine)
      if currentLine >= lineRange.upperBound || matches.count >= 2 {
        break
      }
      currentLine += 1
      lineStart = text.index(after: index)
    }
    index = text.index(after: index)
  }

  if index == text.endIndex && currentLine <= lineRange.upperBound {
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

func swiftmutClosureArgumentReturnExpression(
  _ line: String,
  replacement: String,
  mutation: SwiftmutMutation
) -> (column: Int, sourceOriginal: String, sourceMutated: String)? {
  let bytes = Array(line.utf8)
  let lineStart = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
  let lineEnd = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  guard lineStart < lineEnd,
        !swiftmutLineStartsWithAssignmentReturnBlockedPrefix(bytes: bytes, start: lineStart) else {
    return nil
  }

  if let keyPath = swiftmutClosureArgumentKeyPathExpression(
    bytes: bytes,
    start: lineStart,
    end: lineEnd,
    replacement: replacement,
    mutation: mutation
  ) {
    return keyPath
  }
  return swiftmutSortedByFunctionArgumentExpression(
    bytes: bytes,
    start: lineStart,
    end: lineEnd,
    replacement: replacement,
    mutation: mutation
  )
}

func swiftmutClosureArgumentKeyPathExpression(
  bytes: [UInt8],
  start: Int,
  end: Int,
  replacement: String,
  mutation: SwiftmutMutation
) -> (column: Int, sourceOriginal: String, sourceMutated: String)? {
  var matches: [(column: Int, sourceOriginal: String, sourceMutated: String)] = []
  var index = start
  while index + 2 < end {
    if bytes[index] == 92,
       bytes[index + 1] == 46,
       swiftmutIsASCIIIdentifierStart(bytes[index + 2]),
       swiftmutClosureArgumentKeyPathHasPredicateLabel(bytes: bytes, keyPathStart: index) {
      var valueEnd = index + 3
      while valueEnd < end && swiftmutClosureArgumentPathByte(bytes[valueEnd]) {
        valueEnd += 1
      }
      if swiftmutReturnValueIsEligible(bytes: bytes, start: index, mutation: mutation) {
        matches.append((
          index + 1,
          String(decoding: bytes[index..<valueEnd], as: UTF8.self),
          "{ _ in \(replacement) }"))
      }
      index = valueEnd
      continue
    }
    index += 1
  }
  return matches.count == 1 ? matches[0] : nil
}

func swiftmutSortedByFunctionArgumentExpression(
  bytes: [UInt8],
  start: Int,
  end: Int,
  replacement: String,
  mutation: SwiftmutMutation
) -> (column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard swiftmutASCIIContains(bytes, start: start, end: end, pattern: ".sorted("),
        let label = swiftmutASCIIIndex(bytes, start: start, end: end, pattern: "by:") else {
    return nil
  }
  let valueStart = swiftmutSkipHorizontalWhitespace(bytes, from: label + 3)
  guard valueStart < end,
        swiftmutIsASCIIIdentifierStart(bytes[valueStart]) else {
    return nil
  }

  var valueEnd = valueStart + 1
  while valueEnd < end && swiftmutClosureArgumentPathByte(bytes[valueEnd]) {
    valueEnd += 1
  }
  guard valueEnd > valueStart,
        swiftmutReturnValueIsEligible(bytes: bytes, start: valueStart, mutation: mutation) else {
    return nil
  }
  return (
    valueStart + 1,
    String(decoding: bytes[valueStart..<valueEnd], as: UTF8.self),
    "{ _, _ in \(replacement) }")
}

func swiftmutClosureArgumentReturnReplacement(for mutation: SwiftmutMutation) -> String? {
  switch mutation.mutatedBuiltinName {
  case "return_false":
    return "false"
  case "return_true":
    return "true"
  default:
    return nil
  }
}

func swiftmutClosureArgumentKeyPathHasPredicateLabel(bytes: [UInt8], keyPathStart: Int) -> Bool {
  var index = keyPathStart - 1
  while index >= 0 && swiftmutIsHorizontalWhitespace(bytes[index]) {
    index -= 1
  }
  guard index >= 0,
        bytes[index] == 58 else {
    return false
  }

  var labelEnd = index
  index -= 1
  while index >= 0 && swiftmutIsHorizontalWhitespace(bytes[index]) {
    index -= 1
  }
  labelEnd = index + 1
  while index >= 0 && swiftmutIsASCIILetterNumberOrUnderscore(bytes[index]) {
    index -= 1
  }
  let labelStart = index + 1
  guard labelStart < labelEnd else {
    return false
  }
  let label = String(decoding: bytes[labelStart..<labelEnd], as: UTF8.self)
  return label == "whereSeparator"
}

func swiftmutClosureArgumentPathByte(_ byte: UInt8) -> Bool {
  swiftmutIsASCIILetterNumberOrUnderscore(byte) || byte == 46
}
