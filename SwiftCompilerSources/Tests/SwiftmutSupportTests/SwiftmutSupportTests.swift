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

  func testFunctionEndLineFindsClosingBraceWithoutTrailingNewline() {
    let source = """
    func value() {
      return 1
    }
    """

    XCTAssertEqual(swiftmutFunctionEndLine(functionLocationLine: 1, text: source), 3)
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
}
