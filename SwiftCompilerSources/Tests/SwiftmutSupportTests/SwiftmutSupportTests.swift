//===--- SwiftmutSupportTests.swift ---------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2026 swiftmut contributors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

import XCTest
import Foundation
@testable import SwiftmutSupport

final class SwiftmutSupportTests: XCTestCase {
  func testPipeFieldsPreservesEmptyFieldsAndRejectsWrongCount() {
    XCTAssertEqual(swiftmutPipeFields("a||c|", count: 4), ["a", "", "c", ""])
    XCTAssertEqual(swiftmutPipeFields("a|bé|c", count: 3), ["a", "bé", "c"])
    XCTAssertNil(swiftmutPipeFields("a|b|c", count: 2))
    XCTAssertNil(swiftmutPipeFields("a|b", count: 3))
  }

  func testTopLevelJSONParserReadsStringsAndStringArrays() {
    let fields = SwiftmutJSONTopLevelObject("""
    {
      "name": "swift\\nmut",
      "sourceFiles": ["/repo/A.swift", "/repo/B.swift"],
      "ignored": {"nested": "value"},
      "numbers": [1, 2, 3]
    }
    """)

    XCTAssertEqual(fields.stringValue("name"), "swift\nmut")
    XCTAssertEqual(fields.stringArray("sourceFiles"), ["/repo/A.swift", "/repo/B.swift"])
    XCTAssertNil(fields.stringValue("nested"))
    XCTAssertEqual(fields.stringArray("numbers"), [])
  }

  func testTopLevelJSONParserKeepsFirstDuplicateValueForCompatibility() {
    let fields = SwiftmutJSONTopLevelObject("""
    {
      "mode": "discover",
      "mode": "apply",
      "sourceFiles": ["/repo/A.swift"],
      "sourceFiles": ["/repo/B.swift"]
    }
    """)

    XCTAssertEqual(fields.stringValue("mode"), "discover")
    XCTAssertEqual(fields.stringArray("sourceFiles"), ["/repo/A.swift"])
  }

  func testConfigLoadParsesRulesWithoutCompilerModules() throws {
    let json = """
    {
      "mode": "discover",
      "manifestPath": "/tmp/manifest.json",
      "manifestFragmentsDirectory": "/tmp/fragments",
      "compilerEventsPath": "/tmp/events.jsonl",
      "packageRoot": "/repo",
      "excludePaths": ["Tests"],
      "sourceFiles": ["/repo/Sources/App/File.swift"],
      "enabledMutators": ["condition"],
      "conditionMutationRules": ["cmp_eq_Int64|condition|cmp_ne_Int64|==|!="],
      "arithmeticMutationRules": ["sadd_with_overflow_Int64|ssub_with_overflow_Int64|+|-"],
      "contextualArithmeticMutationRules": ["sadd_with_overflow_Int64|assignment|arithmetic|ssub_with_overflow_Int64|+|-"],
      "returnMutationRules": ["Bool|returnFalse|false|true|false|integer_literal 0"],
      "voidCallMutationRules": ["removeVoidCall|none|call()||"],
      "sourceMutationDisplayRules": ["condition|cmp_eq_Int64|==|!=|!=="]
    }
    """

    let config = try XCTUnwrap(SwiftmutConfig.load(configPath: "config.json") { path in
      path == "config.json" ? json : nil
    })

    XCTAssertEqual(config.mode, .discover)
    XCTAssertEqual(config.packageRoot, "/repo")
    XCTAssertEqual(config.sourceFiles, ["/repo/Sources/App/File.swift"])
    XCTAssertEqual(config.conditionMutationRules.first?.sourceMutated, "!=")
    XCTAssertEqual(config.sourceMutationDisplayRules.first?.sourceMutatedOverride, "!==")
  }

  func testMutatorEnabledUsesConfiguredMutators() {
    let unrestricted = SwiftmutConfig(
      mode: .discover,
      activeMutantID: "",
      mutantsPath: "/repo/.swiftmut/manifest.json",
      manifestFragmentsDirectory: "",
      compilerEventsPath: "",
      packageRoot: "/repo",
      excludePathFragments: [],
      sourceFiles: [],
      enabledMutators: [],
      conditionMutationRules: [],
      arithmeticMutationRules: [],
      contextualArithmeticMutationRules: [],
      returnMutationRules: [],
      voidCallMutationRules: [],
      sourceMutationDisplayRules: [])
    let restricted = SwiftmutConfig(
      mode: .discover,
      activeMutantID: "",
      mutantsPath: "/repo/.swiftmut/manifest.json",
      manifestFragmentsDirectory: "",
      compilerEventsPath: "",
      packageRoot: "/repo",
      excludePathFragments: [],
      sourceFiles: [],
      enabledMutators: ["MATH", "EMPTY_RETURNS"],
      conditionMutationRules: [],
      arithmeticMutationRules: [],
      contextualArithmeticMutationRules: [],
      returnMutationRules: [],
      voidCallMutationRules: [],
      sourceMutationDisplayRules: [])

    XCTAssertTrue(swiftmutMutatorIsEnabled("ANYTHING", config: unrestricted))
    XCTAssertTrue(swiftmutMutatorIsEnabled("MATH", config: restricted))
    XCTAssertFalse(swiftmutMutatorIsEnabled("VOID_METHOD_CALLS", config: restricted))
  }

  func testSourceLookupFindsFunctionLocationWithoutCompilerModules() {
    let config = SwiftmutConfig(
      mode: .discover,
      activeMutantID: "",
      mutantsPath: "/repo/.swiftmut/manifest.json",
      manifestFragmentsDirectory: "",
      compilerEventsPath: "",
      packageRoot: "/repo",
      excludePathFragments: ["Generated"],
      sourceFiles: [
        "/repo/Sources/App/Feature.swift",
        "/repo/Sources/App/Generated/File.swift",
      ],
      enabledMutators: [],
      conditionMutationRules: [],
      arithmeticMutationRules: [],
      contextualArithmeticMutationRules: [],
      returnMutationRules: [],
      voidCallMutationRules: [],
      sourceMutationDisplayRules: [])

    let cache = SwiftmutSourceLookupCache(config: config)
    let location = cache.functionSourceLocation(
      in: "sil hidden @foo : $@convention(thin) () -> () // /repo/Sources/App/Feature.swift:42:9")

    XCTAssertEqual(location?.path, "/repo/Sources/App/Feature.swift")
    XCTAssertEqual(location?.line, 42)
    XCTAssertEqual(cache.swiftSourcePaths(), ["/repo/Sources/App/Feature.swift"])
  }

  func testSourceLookupTreatsUnconfiguredAbsolutePackagePathAsMissing() {
    let config = SwiftmutConfig(
      mode: .discover,
      activeMutantID: "",
      mutantsPath: "/repo/.swiftmut/manifest.json",
      manifestFragmentsDirectory: "",
      compilerEventsPath: "",
      packageRoot: "/repo",
      excludePathFragments: [],
      sourceFiles: ["/repo/Sources/App/Feature.swift"],
      enabledMutators: [],
      conditionMutationRules: [],
      arithmeticMutationRules: [],
      contextualArithmeticMutationRules: [],
      returnMutationRules: [],
      voidCallMutationRules: [],
      sourceMutationDisplayRules: [])

    let cache = SwiftmutSourceLookupCache(config: config)
    let location = cache.functionSourceLocation(
      in: "debug location: /repo/Sources/Missing/Feature.swift:42:9")

    XCTAssertNil(location)
  }

  func testIncludedSourcePathResolvesRelativePackagePath() {
    let config = SwiftmutConfig(
      mode: .discover,
      activeMutantID: "",
      mutantsPath: "/repo/.swiftmut/manifest.json",
      manifestFragmentsDirectory: "",
      compilerEventsPath: "",
      packageRoot: "/repo",
      excludePathFragments: [],
      sourceFiles: ["/repo/Sources/App/Feature.swift"],
      enabledMutators: [],
      conditionMutationRules: [],
      arithmeticMutationRules: [],
      contextualArithmeticMutationRules: [],
      returnMutationRules: [],
      voidCallMutationRules: [],
      sourceMutationDisplayRules: [])

    let cache = SwiftmutSourceLookupCache(config: config)

    XCTAssertEqual(
      cache.includedSourcePath("Sources/App/Feature.swift"),
      "/repo/Sources/App/Feature.swift")
  }

  func testSourceLineBelongsToFunctionUsesExtractedBraceScan() {
    let source = """
    func first() {
      let x = 1
    }

    func second() {
      let y = 2
    }
    """

    XCTAssertTrue(swiftmutSourceLineBelongsToFunction(2, functionLocationLine: 1, text: source))
    XCTAssertFalse(swiftmutSourceLineBelongsToFunction(5, functionLocationLine: 1, text: source))
    XCTAssertEqual(swiftmutFunctionEndLine(functionLocationLine: 1, text: source), 3)
  }

  func testSourceLineExtractsTextByLineNumber() {
    let source = """
    alpha
    béta
    gamma
    """

    XCTAssertEqual(swiftmutSourceLine(in: source, line: 1), "alpha")
    XCTAssertEqual(swiftmutSourceLine(in: source, line: 2), "béta")
    XCTAssertEqual(swiftmutSourceLine(in: "last", line: 1), "last")
    XCTAssertNil(swiftmutSourceLine(in: source, line: 0))
    XCTAssertNil(swiftmutSourceLine(in: source, line: 99))
  }

  func testSourceSnippetMatchesTrackLineColumnAndOffset() {
    let source = """
    alpha call()
    béta call()
    call()
    """

    XCTAssertEqual(
      swiftmutSourceSnippetMatches("call()", in: source),
      [
        SwiftmutSourceSnippetMatch(line: 1, column: 7, offset: 6),
        SwiftmutSourceSnippetMatch(line: 2, column: 7, offset: 19),
        SwiftmutSourceSnippetMatch(line: 3, column: 1, offset: 26),
      ])
    XCTAssertEqual(swiftmutSourceSnippetMatches("", in: source), [])
    XCTAssertEqual(swiftmutSourceLineAndColumn(Array(source.utf8), offset: 19).line, 2)
    XCTAssertEqual(swiftmutSourceLineAndColumn(Array(source.utf8), offset: 19).column, 7)
  }

  func testSourceSnippetMatchesPreserveNonOverlappingBehavior() {
    XCTAssertEqual(
      swiftmutSourceSnippetMatches("aa", in: "aaaa"),
      [
        SwiftmutSourceSnippetMatch(line: 1, column: 1, offset: 0),
        SwiftmutSourceSnippetMatch(line: 1, column: 3, offset: 2),
      ])
  }

  func testSourceTextIndexExtractsLineText() {
    let index = SwiftmutSourceTextIndex(text: "alpha\nbéta\n")

    XCTAssertEqual(index.lineText(line: 1), "alpha")
    XCTAssertEqual(index.lineText(line: 2), "béta")
    XCTAssertEqual(index.lineText(line: 3), "")
    XCTAssertNil(index.lineText(line: 0))
    XCTAssertNil(index.lineText(line: 4))
  }

  func testFunctionEndLineFindsClosingBraceWithoutTrailingNewline() {
    let source = """
    func value() {
      return 1
    }
    """

    XCTAssertEqual(swiftmutFunctionEndLine(functionLocationLine: 1, text: source), 3)
  }

  func testSourceTextIndexFindsLaterFunctionEndLine() {
    let source = """
    func first() {
      let x = 1
    }

    func second() {
      if Bool.random() {
        let y = 2
      }
    }
    """
    let index = SwiftmutSourceTextIndex(text: source)

    XCTAssertEqual(index.functionEndLine(functionLocationLine: 1), 3)
    XCTAssertEqual(index.functionEndLine(functionLocationLine: 5), 9)
    XCTAssertNil(index.functionEndLine(functionLocationLine: 99))
    XCTAssertEqual(
      index.functionEndLine(functionLocationLine: 5),
      swiftmutFunctionEndLineByScanning(functionLocationLine: 5, text: source))
  }

  func testSharedSourceLookupCacheCachesConfiguredSourceReads() throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("swiftmut-support-tests-\(UUID().uuidString)")
    let source = directory
      .appendingPathComponent("Sources")
      .appendingPathComponent("App")
      .appendingPathComponent("Feature.swift")
    try FileManager.default.createDirectory(
      at: source.deletingLastPathComponent(),
      withIntermediateDirectories: true)
    try "first".write(to: source, atomically: true, encoding: .utf8)
    defer {
      try? FileManager.default.removeItem(at: directory)
      swiftmutResetSourceLookupCache()
    }

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

    _ = swiftmutSharedSourceLookupCache(config: config)
    XCTAssertEqual(swiftmutCachedRead(source.path), "first")

    try "second".write(to: source, atomically: true, encoding: .utf8)
    XCTAssertEqual(swiftmutCachedRead(source.path), "first")
  }

  func testSourceLookupCacheCachesFunctionEndLine() throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("swiftmut-support-end-line-tests-\(UUID().uuidString)")
    let source = directory
      .appendingPathComponent("Sources")
      .appendingPathComponent("App")
      .appendingPathComponent("Feature.swift")
    try FileManager.default.createDirectory(
      at: source.deletingLastPathComponent(),
      withIntermediateDirectories: true)
    try """
    func first() {
      let x = 1
    }

    func second() {
      let y = 2
    }
    """.write(to: source, atomically: true, encoding: .utf8)
    defer {
      try? FileManager.default.removeItem(at: directory)
    }

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
    let cache = SwiftmutSourceLookupCache(config: config)
    let functionLocation = (path: source.path, line: 1)

    XCTAssertTrue(cache.sourceLineBelongsToFunction(2, path: source.path, functionLocation: functionLocation))
    XCTAssertFalse(cache.sourceLineBelongsToFunction(5, path: source.path, functionLocation: functionLocation))
  }

  func testSourceLookupCacheLastFunctionRangeDoesNotBleedAcrossFunctions() throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("swiftmut-support-range-cache-tests-\(UUID().uuidString)")
    let source = directory
      .appendingPathComponent("Sources")
      .appendingPathComponent("App")
      .appendingPathComponent("Feature.swift")
    try FileManager.default.createDirectory(
      at: source.deletingLastPathComponent(),
      withIntermediateDirectories: true)
    try """
    func first() {
      let x = 1
    }

    func second() {
      let y = 2
    }
    """.write(to: source, atomically: true, encoding: .utf8)
    defer {
      try? FileManager.default.removeItem(at: directory)
    }

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
    let cache = SwiftmutSourceLookupCache(config: config)

    XCTAssertTrue(cache.sourceLineBelongsToFunction(
      2,
      path: source.path,
      functionLocation: (path: source.path, line: 1)))
    XCTAssertTrue(cache.sourceLineBelongsToFunction(
      6,
      path: source.path,
      functionLocation: (path: source.path, line: 5)))
    XCTAssertFalse(cache.sourceLineBelongsToFunction(
      5,
      path: source.path,
      functionLocation: (path: source.path, line: 1)))
  }

  func testSourceLookupCacheUsesIndexedSourceLine() throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("swiftmut-support-source-line-tests-\(UUID().uuidString)")
    let source = directory
      .appendingPathComponent("Sources")
      .appendingPathComponent("App")
      .appendingPathComponent("Feature.swift")
    try FileManager.default.createDirectory(
      at: source.deletingLastPathComponent(),
      withIntermediateDirectories: true)
    try "alpha\nbéta\n".write(to: source, atomically: true, encoding: .utf8)
    defer {
      try? FileManager.default.removeItem(at: directory)
    }

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
    let cache = SwiftmutSourceLookupCache(config: config)

    XCTAssertEqual(cache.sourceLine(path: source.path, line: 1), "alpha")
    XCTAssertEqual(cache.sourceLine(path: source.path, line: 2), "béta")
    XCTAssertEqual(cache.sourceLine(path: source.path, line: 3), "")
    XCTAssertNil(cache.sourceLine(path: source.path, line: 4))
  }
}
