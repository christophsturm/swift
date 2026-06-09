//===--- SwiftmutSourceLines.swift ---------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2026 swiftmut contributors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

func swiftmutNumberedSourceLines(_ text: String) -> [(number: Int, text: String)] {
  var result: [(number: Int, text: String)] = []
  var currentLine = 1
  var lineStart = text.startIndex
  var index = text.startIndex
  while index < text.endIndex {
    if text[index] == "\n" {
      result.append((currentLine, String(text[lineStart..<index])))
      currentLine += 1
      lineStart = text.index(after: index)
    }
    index = text.index(after: index)
  }
  if lineStart < text.endIndex || text.isEmpty {
    result.append((currentLine, String(text[lineStart..<text.endIndex])))
  }
  return result
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
  guard let matchedPath = swiftmutIncludedSourcePath(path, config: config) else {
    return nil
  }

  return swiftmutAbsoluteSourceLine(path: matchedPath, line: line)
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
