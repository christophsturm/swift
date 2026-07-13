//===--- SwiftmutMutationBuilders.swift ----------------------------------------------===//
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
import SwiftmutSupport

func swiftmutReturnMutations(
  for returnInst: ReturnInst,
  config: SwiftmutConfig
) -> [SwiftmutMutation] {
  let returnedValue = returnInst.returnedValue
  let returnType = returnedValue.type
  var mutations: [SwiftmutMutation] = []

  if swiftmutIsBoolType(returnType, in: returnInst.parentFunction) {
    let literal = swiftmutBoolLiteralValue(returnedValue)
    if literal != false,
       let rule = swiftmutFirstReturnRule(context: "boolToFalse", config: config) {
      mutations.append(swiftmutReturnMutation(rule, silOriginal: returnType.description))
    }
    if literal != true,
       let rule = swiftmutFirstReturnRule(context: "boolToTrue", config: config) {
      mutations.append(swiftmutReturnMutation(rule, silOriginal: returnType.description))
    }
    return mutations
  }

  if returnType.isOptional && !swiftmutIsOptionalNone(returnedValue) {
    if let rule = swiftmutFirstReturnRule(context: "optionalToNil", config: config) {
      mutations.append(swiftmutReturnMutation(rule, silOriginal: returnType.description))
    }
    return mutations
  }

  if swiftmutIsBuiltinIntegerBackedStructType(returnType, in: returnInst.parentFunction),
     swiftmutIntegerStructLiteralValue(returnedValue) != 0,
     let rule = swiftmutFirstReturnRule(context: "integerToZero", config: config) {
    mutations.append(swiftmutReturnMutation(rule, silOriginal: returnType.description))
  }

  if swiftmutIsStringType(returnType),
     let rule = swiftmutFirstReturnRule(context: "stringToEmpty", config: config) {
    mutations.append(swiftmutReturnMutation(rule, silOriginal: returnType.description))
  }

  if swiftmutIsCollectionType(returnType, named: "Array"),
     let rule = swiftmutFirstReturnRule(context: "arrayToEmpty", config: config) {
    mutations.append(swiftmutReturnMutation(rule, silOriginal: returnType.description))
  }

  if swiftmutIsCollectionType(returnType, named: "Dictionary"),
     let rule = swiftmutFirstReturnRule(context: "dictionaryToEmpty", config: config) {
    mutations.append(swiftmutReturnMutation(rule, silOriginal: returnType.description))
  }

  if swiftmutIsCollectionType(returnType, named: "Set"),
     let rule = swiftmutFirstReturnRule(context: "setToEmpty", config: config) {
    mutations.append(swiftmutReturnMutation(rule, silOriginal: returnType.description))
  }

  return mutations
}

func swiftmutReturnMutation(
  _ rule: SwiftmutReturnMutationRule,
  silOriginal: String
) -> SwiftmutMutation {
  return SwiftmutMutation(
    originalID: nil,
    mutator: rule.mutator,
    mutatedBuiltinName: rule.mutatedBuiltinName,
    sourceOriginal: rule.sourceOriginal,
    sourceMutated: rule.sourceMutated,
    silOriginal: silOriginal,
    silMutated: rule.silMutated)
}

func swiftmutFirstReturnRule(
  context: String,
  config: SwiftmutConfig
) -> SwiftmutReturnMutationRule? {
  for rule in config.returnMutationRules where rule.context == context {
    if swiftmutMutatorIsEnabled(rule.mutator, config: config) {
      return rule
    }
  }
  return nil
}

func swiftmutVoidCallMutation(
  for apply: ApplyInst,
  config: SwiftmutConfig
) -> SwiftmutMutation? {
  guard apply.type.isVoid else {
    return nil
  }
  guard let rule = swiftmutFirstVoidCallRule(config: config) else {
    return nil
  }

  return SwiftmutMutation(
    originalID: nil,
    mutator: rule.mutator,
    mutatedBuiltinName: rule.mutatedBuiltinName,
    sourceOriginal: rule.sourceOriginal,
    sourceMutated: rule.sourceMutated,
    silOriginal: apply.description,
    silMutated: rule.silMutated)
}

func swiftmutFirstVoidCallRule(
  config: SwiftmutConfig
) -> SwiftmutVoidCallMutationRule? {
  for rule in config.voidCallMutationRules {
    if swiftmutMutatorIsEnabled(rule.mutator, config: config) {
      return rule
    }
  }
  return nil
}

func swiftmutMutations(
  for builtin: BuiltinInst,
  config: SwiftmutConfig
) -> [SwiftmutMutation] {
  var mutations = swiftmutConditionMutations(
    for: builtin,
    config: config,
    includeGenericComparisonRules: false)
  mutations += swiftmutArithmeticSiteMutations(for: builtin, config: config)
  return mutations
}

func swiftmutContextualArithmeticRule(
  for builtin: BuiltinInst,
  builtinID: String,
  config: SwiftmutConfig
) -> SwiftmutContextualArithmeticMutationRule? {
  for rule in config.contextualArithmeticMutationRules where rule.builtinID == builtinID {
    if swiftmutContext(rule.context, matches: builtin) {
      return rule
    }
  }
  return nil
}

func swiftmutContext(
  _ context: String,
  matches builtin: BuiltinInst
) -> Bool {
  switch context {
  case "increment":
    return swiftmutIsIncrementBuiltin(builtin)
  case "unaryNegation":
    return swiftmutIsUnaryNegationBuiltin(builtin)
  case "otherwise":
    return true
  default:
    return false
  }
}

func swiftmutContextualArithmeticMutation(
  _ rule: SwiftmutContextualArithmeticMutationRule,
  for builtin: BuiltinInst
) -> SwiftmutMutation {
  SwiftmutMutation(
    originalID: builtin.id,
    mutator: rule.mutator,
    mutatedBuiltinName: rule.mutatedBuiltinName,
    sourceOriginal: rule.sourceOriginal,
    sourceMutated: rule.sourceMutated,
    silOriginal: builtin.name.string,
    silMutated: rule.mutatedBuiltinName)
}

func swiftmutArithmeticBuiltinIDName(_ builtin: BuiltinInst) -> String? {
  switch builtin.id {
  case .Add:
    return "Add"
  case .Sub:
    return "Sub"
  case .Mul:
    return "Mul"
  case .SDiv:
    return "SDiv"
  case .SRem:
    return "SRem"
  case .UDiv:
    return "UDiv"
  case .URem:
    return "URem"
  case .FAdd:
    return "FAdd"
  case .FSub:
    return "FSub"
  case .FMul:
    return "FMul"
  case .FDiv:
    return "FDiv"
  case .FRem:
    return "FRem"
  case .And:
    return "And"
  case .Or:
    return "Or"
  case .Xor:
    return "Xor"
  case .Shl:
    return "Shl"
  case .AShr:
    return "AShr"
  case .LShr:
    return "LShr"
  default:
    return nil
  }
}

func swiftmutBuiltinFunctionName(_ builtin: BuiltinInst) -> String? {
  switch builtin.id {
  case .Add:
    return "add"
  case .Sub:
    return "sub"
  case .Mul:
    return "mul"
  case .SDiv:
    return "sdiv"
  case .SRem:
    return "srem"
  case .UDiv:
    return "udiv"
  case .URem:
    return "urem"
  case .FAdd:
    return "fadd"
  case .FSub:
    return "fsub"
  case .FMul:
    return "fmul"
  case .FDiv:
    return "fdiv"
  case .FRem:
    return "frem"
  case .And:
    return "and"
  case .Or:
    return "or"
  case .Xor:
    return "xor"
  case .Shl:
    return "shl"
  case .AShr:
    return "ashr"
  case .LShr:
    return "lshr"
  case .SAddOver:
    return "sadd_with_overflow"
  case .SSubOver:
    return "ssub_with_overflow"
  default:
    return nil
  }
}

func swiftmutBuiltinIDName(_ id: BuiltinInst.ID?) -> String? {
  guard let id else {
    return nil
  }
  switch id {
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
  case .Add:
    return "Add"
  case .Sub:
    return "Sub"
  case .Mul:
    return "Mul"
  case .SDiv:
    return "SDiv"
  case .SRem:
    return "SRem"
  case .UDiv:
    return "UDiv"
  case .URem:
    return "URem"
  case .FAdd:
    return "FAdd"
  case .FSub:
    return "FSub"
  case .FMul:
    return "FMul"
  case .FDiv:
    return "FDiv"
  case .FRem:
    return "FRem"
  case .And:
    return "And"
  case .Or:
    return "Or"
  case .Xor:
    return "Xor"
  case .Shl:
    return "Shl"
  case .AShr:
    return "AShr"
  case .LShr:
    return "LShr"
  case .SAddOver:
    return "SAddOver"
  case .SSubOver:
    return "SSubOver"
  default:
    return nil
  }
}

func swiftmutBinaryMutation(
  _ builtin: BuiltinInst,
  mutator: String,
  mutatedBuiltinName: String,
  sourceOriginal: String,
  sourceMutated: String
) -> SwiftmutMutation {
  SwiftmutMutation(
    originalID: builtin.id,
    mutator: mutator,
    mutatedBuiltinName: mutatedBuiltinName,
    sourceOriginal: sourceOriginal,
    sourceMutated: sourceMutated,
    silOriginal: builtin.name.string,
    silMutated: mutatedBuiltinName)
}

func swiftmutIsIncrementBuiltin(_ builtin: BuiltinInst) -> Bool {
  let arguments = Array(builtin.arguments)
  guard arguments.count >= 2 else {
    return false
  }
  return swiftmutIsOneInteger(arguments[0]) || swiftmutIsOneInteger(arguments[1])
}

func swiftmutIsUnaryNegationBuiltin(_ builtin: BuiltinInst) -> Bool {
  let arguments = Array(builtin.arguments)
  guard arguments.count >= 2 else {
    return false
  }
  return swiftmutIsZeroInteger(arguments[0]) && !swiftmutIsZeroInteger(arguments[1])
}

func swiftmutIsOneInteger(_ value: Value) -> Bool {
  guard let literal = value as? IntegerLiteralInst,
        let literalValue = literal.value else {
    return false
  }
  return literalValue == 1
}

func swiftmutIsZeroInteger(_ value: Value) -> Bool {
  guard let literal = value as? IntegerLiteralInst,
        let literalValue = literal.value else {
    return false
  }
  return literalValue == 0
}

func swiftmutApply(
  mutation: SwiftmutMutation,
  to builtin: BuiltinInst,
  _ context: FunctionPassContext
) {
  guard let firstArgument = builtin.arguments.first else {
    return
  }

  let builder = Builder(before: builtin, context)
  let replacement = builder.createBuiltinBinaryFunction(
    name: mutation.mutatedBuiltinName,
    operandType: firstArgument.type,
    resultType: builtin.type,
    arguments: Array(builtin.arguments))
  builtin.replace(with: replacement, context)
}

func swiftmutApplyReturn(
  mutation: SwiftmutMutation,
  to returnInst: ReturnInst,
  _ context: FunctionPassContext
) {
  let builder = Builder(before: returnInst, context)
  let returnType = returnInst.returnedValue.type
  let replacement: Value?
  switch mutation.mutatedBuiltinName {
  case "return_false":
    replacement = swiftmutMakeBool(false, type: returnType, builder: builder)
  case "return_true":
    replacement = swiftmutMakeBool(true, type: returnType, builder: builder)
  case "return_nil":
    replacement = swiftmutMakeOptionalNone(type: returnType, builder: builder)
  case "return_zero":
    replacement = swiftmutMakeIntegerZero(type: returnType, in: returnInst.parentFunction, builder: builder)
  case "return_empty_string":
    replacement = swiftmutMakeEmptyString(
      type: returnType,
      helperName: "__swiftmut_empty_string",
      context: context,
      builder: builder
    )
  case "return_empty_array":
    replacement = swiftmutMakeEmptyCollection(
      type: returnType,
      helperName: "__swiftmut_empty_array",
      expectedReplacementCount: 1,
      context: context,
      builder: builder
    )
  case "return_empty_dictionary":
    replacement = swiftmutMakeEmptyCollection(
      type: returnType,
      helperName: "__swiftmut_empty_dictionary",
      expectedReplacementCount: 2,
      context: context,
      builder: builder
    )
  case "return_empty_set":
    replacement = swiftmutMakeEmptyCollection(
      type: returnType,
      helperName: "__swiftmut_empty_set",
      expectedReplacementCount: 1,
      context: context,
      builder: builder
    )
  default:
    replacement = nil
  }

  guard let replacement else {
    return
  }
  builder.createReturn(of: replacement)
  context.erase(instruction: returnInst)
}

func swiftmutMakeBool(
  _ value: Bool,
  type: Type,
  builder: Builder
) -> Value {
  let literal = builder.createBoolLiteral(value)
  return builder.createStruct(type: type, elements: [literal])
}

func swiftmutMakeIntegerZero(
  type: Type,
  in function: Function,
  builder: Builder
) -> Value? {
  guard let fields = type.getNominalFields(in: function),
        fields.count == 1,
        fields[0].canonicalType.isBuiltinInteger else {
    return nil
  }
  let zero = builder.createIntegerLiteral(0, type: fields[0])
  return builder.createStruct(type: type, elements: [zero])
}

func swiftmutMakeOptionalNone(
  type: Type,
  builder: Builder
) -> Value {
  return builder.createEnum(caseIndex: 0, payload: nil, enumType: type)
}

func swiftmutMakeEmptyString(
  type: Type,
  helperName: String,
  context: FunctionPassContext,
  builder: Builder
) -> Value? {
  guard swiftmutIsStringType(type),
        let emptyStringFunction = swiftmutEmptyStringFunction(named: helperName, context) else {
    return nil
  }
  let functionRef = builder.createFunctionRef(emptyStringFunction)
  return builder.createApply(
    function: functionRef,
    SubstitutionMap(),
    arguments: []
  )
}

func swiftmutEmptyStringFunction(
  named helperName: String,
  _ context: FunctionPassContext
) -> Function? {
  if let helper = context.lookupFunction(name: helperName)
    ?? context.lookupFunction(name: "@\(helperName)") {
    return helper
  }
  return context.lookupFunction(name: "__swiftmut_empty_string")
    ?? context.lookupFunction(name: "@__swiftmut_empty_string")
    ?? context.loadFunction(name: "__swiftmut_empty_string", loadCalleesRecursively: false)
    ?? context.loadFunction(name: "@__swiftmut_empty_string", loadCalleesRecursively: false)
}

func swiftmutRuntimeHelperThunkName(
  runtimeFunctionName: String?,
  suffix: String,
  fallbackName: String = "__swiftmut_empty_string"
) -> String {
  guard let runtimeFunctionName else {
    return fallbackName
  }
  return "\(runtimeFunctionName)_\(suffix)"
}

func swiftmutMakeEmptyCollection(
  type: Type,
  helperName: String,
  expectedReplacementCount: Int,
  context: FunctionPassContext,
  builder: Builder
) -> Value? {
  guard let emptyCollectionFunction = swiftmutEmptyCollectionFunction(named: helperName, context) else {
    return nil
  }
  guard let substitutionMap = swiftmutEmptyCollectionSubstitutionMap(
    type: type,
    helper: emptyCollectionFunction,
    expectedReplacementCount: expectedReplacementCount
  ) else {
    return nil
  }
  let functionRef = builder.createFunctionRef(emptyCollectionFunction)
  return builder.createApply(
    function: functionRef,
    substitutionMap,
    arguments: []
  )
}

func swiftmutCanApplyEmptyCollection(
  type: Type,
  helperName: String,
  expectedReplacementCount: Int,
  context: FunctionPassContext
) -> Bool {
  guard let helper = swiftmutEmptyCollectionFunction(named: helperName, context) else {
    return false
  }
  return swiftmutEmptyCollectionSubstitutionMap(
    type: type,
    helper: helper,
    expectedReplacementCount: expectedReplacementCount
  ) != nil
}

func swiftmutEmptyCollectionSubstitutionMap(
  type: Type,
  helper: Function,
  expectedReplacementCount: Int
) -> SubstitutionMap? {
  let genericSignature = helper.loweredFunctionType.invocationGenericSignatureOfFunction
  if genericSignature.isEmpty {
    return SubstitutionMap()
  }
  guard genericSignature.genericParameters.count == expectedReplacementCount else {
    return nil
  }
  let replacements = Array(type.contextSubstitutionMap.replacementTypes)
  guard replacements.count == expectedReplacementCount else {
    return nil
  }
  return SubstitutionMap(
    genericSignature: genericSignature,
    replacementTypes: replacements
  )
}

func swiftmutEmptyCollectionFunction(
  named helperName: String,
  _ context: FunctionPassContext
) -> Function? {
  if let helper = context.lookupFunction(name: helperName)
    ?? context.lookupFunction(name: "@\(helperName)") {
    return helper
  }
  switch helperName {
  case "__swiftmut_empty_array":
    return context.lookupFunction(name: "__swiftmut_empty_array")
      ?? context.lookupFunction(name: "@__swiftmut_empty_array")
      ?? context.loadFunction(name: "__swiftmut_empty_array", loadCalleesRecursively: false)
      ?? context.loadFunction(name: "@__swiftmut_empty_array", loadCalleesRecursively: false)
  case "__swiftmut_empty_dictionary":
    return context.lookupFunction(name: "__swiftmut_empty_dictionary")
      ?? context.lookupFunction(name: "@__swiftmut_empty_dictionary")
      ?? context.loadFunction(name: "__swiftmut_empty_dictionary", loadCalleesRecursively: false)
      ?? context.loadFunction(name: "@__swiftmut_empty_dictionary", loadCalleesRecursively: false)
  case "__swiftmut_empty_set":
    return context.lookupFunction(name: "__swiftmut_empty_set")
      ?? context.lookupFunction(name: "@__swiftmut_empty_set")
      ?? context.loadFunction(name: "__swiftmut_empty_set", loadCalleesRecursively: false)
      ?? context.loadFunction(name: "@__swiftmut_empty_set", loadCalleesRecursively: false)
  default:
    return nil
  }
}

func swiftmutIsBoolType(_ type: Type, in function: Function) -> Bool {
  guard let nominal = type.nominal,
        nominal.name.string == "Bool",
        let fields = type.getNominalFields(in: function),
        fields.count == 1 else {
    return false
  }
  return fields[0].canonicalType.isBuiltinInteger(withFixedWidth: 1)
}

func swiftmutIsBuiltinIntegerBackedStructType(_ type: Type, in function: Function) -> Bool {
  guard type.nominal != nil,
        let fields = type.getNominalFields(in: function),
        fields.count == 1 else {
    return false
  }
  return fields[0].canonicalType.isBuiltinInteger
}

func swiftmutNominalTypeFact(_ type: Type) -> SwiftmutNominalTypeFact? {
  guard let nominal = type.nominal else {
    return nil
  }
  return SwiftmutNominalTypeFact(
    module: nominal.parentModule.name.string,
    name: nominal.name.string
  )
}

func swiftmutIsStringType(_ type: Type) -> Bool {
  guard let nominal = type.nominal else {
    return false
  }
  return nominal.name.string == "String"
}

func swiftmutIsCollectionType(_ type: Type, named name: String) -> Bool {
  guard let nominal = type.nominal else {
    return false
  }
  return nominal.name.string == name
}

func swiftmutRecordReturnType(
  _ type: Type,
  in function: Function,
  stats: inout SwiftmutReturnDiscoveryStats
) {
  if swiftmutIsBoolType(type, in: function) {
    stats.boolTerminators += 1
    return
  }
  if type.isOptional {
    stats.optionalTerminators += 1
    return
  }
  if swiftmutIsBuiltinIntegerBackedStructType(type, in: function) {
    stats.integerTerminators += 1
    return
  }
  if swiftmutIsStringType(type) {
    stats.stringTerminators += 1
    return
  }
  guard let nominal = type.nominal else {
    stats.otherTerminators += 1
    return
  }
  switch nominal.name.string {
  case "Array", "Dictionary", "Set":
    stats.collectionTerminators += 1
  default:
    stats.otherTerminators += 1
  }
}

func swiftmutRecordReturnSourceLocationMiss(
  _ type: Type,
  in function: Function,
  stats: inout SwiftmutReturnDiscoveryStats
) {
  if swiftmutIsBoolType(type, in: function) {
    stats.missingBoolSourceLocations += 1
    return
  }
  if type.isOptional {
    stats.missingOptionalSourceLocations += 1
    return
  }
  if swiftmutIsBuiltinIntegerBackedStructType(type, in: function) {
    stats.missingIntegerSourceLocations += 1
    return
  }
  if swiftmutIsStringType(type) {
    stats.missingStringSourceLocations += 1
    return
  }
  guard let nominal = type.nominal else {
    stats.missingOtherSourceLocations += 1
    return
  }
  switch nominal.name.string {
  case "Array", "Dictionary", "Set":
    stats.missingCollectionSourceLocations += 1
  default:
    stats.missingOtherSourceLocations += 1
  }
}

func swiftmutBoolLiteralValue(_ value: Value) -> Bool? {
  guard let structInst = value as? StructInst,
        let literal = structInst.operands.first?.value as? IntegerLiteralInst,
        let literalValue = literal.value else {
    return nil
  }
  if literalValue == 0 {
    return false
  }
  if literalValue == -1 || literalValue == 1 {
    return true
  }
  return nil
}

func swiftmutIntegerStructLiteralValue(_ value: Value) -> Int? {
  guard let structInst = value as? StructInst,
        let literal = structInst.operands.first?.value as? IntegerLiteralInst else {
    return nil
  }
  return literal.value
}

func swiftmutIsOptionalNone(_ value: Value) -> Bool {
  guard let enumInst = value as? EnumInst else {
    return false
  }
  return enumInst.type.isOptional && enumInst.caseIndex == 0
}

func swiftmutMutatorIsEnabled(
  _ mutator: String,
  config: SwiftmutConfig
) -> Bool {
  SwiftmutSupport.swiftmutMutatorIsEnabled(mutator, config: config)
}
