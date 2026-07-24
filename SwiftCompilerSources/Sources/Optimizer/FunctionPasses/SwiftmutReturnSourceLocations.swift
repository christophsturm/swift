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
  let functionName = returnInst.parentFunction.name.string

  func usableReturnSourceLocation(
    _ location: (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String),
    path: String
  ) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
    guard swiftmutSourceLineBelongsToFunction(
      location.line,
      path: path,
      function: returnInst.parentFunction,
      config: config
    ) else {
      return nil
    }
    if swiftmutReturnSourceLocationIsUsableForFunction(
      location,
      functionName: functionName,
      path: path,
      mutation: mutation,
      config: config
    ) {
      return location
    }
    return nil
  }

  func computedPropertyReturnSourceLocation(
    path: String
  ) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
    swiftmutFindComputedPropertyReturnSourceLocation(
      functionName: functionName,
      path: path,
      mutation: mutation,
      config: config
    )
  }

  if let fileNameAndPosition = returnInst.location.fileNameAndPosition {
    let path = fileNameAndPosition.path.string
    if let matchedPath = swiftmutIncludedSourcePath(path, config: config) {
      if let anchored = computedPropertyReturnSourceLocation(path: matchedPath) {
        return anchored
      }
      if let anchored = swiftmutFindPropertyGetterReturnSourceLocation(
        functionName: functionName,
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        mutation: mutation,
        config: config
      ), let usable = usableReturnSourceLocation(anchored, path: matchedPath) {
        return usable
      }
      if let anchored = swiftmutFindUniqueExplicitReturnValueExpressionSourceLocation(
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        mutation: mutation,
        config: config
      ), let usable = usableReturnSourceLocation(anchored, path: matchedPath) {
        return usable
      }
      let candidate = (
        swiftmutTrimPackageRoot(matchedPath, config: config),
        fileNameAndPosition.line,
        fileNameAndPosition.column,
        mutation.sourceOriginal,
        mutation.sourceMutated)
      if swiftmutReturnSourceLocationCandidateIsUsable(
        candidate,
        functionName: functionName,
        path: matchedPath,
        mutation: mutation,
        config: config
      ) {
        return candidate
      }
      if let anchored = swiftmutFindClosureArgumentReturnSourceLocation(
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        mutation: mutation,
        config: config
      ), let usable = usableReturnSourceLocation(anchored, path: matchedPath) {
        return usable
      }
      if let anchored = swiftmutFindDescribedExplicitReturnSourceLocation(
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        locationDescription: returnInst.location.description,
        mutation: mutation,
        config: config
      ), let usable = usableReturnSourceLocation(anchored, path: matchedPath) {
        return usable
      }
      if let anchored = swiftmutFindUniqueExplicitReturnSourceLocation(
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        mutation: mutation,
        config: config
      ), let usable = usableReturnSourceLocation(anchored, path: matchedPath) {
        return usable
      }
      if let anchored = swiftmutFindNearestPriorExplicitReturnSourceLocation(
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        mutation: mutation,
        config: config
      ), let usable = usableReturnSourceLocation(anchored, path: matchedPath) {
        return usable
      }
      if let anchored = swiftmutFindNearestPriorImplicitReturnSourceLocation(
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        mutation: mutation,
        config: config
      ), let usable = usableReturnSourceLocation(anchored, path: matchedPath) {
        return usable
      }
      if let anchored = swiftmutFindUniqueImplicitReturnSourceLocation(
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        mutation: mutation,
        config: config
      ), let usable = usableReturnSourceLocation(anchored, path: matchedPath) {
        return usable
      }
      if let anchored = swiftmutFindPropertyGetterReturnSourceLocation(
        functionName: functionName,
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        mutation: mutation,
        config: config
      ), let usable = usableReturnSourceLocation(anchored, path: matchedPath) {
        return usable
      }
    }
  }

  if let definingInstruction = returnInst.returnedValue.definingInstruction,
     let fileNameAndPosition = definingInstruction.location.fileNameAndPosition {
    let path = fileNameAndPosition.path.string
    if let matchedPath = swiftmutIncludedSourcePath(path, config: config) {
      if let anchored = computedPropertyReturnSourceLocation(path: matchedPath) {
        return anchored
      }
      if let anchored = swiftmutFindPropertyGetterReturnSourceLocation(
        functionName: functionName,
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        mutation: mutation,
        config: config
      ), let usable = usableReturnSourceLocation(anchored, path: matchedPath) {
        return usable
      }
      if let anchored = swiftmutFindUniqueExplicitReturnValueExpressionSourceLocation(
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        mutation: mutation,
        config: config
      ), let usable = usableReturnSourceLocation(anchored, path: matchedPath) {
        return usable
      }
      let candidate = (
        swiftmutTrimPackageRoot(matchedPath, config: config),
        fileNameAndPosition.line,
        fileNameAndPosition.column,
        mutation.sourceOriginal,
        mutation.sourceMutated)
      if swiftmutReturnSourceLocationCandidateIsUsable(
        candidate,
        functionName: functionName,
        path: matchedPath,
        mutation: mutation,
        config: config
      ) {
        return candidate
      }
      if let anchored = swiftmutFindClosureArgumentReturnSourceLocation(
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        mutation: mutation,
        config: config
      ), let usable = usableReturnSourceLocation(anchored, path: matchedPath) {
        return usable
      }
      if let anchored = swiftmutFindDescribedExplicitReturnSourceLocation(
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        locationDescription: returnInst.location.description,
        mutation: mutation,
        config: config
      ), let usable = usableReturnSourceLocation(anchored, path: matchedPath) {
        return usable
      }
      if let anchored = swiftmutFindUniqueExplicitReturnSourceLocation(
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        mutation: mutation,
        config: config
      ), let usable = usableReturnSourceLocation(anchored, path: matchedPath) {
        return usable
      }
      if let anchored = swiftmutFindNearestPriorExplicitReturnSourceLocation(
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        mutation: mutation,
        config: config
      ), let usable = usableReturnSourceLocation(anchored, path: matchedPath) {
        return usable
      }
      if let anchored = swiftmutFindNearestPriorImplicitReturnSourceLocation(
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        mutation: mutation,
        config: config
      ), let usable = usableReturnSourceLocation(anchored, path: matchedPath) {
        return usable
      }
      if let anchored = swiftmutFindUniqueImplicitReturnSourceLocation(
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        mutation: mutation,
        config: config
      ), let usable = usableReturnSourceLocation(anchored, path: matchedPath) {
        return usable
      }
      if let anchored = swiftmutFindPropertyGetterReturnSourceLocation(
        functionName: functionName,
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        mutation: mutation,
        config: config
      ), let usable = usableReturnSourceLocation(anchored, path: matchedPath) {
        return usable
      }
    }
  }

  if let anchored = swiftmutFindDescribedStoredPropertyInitializerReturnSourceLocation(
    functionName: functionName,
    locationDescription: returnInst.location.description,
    mutation: mutation,
    config: config
  ) {
    return anchored
  }
  if let definingInstruction = returnInst.returnedValue.definingInstruction,
     let anchored = swiftmutFindDescribedStoredPropertyInitializerReturnSourceLocation(
       functionName: functionName,
       locationDescription: definingInstruction.location.description,
       mutation: mutation,
       config: config
     ) {
    return anchored
  }
  if let anchored = swiftmutFindDescribedStoredPropertyInitializerReturnSourceLocation(
    functionName: functionName,
    locationDescription: returnInst.parentFunction.location.description,
    mutation: mutation,
    config: config
  ) {
    return anchored
  }

  if let anchored = swiftmutFindDescribedDefaultArgumentReturnSourceLocation(
    functionName: functionName,
    locationDescription: returnInst.location.description,
    mutation: mutation,
    config: config
  ) {
    return anchored
  }
  if let definingInstruction = returnInst.returnedValue.definingInstruction,
     let anchored = swiftmutFindDescribedDefaultArgumentReturnSourceLocation(
       functionName: functionName,
       locationDescription: definingInstruction.location.description,
       mutation: mutation,
       config: config
     ) {
    return anchored
  }
  if swiftmutFunctionNameLooksDefaultArgumentThunk(functionName),
     let anchored = swiftmutFindDescribedDefaultArgumentReturnSourceLocation(
       functionName: functionName,
       locationDescription: returnInst.parentFunction.location.description,
       mutation: mutation,
       config: config
     ) {
    return anchored
  }
  if let anchored = swiftmutFindOrdinalDefaultArgumentReturnSourceLocation(
    functionName: functionName,
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
    if let anchored = computedPropertyReturnSourceLocation(path: path) {
      return anchored
    }
    if let anchored = swiftmutFindPropertyGetterReturnSourceLocation(
      functionName: functionName,
      path: path,
      preferredLine: line,
      mutation: mutation,
      config: config
    ), let usable = usableReturnSourceLocation(anchored, path: path) {
      return usable
    }
    if let anchored = swiftmutFindUniqueExplicitReturnValueExpressionSourceLocation(
      path: path,
      preferredLine: line,
      mutation: mutation,
      config: config
    ), let usable = usableReturnSourceLocation(anchored, path: path) {
      return usable
    }
    let candidate = (
      swiftmutTrimPackageRoot(path, config: config),
      line,
      1,
      mutation.sourceOriginal,
      mutation.sourceMutated)
    if swiftmutReturnSourceLocationCandidateIsUsable(
      candidate,
      functionName: functionName,
      path: path,
      mutation: mutation,
      config: config
    ) {
      return candidate
    }
    if let anchored = swiftmutFindClosureArgumentReturnSourceLocation(
      path: path,
      preferredLine: line,
      mutation: mutation,
      config: config
    ), let usable = usableReturnSourceLocation(anchored, path: path) {
      return usable
    }
    if let anchored = swiftmutFindDescribedExplicitReturnSourceLocation(
      path: path,
      preferredLine: line,
      locationDescription: returnLocation,
      mutation: mutation,
      config: config
    ), let usable = usableReturnSourceLocation(anchored, path: path) {
      return usable
    }
    if let anchored = swiftmutFindUniqueExplicitReturnSourceLocation(
      path: path,
      preferredLine: line,
      mutation: mutation,
      config: config
    ), let usable = usableReturnSourceLocation(anchored, path: path) {
      return usable
    }
    if let anchored = swiftmutFindNearestPriorExplicitReturnSourceLocation(
      path: path,
      preferredLine: line,
      mutation: mutation,
      config: config
    ), let usable = usableReturnSourceLocation(anchored, path: path) {
      return usable
    }
    if let anchored = swiftmutFindNearestPriorImplicitReturnSourceLocation(
      path: path,
      preferredLine: line,
      mutation: mutation,
      config: config
    ), let usable = usableReturnSourceLocation(anchored, path: path) {
      return usable
    }
    if let anchored = swiftmutFindUniqueImplicitReturnSourceLocation(
      path: path,
      preferredLine: line,
      mutation: mutation,
      config: config
    ), let usable = usableReturnSourceLocation(anchored, path: path) {
      return usable
    }
    if let anchored = swiftmutFindMultilineImplicitReturnSourceLocation(
      path: path,
      functionLine: line,
      mutation: mutation,
      config: config
    ), let usable = usableReturnSourceLocation(anchored, path: path) {
      return usable
    }
    if let anchored = swiftmutFindPropertyGetterReturnSourceLocation(
      functionName: functionName,
      path: path,
      preferredLine: line,
      mutation: mutation,
      config: config
    ), let usable = usableReturnSourceLocation(anchored, path: path) {
      return usable
    }
  }

  let location = returnInst.parentFunction.location.description
  for path in swiftmutSwiftSourcePaths(config: config) {
    guard location.contains(path),
          let line = swiftmutPreferredLine(in: location, path: path) else {
      continue
    }
    if let anchored = computedPropertyReturnSourceLocation(path: path) {
      return anchored
    }
    if let anchored = swiftmutFindPropertyGetterReturnSourceLocation(
      functionName: functionName,
      path: path,
      preferredLine: line,
      mutation: mutation,
      config: config
    ), let usable = usableReturnSourceLocation(anchored, path: path) {
      return usable
    }
    if let anchored = swiftmutFindUniqueExplicitReturnValueExpressionSourceLocation(
      path: path,
      preferredLine: line,
      mutation: mutation,
      config: config
    ), let usable = usableReturnSourceLocation(anchored, path: path) {
      return usable
    }
    let candidate = (
      swiftmutTrimPackageRoot(path, config: config),
      line,
      1,
      mutation.sourceOriginal,
      mutation.sourceMutated)
    if swiftmutReturnSourceLocationCandidateIsUsable(
      candidate,
      functionName: functionName,
      path: path,
      mutation: mutation,
      config: config
    ) {
      return candidate
    }
    if let anchored = swiftmutFindClosureArgumentReturnSourceLocation(
      path: path,
      preferredLine: line,
      mutation: mutation,
      config: config
    ), let usable = usableReturnSourceLocation(anchored, path: path) {
      return usable
    }
    if let anchored = swiftmutFindDescribedExplicitReturnSourceLocation(
      path: path,
      preferredLine: line,
      locationDescription: returnInst.location.description,
      mutation: mutation,
      config: config
    ), let usable = usableReturnSourceLocation(anchored, path: path) {
      return usable
    }
    if let anchored = swiftmutFindUniqueExplicitReturnSourceLocation(
      path: path,
      preferredLine: line,
      mutation: mutation,
      config: config
    ), let usable = usableReturnSourceLocation(anchored, path: path) {
      return usable
    }
    if let anchored = swiftmutFindTrailingExplicitReturnSourceLocation(
      path: path,
      functionLine: line,
      mutation: mutation,
      config: config
    ), let usable = usableReturnSourceLocation(anchored, path: path) {
      return usable
    }
    if let anchored = swiftmutFindUniqueImplicitReturnSourceLocation(
      path: path,
      preferredLine: line,
      mutation: mutation,
      config: config
    ), let usable = usableReturnSourceLocation(anchored, path: path) {
      return usable
    }
    if let anchored = swiftmutFindMultilineImplicitReturnSourceLocation(
      path: path,
      functionLine: line,
      mutation: mutation,
      config: config
    ), let usable = usableReturnSourceLocation(anchored, path: path) {
      return usable
    }
    if let anchored = swiftmutFindPropertyGetterReturnSourceLocation(
      functionName: functionName,
      path: path,
      preferredLine: line,
      mutation: mutation,
      config: config
    ), let usable = usableReturnSourceLocation(anchored, path: path) {
      return usable
    }
  }
  return nil
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

  func usableScalarSourceLocation(
    _ location: (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String),
    path: String
  ) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
    if swiftmutSourceLineBelongsToFunction(
      location.line,
      path: path,
      function: value.parentFunction,
      config: config
    ) {
      return location
    }
    return nil
  }

  if let fileNameAndPosition = value.location.fileNameAndPosition {
    let path = fileNameAndPosition.path.string
    if let matchedPath = swiftmutIncludedSourcePath(path, config: config) {
      if let returned = swiftmutFindReturnedScalarValueSourceLocation(
        for: value,
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        mutation: mutation,
        config: config
      ), let usable = usableScalarSourceLocation(returned, path: matchedPath) {
        return usable
      }
      if let anchored = swiftmutFindClosureArgumentReturnSourceLocation(
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        mutation: mutation,
        config: config
      ), let usable = usableScalarSourceLocation(anchored, path: matchedPath) {
        return usable
      }
      if let anchored = swiftmutFindDescribedScalarLiteralSourceLocation(
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        locationDescription: value.location.description,
        mutation: mutation,
        config: config
      ), let usable = usableScalarSourceLocation(anchored, path: matchedPath) {
        return usable
      }
      if let anchored = swiftmutFindScalarLiteralSourceLocation(
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        preferredColumn: fileNameAndPosition.column,
        mutation: mutation,
        config: config
      ), let usable = usableScalarSourceLocation(anchored, path: matchedPath) {
        return usable
      }
      if let anchored = swiftmutFindOrdinalScalarValueSourceLocation(
        for: value,
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        mutation: mutation,
        config: config
      ), let usable = usableScalarSourceLocation(anchored, path: matchedPath) {
        return usable
      }
    }
  }

  if let functionSourceLocation {
    if let anchored = swiftmutFindReturnedScalarValueSourceLocation(
      for: value,
      path: functionSourceLocation.path,
      preferredLine: functionSourceLocation.line,
      mutation: mutation,
      config: config
    ), let usable = usableScalarSourceLocation(anchored, path: functionSourceLocation.path) {
      return usable
    }
    if let anchored = swiftmutFindClosureArgumentReturnSourceLocation(
      path: functionSourceLocation.path,
      preferredLine: functionSourceLocation.line,
      mutation: mutation,
      config: config
    ), let usable = usableScalarSourceLocation(anchored, path: functionSourceLocation.path) {
      return usable
    }
    if let anchored = swiftmutFindDescribedScalarLiteralSourceLocation(
      path: functionSourceLocation.path,
      preferredLine: functionSourceLocation.line,
      locationDescription: value.location.description,
      mutation: mutation,
      config: config
    ), let usable = usableScalarSourceLocation(anchored, path: functionSourceLocation.path) {
      return usable
    }
    if let anchored = swiftmutFindScalarLiteralSourceLocation(
      path: functionSourceLocation.path,
      preferredLine: functionSourceLocation.line,
      preferredColumn: 1,
      mutation: mutation,
      config: config
    ), let usable = usableScalarSourceLocation(anchored, path: functionSourceLocation.path) {
      return usable
    }
    if let anchored = swiftmutFindOrdinalScalarValueSourceLocation(
      for: value,
      path: functionSourceLocation.path,
      preferredLine: functionSourceLocation.line,
      mutation: mutation,
      config: config
    ), let usable = usableScalarSourceLocation(anchored, path: functionSourceLocation.path) {
      return usable
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
    config: config,
    requiresMultipleMatches: false,
    requiresDirectValueExpression: true
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
