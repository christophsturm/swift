// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for Swift project authors

import SwiftmutSupport

func swiftmutTopLevelASCIIContains(
  _ bytes: [UInt8],
  start: Int,
  end: Int,
  pattern: String
) -> Bool {
  SwiftmutSupport.swiftmutTopLevelASCIIContains(
    bytes,
    start: start,
    end: end,
    pattern: pattern)
}

func swiftmutTopLevelASCIIIndex(
  _ bytes: [UInt8],
  start: Int,
  end: Int,
  pattern: String
) -> Int? {
  SwiftmutSupport.swiftmutTopLevelASCIIIndex(bytes, start: start, end: end, pattern: pattern)
}

func swiftmutTopLevelByteIndex(
  _ bytes: [UInt8],
  start: Int,
  end: Int,
  byte: UInt8
) -> Int? {
  SwiftmutSupport.swiftmutTopLevelByteIndex(bytes, start: start, end: end, byte: byte)
}

func swiftmutLineOpensFunctionBody(_ line: String) -> Bool {
  SwiftmutSupport.swiftmutLineOpensFunctionBody(line)
}

func swiftmutFirstTopLevelIndex(
  _ bytes: [UInt8],
  start: Int,
  end: Int,
  matches: (Int) -> Bool
) -> Int? {
  SwiftmutSupport.swiftmutFirstTopLevelIndex(
    bytes,
    start: start,
    end: end,
    matches: matches)
}

func swiftmutSourceExpressionIsSingleLineComplete(
  bytes: [UInt8],
  start: Int,
  end: Int
) -> Bool {
  SwiftmutSupport.swiftmutSourceExpressionIsSingleLineComplete(
    bytes: bytes,
    start: start,
    end: end)
}

func swiftmutTrimTrailingHorizontalWhitespace(_ bytes: [UInt8], end: Int) -> Int {
  SwiftmutSupport.swiftmutTrimTrailingHorizontalWhitespace(bytes, end: end)
}

func swiftmutTrimmedHorizontalWhitespace(_ text: String) -> String {
  SwiftmutSupport.swiftmutTrimmedHorizontalWhitespace(text)
}

func swiftmutSkipHorizontalWhitespace(_ bytes: [UInt8], from start: Int) -> Int {
  SwiftmutSupport.swiftmutSkipHorizontalWhitespace(bytes, from: start)
}

func swiftmutASCIIContains(_ bytes: [UInt8], start: Int, end: Int, pattern: String) -> Bool {
  SwiftmutSupport.swiftmutASCIIContains(bytes, start: start, end: end, pattern: pattern)
}

func swiftmutASCIIIndex(_ bytes: [UInt8], start: Int, end: Int, pattern: String) -> Int? {
  SwiftmutSupport.swiftmutASCIIIndex(bytes, start: start, end: end, pattern: pattern)
}

func swiftmutASCIIHasExactPrefix(_ bytes: [UInt8], start: Int, prefix: String) -> Bool {
  SwiftmutSupport.swiftmutASCIIHasExactPrefix(bytes, start: start, prefix: prefix)
}

func swiftmutASCIIHasPrefix(_ bytes: [UInt8], start: Int, prefix: String) -> Bool {
  SwiftmutSupport.swiftmutASCIIHasPrefix(bytes, start: start, prefix: prefix)
}

func swiftmutASCIILowercase(_ byte: UInt8) -> UInt8 {
  SwiftmutSupport.swiftmutASCIILowercase(byte)
}

func swiftmutIsASCIIIdentifierStart(_ byte: UInt8) -> Bool {
  SwiftmutSupport.swiftmutIsASCIIIdentifierStart(byte)
}

func swiftmutIsASCIILetterNumberOrUnderscore(_ byte: UInt8) -> Bool {
  SwiftmutSupport.swiftmutIsASCIILetterNumberOrUnderscore(byte)
}

func swiftmutIsHorizontalWhitespace(_ byte: UInt8) -> Bool {
  SwiftmutSupport.swiftmutIsHorizontalWhitespace(byte)
}
