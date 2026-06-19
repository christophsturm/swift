//===--- SwiftmutSourceLookup.swift ---------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2026 swiftmut contributors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

public final class SwiftmutSourceLookupCache {
  public let config: SwiftmutConfig

  private var sourcePaths: [String]?
  private var sourcePathSet: Set<String>?
  private var sourceTextByPath: [String: String] = [:]

  public init(config: SwiftmutConfig) {
    self.config = config
  }

  public func swiftSourcePaths() -> [String] {
    if let sourcePaths {
      return sourcePaths
    }
    var computed: [String] = []
    for path in config.sourceFiles {
      if pathIsIncludedConfiguredSource(path) {
        computed.append(path)
      }
    }
    sourcePaths = computed
    return computed
  }

  public func includedSourcePath(_ path: String) -> String? {
    if pathIsIncluded(path) {
      return path
    }
    let suffix = path.hasPrefix("/") ? path : "/" + path
    for sourceFile in config.sourceFiles {
      if sourceFile.hasSuffix(suffix),
         pathIsIncludedConfiguredSource(sourceFile) {
        return sourceFile
      }
    }
    return nil
  }

  public func trimPackageRoot(_ path: String) -> String {
    swiftmutTrimPackageRoot(path, config: config)
  }

  public func read(_ path: String) -> String? {
    guard let sourcePath = includedSourcePath(path) else {
      return swiftmutRead(path)
    }
    if let cached = sourceTextByPath[sourcePath] {
      return cached
    }
    guard let text = swiftmutRead(sourcePath) else {
      return nil
    }
    sourceTextByPath[sourcePath] = text
    return text
  }

  public func functionSourceLocation(
    in locationDescription: String
  ) -> (path: String, line: Int)? {
    if let direct = directFunctionSourceLocation(in: locationDescription) {
      return direct
    }
    for path in swiftSourcePaths() {
      guard locationDescription.contains(path),
            let line = swiftmutPreferredLine(in: locationDescription, path: path) else {
        continue
      }
      return (path, line)
    }
    return nil
  }

  private func directFunctionSourceLocation(
    in locationDescription: String
  ) -> (path: String, line: Int)? {
    guard !config.packageRoot.isEmpty else {
      return nil
    }

    let locationBytes = Array(locationDescription.utf8)
    let rootBytes = Array(config.packageRoot.utf8)
    guard let rootIndex = swiftmutFind(rootBytes, in: locationBytes, startingAt: 0) else {
      return nil
    }

    var pathEnd = rootIndex + rootBytes.count
    while pathEnd < locationBytes.count && locationBytes[pathEnd] != 58 {
      pathEnd += 1
    }

    guard pathEnd < locationBytes.count else {
      return nil
    }

    let candidate = String(decoding: locationBytes[rootIndex..<pathEnd], as: UTF8.self)
    guard let includedPath = includedSourcePath(candidate),
          let line = swiftmutLineNumber(in: locationBytes, afterPathEnd: pathEnd) else {
      return nil
    }
    return (includedPath, line)
  }

  private func swiftmutLineNumber(in locationBytes: [UInt8], afterPathEnd pathEnd: Int) -> Int? {
    guard pathEnd < locationBytes.count, locationBytes[pathEnd] == 58 else {
      return nil
    }
    var index = pathEnd + 1
    var value = 0
    var hasDigit = false
    while index < locationBytes.count {
      let byte = locationBytes[index]
      guard byte >= 48 && byte <= 57 else {
        break
      }
      value = value * 10 + Int(byte - 48)
      hasDigit = true
      index += 1
    }
    return hasDigit ? value : nil
  }

  private func configuredSourcePaths() -> Set<String> {
    if let sourcePathSet {
      return sourcePathSet
    }
    let computed = Set(config.sourceFiles)
    sourcePathSet = computed
    return computed
  }

  private func pathIsIncluded(_ path: String) -> Bool {
    if !config.packageRoot.isEmpty && !path.hasPrefix(config.packageRoot + "/") {
      return false
    }
    if !config.sourceFiles.isEmpty && !configuredSourcePaths().contains(path) {
      return false
    }
    return pathIsIncludedConfiguredSource(path)
  }

  private func pathIsIncludedConfiguredSource(_ path: String) -> Bool {
    if !config.packageRoot.isEmpty && !path.hasPrefix(config.packageRoot + "/") {
      return false
    }
    for fragment in config.excludePathFragments {
      if path.contains(fragment) {
        return false
      }
    }
    return true
  }

  public func sourceLineBelongsToFunction(
    _ line: Int,
    path: String,
    functionLocation: (path: String, line: Int)?
  ) -> Bool {
    guard let functionLocation,
          functionLocation.path == path else {
      return true
    }
    guard line >= functionLocation.line else {
      return false
    }
    guard let text = read(path) else {
      return true
    }
    return swiftmutSourceLineBelongsToFunction(
      line,
      functionLocationLine: functionLocation.line,
      text: text)
  }
}

public func swiftmutFunctionSourceLocation(
  in locationDescription: String,
  config: SwiftmutConfig
) -> (path: String, line: Int)? {
  SwiftmutSourceLookupCache(config: config).functionSourceLocation(in: locationDescription)
}

public func swiftmutPreferredLine(in location: String, path: String) -> Int? {
  let locationBytes = Array(location.utf8)
  let pathBytes = Array(path.utf8)
  guard let pathIndex = swiftmutFind(pathBytes, in: locationBytes, startingAt: 0) else {
    return nil
  }
  var index = pathIndex + pathBytes.count
  guard index < locationBytes.count, locationBytes[index] == 58 else {
    return nil
  }
  index += 1
  var value = 0
  var hasDigit = false
  while index < locationBytes.count {
    let byte = locationBytes[index]
    guard byte >= 48 && byte <= 57 else {
      break
    }
    value = value * 10 + Int(byte - 48)
    hasDigit = true
    index += 1
  }
  return hasDigit ? value : nil
}

public func swiftmutSourceLineBelongsToFunction(
  _ line: Int,
  functionLocationLine: Int,
  text: String
) -> Bool {
  var currentLine = 1
  var lineStart = text.startIndex
  var index = text.startIndex
  var braceDepth = 0
  var sawOpeningBrace = false

  func inspectLine(_ lineText: String, lineNumber: Int) -> Bool? {
    guard lineNumber >= functionLocationLine else {
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

private var swiftmutSharedSourceLookupCacheStorage: SwiftmutSourceLookupCache?
private var swiftmutSharedSourceLookupCacheSignature: String?

public func swiftmutSharedSourceLookupCache(config: SwiftmutConfig) -> SwiftmutSourceLookupCache {
  let signature = swiftmutSourceLookupCacheSignature(config: config)
  if let cache = swiftmutSharedSourceLookupCacheStorage,
     signature == swiftmutSharedSourceLookupCacheSignature {
    return cache
  }
  let cache = SwiftmutSourceLookupCache(config: config)
  swiftmutSharedSourceLookupCacheStorage = cache
  swiftmutSharedSourceLookupCacheSignature = signature
  return cache
}

public func swiftmutCachedRead(_ path: String) -> String? {
  if let cache = swiftmutSharedSourceLookupCacheStorage {
    return cache.read(path)
  }
  return swiftmutRead(path)
}

public func swiftmutResetSourceLookupCache() {
  swiftmutSharedSourceLookupCacheStorage = nil
  swiftmutSharedSourceLookupCacheSignature = nil
}

private func swiftmutSourceLookupCacheSignature(config: SwiftmutConfig) -> String {
  var signature = config.packageRoot
  signature += "\u{0}"
  signature += config.sourceFiles.joined(separator: "\u{0}")
  signature += "\u{0}"
  signature += config.excludePathFragments.joined(separator: "\u{0}")
  return signature
}
