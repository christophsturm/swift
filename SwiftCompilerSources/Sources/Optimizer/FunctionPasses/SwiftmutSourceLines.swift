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

import SwiftmutSupport

func swiftmutNumberedSourceLines(_ text: String) -> [(number: Int, text: String)] {
  SwiftmutSupport.swiftmutNumberedSourceLines(text)
}

func swiftmutNumberedSourceLines(path: String) -> [(number: Int, text: String)]? {
  SwiftmutSupport.swiftmutCachedNumberedSourceLines(path: path)
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
  guard line > 0 else {
    return nil
  }
  return SwiftmutSupport.swiftmutCachedSourceLine(path: path, line: line)
}
