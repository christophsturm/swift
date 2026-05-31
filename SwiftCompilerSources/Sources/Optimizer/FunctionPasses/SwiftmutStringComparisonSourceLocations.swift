//===--- SwiftmutStringComparisonSourceLocations.swift ----------------------------------------------===//
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

func swiftmutFindStringComparisonValueSourceLocation(
  for apply: ApplyInst,
  path: String,
  preferredLine: Int,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard let ordinal = swiftmutStringComparisonApplyOrdinalAndCount(
    for: apply,
    mutation: mutation,
    config: config
  ), ordinal.count <= 200,
    let text = swiftmutRead(path) else {
    return nil
  }

  let candidates = swiftmutStringComparisonExpressionCandidates(
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

func swiftmutStringComparisonApplyOrdinalAndCount(
  for apply: ApplyInst,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (ordinal: Int, count: Int)? {
  guard swiftmutIsStringComparisonApply(apply, mutation: mutation) else {
    return nil
  }

  var ordinal = 0
  var count = 0
  var foundApply = false
  for block in apply.parentFunction.blocks {
    for instruction in block.instructions {
      guard let candidate = instruction as? ApplyInst,
            swiftmutIsStringComparisonApply(candidate, mutation: mutation),
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

func swiftmutIsStringComparisonApply(_ apply: ApplyInst, mutation: SwiftmutMutation) -> Bool {
  guard mutation.mutatedBuiltinName == "return_false" || mutation.mutatedBuiltinName == "return_true",
        swiftmutIsBoolType(apply.type, in: apply.parentFunction) else {
    return false
  }
  return apply.callee.description.contains("_stringCompareWithSmolCheck")
}

func swiftmutStringComparisonExpressionCandidates(
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
    let expressions = swiftmutStringComparisonExpressions(on: lineText, mutation: mutation)
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

func swiftmutStringComparisonExpressions(
  on line: String,
  mutation: SwiftmutMutation
) -> [(column: Int, sourceOriginal: String, sourceMutated: String)] {
  let bytes = Array(line.utf8)
  let lineEnd = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  guard lineEnd > 0 else {
    return []
  }

  let operators = ["==", "!=", "<=", ">=", "<", ">"]
  var expressions: [(column: Int, sourceOriginal: String, sourceMutated: String)] = []
  var index = 0
  while index < lineEnd {
    var matchedOperator: String?
    for op in operators {
      let opBytes = Array(op.utf8)
      if index + opBytes.count <= lineEnd,
         swiftmutBytesMatch(bytes, start: index, pattern: opBytes),
         swiftmutIsSourceComparisonOperator(
          bytes: bytes,
          operatorStart: index,
          operatorEnd: index + opBytes.count
         ) {
        matchedOperator = op
        break
      }
    }

    if let op = matchedOperator {
      let expression = swiftmutSourceExpression(
        in: bytes,
        operatorStart: index,
        operatorEnd: index + op.utf8.count,
        mutatedOperator: op
      )
      expressions.append((index + 1, expression.original, swiftmutImplicitReturnSourceMutation(for: mutation)))
      index += op.utf8.count
    } else {
      index += 1
    }
  }
  return expressions
}
