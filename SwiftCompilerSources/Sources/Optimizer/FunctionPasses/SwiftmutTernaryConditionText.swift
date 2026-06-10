// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for Swift project authors

func swiftmutTopLevelTernaryQuestionIndex(bytes: [UInt8], start: Int, end: Int) -> Int? {
  var searchStart = start
  while let question = swiftmutTopLevelByteIndex(bytes, start: searchStart, end: end, byte: 63) {
    let previous = question > start ? bytes[question - 1] : 0
    let next = question + 1 < end ? bytes[question + 1] : 0
    if previous != 63 && next != 63 {
      return question
    }
    searchStart = question + 1
  }
  return nil
}

func swiftmutLastTopLevelAssignmentEqualsBefore(bytes: [UInt8], start: Int, end: Int) -> Int? {
  var searchStart = start
  var result: Int?
  while let equals = swiftmutTopLevelByteIndex(bytes, start: searchStart, end: end, byte: 61) {
    let previous = equals > start ? bytes[equals - 1] : 0
    let next = equals + 1 < end ? bytes[equals + 1] : 0
    if previous != 33 && previous != 60 && previous != 61 && previous != 62 && next != 61 {
      result = equals
    }
    searchStart = equals + 1
  }
  return result
}

func swiftmutLastTopLevelByteBefore(bytes: [UInt8], start: Int, end: Int, byte: UInt8) -> Int? {
  var searchStart = start
  var result: Int?
  while let index = swiftmutTopLevelByteIndex(bytes, start: searchStart, end: end, byte: byte) {
    result = index
    searchStart = index + 1
  }
  return result
}
