// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for Swift project authors

import SwiftmutSupport

func swiftmutTopLevelTernaryQuestionIndex(bytes: [UInt8], start: Int, end: Int) -> Int? {
  SwiftmutSupport.swiftmutTopLevelTernaryQuestionIndex(bytes: bytes, start: start, end: end)
}

func swiftmutLastTopLevelAssignmentEqualsBefore(bytes: [UInt8], start: Int, end: Int) -> Int? {
  SwiftmutSupport.swiftmutLastTopLevelAssignmentEqualsBefore(bytes: bytes, start: start, end: end)
}

func swiftmutLastTopLevelByteBefore(bytes: [UInt8], start: Int, end: Int, byte: UInt8) -> Int? {
  SwiftmutSupport.swiftmutLastTopLevelByteBefore(bytes: bytes, start: start, end: end, byte: byte)
}

func swiftmutTopLevelTernaryParts(
  bytes: [UInt8],
  start: Int,
  end: Int
) -> SwiftmutSupport.SwiftmutTopLevelTernaryParts? {
  SwiftmutSupport.swiftmutTopLevelTernaryParts(bytes: bytes, start: start, end: end)
}
