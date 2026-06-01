//===--- SwiftmutValueApplySourceLocations.swift -------------------------===//
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
         let anchored = swiftmutFindOperatorValueApplySourceLocation(
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
    if let anchored = swiftmutFindOperatorValueApplySourceLocation(
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
