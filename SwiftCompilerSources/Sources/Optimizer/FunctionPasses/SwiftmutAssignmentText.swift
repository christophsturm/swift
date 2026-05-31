// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for Swift project authors

import SIL

func swiftmutAssignmentValueExpression(
  _ line: String,
  mutation: SwiftmutMutation,
  targetNames: [String] = [],
  requiresDirectValueExpression: Bool = false
) -> (column: Int, sourceOriginal: String, sourceMutated: String)? {
  let bytes = Array(line.utf8)
  let lineStart = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
  let lineEnd = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  guard lineStart < lineEnd,
        !swiftmutLineStartsWithAssignmentReturnBlockedPrefix(bytes: bytes, start: lineStart) else {
    return nil
  }

  guard let equals = swiftmutFirstAssignmentOperator(bytes: bytes, start: lineStart, end: lineEnd) else {
    if mutation.sourceOriginal == "return",
       let compound = swiftmutCompoundAssignmentValueSource(
         bytes: bytes,
         lineStart: lineStart,
         lineEnd: lineEnd,
         targetNames: targetNames
       ),
       swiftmutReturnValueIsEligible(bytes: bytes, start: compound.valueStart, mutation: mutation) {
      return (
        compound.column,
        compound.sourceOriginal,
        compound.assignmentPrefix + swiftmutImplicitReturnSourceMutation(for: mutation))
    }
    return swiftmutLabeledArgumentValueExpression(
      bytes: bytes,
      lineStart: lineStart,
      lineEnd: lineEnd,
      mutation: mutation,
      targetNames: targetNames,
      requiresDirectValueExpression: requiresDirectValueExpression
    )
  }

  guard swiftmutAssignmentLeftHandSideMatchesTargetNames(
    bytes: bytes,
    start: lineStart,
    end: equals,
    targetNames: targetNames
  ) else {
    return nil
  }

  let valueStart = swiftmutSkipHorizontalWhitespace(bytes, from: equals + 1)
  var valueEnd = lineEnd
  if valueEnd > valueStart && bytes[valueEnd - 1] == 44 {
    valueEnd = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: valueEnd - 1)
  }
  guard valueStart < valueEnd,
        swiftmutAssignmentValueRHSIsDirectValueExpression(
          bytes: bytes,
          start: valueStart,
          end: valueEnd,
          isRequired: requiresDirectValueExpression
        ),
        swiftmutReturnValueIsEligible(bytes: bytes, start: valueStart, mutation: mutation) else {
    return nil
  }

  let sourceOriginal = String(decoding: bytes[valueStart..<valueEnd], as: UTF8.self)
  return (
    valueStart + 1,
    sourceOriginal,
    swiftmutImplicitReturnSourceMutation(for: mutation))
}

func swiftmutSignatureAssignmentValueExpression(
  _ line: String,
  mutation: SwiftmutMutation,
  targetNames: [String],
  requiresMutationEligibility: Bool = true
) -> (column: Int, sourceOriginal: String, sourceMutated: String)? {
  let bytes = Array(line.utf8)
  let lineStart = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
  var lineEnd = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  if let bodyStart = swiftmutTopLevelByteIndex(bytes, start: lineStart, end: lineEnd, byte: 123) {
    lineEnd = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bodyStart)
  }
  guard lineStart < lineEnd,
        !swiftmutASCIIHasPrefix(bytes, start: lineStart, prefix: "//"),
        let equals = swiftmutFirstAssignmentOperator(bytes: bytes, start: lineStart, end: lineEnd),
        swiftmutAssignmentLeftHandSideMatchesTargetNames(
          bytes: bytes,
          start: lineStart,
          end: equals,
          targetNames: targetNames
        ) else {
    return nil
  }

  let valueStart = swiftmutSkipHorizontalWhitespace(bytes, from: equals + 1)
  var valueEnd = swiftmutTopLevelByteIndex(bytes, start: valueStart, end: lineEnd, byte: 44) ?? lineEnd
  valueEnd = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: valueEnd)
  guard valueStart < valueEnd,
        swiftmutSourceExpressionIsSingleLineComplete(bytes: bytes, start: valueStart, end: valueEnd),
        (!requiresMutationEligibility
         || swiftmutReturnValueIsEligible(bytes: bytes, start: valueStart, mutation: mutation)) else {
    return nil
  }

  let sourceOriginal = String(decoding: bytes[valueStart..<valueEnd], as: UTF8.self)
  return (
    valueStart + 1,
    sourceOriginal,
    swiftmutImplicitReturnSourceMutation(for: mutation))
}

private func swiftmutLabeledArgumentValueExpression(
  bytes: [UInt8],
  lineStart: Int,
  lineEnd: Int,
  mutation: SwiftmutMutation,
  targetNames: [String],
  requiresDirectValueExpression: Bool
) -> (column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard !targetNames.isEmpty,
        let colon = swiftmutFirstLabeledArgumentSeparator(bytes: bytes, start: lineStart, end: lineEnd),
        swiftmutAssignmentLeftHandSideMatchesTargetNames(
          bytes: bytes,
          start: lineStart,
          end: colon,
          targetNames: targetNames
        ) else {
    return nil
  }

  let valueStart = swiftmutSkipHorizontalWhitespace(bytes, from: colon + 1)
  var valueEnd = lineEnd
  if valueEnd > valueStart && bytes[valueEnd - 1] == 44 {
    valueEnd = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: valueEnd - 1)
  }
  guard valueStart < valueEnd,
        swiftmutLabeledArgumentRHSLooksLikeValueExpression(bytes: bytes, start: valueStart, end: valueEnd),
        swiftmutAssignmentValueRHSIsDirectValueExpression(
          bytes: bytes,
          start: valueStart,
          end: valueEnd,
          isRequired: requiresDirectValueExpression
        ),
        swiftmutReturnValueIsEligible(bytes: bytes, start: valueStart, mutation: mutation) else {
    return nil
  }

  let sourceOriginal = String(decoding: bytes[valueStart..<valueEnd], as: UTF8.self)
  return (
    valueStart + 1,
    sourceOriginal,
    swiftmutImplicitReturnSourceMutation(for: mutation))
}

func swiftmutLocalBindingValueExpression(
  _ line: String,
  mutation: SwiftmutMutation,
  targetNames: [String]
) -> (column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard !targetNames.isEmpty else {
    return nil
  }
  let bytes = Array(line.utf8)
  let lineStart = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
  let lineEnd = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  guard lineStart < lineEnd,
        !swiftmutASCIIHasPrefix(bytes, start: lineStart, prefix: "//") else {
    return nil
  }

  var matches: [(column: Int, sourceOriginal: String)] = []
  var index = lineStart
  while index < lineEnd {
    if swiftmutLocalBindingTokenMatches(bytes: bytes, index: index, end: lineEnd, token: "let")
        || swiftmutLocalBindingTokenMatches(bytes: bytes, index: index, end: lineEnd, token: "var") {
      let nameStart = swiftmutSkipHorizontalWhitespace(bytes, from: index + 3)
      if nameStart < lineEnd && swiftmutIsIdentifierStartByte(bytes[nameStart]) {
        var nameEnd = nameStart + 1
        while nameEnd < lineEnd && swiftmutIsIdentifierByte(bytes[nameEnd]) {
          nameEnd += 1
        }
        let name = String(decoding: bytes[nameStart..<nameEnd], as: UTF8.self)
        if targetNames.contains(name),
           let equals = swiftmutFirstAssignmentOperator(bytes: bytes, start: nameEnd, end: lineEnd) {
          let valueStart = swiftmutSkipHorizontalWhitespace(bytes, from: equals + 1)
          var valueEnd = lineEnd
          if valueEnd > valueStart && bytes[valueEnd - 1] == 44 {
            valueEnd = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: valueEnd - 1)
          }
          guard valueStart < valueEnd,
                swiftmutReturnValueIsEligible(bytes: bytes, start: valueStart, mutation: mutation) else {
            index = nameEnd
            continue
          }
          matches.append((
            valueStart + 1,
            String(decoding: bytes[valueStart..<valueEnd], as: UTF8.self)))
          if matches.count >= 2 {
            return nil
          }
        }
        index = nameEnd
        continue
      }
    }
    index += 1
  }

  guard matches.count == 1,
        let match = matches.first else {
    return nil
  }
  return (
    match.column,
    match.sourceOriginal,
    swiftmutImplicitReturnSourceMutation(for: mutation))
}

private func swiftmutLocalBindingTokenMatches(
  bytes: [UInt8],
  index: Int,
  end: Int,
  token: String
) -> Bool {
  let tokenBytes = Array(token.utf8)
  guard index >= 0,
        index + tokenBytes.count < end else {
    return false
  }
  if index > 0 && swiftmutIsIdentifierByte(bytes[index - 1]) {
    return false
  }
  for offset in 0..<tokenBytes.count where bytes[index + offset] != tokenBytes[offset] {
    return false
  }
  let after = index + tokenBytes.count
  return after < end && swiftmutIsHorizontalWhitespace(bytes[after])
}

func swiftmutFirstLabeledArgumentSeparator(bytes: [UInt8], start: Int, end: Int) -> Int? {
  guard start < end else {
    return nil
  }
  for index in start..<end where bytes[index] == 58 {
    let before = index > start ? bytes[index - 1] : 0
    let after = index + 1 < end ? bytes[index + 1] : 0
    if before == 58 || after == 58 {
      continue
    }
    return index
  }
  return nil
}

func swiftmutLabeledArgumentRHSLooksLikeValueExpression(
  bytes: [UInt8],
  start: Int,
  end: Int
) -> Bool {
  guard start < end else {
    return false
  }
  if bytes[start] >= 65 && bytes[start] <= 90 && !swiftmutASCIIContains(bytes, start: start, end: end, pattern: ".") {
    return false
  }
  if swiftmutASCIIHasPrefix(bytes, start: start, prefix: "some ")
      || swiftmutASCIIHasPrefix(bytes, start: start, prefix: "any ") {
    return false
  }
  return true
}

func swiftmutLabeledArgumentRHSLooksLikeCallExpression(
  bytes: [UInt8],
  start: Int,
  end: Int
) -> Bool {
  guard start < end,
        swiftmutASCIIContains(bytes, start: start, end: end, pattern: "(") else {
    return false
  }
  for index in start..<end {
    switch bytes[index] {
    case 123, 125, 59:
      return false
    default:
      continue
    }
  }
  return true
}

private func swiftmutAssignmentValueRHSIsDirectValueExpression(
  bytes: [UInt8],
  start: Int,
  end: Int,
  isRequired: Bool
) -> Bool {
  guard isRequired else {
    return true
  }
  for index in start..<end {
    switch bytes[index] {
    case 40, 63, 91, 123:
      return false
    default:
      continue
    }
  }
  return true
}

func swiftmutAssignmentDestinationNames(for store: StoreInst) -> [String] {
  var names: [String] = []
  swiftmutCollectAssignmentDestinationNames(
    from: store.destination,
    in: store.parentFunction,
    names: &names,
    depth: 0
  )
  return swiftmutUniqueAssignmentNames(names)
}

func swiftmutAssignmentSourceNames(for store: StoreInst) -> [String] {
  var names: [String] = []
  swiftmutCollectAssignmentSourceNames(
    from: store.source,
    names: &names,
    depth: 0
  )
  return swiftmutUniqueAssignmentNames(names)
}

func swiftmutUniqueAssignmentNames(_ names: [String]) -> [String] {
  var seen = Set<String>()
  var uniqueNames: [String] = []
  for name in names where swiftmutIdentifierIsUsable(name) && !seen.contains(name) {
    seen.insert(name)
    uniqueNames.append(name)
  }
  return uniqueNames
}

private func swiftmutCollectAssignmentSourceNames(
  from value: Value,
  names: inout [String],
  depth: Int
) {
  guard depth < 6 else {
    return
  }

  if let argumentName = (value as? Argument)?.findVarDecl()?.userFacingName.string {
    names.append(argumentName)
  }

  guard let instruction = value.definingInstruction else {
    return
  }

  if let declaration = instruction.findVarDecl() {
    names.append(declaration.userFacingName.string)
  }

  switch instruction {
  case let copyValue as CopyValueInst:
    swiftmutCollectAssignmentSourceNames(
      from: copyValue.fromValue,
      names: &names,
      depth: depth + 1
    )
  case let explicitCopyValue as ExplicitCopyValueInst:
    swiftmutCollectAssignmentSourceNames(
      from: explicitCopyValue.fromValue,
      names: &names,
      depth: depth + 1
    )
  case let moveValue as MoveValueInst:
    swiftmutCollectAssignmentSourceNames(
      from: moveValue.fromValue,
      names: &names,
      depth: depth + 1
    )
  default:
    break
  }
}

private func swiftmutCollectAssignmentDestinationNames(
  from value: Value,
  in function: Function,
  names: inout [String],
  depth: Int
) {
  guard depth < 8,
        let instruction = value.definingInstruction else {
    if let argumentName = (value as? Argument)?.findVarDecl()?.userFacingName.string {
      names.append(argumentName)
    }
    return
  }

  if let declaration = instruction.findVarDecl() {
    names.append(declaration.userFacingName.string)
  }

  switch instruction {
  case let beginAccess as BeginAccessInst:
    swiftmutCollectAssignmentDestinationNames(
      from: beginAccess.address,
      in: function,
      names: &names,
      depth: depth + 1
    )
  case let markUninitialized as MarkUninitializedInst:
    swiftmutCollectAssignmentDestinationNames(
      from: markUninitialized.operand.value,
      in: function,
      names: &names,
      depth: depth + 1
    )
  case let structElementAddr as StructElementAddrInst:
    let structType = structElementAddr.struct.type.objectType
    if let fields = structType.getNominalFields(in: function) {
      names.append(fields.getNameOfField(withIndex: structElementAddr.fieldIndex).string)
    }
    swiftmutCollectAssignmentDestinationNames(
      from: structElementAddr.struct,
      in: function,
      names: &names,
      depth: depth + 1
    )
  case let refElementAddr as RefElementAddrInst:
    if let declaration = refElementAddr.varDecl {
      names.append(declaration.userFacingName.string)
    }
    swiftmutCollectAssignmentDestinationNames(
      from: refElementAddr.instance,
      in: function,
      names: &names,
      depth: depth + 1
    )
  case let projectBox as ProjectBoxInst:
    swiftmutCollectAssignmentDestinationNames(
      from: projectBox.box,
      in: function,
      names: &names,
      depth: depth + 1
    )
  default:
    break
  }
}

private func swiftmutIdentifierIsUsable(_ name: String) -> Bool {
  guard !name.isEmpty,
        name != "_",
        name != "self" else {
    return false
  }
  for byte in name.utf8 {
    guard swiftmutIsIdentifierByte(byte) else {
      return false
    }
  }
  return true
}

private func swiftmutAssignmentLeftHandSideMatchesTargetNames(
  bytes: [UInt8],
  start: Int,
  end: Int,
  targetNames: [String]
) -> Bool {
  guard !targetNames.isEmpty else {
    return true
  }
  for targetName in targetNames {
    guard swiftmutIdentifierIsUsable(targetName) else {
      continue
    }
    if swiftmutLeftHandSideContainsIdentifier(
      bytes: bytes,
      start: start,
      end: end,
      identifier: Array(targetName.utf8)
    ) {
      return true
    }
  }
  return false
}

private func swiftmutLeftHandSideContainsIdentifier(
  bytes: [UInt8],
  start: Int,
  end: Int,
  identifier: [UInt8]
) -> Bool {
  guard !identifier.isEmpty,
        start < end else {
    return false
  }

  var index = start
  while index < end {
    if swiftmutIsIdentifierStartByte(bytes[index]) {
      let identifierStart = index
      index += 1
      while index < end && swiftmutIsIdentifierByte(bytes[index]) {
        index += 1
      }
      if bytes[identifierStart..<index].elementsEqual(identifier) {
        return true
      }
      continue
    }
    index += 1
  }
  return false
}

func swiftmutIsIdentifierStartByte(_ byte: UInt8) -> Bool {
  byte == 95 || (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122)
}

func swiftmutIsIdentifierByte(_ byte: UInt8) -> Bool {
  swiftmutIsIdentifierStartByte(byte) || (byte >= 48 && byte <= 57)
}

func swiftmutAssignmentReturnExpression(
  _ line: String,
  mutation: SwiftmutMutation
) -> (column: Int, sourceOriginal: String, sourceMutated: String)? {
  let bytes = Array(line.utf8)
  let lineStart = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
  let lineEnd = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  guard lineStart < lineEnd,
        !swiftmutLineStartsWithAssignmentReturnBlockedPrefix(bytes: bytes, start: lineStart) else {
    return nil
  }

  guard let equals = swiftmutFirstAssignmentOperator(bytes: bytes, start: lineStart, end: lineEnd) else {
    guard let compound = swiftmutCompoundAssignmentValueSource(
      bytes: bytes,
      lineStart: lineStart,
      lineEnd: lineEnd,
      targetNames: []
    ), swiftmutReturnValueIsEligible(bytes: bytes, start: compound.valueStart, mutation: mutation) else {
      return nil
    }
    return (
      compound.column,
      compound.sourceOriginal,
      compound.assignmentPrefix + swiftmutImplicitReturnSourceMutation(for: mutation))
  }

  let valueStart = swiftmutSkipHorizontalWhitespace(bytes, from: equals + 1)
  var valueEnd = lineEnd
  if valueEnd > valueStart && bytes[valueEnd - 1] == 44 {
    valueEnd = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: valueEnd - 1)
  }
  guard valueStart < valueEnd,
        swiftmutReturnValueIsEligible(bytes: bytes, start: valueStart, mutation: mutation) else {
    return nil
  }

  let sourceOriginal = String(decoding: bytes[valueStart..<valueEnd], as: UTF8.self)
  return (
    valueStart + 1,
    sourceOriginal,
    swiftmutImplicitReturnSourceMutation(for: mutation))
}

func swiftmutLineStartsWithAssignmentReturnBlockedPrefix(bytes: [UInt8], start: Int) -> Bool {
  [
    "if ", "if(", "guard ", "guard(", "while ", "while(", "for ", "for(",
    "switch ", "switch(", "return ", "throw ", "import ", "//", "/*"
  ].contains { swiftmutASCIIHasPrefix(bytes, start: start, prefix: $0) }
}

func swiftmutFirstAssignmentOperator(bytes: [UInt8], start: Int, end: Int) -> Int? {
  guard start < end else {
    return nil
  }
  for index in start..<end where bytes[index] == 61 {
    let before = index > start ? bytes[index - 1] : 0
    let after = index + 1 < end ? bytes[index + 1] : 0
    if swiftmutIsAssignmentOperatorNeighbor(before) || swiftmutIsAssignmentOperatorNeighbor(after) {
      continue
    }
    return index
  }
  return nil
}

private func swiftmutIsAssignmentOperatorNeighbor(_ byte: UInt8) -> Bool {
  switch byte {
  case 33, 37, 38, 42, 43, 45, 47, 60, 61, 62, 63, 94, 124, 126:
    return true
  default:
    return false
  }
}

struct SwiftmutCompoundAssignmentSource {
  var column: Int
  var valueStart: Int
  var sourceOriginal: String
  var assignmentPrefix: String
}

func swiftmutCompoundAssignmentValueSource(
  bytes: [UInt8],
  lineStart: Int,
  lineEnd: Int,
  targetNames: [String]
) -> SwiftmutCompoundAssignmentSource? {
  guard let assignmentOperator = swiftmutFirstCompoundAssignmentOperator(
    bytes: bytes,
    start: lineStart,
    end: lineEnd
  ) else {
    return nil
  }

  let lhsEnd = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: assignmentOperator.start)
  guard lineStart < lhsEnd,
        swiftmutCompoundAssignmentLeftHandSideMatchesTargetNames(
          bytes: bytes,
          start: lineStart,
          end: lhsEnd,
          targetNames: targetNames
        ) else {
    return nil
  }

  let valueStart = swiftmutSkipHorizontalWhitespace(bytes, from: assignmentOperator.end)
  var valueEnd = lineEnd
  if valueEnd > valueStart && bytes[valueEnd - 1] == 44 {
    valueEnd = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: valueEnd - 1)
  }
  guard valueStart < valueEnd,
        swiftmutSourceExpressionIsSingleLineComplete(bytes: bytes, start: valueStart, end: valueEnd) else {
    return nil
  }

  let sourceOriginal = String(decoding: bytes[lineStart..<valueEnd], as: UTF8.self)
  let lhs = String(decoding: bytes[lineStart..<lhsEnd], as: UTF8.self)
  return SwiftmutCompoundAssignmentSource(
    column: lineStart + 1,
    valueStart: valueStart,
    sourceOriginal: sourceOriginal,
    assignmentPrefix: lhs + " = "
  )
}

private func swiftmutFirstCompoundAssignmentOperator(
  bytes: [UInt8],
  start: Int,
  end: Int
) -> (start: Int, end: Int)? {
  guard start < end else {
    return nil
  }
  return swiftmutFirstTopLevelIndex(bytes, start: start, end: end) { index in
    guard index + 1 < end,
          bytes[index + 1] == 61 else {
      return false
    }
    switch bytes[index] {
    case 37, 38, 42, 43, 45, 47, 94, 124:
      return true
    default:
      return false
    }
  }.map { ($0, $0 + 2) }
}

private func swiftmutCompoundAssignmentLeftHandSideMatchesTargetNames(
  bytes: [UInt8],
  start: Int,
  end: Int,
  targetNames: [String]
) -> Bool {
  guard !targetNames.isEmpty else {
    return true
  }
  for targetName in targetNames {
    guard swiftmutCompoundAssignmentIdentifierIsUsable(targetName),
          swiftmutCompoundAssignmentLeftHandSideContainsIdentifier(
            bytes: bytes,
            start: start,
            end: end,
            identifier: Array(targetName.utf8)
          ) else {
      continue
    }
    return true
  }
  return false
}

private func swiftmutCompoundAssignmentIdentifierIsUsable(_ name: String) -> Bool {
  guard let first = name.utf8.first,
        swiftmutIsASCIIIdentifierStart(first) else {
    return false
  }
  for byte in name.utf8 {
    guard swiftmutIsASCIILetterNumberOrUnderscore(byte) else {
      return false
    }
  }
  return true
}

private func swiftmutCompoundAssignmentLeftHandSideContainsIdentifier(
  bytes: [UInt8],
  start: Int,
  end: Int,
  identifier: [UInt8]
) -> Bool {
  guard !identifier.isEmpty,
        start < end else {
    return false
  }

  var index = start
  while index < end {
    if swiftmutIsASCIIIdentifierStart(bytes[index]) {
      let identifierStart = index
      index += 1
      while index < end && swiftmutIsASCIILetterNumberOrUnderscore(bytes[index]) {
        index += 1
      }
      if bytes[identifierStart..<index].elementsEqual(identifier) {
        return true
      }
      continue
    }
    index += 1
  }
  return false
}
