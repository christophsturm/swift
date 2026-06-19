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
let parseSeconds = elapsed {
  for _ in 0..<options.iterations {
    _ = SwiftmutConfig.load(configPath: configPath) { path in
      if let realPath = options.configPath {
        return SwiftmutSupport.swiftmutRead(realPath)
      }
      return path == "synthetic.json" ? loaded.json : nil
    }
  }
}

let cache = SwiftmutSourceLookupCache(config: loaded.config)
let sourcePaths = cache.swiftSourcePaths()
let locations = sourcePaths.prefix(500).enumerated().map { index, path in
  "debug location: \(path):\(index + 1):1"
}
let lookupSeconds = elapsed {
  for _ in 0..<options.iterations {
    for location in locations {
      _ = cache.functionSourceLocation(in: location)
    }
  }
}

print("swiftmut support benchmark")
print("config: \(configPath)")
print("iterations: \(options.iterations)")
print("source files: \(sourcePaths.count)")
print(String(format: "config parse: %.6fs", parseSeconds))
print(String(format: "source lookup: %.6fs", lookupSeconds))
