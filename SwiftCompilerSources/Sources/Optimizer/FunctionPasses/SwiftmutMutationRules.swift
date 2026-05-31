//===--- SwiftmutMutationRules.swift ----------------------------------------------===//
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

func swiftmutSourceLocationMatchesSite(
  _ candidate: (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String),
  _ site: (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)
) -> Bool {
  candidate.file == site.file
    && candidate.line == site.line
    && candidate.column == site.column
    && candidate.sourceOriginal == site.sourceOriginal
}

func swiftmutMetamutantReturnMutations(
  for returnInst: ReturnInst,
  config: SwiftmutConfig
) -> [SwiftmutMutation] {
  swiftmutReturnMutations(for: returnInst, config: config).filter { mutation in
    switch mutation.mutatedBuiltinName {
    case "return_false", "return_true", "return_nil", "return_zero", "return_empty_string",
         "return_empty_array", "return_empty_dictionary", "return_empty_set":
      return true
    default:
      return false
    }
  }
}

func swiftmutScalarValueMutations(
  for structInst: StructInst,
  config: SwiftmutConfig
) -> [SwiftmutMutation] {
  let valueType = structInst.type
  var mutations: [SwiftmutMutation] = []

  if swiftmutIsBoolType(valueType, in: structInst.parentFunction) {
    let literal = swiftmutBoolLiteralValue(structInst)
    if literal != false,
       let rule = swiftmutFirstReturnRule(context: "boolToFalse", config: config) {
      mutations.append(swiftmutReturnMutation(rule, silOriginal: valueType.description))
    }
    if literal != true,
       let rule = swiftmutFirstReturnRule(context: "boolToTrue", config: config) {
      mutations.append(swiftmutReturnMutation(rule, silOriginal: valueType.description))
    }
    return mutations
  }

  if swiftmutIsIntegerStructType(valueType, in: structInst.parentFunction),
     swiftmutIntegerStructLiteralValue(structInst) != 0,
     let rule = swiftmutFirstReturnRule(context: "integerToZero", config: config) {
    mutations.append(swiftmutReturnMutation(rule, silOriginal: valueType.description))
  }

  return mutations
}

func swiftmutValueReplacementMutations(
  for apply: ApplyInst,
  valueType: Type,
  config: SwiftmutConfig
) -> [SwiftmutMutation] {
  swiftmutValueReplacementMutations(
    valueType: valueType,
    function: apply.parentFunction,
    config: config
  )
}

func swiftmutReturnBranchMutations(
  for branch: BranchInst,
  config: SwiftmutConfig
) -> [SwiftmutMutation] {
  guard swiftmutBranchFeedsReturnValue(branch),
        let value = branch.operands.first?.value,
        value.type.isTrivial(in: branch.parentFunction) else {
    return []
  }
  if let structInst = value.definingInstruction as? StructInst,
     !swiftmutScalarValueMutations(for: structInst, config: config).isEmpty {
    return []
  }
  return swiftmutValueReplacementMutations(
    valueType: value.type,
    function: branch.parentFunction,
    config: config
  )
}

func swiftmutAssignmentValueMutations(
  for store: StoreInst,
  config: SwiftmutConfig
) -> [SwiftmutMutation] {
  guard swiftmutCanDispatchAssignmentValue(store) else {
    return []
  }
  return swiftmutValueReplacementMutations(
    valueType: store.source.type,
    function: store.parentFunction,
    config: config
  ).filter { mutation in
    swiftmutAssignmentMutationChangesConcreteValue(mutation, source: store.source)
  }
}

func swiftmutAssignmentMutationChangesConcreteValue(
  _ mutation: SwiftmutMutation,
  source: Value
) -> Bool {
  switch mutation.mutatedBuiltinName {
  case "return_false":
    return swiftmutBoolLiteralValue(source) != false
  case "return_true":
    return swiftmutBoolLiteralValue(source) != true
  case "return_nil":
    return !swiftmutIsOptionalNone(source)
  case "return_zero":
    return swiftmutIntegerStructLiteralValue(source) != 0
  default:
    return true
  }
}

func swiftmutCanDispatchAssignmentValue(_ store: StoreInst) -> Bool {
  store.source.type.isTrivial(in: store.parentFunction) || store.source.ownership == .owned
}

func swiftmutAssignmentStoreIsEligible(_ store: StoreInst, config: SwiftmutConfig) -> Bool {
  guard !store.source.type.isAddress else {
    return false
  }
  let destinationNames = swiftmutAssignmentDestinationNames(for: store)
  let sourceNames = swiftmutAssignmentSourceNames(for: store)
  if swiftmutIsSynthesizedCollectionStorageAssignment(
    destinationNames: destinationNames,
    sourceNames: sourceNames
  ) {
    return false
  }
  let storeLocation = store.location.fileNameAndPosition
  let sourceLocation = store.source.definingInstruction?.location.fileNameAndPosition
  let storeIsSourceAnchored = storeLocation.map {
    $0.line > 0 && !$0.path.string.contains("<compiler-generated>")
  } ?? false
  let sourceIsSourceAnchored = sourceLocation.map {
    $0.line > 0 && !$0.path.string.contains("<compiler-generated>")
  } ?? false
  if destinationNames.isEmpty, !storeIsSourceAnchored, !sourceIsSourceAnchored {
    return false
  }
  if !storeIsSourceAnchored,
     !sourceIsSourceAnchored,
     swiftmutIsSynthesizedStorageAssignment(
       destinationNames: destinationNames,
       sourceNames: sourceNames
     ) {
    return false
  }
  if destinationNames.isEmpty, sourceNames.isEmpty {
    guard let storeLocation else {
      return false
    }
    if storeLocation.line <= 0 || storeLocation.path.string.contains("<compiler-generated>") {
      return false
    }
  }
  guard let definingInstruction = store.source.definingInstruction else {
    return true
  }
  switch definingInstruction {
  case is BuiltinInst:
    return false
  case let structInst as StructInst:
    return !swiftmutScalarValueHasMappedSource(structInst, config: config)
  case let apply as ApplyInst:
    return !swiftmutValueApplyHasMappedSource(apply, config: config)
  default:
    return true
  }
}

private func swiftmutIsSynthesizedCollectionStorageAssignment(
  destinationNames: [String],
  sourceNames: [String]
) -> Bool {
  let names = Set(destinationNames + sourceNames)
  return names.contains("_storage") && names.contains("countAndCapacity")
}

private func swiftmutIsSynthesizedStorageAssignment(
  destinationNames: [String],
  sourceNames: [String]
) -> Bool {
  let names = destinationNames + sourceNames
  return !names.isEmpty && names.allSatisfy { $0.hasPrefix("_") || $0 == "countAndCapacity" }
}

func swiftmutScalarValueHasMappedSource(_ value: StructInst, config: SwiftmutConfig) -> Bool {
  for mutation in swiftmutScalarValueMutations(for: value, config: config) {
    if swiftmutScalarValueSourceLocation(for: value, mutation: mutation, config: config) != nil {
      return true
    }
  }
  return false
}

func swiftmutValueApplyHasMappedSource(_ apply: ApplyInst, config: SwiftmutConfig) -> Bool {
  for mutation in swiftmutValueReplacementMutations(
    for: apply,
    valueType: apply.type,
    config: config
  ) {
    if swiftmutValueApplySourceLocation(for: apply, mutation: mutation, config: config) != nil {
      return true
    }
  }
  return false
}

func swiftmutValueReplacementMutations(
  valueType: Type,
  function: Function,
  config: SwiftmutConfig
) -> [SwiftmutMutation] {
  var mutations: [SwiftmutMutation] = []

  if swiftmutIsBoolType(valueType, in: function) {
    if let rule = swiftmutFirstReturnRule(context: "boolToFalse", config: config) {
      mutations.append(swiftmutReturnMutation(rule, silOriginal: valueType.description))
    }
    if let rule = swiftmutFirstReturnRule(context: "boolToTrue", config: config) {
      mutations.append(swiftmutReturnMutation(rule, silOriginal: valueType.description))
    }
    return mutations
  }

  if valueType.isOptional,
     let rule = swiftmutFirstReturnRule(context: "optionalToNil", config: config) {
    mutations.append(swiftmutReturnMutation(rule, silOriginal: valueType.description))
    return mutations
  }

  if swiftmutIsIntegerStructType(valueType, in: function),
     let rule = swiftmutFirstReturnRule(context: "integerToZero", config: config) {
    mutations.append(swiftmutReturnMutation(rule, silOriginal: valueType.description))
  }

  if swiftmutIsStringType(valueType),
     let rule = swiftmutFirstReturnRule(context: "stringToEmpty", config: config) {
    mutations.append(swiftmutReturnMutation(rule, silOriginal: valueType.description))
  }

  if swiftmutIsCollectionType(valueType, named: "Array"),
     let rule = swiftmutFirstReturnRule(context: "arrayToEmpty", config: config) {
    mutations.append(swiftmutReturnMutation(rule, silOriginal: valueType.description))
  }

  if swiftmutIsCollectionType(valueType, named: "Dictionary"),
     let rule = swiftmutFirstReturnRule(context: "dictionaryToEmpty", config: config) {
    mutations.append(swiftmutReturnMutation(rule, silOriginal: valueType.description))
  }

  if swiftmutIsCollectionType(valueType, named: "Set"),
     let rule = swiftmutFirstReturnRule(context: "setToEmpty", config: config) {
    mutations.append(swiftmutReturnMutation(rule, silOriginal: valueType.description))
  }

  return mutations
}

func swiftmutConditionBranchCount(in function: Function) -> Int {
  var count = 0
  for block in function.blocks {
    if block.terminator is CondBranchInst {
      count += 1
    }
  }
  return count
}

func swiftmutConditionSiteMutations(
  for builtin: BuiltinInst,
  config: SwiftmutConfig
) -> [SwiftmutMutation] {
  swiftmutConditionMutations(for: builtin, config: config, includeGenericComparisonRules: true)
}

func swiftmutGenericConditionSiteMutations(
  config: SwiftmutConfig
) -> [SwiftmutMutation] {
  var mutations: [SwiftmutMutation] = []
  for rule in config.conditionMutationRules where rule.builtinID == "COMPARISON" {
    guard swiftmutMutatorIsEnabled(rule.mutator, config: config) else {
      continue
    }
    mutations.append(SwiftmutMutation(
      originalID: nil,
      mutator: rule.mutator,
      mutatedBuiltinName: rule.mutatedBuiltinName,
      sourceOriginal: rule.sourceOriginal,
      sourceMutated: rule.sourceMutated,
      silOriginal: "condition",
      silMutated: rule.mutatedBuiltinName))
  }
  return mutations
}

func swiftmutConditionMutations(
  for builtin: BuiltinInst,
  config: SwiftmutConfig,
  includeGenericComparisonRules: Bool
) -> [SwiftmutMutation] {
  guard let builtinID = swiftmutComparisonBuiltinIDName(builtin) else {
    return []
  }

  var mutations: [SwiftmutMutation] = []
  for rule in config.conditionMutationRules {
    let appliesToBuiltin = rule.builtinID == builtinID
      || (includeGenericComparisonRules && rule.builtinID == "COMPARISON")
    guard appliesToBuiltin, swiftmutMutatorIsEnabled(rule.mutator, config: config) else {
      continue
    }
    mutations.append(SwiftmutMutation(
      originalID: builtin.id,
      mutator: rule.mutator,
      mutatedBuiltinName: rule.mutatedBuiltinName,
      sourceOriginal: rule.sourceOriginal,
      sourceMutated: rule.sourceMutated,
      silOriginal: builtin.name.string,
      silMutated: rule.mutatedBuiltinName))
  }
  return mutations
}

func swiftmutArithmeticSiteMutations(
  for builtin: BuiltinInst,
  config: SwiftmutConfig
) -> [SwiftmutMutation] {
  var mutations: [SwiftmutMutation] = []

  switch builtin.id {
  case .SAddOver:
    if let rule = swiftmutContextualArithmeticRule(for: builtin, builtinID: "SAddOver", config: config),
       swiftmutMutatorIsEnabled(rule.mutator, config: config) {
      mutations.append(swiftmutContextualArithmeticMutation(rule, for: builtin))
    }
  case .SSubOver:
    if let rule = swiftmutContextualArithmeticRule(for: builtin, builtinID: "SSubOver", config: config),
       swiftmutMutatorIsEnabled(rule.mutator, config: config) {
      mutations.append(swiftmutContextualArithmeticMutation(rule, for: builtin))
    }
  default:
    break
  }

  if let builtinID = swiftmutArithmeticBuiltinIDName(builtin) {
    for rule in config.arithmeticMutationRules where rule.builtinID == builtinID {
      guard swiftmutMutatorIsEnabled("MATH", config: config) else {
        continue
      }
      mutations.append(swiftmutBinaryMutation(
        builtin,
        mutator: "MATH",
        mutatedBuiltinName: rule.mutatedBuiltinName,
        sourceOriginal: rule.sourceOriginal,
        sourceMutated: rule.sourceMutated))
    }
  }

  return mutations
}

func swiftmutComparisonBuiltinIDName(_ builtin: BuiltinInst) -> String? {
  switch builtin.id {
  case .ICMP_EQ:
    return "ICMP_EQ"
  case .ICMP_NE:
    return "ICMP_NE"
  case .ICMP_SGE:
    return "ICMP_SGE"
  case .ICMP_SGT:
    return "ICMP_SGT"
  case .ICMP_SLE:
    return "ICMP_SLE"
  case .ICMP_SLT:
    return "ICMP_SLT"
  case .ICMP_UGE:
    return "ICMP_UGE"
  case .ICMP_UGT:
    return "ICMP_UGT"
  case .ICMP_ULE:
    return "ICMP_ULE"
  case .ICMP_ULT:
    return "ICMP_ULT"
  default:
    return nil
  }
}

func swiftmutIsComparisonBuiltin(_ builtin: BuiltinInst) -> Bool {
  switch builtin.id {
  case .ICMP_EQ, .ICMP_NE,
       .ICMP_SGE, .ICMP_SGT, .ICMP_SLE, .ICMP_SLT,
       .ICMP_UGE, .ICMP_UGT, .ICMP_ULE, .ICMP_ULT:
    return true
  default:
    return false
  }
}
