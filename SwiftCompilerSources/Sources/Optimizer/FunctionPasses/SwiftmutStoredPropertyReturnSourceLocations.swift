//===--- SwiftmutStoredPropertyReturnSourceLocations.swift ----------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2026 swiftmut contributors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

func swiftmutFindDescribedStoredPropertyInitializerReturnSourceLocation(
  functionName: String,
  locationDescription: String,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard mutation.sourceOriginal == "return",
        swiftmutFunctionNameLooksStoredPropertyInitializer(functionName),
        let rawSnippet = swiftmutQuotedSourceSearchSnippet(locationDescription),
        rawSnippet.count >= 4 else {
    return nil
  }

  let snippet = swiftmutDecodedSourceSnippet(rawSnippet)
  guard swiftmutStoredPropertyInitializerSnippetLooksMappable(snippet) else {
    return nil
  }

  var matches: [(path: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)] = []
  for path in swiftmutSwiftSourcePaths(config: config) {
    guard let text = swiftmutRead(path) else {
      continue
    }
    for match in swiftmutSourceSnippetMatches(snippet, in: text) {
      guard let sourceLine = swiftmutSourceLine(text, line: match.line),
            let property = swiftmutStoredPropertyInitializerDeclaration(sourceLine, mutation: mutation),
            swiftmutFunctionName(functionName, containsPropertyName: property.name) else {
        continue
      }
      matches.append((path, match.line, property.column, property.sourceOriginal, property.sourceMutated))
      if matches.count > 1 {
        return nil
      }
    }
  }

  guard let match = matches.first else {
    return nil
  }
  return (
    swiftmutTrimPackageRoot(match.path, config: config),
    match.line,
    match.column,
    match.sourceOriginal,
    match.sourceMutated)
}

func swiftmutFunctionNameLooksStoredPropertyInitializer(_ functionName: String) -> Bool {
  let bytes = Array(functionName.utf8)
  guard bytes.count >= 4 else {
    return false
  }
  for index in 0...(bytes.count - 4) {
    if bytes[index] == 118,
       bytes[index + 1] == 112,
       bytes[index + 2] == 102,
       bytes[index + 3] == 105 {
      return true
    }
  }
  return false
}

func swiftmutStoredPropertyInitializerSnippetLooksMappable(_ snippet: String) -> Bool {
  let bytes = Array(snippet.utf8)
  guard bytes.count >= 4 else {
    return false
  }
  for byte in bytes where byte == 10 || byte == 13 {
    return false
  }
  return true
}

func swiftmutStoredPropertySourceLocation(
  _ line: String,
  mutation: SwiftmutMutation
) -> (name: String, column: Int, sourceOriginal: String, sourceMutated: String)? {
  if let initializer = swiftmutStoredPropertyInitializerDeclaration(line, mutation: mutation) {
    return initializer
  }
  return swiftmutStoredPropertyDeclaration(line, mutation: mutation)
}

func swiftmutStoredPropertyInitializerDeclaration(
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
        !swiftmutASCIIHasPrefix(bytes, start: lineStart, prefix: "//"),
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
  guard let equals = swiftmutStoredPropertyInitializerEquals(bytes: bytes, start: nameEnd, end: lineEnd),
        let expression = swiftmutDefaultArgumentExpression(bytes: bytes, from: equals + 1, mutation: mutation) else {
    return nil
  }
  return (
    String(decoding: bytes[nameStart..<nameEnd], as: UTF8.self),
    expression.start + 1,
    expression.text,
    swiftmutImplicitReturnSourceMutation(for: mutation))
}

func swiftmutStoredPropertyInitializerEquals(bytes: [UInt8], start: Int, end: Int) -> Int? {
  var index = start
  var angleDepth = 0
  var squareDepth = 0
  var parenDepth = 0
  while index < end {
    let byte = bytes[index]
    if byte == 60 {
      angleDepth += 1
    } else if byte == 62 && angleDepth > 0 {
      angleDepth -= 1
    } else if byte == 91 {
      squareDepth += 1
    } else if byte == 93 && squareDepth > 0 {
      squareDepth -= 1
    } else if byte == 40 {
      parenDepth += 1
    } else if byte == 41 && parenDepth > 0 {
      parenDepth -= 1
    } else if byte == 123 {
      return nil
    } else if byte == 61 && angleDepth == 0 && squareDepth == 0 && parenDepth == 0 {
      return index
    }
    index += 1
  }
  return nil
}
