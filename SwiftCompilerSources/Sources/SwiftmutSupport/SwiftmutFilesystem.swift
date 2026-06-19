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

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
import Darwin
#elseif os(Linux) || os(Android)
import Glibc
#endif

public func swiftmutSwiftSourcePaths(config: SwiftmutConfig) -> [String] {
  var paths: [String] = []
  for path in config.sourceFiles {
    if swiftmutPathIsIncluded(path, config: config) {
      paths.append(path)
    }
  }
  return paths
}

public func swiftmutPathIsIncluded(
  _ path: String,
  config: SwiftmutConfig
) -> Bool {
  if !config.packageRoot.isEmpty && !path.hasPrefix(config.packageRoot + "/") {
    return false
  }
  if !config.sourceFiles.isEmpty && !swiftmutPathIsConfiguredSource(path, config: config) {
    return false
  }
  for fragment in config.excludePathFragments {
    if path.contains(fragment) {
      return false
    }
  }
  return true
}

public func swiftmutPathIsConfiguredSource(
  _ path: String,
  config: SwiftmutConfig
) -> Bool {
  for sourcePath in config.sourceFiles {
    if path == sourcePath {
      return true
    }
  }
  return false
}

public func swiftmutIncludedSourcePath(
  _ path: String,
  config: SwiftmutConfig
) -> String? {
  if swiftmutPathIsIncluded(path, config: config) {
    return path
  }
  let suffix = path.hasPrefix("/") ? path : "/" + path
  for sourceFile in config.sourceFiles {
    if sourceFile.hasSuffix(suffix),
       swiftmutPathIsIncluded(sourceFile, config: config) {
      return sourceFile
    }
  }
  return nil
}

public func swiftmutTrimPackageRoot(
  _ path: String,
  config: SwiftmutConfig
) -> String {
  guard !config.packageRoot.isEmpty else {
    return path
  }
  if path == config.packageRoot {
    return "."
  }
  if path.hasPrefix(config.packageRoot + "/") {
    return String(path.dropFirst(config.packageRoot.count + 1))
  }
  return path
}

public func swiftmutCreateParentDirectories(forFile path: String) {
  #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(Linux) || os(Android)
  let components = path.split(separator: "/", omittingEmptySubsequences: true)
  guard components.count > 1 else {
    return
  }

  var current = path.hasPrefix("/") ? "/" : ""
  for component in components.dropLast() {
    if current.isEmpty || current == "/" {
      current += component
    } else {
      current += "/" + component
    }
    _ = current.withCString { mkdir($0, 0o755) }
  }
  #endif
}

public func swiftmutRead(_ path: String) -> String? {
  #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(Linux) || os(Android)
  return path.withCString { pathPointer in
    guard let file = fopen(pathPointer, "r") else {
      return nil
    }
    defer { fclose(file) }

    var output = ""
    var buffer = [CChar](repeating: 0, count: 4096)
    while true {
      let readLine = buffer.withUnsafeMutableBufferPointer {
        fgets($0.baseAddress, Int32($0.count), file)
      }
      guard readLine != nil else {
        break
      }
      output += String(cString: buffer)
    }
    return output
  }
  #else
  return nil
  #endif
}

public func swiftmutWrite(
  _ text: String,
  to path: String,
  append: Bool
) {
  #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(Linux) || os(Android)
  let mode = append ? "a" : "w"
  path.withCString { pathPointer in
    mode.withCString { modePointer in
      guard let file = fopen(pathPointer, modePointer) else {
        return
      }
      _ = text.withCString { textPointer in
        fputs(textPointer, file)
      }
      fclose(file)
    }
  }
  #endif
}
