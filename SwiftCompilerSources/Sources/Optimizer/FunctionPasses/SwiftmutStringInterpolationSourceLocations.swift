//===--- SwiftmutStringInterpolationSourceLocations.swift ----------------------------------------------===//
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

func swiftmutFindStringInterpolationValueSourceLocation(
  for apply: ApplyInst,
  path: String,
  preferredLine: Int,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard let ordinal = swiftmutStringInterpolationApplyOrdinalAndCount(
    for: apply,
    mutation: mutation,
    config: config
  ), ordinal.count <= 300,
    let text = swiftmutRead(path) else {
    return nil
  }

  let candidates = swiftmutStringInterpolationExpressionCandidates(
    in: text,
    path: path,
    preferredLine: preferredLine,
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

func swiftmutStringInterpolationApplyOrdinalAndCount(
  for apply: ApplyInst,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (ordinal: Int, count: Int)? {
  guard swiftmutIsStringInterpolationDescriptionApply(apply, mutation: mutation) else {
    return nil
  }

  var ordinal = 0
  var count = 0
  var foundApply = false
  for block in apply.parentFunction.blocks {
    for instruction in block.instructions {
      guard let candidate = instruction as? ApplyInst,
            swiftmutIsStringInterpolationDescriptionApply(candidate, mutation: mutation),
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

  guard foundApply else {
    return nil
  }
  return (ordinal, count)
}

func swiftmutIsStringInterpolationDescriptionApply(
  _ apply: ApplyInst,
  mutation: SwiftmutMutation
) -> Bool {
  guard mutation.mutatedBuiltinName == "return_empty_string",
        swiftmutIsStringType(apply.type) else {
    return false
  }
  let callee = apply.callee.description
  return callee.contains("#CustomStringConvertible.description")
}

func swiftmutStringInterpolationExpressionCandidates(
  in text: String,
  path: String,
  preferredLine: Int,
  expectedCount: Int,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> [(file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)] {
  guard preferredLine > 0 else {
    return []
  }

  var candidates: [(file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)] = []
  var currentLine = 1
  var lineStart = text.startIndex
  var index = text.startIndex
  var braceDepth = 0
  var sawOpeningBrace = false

  func inspectLine(_ lineText: String, line: Int) {
    guard line >= preferredLine,
          candidates.count <= expectedCount else {
      return
    }
    let expressions = swiftmutStringInterpolationExpressions(on: lineText, mutation: mutation)
    for expression in expressions {
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
      if currentLine >= preferredLine {
        if sawOpeningBrace && braceDepth > 0 {
          inspectLine(lineText, line: currentLine)
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
      lineStart = text.index(after: index)
    }
    index = text.index(after: index)
  }

  if index == text.endIndex && currentLine >= preferredLine && sawOpeningBrace && braceDepth > 0 {
    inspectLine(String(text[lineStart..<text.endIndex]), line: currentLine)
  }
  return candidates
}

func swiftmutStringInterpolationExpressions(
  on line: String,
  mutation: SwiftmutMutation
) -> [(column: Int, sourceOriginal: String, sourceMutated: String)] {
  let bytes = Array(line.utf8)
  let lineEnd = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  var expressions: [(column: Int, sourceOriginal: String, sourceMutated: String)] = []
  var index = 0
  while index + 1 < lineEnd {
    if bytes[index] == 92,
       bytes[index + 1] == 40,
       let close = swiftmutBalancedExpressionEnd(
        in: bytes,
        openIndex: index + 1,
        close: 41,
        lineEnd: lineEnd
       ) {
      let expressionStart = swiftmutSkipHorizontalWhitespace(bytes, from: index + 2)
      let expressionEnd = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: close - 1)
      if expressionStart < expressionEnd,
         swiftmutReturnValueIsEligible(bytes: bytes, start: expressionStart, mutation: mutation) {
        expressions.append((
          expressionStart + 1,
          String(decoding: bytes[expressionStart..<expressionEnd], as: UTF8.self),
          swiftmutImplicitReturnSourceMutation(for: mutation)
        ))
      }
      index = close
      continue
    }
    index += 1
  }
  return expressions
}
