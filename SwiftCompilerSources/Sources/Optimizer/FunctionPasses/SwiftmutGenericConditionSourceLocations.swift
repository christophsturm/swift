//===--- SwiftmutGenericConditionSourceLocations.swift ----------------------------------------------===//
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

func swiftmutGenericConditionSourceLocation(
  path: String,
  line: Int,
  fallbackColumn: Int,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard let sourceLine = swiftmutAbsoluteSourceLine(path: path, line: line),
        let expression = swiftmutGenericConditionExpression(sourceLine) else {
    return nil
  }
  return (
    swiftmutTrimPackageRoot(path, config: config),
    line,
    expression.column > 0 ? expression.column : fallbackColumn,
    expression.sourceOriginal,
    mutation.sourceMutated)
}

func swiftmutSourceLocation(
  for instruction: Instruction,
  function: Function,
  moduleName: String,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  if let fileNameAndPosition = instruction.location.fileNameAndPosition {
    let path = fileNameAndPosition.path.string
    guard let matchedPath = swiftmutIncludedSourcePath(path, config: config) else {
      return nil
    }
    return (
      swiftmutTrimPackageRoot(matchedPath, config: config),
      fileNameAndPosition.line,
      fileNameAndPosition.column,
      "",
      "")
  }

  if let located = swiftmutFindSourceOperator(
    moduleName: moduleName,
    functionLocation: function.location.description,
    mutation: mutation,
    config: config) {
    return located
  }

  if let located = swiftmutFindDescribedSourceOperator(
    moduleName: moduleName,
    functionLocation: function.location.description,
    locationDescription: instruction.location.description,
    mutation: mutation,
    config: config) {
    return located
  }

  if let comparison = instruction as? BuiltinInst,
     swiftmutIsComparisonBuiltin(comparison),
     let ordinal = swiftmutComparisonOrdinalAndCount(for: comparison, in: function),
     ordinal.count <= 12 {
    return swiftmutFindOrdinalSourceOperator(
      moduleName: moduleName,
      functionLocation: function.location.description,
      ordinal: ordinal.ordinal,
      expectedCount: ordinal.count,
      mutation: mutation,
      config: config)
  }

  return nil
}

func swiftmutSourceLocation(
  for comparison: BuiltinInst,
  branch: CondBranchInst,
  function: Function,
  moduleName: String,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard swiftmutIsComparisonBuiltin(comparison) else {
    return nil
  }
  if mutation.sourceOriginal == "condition",
     let located = swiftmutFindDescribedGenericConditionSourceLocation(
       moduleName: moduleName,
       functionLocation: function.location.description,
       locationDescription: branch.location.description,
       mutation: mutation,
       config: config
     ) {
    return located
  }
  return swiftmutFindDescribedSourceOperator(
    moduleName: moduleName,
    functionLocation: function.location.description,
    locationDescription: branch.location.description,
    mutation: mutation,
    config: config
  ) ?? swiftmutFindOrdinalDescribedConditionSourceLocation(
    moduleName: moduleName,
    function: function,
    branch: branch,
    locationDescription: branch.location.description,
    mutation: mutation,
    config: config)
}

func swiftmutFindDescribedGenericConditionSourceLocation(
  moduleName: String,
  functionLocation: String,
  locationDescription: String,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard let snippet = swiftmutQuotedSourceSnippetPrefix(locationDescription),
        let needle = swiftmutDescribedGenericConditionNeedle(snippet) else {
    return nil
  }

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
    let result = swiftmutFindDescribedGenericConditionInFunctionBody(
      path: path,
      preferredLine: preferredLine,
      needle: needle,
      mutation: mutation,
      config: config
    ) ?? swiftmutFindDescribedGenericConditionInFile(
      path: path,
      needle: needle,
      mutation: mutation,
      config: config
    )
    guard let result else { continue }
    if path.hasPrefix(preferredPrefix) {
      return result
    }
    if fallback == nil {
      fallback = result
    }
  }
  return fallback
}

func swiftmutGenericConditionSourceIsExplicit(
  file: String,
  line: Int,
  config: SwiftmutConfig
) -> Bool {
  guard let sourceLine = swiftmutSourceLine(file: file, line: line, config: config) else {
    return true
  }
  return swiftmutSourceLineLooksLikeExplicitCondition(sourceLine)
}

func swiftmutSourceLine(
  file: String,
  line: Int,
  config: SwiftmutConfig
) -> String? {
  guard line > 0 else {
    return nil
  }

  let path: String
  if file.hasPrefix("/") || config.packageRoot.isEmpty {
    path = file
  } else {
    path = config.packageRoot + "/" + file
  }
  guard let matchedPath = swiftmutIncludedSourcePath(path, config: config),
        let text = swiftmutRead(matchedPath) else {
    return nil
  }

  var currentLine = 1
  var lineStart = text.startIndex
  var index = text.startIndex
  while index < text.endIndex {
    if text[index] == "\n" {
      if currentLine == line {
        return String(text[lineStart..<index])
      }
      currentLine += 1
      lineStart = text.index(after: index)
    }
    index = text.index(after: index)
  }

  if currentLine == line {
    return String(text[lineStart..<text.endIndex])
  }
  return nil
}

func swiftmutAbsoluteSourceLine(path: String, line: Int) -> String? {
  guard line > 0,
        let text = swiftmutRead(path) else {
    return nil
  }

  var currentLine = 1
  var lineStart = text.startIndex
  var index = text.startIndex
  while index < text.endIndex {
    if text[index] == "\n" {
      if currentLine == line {
        return String(text[lineStart..<index])
      }
      currentLine += 1
      lineStart = text.index(after: index)
    }
    index = text.index(after: index)
  }

  if currentLine == line {
    return String(text[lineStart..<text.endIndex])
  }
  return nil
}

func swiftmutGenericConditionExpression(
  _ line: String
) -> (column: Int, sourceOriginal: String)? {
  let bytes = Array(line.utf8)
  let lineEnd = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  var start = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
  guard start < lineEnd else {
    return nil
  }

  if bytes[start] == 125 {
    start = swiftmutSkipHorizontalWhitespace(bytes, from: start + 1)
    if swiftmutASCIIHasPrefix(bytes, start: start, prefix: "else ") {
      start = swiftmutSkipHorizontalWhitespace(bytes, from: start + 5)
    }
  }

  guard !swiftmutSourceLineLooksLikeOptionalBindingCondition(bytes: bytes, start: start),
        !swiftmutTopLevelASCIIContains(bytes, start: start, end: lineEnd, pattern: ", let "),
        !swiftmutTopLevelASCIIContains(bytes, start: start, end: lineEnd, pattern: ", var ") else {
    return nil
  }

  let expressionRange: (start: Int, end: Int)?
  if swiftmutASCIIHasPrefix(bytes, start: start, prefix: "if ") {
    expressionRange = swiftmutControlConditionRange(bytes: bytes, start: start + 3, end: lineEnd)
  } else if swiftmutASCIIHasPrefix(bytes, start: start, prefix: "if(") {
    expressionRange = swiftmutParenthesizedControlConditionRange(bytes: bytes, open: start + 2, end: lineEnd)
  } else if swiftmutASCIIHasPrefix(bytes, start: start, prefix: "guard ") {
    expressionRange = swiftmutGuardConditionRange(bytes: bytes, start: start + 6, end: lineEnd)
  } else if swiftmutASCIIHasPrefix(bytes, start: start, prefix: "guard(") {
    expressionRange = swiftmutParenthesizedControlConditionRange(bytes: bytes, open: start + 5, end: lineEnd)
  } else if swiftmutASCIIHasPrefix(bytes, start: start, prefix: "while ") {
    expressionRange = swiftmutControlConditionRange(bytes: bytes, start: start + 6, end: lineEnd)
  } else if swiftmutASCIIHasPrefix(bytes, start: start, prefix: "while(") {
    expressionRange = swiftmutParenthesizedControlConditionRange(bytes: bytes, open: start + 5, end: lineEnd)
  } else if swiftmutASCIIHasPrefix(bytes, start: start, prefix: "for ")
      || swiftmutASCIIHasPrefix(bytes, start: start, prefix: "for(") {
    expressionRange = swiftmutForWhereConditionRange(bytes: bytes, start: start, end: lineEnd)
  } else {
    expressionRange = nil
  }

  guard var range = expressionRange else {
    return nil
  }
  range.start = swiftmutSkipHorizontalWhitespace(bytes, from: range.start)
  range.end = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: range.end)
  guard range.start < range.end else {
    return nil
  }
  return (
    range.start + 1,
    String(decoding: bytes[range.start..<range.end], as: UTF8.self))
}

func swiftmutControlConditionRange(
  bytes: [UInt8],
  start: Int,
  end: Int
) -> (start: Int, end: Int)? {
  let conditionEnd = swiftmutTopLevelByteIndex(bytes, start: start, end: end, byte: 123) ?? end
  return (start, conditionEnd)
}

func swiftmutGuardConditionRange(
  bytes: [UInt8],
  start: Int,
  end: Int
) -> (start: Int, end: Int)? {
  let elseIndex = swiftmutTopLevelASCIIIndex(bytes, start: start, end: end, pattern: " else ")
  let braceIndex = swiftmutTopLevelByteIndex(bytes, start: start, end: end, byte: 123)
  let conditionEnd = elseIndex ?? braceIndex ?? end
  return (start, conditionEnd)
}

func swiftmutForWhereConditionRange(
  bytes: [UInt8],
  start: Int,
  end: Int
) -> (start: Int, end: Int)? {
  guard let whereIndex = swiftmutTopLevelASCIIIndex(bytes, start: start, end: end, pattern: " where ") else {
    return nil
  }
  let valueStart = whereIndex + 7
  let valueEnd = swiftmutTopLevelByteIndex(bytes, start: valueStart, end: end, byte: 123) ?? end
  return (valueStart, valueEnd)
}

func swiftmutParenthesizedControlConditionRange(
  bytes: [UInt8],
  open: Int,
  end: Int
) -> (start: Int, end: Int)? {
  guard open < end,
        bytes[open] == 40,
        let close = swiftmutBalancedExpressionEnd(
          in: bytes,
          openIndex: open,
          close: 41,
          lineEnd: end
        ) else {
    return nil
  }
  return (open + 1, close - 1)
}

func swiftmutSourceLineLooksLikeExplicitCondition(_ line: String) -> Bool {
  let bytes = Array(line.utf8)
  var start = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
  guard start < bytes.count else {
    return false
  }

  if bytes[start] == 125 {
    start = swiftmutSkipHorizontalWhitespace(bytes, from: start + 1)
    if swiftmutASCIIHasPrefix(bytes, start: start, prefix: "else ") {
      start = swiftmutSkipHorizontalWhitespace(bytes, from: start + 5)
    }
  }

  if swiftmutSourceLineLooksLikeOptionalBindingCondition(bytes: bytes, start: start) {
    return false
  }

  return swiftmutASCIIHasPrefix(bytes, start: start, prefix: "if ")
    || swiftmutASCIIHasPrefix(bytes, start: start, prefix: "if(")
    || swiftmutASCIIHasPrefix(bytes, start: start, prefix: "guard ")
    || swiftmutASCIIHasPrefix(bytes, start: start, prefix: "guard(")
    || swiftmutASCIIHasPrefix(bytes, start: start, prefix: "while ")
    || swiftmutASCIIHasPrefix(bytes, start: start, prefix: "while(")
    || swiftmutASCIIHasPrefix(bytes, start: start, prefix: "for ")
    || swiftmutASCIIHasPrefix(bytes, start: start, prefix: "for(")
}

func swiftmutSourceLineLooksLikeOptionalBindingCondition(bytes: [UInt8], start: Int) -> Bool {
  swiftmutASCIIHasPrefix(bytes, start: start, prefix: "if let ")
    || swiftmutASCIIHasPrefix(bytes, start: start, prefix: "if var ")
    || swiftmutASCIIHasPrefix(bytes, start: start, prefix: "guard let ")
    || swiftmutASCIIHasPrefix(bytes, start: start, prefix: "guard var ")
}

func swiftmutReturnSourceLooksLikeStatement(
  file: String,
  line: Int,
  config: SwiftmutConfig
) -> Bool {
  guard let sourceLine = swiftmutSourceLine(file: file, line: line, config: config) else {
    return true
  }
  let bytes = Array(sourceLine.utf8)
  let start = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
  return swiftmutASCIIHasExactPrefix(bytes, start: start, prefix: "return ")
}

func swiftmutVoidCallSourceLooksLikeStatement(
  file: String,
  line: Int,
  config: SwiftmutConfig
) -> Bool {
  guard let sourceLine = swiftmutSourceLine(file: file, line: line, config: config) else {
    return true
  }
  return swiftmutSourceLineLooksLikeVoidCallStatement(sourceLine)
}

func swiftmutSourceLineLooksLikeVoidCallStatement(_ line: String) -> Bool {
  let bytes = Array(line.utf8)
  let start = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
  let end = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  guard start < end else {
    return false
  }

  let nonStatementPrefixes = [
    "let ", "var ", "return ", "if ", "if(", "guard ", "guard(",
    "while ", "while(", "for ", "for(", "switch ", "catch ",
    "public ", "private ", "internal ", "fileprivate ", "open ",
    "static ", "func ", "init(", "deinit", ".", "}", ")", "]"
  ]
  for prefix in nonStatementPrefixes {
    if swiftmutASCIIHasPrefix(bytes, start: start, prefix: prefix) {
      return false
    }
  }
  if swiftmutASCIIContains(bytes, start: start, end: end, pattern: " = ") {
    return false
  }
  if swiftmutSourceLineLooksLikeArgumentLabel(bytes: bytes, start: start, end: end) {
    return false
  }
  if swiftmutASCIIContains(bytes, start: start, end: end, pattern: ":")
      && !swiftmutASCIIContains(bytes, start: start, end: end, pattern: "(") {
    return false
  }
  return swiftmutASCIIContains(bytes, start: start, end: end, pattern: "(")
}

func swiftmutSourceLineLooksLikeArgumentLabel(bytes: [UInt8], start: Int, end: Int) -> Bool {
  var colonIndex: Int?
  var index = start
  while index < end {
    if bytes[index] == 58 {
      colonIndex = index
      break
    }
    index += 1
  }
  guard let colonIndex else {
    return false
  }

  var labelEnd = colonIndex
  while labelEnd > start && swiftmutIsHorizontalWhitespace(bytes[labelEnd - 1]) {
    labelEnd -= 1
  }
  guard start < labelEnd else {
    return false
  }
  for labelIndex in start..<labelEnd {
    guard swiftmutIsASCIILetterNumberOrUnderscore(bytes[labelIndex]) else {
      return false
    }
  }
  return true
}
