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
  private enum DirectFunctionSourceLocationResult {
    case found(path: String, line: Int)
    case notPresent
    case unknown
  }

  public let config: SwiftmutConfig

  private var sourcePaths: [String]?
  private var sourcePathSet: Set<String>?
  private var sourcePathByRelativePath: [String: String]?
  private var sourceTextByPath: [String: String] = [:]
  private var functionLocationByDescription: [String: (path: String, line: Int)] = [:]
  private var missingFunctionLocationDescriptions = Set<String>()
  private var functionEndLineByPathAndStartLine: [String: [Int: Int]] = [:]
  private var packageRootBytes: [UInt8]?

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
    if !path.hasPrefix("/"),
       let sourcePath = relativeSourcePathMap()[path] {
      return sourcePath
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
    if let cached = functionLocationByDescription[locationDescription] {
      return cached
    }
    if missingFunctionLocationDescriptions.contains(locationDescription) {
      return nil
    }
    guard let location = computeFunctionSourceLocation(in: locationDescription) else {
      missingFunctionLocationDescriptions.insert(locationDescription)
      return nil
    }
    functionLocationByDescription[locationDescription] = location
    return location
  }

  private func computeFunctionSourceLocation(
    in locationDescription: String
  ) -> (path: String, line: Int)? {
    switch directFunctionSourceLocation(in: locationDescription) {
    case .found(let path, let line):
      return (path, line)
    case .notPresent:
      return nil
    case .unknown:
      break
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
  ) -> DirectFunctionSourceLocationResult {
    guard !config.packageRoot.isEmpty else {
      return .unknown
    }

    let locationBytes = Array(locationDescription.utf8)
    let rootBytes = cachedPackageRootBytes()
    guard let rootIndex = swiftmutFind(rootBytes, in: locationBytes, startingAt: 0) else {
      return .unknown
    }

    var pathEnd = rootIndex + rootBytes.count
    while pathEnd < locationBytes.count && locationBytes[pathEnd] != 58 {
      pathEnd += 1
    }

    guard pathEnd < locationBytes.count else {
      return .unknown
    }

    let candidate = String(decoding: locationBytes[rootIndex..<pathEnd], as: UTF8.self)
    guard let line = swiftmutLineNumber(in: locationBytes, afterPathEnd: pathEnd) else {
      return .unknown
    }
    guard let includedPath = exactlyIncludedSourcePath(candidate) else {
      return .notPresent
    }
    return .found(path: includedPath, line: line)
  }

  private func cachedPackageRootBytes() -> [UInt8] {
    if let packageRootBytes {
      return packageRootBytes
    }
    let computed = Array(config.packageRoot.utf8)
    packageRootBytes = computed
    return computed
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

  private func relativeSourcePathMap() -> [String: String] {
    if let sourcePathByRelativePath {
      return sourcePathByRelativePath
    }

    var computed: [String: String] = [:]
    for sourceFile in config.sourceFiles {
      guard pathIsIncludedConfiguredSource(sourceFile) else {
        continue
      }
      if !config.packageRoot.isEmpty && sourceFile.hasPrefix(config.packageRoot + "/") {
        let relativePath = String(sourceFile.dropFirst(config.packageRoot.count + 1))
        if computed[relativePath] == nil {
          computed[relativePath] = sourceFile
        }
      }
      if sourceFile.hasPrefix("/") {
        let withoutLeadingSlash = String(sourceFile.dropFirst())
        if computed[withoutLeadingSlash] == nil {
          computed[withoutLeadingSlash] = sourceFile
        }
      }
    }
    sourcePathByRelativePath = computed
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

  private func exactlyIncludedSourcePath(_ path: String) -> String? {
    pathIsIncluded(path) ? path : nil
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
    if let endLine = functionEndLineByPathAndStartLine[path]?[functionLocation.line] {
      return line <= endLine
    }
    guard let endLine = swiftmutFunctionEndLine(
      functionLocationLine: functionLocation.line,
      text: text) else {
      return true
    }
    var endLineByStartLine = functionEndLineByPathAndStartLine[path] ?? [:]
    endLineByStartLine[functionLocation.line] = endLine
    functionEndLineByPathAndStartLine[path] = endLineByStartLine
    return line <= endLine
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
  guard line >= functionLocationLine else {
    return false
  }
  guard let endLine = swiftmutFunctionEndLine(
    functionLocationLine: functionLocationLine,
    text: text) else {
    return true
  }
  return line <= endLine
}

public func swiftmutFunctionEndLine(
  functionLocationLine: Int,
  text: String
) -> Int? {
  var currentLine = 1
  var braceDepth = 0
  var sawOpeningBrace = false

  for byte in text.utf8 {
    if currentLine >= functionLocationLine {
      if byte == 123 {
        braceDepth += 1
        sawOpeningBrace = true
      } else if byte == 125 {
        braceDepth -= 1
      }
    }
    if byte == 10 {
      if sawOpeningBrace && braceDepth <= 0 {
        return currentLine
      }
      currentLine += 1
    }
  }
  if sawOpeningBrace && braceDepth <= 0 {
    return currentLine
  }
  return nil
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
