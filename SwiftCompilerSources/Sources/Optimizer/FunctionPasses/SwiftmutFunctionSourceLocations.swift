//===--- SwiftmutFunctionSourceLocations.swift ---------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2026 swiftmut contributors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

import SIL

func swiftmutFunctionSourceLocation(
  for function: Function,
  config: SwiftmutConfig
) -> (path: String, line: Int)? {
  let location = function.location.description
  for path in swiftmutSwiftSourcePaths(config: config) {
    guard location.contains(path),
          let line = swiftmutPreferredLine(in: location, path: path) else {
      continue
    }
    return (path, line)
  }
  return nil
}

func swiftmutSourceLineBelongsToFunction(
  _ line: Int,
  path: String,
  function: Function,
  config: SwiftmutConfig
) -> Bool {
  guard let functionLocation = swiftmutFunctionSourceLocation(for: function, config: config),
        functionLocation.path == path else {
    return true
  }
  guard line >= functionLocation.line else {
    return false
  }
  guard let text = swiftmutRead(path) else {
    return true
  }

  var currentLine = 1
  var lineStart = text.startIndex
  var index = text.startIndex
  var braceDepth = 0
  var sawOpeningBrace = false

  func inspectLine(_ lineText: String, lineNumber: Int) -> Bool? {
    guard lineNumber >= functionLocation.line else {
      return nil
    }
    if lineNumber == line {
      return true
    }
    for byte in lineText.utf8 {
      if byte == 123 {
        braceDepth += 1
        sawOpeningBrace = true
      } else if byte == 125 {
        braceDepth -= 1
      }
    }
    if sawOpeningBrace && braceDepth <= 0 {
      return false
    }
    return nil
  }

  while index < text.endIndex {
    if text[index] == "\n" {
      if let result = inspectLine(String(text[lineStart..<index]), lineNumber: currentLine) {
        return result
      }
      currentLine += 1
      lineStart = text.index(after: index)
    }
    index = text.index(after: index)
  }
  return inspectLine(String(text[lineStart..<text.endIndex]), lineNumber: currentLine) ?? true
}

func swiftmutSourceLocationBelongsToFunction(
  _ location: (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String),
  function: Function,
  config: SwiftmutConfig
) -> Bool {
  let path: String
  if location.file.hasPrefix("/") || config.packageRoot.isEmpty {
    path = location.file
  } else {
    path = config.packageRoot + "/" + location.file
  }
  guard let matchedPath = swiftmutIncludedSourcePath(path, config: config) else {
    return true
  }
  return swiftmutSourceLineBelongsToFunction(
    location.line,
    path: matchedPath,
    function: function,
    config: config
  )
}
