//===--- SwiftmutStatementSourceLocations.swift ----------------------------------------------===//
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

func swiftmutStatementDeletionSourceLocation(
  for store: StoreInst,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  let targetNames = swiftmutAssignmentDestinationNames(for: store)

  var candidates: [(path: String, line: Int)] = []
  if let position = store.location.fileNameAndPosition {
    candidates.append((position.path.string, position.line))
  }
  if let position = store.source.definingInstruction?.location.fileNameAndPosition {
    candidates.append((position.path.string, position.line))
  }

  var seen = Set<String>()
  for candidate in candidates {
    guard candidate.line > 0,
          let path = swiftmutIncludedSourcePath(candidate.path, config: config),
          seen.insert("\(path):\(candidate.line)").inserted,
          let sourceLine = swiftmutAbsoluteSourceLine(path: path, line: candidate.line),
          swiftmutSourceLineIsReassignment(sourceLine) else {
      continue
    }
    let namedExpression = targetNames.isEmpty
      ? nil
      : swiftmutAssignmentValueExpression(
        sourceLine,
        mutation: mutation,
        targetNames: targetNames,
        requiresDirectValueExpression: false
      )
    let locationIsUnique = swiftmutStatementDeletionStoreLocationIsUnique(
      store,
      path: path,
      line: candidate.line,
      config: config
    )
    let expression = namedExpression ?? (locationIsUnique
      ? swiftmutAssignmentValueExpression(
        sourceLine,
        mutation: mutation,
        requiresDirectValueExpression: false
      )
      : nil)
    guard let expression else {
      continue
    }
    return (
      swiftmutTrimPackageRoot(path, config: config),
      candidate.line,
      expression.column,
      expression.sourceOriginal,
      mutation.sourceMutated)
  }

  if let functionLocation = swiftmutFunctionSourceLocation(
    for: store.parentFunction,
    config: config
  ) {
    if let described = swiftmutFindScopedDescribedAssignmentValueSourceLocation(
      path: functionLocation.path,
      functionLine: functionLocation.line,
      locationDescription: store.location.description,
      mutation: mutation,
      config: config,
      targetNames: targetNames
    ), swiftmutStatementDeletionLocationIsReassignment(described, config: config) {
      return described
    }
    if let scoped = swiftmutFindScopedAssignmentValueSourceLocation(
      path: functionLocation.path,
      functionLine: functionLocation.line,
      mutation: mutation,
      config: config,
      targetNames: targetNames,
      requiresDirectValueExpression: false
    ), swiftmutStatementDeletionLocationIsReassignment(scoped, config: config) {
      return scoped
    }
  }
  return nil
}

private func swiftmutStatementDeletionLocationIsReassignment(
  _ location: (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String),
  config: SwiftmutConfig
) -> Bool {
  guard let sourceLine = swiftmutSourceLine(
    file: location.file,
    line: location.line,
    config: config
  ) else {
    return false
  }
  return swiftmutSourceLineIsReassignment(sourceLine)
}

private func swiftmutStatementDeletionStoreLocationIsUnique(
  _ store: StoreInst,
  path: String,
  line: Int,
  config: SwiftmutConfig
) -> Bool {
  var matchingStores = 0
  for block in store.parentFunction.blocks {
    for instruction in block.instructions {
      guard let candidate = instruction as? StoreInst,
            swiftmutCanDeleteStatementAssignment(candidate),
            let position = candidate.location.fileNameAndPosition,
            position.line == line,
            swiftmutIncludedSourcePath(position.path.string, config: config) == path else {
        continue
      }
      matchingStores += 1
      if matchingStores > 1 {
        return false
      }
    }
  }
  return matchingStores == 1
}

private func swiftmutSourceLineIsReassignment(_ line: String) -> Bool {
  let bytes = Array(line.utf8)
  let start = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
  guard start < bytes.count,
        !swiftmutASCIIHasPrefix(bytes, start: start, prefix: "//"),
        !swiftmutASCIIHasExactPrefix(bytes, start: start, prefix: "let "),
        !swiftmutASCIIHasExactPrefix(bytes, start: start, prefix: "var ") else {
    return false
  }
  return true
}

func swiftmutStatementCallSourceLocation(
  for apply: ApplyInst,
  mutation: SwiftmutMutation,
  kind: SwiftmutStatementCallKind,
  config: SwiftmutConfig
) -> SwiftmutVoidCallSourceLocationResult {
  let functionSourceLocation = swiftmutFunctionSourceLocation(
    for: apply.parentFunction,
    config: config
  )
  if kind == .unusedResult {
    var describedPaths: [String] = []
    if let functionSourceLocation {
      describedPaths.append(functionSourceLocation.path)
    }
    for path in swiftmutSwiftSourcePaths(config: config)
        where apply.parentFunction.location.description.contains(path)
          && !describedPaths.contains(path) {
      describedPaths.append(path)
    }
    for path in describedPaths {
      if let described = swiftmutFindUniqueDescribedStatementCallSourceLocation(
        path: path,
        locationDescription: apply.location.description,
        mutation: mutation,
        function: apply.parentFunction,
        config: config
      ) {
        return .found(
          file: described.file,
          line: described.line,
          column: described.column,
          sourceOriginal: described.sourceOriginal,
          sourceMutated: described.sourceMutated
        )
      }
    }
  }
  if let fileNameAndPosition = apply.location.fileNameAndPosition {
    let path = fileNameAndPosition.path.string
    if let matchedPath = swiftmutIncludedSourcePath(path, config: config) {
      let candidate = (
        swiftmutTrimPackageRoot(matchedPath, config: config),
        fileNameAndPosition.line,
        fileNameAndPosition.column,
        mutation.sourceOriginal,
        mutation.sourceMutated)
      if kind == .void,
         let setterAssignment = swiftmutSetterAssignmentSourceLocation(
           for: apply,
           path: matchedPath,
           line: fileNameAndPosition.line,
           mutation: mutation,
           config: config
         ) {
        return .found(
          file: setterAssignment.file,
          line: setterAssignment.line,
          column: setterAssignment.column,
          sourceOriginal: setterAssignment.sourceOriginal,
          sourceMutated: setterAssignment.sourceMutated
        )
      }
      if swiftmutVoidCallSourceLooksLikeStatement(file: candidate.0, line: candidate.1, config: config) {
        return .found(
          file: candidate.0,
          line: candidate.1,
          column: candidate.2,
          sourceOriginal: candidate.3,
          sourceMutated: candidate.4
        )
      }
      if let functionSourceLocation,
         functionSourceLocation.path == matchedPath,
         fileNameAndPosition.line > functionSourceLocation.line {
        return .nonStatement
      }
      if let anchored = swiftmutFindCalleeOrdinalStatementCallSourceLocation(
        for: apply,
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        mutation: mutation,
        kind: kind,
        config: config
      ) {
        return .found(
          file: anchored.file,
          line: anchored.line,
          column: anchored.column,
          sourceOriginal: anchored.sourceOriginal,
          sourceMutated: anchored.sourceMutated
        )
      }
      if swiftmutMutationEligibleStatementCallCount(
        in: apply.parentFunction,
        kind: kind,
        config: config
      ) == 1,
         let functionSourceLocation,
         functionSourceLocation.path == matchedPath,
         fileNameAndPosition.line <= functionSourceLocation.line,
         let anchored = swiftmutFindUniqueStatementCallSourceLocation(
           path: matchedPath,
           preferredLine: fileNameAndPosition.line,
           mutation: mutation,
           config: config
         ) {
        return .found(
          file: anchored.file,
          line: anchored.line,
          column: anchored.column,
          sourceOriginal: anchored.sourceOriginal,
          sourceMutated: anchored.sourceMutated
        )
      }
      if let functionSourceLocation,
         functionSourceLocation.path == matchedPath,
         let anchored = swiftmutFindCalleeOrdinalStatementCallSourceLocation(
           for: apply,
           path: matchedPath,
           preferredLine: functionSourceLocation.line,
           mutation: mutation,
           kind: kind,
           config: config
         ) {
        return .found(
          file: anchored.file,
          line: anchored.line,
          column: anchored.column,
          sourceOriginal: anchored.sourceOriginal,
          sourceMutated: anchored.sourceMutated
        )
      }
    }
  }

  if let fallback = swiftmutInstructionSourceLocation(
    for: apply,
    mutation: mutation,
    config: config
  ) {
    if swiftmutVoidCallSourceLooksLikeStatement(file: fallback.file, line: fallback.line, config: config) {
      return .found(
        file: fallback.file,
        line: fallback.line,
        column: fallback.column,
        sourceOriginal: fallback.sourceOriginal,
        sourceMutated: fallback.sourceMutated
      )
    }
    let fallbackPath = fallback.file.hasPrefix("/") || config.packageRoot.isEmpty
      ? fallback.file
      : config.packageRoot + "/" + fallback.file
    if kind == .unusedResult,
       let described = swiftmutFindUniqueDescribedStatementCallSourceLocation(
         path: fallbackPath,
         locationDescription: apply.location.description,
         mutation: mutation,
         function: apply.parentFunction,
         config: config
       ) {
      return .found(
        file: described.file,
        line: described.line,
        column: described.column,
        sourceOriginal: described.sourceOriginal,
        sourceMutated: described.sourceMutated
      )
    }
    if kind == .void,
       let setterAssignment = swiftmutSetterAssignmentSourceLocation(
         for: apply,
         path: fallbackPath,
         line: fallback.line,
         mutation: mutation,
         config: config
       ) {
      return .found(
        file: setterAssignment.file,
        line: setterAssignment.line,
        column: setterAssignment.column,
        sourceOriginal: setterAssignment.sourceOriginal,
        sourceMutated: setterAssignment.sourceMutated
      )
    }
    if kind == .void,
       swiftmutApplyIsSetter(apply),
       let functionSourceLocation,
       functionSourceLocation.path == fallbackPath,
       let scopedSetterAssignment = swiftmutFindScopedAssignmentValueSourceLocation(
         path: functionSourceLocation.path,
         functionLine: functionSourceLocation.line,
         mutation: mutation,
         config: config,
         targetNames: swiftmutSourceExpressionIdentifiers(for: apply),
         requiresDirectValueExpression: false
       ) {
      return .found(
        file: scopedSetterAssignment.file,
        line: scopedSetterAssignment.line,
        column: scopedSetterAssignment.column,
        sourceOriginal: scopedSetterAssignment.sourceOriginal,
        sourceMutated: scopedSetterAssignment.sourceMutated
      )
    }
    if let functionSourceLocation,
       functionSourceLocation.path == fallbackPath,
       fallback.line > functionSourceLocation.line {
      return .nonStatement
    }
    if let anchored = swiftmutFindCalleeOrdinalStatementCallSourceLocation(
      for: apply,
      path: fallbackPath,
      preferredLine: fallback.line,
      mutation: mutation,
      kind: kind,
      config: config
    ) {
      return .found(
        file: anchored.file,
        line: anchored.line,
        column: anchored.column,
        sourceOriginal: anchored.sourceOriginal,
        sourceMutated: anchored.sourceMutated
      )
    }
    if swiftmutMutationEligibleStatementCallCount(
      in: apply.parentFunction,
      kind: kind,
      config: config
    ) == 1,
       let functionSourceLocation,
       functionSourceLocation.path == fallbackPath,
       fallback.line <= functionSourceLocation.line,
       let anchored = swiftmutFindUniqueStatementCallSourceLocation(
         path: fallbackPath,
         preferredLine: fallback.line,
         mutation: mutation,
         config: config
       ) {
      return .found(
        file: anchored.file,
        line: anchored.line,
        column: anchored.column,
        sourceOriginal: anchored.sourceOriginal,
        sourceMutated: anchored.sourceMutated
      )
    }
    if let functionSourceLocation,
       functionSourceLocation.path == fallbackPath,
       let anchored = swiftmutFindCalleeOrdinalStatementCallSourceLocation(
         for: apply,
         path: fallbackPath,
         preferredLine: functionSourceLocation.line,
         mutation: mutation,
         kind: kind,
         config: config
       ) {
      return .found(
        file: anchored.file,
        line: anchored.line,
        column: anchored.column,
        sourceOriginal: anchored.sourceOriginal,
        sourceMutated: anchored.sourceMutated
      )
    }
    return .nonStatement
  }

  return .missing
}

func swiftmutFindUniqueDescribedStatementCallSourceLocation(
  path: String,
  locationDescription: String,
  mutation: SwiftmutMutation,
  function: Function,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard let snippet = swiftmutQuotedSourceSnippetPrefix(locationDescription),
        swiftmutDescribedValueSnippetLooksMappable(snippet),
        let text = swiftmutRead(path) else {
    return nil
  }

  let prefixes = swiftmutDescribedValueSnippetPrefixes(snippet)
  guard !prefixes.isEmpty else {
    return nil
  }

  var matches: [(line: Int, column: Int)] = []
  var currentLine = 1
  var lineStart = text.startIndex
  var index = text.startIndex

  func inspectLine(_ lineText: String, line: Int) {
    guard matches.count < 2 else {
      return
    }
    let bytes = Array(lineText.utf8)
    let start = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
    let end = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
    guard start < end else {
      return
    }

    for prefix in prefixes {
      guard let matchStart = swiftmutASCIIIndex(
        bytes,
        start: start,
        end: end,
        pattern: prefix
      ), swiftmutSourceLineLooksLikeVoidCallStatement(lineText)
          || swiftmutSourceLineLooksLikeDiscardedCallStatement(
            bytes: bytes,
            start: start,
            callStart: matchStart
          ) else {
        continue
      }
      matches.append((line, matchStart + 1))
      return
    }
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

  if index == text.endIndex && matches.count < 2 {
    inspectLine(String(text[lineStart..<text.endIndex]), line: currentLine)
  }

  let selectedMatches: [(line: Int, column: Int)]
  if matches.count > 1 {
    selectedMatches = matches.filter {
      swiftmutSourceLineBelongsToFunction(
        $0.line,
        path: path,
        function: function,
        config: config
      )
    }
  } else {
    selectedMatches = matches
  }
  guard selectedMatches.count == 1,
        let match = selectedMatches.first else {
    return nil
  }
  return (
    swiftmutTrimPackageRoot(path, config: config),
    match.line,
    match.column,
    mutation.sourceOriginal,
    mutation.sourceMutated
  )
}

private func swiftmutSourceLineLooksLikeDiscardedCallStatement(
  bytes: [UInt8],
  start: Int,
  callStart: Int
) -> Bool {
  guard start < callStart else {
    return false
  }
  return swiftmutASCIIHasExactPrefix(bytes, start: start, prefix: "_ = ")
    || swiftmutASCIIHasExactPrefix(bytes, start: start, prefix: "let _ = ")
    || swiftmutASCIIHasExactPrefix(bytes, start: start, prefix: "var _ = ")
}

private func swiftmutSetterAssignmentSourceLocation(
  for apply: ApplyInst,
  path: String,
  line: Int,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard swiftmutApplyIsSetter(apply),
        line > 0,
        let sourceLine = swiftmutAbsoluteSourceLine(path: path, line: line),
        swiftmutSourceLineIsReassignment(sourceLine),
        let expression = swiftmutAssignmentValueExpression(
          sourceLine,
          mutation: mutation,
          targetNames: swiftmutSourceExpressionIdentifiers(for: apply),
          requiresDirectValueExpression: false
        ) else {
    return nil
  }
  return (
    swiftmutTrimPackageRoot(path, config: config),
    line,
    expression.column,
    expression.sourceOriginal,
    expression.sourceMutated
  )
}

func swiftmutFindCalleeOrdinalStatementCallSourceLocation(
  for apply: ApplyInst,
  path: String,
  preferredLine: Int,
  mutation: SwiftmutMutation,
  kind: SwiftmutStatementCallKind,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  let identifiers = swiftmutSourceExpressionIdentifiers(for: apply)
  guard !identifiers.isEmpty,
        let ordinal = swiftmutStatementCallOrdinalAndCount(
          for: apply,
          matchingAnyOf: identifiers,
          kind: kind,
          config: config
        ),
        let text = swiftmutRead(path) else {
    return nil
  }

  let candidates = swiftmutCalleeStatementCallSourceCandidates(
    in: text,
    path: path,
    preferredLine: preferredLine,
    identifiers: identifiers,
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

func swiftmutStatementCallOrdinalAndCount(
  for apply: ApplyInst,
  matchingAnyOf identifiers: [String],
  kind: SwiftmutStatementCallKind,
  config: SwiftmutConfig
) -> (ordinal: Int, count: Int)? {
  var ordinal = 0
  var count = 0
  for block in apply.parentFunction.blocks {
    for instruction in block.instructions {
      guard let candidate = instruction as? ApplyInst,
            swiftmutStatementCallIsEligible(candidate, kind: kind, config: config),
            swiftmutSourceCalleeIdentifiers(for: candidate).contains(where: { identifiers.contains($0) }) else {
        continue
      }
      count += 1
      if candidate === apply {
        ordinal = count
      }
    }
  }
  guard ordinal > 0 else {
    return nil
  }
  return (ordinal, count)
}

func swiftmutMutationEligibleStatementCallCount(
  in function: Function,
  kind: SwiftmutStatementCallKind,
  config: SwiftmutConfig
) -> Int {
  var count = 0
  for block in function.blocks {
    for instruction in block.instructions {
      guard let apply = instruction as? ApplyInst,
            swiftmutStatementCallIsEligible(apply, kind: kind, config: config) else {
        continue
      }
      count += 1
    }
  }
  return count
}

private func swiftmutStatementCallIsEligible(
  _ apply: ApplyInst,
  kind: SwiftmutStatementCallKind,
  config: SwiftmutConfig
) -> Bool {
  switch kind {
  case .void:
    return apply.type.isVoid
      && swiftmutVoidCallMutation(for: apply, config: config) != nil
  case .unusedResult:
    return !apply.type.isVoid
      && apply.uses.isEmpty
      && swiftmutStatementDeletionMutation(for: apply, config: config) != nil
  }
}

func swiftmutCalleeStatementCallSourceCandidates(
  in text: String,
  path: String,
  preferredLine: Int,
  identifiers: [String],
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> [(file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)] {
  guard preferredLine > 0 else {
    return []
  }
  let lastLine = preferredLine + 220
  var candidates: [(file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)] = []
  var currentLine = 1
  var lineStart = text.startIndex
  var index = text.startIndex
  var braceDepth = 0
  var sawOpeningBrace = false

  func inspectLine(_ lineText: String, line: Int) {
    guard line >= preferredLine,
          line <= lastLine,
          swiftmutSourceLineLooksLikeVoidCallStatement(lineText),
          swiftmutSourceLineContainsExpressionIdentifier(lineText, identifiers: identifiers) else {
      return
    }
    let bytes = Array(lineText.utf8)
    let start = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
    candidates.append((
      swiftmutTrimPackageRoot(path, config: config),
      line,
      start + 1,
      mutation.sourceOriginal,
      mutation.sourceMutated
    ))
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
      inspectLine(lineText, line: currentLine)
      if currentLine >= preferredLine {
        updateBraceDepth(lineText)
      }
      if currentLine >= lastLine || (sawOpeningBrace && braceDepth <= 0) {
        break
      }
      currentLine += 1
      lineStart = text.index(after: index)
    }
    index = text.index(after: index)
  }

  if index == text.endIndex && currentLine <= lastLine {
    let lineText = String(text[lineStart..<text.endIndex])
    inspectLine(lineText, line: currentLine)
  }
  return candidates
}

func swiftmutFindUniqueStatementCallSourceLocation(
  path: String,
  preferredLine: Int,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard preferredLine > 0,
        let text = swiftmutRead(path) else {
    return nil
  }

  let firstLine = preferredLine
  let lastLine = preferredLine + 40
  var matches: [(line: Int, column: Int)] = []
  var currentLine = 1
  var lineStart = text.startIndex
  var index = text.startIndex
  var braceDepth = 0
  var sawOpeningBrace = false

  func inspectLine(_ lineText: String, line: Int) {
    guard line >= firstLine,
          line <= lastLine,
          matches.count < 2,
          swiftmutSourceLineLooksLikeVoidCallStatement(lineText) else {
      return
    }
    let bytes = Array(lineText.utf8)
    let start = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
    matches.append((line, start + 1))
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
      inspectLine(lineText, line: currentLine)
      if currentLine >= firstLine {
        updateBraceDepth(lineText)
      }
      if currentLine >= lastLine || matches.count >= 2 || (sawOpeningBrace && braceDepth <= 0) {
        break
      }
      currentLine += 1
      lineStart = text.index(after: index)
    }
    index = text.index(after: index)
  }

  if index == text.endIndex && currentLine <= lastLine {
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
    mutation.sourceOriginal,
    mutation.sourceMutated)
}

func swiftmutBranchSourceLocation(
  for branch: CondBranchInst,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  let function = branch.parentFunction

  func usableConditionSourceLocation(
    _ location: (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)
  ) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
    if swiftmutSourceLocationBelongsToFunction(location, function: function, config: config) {
      return location
    }
    return nil
  }

  if let fileNameAndPosition = branch.location.fileNameAndPosition {
    let path = fileNameAndPosition.path.string
    if let matchedPath = swiftmutIncludedSourcePath(path, config: config) {
      if let sourceLocation = swiftmutGenericConditionSourceLocation(
        path: matchedPath,
        line: fileNameAndPosition.line,
        fallbackColumn: fileNameAndPosition.column,
        mutation: mutation,
        config: config
      ) {
        return usableConditionSourceLocation(sourceLocation)
      }
      if let ordinal = swiftmutGenericConditionBranchOrdinal(branch),
         let sourceLocation = swiftmutFindGenericConditionSourceLocationByBranchOrdinal(
          path: matchedPath,
          preferredLine: fileNameAndPosition.line,
          branchOrdinal: ordinal,
          mutation: mutation,
          config: config
         ) {
        return usableConditionSourceLocation(sourceLocation)
      }
      if let sourceLocation = swiftmutFindDescribedBranchGenericConditionSourceLocation(
        branch,
        mutation: mutation,
        config: config
      ) {
        return usableConditionSourceLocation(sourceLocation)
      }
      return nil
    }
  }

  let location = branch.parentFunction.location.description
  for path in swiftmutSwiftSourcePaths(config: config) {
    guard location.contains(path),
          let line = swiftmutPreferredLine(in: location, path: path) else {
      continue
    }
    if let ordinal = swiftmutGenericConditionBranchOrdinal(branch),
       let sourceLocation = swiftmutFindGenericConditionSourceLocationByBranchOrdinal(
        path: path,
        preferredLine: line,
        branchOrdinal: ordinal,
        mutation: mutation,
        config: config
       ) {
      return usableConditionSourceLocation(sourceLocation)
    }
    if let sourceLocation = swiftmutFindDescribedBranchGenericConditionSourceLocation(
      branch,
      mutation: mutation,
      config: config
    ) {
      return usableConditionSourceLocation(sourceLocation)
    }
    if let anchored = swiftmutFindUniqueExplicitConditionSourceLocation(
      path: path,
      preferredLine: line,
      mutation: mutation,
      config: config
    ) {
      return usableConditionSourceLocation(anchored)
    }
    return nil
  }
  return nil
}

func swiftmutFindDescribedBranchGenericConditionSourceLocation(
  _ branch: CondBranchInst,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  let function = branch.parentFunction
  let functionLocation = function.location.description
  if let sourceLocation = swiftmutFindDescribedGenericConditionSourceLocation(
    moduleName: "",
    functionLocation: functionLocation,
    locationDescription: branch.location.description,
    mutation: mutation,
    config: config
  ) {
    return sourceLocation
  }
  guard let conditionLocation = branch.condition.definingInstruction?.location.description,
        conditionLocation != branch.location.description else {
    return nil
  }
  return swiftmutFindDescribedGenericConditionSourceLocation(
    moduleName: "",
    functionLocation: functionLocation,
    locationDescription: conditionLocation,
    mutation: mutation,
    config: config)
}

func swiftmutGenericConditionBranchOrdinal(_ branch: CondBranchInst) -> Int? {
  var ordinal = 0
  for block in branch.parentFunction.blocks {
    guard let candidate = block.terminator as? CondBranchInst else {
      continue
    }
    if let comparison = candidate.condition as? BuiltinInst,
       swiftmutIsComparisonBuiltin(comparison) {
      continue
    }
    ordinal += 1
    if candidate === branch {
      return ordinal
    }
  }
  return nil
}

func swiftmutFindGenericConditionSourceLocationByBranchOrdinal(
  path: String,
  preferredLine: Int,
  branchOrdinal: Int,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard preferredLine > 0,
        branchOrdinal > 0,
        let text = swiftmutRead(path) else {
    return nil
  }

  var consumedBranches = 0
  var currentLine = 1
  var lineStart = text.startIndex
  var index = text.startIndex
  var braceDepth = 0
  var sawOpeningBrace = false

  func inspectLine(_ lineText: String, line: Int)
    -> (line: Int, column: Int, sourceOriginal: String)? {
    guard line >= preferredLine else {
      return nil
    }
    for expression in swiftmutGenericConditionExpressionCandidates(lineText) {
      let branchSpan = swiftmutGenericConditionBranchSpan(expression.sourceOriginal)
      let rangeStart = consumedBranches + 1
      let rangeEnd = consumedBranches + branchSpan
      consumedBranches = rangeEnd
      guard branchSpan == 1,
            branchOrdinal >= rangeStart,
            branchOrdinal <= rangeEnd else {
        continue
      }
      return (line, expression.column, expression.sourceOriginal)
    }
    return nil
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
        if let match = inspectLine(lineText, line: currentLine) {
          return (
            swiftmutTrimPackageRoot(path, config: config),
            match.line,
            match.column,
            match.sourceOriginal,
            mutation.sourceMutated)
        }
        updateBraceDepth(lineText)
        if consumedBranches >= branchOrdinal {
          break
        }
        if sawOpeningBrace && braceDepth <= 0 {
          break
        }
        if currentLine >= preferredLine + 300 {
          break
        }
      }
      currentLine += 1
      lineStart = text.index(after: index)
    }
    index = text.index(after: index)
  }

  if index == text.endIndex && currentLine >= preferredLine {
    let lineText = String(text[lineStart..<text.endIndex])
    if let match = inspectLine(lineText, line: currentLine) {
      return (
        swiftmutTrimPackageRoot(path, config: config),
        match.line,
        match.column,
        match.sourceOriginal,
        mutation.sourceMutated)
    }
  }
  return nil
}

func swiftmutGenericConditionBranchSpan(_ sourceOriginal: String) -> Int {
  let bytes = Array(sourceOriginal.utf8)
  let end = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  var count = 1
  var searchStart = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
  while let logical = swiftmutTopLevelLogicalOperatorIndex(bytes: bytes, start: searchStart, end: end) {
    count += 1
    searchStart = logical + 2
  }
  return count
}

func swiftmutTopLevelLogicalOperatorIndex(bytes: [UInt8], start: Int, end: Int) -> Int? {
  swiftmutFirstTopLevelIndex(bytes, start: start, end: end) { index in
    guard index + 1 < end else {
      return false
    }
    return (bytes[index] == 38 || bytes[index] == 124) && bytes[index + 1] == bytes[index]
  }
}

func swiftmutFindUniqueExplicitConditionSourceLocation(
  path: String,
  preferredLine: Int,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard preferredLine > 0,
        let text = swiftmutRead(path) else {
    return nil
  }
  if let multiline = swiftmutFindUniqueMultilineExplicitConditionSourceLocation(
    path: path,
    preferredLine: preferredLine,
    mutation: mutation,
    config: config
  ) {
    return multiline
  }

  var matches: [(line: Int, column: Int, sourceOriginal: String)] = []
  var currentLine = 1
  var lineStart = text.startIndex
  var index = text.startIndex
  var braceDepth = 0
  var sawOpeningBrace = false

  func inspectLine(_ lineText: String, line: Int) {
    guard line >= preferredLine,
          line <= preferredLine + 120,
          matches.count < 2,
          let expression = swiftmutGenericConditionExpression(lineText) else {
      return
    }
    matches.append((line, expression.column, expression.sourceOriginal))
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
        inspectLine(lineText, line: currentLine)
        updateBraceDepth(lineText)
        if sawOpeningBrace && braceDepth <= 0 {
          break
        }
        if currentLine >= preferredLine + 120 {
          break
        }
      }
      currentLine += 1
      lineStart = text.index(after: index)
    }
    index = text.index(after: index)
  }

  if index == text.endIndex && currentLine >= preferredLine {
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
    swiftmutGenericConditionSourceMutated(
      match.sourceOriginal,
      mutation: mutation,
      config: config))
}

func swiftmutFunctionBodyContainsExplicitCondition(
  path: String,
  preferredLine: Int,
  config: SwiftmutConfig
) -> Bool {
  guard preferredLine > 0,
        let text = swiftmutRead(path) else {
    return false
  }

  var currentLine = 1
  var lineStart = text.startIndex
  var index = text.startIndex
  var braceDepth = 0
  var sawOpeningBrace = false

  func inspectLine(_ lineText: String, line: Int) -> Bool {
    guard line >= preferredLine,
          line <= preferredLine + 120 else {
      return false
    }
    return swiftmutGenericConditionExpression(lineText) != nil
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
        if inspectLine(lineText, line: currentLine) {
          return true
        }
        updateBraceDepth(lineText)
        if sawOpeningBrace && braceDepth <= 0 {
          return false
        }
        if currentLine >= preferredLine + 120 {
          return false
        }
      }
      currentLine += 1
      lineStart = text.index(after: index)
    }
    index = text.index(after: index)
  }

  if index == text.endIndex && currentLine >= preferredLine {
    return inspectLine(String(text[lineStart..<text.endIndex]), line: currentLine)
  }
  return false
}
