//===--- SwiftmutReturnSourceLocations.swift ----------------------------------------------===//
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

func swiftmutReturnSourceLocation(
  for returnInst: ReturnInst,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  if let fileNameAndPosition = returnInst.location.fileNameAndPosition {
    let path = fileNameAndPosition.path.string
    if let matchedPath = swiftmutIncludedSourcePath(path, config: config) {
      let candidate = (
        swiftmutTrimPackageRoot(matchedPath, config: config),
        fileNameAndPosition.line,
        fileNameAndPosition.column,
        mutation.sourceOriginal,
        mutation.sourceMutated)
      if swiftmutReturnSourceLocationIsUsable(candidate, mutation: mutation, config: config) {
        return candidate
      }
      if let anchored = swiftmutFindAssignmentReturnSourceLocation(
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        mutation: mutation,
        config: config
      ) {
        return anchored
      }
      if let anchored = swiftmutFindDescribedExplicitReturnSourceLocation(
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        locationDescription: returnInst.location.description,
        mutation: mutation,
        config: config
      ) {
        return anchored
      }
      if let anchored = swiftmutFindUniqueExplicitReturnSourceLocation(
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        mutation: mutation,
        config: config
      ) {
        return anchored
      }
      if let anchored = swiftmutFindNearestPriorExplicitReturnSourceLocation(
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        mutation: mutation,
        config: config
      ) {
        return anchored
      }
      if let anchored = swiftmutFindNearestPriorImplicitReturnSourceLocation(
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        mutation: mutation,
        config: config
      ) {
        return anchored
      }
      if let anchored = swiftmutFindUniqueImplicitReturnSourceLocation(
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        mutation: mutation,
        config: config
      ) {
        return anchored
      }
      if let anchored = swiftmutFindPropertyGetterReturnSourceLocation(
        functionName: returnInst.parentFunction.name.string,
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        mutation: mutation,
        config: config
      ) {
        return anchored
      }
    }
  }

  if let definingInstruction = returnInst.returnedValue.definingInstruction,
     let fileNameAndPosition = definingInstruction.location.fileNameAndPosition {
    let path = fileNameAndPosition.path.string
    if let matchedPath = swiftmutIncludedSourcePath(path, config: config) {
      let candidate = (
        swiftmutTrimPackageRoot(matchedPath, config: config),
        fileNameAndPosition.line,
        fileNameAndPosition.column,
        mutation.sourceOriginal,
        mutation.sourceMutated)
      if swiftmutReturnSourceLocationIsUsable(candidate, mutation: mutation, config: config) {
        return candidate
      }
      if let anchored = swiftmutFindAssignmentReturnSourceLocation(
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        mutation: mutation,
        config: config
      ) {
        return anchored
      }
      if let anchored = swiftmutFindDescribedExplicitReturnSourceLocation(
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        locationDescription: returnInst.location.description,
        mutation: mutation,
        config: config
      ) {
        return anchored
      }
      if let anchored = swiftmutFindUniqueExplicitReturnSourceLocation(
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        mutation: mutation,
        config: config
      ) {
        return anchored
      }
      if let anchored = swiftmutFindNearestPriorExplicitReturnSourceLocation(
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        mutation: mutation,
        config: config
      ) {
        return anchored
      }
      if let anchored = swiftmutFindNearestPriorImplicitReturnSourceLocation(
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        mutation: mutation,
        config: config
      ) {
        return anchored
      }
      if let anchored = swiftmutFindUniqueImplicitReturnSourceLocation(
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        mutation: mutation,
        config: config
      ) {
        return anchored
      }
      if let anchored = swiftmutFindPropertyGetterReturnSourceLocation(
        functionName: returnInst.parentFunction.name.string,
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        mutation: mutation,
        config: config
      ) {
        return anchored
      }
    }
  }

  if let anchored = swiftmutFindDescribedDefaultArgumentReturnSourceLocation(
    functionName: returnInst.parentFunction.name.string,
    locationDescription: returnInst.location.description,
    mutation: mutation,
    config: config
  ) {
    return anchored
  }
  if let definingInstruction = returnInst.returnedValue.definingInstruction,
     let anchored = swiftmutFindDescribedDefaultArgumentReturnSourceLocation(
       functionName: returnInst.parentFunction.name.string,
       locationDescription: definingInstruction.location.description,
       mutation: mutation,
       config: config
     ) {
    return anchored
  }

  let returnLocation = returnInst.location.description
  for path in swiftmutSwiftSourcePaths(config: config) {
    guard returnLocation.contains(path),
          let line = swiftmutPreferredLine(in: returnLocation, path: path) else {
      continue
    }
    let candidate = (
      swiftmutTrimPackageRoot(path, config: config),
      line,
      1,
      mutation.sourceOriginal,
      mutation.sourceMutated)
    if swiftmutReturnSourceLocationIsUsable(candidate, mutation: mutation, config: config) {
      return candidate
    }
    if let anchored = swiftmutFindAssignmentReturnSourceLocation(
      path: path,
      preferredLine: line,
      mutation: mutation,
      config: config
    ) {
      return anchored
    }
    if let anchored = swiftmutFindDescribedExplicitReturnSourceLocation(
      path: path,
      preferredLine: line,
      locationDescription: returnLocation,
      mutation: mutation,
      config: config
    ) {
      return anchored
    }
    if let anchored = swiftmutFindUniqueExplicitReturnSourceLocation(
      path: path,
      preferredLine: line,
      mutation: mutation,
      config: config
    ) {
      return anchored
    }
    if let anchored = swiftmutFindNearestPriorExplicitReturnSourceLocation(
      path: path,
      preferredLine: line,
      mutation: mutation,
      config: config
    ) {
      return anchored
    }
    if let anchored = swiftmutFindNearestPriorImplicitReturnSourceLocation(
      path: path,
      preferredLine: line,
      mutation: mutation,
      config: config
    ) {
      return anchored
    }
    if let anchored = swiftmutFindUniqueImplicitReturnSourceLocation(
      path: path,
      preferredLine: line,
      mutation: mutation,
      config: config
    ) {
      return anchored
    }
    if let anchored = swiftmutFindPropertyGetterReturnSourceLocation(
      functionName: returnInst.parentFunction.name.string,
      path: path,
      preferredLine: line,
      mutation: mutation,
      config: config
    ) {
      return anchored
    }
  }

  let location = returnInst.parentFunction.location.description
  for path in swiftmutSwiftSourcePaths(config: config) {
    guard location.contains(path),
          let line = swiftmutPreferredLine(in: location, path: path) else {
      continue
    }
    let candidate = (
      swiftmutTrimPackageRoot(path, config: config),
      line,
      1,
      mutation.sourceOriginal,
      mutation.sourceMutated)
    if swiftmutReturnSourceLocationIsUsable(candidate, mutation: mutation, config: config) {
      return candidate
    }
    if let anchored = swiftmutFindAssignmentReturnSourceLocation(
      path: path,
      preferredLine: line,
      mutation: mutation,
      config: config
    ) {
      return anchored
    }
    if let anchored = swiftmutFindDescribedExplicitReturnSourceLocation(
      path: path,
      preferredLine: line,
      locationDescription: returnInst.location.description,
      mutation: mutation,
      config: config
    ) {
      return anchored
    }
    if let anchored = swiftmutFindUniqueExplicitReturnSourceLocation(
      path: path,
      preferredLine: line,
      mutation: mutation,
      config: config
    ) {
      return anchored
    }
    if let anchored = swiftmutFindUniqueImplicitReturnSourceLocation(
      path: path,
      preferredLine: line,
      mutation: mutation,
      config: config
    ) {
      return anchored
    }
    if let anchored = swiftmutFindPropertyGetterReturnSourceLocation(
      functionName: returnInst.parentFunction.name.string,
      path: path,
      preferredLine: line,
      mutation: mutation,
      config: config
    ) {
      return anchored
    }
  }
  return nil
}

func swiftmutFindPropertyGetterReturnSourceLocation(
  functionName: String,
  path: String,
  preferredLine: Int,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard preferredLine > 0,
        mutation.sourceOriginal == "return",
        let text = swiftmutRead(path) else {
    return nil
  }

  if let exact = swiftmutPropertyGetterReturnSourceLocation(
    in: text,
    functionName: functionName,
    path: path,
    lineRange: preferredLine...preferredLine,
    mutation: mutation,
    config: config
  ) {
    return exact
  }

  let firstLine = preferredLine > 1 ? preferredLine - 1 : 1
  return swiftmutPropertyGetterReturnSourceLocation(
    in: text,
    functionName: functionName,
    path: path,
    lineRange: firstLine...(preferredLine + 2),
    mutation: mutation,
    config: config
  )
}

func swiftmutPropertyGetterReturnSourceLocation(
  in text: String,
  functionName: String,
  path: String,
  lineRange: ClosedRange<Int>,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  var matches: [(line: Int, column: Int, sourceOriginal: String, sourceMutated: String)] = []
  var currentLine = 1
  var lineStart = text.startIndex
  var index = text.startIndex

  func inspectLine(_ lineText: String, line: Int) {
    guard lineRange.contains(line),
          matches.count < 2,
          let property = swiftmutStoredPropertyDeclaration(lineText, mutation: mutation) else {
      return
    }
    guard swiftmutFunctionName(functionName, containsPropertyName: property.name) else {
      return
    }
    matches.append((line, property.column, property.sourceOriginal, property.sourceMutated))
  }

  while index < text.endIndex {
    if text[index] == "\n" {
      inspectLine(String(text[lineStart..<index]), line: currentLine)
      if currentLine >= lineRange.upperBound || matches.count >= 2 {
        break
      }
      currentLine += 1
      lineStart = text.index(after: index)
    }
    index = text.index(after: index)
  }

  if index == text.endIndex && currentLine <= lineRange.upperBound {
    inspectLine(String(text[lineStart..<text.endIndex]), line: currentLine)
  }

  guard matches.count == 1,
        let match = matches.first else {
    return nil
  }
  return (
    swiftmutTrimPackageRoot(path, config: config),
    match.line,
    match.column,
    match.sourceOriginal,
    match.sourceMutated)
}

func swiftmutStoredPropertyDeclaration(
  _ line: String,
  mutation: SwiftmutMutation
) -> (name: String, column: Int, sourceOriginal: String, sourceMutated: String)? {
  let bytes = Array(line.utf8)
  let lineStart = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
  let lineEnd = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  guard lineStart < lineEnd,
        !swiftmutASCIIHasPrefix(bytes, start: lineStart, prefix: "case "),
        !swiftmutASCIIHasPrefix(bytes, start: lineStart, prefix: "func "),
        !swiftmutASCIIHasPrefix(bytes, start: lineStart, prefix: "init"),
        !swiftmutASCIIHasPrefix(bytes, start: lineStart, prefix: "return "),
        !swiftmutASCIIHasPrefix(bytes, start: lineStart, prefix: "//") else {
    return nil
  }

  guard let keyword = swiftmutPropertyDeclarationKeyword(bytes: bytes, start: lineStart, end: lineEnd) else {
    return nil
  }
  let nameStart = swiftmutSkipHorizontalWhitespace(bytes, from: keyword.end)
  if nameStart < lineEnd && bytes[nameStart] == 40 {
    return nil
  }
  guard nameStart < lineEnd,
        swiftmutIsASCIIIdentifierStart(bytes[nameStart]) else {
    return nil
  }
  var nameEnd = nameStart + 1
  while nameEnd < lineEnd && swiftmutIsASCIILetterNumberOrUnderscore(bytes[nameEnd]) {
    nameEnd += 1
  }
  var afterName = swiftmutSkipHorizontalWhitespace(bytes, from: nameEnd)
  guard afterName < lineEnd,
        bytes[afterName] == 58 else {
    return nil
  }
  afterName = swiftmutSkipHorizontalWhitespace(bytes, from: afterName + 1)
  guard afterName < lineEnd else {
    return nil
  }
  for index in afterName..<lineEnd {
    if bytes[index] == 123 {
      return nil
    }
  }

  let name = String(decoding: bytes[nameStart..<nameEnd], as: UTF8.self)
  return (
    name,
    nameStart + 1,
    name,
    swiftmutImplicitReturnSourceMutation(for: mutation))
}

func swiftmutFunctionName(_ functionName: String, containsPropertyName propertyName: String) -> Bool {
  guard !propertyName.isEmpty else {
    return false
  }
  return swiftmutMangledNameContainsIdentifier(functionName, identifier: propertyName)
}

func swiftmutPropertyDeclarationKeyword(bytes: [UInt8], start: Int, end: Int) -> (start: Int, end: Int)? {
  var index = start
  while index < end {
    let tokenStart = swiftmutSkipHorizontalWhitespace(bytes, from: index)
    guard tokenStart < end else {
      return nil
    }
    var tokenEnd = tokenStart
    while tokenEnd < end && swiftmutIsASCIILetterNumberOrUnderscore(bytes[tokenEnd]) {
      tokenEnd += 1
    }
    guard tokenEnd > tokenStart else {
      return nil
    }
    let token = String(decoding: bytes[tokenStart..<tokenEnd], as: UTF8.self)
    if token == "let" || token == "var" {
      return (tokenStart, tokenEnd)
    }
    if !swiftmutIsPropertyDeclarationModifier(token) {
      return nil
    }
    index = swiftmutSkipPropertyDeclarationModifierSuffix(bytes: bytes, from: tokenEnd, end: end)
  }
  return nil
}

func swiftmutSkipPropertyDeclarationModifierSuffix(bytes: [UInt8], from index: Int, end: Int) -> Int {
  guard index + 5 <= end,
        bytes[index] == 40,
        swiftmutASCIIHasExactPrefix(bytes, start: index, prefix: "(set)") else {
    return index
  }
  return index + 5
}

func swiftmutIsPropertyDeclarationModifier(_ token: String) -> Bool {
  switch token {
  case "public", "private", "internal", "fileprivate", "open", "package",
       "static", "class", "final", "lazy", "weak", "unowned", "nonisolated",
       "isolated", "mutating", "nonmutating":
    return true
  default:
    return false
  }
}

func swiftmutScalarValueSourceLocation(
  for value: StructInst,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  let functionSourceLocation = swiftmutFunctionSourceLocation(
    for: value.parentFunction,
    config: config
  )
  if let fileNameAndPosition = value.location.fileNameAndPosition {
    let path = fileNameAndPosition.path.string
    if let matchedPath = swiftmutIncludedSourcePath(path, config: config) {
      if let assignment = swiftmutFindAssignmentValueSourceLocation(
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        mutation: mutation,
        config: config,
        requiresDirectValueExpression: true
      ) {
        return assignment
      }
      if let returned = swiftmutFindReturnedScalarValueSourceLocation(
        for: value,
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        mutation: mutation,
        config: config
      ) {
        return returned
      }
      if let functionSourceLocation,
         functionSourceLocation.path == matchedPath,
         let anchored = swiftmutFindOrdinalScalarValueSourceLocation(
           for: value,
           path: matchedPath,
           preferredLine: functionSourceLocation.line,
           mutation: mutation,
           config: config
         ) {
        return anchored
      }
    }
  }

  if let functionSourceLocation {
    if let anchored = swiftmutFindAssignmentValueSourceLocation(
      path: functionSourceLocation.path,
      preferredLine: functionSourceLocation.line,
      mutation: mutation,
      config: config,
      requiresDirectValueExpression: true
    ) {
      return anchored
    }
    if let anchored = swiftmutFindReturnedScalarValueSourceLocation(
      for: value,
      path: functionSourceLocation.path,
      preferredLine: functionSourceLocation.line,
      mutation: mutation,
      config: config
    ) {
      return anchored
    }
    if let anchored = swiftmutFindOrdinalScalarValueSourceLocation(
      for: value,
      path: functionSourceLocation.path,
      preferredLine: functionSourceLocation.line,
      mutation: mutation,
      config: config
    ) {
      return anchored
    }
  }
  return nil
}

func swiftmutFindOrdinalScalarValueSourceLocation(
  for value: StructInst,
  path: String,
  preferredLine: Int,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard let ordinal = swiftmutScalarValueOrdinalAndCount(
    for: value,
    mutation: mutation,
    config: config
  ), ordinal.count <= 200 else {
    return nil
  }
  return swiftmutFindOrdinalValueExpressionSourceLocation(
    path: path,
    preferredLine: preferredLine,
    ordinal: ordinal.ordinal,
    expectedCount: ordinal.count,
    mutation: mutation,
    config: config
  )
}

func swiftmutScalarValueOrdinalAndCount(
  for value: StructInst,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (ordinal: Int, count: Int)? {
  var ordinal = 0
  var count = 0
  var foundValue = false

  for block in value.parentFunction.blocks {
    for instruction in block.instructions {
      guard let candidate = instruction as? StructInst else {
        continue
      }
      let mutations = swiftmutScalarValueMutations(for: candidate, config: config)
      guard mutations.contains(where: { $0.mutatedBuiltinName == mutation.mutatedBuiltinName }) else {
        continue
      }
      count += 1
      if candidate === value {
        ordinal = count
        foundValue = true
      }
    }
  }

  guard foundValue else {
    return nil
  }
  return (ordinal, count)
}

func swiftmutFindReturnedScalarValueSourceLocation(
  for value: StructInst,
  path: String,
  preferredLine: Int,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard swiftmutScalarValueIsDirectReturnBranchValue(value),
        let ordinal = swiftmutReturnedScalarValueOrdinalAndCount(
          for: value,
          mutation: mutation,
          config: config
        ), ordinal.count <= 20 else {
    return nil
  }
  return swiftmutFindOrdinalExplicitReturnSourceLocation(
    path: path,
    preferredLine: preferredLine,
    ordinal: ordinal.ordinal,
    expectedCount: ordinal.count,
    mutation: mutation,
    config: config
  )
}

func swiftmutScalarValueIsDirectReturnBranchValue(_ value: StructInst) -> Bool {
  for use in value.uses.ignoreDebugUses {
    guard let branch = use.instruction as? BranchInst,
          branch.targetBlock.terminator is ReturnInst else {
      continue
    }
    return true
  }
  return false
}

func swiftmutReturnedScalarValueOrdinalAndCount(
  for value: StructInst,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (ordinal: Int, count: Int)? {
  var ordinal = 0
  var count = 0
  var foundValue = false

  for block in value.parentFunction.blocks {
    for instruction in block.instructions {
      guard let candidate = instruction as? StructInst,
            swiftmutScalarValueIsDirectReturnBranchValue(candidate) else {
        continue
      }
      let mutations = swiftmutScalarValueMutations(for: candidate, config: config)
      guard mutations.contains(where: { $0.mutatedBuiltinName == mutation.mutatedBuiltinName }) else {
        continue
      }
      count += 1
      if candidate === value {
        ordinal = count
        foundValue = true
      }
    }
  }

  guard foundValue else {
    return nil
  }
  return (ordinal, count)
}

func swiftmutReturnBranchSourceLocation(
  for branch: BranchInst,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  let functionSourceLocation = swiftmutFunctionSourceLocation(
    for: branch.parentFunction,
    config: config
  )
  if let fileNameAndPosition = branch.location.fileNameAndPosition {
    let path = fileNameAndPosition.path.string
    if let matchedPath = swiftmutIncludedSourcePath(path, config: config),
       let anchored = swiftmutFindReturnBranchSourceLocation(
        for: branch,
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        mutation: mutation,
        config: config
       ) {
      return anchored
    }
  }

  if let definingInstruction = branch.operands.first?.value.definingInstruction,
     let fileNameAndPosition = definingInstruction.location.fileNameAndPosition {
    let path = fileNameAndPosition.path.string
    if let matchedPath = swiftmutIncludedSourcePath(path, config: config),
       let anchored = swiftmutFindReturnBranchSourceLocation(
        for: branch,
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        mutation: mutation,
        config: config
       ) {
      return anchored
    }
  }

  if let functionSourceLocation {
    return swiftmutFindReturnBranchSourceLocation(
      for: branch,
      path: functionSourceLocation.path,
      preferredLine: functionSourceLocation.line,
      mutation: mutation,
      config: config
    )
  }
  return nil
}

func swiftmutFindReturnBranchSourceLocation(
  for branch: BranchInst,
  path: String,
  preferredLine: Int,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  if let exact = swiftmutFindUniqueExplicitReturnSourceLocation(
    path: path,
    preferredLine: preferredLine,
    mutation: mutation,
    config: config
  ) {
    return exact
  }
  if let implicit = swiftmutFindNearestPriorImplicitReturnSourceLocation(
    path: path,
    preferredLine: preferredLine,
    mutation: mutation,
    config: config
  ) {
    return implicit
  }
  if let implicit = swiftmutFindUniqueImplicitReturnSourceLocation(
    path: path,
    preferredLine: preferredLine,
    mutation: mutation,
    config: config
  ) {
    return implicit
  }
  guard let ordinal = swiftmutReturnBranchOrdinalAndCount(
    for: branch,
    mutation: mutation,
    config: config
  ), ordinal.count <= 40 else {
    return nil
  }
  return swiftmutFindOrdinalExplicitReturnSourceLocation(
    path: path,
    preferredLine: preferredLine,
    ordinal: ordinal.ordinal,
    expectedCount: ordinal.count,
    mutation: mutation,
    config: config
  )
}

func swiftmutReturnBranchOrdinalAndCount(
  for branch: BranchInst,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (ordinal: Int, count: Int)? {
  var ordinal = 0
  var count = 0
  var foundBranch = false

  for block in branch.parentFunction.blocks {
    guard let candidate = block.terminator as? BranchInst else {
      continue
    }
    let mutations = swiftmutReturnBranchMutations(for: candidate, config: config)
    guard mutations.contains(where: { $0.mutatedBuiltinName == mutation.mutatedBuiltinName }) else {
      continue
    }
    count += 1
    if candidate === branch {
      ordinal = count
      foundBranch = true
    }
  }

  guard foundBranch else {
    return nil
  }
  return (ordinal, count)
}
