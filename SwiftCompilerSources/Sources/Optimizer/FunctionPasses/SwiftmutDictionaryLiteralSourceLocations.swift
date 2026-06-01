//===--- SwiftmutDictionaryLiteralSourceLocations.swift ----------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2026 swiftmut contributors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

import AST
import SIL

func swiftmutFindDictionaryLiteralValueSourceLocation(
  for apply: ApplyInst,
  path: String,
  functionLine: Int,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard functionLine > 0,
        mutation.mutatedBuiltinName == "return_empty_dictionary",
        swiftmutIsDictionaryLiteralApply(apply),
        let ordinal = swiftmutDictionaryLiteralApplyOrdinalAndCount(
          for: apply,
          mutation: mutation,
          config: config
        ),
        let text = swiftmutRead(path) else {
    return nil
  }

  let candidates = swiftmutDictionaryLiteralExpressionCandidates(
    in: text,
    path: path,
    functionLine: functionLine,
    expectedCount: ordinal.count,
    mutation: mutation,
    config: config
  )
  guard candidates.count == ordinal.count,
        ordinal.ordinal > 0,
        ordinal.ordinal <= candidates.count else {
    return nil
  }
  return candidates[ordinal.ordinal - 1]
}

func swiftmutDictionaryLiteralApplyOrdinalAndCount(
  for apply: ApplyInst,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (ordinal: Int, count: Int)? {
  var ordinal = 0
  var count = 0
  var foundApply = false

  for block in apply.parentFunction.blocks {
    for instruction in block.instructions {
      guard let candidate = instruction as? ApplyInst,
            swiftmutIsDictionaryLiteralApply(candidate),
            swiftmutValueReplacementMutations(
              for: candidate,
              valueType: candidate.type,
              config: config
            ).contains(where: { $0.mutatedBuiltinName == mutation.mutatedBuiltinName }) else {
        continue
      }
      count += 1
      if candidate === apply {
        ordinal = count
        foundApply = true
      }
    }
  }

  guard foundApply,
        count <= 200 else {
    return nil
  }
  return (ordinal, count)
}

func swiftmutIsDictionaryLiteralApply(_ apply: ApplyInst) -> Bool {
  apply.callee.description.contains("Dictionary.init(dictionaryLiteral:)")
}

func swiftmutDictionaryLiteralExpressionCandidates(
  in text: String,
  path: String,
  functionLine: Int,
  expectedCount: Int,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> [(file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)] {
  var candidates: [(file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)] = []
  var currentLine = 1
  var lineStart = text.startIndex
  var lineStartUTF8Offset = 0
  var index = text.startIndex
  var braceDepth = 0
  var sawOpeningBrace = false

  func inspectLine(_ lineText: String, line: Int, lineStartUTF8Offset: Int) {
    guard line >= functionLine,
          candidates.count <= expectedCount else {
      return
    }
    for expression in swiftmutDictionaryLiteralExpressions(
      in: text,
      lineText: lineText,
      lineStartUTF8Offset: lineStartUTF8Offset,
      mutation: mutation
    ) {
      candidates.append((
        swiftmutTrimPackageRoot(path, config: config),
        line,
        expression.column,
        expression.sourceOriginal,
        expression.sourceMutated
      ))
      if candidates.count > expectedCount {
        return
      }
    }
  }

  func updateBraceDepth(_ lineText: String) {
    for byte in lineText.utf8 {
      if byte == 123 {
        braceDepth += 1
        sawOpeningBrace = true
      } else if byte == 125 {
        braceDepth -= 1
      }
    }
  }

  while index < text.endIndex {
    if text[index] == "\n" {
      let lineText = String(text[lineStart..<index])
      if currentLine >= functionLine {
        if sawOpeningBrace && braceDepth > 0 {
          inspectLine(lineText, line: currentLine, lineStartUTF8Offset: lineStartUTF8Offset)
          if candidates.count > expectedCount {
            break
          }
        }
        updateBraceDepth(lineText)
        if sawOpeningBrace && braceDepth <= 0 {
          break
        }
      }
      currentLine += 1
      lineStartUTF8Offset += lineText.utf8.count + 1
      lineStart = text.index(after: index)
    }
    index = text.index(after: index)
  }

  if index == text.endIndex && currentLine >= functionLine && sawOpeningBrace && braceDepth > 0 {
    inspectLine(
      String(text[lineStart..<text.endIndex]),
      line: currentLine,
      lineStartUTF8Offset: lineStartUTF8Offset
    )
  }
  return candidates
}

func swiftmutDictionaryLiteralExpressions(
  in text: String,
  lineText: String,
  lineStartUTF8Offset: Int,
  mutation: SwiftmutMutation
) -> [(column: Int, sourceOriginal: String, sourceMutated: String)] {
  let bytes = Array(lineText.utf8)
  let lineEnd = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  var expressions: [(column: Int, sourceOriginal: String, sourceMutated: String)] = []
  var index = 0

  while index < lineEnd {
    guard bytes[index] == 91,
          swiftmutDictionaryLiteralHasExpressionPrefix(bytes: bytes, openIndex: index),
          let openIndex = swiftmutStringIndex(in: text, utf8Offset: lineStartUTF8Offset + index),
          let closeIndex = swiftmutDictionaryLiteralEnd(in: text, openIndex: openIndex) else {
      index += 1
      continue
    }

    let sourceOriginal = String(text[openIndex..<closeIndex])
    let sourceBytes = Array(sourceOriginal.utf8)
    guard !sourceBytes.isEmpty else {
      index += 1
      continue
    }
    if swiftmutDictionaryLiteralHasExpressionSuffix(in: text, closeIndex: closeIndex),
       swiftmutDictionaryLiteralContainsTopLevelColon(
         bytes: sourceBytes,
         start: 1,
         end: sourceBytes.count - 1
       ),
       swiftmutReturnValueIsEligible(bytes: sourceBytes, start: 0, mutation: mutation) {
      expressions.append((
        index + 1,
        sourceOriginal,
        swiftmutImplicitReturnSourceMutation(for: mutation)
      ))
    }
    index += 1
  }
  return expressions
}

func swiftmutDictionaryLiteralHasExpressionPrefix(bytes: [UInt8], openIndex: Int) -> Bool {
  var index = openIndex
  while index > 0 && swiftmutIsHorizontalWhitespace(bytes[index - 1]) {
    index -= 1
  }
  guard index > 0 else {
    return true
  }
  let previous = bytes[index - 1]
  return previous == 40 || previous == 44 || previous == 61 || previous == 123
}

func swiftmutDictionaryLiteralHasExpressionSuffix(in text: String, closeIndex: String.Index) -> Bool {
  var index = closeIndex
  while index < text.endIndex && (text[index] == " " || text[index] == "\t" || text[index] == "\n") {
    index = text.index(after: index)
  }
  guard index < text.endIndex else {
    return true
  }
  let next = text[index]
  return next == ")" || next == "," || next == "]" || next == "}"
}

func swiftmutDictionaryLiteralEnd(in text: String, openIndex: String.Index) -> String.Index? {
  var depth = 0
  var index = openIndex
  var quote: Character?
  var escaped = false
  while index < text.endIndex {
    let character = text[index]
    if let activeQuote = quote {
      if escaped {
        escaped = false
      } else if character == "\\" {
        escaped = true
      } else if character == activeQuote {
        quote = nil
      }
      index = text.index(after: index)
      continue
    }
    if character == "\"" || character == "'" {
      quote = character
    } else if character == "[" {
      depth += 1
    } else if character == "]" {
      depth -= 1
      if depth == 0 {
        return text.index(after: index)
      }
    }
    index = text.index(after: index)
  }
  return nil
}

func swiftmutDictionaryLiteralContainsTopLevelColon(bytes: [UInt8], start: Int, end: Int) -> Bool {
  var index = start
  var parenDepth = 0
  var bracketDepth = 0
  var braceDepth = 0
  var quote: UInt8?
  var escaped = false

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
    } else if byte == 34 || byte == 39 {
      quote = byte
    } else if byte == 40 {
      parenDepth += 1
    } else if byte == 41 && parenDepth > 0 {
      parenDepth -= 1
    } else if byte == 91 {
      bracketDepth += 1
    } else if byte == 93 && bracketDepth > 0 {
      bracketDepth -= 1
    } else if byte == 123 {
      braceDepth += 1
    } else if byte == 125 && braceDepth > 0 {
      braceDepth -= 1
    } else if byte == 58 && parenDepth == 0 && bracketDepth == 0 && braceDepth == 0 {
      return true
    }
    index += 1
  }
  return false
}
