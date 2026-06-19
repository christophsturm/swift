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
  swiftmutSourceLookupCache(config: config).functionSourceLocation(
    in: function.location.description)
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
  return swiftmutSourceLookupCache(config: config).sourceLineBelongsToFunction(
    line,
    path: path,
    functionLocation: functionLocation)
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
