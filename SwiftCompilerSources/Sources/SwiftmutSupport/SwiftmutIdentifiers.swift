//===--- SwiftmutIdentifiers.swift ----------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2026 swiftmut contributors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

public func swiftmutMangledIdentifiers(in name: String) -> [String] {
  var mangledName = name
  return mangledName.withUTF8 { bytes in
    var identifiers: [String] = []
    var index = 0
    while index < bytes.count {
      guard bytes[index] >= 48 && bytes[index] <= 57 else {
        index += 1
        continue
      }
      var length = 0
      var cursor = index
      while cursor < bytes.count && bytes[cursor] >= 48 && bytes[cursor] <= 57 {
        length = (length * 10) + Int(bytes[cursor] - 48)
        cursor += 1
      }
      guard length > 0,
            cursor + length <= bytes.count,
            swiftmutBytesAreIdentifier(bytes, start: cursor, end: cursor + length) else {
        index += 1
        continue
      }
      let identifier = String(decoding: bytes[cursor..<(cursor + length)], as: UTF8.self)
      if !identifiers.contains(identifier) {
        identifiers.append(identifier)
      }
      index = cursor + length
    }
    return identifiers
  }
}

public func swiftmutIdentifierLooksLikeSourceExpression(_ identifier: String) -> Bool {
  guard let first = identifier.utf8.first else {
    return false
  }
  return (first >= 97 && first <= 122) || first == 95
}

public func swiftmutBytesAreIdentifier(_ bytes: [UInt8], start: Int, end: Int) -> Bool {
  bytes.withUnsafeBufferPointer { buffer in
    swiftmutBytesAreIdentifier(buffer, start: start, end: end)
  }
}

public func swiftmutBytesAreIdentifier(
  _ bytes: UnsafeBufferPointer<UInt8>,
  start: Int,
  end: Int
) -> Bool {
  guard start < end else {
    return false
  }
  for index in start..<end {
    if !swiftmutIsASCIILetterNumberOrUnderscore(bytes[index]) {
      return false
    }
  }
  return true
}

public func swiftmutMangledNameContainsIdentifier(
  _ functionName: String,
  identifier: String
) -> Bool {
  guard identifier != "init" else {
    return functionName.contains("cf")
  }
  if identifier.count <= 3 {
    return functionName.contains(identifier)
  }
  if functionName.contains(identifier) {
    return true
  }
  if swiftmutMangledNameContainsIdentifierWords(functionName, identifier: identifier) {
    return true
  }
  let prefixLength = min(identifier.count, 8)
  let prefix = String(identifier.prefix(prefixLength))
  return prefix.count >= 4 && functionName.contains(prefix)
}

public func swiftmutMangledNameContainsIdentifierWords(
  _ functionName: String,
  identifier: String
) -> Bool {
  let words = swiftmutCamelCaseIdentifierWords(identifier)
  guard words.count >= 2,
        let first = words.first,
        let last = words.last,
        last.count >= 4 else {
    return false
  }
  if first.count < 3,
     words.count >= 3 {
    let firstPair = words[0] + words[1]
    if firstPair.count >= 4 {
      return functionName.contains(firstPair) && functionName.contains(last)
    }
  }
  guard first.count >= 3 else {
    return false
  }
  return functionName.contains(first) && functionName.contains(last)
}

public func swiftmutCamelCaseIdentifierWords(_ identifier: String) -> [String] {
  var identifierText = identifier
  return identifierText.withUTF8 { bytes in
    guard !bytes.isEmpty else {
      return []
    }

    var words: [String] = []
    var start = 0
    var index = 1
    while index < bytes.count {
      if swiftmutIsASCIIUppercase(bytes[index])
          && swiftmutIsASCIILowercase(bytes[index - 1]) {
        words.append(String(decoding: bytes[start..<index], as: UTF8.self))
        start = index
      }
      index += 1
    }
    words.append(String(decoding: bytes[start..<bytes.count], as: UTF8.self))
    return words.filter { !$0.isEmpty }
  }
}

public func swiftmutIsASCIIUppercase(_ byte: UInt8) -> Bool {
  byte >= 65 && byte <= 90
}

public func swiftmutIsASCIILowercase(_ byte: UInt8) -> Bool {
  byte >= 97 && byte <= 122
}
