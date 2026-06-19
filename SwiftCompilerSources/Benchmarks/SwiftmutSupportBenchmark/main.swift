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

func multiFunctionEndLineFixture() -> (text: String, startLines: [Int]) {
  var lines: [String] = []
  var startLines: [Int] = []
  for functionIndex in 0..<200 {
    startLines.append(lines.count + 1)
    lines.append("func benchmark\(functionIndex)() {")
    for lineIndex in 0..<20 {
      lines.append("  let value\(lineIndex) = \(lineIndex)")
    }
    lines.append("}")
    lines.append("")
  }
  return (lines.joined(separator: "\n"), startLines)
}

func topLevelScanFixture() -> [UInt8] {
  var segments: [String] = []
  for index in 0..<250 {
    segments.append("call\(index)(value: [1, 2, 3], text: \"where else = ?\")")
  }
  segments.append(" target: true")
  return Array(segments.joined(separator: ", ").utf8)
}

func balancedExpressionFixture() -> [UInt8] {
  var nested = "value("
  for index in 0..<100 {
    nested += "call\(index)([\"ignored )\", value\(index)]), "
  }
  nested += "tail)"
  return Array(nested.utf8)
}

func ternaryScanFixture() -> [UInt8] {
  var source = "label: value0 == other0, "
  for index in 1..<150 {
    source += "call\(index)(value: [left\(index) ? right\(index) : fallback\(index)]), "
  }
  source += "target = object.value ? yes : no"
  return Array(source.utf8)
}

func mangledIdentifierFixture() -> [String] {
  var names: [String] = []
  for index in 0..<500 {
    names.append("$s7Module6value\(index)5ModelV6updateyyF6value\(index)5Model")
  }
  return names
}

func defaultArgumentDeclarationFixture() -> (bytes: [UInt8], keywordOffsets: [Int]) {
  var source = ""
  var keywordOffsets: [Int] = []
  for index in 0..<300 {
    keywordOffsets.append(source.utf8.count)
    source += """
    func make\(index)<T: Comparable>(
      value: Int = call\(index)([")", nested(value: \(index))], other: T.self),
      label: String = "text, with = signs",
      flag: Bool = value\(index) == other\(index)
    ) -> T {
      fatalError()
    }

    """
  }
  return (Array(source.utf8), keywordOffsets)
}

func trimTextFixture() -> [String] {
  var values: [String] = []
  for index in 0..<2_000 {
    values.append("    value\(index) == other\(index)    ")
  }
  values.append(" \t ")
  values.append("  béta value  ")
  return values
}

func pipeFieldFixture() -> [String] {
  var values: [String] = []
  for index in 0..<1_000 {
    values.append("builtin\(index)|condition|mutated\(index)|==|!=")
    values.append("context\(index)|returnFalse|false|true|false|integer_literal 0")
  }
  values.append("unicode|bé|c|d|e")
  return values
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
let mutatorsToCheck = (
  loaded.config.enabledMutators
  + ["MISSING_MUTATOR", "MATH", "EMPTY_RETURNS", "VOID_METHOD_CALLS"]
)
let mutatorEnabledSeconds = elapsed {
  for _ in 0..<options.iterations {
    for mutator in mutatorsToCheck {
      _ = swiftmutMutatorIsEnabled(mutator, config: loaded.config)
    }
  }
}
let pipeFields = pipeFieldFixture()
let pipeFieldIterations = max(1, options.iterations / 100)
let pipeFieldSeconds = elapsed {
  for _ in 0..<pipeFieldIterations {
    for value in pipeFields {
      _ = swiftmutPipeFields(value, count: 5)
      _ = swiftmutPipeFields(value, count: 6)
    }
  }
}
let trimTexts = trimTextFixture()
let trimTextIterations = max(1, options.iterations / 100)
let trimTextSeconds = elapsed {
  for _ in 0..<trimTextIterations {
    for value in trimTexts {
      _ = swiftmutTrimmedHorizontalWhitespace(value)
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
let sourceReadSeconds = elapsed {
  for _ in 0..<options.iterations {
    _ = swiftmutRead(membershipFixture.path)
  }
}
let cachedSourceLineSeconds = elapsed {
  for _ in 0..<options.iterations {
    _ = membershipFixture.cache.sourceLine(path: membershipFixture.path, line: 1_000)
  }
}
let cachedNumberedSourceLinesSeconds = elapsed {
  for _ in 0..<options.iterations {
    _ = membershipFixture.cache.numberedSourceLines(path: membershipFixture.path)
  }
}
let cachedSourceSnippetSeconds = elapsed {
  for _ in 0..<options.iterations {
    _ = membershipFixture.cache.sourceSnippetMatches("let value999", path: membershipFixture.path)
  }
}
membershipFixture.cleanup()
let endLineFixture = functionEndLineFixture()
let sourceLineSeconds = elapsed {
  for _ in 0..<options.iterations {
    _ = swiftmutSourceLine(in: endLineFixture, line: 1_000)
  }
}
let numberedSourceLinesSeconds = elapsed {
  for _ in 0..<options.iterations {
    _ = swiftmutNumberedSourceLines(endLineFixture)
  }
}
let sourceSnippetSeconds = elapsed {
  for _ in 0..<options.iterations {
    _ = swiftmutSourceSnippetMatches("let value999", in: endLineFixture)
  }
}
let endLineSeconds = elapsed {
  for _ in 0..<options.iterations {
    _ = swiftmutFunctionEndLine(functionLocationLine: 1, text: endLineFixture)
  }
}
let multiFunctionFixture = multiFunctionEndLineFixture()
let endLineComparisonIterations = max(1, options.iterations / 100)
let repeatedEndLineSeconds = elapsed {
  for _ in 0..<endLineComparisonIterations {
    for line in multiFunctionFixture.startLines {
      _ = swiftmutFunctionEndLineByScanning(
        functionLocationLine: line,
        text: multiFunctionFixture.text)
    }
  }
}
let sourceTextIndex = SwiftmutSourceTextIndex(text: multiFunctionFixture.text)
let indexedEndLineSeconds = elapsed {
  for _ in 0..<endLineComparisonIterations {
    for line in multiFunctionFixture.startLines {
      _ = sourceTextIndex.functionEndLine(functionLocationLine: line)
    }
  }
}
let topLevelFixture = topLevelScanFixture()
let topLevelByteSeconds = elapsed {
  for _ in 0..<options.iterations {
    _ = swiftmutTopLevelByteIndex(
      topLevelFixture,
      start: 0,
      end: topLevelFixture.count,
      byte: UInt8(ascii: ":"))
  }
}
let topLevelASCIISeconds = elapsed {
  for _ in 0..<options.iterations {
    _ = swiftmutTopLevelASCIIIndex(
      topLevelFixture,
      start: 0,
      end: topLevelFixture.count,
      pattern: "target")
  }
}
let expressionCompleteSeconds = elapsed {
  for _ in 0..<options.iterations {
    _ = swiftmutSourceExpressionIsSingleLineComplete(
      bytes: topLevelFixture,
      start: 0,
      end: topLevelFixture.count)
  }
}
let balancedFixture = balancedExpressionFixture()
let balancedExpressionSeconds = elapsed {
  for _ in 0..<options.iterations {
    _ = swiftmutBalancedExpressionEnd(
      in: balancedFixture,
      openIndex: 5,
      close: UInt8(ascii: ")"),
      lineEnd: balancedFixture.count)
  }
}
let ternaryFixture = ternaryScanFixture()
let ternaryScanSeconds = elapsed {
  for _ in 0..<options.iterations {
    if let parts = swiftmutTopLevelTernaryParts(
      bytes: ternaryFixture,
      start: 0,
      end: ternaryFixture.count) {
      _ = parts.assignmentBeforeQuestion
      _ = parts.labelColonBeforeQuestion
      _ = parts.colonAfterQuestion
    }
  }
}
let ternaryConditionRangeSeconds = elapsed {
  for _ in 0..<options.iterations {
    if let parts = swiftmutTopLevelTernaryParts(
      bytes: ternaryFixture,
      start: 0,
      end: ternaryFixture.count) {
      var boundary = -1
      if let assignment = parts.assignmentBeforeQuestion {
        boundary = max(boundary, assignment)
      }
      if let comma = parts.commaBeforeQuestion {
        boundary = max(boundary, comma)
      }
      let start = swiftmutSkipHorizontalWhitespace(
        ternaryFixture,
        from: boundary >= 0 ? boundary + 1 : 0)
      let end = swiftmutTrimTrailingHorizontalWhitespace(ternaryFixture, end: parts.question)
      _ = start < end
    }
  }
}
let mangledNames = mangledIdentifierFixture()
let mangledIdentifierIterations = max(1, options.iterations / 100)
let mangledIdentifierSeconds = elapsed {
  for _ in 0..<mangledIdentifierIterations {
    for name in mangledNames {
      _ = swiftmutMangledIdentifiers(in: name)
      _ = swiftmutMangledNameContainsIdentifier(name, identifier: "valueModel")
    }
  }
}
let defaultArgumentFixture = defaultArgumentDeclarationFixture()
let defaultArgumentIterations = max(1, options.iterations / 100)
let defaultArgumentDeclarationSeconds = elapsed {
  for _ in 0..<defaultArgumentIterations {
    for keywordOffset in defaultArgumentFixture.keywordOffsets {
      if swiftmutSourceDeclarationKeywordAt(
        bytes: defaultArgumentFixture.bytes,
        index: keywordOffset),
        let list = swiftmutSourceDeclarationParameterList(
          bytes: defaultArgumentFixture.bytes,
          from: keywordOffset) {
        _ = swiftmutTopLevelEquals(
          bytes: defaultArgumentFixture.bytes,
          start: list.start,
          end: list.end)
      }
    }
  }
}

print("swiftmut support benchmark")
print("config: \(configPath)")
print("iterations: \(options.iterations)")
print("source files: \(sourcePaths.count)")
print(String(format: "config parse: %.6fs", parseSeconds))
print(String(format: "mutator enabled: %.6fs", mutatorEnabledSeconds))
print("pipe field iterations: \(pipeFieldIterations)")
print(String(format: "pipe field split: %.6fs", pipeFieldSeconds))
print("trim text iterations: \(trimTextIterations)")
print(String(format: "trim horizontal whitespace: %.6fs", trimTextSeconds))
print(String(format: "source lookup cold: %.6fs", coldLookupSeconds))
print(String(format: "source lookup warm: %.6fs", warmLookupSeconds))
print(String(format: "source lookup missing: %.6fs", missingLookupSeconds))
print(String(format: "source suffix lookup: %.6fs", suffixLookupSeconds))
print(String(format: "source membership cached: %.6fs", membershipSeconds))
print(String(format: "source read: %.6fs", sourceReadSeconds))
print(String(format: "source line: %.6fs", sourceLineSeconds))
print(String(format: "numbered source lines: %.6fs", numberedSourceLinesSeconds))
print(String(format: "source line cached: %.6fs", cachedSourceLineSeconds))
print(String(format: "numbered source lines cached: %.6fs", cachedNumberedSourceLinesSeconds))
print(String(format: "source snippet: %.6fs", sourceSnippetSeconds))
print(String(format: "source snippet cached: %.6fs", cachedSourceSnippetSeconds))
print(String(format: "function end-line scan: %.6fs", endLineSeconds))
print("function end-line comparison iterations: \(endLineComparisonIterations)")
print(String(format: "function end-line repeated scan: %.6fs", repeatedEndLineSeconds))
print(String(format: "function end-line indexed: %.6fs", indexedEndLineSeconds))
print(String(format: "top-level byte scan: %.6fs", topLevelByteSeconds))
print(String(format: "top-level ascii scan: %.6fs", topLevelASCIISeconds))
print(String(format: "expression complete scan: %.6fs", expressionCompleteSeconds))
print(String(format: "balanced expression scan: %.6fs", balancedExpressionSeconds))
print(String(format: "ternary boundary scan: %.6fs", ternaryScanSeconds))
print(String(format: "ternary condition range scan: %.6fs", ternaryConditionRangeSeconds))
print("mangled identifier iterations: \(mangledIdentifierIterations)")
print(String(format: "mangled identifier scan: %.6fs", mangledIdentifierSeconds))
print("default argument declaration iterations: \(defaultArgumentIterations)")
print(String(format: "default argument declaration scan: %.6fs", defaultArgumentDeclarationSeconds))
