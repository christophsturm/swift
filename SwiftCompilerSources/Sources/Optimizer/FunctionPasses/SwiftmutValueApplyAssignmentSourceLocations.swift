//===--- SwiftmutValueApplyAssignmentSourceLocations.swift ----------------------------------------------===//
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

func swiftmutValueApplySourceLocation(
  for apply: ApplyInst,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  let functionSourceLocation = swiftmutFunctionSourceLocation(
    for: apply.parentFunction,
    config: config
  )
  if mutation.mutatedBuiltinName == "return_zero",
     apply.callee.description.contains("-> Int"),
     swiftmutFunctionNameLooksDefaultArgumentThunk(apply.parentFunction.name.string),
     let anchored = swiftmutFindDescribedDefaultArgumentReturnSourceLocation(
       functionName: apply.parentFunction.name.string,
       locationDescription: apply.location.description,
       mutation: mutation,
       config: config
     ),
     !swiftmutDefaultArgumentValueApplySourceLooksLikeConstructor(anchored.sourceOriginal) {
    return anchored
  }
  if let anchored = swiftmutFindDefaultArgumentValueApplySourceLocation(
    functionName: apply.parentFunction.name.string,
    locationDescription: apply.location.description,
    mutation: mutation,
    config: config
  ) {
    return anchored
  }
  if let fileNameAndPosition = apply.location.fileNameAndPosition {
    let path = fileNameAndPosition.path.string
    if let matchedPath = swiftmutIncludedSourcePath(path, config: config) {
      if let anchored = swiftmutFindValueExpressionSourceLocation(
        for: apply,
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        mutation: mutation,
        config: config
      ) {
        return anchored
      }
      if let functionSourceLocation,
         functionSourceLocation.path == matchedPath,
         let anchored = swiftmutFindLogicalRHSValueApplySourceLocation(
           path: matchedPath,
           functionLine: functionSourceLocation.line,
           locationDescription: apply.location.description,
           mutation: mutation,
           config: config
         ) {
        return anchored
      }
      if let functionSourceLocation,
         functionSourceLocation.path == matchedPath,
        let anchored = swiftmutFindDescribedValueExpressionSourceLocation(
           for: apply,
           path: matchedPath,
           functionLine: functionSourceLocation.line,
           locationDescription: apply.location.description,
           mutation: mutation,
           config: config
      ) {
        return anchored
      }
      if let anchored = swiftmutFindUniqueDescribedValueExpressionSourceLocation(
        for: apply,
        path: matchedPath,
        locationDescription: apply.location.description,
        mutation: mutation,
        config: config
      ) {
        return anchored
      }
      if let functionSourceLocation,
         functionSourceLocation.path == matchedPath,
         let anchored = swiftmutFindMultilineCallValueSourceLocation(
           path: matchedPath,
           functionLine: functionSourceLocation.line,
           locationDescription: apply.location.description,
           mutation: mutation,
           config: config
         ) {
        return anchored
      }
      if let functionSourceLocation,
         functionSourceLocation.path == matchedPath,
         let anchored = swiftmutFindStringInterpolationValueSourceLocation(
           for: apply,
           path: matchedPath,
           preferredLine: functionSourceLocation.line,
           mutation: mutation,
           config: config
         ) {
        return anchored
      }
      if let functionSourceLocation,
         functionSourceLocation.path == matchedPath,
         let anchored = swiftmutFindStringDescriptionValueSourceLocation(
           for: apply,
           path: matchedPath,
           preferredLine: functionSourceLocation.line,
           mutation: mutation,
           config: config
         ) {
        return anchored
      }
      if let functionSourceLocation,
         functionSourceLocation.path == matchedPath,
         let anchored = swiftmutFindStringComparisonValueSourceLocation(
           for: apply,
           path: matchedPath,
           preferredLine: functionSourceLocation.line,
           mutation: mutation,
           config: config
      ) {
        return anchored
      }
      if let functionSourceLocation,
         functionSourceLocation.path == matchedPath,
         let anchored = swiftmutFindDictionaryLiteralValueSourceLocation(
           for: apply,
           path: matchedPath,
           functionLine: functionSourceLocation.line,
           mutation: mutation,
           config: config
         ) {
        return anchored
      }
      if let functionSourceLocation,
         functionSourceLocation.path == matchedPath,
         let anchored = swiftmutFindOrdinalValueExpressionSourceLocation(
           for: apply,
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
    if let anchored = swiftmutFindValueExpressionSourceLocation(
      for: apply,
      path: functionSourceLocation.path,
      preferredLine: functionSourceLocation.line,
      mutation: mutation,
      config: config
    ) {
      return anchored
    }
    if let anchored = swiftmutFindLogicalRHSValueApplySourceLocation(
      path: functionSourceLocation.path,
      functionLine: functionSourceLocation.line,
      locationDescription: apply.location.description,
      mutation: mutation,
      config: config
    ) {
      return anchored
    }
    if let anchored = swiftmutFindDescribedValueExpressionSourceLocation(
      for: apply,
      path: functionSourceLocation.path,
      functionLine: functionSourceLocation.line,
      locationDescription: apply.location.description,
      mutation: mutation,
      config: config
    ) {
      return anchored
    }
    if let anchored = swiftmutFindUniqueDescribedValueExpressionSourceLocation(
      for: apply,
      path: functionSourceLocation.path,
      locationDescription: apply.location.description,
      mutation: mutation,
      config: config
    ) {
      return anchored
    }
    if let anchored = swiftmutFindMultilineCallValueSourceLocation(
      path: functionSourceLocation.path,
      functionLine: functionSourceLocation.line,
      locationDescription: apply.location.description,
      mutation: mutation,
      config: config
    ) {
      return anchored
    }
    if let anchored = swiftmutFindStringInterpolationValueSourceLocation(
      for: apply,
      path: functionSourceLocation.path,
      preferredLine: functionSourceLocation.line,
      mutation: mutation,
      config: config
    ) {
      return anchored
    }
    if let anchored = swiftmutFindStringDescriptionValueSourceLocation(
      for: apply,
      path: functionSourceLocation.path,
      preferredLine: functionSourceLocation.line,
      mutation: mutation,
      config: config
    ) {
      return anchored
    }
    if let anchored = swiftmutFindStringComparisonValueSourceLocation(
      for: apply,
      path: functionSourceLocation.path,
      preferredLine: functionSourceLocation.line,
      mutation: mutation,
      config: config
    ) {
      return anchored
    }
    if let anchored = swiftmutFindDictionaryLiteralValueSourceLocation(
      for: apply,
      path: functionSourceLocation.path,
      functionLine: functionSourceLocation.line,
      mutation: mutation,
      config: config
    ) {
      return anchored
    }
    if let anchored = swiftmutFindOrdinalValueExpressionSourceLocation(
      for: apply,
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

func swiftmutDefaultArgumentValueApplySourceLooksLikeConstructor(_ sourceOriginal: String) -> Bool {
  let bytes = Array(sourceOriginal.utf8)
  let start = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
  let end = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  guard start + 2 <= end,
        bytes[end - 2] == 40,
        bytes[end - 1] == 41,
        swiftmutIsASCIIUppercase(bytes[start]) else {
    return false
  }
  var index = start + 1
  while index < end - 2 {
    guard swiftmutIsASCIILetterNumberOrUnderscore(bytes[index]) || bytes[index] == 46 else {
      return false
    }
    index += 1
  }
  return true
}

func swiftmutAssignmentValueSourceLocation(
  for store: StoreInst,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  let destinationNames = swiftmutAssignmentDestinationNames(for: store)
  let sourceNames = swiftmutAssignmentSourceNames(for: store)
  let targetNames = destinationNames.isEmpty
    ? swiftmutUniqueAssignmentNames(sourceNames)
    : swiftmutUniqueAssignmentNames(destinationNames)
  let functionSourceLocation = swiftmutFunctionSourceLocation(
    for: store.parentFunction,
    config: config
  )
  if let fileNameAndPosition = store.location.fileNameAndPosition {
    let path = fileNameAndPosition.path.string
    if let matchedPath = swiftmutIncludedSourcePath(path, config: config) {
      if let anchored = swiftmutFindAssignmentValueSourceLocation(
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        mutation: mutation,
        config: config,
        targetNames: targetNames,
        requiresDirectValueExpression: true
      ) {
        return anchored
      }
      if !targetNames.isEmpty,
         let anchored = swiftmutFindAssignmentValueSourceLocation(
           path: matchedPath,
           preferredLine: fileNameAndPosition.line,
           mutation: mutation,
           config: config,
           targetNames: targetNames,
           requiresDirectValueExpression: false
         ) {
        return anchored
      }
      if let functionSourceLocation,
         functionSourceLocation.path == matchedPath,
         let anchored = swiftmutFindOrdinalAssignmentValueSourceLocation(
           for: store,
           path: matchedPath,
           preferredLine: functionSourceLocation.line,
           mutation: mutation,
           config: config
         ) {
        return anchored
      }
    }
  }

  if let definingInstruction = store.source.definingInstruction,
     let fileNameAndPosition = definingInstruction.location.fileNameAndPosition {
    let path = fileNameAndPosition.path.string
    if let matchedPath = swiftmutIncludedSourcePath(path, config: config) {
      if let anchored = swiftmutFindAssignmentValueSourceLocation(
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        mutation: mutation,
        config: config,
        targetNames: targetNames,
        requiresDirectValueExpression: true
      ) {
        return anchored
      }
      if !targetNames.isEmpty,
         let anchored = swiftmutFindAssignmentValueSourceLocation(
           path: matchedPath,
           preferredLine: fileNameAndPosition.line,
           mutation: mutation,
           config: config,
           targetNames: targetNames,
           requiresDirectValueExpression: false
         ) {
        return anchored
      }
    }
  }

  if let functionSourceLocation {
    if let anchored = swiftmutFindScopedAssignmentValueSourceLocation(
      path: functionSourceLocation.path,
      functionLine: functionSourceLocation.line,
      mutation: mutation,
      config: config,
      targetNames: targetNames,
      requiresDirectValueExpression: true
    ) {
      return anchored
    }
    if !targetNames.isEmpty,
       let anchored = swiftmutFindScopedAssignmentValueSourceLocation(
         path: functionSourceLocation.path,
         functionLine: functionSourceLocation.line,
         mutation: mutation,
         config: config,
         targetNames: targetNames,
         requiresDirectValueExpression: false
       ) {
      return anchored
    }
    if let anchored = swiftmutFindStoreSnippetAssignmentValueSourceLocation(
      for: store,
      path: functionSourceLocation.path,
      functionLine: functionSourceLocation.line,
      mutation: mutation,
      config: config,
      targetNames: targetNames
    ) {
      return anchored
    }
    if let anchored = swiftmutFindStoreUsageSnippetAssignmentValueSourceLocation(
      for: store,
      path: functionSourceLocation.path,
      functionLine: functionSourceLocation.line,
      mutation: mutation,
      config: config,
      targetNames: targetNames
    ) {
      return anchored
    }
    if let anchored = swiftmutFindScopedDescribedAssignmentValueSourceLocation(
      path: functionSourceLocation.path,
      functionLine: functionSourceLocation.line,
      locationDescription: store.location.description,
      mutation: mutation,
      config: config,
      targetNames: targetNames
    ) {
      return anchored
    }
    if let definingInstruction = store.source.definingInstruction,
       let anchored = swiftmutFindScopedDescribedAssignmentValueSourceLocation(
         path: functionSourceLocation.path,
         functionLine: functionSourceLocation.line,
         locationDescription: definingInstruction.location.description,
         mutation: mutation,
         config: config,
         targetNames: targetNames
       ) {
      return anchored
    }
    if let anchored = swiftmutFindAssignmentValueSourceLocation(
      path: functionSourceLocation.path,
      preferredLine: functionSourceLocation.line,
      mutation: mutation,
      config: config,
      targetNames: targetNames,
      requiresDirectValueExpression: true
    ) {
      return anchored
    }
    if !targetNames.isEmpty,
       let anchored = swiftmutFindAssignmentValueSourceLocation(
         path: functionSourceLocation.path,
         preferredLine: functionSourceLocation.line,
         mutation: mutation,
         config: config,
         targetNames: targetNames,
         requiresDirectValueExpression: false
       ) {
      return anchored
    }
    if let anchored = swiftmutFindOrdinalAssignmentValueSourceLocation(
      for: store,
      path: functionSourceLocation.path,
      preferredLine: functionSourceLocation.line,
      mutation: mutation,
      config: config
    ) {
      return anchored
    }
    if let anchored = swiftmutFindScopedLocalBindingValueSourceLocation(
      path: functionSourceLocation.path,
      functionLine: functionSourceLocation.line,
      mutation: mutation,
      config: config,
      targetNames: targetNames
    ) {
      return anchored
    }
    if let anchored = swiftmutFindScopedLabeledAssignmentValueSourceLocation(
      path: functionSourceLocation.path,
      functionLine: functionSourceLocation.line,
      mutation: mutation,
      config: config,
      targetNames: targetNames
    ) {
      return anchored
    }
    if let anchored = swiftmutFindFunctionSignatureAssignmentValueSourceLocation(
      path: functionSourceLocation.path,
      functionLine: functionSourceLocation.line,
      mutation: mutation,
      config: config,
      targetNames: targetNames
    ) {
      return anchored
    }
    if let anchored = swiftmutFindUniqueFileCompoundAssignmentValueSourceLocation(
      path: functionSourceLocation.path,
      mutation: mutation,
      config: config,
      targetNames: targetNames
    ) {
      return anchored
    }
    if let anchored = swiftmutFindUniqueFileAssignmentValueSourceLocation(
      path: functionSourceLocation.path,
      mutation: mutation,
      config: config,
      targetNames: targetNames
    ) {
      return anchored
    }
    if let definingInstruction = store.source.definingInstruction,
       let anchored = swiftmutFindSourceSnippetAssignmentValueSourceLocation(
         path: functionSourceLocation.path,
         locationDescription: definingInstruction.location.description,
         mutation: mutation,
         config: config,
         targetNames: targetNames
       ) {
      return anchored
    }
  }
  if !targetNames.isEmpty {
    if let definingInstruction = store.source.definingInstruction,
       let anchored = swiftmutFindDescribedAssignmentValueSourceLocation(
         locationDescription: definingInstruction.location.description,
         mutation: mutation,
         config: config,
         targetNames: targetNames
       ) {
      return anchored
    }
    if let anchored = swiftmutFindDescribedAssignmentValueSourceLocation(
      locationDescription: store.location.description,
      mutation: mutation,
      config: config,
      targetNames: targetNames
    ) {
      return anchored
    }
  }
  return nil
}

func swiftmutFindFunctionSignatureAssignmentValueSourceLocation(
  path: String,
  functionLine: Int,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig,
  targetNames: [String]
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard functionLine > 0,
        !targetNames.isEmpty,
        let text = swiftmutRead(path) else {
    return nil
  }

  var matches: [(line: Int, column: Int, sourceOriginal: String, sourceMutated: String)] = []
  var currentLine = 1
  var lineStart = text.startIndex
  var index = text.startIndex

  func inspectLine(_ lineText: String, line: Int) {
    guard line >= functionLine,
          matches.count < 2,
          let expression = swiftmutSignatureAssignmentValueExpression(
            lineText,
            mutation: mutation,
            targetNames: targetNames
          ) else {
      return
    }
    matches.append((line, expression.column, expression.sourceOriginal, expression.sourceMutated))
  }

  while index < text.endIndex {
    if text[index] == "\n" {
      let lineText = String(text[lineStart..<index])
      if currentLine >= functionLine {
        inspectLine(lineText, line: currentLine)
        if matches.count >= 2 || swiftmutLineOpensFunctionBody(lineText) || currentLine > functionLine + 120 {
          break
        }
      }
      currentLine += 1
      lineStart = text.index(after: index)
    }
    index = text.index(after: index)
  }

  if index == text.endIndex && currentLine >= functionLine {
    let lineText = String(text[lineStart..<text.endIndex])
    inspectLine(lineText, line: currentLine)
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

func swiftmutFindSourceSnippetAssignmentValueSourceLocation(
  path: String,
  locationDescription: String,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig,
  targetNames: [String]
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard !targetNames.isEmpty,
        let expectedExpression = swiftmutSourceSnippetValueExpression(locationDescription),
        let text = swiftmutRead(path) else {
    return nil
  }

  var matches: [(line: Int, column: Int, sourceOriginal: String, sourceMutated: String)] = []
  var currentLine = 1
  var lineStart = text.startIndex
  var index = text.startIndex

  func inspectLine(_ lineText: String, line: Int) {
    guard matches.count < 2,
          let expression = swiftmutAssignmentOrLocalBindingValueExpression(
            lineText,
            mutation: mutation,
            targetNames: targetNames
          ),
          swiftmutStoreLocationExpressionMatches(
            expression.sourceOriginal,
            expected: expectedExpression
          ) else {
      return
    }
    matches.append((line, expression.column, expression.sourceOriginal, expression.sourceMutated))
  }

  while index < text.endIndex {
    if text[index] == "\n" {
      inspectLine(String(text[lineStart..<index]), line: currentLine)
      if matches.count >= 2 {
        break
      }
      currentLine += 1
      lineStart = text.index(after: index)
    }
    index = text.index(after: index)
  }

  if index == text.endIndex {
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

func swiftmutAssignmentOrLocalBindingValueExpression(
  _ line: String,
  mutation: SwiftmutMutation,
  targetNames: [String]
) -> (column: Int, sourceOriginal: String, sourceMutated: String)? {
  if let assignment = swiftmutAssignmentValueExpression(
    line,
    mutation: mutation,
    targetNames: targetNames,
    requiresDirectValueExpression: false
  ) {
    return assignment
  }
  return swiftmutLocalBindingValueExpression(
    line,
    mutation: mutation,
    targetNames: targetNames
  )
}

func swiftmutFindStoreSnippetAssignmentValueSourceLocation(
  for store: StoreInst,
  path: String,
  functionLine: Int,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig,
  targetNames: [String]
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard functionLine > 0,
        !targetNames.isEmpty,
        let expectedExpression = swiftmutStoreLocationAssignedExpression(store.location.description),
        let text = swiftmutRead(path) else {
    return nil
  }

  var matches: [(line: Int, column: Int, sourceOriginal: String, sourceMutated: String)] = []
  var currentLine = 1
  var lineStart = text.startIndex
  var index = text.startIndex
  var braceDepth = 0
  var sawOpeningBrace = false

  func inspectLine(_ lineText: String, line: Int) {
    guard line >= functionLine,
          matches.count < 2,
          let expression = swiftmutAssignmentValueExpression(
            lineText,
            mutation: mutation,
            targetNames: targetNames,
            requiresDirectValueExpression: false
          ),
          swiftmutStoreLocationExpressionMatches(
            expression.sourceOriginal,
            expected: expectedExpression
          ) else {
      return
    }
    matches.append((line, expression.column, expression.sourceOriginal, expression.sourceMutated))
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
          inspectLine(lineText, line: currentLine)
          if matches.count >= 2 {
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

  if index == text.endIndex && currentLine >= functionLine && sawOpeningBrace && braceDepth > 0 {
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

func swiftmutFindStoreUsageSnippetAssignmentValueSourceLocation(
  for store: StoreInst,
  path: String,
  functionLine: Int,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig,
  targetNames: [String]
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard functionLine > 0,
        !targetNames.isEmpty,
        let snippet = swiftmutQuotedSourceSnippetPrefix(store.location.description),
        let comparison = swiftmutStoreUsageComparisonSnippet(snippet),
        let text = swiftmutRead(path) else {
    return nil
  }

  var matches: [(line: Int, column: Int, sourceOriginal: String, sourceMutated: String)] = []
  var currentLine = 1
  var lineStart = text.startIndex
  var index = text.startIndex
  var braceDepth = 0
  var sawOpeningBrace = false

  func inspectLine(_ lineText: String, line: Int) {
    guard line >= functionLine,
          matches.count < 2 else {
      return
    }
    for targetName in targetNames {
      guard let column = swiftmutLineColumn(
        ofTarget: targetName,
        followedBy: comparison,
        in: lineText
      ) else {
        continue
      }
      matches.append((
        line,
        column,
        targetName,
        swiftmutImplicitReturnSourceMutation(for: mutation)))
      if matches.count >= 2 {
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
          inspectLine(lineText, line: currentLine)
          if matches.count >= 2 {
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

  if index == text.endIndex && currentLine >= functionLine && sawOpeningBrace && braceDepth > 0 {
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

func swiftmutStoreLocationAssignedExpression(_ description: String) -> String? {
  guard let snippet = swiftmutQuotedSourceSnippetPrefix(description) else {
    return nil
  }

  let bytes = Array(snippet.utf8)
  guard bytes.count > 1,
        bytes[0] == 61 else {
    return nil
  }
  let expressionStart = swiftmutSkipHorizontalWhitespace(bytes, from: 2)
  let trimmedEnd = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  guard expressionStart < trimmedEnd else {
    return nil
  }
  return String(decoding: bytes[expressionStart..<trimmedEnd], as: UTF8.self)
}

func swiftmutSourceSnippetValueExpression(_ description: String) -> String? {
  guard let snippet = swiftmutQuotedSourceSnippetPrefix(description) else {
    return nil
  }

  let bytes = Array(snippet.utf8)
  let start = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
  var end = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  if end > start && bytes[end - 1] == 44 {
    end = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: end - 1)
  }
  guard start < end else {
    return nil
  }

  if bytes[start] == 40 {
    var index = start + 1
    while index + 4 <= end {
      if swiftmutASCIIHasExactPrefix(bytes, start: index, prefix: "let ") {
        let nameStart = swiftmutSkipHorizontalWhitespace(bytes, from: index + 3)
        guard nameStart < end && swiftmutIsIdentifierStartByte(bytes[nameStart]) else {
          return nil
        }
        var nameEnd = nameStart + 1
        while nameEnd < end && swiftmutIsIdentifierByte(bytes[nameEnd]) {
          nameEnd += 1
        }
        return String(decoding: bytes[nameStart..<nameEnd], as: UTF8.self)
      }
      index += 1
    }
  }

  while end > start {
    let byte = bytes[end - 1]
    if byte == 41 || byte == 93 || byte == 125 {
      end = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: end - 1)
      continue
    }
    break
  }
  guard start < end else {
    return nil
  }
  return String(decoding: bytes[start..<end], as: UTF8.self)
}

func swiftmutStoreLocationExpressionMatches(
  _ expression: String,
  expected: String
) -> Bool {
  if expression == expected {
    return true
  }
  guard expected.utf8.count >= 8 else {
    return false
  }
  return expression.hasPrefix(expected)
}

func swiftmutStoreUsageComparisonSnippet(_ snippet: String) -> (operatorText: String, rhsText: String)? {
  let bytes = Array(snippet.utf8)
  var index = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
  guard index < bytes.count else {
    return nil
  }

  let operators = ["!=", "==", ">=", "<=", ">", "<"]
  var matchedOperator: String?
  for operatorText in operators {
    if swiftmutASCIIHasExactPrefix(bytes, start: index, prefix: operatorText) {
      matchedOperator = operatorText
      index += operatorText.utf8.count
      break
    }
  }
  guard let operatorText = matchedOperator else {
    return nil
  }

  index = swiftmutSkipHorizontalWhitespace(bytes, from: index)
  let rhsStart = index
  while index < bytes.count && !swiftmutIsHorizontalWhitespace(bytes[index]) {
    index += 1
  }
  guard rhsStart < index else {
    return nil
  }
  let rhsText = String(decoding: bytes[rhsStart..<index], as: UTF8.self)
  return (operatorText, rhsText)
}
