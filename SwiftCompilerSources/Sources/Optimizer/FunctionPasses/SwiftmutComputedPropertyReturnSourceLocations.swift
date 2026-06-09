//===--- SwiftmutComputedPropertyReturnSourceLocations.swift -------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2026 swiftmut contributors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

func swiftmutReturnSourceLocationCandidateIsUsable(
  _ location: (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String),
  functionName: String,
  path: String,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> Bool {
  swiftmutReturnSourceLocationIsUsableForFunction(
    location,
    functionName: functionName,
    path: path,
    mutation: mutation,
    config: config
  )
}

func swiftmutReturnSourceLocationIsUsableForFunction(
  _ location: (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String),
  functionName: String,
  path: String,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> Bool {
  if location.sourceOriginal == mutation.sourceOriginal {
    guard swiftmutReturnSourceLocationIsUsable(location, mutation: mutation, config: config) else {
      return false
    }
  }
  guard functionName.hasSuffix("vg"),
        let text = swiftmutRead(path),
        let sourceProperty = swiftmutComputedPropertyName(containingLine: location.line, in: text) else {
    return true
  }
  return swiftmutFunctionName(functionName, containsPropertyName: sourceProperty)
}

func swiftmutFindComputedPropertyReturnSourceLocation(
  functionName: String,
  path: String,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard functionName.hasSuffix("vg"),
        let text = swiftmutRead(path) else {
    return nil
  }

  var matches: [(line: Int, column: Int, sourceOriginal: String, sourceMutated: String)] = []
  var active: (name: String, braceDepth: Int)?
  var currentLine = 1
  var lineStart = text.startIndex
  var index = text.startIndex

  func inspectLine(_ lineText: String, line: Int) {
    if let property = active,
       swiftmutFunctionName(functionName, containsPropertyName: property.name),
       let expression = swiftmutComputedPropertyReturnExpression(lineText, mutation: mutation) {
      matches.append((line, expression.column, expression.sourceOriginal, expression.sourceMutated))
    }

    if active == nil,
       let declaration = swiftmutComputedPropertyDeclaration(lineText) {
      active = (declaration.name, swiftmutSourceBraceDelta(lineText))
    } else if let property = active {
      active = (property.name, property.braceDepth + swiftmutSourceBraceDelta(lineText))
    }

    if let property = active,
       property.braceDepth <= 0 {
      active = nil
    }
  }

  while index < text.endIndex {
    if text[index] == "\n" {
      inspectLine(String(text[lineStart..<index]), line: currentLine)
      if matches.count > 1 {
        break
      }
      currentLine += 1
      lineStart = text.index(after: index)
    }
    index = text.index(after: index)
  }
  if index == text.endIndex {
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

func swiftmutComputedPropertyName(containingLine targetLine: Int, in text: String) -> String? {
  var active: (name: String, braceDepth: Int)?
  var currentLine = 1
  var lineStart = text.startIndex
  var index = text.startIndex

  func inspectLine(_ lineText: String, line: Int) -> String? {
    if let property = active,
       line == targetLine {
      return property.name
    }

    if active == nil,
       let declaration = swiftmutComputedPropertyDeclaration(lineText) {
      active = (declaration.name, swiftmutSourceBraceDelta(lineText))
    } else if let property = active {
      active = (property.name, property.braceDepth + swiftmutSourceBraceDelta(lineText))
    }

    if let property = active,
       line == targetLine {
      return property.name
    }
    if let property = active,
       property.braceDepth <= 0 {
      active = nil
    }
    return nil
  }

  while index < text.endIndex {
    if text[index] == "\n" {
      if let name = inspectLine(String(text[lineStart..<index]), line: currentLine) {
        return name
      }
      currentLine += 1
      lineStart = text.index(after: index)
    }
    index = text.index(after: index)
  }
  return inspectLine(String(text[lineStart..<text.endIndex]), line: currentLine)
}

func swiftmutComputedPropertyDeclaration(_ line: String) -> (name: String, column: Int)? {
  let bytes = Array(line.utf8)
  let lineStart = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
  let lineEnd = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  guard lineStart < lineEnd,
        let keyword = swiftmutPropertyDeclarationKeyword(bytes: bytes, start: lineStart, end: lineEnd) else {
    return nil
  }
  let nameStart = swiftmutSkipHorizontalWhitespace(bytes, from: keyword.end)
  guard nameStart < lineEnd,
        swiftmutIsASCIIIdentifierStart(bytes[nameStart]) else {
    return nil
  }
  var nameEnd = nameStart + 1
  while nameEnd < lineEnd && swiftmutIsASCIILetterNumberOrUnderscore(bytes[nameEnd]) {
    nameEnd += 1
  }
  guard swiftmutTopLevelByteIndex(bytes, start: nameEnd, end: lineEnd, byte: 123) != nil else {
    return nil
  }
  return (String(decoding: bytes[nameStart..<nameEnd], as: UTF8.self), nameStart + 1)
}

func swiftmutComputedPropertyReturnExpression(
  _ line: String,
  mutation: SwiftmutMutation
) -> (column: Int, sourceOriginal: String, sourceMutated: String)? {
  let bytes = Array(line.utf8)
  let lineStart = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
  let lineEnd = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  guard lineStart < lineEnd else {
    return nil
  }
  let expressionStart: Int
  if swiftmutASCIIHasExactPrefix(bytes, start: lineStart, prefix: "return ") {
    expressionStart = swiftmutSkipHorizontalWhitespace(bytes, from: lineStart + 7)
  } else {
    expressionStart = lineStart
  }
  let sourceOriginal = String(decoding: bytes[expressionStart..<lineEnd], as: UTF8.self)
  guard swiftmutReturnValueIsEligible(bytes: bytes, start: expressionStart, mutation: mutation) else {
    return nil
  }
  return (expressionStart + 1, sourceOriginal, swiftmutImplicitReturnSourceMutation(for: mutation))
}

func swiftmutSourceBraceDelta(_ line: String) -> Int {
  var delta = 0
  for byte in line.utf8 {
    if byte == 123 {
      delta += 1
    } else if byte == 125 {
      delta -= 1
    }
  }
  return delta
}

func swiftmutFindPropertyGetterReturnSourceLocation(
  functionName: String,
  path: String,
  preferredLine: Int,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard preferredLine > 0,
        mutation.sourceOriginal == "return",
        let text = swiftmutRead(path) else {
    return nil
  }

  if let exact = swiftmutPropertyGetterReturnSourceLocation(
    in: text,
    functionName: functionName,
    path: path,
    lineRange: preferredLine...preferredLine,
    mutation: mutation,
    config: config
  ) {
    return exact
  }

  let firstLine = preferredLine > 1 ? preferredLine - 1 : 1
  return swiftmutPropertyGetterReturnSourceLocation(
    in: text,
    functionName: functionName,
    path: path,
    lineRange: firstLine...(preferredLine + 2),
    mutation: mutation,
    config: config
  )
}

func swiftmutPropertyGetterReturnSourceLocation(
  in text: String,
  functionName: String,
  path: String,
  lineRange: ClosedRange<Int>,
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
          let property = swiftmutStoredPropertySourceLocation(lineText, mutation: mutation) else {
      return
    }
    guard swiftmutFunctionName(functionName, containsPropertyName: property.name) else {
      return
    }
    matches.append((line, property.column, property.sourceOriginal, property.sourceMutated))
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

func swiftmutStoredPropertyDeclaration(
  _ line: String,
  mutation: SwiftmutMutation
) -> (name: String, column: Int, sourceOriginal: String, sourceMutated: String)? {
  let bytes = Array(line.utf8)
  let lineStart = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
  let lineEnd = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  guard lineStart < lineEnd,
        !swiftmutASCIIHasPrefix(bytes, start: lineStart, prefix: "case "),
        !swiftmutASCIIHasPrefix(bytes, start: lineStart, prefix: "func "),
        !swiftmutASCIIHasPrefix(bytes, start: lineStart, prefix: "init"),
        !swiftmutASCIIHasPrefix(bytes, start: lineStart, prefix: "return "),
        !swiftmutASCIIHasPrefix(bytes, start: lineStart, prefix: "//") else {
    return nil
  }

  guard let keyword = swiftmutPropertyDeclarationKeyword(bytes: bytes, start: lineStart, end: lineEnd) else {
    return nil
  }
  let nameStart = swiftmutSkipHorizontalWhitespace(bytes, from: keyword.end)
  if nameStart < lineEnd && bytes[nameStart] == 40 {
    return nil
  }
  guard nameStart < lineEnd,
        swiftmutIsASCIIIdentifierStart(bytes[nameStart]) else {
    return nil
  }
  var nameEnd = nameStart + 1
  while nameEnd < lineEnd && swiftmutIsASCIILetterNumberOrUnderscore(bytes[nameEnd]) {
    nameEnd += 1
  }
  var afterName = swiftmutSkipHorizontalWhitespace(bytes, from: nameEnd)
  guard afterName < lineEnd,
        bytes[afterName] == 58 else {
    return nil
  }
  afterName = swiftmutSkipHorizontalWhitespace(bytes, from: afterName + 1)
  guard afterName < lineEnd else {
    return nil
  }
  for index in afterName..<lineEnd {
    if bytes[index] == 123 {
      return nil
    }
  }

  let name = String(decoding: bytes[nameStart..<nameEnd], as: UTF8.self)
  return (
    name,
    nameStart + 1,
    name,
    swiftmutImplicitReturnSourceMutation(for: mutation))
}

func swiftmutFunctionName(_ functionName: String, containsPropertyName propertyName: String) -> Bool {
  guard !propertyName.isEmpty else {
    return false
  }
  return swiftmutMangledNameContainsIdentifier(functionName, identifier: propertyName)
}

func swiftmutPropertyDeclarationKeyword(bytes: [UInt8], start: Int, end: Int) -> (start: Int, end: Int)? {
  var index = start
  while index < end {
    let tokenStart = swiftmutSkipHorizontalWhitespace(bytes, from: index)
    guard tokenStart < end else {
      return nil
    }
    var tokenEnd = tokenStart
    while tokenEnd < end && swiftmutIsASCIILetterNumberOrUnderscore(bytes[tokenEnd]) {
      tokenEnd += 1
    }
    guard tokenEnd > tokenStart else {
      return nil
    }
    let token = String(decoding: bytes[tokenStart..<tokenEnd], as: UTF8.self)
    if token == "let" || token == "var" {
      return (tokenStart, tokenEnd)
    }
    if !swiftmutIsPropertyDeclarationModifier(token) {
      return nil
    }
    index = swiftmutSkipPropertyDeclarationModifierSuffix(bytes: bytes, from: tokenEnd, end: end)
  }
  return nil
}

func swiftmutSkipPropertyDeclarationModifierSuffix(bytes: [UInt8], from index: Int, end: Int) -> Int {
  guard index + 5 <= end,
        bytes[index] == 40,
        swiftmutASCIIHasExactPrefix(bytes, start: index, prefix: "(set)") else {
    return index
  }
  return index + 5
}

func swiftmutIsPropertyDeclarationModifier(_ token: String) -> Bool {
  switch token {
  case "public", "private", "internal", "fileprivate", "open", "package",
       "static", "class", "final", "lazy", "weak", "unowned", "nonisolated",
       "isolated", "mutating", "nonmutating":
    return true
  default:
    return false
  }
}
