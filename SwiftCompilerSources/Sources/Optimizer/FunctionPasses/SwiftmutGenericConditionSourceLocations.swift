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
    return swiftmutMultilineGenericConditionSourceLocation(
      path: path,
      line: line,
      fallbackColumn: fallbackColumn,
      mutation: mutation,
      config: config)
  }
  return (
    swiftmutTrimPackageRoot(path, config: config),
    line,
    expression.column > 0 ? expression.column : fallbackColumn,
    expression.sourceOriginal,
    swiftmutGenericConditionSourceMutated(
      expression.sourceOriginal,
      mutation: mutation,
      config: config))
}

func swiftmutMultilineGenericConditionSourceLocation(
  path: String,
  line: Int,
  fallbackColumn: Int,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard line > 0,
        let text = swiftmutRead(path) else {
    return nil
  }
  let lines = swiftmutNumberedSourceLines(text)
  guard line <= lines.count else {
    return nil
  }
  let targetIndex = line - 1
  let firstCandidateIndex = targetIndex > 8 ? targetIndex - 8 : 0

  var startIndex = targetIndex
  while startIndex >= firstCandidateIndex {
    guard swiftmutSourceLineLooksLikeExplicitCondition(lines[startIndex].text),
          let statement = swiftmutMultilineConditionStatement(
            lines: lines,
            startIndex: startIndex,
            targetIndex: targetIndex
          ),
          let expression = swiftmutGenericConditionExpression(statement.text) else {
      if startIndex == 0 {
        break
      }
      startIndex -= 1
      continue
    }
    guard expression.sourceOriginal.contains("("),
          !swiftmutGenericConditionSourceContainsTopLevelLogicalOperator(expression.sourceOriginal) else {
      return nil
    }
    return (
      swiftmutTrimPackageRoot(path, config: config),
      lines[startIndex].number,
      expression.column > 0 ? expression.column : fallbackColumn,
      expression.sourceOriginal,
      swiftmutGenericConditionSourceMutated(
        expression.sourceOriginal,
        mutation: mutation,
        config: config))
  }
  return nil
}

func swiftmutMultilineConditionStatement(
  lines: [(number: Int, text: String)],
  startIndex: Int,
  targetIndex: Int
) -> (line: Int, text: String, endIndex: Int)? {
  var parts: [String] = []
  var index = startIndex
  while index < lines.count && index <= startIndex + 12 {
    let lineText = lines[index].text
    parts.append(index == startIndex ? lineText : swiftmutTrimmedHorizontalWhitespace(lineText))
    if swiftmutLineContainsTopLevelOpeningBrace(lineText) {
      guard index >= targetIndex else {
        return nil
      }
      return (lines[startIndex].number, parts.joined(separator: " "), index)
    }
    index += 1
  }
  return nil
}

func swiftmutFindUniqueMultilineExplicitConditionSourceLocation(
  path: String,
  preferredLine: Int,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard preferredLine > 0,
        let text = swiftmutRead(path) else {
    return nil
  }
  let lines = swiftmutNumberedSourceLines(text)
  var matches: [(line: Int, column: Int, sourceOriginal: String)] = []
  var index = 0
  while index < lines.count {
    let line = lines[index].number
    if line >= preferredLine,
       line <= preferredLine + 120,
       swiftmutSourceLineLooksLikeExplicitCondition(lines[index].text),
       let statement = swiftmutMultilineConditionStatement(
        lines: lines,
        startIndex: index,
        targetIndex: index
       ),
       statement.endIndex > index,
       let expression = swiftmutGenericConditionExpression(statement.text),
       expression.sourceOriginal.contains("("),
       !swiftmutGenericConditionSourceContainsTopLevelLogicalOperator(expression.sourceOriginal) {
      matches.append((line, expression.column, expression.sourceOriginal))
      if matches.count >= 2 {
        break
      }
      index = statement.endIndex
    }
    if line > preferredLine + 120 {
      break
    }
    index += 1
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
    swiftmutGenericConditionSourceMutated(
      match.sourceOriginal,
      mutation: mutation,
      config: config))
}

func swiftmutTrimmedHorizontalWhitespace(_ text: String) -> String {
  let bytes = Array(text.utf8)
  let start = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
  let end = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  guard start < end else {
    return ""
  }
  return String(decoding: bytes[start..<end], as: UTF8.self)
}

func swiftmutLineContainsTopLevelOpeningBrace(_ line: String) -> Bool {
  let bytes = Array(line.utf8)
  let start = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
  let end = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  return swiftmutTopLevelByteIndex(bytes, start: start, end: end, byte: 123) != nil
}

func swiftmutGenericConditionSourceContainsTopLevelLogicalOperator(_ source: String) -> Bool {
  let bytes = Array(source.utf8)
  let end = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  let start = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
  return swiftmutTopLevelLogicalOperatorIndex(bytes: bytes, start: start, end: end) != nil
}

func swiftmutMultilineGenericConditionSourceIsExplicit(
  file: String,
  line: Int,
  config: SwiftmutConfig
) -> Bool {
  guard line > 0 else {
    return false
  }

  let path: String
  if file.hasPrefix("/") || config.packageRoot.isEmpty {
    path = file
  } else {
    path = config.packageRoot + "/" + file
  }
  guard let matchedPath = swiftmutIncludedSourcePath(path, config: config),
        let text = swiftmutRead(matchedPath) else {
    return false
  }
  let lines = swiftmutNumberedSourceLines(text)
  guard line <= lines.count else {
    return false
  }
  let targetIndex = line - 1
  let firstCandidateIndex = targetIndex > 8 ? targetIndex - 8 : 0
  var startIndex = targetIndex
  while startIndex >= firstCandidateIndex {
    if swiftmutSourceLineLooksLikeExplicitCondition(lines[startIndex].text),
       let statement = swiftmutMultilineConditionStatement(
        lines: lines,
        startIndex: startIndex,
        targetIndex: targetIndex
       ),
       let expression = swiftmutGenericConditionExpression(statement.text),
       expression.sourceOriginal.contains("("),
       !swiftmutGenericConditionSourceContainsTopLevelLogicalOperator(expression.sourceOriginal) {
      return true
    }
    if startIndex == 0 {
      break
    }
    startIndex -= 1
  }
  return false
}

func swiftmutCanUseComparisonOrdinalSourceLocation(count: Int) -> Bool {
  count > 0 && count <= 64
}

func swiftmutSourceLocation(
  for instruction: Instruction,
  function: Function,
  moduleName: String,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  func usableConditionSourceLocation(
    _ location: (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)
  ) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
    if swiftmutSourceLocationBelongsToFunction(location, function: function, config: config) {
      return location
    }
    return nil
  }

  let completeExpressionLocation: (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)?
  if let comparison = instruction as? BuiltinInst,
     swiftmutIsComparisonBuiltin(comparison),
     let ordinal = swiftmutComparisonOrdinalAndCount(for: comparison, in: function),
     swiftmutCanUseComparisonOrdinalSourceLocation(count: ordinal.count),
     let located = swiftmutFindOrdinalSourceOperator(
       moduleName: moduleName,
       functionLocation: function.location.description,
       ordinal: ordinal.ordinal,
       expectedCount: ordinal.count,
       mutation: mutation,
       config: config) {
    completeExpressionLocation = located
  } else if let located = swiftmutFindSourceOperator(
    moduleName: moduleName,
    functionLocation: function.location.description,
    mutation: mutation,
    config: config) {
    completeExpressionLocation = located
  } else if let located = swiftmutFindDescribedSourceOperator(
    moduleName: moduleName,
    functionLocation: function.location.description,
    locationDescription: instruction.location.description,
    mutation: mutation,
    config: config) {
    completeExpressionLocation = located
  } else {
    completeExpressionLocation = nil
  }

  if let fileNameAndPosition = instruction.location.fileNameAndPosition {
    let path = fileNameAndPosition.path.string
    guard let matchedPath = swiftmutIncludedSourcePath(path, config: config) else {
      return nil
    }
    if let completeExpressionLocation,
       completeExpressionLocation.file == swiftmutTrimPackageRoot(matchedPath, config: config),
       completeExpressionLocation.line == fileNameAndPosition.line {
      return usableConditionSourceLocation(completeExpressionLocation)
    }
    return usableConditionSourceLocation((
      swiftmutTrimPackageRoot(matchedPath, config: config),
      fileNameAndPosition.line,
      fileNameAndPosition.column,
      "",
      ""))
  }

  if let completeExpressionLocation {
    return usableConditionSourceLocation(completeExpressionLocation)
  }

  if mutation.sourceOriginal == "condition" {
    for path in swiftmutSwiftSourcePaths(config: config) {
      guard function.location.description.contains(path),
            let line = swiftmutPreferredLine(in: function.location.description, path: path),
            let located = swiftmutFindClosureArgumentConditionSourceLocation(
              path: path,
              preferredLine: line,
              mutation: mutation,
              config: config
            ) else {
        continue
      }
      return usableConditionSourceLocation(located)
    }
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
  func usableConditionSourceLocation(
    _ location: (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)
  ) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
    if swiftmutSourceLocationBelongsToFunction(location, function: function, config: config) {
      return location
    }
    return nil
  }

  if let functionSourceLocation = swiftmutFunctionSourceLocation(for: function, config: config),
     let located = swiftmutFindUniqueExplicitConditionSourceLocation(
       path: functionSourceLocation.path,
       preferredLine: functionSourceLocation.line,
       mutation: mutation,
       config: config
     ) {
    return usableConditionSourceLocation(located)
  }
  if let located = swiftmutFindOrdinalExplicitConditionSourceLocation(
    moduleName: moduleName,
    function: function,
    branch: branch,
    comparison: comparison,
    mutation: mutation,
    config: config
  ) {
    return usableConditionSourceLocation(located)
  }
  if let located = swiftmutFindBooleanNegatedConditionSourceLocation(
    moduleName: moduleName,
    functionLocation: function.location.description,
    locationDescription: branch.location.description,
    mutation: mutation,
    config: config
  ) {
    return usableConditionSourceLocation(located)
  }
  if mutation.sourceOriginal == "condition",
     let located = swiftmutFindDescribedGenericConditionSourceLocation(
       moduleName: moduleName,
       functionLocation: function.location.description,
       locationDescription: branch.location.description,
       mutation: mutation,
       config: config
     ) {
    return usableConditionSourceLocation(located)
  }
  if let located = swiftmutFindDescribedSourceOperator(
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
    config: config) {
    return usableConditionSourceLocation(located)
  }
  return nil
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
    || swiftmutMultilineGenericConditionSourceIsExplicit(file: file, line: line, config: config)
}

func swiftmutGenericConditionSourceLocationIsExplicit(
  _ location: (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String),
  config: SwiftmutConfig
) -> Bool {
  if swiftmutGenericConditionSourceIsExplicit(file: location.file, line: location.line, config: config) {
    return true
  }
  guard let sourceLine = swiftmutSourceLine(file: location.file, line: location.line, config: config) else {
    return true
  }
  return swiftmutGenericConditionExpressionCandidates(sourceLine).contains {
    $0.sourceOriginal == location.sourceOriginal
  }
}

func swiftmutGenericConditionSourceMutated(
  _ sourceOriginal: String,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> String {
  guard mutation.sourceOriginal != "condition" else {
    return mutation.sourceMutated
  }
  if let sourceMutated = swiftmutGenericConditionSourceMutationText(
    sourceOriginal,
    mutation: mutation,
    config: config
  ) {
    return sourceMutated
  }
  for rule in swiftmutSourceMutationDisplayRules(for: mutation, config: config) {
    let sourceMutated = rule.sourceMutatedOverride.isEmpty
      ? rule.sourceMutated
      : rule.sourceMutatedOverride
    if let mutated = swiftmutReplaceFirstSourceOperator(
      rule.sourceOriginal,
      with: sourceMutated,
      in: sourceOriginal
    ) {
      return mutated
    }
  }
  return mutation.sourceMutated
}

func swiftmutReplaceFirstSourceOperator(
  _ sourceOriginal: String,
  with sourceMutated: String,
  in expression: String
) -> String? {
  let bytes = Array(expression.utf8)
  let operatorBytes = Array(sourceOriginal.utf8)
  guard !operatorBytes.isEmpty,
        bytes.count >= operatorBytes.count else {
    return nil
  }

  var index = 0
  while index + operatorBytes.count <= bytes.count {
    var matched = true
    for offset in 0..<operatorBytes.count where bytes[index + offset] != operatorBytes[offset] {
      matched = false
      break
    }
    if matched,
       swiftmutIsSourceComparisonOperator(
        bytes: bytes,
        operatorStart: index,
        operatorEnd: index + operatorBytes.count
       ) {
      let prefix = String(decoding: bytes[0..<index], as: UTF8.self)
      let suffix = String(decoding: bytes[(index + operatorBytes.count)..<bytes.count], as: UTF8.self)
      return prefix + sourceMutated + suffix
    }
    index += 1
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
  } else if swiftmutASCIIHasPrefix(bytes, start: start, prefix: "case ") {
    expressionRange = swiftmutCaseWhereConditionRange(bytes: bytes, start: start, end: lineEnd)
  } else if let ternaryRange = swiftmutTernaryConditionRange(bytes: bytes, start: start, end: lineEnd) {
    expressionRange = ternaryRange
  } else {
    expressionRange = nil
  }

  guard var range = expressionRange else {
    return nil
  }
  range.start = swiftmutSkipHorizontalWhitespace(bytes, from: range.start)
  range.end = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: range.end)
  if range.end > range.start && bytes[range.end - 1] == 44 {
    return nil
  }
  guard range.start < range.end else {
    return nil
  }
  guard swiftmutSourceExpressionIsSingleLineComplete(
    bytes: bytes,
    start: range.start,
    end: range.end
  ) else {
    return nil
  }
  return (
    range.start + 1,
    String(decoding: bytes[range.start..<range.end], as: UTF8.self))
}

func swiftmutGenericConditionExpressionCandidates(
  _ line: String
) -> [(column: Int, sourceOriginal: String)] {
  if let expression = swiftmutGenericConditionExpression(line) {
    return [expression]
  }
  let optionalBindingExpressions = swiftmutOptionalBindingBooleanConditionExpressions(line)
  if !optionalBindingExpressions.isEmpty {
    return optionalBindingExpressions
  }
  return []
}

func swiftmutGenericConditionClauseExpression(
  _ line: String,
  needle: String?
) -> (column: Int, sourceOriginal: String)? {
  if let needle, !line.contains(needle) {
    return nil
  }
  let bytes = Array(line.utf8)
  var start = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
  var end = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  guard start < end else {
    return nil
  }

  let handledPrefixes = ["if ", "if(", "guard ", "guard(", "while ", "while(", "for ", "for("]
  for prefix in handledPrefixes where swiftmutASCIIHasPrefix(bytes, start: start, prefix: prefix) {
    return nil
  }
  let excludedPrefixes = [
    "public ", "private ", "internal ", "fileprivate ", "open ", "static ",
    "func ", "init(", "deinit", "struct ", "class ", "enum ", "protocol ",
    "extension ", "import ", "@"
  ]
  for prefix in excludedPrefixes where swiftmutASCIIHasPrefix(bytes, start: start, prefix: prefix) {
    return nil
  }

  if start + 1 < end
      && (bytes[start] == 38 || bytes[start] == 124)
      && bytes[start + 1] == bytes[start] {
    start = swiftmutSkipHorizontalWhitespace(bytes, from: start + 2)
  }
  guard !swiftmutConditionClauseLooksLikeBinding(bytes: bytes, start: start, end: end) else {
    return nil
  }

  if let elseIndex = swiftmutTopLevelASCIIIndex(bytes, start: start, end: end, pattern: " else ") {
    end = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: elseIndex)
  } else if let elseIndex = swiftmutTopLevelASCIIIndex(bytes, start: start, end: end, pattern: " else") {
    end = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: elseIndex)
  }
  while end > start {
    let byte = bytes[end - 1]
    if byte == 44 || byte == 123 || byte == 125 {
      end = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: end - 1)
      continue
    }
    break
  }
  guard start < end,
        !swiftmutTopLevelASCIIContains(bytes, start: start, end: end, pattern: " = "),
        swiftmutSourceExpressionIsSingleLineComplete(bytes: bytes, start: start, end: end) else {
    return nil
  }
  return (
    start + 1,
    String(decoding: bytes[start..<end], as: UTF8.self))
}

func swiftmutOptionalBindingBooleanConditionExpressions(
  _ line: String
) -> [(column: Int, sourceOriginal: String)] {
  let bytes = Array(line.utf8)
  let lineEnd = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  var start = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
  guard start < lineEnd else {
    return []
  }

  if bytes[start] == 125 {
    start = swiftmutSkipHorizontalWhitespace(bytes, from: start + 1)
    if swiftmutASCIIHasPrefix(bytes, start: start, prefix: "else ") {
      start = swiftmutSkipHorizontalWhitespace(bytes, from: start + 5)
    }
  }

  let expressionRange: (start: Int, end: Int)?
  if swiftmutASCIIHasPrefix(bytes, start: start, prefix: "if ") {
    expressionRange = swiftmutControlConditionRange(bytes: bytes, start: start + 3, end: lineEnd)
  } else if swiftmutASCIIHasPrefix(bytes, start: start, prefix: "guard ") {
    expressionRange = swiftmutGuardConditionRange(bytes: bytes, start: start + 6, end: lineEnd)
  } else if swiftmutASCIIHasPrefix(bytes, start: start, prefix: "while ") {
    expressionRange = swiftmutControlConditionRange(bytes: bytes, start: start + 6, end: lineEnd)
  } else {
    expressionRange = nil
  }
  guard let range = expressionRange else {
    return []
  }

  var result: [(column: Int, sourceOriginal: String)] = []
  for clause in swiftmutTopLevelCommaSeparatedRanges(bytes: bytes, start: range.start, end: range.end) {
    let clauseStart = swiftmutSkipHorizontalWhitespace(bytes, from: clause.start)
    let clauseEnd = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: clause.end)
    guard clauseStart < clauseEnd,
          !swiftmutConditionClauseLooksLikeBinding(bytes: bytes, start: clauseStart, end: clauseEnd),
          swiftmutSourceExpressionIsSingleLineComplete(bytes: bytes, start: clauseStart, end: clauseEnd) else {
      continue
    }
    result.append((
      clauseStart + 1,
      String(decoding: bytes[clauseStart..<clauseEnd], as: UTF8.self)))
  }
  return result
}

func swiftmutTopLevelCommaSeparatedRanges(
  bytes: [UInt8],
  start: Int,
  end: Int
) -> [(start: Int, end: Int)] {
  var result: [(start: Int, end: Int)] = []
  var clauseStart = start
  var searchStart = start
  while let comma = swiftmutTopLevelByteIndex(bytes, start: searchStart, end: end, byte: 44) {
    result.append((clauseStart, comma))
    clauseStart = comma + 1
    searchStart = comma + 1
  }
  result.append((clauseStart, end))
  return result
}

func swiftmutConditionClauseLooksLikeBinding(bytes: [UInt8], start: Int, end: Int) -> Bool {
  guard start < end else {
    return true
  }
  return swiftmutASCIIHasPrefix(bytes, start: start, prefix: "let ")
    || swiftmutASCIIHasPrefix(bytes, start: start, prefix: "var ")
    || swiftmutASCIIHasPrefix(bytes, start: start, prefix: "case ")
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

func swiftmutCaseWhereConditionRange(
  bytes: [UInt8],
  start: Int,
  end: Int
) -> (start: Int, end: Int)? {
  guard let whereIndex = swiftmutTopLevelASCIIIndex(bytes, start: start, end: end, pattern: " where ") else {
    return nil
  }
  let valueStart = whereIndex + 7
  let colonIndex = swiftmutTopLevelByteIndex(bytes, start: valueStart, end: end, byte: 58)
  let valueEnd = colonIndex ?? end
  return (valueStart, valueEnd)
}

func swiftmutTernaryConditionRange(
  bytes: [UInt8],
  start: Int,
  end: Int
) -> (start: Int, end: Int)? {
  guard let question = swiftmutTopLevelTernaryQuestionIndex(bytes: bytes, start: start, end: end),
        swiftmutTopLevelByteIndex(bytes, start: question + 1, end: end, byte: 58) != nil else {
    return nil
  }

  var conditionStart = start
  if swiftmutASCIIHasPrefix(bytes, start: conditionStart, prefix: "return ") {
    conditionStart = swiftmutSkipHorizontalWhitespace(bytes, from: conditionStart + 7)
  }
  if let assignment = swiftmutLastTopLevelAssignmentEqualsBefore(bytes: bytes, start: conditionStart, end: question) {
    conditionStart = swiftmutSkipHorizontalWhitespace(bytes, from: assignment + 1)
  }
  if let labelColon = swiftmutLastTopLevelByteBefore(bytes: bytes, start: conditionStart, end: question, byte: 58) {
    conditionStart = swiftmutSkipHorizontalWhitespace(bytes, from: labelColon + 1)
  }

  let conditionEnd = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: question)
  guard conditionStart < conditionEnd else {
    return nil
  }
  return (conditionStart, conditionEnd)
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
    || swiftmutASCIIHasPrefix(bytes, start: start, prefix: "case ")
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
    "static ", "func ", "init(", "deinit", "@", "//", "/*", ".", "}", ")", "]"
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
