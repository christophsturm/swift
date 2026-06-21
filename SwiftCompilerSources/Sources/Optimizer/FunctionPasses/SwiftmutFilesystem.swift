//===--- SwiftmutFilesystem.swift ----------------------------------------------===//
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

func swiftmutSourceLookupCache(config: SwiftmutConfig) -> SwiftmutSourceLookupCache {
  SwiftmutSupport.swiftmutSharedSourceLookupCache(config: config)
}

func swiftmutSwiftSourcePaths(config: SwiftmutConfig) -> [String] {
  swiftmutSourceLookupCache(config: config).swiftSourcePaths()
}

func swiftmutPathIsIncluded(
  _ path: String,
  config: SwiftmutConfig
) -> Bool {
  SwiftmutSupport.swiftmutPathIsIncluded(path, config: config)
}

func swiftmutPathIsConfiguredSource(
  _ path: String,
  config: SwiftmutConfig
) -> Bool {
  SwiftmutSupport.swiftmutPathIsConfiguredSource(path, config: config)
}

func swiftmutIncludedSourcePath(
  _ path: String,
  config: SwiftmutConfig
) -> String? {
  swiftmutSourceLookupCache(config: config).includedSourcePath(path)
}

func swiftmutTrimPackageRoot(
  _ path: String,
  config: SwiftmutConfig
) -> String {
  swiftmutSourceLookupCache(config: config).trimPackageRoot(path)
}

func swiftmutCreateParentDirectories(forFile path: String) {
  SwiftmutSupport.swiftmutCreateParentDirectories(forFile: path)
}

func swiftmutRead(_ path: String) -> String? {
  SwiftmutSupport.swiftmutCachedRead(path)
}

func swiftmutShouldRecordSourceLocationMissSample(_ samples: inout Int) -> Bool {
  SwiftmutSupport.swiftmutShouldRecordSourceLocationMissSample(&samples)
}

func swiftmutWrite(
  _ text: String,
  to path: String,
  append: Bool
) {
  SwiftmutSupport.swiftmutWrite(text, to: path, append: append)
}
