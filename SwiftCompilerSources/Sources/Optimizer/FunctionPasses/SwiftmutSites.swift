// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for Swift project authors

import SIL

struct SwiftmutCandidate {
  let id: String
  let module: String
  let function: String
  let file: String
  let line: Int
  let column: Int
  let mutation: SwiftmutMutation

  var jsonLine: String {
    var fields: [String] = []
    fields.append(#""id":"\#(swiftmutEscapeJSON(id))""#)
    fields.append(#""mutator":"\#(swiftmutEscapeJSON(mutation.mutator))""#)
    fields.append(#""module":"\#(swiftmutEscapeJSON(module))""#)
    fields.append(#""function":"\#(swiftmutEscapeJSON(function))""#)
    fields.append(#""file":"\#(swiftmutEscapeJSON(file))""#)
    fields.append(#""line":\#(line)"#)
    fields.append(#""column":\#(column)"#)
    fields.append(#""sourceOriginal":"\#(swiftmutEscapeJSON(mutation.sourceOriginal))""#)
    fields.append(#""sourceMutated":"\#(swiftmutEscapeJSON(mutation.sourceMutated))""#)
    fields.append(#""silOriginal":"\#(swiftmutEscapeJSON(mutation.silOriginal))""#)
    fields.append(#""silMutated":"\#(swiftmutEscapeJSON(mutation.silMutated))""#)
    return "{\(fields.joined(separator: ","))}\n"
  }
}

struct SwiftmutConditionAlternative {
  let mutantID: String
  let alternativeIndex: UInt32
  let mutation: SwiftmutMutation
}

struct SwiftmutConditionSite {
  let siteID: UInt64
  let runtimeFunctionName: String
  let module: String
  let function: String
  let file: String
  let line: Int
  let column: Int
  let comparison: BuiltinInst?
  let branch: CondBranchInst
  let alternatives: [SwiftmutConditionAlternative]
}

struct SwiftmutConditionDiscoveryStats {
  var branches = 0
  var branchesWithArguments = 0
  var comparisonBranches = 0
  var genericBranches = 0
  var noMutationBranches = 0
  var mutationAlternatives = 0
  var sourceLocationMisses = 0
  var genericNonExplicitSourceLocations = 0
}

struct SwiftmutConditionDiscoveryResult {
  let sites: [SwiftmutConditionSite]
  let stats: SwiftmutConditionDiscoveryStats
}

struct SwiftmutReturnAlternative {
  let mutantID: String
  let alternativeIndex: UInt32
  let mutation: SwiftmutMutation
}

struct SwiftmutArithmeticAlternative {
  let mutantID: String
  let alternativeIndex: UInt32
  let mutation: SwiftmutMutation
}

struct SwiftmutScalarValueAlternative {
  let mutantID: String
  let alternativeIndex: UInt32
  let mutation: SwiftmutMutation
}

struct SwiftmutValueApplyAlternative {
  let mutantID: String
  let alternativeIndex: UInt32
  let mutation: SwiftmutMutation
}

struct SwiftmutAssignmentValueAlternative {
  let mutantID: String
  let alternativeIndex: UInt32
  let mutation: SwiftmutMutation
}

struct SwiftmutVoidCallAlternative {
  let mutantID: String
  let alternativeIndex: UInt32
  let mutation: SwiftmutMutation
}

struct SwiftmutReturnSite {
  let siteID: UInt64
  let runtimeFunctionName: String
  let module: String
  let function: String
  let file: String
  let line: Int
  let column: Int
  let returnInst: ReturnInst
  let alternatives: [SwiftmutReturnAlternative]
}

struct SwiftmutReturnBranchSite {
  let siteID: UInt64
  let runtimeFunctionName: String
  let module: String
  let function: String
  let file: String
  let line: Int
  let column: Int
  let branch: BranchInst
  let value: Value
  let alternatives: [SwiftmutReturnAlternative]
}

struct SwiftmutReturnDiscoveryStats {
  var terminators = 0
  var boolTerminators = 0
  var optionalTerminators = 0
  var integerTerminators = 0
  var stringTerminators = 0
  var collectionTerminators = 0
  var otherTerminators = 0
  var mutationEligibleTerminators = 0
  var mutationAlternatives = 0
  var missingSourceLocations = 0
  var missingBoolSourceLocations = 0
  var missingOptionalSourceLocations = 0
  var missingIntegerSourceLocations = 0
  var missingStringSourceLocations = 0
  var missingCollectionSourceLocations = 0
  var missingOtherSourceLocations = 0
  var missingSourceLocationSamples = 0
  var nonStatementSourceLocations = 0
}

struct SwiftmutReturnDiscoveryResult {
  let sites: [SwiftmutReturnSite]
  let stats: SwiftmutReturnDiscoveryStats
}

struct SwiftmutReturnBranchDiscoveryStats {
  var branches = 0
  var mutationEligibleBranches = 0
  var mutationAlternatives = 0
  var sourceLocationMisses = 0
}

struct SwiftmutReturnBranchDiscoveryResult {
  let sites: [SwiftmutReturnBranchSite]
  let stats: SwiftmutReturnBranchDiscoveryStats
}

struct SwiftmutArithmeticSite {
  let siteID: UInt64
  let runtimeFunctionName: String
  let module: String
  let function: String
  let file: String
  let line: Int
  let column: Int
  let builtin: BuiltinInst
  let alternatives: [SwiftmutArithmeticAlternative]
}

struct SwiftmutScalarValueSite {
  let siteID: UInt64
  let runtimeFunctionName: String
  let module: String
  let function: String
  let file: String
  let line: Int
  let column: Int
  let value: StructInst
  let alternatives: [SwiftmutScalarValueAlternative]
}

struct SwiftmutScalarValueDiscoveryStats {
  var structInstructions = 0
  var mutationEligibleStructInstructions = 0
  var mutationAlternatives = 0
  var sourceLocationMisses = 0
  var sourceLocationMissSamples = 0
}

struct SwiftmutScalarValueDiscoveryResult {
  let sites: [SwiftmutScalarValueSite]
  let stats: SwiftmutScalarValueDiscoveryStats
}

struct SwiftmutValueApplySite {
  let siteID: UInt64
  let runtimeFunctionName: String
  let module: String
  let function: String
  let file: String
  let line: Int
  let column: Int
  let apply: ApplyInst
  let alternatives: [SwiftmutValueApplyAlternative]
}

struct SwiftmutValueApplyDiscoveryStats {
  var applyInstructions = 0
  var valueApplyInstructions = 0
  var mutationEligibleApplyInstructions = 0
  var mutationAlternatives = 0
  var sourceLocationMisses = 0
  var sourceLocationMissSamples = 0
}

struct SwiftmutValueApplyDiscoveryResult {
  let sites: [SwiftmutValueApplySite]
  let stats: SwiftmutValueApplyDiscoveryStats
}

struct SwiftmutAssignmentValueSite {
  let siteID: UInt64
  let runtimeFunctionName: String
  let module: String
  let function: String
  let file: String
  let line: Int
  let column: Int
  let store: StoreInst
  let alternatives: [SwiftmutAssignmentValueAlternative]
}

struct SwiftmutAssignmentValueDiscoveryStats {
  var storeInstructions = 0
  var mutationEligibleStoreInstructions = 0
  var mutationAlternatives = 0
  var sourceLocationMisses = 0
  var sourceLocationMissSamples = 0
}

struct SwiftmutAssignmentValueDiscoveryResult {
  let sites: [SwiftmutAssignmentValueSite]
  let stats: SwiftmutAssignmentValueDiscoveryStats
}

struct SwiftmutVoidCallSite {
  let siteID: UInt64
  let runtimeFunctionName: String
  let module: String
  let function: String
  let file: String
  let line: Int
  let column: Int
  let apply: ApplyInst
  let alternatives: [SwiftmutVoidCallAlternative]
}

struct SwiftmutVoidCallDiscoveryStats {
  var applyInstructions = 0
  var voidApplyInstructions = 0
  var mutationEligibleApplyInstructions = 0
  var sourceLocationMisses = 0
  var nonStatementSourceLocations = 0
}

struct SwiftmutVoidCallDiscoveryResult {
  let sites: [SwiftmutVoidCallSite]
  let stats: SwiftmutVoidCallDiscoveryStats
}

enum SwiftmutVoidCallSourceLocationResult {
  case found(file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)
  case nonStatement
  case missing
}
