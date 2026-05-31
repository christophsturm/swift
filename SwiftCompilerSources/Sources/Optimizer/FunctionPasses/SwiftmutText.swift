// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for Swift project authors

func swiftmutTopLevelASCIIContains(
  _ bytes: [UInt8],
  start: Int,
  end: Int,
  pattern: String
) -> Bool {
  swiftmutTopLevelASCIIIndex(bytes, start: start, end: end, pattern: pattern) != nil
}

func swiftmutTopLevelASCIIIndex(
  _ bytes: [UInt8],
  start: Int,
  end: Int,
  pattern: String
) -> Int? {
  let patternBytes = Array(pattern.utf8)
  guard !patternBytes.isEmpty,
        start < end,
        patternBytes.count <= end - start else {
    return nil
  }
  return swiftmutFirstTopLevelIndex(bytes, start: start, end: end) { index in
    guard index + patternBytes.count <= end else {
      return false
    }
    for offset in 0..<patternBytes.count where bytes[index + offset] != patternBytes[offset] {
      return false
    }
    return true
  }
}

func swiftmutTopLevelByteIndex(
  _ bytes: [UInt8],
  start: Int,
  end: Int,
  byte: UInt8
) -> Int? {
  swiftmutFirstTopLevelIndex(bytes, start: start, end: end) { index in
    bytes[index] == byte
  }
}

func swiftmutLineOpensFunctionBody(_ line: String) -> Bool {
  let bytes = Array(line.utf8)
  let start = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
  let end = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  return swiftmutTopLevelByteIndex(bytes, start: start, end: end, byte: 123) != nil
}

func swiftmutFirstTopLevelIndex(
  _ bytes: [UInt8],
  start: Int,
  end: Int,
  matches: (Int) -> Bool
) -> Int? {
  var parenDepth = 0
  var bracketDepth = 0
  var braceDepth = 0
  var quote: UInt8?
  var escaped = false
  var index = start
  while index < end {
    let byte = bytes[index]
    if let activeQuote = quote {
      if escaped {
        escaped = false
      } else if byte == 92 {
        escaped = true
      } else if byte == activeQuote {
        quote = nil
      }
      index += 1
      continue
    }
    if byte == 34 || byte == 39 {
      quote = byte
      index += 1
      continue
    }
    if parenDepth == 0 && bracketDepth == 0 && braceDepth == 0 && matches(index) {
      return index
    }
    switch byte {
    case 40:
      parenDepth += 1
    case 41:
      if parenDepth > 0 { parenDepth -= 1 }
    case 91:
      bracketDepth += 1
    case 93:
      if bracketDepth > 0 { bracketDepth -= 1 }
    case 123:
      braceDepth += 1
    case 125:
      if braceDepth > 0 { braceDepth -= 1 }
    default:
      break
    }
    index += 1
  }
  return nil
}

func swiftmutSourceExpressionIsSingleLineComplete(
  bytes: [UInt8],
  start: Int,
  end: Int
) -> Bool {
  var parenDepth = 0
  var bracketDepth = 0
  var braceDepth = 0
  var quote: UInt8?
  var escaped = false
  var index = start
  while index < end {
    let byte = bytes[index]
    if let activeQuote = quote {
      if escaped {
        escaped = false
      } else if byte == 92 {
        escaped = true
      } else if byte == activeQuote {
        quote = nil
      }
      index += 1
      continue
    }
    if byte == 34 || byte == 39 {
      quote = byte
      index += 1
      continue
    }
    switch byte {
    case 40:
      parenDepth += 1
    case 41:
      parenDepth -= 1
      if parenDepth < 0 { return false }
    case 91:
      bracketDepth += 1
    case 93:
      bracketDepth -= 1
      if bracketDepth < 0 { return false }
    case 123:
      braceDepth += 1
    case 125:
      braceDepth -= 1
      if braceDepth < 0 { return false }
    default:
      break
    }
    index += 1
  }
  return quote == nil && parenDepth == 0 && bracketDepth == 0 && braceDepth == 0
}

func swiftmutTrimTrailingHorizontalWhitespace(_ bytes: [UInt8], end: Int) -> Int {
  var index = end
  while index > 0 && swiftmutIsHorizontalWhitespace(bytes[index - 1]) {
    index -= 1
  }
  return index
}

func swiftmutSkipHorizontalWhitespace(_ bytes: [UInt8], from start: Int) -> Int {
  var index = start
  while index < bytes.count && swiftmutIsHorizontalWhitespace(bytes[index]) {
    index += 1
  }
  return index
}

func swiftmutASCIIContains(_ bytes: [UInt8], start: Int, end: Int, pattern: String) -> Bool {
  swiftmutASCIIIndex(bytes, start: start, end: end, pattern: pattern) != nil
}

func swiftmutASCIIIndex(_ bytes: [UInt8], start: Int, end: Int, pattern: String) -> Int? {
  let patternBytes = Array(pattern.utf8)
  guard !patternBytes.isEmpty,
        start >= 0,
        start <= end,
        end <= bytes.count,
        patternBytes.count <= end - start else {
    return nil
  }

  var index = start
  while index <= end - patternBytes.count {
    var matched = true
    for offset in 0..<patternBytes.count {
      if bytes[index + offset] != patternBytes[offset] {
        matched = false
        break
      }
    }
    if matched {
      return index
    }
    index += 1
  }
  return nil
}

func swiftmutASCIIHasExactPrefix(_ bytes: [UInt8], start: Int, prefix: String) -> Bool {
  let prefixBytes = Array(prefix.utf8)
  guard start >= 0 && start + prefixBytes.count <= bytes.count else {
    return false
  }
  for offset in 0..<prefixBytes.count {
    if bytes[start + offset] != prefixBytes[offset] {
      return false
    }
  }
  return true
}

func swiftmutASCIIHasPrefix(_ bytes: [UInt8], start: Int, prefix: String) -> Bool {
  let prefixBytes = Array(prefix.utf8)
  guard start >= 0 && start + prefixBytes.count <= bytes.count else {
    return false
  }
  for offset in 0..<prefixBytes.count {
    if swiftmutASCIILowercase(bytes[start + offset]) != swiftmutASCIILowercase(prefixBytes[offset]) {
      return false
    }
  }
  return true
}

func swiftmutASCIILowercase(_ byte: UInt8) -> UInt8 {
  if byte >= 65 && byte <= 90 {
    return byte + 32
  }
  return byte
}

func swiftmutIsASCIIIdentifierStart(_ byte: UInt8) -> Bool {
  if byte >= 65 && byte <= 90 {
    return true
  }
  if byte >= 97 && byte <= 122 {
    return true
  }
  return byte == 95
}

func swiftmutIsASCIILetterNumberOrUnderscore(_ byte: UInt8) -> Bool {
  if byte >= 48 && byte <= 57 {
    return true
  }
  if byte >= 65 && byte <= 90 {
    return true
  }
  if byte >= 97 && byte <= 122 {
    return true
  }
  return byte == 95
}

func swiftmutIsHorizontalWhitespace(_ byte: UInt8) -> Bool {
  byte == 32 || byte == 9
}
