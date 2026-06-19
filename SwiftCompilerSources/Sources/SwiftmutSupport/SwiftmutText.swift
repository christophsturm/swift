//===--- SwiftmutText.swift -----------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2026 swiftmut contributors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

public func swiftmutTopLevelASCIIContains(
  _ bytes: [UInt8],
  start: Int,
  end: Int,
  pattern: String
) -> Bool {
  swiftmutTopLevelASCIIIndex(bytes, start: start, end: end, pattern: pattern) != nil
}

public func swiftmutTopLevelASCIIIndex(
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
  let firstPatternByte = patternBytes[0]
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
    if parenDepth == 0 && bracketDepth == 0 && braceDepth == 0 && byte == firstPatternByte {
      if swiftmutBytesHaveExactPrefix(bytes, start: index, end: end, prefix: patternBytes) {
        return index
      }
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

public func swiftmutTopLevelByteIndex(
  _ bytes: [UInt8],
  start: Int,
  end: Int,
  byte: UInt8
) -> Int? {
  var parenDepth = 0
  var bracketDepth = 0
  var braceDepth = 0
  var quote: UInt8?
  var escaped = false
  var index = start
  while index < end {
    let currentByte = bytes[index]
    if let activeQuote = quote {
      if escaped {
        escaped = false
      } else if currentByte == 92 {
        escaped = true
      } else if currentByte == activeQuote {
        quote = nil
      }
      index += 1
      continue
    }
    if currentByte == 34 || currentByte == 39 {
      quote = currentByte
      index += 1
      continue
    }
    if parenDepth == 0 && bracketDepth == 0 && braceDepth == 0 && currentByte == byte {
      return index
    }
    switch currentByte {
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

public func swiftmutLineOpensFunctionBody(_ line: String) -> Bool {
  let bytes = Array(line.utf8)
  let start = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
  let end = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  return swiftmutTopLevelByteIndex(bytes, start: start, end: end, byte: 123) != nil
}

public func swiftmutBalancedExpressionEnd(
  in bytes: [UInt8],
  openIndex: Int,
  close: UInt8,
  lineEnd: Int
) -> Int? {
  let open = bytes[openIndex]
  var depth = 0
  var index = openIndex
  var quote: UInt8?
  var escaped = false
  while index < lineEnd {
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
    if byte == open {
      depth += 1
    } else if byte == close {
      depth -= 1
      if depth == 0 {
        return index + 1
      }
    }
    index += 1
  }
  return nil
}

public func swiftmutTopLevelTernaryQuestionIndex(bytes: [UInt8], start: Int, end: Int) -> Int? {
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
    if parenDepth == 0 && bracketDepth == 0 && braceDepth == 0 && byte == 63 {
      let previous = index > start ? bytes[index - 1] : 0
      let next = index + 1 < end ? bytes[index + 1] : 0
      if previous != 63 && next != 63 {
        return index
      }
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

public func swiftmutLastTopLevelAssignmentEqualsBefore(bytes: [UInt8], start: Int, end: Int) -> Int? {
  var parenDepth = 0
  var bracketDepth = 0
  var braceDepth = 0
  var quote: UInt8?
  var escaped = false
  var result: Int?
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
    if parenDepth == 0 && bracketDepth == 0 && braceDepth == 0 && byte == 61 {
      let previous = index > start ? bytes[index - 1] : 0
      let next = index + 1 < end ? bytes[index + 1] : 0
      if previous != 33 && previous != 60 && previous != 61 && previous != 62 && next != 61 {
        result = index
      }
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
  return result
}

public func swiftmutLastTopLevelByteBefore(bytes: [UInt8], start: Int, end: Int, byte: UInt8) -> Int? {
  var parenDepth = 0
  var bracketDepth = 0
  var braceDepth = 0
  var quote: UInt8?
  var escaped = false
  var result: Int?
  var index = start
  while index < end {
    let currentByte = bytes[index]
    if let activeQuote = quote {
      if escaped {
        escaped = false
      } else if currentByte == 92 {
        escaped = true
      } else if currentByte == activeQuote {
        quote = nil
      }
      index += 1
      continue
    }
    if currentByte == 34 || currentByte == 39 {
      quote = currentByte
      index += 1
      continue
    }
    if parenDepth == 0 && bracketDepth == 0 && braceDepth == 0 && currentByte == byte {
      result = index
    }
    switch currentByte {
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
  return result
}

public struct SwiftmutTopLevelTernaryParts: Equatable {
  public let question: Int
  public let colonAfterQuestion: Int
  public let assignmentBeforeQuestion: Int?
  public let labelColonBeforeQuestion: Int?
  public let commaBeforeQuestion: Int?

  public init(
    question: Int,
    colonAfterQuestion: Int,
    assignmentBeforeQuestion: Int?,
    labelColonBeforeQuestion: Int?,
    commaBeforeQuestion: Int? = nil
  ) {
    self.question = question
    self.colonAfterQuestion = colonAfterQuestion
    self.assignmentBeforeQuestion = assignmentBeforeQuestion
    self.labelColonBeforeQuestion = labelColonBeforeQuestion
    self.commaBeforeQuestion = commaBeforeQuestion
  }
}

public func swiftmutTopLevelTernaryParts(
  bytes: [UInt8],
  start: Int,
  end: Int
) -> SwiftmutTopLevelTernaryParts? {
  var parenDepth = 0
  var bracketDepth = 0
  var braceDepth = 0
  var quote: UInt8?
  var escaped = false
  var question: Int?
  var assignmentBeforeQuestion: Int?
  var labelColonBeforeQuestion: Int?
  var commaBeforeQuestion: Int?
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
    let atTopLevel = parenDepth == 0 && bracketDepth == 0 && braceDepth == 0
    if atTopLevel {
      if let questionIndex = question {
        if byte == 58 {
          return SwiftmutTopLevelTernaryParts(
            question: questionIndex,
            colonAfterQuestion: index,
            assignmentBeforeQuestion: assignmentBeforeQuestion,
            labelColonBeforeQuestion: labelColonBeforeQuestion,
            commaBeforeQuestion: commaBeforeQuestion)
        }
      } else if byte == 63 {
        let previous = index > start ? bytes[index - 1] : 0
        let next = index + 1 < end ? bytes[index + 1] : 0
        if previous != 63 && next != 63 {
          question = index
        }
      } else if byte == 61 {
        let previous = index > start ? bytes[index - 1] : 0
        let next = index + 1 < end ? bytes[index + 1] : 0
        if previous != 33 && previous != 60 && previous != 61 && previous != 62 && next != 61 {
          assignmentBeforeQuestion = index
        }
      } else if byte == 58 {
        labelColonBeforeQuestion = index
      } else if byte == 44 {
        commaBeforeQuestion = index
      }
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

public func swiftmutTernaryConditionStart(
  bytes: [UInt8],
  before questionIndex: Int,
  lineStart: Int
) -> Int {
  var index = questionIndex
  var parenDepth = 0
  var bracketDepth = 0
  var braceDepth = 0
  var quote: UInt8?
  var escaped = false
  while index > lineStart {
    index -= 1
    let byte = bytes[index]
    if let activeQuote = quote {
      if escaped {
        escaped = false
      } else if byte == 92 {
        escaped = true
      } else if byte == activeQuote {
        quote = nil
      }
      continue
    }
    if byte == 34 || byte == 39 {
      quote = byte
      continue
    }
    switch byte {
    case 41:
      parenDepth += 1
    case 40:
      if parenDepth > 0 {
        parenDepth -= 1
      }
    case 93:
      bracketDepth += 1
    case 91:
      if bracketDepth > 0 {
        bracketDepth -= 1
      }
    case 125:
      braceDepth += 1
    case 123:
      if braceDepth > 0 {
        braceDepth -= 1
      }
    case 61:
      if parenDepth == 0
          && bracketDepth == 0
          && braceDepth == 0
          && swiftmutTernaryConditionStartEqualsIsBoundary(
            bytes: bytes,
            index: index,
            lineStart: lineStart,
            questionIndex: questionIndex
          ) {
        return index + 1
      }
    case 44:
      if parenDepth == 0 && bracketDepth == 0 && braceDepth == 0 {
        return index + 1
      }
    default:
      break
    }
  }
  return lineStart
}

private func swiftmutTernaryConditionStartEqualsIsBoundary(
  bytes: [UInt8],
  index: Int,
  lineStart: Int,
  questionIndex: Int
) -> Bool {
  if index > lineStart {
    let previous = bytes[index - 1]
    if previous == 33 || previous == 60 || previous == 61 || previous == 62 {
      return false
    }
  }
  if index + 1 < questionIndex,
     bytes[index + 1] == 61 {
    return false
  }
  return true
}

public func swiftmutSourceDeclarationKeywordAt(bytes: [UInt8], index: Int) -> Bool {
  if swiftmutASCIIHasExactPrefix(bytes, start: index, prefix: "func ") {
    return index == 0 || !swiftmutIsASCIILetterNumberOrUnderscore(bytes[index - 1])
  }
  if swiftmutASCIIHasExactPrefix(bytes, start: index, prefix: "init(") {
    return index == 0 || !swiftmutIsASCIILetterNumberOrUnderscore(bytes[index - 1])
  }
  if swiftmutASCIIHasExactPrefix(bytes, start: index, prefix: "init?(") {
    return index == 0 || !swiftmutIsASCIILetterNumberOrUnderscore(bytes[index - 1])
  }
  if swiftmutASCIIHasExactPrefix(bytes, start: index, prefix: "init!(") {
    return index == 0 || !swiftmutIsASCIILetterNumberOrUnderscore(bytes[index - 1])
  }
  return false
}

public func swiftmutSourceDeclarationParameterList(
  bytes: [UInt8],
  from keywordStart: Int
) -> (start: Int, end: Int)? {
  guard let openParen = swiftmutFindDeclarationOpenParen(bytes: bytes, from: keywordStart),
        let closeParen = swiftmutFindMatchingSourceDelimiter(
          bytes: bytes,
          openOffset: openParen,
          open: 40,
          close: 41
        ) else {
    return nil
  }
  return (openParen + 1, closeParen)
}

public func swiftmutFindDeclarationOpenParen(bytes: [UInt8], from offset: Int) -> Int? {
  var index = offset
  let limit = min(bytes.count, offset + 320)
  var angleDepth = 0
  var inString = false
  var escaped = false
  while index < limit {
    let byte = bytes[index]
    if inString {
      if escaped {
        escaped = false
      } else if byte == 92 {
        escaped = true
      } else if byte == 34 {
        inString = false
      }
      index += 1
      continue
    }
    if byte == 34 {
      inString = true
    } else if byte == 10 || byte == 123 {
      return nil
    } else if byte == 60 {
      angleDepth += 1
    } else if byte == 62 && angleDepth > 0 {
      angleDepth -= 1
    } else if byte == 40 && angleDepth == 0 {
      return index
    }
    index += 1
  }
  return nil
}

public func swiftmutFindMatchingSourceDelimiter(
  bytes: [UInt8],
  openOffset: Int,
  open: UInt8,
  close: UInt8
) -> Int? {
  var depth = 0
  var index = openOffset
  var inString = false
  var escaped = false
  while index < bytes.count {
    let byte = bytes[index]
    if inString {
      if escaped {
        escaped = false
      } else if byte == 92 {
        escaped = true
      } else if byte == 34 {
        inString = false
      }
      index += 1
      continue
    }
    if byte == 34 {
      inString = true
    } else if byte == open {
      depth += 1
    } else if byte == close {
      depth -= 1
      if depth == 0 {
        return index
      }
    }
    index += 1
  }
  return nil
}

public func swiftmutTopLevelEquals(bytes: [UInt8], start: Int, end: Int) -> Int? {
  var index = start
  var squareDepth = 0
  var parenDepth = 0
  var braceDepth = 0
  var inString = false
  var escaped = false
  while index < end {
    let byte = bytes[index]
    if inString {
      if escaped {
        escaped = false
      } else if byte == 92 {
        escaped = true
      } else if byte == 34 {
        inString = false
      }
      index += 1
      continue
    }
    if byte == 34 {
      inString = true
    } else if byte == 91 {
      squareDepth += 1
    } else if byte == 93 {
      squareDepth -= 1
    } else if byte == 40 {
      parenDepth += 1
    } else if byte == 41 {
      parenDepth -= 1
    } else if byte == 123 {
      braceDepth += 1
    } else if byte == 125 {
      braceDepth -= 1
    } else if byte == 61 && squareDepth == 0 && parenDepth == 0 && braceDepth == 0 {
      return index
    }
    index += 1
  }
  return nil
}

public func swiftmutFirstTopLevelIndex(
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

public func swiftmutSourceExpressionIsSingleLineComplete(
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

public func swiftmutTrimTrailingHorizontalWhitespace(_ bytes: [UInt8], end: Int) -> Int {
  var index = end
  while index > 0 && swiftmutIsHorizontalWhitespace(bytes[index - 1]) {
    index -= 1
  }
  return index
}

public func swiftmutSkipHorizontalWhitespace(_ bytes: [UInt8], from start: Int) -> Int {
  var index = start
  while index < bytes.count && swiftmutIsHorizontalWhitespace(bytes[index]) {
    index += 1
  }
  return index
}

public func swiftmutASCIIContains(_ bytes: [UInt8], start: Int, end: Int, pattern: String) -> Bool {
  swiftmutASCIIIndex(bytes, start: start, end: end, pattern: pattern) != nil
}

public func swiftmutASCIIIndex(_ bytes: [UInt8], start: Int, end: Int, pattern: String) -> Int? {
  let patternBytes = Array(pattern.utf8)
  guard !patternBytes.isEmpty,
        start >= 0,
        start <= end,
        end <= bytes.count,
        patternBytes.count <= end - start else {
    return nil
  }

  let firstPatternByte = patternBytes[0]
  var index = start
  while index <= end - patternBytes.count {
    if bytes[index] == firstPatternByte,
       swiftmutBytesHaveExactPrefix(bytes, start: index, end: end, prefix: patternBytes) {
      return index
    }
    index += 1
  }
  return nil
}

public func swiftmutASCIIHasExactPrefix(_ bytes: [UInt8], start: Int, prefix: String) -> Bool {
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

public func swiftmutASCIIHasPrefix(_ bytes: [UInt8], start: Int, prefix: String) -> Bool {
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

public func swiftmutASCIILowercase(_ byte: UInt8) -> UInt8 {
  if byte >= 65 && byte <= 90 {
    return byte + 32
  }
  return byte
}

public func swiftmutIsASCIIIdentifierStart(_ byte: UInt8) -> Bool {
  if byte >= 65 && byte <= 90 {
    return true
  }
  if byte >= 97 && byte <= 122 {
    return true
  }
  return byte == 95
}

public func swiftmutIsASCIILetterNumberOrUnderscore(_ byte: UInt8) -> Bool {
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

public func swiftmutIsHorizontalWhitespace(_ byte: UInt8) -> Bool {
  byte == 32 || byte == 9
}

private func swiftmutBytesHaveExactPrefix(
  _ bytes: [UInt8],
  start: Int,
  end: Int,
  prefix: [UInt8]
) -> Bool {
  guard start + prefix.count <= end else {
    return false
  }
  for offset in 0..<prefix.count where bytes[start + offset] != prefix[offset] {
    return false
  }
  return true
}
