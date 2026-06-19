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

  func testMangledIdentifiersExtractsUniqueLengthPrefixedIdentifiers() {
    XCTAssertEqual(
      swiftmutMangledIdentifiers(in: "$s5ModelV4nameSSvg5Model4name"),
      ["Model", "name"])
    XCTAssertEqual(swiftmutMangledIdentifiers(in: "$s10toolong"), [])
    XCTAssertTrue(swiftmutIdentifierLooksLikeSourceExpression("value"))
    XCTAssertTrue(swiftmutIdentifierLooksLikeSourceExpression("_value"))
    XCTAssertFalse(swiftmutIdentifierLooksLikeSourceExpression("Value"))
  }

  func testIdentifierByteValidationRejectsInvalidIdentifierBytes() {
    XCTAssertTrue(swiftmutBytesAreIdentifier(Array("value_1".utf8), start: 0, end: 7))
    XCTAssertFalse(swiftmutBytesAreIdentifier(Array("value-name".utf8), start: 0, end: 10))
    XCTAssertFalse(swiftmutBytesAreIdentifier(Array("".utf8), start: 0, end: 0))
  }

  func testMangledNameIdentifierMatchingUsesCamelCaseFallbacks() {
    XCTAssertEqual(swiftmutCamelCaseIdentifierWords("myHTTPClientValue"), ["my", "HTTPClient", "Value"])
    XCTAssertTrue(swiftmutMangledNameContainsIdentifier("some myHTTPClient Value payload", identifier: "myHTTPClientValue"))
    XCTAssertTrue(swiftmutMangledNameContainsIdentifier("prefix LongIdent suffix", identifier: "LongIdentifierName"))
    XCTAssertTrue(swiftmutMangledNameContainsIdentifier("cf", identifier: "init"))
    XCTAssertFalse(swiftmutMangledNameContainsIdentifier("unrelated", identifier: "myHTTPClientValue"))
    XCTAssertTrue(swiftmutIsASCIIUppercase(UInt8(ascii: "A")))
    XCTAssertTrue(swiftmutIsASCIILowercase(UInt8(ascii: "z")))
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

  func testNumberedSourceLinesPreservesLineNumbersAndUTF8Text() {
    let lines = swiftmutNumberedSourceLines("alpha\nbéta\n")
    XCTAssertEqual(lines.map(\.number), [1, 2])
    XCTAssertEqual(lines.map(\.text), ["alpha", "béta"])

    let last = swiftmutNumberedSourceLines("last")
    XCTAssertEqual(last.map(\.number), [1])
    XCTAssertEqual(last.map(\.text), ["last"])

    let empty = swiftmutNumberedSourceLines("")
    XCTAssertEqual(empty.map(\.number), [1])
    XCTAssertEqual(empty.map(\.text), [""])
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

  func testTopLevelByteIndexIgnoresNestedAndQuotedBytes() {
    let bytes = Array(#"call(a, ["ignored, comma"], nested(value)) , trailing"#.utf8)

    XCTAssertEqual(swiftmutTopLevelByteIndex(bytes, start: 0, end: bytes.count, byte: 44), 43)
    XCTAssertEqual(swiftmutTopLevelASCIIIndex(bytes, start: 0, end: bytes.count, pattern: "trailing"), 45)
    XCTAssertTrue(swiftmutTopLevelASCIIContains(bytes, start: 0, end: bytes.count, pattern: "trailing"))
    XCTAssertFalse(swiftmutTopLevelASCIIContains(bytes, start: 0, end: bytes.count, pattern: "ignored"))
  }

  func testSingleLineExpressionCompletenessTracksQuotesAndDelimiters() {
    XCTAssertTrue(swiftmutSourceExpressionIsSingleLineComplete(
      bytes: Array(#"value(")") + [1, 2]"#.utf8),
      start: 0,
      end: #"value(")") + [1, 2]"#.utf8.count))
    XCTAssertFalse(swiftmutSourceExpressionIsSingleLineComplete(
      bytes: Array("value([1, 2".utf8),
      start: 0,
      end: "value([1, 2".utf8.count))
    XCTAssertFalse(swiftmutSourceExpressionIsSingleLineComplete(
      bytes: Array("value())".utf8),
      start: 0,
      end: "value())".utf8.count))
  }

  func testASCIITextHelpersAreAvailableWithoutCompilerModules() {
    let bytes = Array("  Alpha beta  ".utf8)

    XCTAssertEqual(swiftmutSkipHorizontalWhitespace(bytes, from: 0), 2)
    XCTAssertEqual(swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count), 12)
    XCTAssertEqual(swiftmutASCIIIndex(bytes, start: 0, end: bytes.count, pattern: "beta"), 8)
    XCTAssertTrue(swiftmutASCIIContains(bytes, start: 0, end: bytes.count, pattern: "Alpha"))
    XCTAssertTrue(swiftmutASCIIHasPrefix(bytes, start: 2, prefix: "alpha"))
    XCTAssertTrue(swiftmutASCIIHasExactPrefix(bytes, start: 2, prefix: "Alpha"))
    XCTAssertFalse(swiftmutASCIIHasExactPrefix(bytes, start: 2, prefix: "alpha"))
    XCTAssertEqual(swiftmutASCIILowercase(UInt8(ascii: "A")), UInt8(ascii: "a"))
    XCTAssertTrue(swiftmutIsASCIIIdentifierStart(UInt8(ascii: "_")))
    XCTAssertTrue(swiftmutIsASCIILetterNumberOrUnderscore(UInt8(ascii: "7")))
    XCTAssertTrue(swiftmutIsHorizontalWhitespace(UInt8(ascii: "\t")))
  }

  func testSourceDeclarationKeywordAtFindsFunctionsAndInitializers() {
    let source = "myfunc value\nfunc make()\ninit(value: Int)\ninit?(value: Int)\ninit!(value: Int)"
    let bytes = Array(source.utf8)

    XCTAssertFalse(swiftmutSourceDeclarationKeywordAt(bytes: bytes, index: 2))
    XCTAssertTrue(swiftmutSourceDeclarationKeywordAt(
      bytes: bytes,
      index: swiftmutASCIIIndex(bytes, start: 0, end: bytes.count, pattern: "func make")!))
    XCTAssertTrue(swiftmutSourceDeclarationKeywordAt(
      bytes: bytes,
      index: swiftmutASCIIIndex(bytes, start: 0, end: bytes.count, pattern: "init(value")!))
    XCTAssertTrue(swiftmutSourceDeclarationKeywordAt(
      bytes: bytes,
      index: swiftmutASCIIIndex(bytes, start: 0, end: bytes.count, pattern: "init?(value")!))
    XCTAssertTrue(swiftmutSourceDeclarationKeywordAt(
      bytes: bytes,
      index: swiftmutASCIIIndex(bytes, start: 0, end: bytes.count, pattern: "init!(value")!))
  }

  func testSourceDeclarationParameterListHandlesGenericsAndNestedDefaults() {
    let source = #"func make<T: Comparable>(value: Int = call([")"], other: T.self), label: String = "x,y") -> T {"#
    let bytes = Array(source.utf8)
    let keyword = swiftmutASCIIIndex(bytes, start: 0, end: bytes.count, pattern: "func make")!

    let list = swiftmutSourceDeclarationParameterList(bytes: bytes, from: keyword)

    XCTAssertEqual(
      list.map { String(decoding: bytes[$0.start..<$0.end], as: UTF8.self) },
      #"value: Int = call([")"], other: T.self), label: String = "x,y""#)
  }

  func testFindMatchingSourceDelimiterIgnoresCloseDelimiterInStrings() {
    let source = #"call(")") trailing"#
    let bytes = Array(source.utf8)
    let open = swiftmutASCIIIndex(bytes, start: 0, end: bytes.count, pattern: "(")!
    let trailing = swiftmutASCIIIndex(bytes, start: 0, end: bytes.count, pattern: " trailing")!

    XCTAssertEqual(
      swiftmutFindMatchingSourceDelimiter(
        bytes: bytes,
        openOffset: open,
        open: UInt8(ascii: "("),
        close: UInt8(ascii: ")")),
      trailing - 1)
  }

  func testTopLevelEqualsIgnoresNestedEqualsAndStrings() {
    let source = #"value: [String: Int] = ["ignored =": call(value = 1)], label: String = "target""#
    let bytes = Array(source.utf8)
    let expected = swiftmutASCIIIndex(bytes, start: 0, end: bytes.count, pattern: " = [")!

    XCTAssertEqual(swiftmutTopLevelEquals(bytes: bytes, start: 0, end: bytes.count), expected + 1)
  }

  func testLineOpensFunctionBodyUsesTopLevelBraceOnly() {
    XCTAssertTrue(swiftmutLineOpensFunctionBody("func value() {"))
    XCTAssertFalse(swiftmutLineOpensFunctionBody("let text = \"{\""))
    XCTAssertFalse(swiftmutLineOpensFunctionBody("let value = call({ nested() })"))
  }

  func testBalancedExpressionEndHandlesNestedDelimitersAndQuotes() {
    let call = Array(#"value(["ignored )"], nested(1 + 2)) + tail"#.utf8)

    XCTAssertEqual(
      swiftmutBalancedExpressionEnd(
        in: call,
        openIndex: 5,
        close: UInt8(ascii: ")"),
        lineEnd: call.count),
      35)

    let closure = Array(#"{ text = "}" ; nested { value } } trailing"#.utf8)
    XCTAssertEqual(
      swiftmutBalancedExpressionEnd(
        in: closure,
        openIndex: 0,
        close: UInt8(ascii: "}"),
        lineEnd: closure.count),
      33)
  }

  func testBalancedExpressionEndReturnsNilForUnclosedExpression() {
    let bytes = Array(#"value("unterminated")"#.utf8)

    XCTAssertNil(swiftmutBalancedExpressionEnd(
      in: bytes,
      openIndex: 5,
      close: UInt8(ascii: ")"),
      lineEnd: bytes.count - 1))
  }

  func testTopLevelTernaryQuestionSkipsNilCoalescingAndNestedQuestions() {
    let bytes = Array(#"value ?? fallback ? yes([ignored ? value]) : no"#.utf8)

    XCTAssertEqual(
      swiftmutTopLevelTernaryQuestionIndex(bytes: bytes, start: 0, end: bytes.count),
      18)
  }

  func testLastTopLevelAssignmentEqualsSkipsComparisonsAndNestedEquals() {
    let bytes = Array(#"label: lhs == rhs ? x : object.assign(value = 1) = result"#.utf8)
    let question = swiftmutTopLevelTernaryQuestionIndex(bytes: bytes, start: 0, end: bytes.count)!

    XCTAssertNil(swiftmutLastTopLevelAssignmentEqualsBefore(bytes: bytes, start: 0, end: question))
    XCTAssertEqual(
      swiftmutLastTopLevelAssignmentEqualsBefore(bytes: bytes, start: question + 1, end: bytes.count),
      49)
  }

  func testLastTopLevelByteBeforeIgnoresNestedBytes() {
    let bytes = Array(#"label: call([1: 2], text: ":") ? yes : no"#.utf8)
    let question = swiftmutTopLevelTernaryQuestionIndex(bytes: bytes, start: 0, end: bytes.count)!

    XCTAssertEqual(
      swiftmutLastTopLevelByteBefore(bytes: bytes, start: 0, end: question, byte: UInt8(ascii: ":")),
      5)
  }

  func testTopLevelTernaryPartsScansQuestionColonAssignmentAndLabelTogether() {
    let source = #"prefix(value), target = label: call([1: 2], text: ":") ? yes : no"#
    let bytes = Array(source.utf8)

    XCTAssertEqual(
      swiftmutTopLevelTernaryParts(bytes: bytes, start: 0, end: bytes.count),
      SwiftmutTopLevelTernaryParts(
        question: swiftmutASCIIIndex(bytes, start: 0, end: bytes.count, pattern: " ? ")! + 1,
        colonAfterQuestion: swiftmutASCIIIndex(bytes, start: 0, end: bytes.count, pattern: " : no")! + 1,
        assignmentBeforeQuestion: swiftmutASCIIIndex(bytes, start: 0, end: bytes.count, pattern: " = ")! + 1,
        labelColonBeforeQuestion: swiftmutASCIIIndex(bytes, start: 0, end: bytes.count, pattern: "label:")! + 5,
        commaBeforeQuestion: swiftmutASCIIIndex(bytes, start: 0, end: bytes.count, pattern: ", target")!))
  }

  func testTopLevelTernaryPartsRejectsMissingColonAndNilCoalescing() {
    let missingColon = Array(#"value ? yes"#.utf8)
    let nilCoalescing = Array(#"value ?? fallback"#.utf8)

    XCTAssertNil(swiftmutTopLevelTernaryParts(bytes: missingColon, start: 0, end: missingColon.count))
    XCTAssertNil(swiftmutTopLevelTernaryParts(bytes: nilCoalescing, start: 0, end: nilCoalescing.count))
  }

  func testTernaryConditionStartUsesTopLevelAssignmentBoundary() {
    let bytes = Array(#"target = object.value ? yes : no"#.utf8)
    let question = swiftmutTopLevelTernaryQuestionIndex(bytes: bytes, start: 0, end: bytes.count)!

    XCTAssertEqual(
      swiftmutTernaryConditionStart(bytes: bytes, before: question, lineStart: 0),
      8)
  }

  func testTernaryConditionStartUsesTopLevelCommaBoundary() {
    let bytes = Array(#"prefix(value: 1), object.value ? yes : no"#.utf8)
    let question = swiftmutTopLevelTernaryQuestionIndex(bytes: bytes, start: 0, end: bytes.count)!

    XCTAssertEqual(
      swiftmutTernaryConditionStart(bytes: bytes, before: question, lineStart: 0),
      17)
  }

  func testTernaryConditionStartIgnoresNestedAndComparisonEquals() {
    let bytes = Array(#"lhs == rhs && call(value = "ignored ?") ? yes : no"#.utf8)
    let question = swiftmutTopLevelTernaryQuestionIndex(bytes: bytes, start: 0, end: bytes.count)!

    XCTAssertEqual(
      swiftmutTernaryConditionStart(bytes: bytes, before: question, lineStart: 0),
      0)
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

  func testSourceLookupCacheCachesNumberedSourceLines() throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("swiftmut-support-numbered-line-tests-\(UUID().uuidString)")
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

    let lines = cache.numberedSourceLines(path: source.path)
    XCTAssertEqual(lines?.map(\.number), [1, 2])
    XCTAssertEqual(lines?.map(\.text), ["alpha", "béta"])
    XCTAssertEqual(cache.numberedSourceLines(path: source.path)?.map(\.text), ["alpha", "béta"])
  }

  func testSourceLookupCacheCachesSourceSnippetMatches() throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("swiftmut-support-snippet-tests-\(UUID().uuidString)")
    let source = directory
      .appendingPathComponent("Sources")
      .appendingPathComponent("App")
      .appendingPathComponent("Feature.swift")
    try FileManager.default.createDirectory(
      at: source.deletingLastPathComponent(),
      withIntermediateDirectories: true)
    try """
    alpha call()
    béta call()
    call()
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

    let expected = [
      SwiftmutSourceSnippetMatch(line: 1, column: 7, offset: 6),
      SwiftmutSourceSnippetMatch(line: 2, column: 7, offset: 19),
      SwiftmutSourceSnippetMatch(line: 3, column: 1, offset: 26),
    ]
    XCTAssertEqual(cache.sourceSnippetMatches("call()", path: source.path), expected)
    XCTAssertEqual(cache.sourceSnippetMatches("call()", path: source.path), expected)
  }
}
