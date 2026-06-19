//===--- main.swift --------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2026 swiftmut contributors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

import Foundation
import SwiftmutSupport

struct Options {
  var configPath: String?
  var iterations = 1_000
}

func parseOptions(_ arguments: [String]) -> Options {
  var options = Options()
  var index = 1
  while index < arguments.count {
    switch arguments[index] {
    case "--config":
      if index + 1 < arguments.count {
        options.configPath = arguments[index + 1]
        index += 1
      }
    case "--iterations":
      if index + 1 < arguments.count,
         let iterations = Int(arguments[index + 1]),
         iterations > 0 {
        options.iterations = iterations
        index += 1
      }
    default:
      break
    }
    index += 1
  }
  return options
}

func elapsed(_ body: () -> Void) -> Double {
  let startedAt = Date()
  body()
  return Date().timeIntervalSince(startedAt)
}

func syntheticJSON() -> (json: String, config: SwiftmutConfig) {
  let root = "/tmp/swiftmut-support-benchmark"
  var sourceFiles: [String] = []
  for index in 0..<800 {
    sourceFiles.append("\(root)/Sources/Module/File\(index).swift")
  }
  let json = """
  {
    "mode": "discover",
    "manifestPath": "\(root)/manifest.json",
    "manifestFragmentsDirectory": "\(root)/fragments",
    "compilerEventsPath": "\(root)/events.jsonl",
    "packageRoot": "\(root)",
    "excludePaths": ["Generated"],
    "sourceFiles": [\(sourceFiles.map { "\"\($0)\"" }.joined(separator: ","))],
    "enabledMutators": ["condition", "return"],
    "conditionMutationRules": ["cmp_eq_Int64|condition|cmp_ne_Int64|==|!="],
    "arithmeticMutationRules": ["sadd_with_overflow_Int64|ssub_with_overflow_Int64|+|-"],
    "contextualArithmeticMutationRules": [],
    "returnMutationRules": [],
    "voidCallMutationRules": [],
    "sourceMutationDisplayRules": []
  }
  """
  let config = SwiftmutConfig.load(configPath: "synthetic.json") { path in
    path == "synthetic.json" ? json : nil
  }!
  return (json, config)
}

func sourceLocations(from sourcePaths: [String], count: Int) -> [String] {
  sourcePaths.prefix(count).enumerated().map { index, path in
    "debug location: \(path):\(index + 1):1"
  }
}

func missingLocations(root: String, count: Int) -> [String] {
  (0..<count).map { index in
    "debug location: \(root)/Sources/Missing/File\(index).swift:\(index + 1):1"
  }
}

func relativeSourcePaths(from sourcePaths: [String], packageRoot: String, count: Int) -> [String] {
  sourcePaths.prefix(count).map { path in
    if !packageRoot.isEmpty && path.hasPrefix(packageRoot + "/") {
      return String(path.dropFirst(packageRoot.count + 1))
    }
    return path
  }
}

func makeMembershipFixture() -> (cache: SwiftmutSourceLookupCache, path: String, cleanup: () -> Void) {
  let directory = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("swiftmut-support-benchmark-\(UUID().uuidString)")
  let source = directory
    .appendingPathComponent("Sources")
    .appendingPathComponent("App")
    .appendingPathComponent("Feature.swift")
  try! FileManager.default.createDirectory(
    at: source.deletingLastPathComponent(),
    withIntermediateDirectories: true)

  var lines = ["func benchmark() {"]
  for index in 0..<2_000 {
    lines.append("  let value\(index) = \(index)")
  }
  lines.append("}")
  try! lines.joined(separator: "\n").write(to: source, atomically: true, encoding: .utf8)

  let config = SwiftmutConfig(
    mode: .discover,
    activeMutantID: "",
    mutantsPath: directory.appendingPathComponent("manifest.json").path,
    manifestFragmentsDirectory: "",
    compilerEventsPath: "",
    packageRoot: directory.path,
    excludePathFragments: [],
    sourceFiles: [source.path],
    enabledMutators: [],
    conditionMutationRules: [],
    arithmeticMutationRules: [],
    contextualArithmeticMutationRules: [],
    returnMutationRules: [],
    voidCallMutationRules: [],
    sourceMutationDisplayRules: [])
  return (
    SwiftmutSourceLookupCache(config: config),
    source.path,
    { try? FileManager.default.removeItem(at: directory) }
  )
}

func functionEndLineFixture() -> String {
  var lines = ["func benchmark() {"]
  for index in 0..<2_000 {
    lines.append("  let value\(index) = \(index)")
  }
  lines.append("}")
  return lines.joined(separator: "\n")
}

let options = parseOptions(CommandLine.arguments)
let loaded: (json: String?, config: SwiftmutConfig)
if let configPath = options.configPath {
  guard let config = SwiftmutConfig.load(configPath: configPath) else {
    FileHandle.standardError.write(Data("failed to load \(configPath)\n".utf8))
    exit(1)
  }
  loaded = (try? String(contentsOfFile: configPath, encoding: .utf8), config)
} else {
  let synthetic = syntheticJSON()
  loaded = (synthetic.json, synthetic.config)
}

let configPath = options.configPath ?? "synthetic.json"
let benchmarkJSON = loaded.json
let parseSeconds = elapsed {
  for _ in 0..<options.iterations {
    _ = SwiftmutConfig.load(configPath: configPath) { path in
      path == configPath ? benchmarkJSON : nil
    }
  }
}

let cache = SwiftmutSourceLookupCache(config: loaded.config)
let sourcePaths = cache.swiftSourcePaths()
let locations = sourceLocations(from: sourcePaths, count: 500)
let coldLookupSeconds = elapsed {
  let coldCache = SwiftmutSourceLookupCache(config: loaded.config)
  for location in locations {
    _ = coldCache.functionSourceLocation(in: location)
  }
}
let warmLookupSeconds = elapsed {
  for _ in 0..<options.iterations {
    for location in locations {
      _ = cache.functionSourceLocation(in: location)
    }
  }
}
let missing = missingLocations(root: loaded.config.packageRoot, count: max(1, min(sourcePaths.count, 500)))
let missingLookupSeconds = elapsed {
  let missingCache = SwiftmutSourceLookupCache(config: loaded.config)
  for _ in 0..<options.iterations {
    for location in missing {
      _ = missingCache.functionSourceLocation(in: location)
    }
  }
}
let relativePaths = relativeSourcePaths(
  from: sourcePaths,
  packageRoot: loaded.config.packageRoot,
  count: 500)
let suffixLookupSeconds = elapsed {
  let suffixCache = SwiftmutSourceLookupCache(config: loaded.config)
  for _ in 0..<options.iterations {
    for path in relativePaths {
      _ = suffixCache.includedSourcePath(path)
    }
  }
}
let membershipFixture = makeMembershipFixture()
let membershipSeconds = elapsed {
  for _ in 0..<options.iterations {
    for line in stride(from: 1, through: 2_200, by: 11) {
      _ = membershipFixture.cache.sourceLineBelongsToFunction(
        line,
        path: membershipFixture.path,
        functionLocation: (path: membershipFixture.path, line: 1))
    }
  }
}
membershipFixture.cleanup()
let endLineFixture = functionEndLineFixture()
let endLineSeconds = elapsed {
  for _ in 0..<options.iterations {
    _ = swiftmutFunctionEndLine(functionLocationLine: 1, text: endLineFixture)
  }
}

print("swiftmut support benchmark")
print("config: \(configPath)")
print("iterations: \(options.iterations)")
print("source files: \(sourcePaths.count)")
print(String(format: "config parse: %.6fs", parseSeconds))
print(String(format: "source lookup cold: %.6fs", coldLookupSeconds))
print(String(format: "source lookup warm: %.6fs", warmLookupSeconds))
print(String(format: "source lookup missing: %.6fs", missingLookupSeconds))
print(String(format: "source suffix lookup: %.6fs", suffixLookupSeconds))
print(String(format: "source membership cached: %.6fs", membershipSeconds))
print(String(format: "function end-line scan: %.6fs", endLineSeconds))
