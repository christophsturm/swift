//===--- SwiftmutRuntimeChoice.swift ----------------------------------------------===//
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

func swiftmutRuntimeVisitFunction(_ context: FunctionPassContext) -> Function? {
  context.lookupFunction(name: "__swiftmut_visit")
    ?? context.lookupFunction(name: "@__swiftmut_visit")
    ?? context.loadFunction(name: "__swiftmut_visit", loadCalleesRecursively: false)
    ?? context.loadFunction(name: "@__swiftmut_visit", loadCalleesRecursively: false)
}

func swiftmutRuntimeVisitFunction(
  named functionName: String,
  _ context: FunctionPassContext
) -> Function? {
  context.lookupFunction(name: functionName)
    ?? context.lookupFunction(name: "@\(functionName)")
    ?? swiftmutRuntimeVisitFunction(context)
}

func swiftmutAnyRuntimeVisitFunctionAvailable(
  conditionSites: [SwiftmutConditionSite],
  logicalConnectorSites: [SwiftmutLogicalConnectorSite],
  arithmeticSites: [SwiftmutArithmeticSite],
  scalarValueSites: [SwiftmutScalarValueSite],
  valueApplySites: [SwiftmutValueApplySite],
  assignmentValueSites: [SwiftmutAssignmentValueSite],
  returnSites: [SwiftmutReturnSite],
  returnBranchSites: [SwiftmutReturnBranchSite],
  voidCallSites: [SwiftmutVoidCallSite],
  _ context: FunctionPassContext
) -> Bool {
  for site in conditionSites where swiftmutRuntimeVisitFunction(named: site.runtimeFunctionName, context) != nil {
    return true
  }
  for site in logicalConnectorSites where swiftmutRuntimeVisitFunction(named: site.runtimeFunctionName, context) != nil {
    return true
  }
  for site in arithmeticSites where swiftmutRuntimeVisitFunction(named: site.runtimeFunctionName, context) != nil {
    return true
  }
  for site in scalarValueSites where swiftmutRuntimeVisitFunction(named: site.runtimeFunctionName, context) != nil {
    return true
  }
  for site in valueApplySites where swiftmutRuntimeVisitFunction(named: site.runtimeFunctionName, context) != nil {
    return true
  }
  for site in assignmentValueSites where swiftmutRuntimeVisitFunction(named: site.runtimeFunctionName, context) != nil {
    return true
  }
  for site in returnSites where swiftmutRuntimeVisitFunction(named: site.runtimeFunctionName, context) != nil {
    return true
  }
  for site in returnBranchSites where swiftmutRuntimeVisitFunction(named: site.runtimeFunctionName, context) != nil {
    return true
  }
  for site in voidCallSites where swiftmutRuntimeVisitFunction(named: site.runtimeFunctionName, context) != nil {
    return true
  }
  return swiftmutRuntimeVisitFunction(context) != nil
}

func swiftmutRuntimeVisitThunkName(file: String, config: SwiftmutConfig) -> String {
  let absolutePath: String
  if file.hasPrefix("/") {
    absolutePath = file
  } else if config.packageRoot.isEmpty {
    absolutePath = file
  } else {
    absolutePath = config.packageRoot + "/" + file
  }
  return "__swiftmut_visit_\(swiftmutHex(swiftmutStableHash(absolutePath)))"
}

func swiftmutCanMakeReturnAlternative(
  _ mutation: SwiftmutMutation,
  returnType: Type,
  in function: Function,
  runtimeFunctionName: String? = nil,
  _ context: FunctionPassContext
) -> Bool {
  switch mutation.mutatedBuiltinName {
  case "return_false", "return_true":
    return swiftmutIsBoolType(returnType, in: function)
  case "return_nil":
    return returnType.isOptional
  case "return_zero":
    return swiftmutIsIntegerStructType(returnType, in: function)
  case "return_empty_string":
    return swiftmutIsStringType(returnType)
      && swiftmutEmptyStringFunction(named: swiftmutRuntimeHelperThunkName(
        runtimeFunctionName: runtimeFunctionName,
        suffix: "empty_string"
      ), context) != nil
  case "return_empty_array":
    return swiftmutIsCollectionType(returnType, named: "Array")
      && swiftmutCanApplyEmptyCollection(
        type: returnType,
        helperName: swiftmutRuntimeHelperThunkName(
          runtimeFunctionName: runtimeFunctionName,
          suffix: "empty_array",
          fallbackName: "__swiftmut_empty_array"
        ),
        expectedReplacementCount: 1,
        context: context
      )
  case "return_empty_dictionary":
    return swiftmutIsCollectionType(returnType, named: "Dictionary")
      && swiftmutCanApplyEmptyCollection(
        type: returnType,
        helperName: swiftmutRuntimeHelperThunkName(
          runtimeFunctionName: runtimeFunctionName,
          suffix: "empty_dictionary",
          fallbackName: "__swiftmut_empty_dictionary"
        ),
        expectedReplacementCount: 2,
        context: context
      )
  case "return_empty_set":
    return swiftmutIsCollectionType(returnType, named: "Set")
      && swiftmutCanApplyEmptyCollection(
        type: returnType,
        helperName: swiftmutRuntimeHelperThunkName(
          runtimeFunctionName: runtimeFunctionName,
          suffix: "empty_set",
          fallbackName: "__swiftmut_empty_set"
        ),
        expectedReplacementCount: 1,
        context: context
      )
  default:
    return false
  }
}

func swiftmutMakeReturnAlternative(
  _ mutation: SwiftmutMutation,
  returnType: Type,
  function: Function,
  runtimeFunctionName: String? = nil,
  context: FunctionPassContext,
  builder: Builder
) -> Value? {
  switch mutation.mutatedBuiltinName {
  case "return_false":
    return swiftmutMakeBool(false, type: returnType, builder: builder)
  case "return_true":
    return swiftmutMakeBool(true, type: returnType, builder: builder)
  case "return_nil":
    return swiftmutMakeOptionalNone(type: returnType, builder: builder)
  case "return_zero":
    return swiftmutMakeIntegerZero(type: returnType, in: function, builder: builder)
  case "return_empty_string":
    return swiftmutMakeEmptyString(
      type: returnType,
      helperName: swiftmutRuntimeHelperThunkName(
        runtimeFunctionName: runtimeFunctionName,
        suffix: "empty_string"
      ),
      context: context,
      builder: builder
    )
  case "return_empty_array":
    return swiftmutMakeEmptyCollection(
      type: returnType,
      helperName: swiftmutRuntimeHelperThunkName(
        runtimeFunctionName: runtimeFunctionName,
        suffix: "empty_array",
        fallbackName: "__swiftmut_empty_array"
      ),
      expectedReplacementCount: 1,
      context: context,
      builder: builder
    )
  case "return_empty_dictionary":
    return swiftmutMakeEmptyCollection(
      type: returnType,
      helperName: swiftmutRuntimeHelperThunkName(
        runtimeFunctionName: runtimeFunctionName,
        suffix: "empty_dictionary",
        fallbackName: "__swiftmut_empty_dictionary"
      ),
      expectedReplacementCount: 2,
      context: context,
      builder: builder
    )
  case "return_empty_set":
    return swiftmutMakeEmptyCollection(
      type: returnType,
      helperName: swiftmutRuntimeHelperThunkName(
        runtimeFunctionName: runtimeFunctionName,
        suffix: "empty_set",
        fallbackName: "__swiftmut_empty_set"
      ),
      expectedReplacementCount: 1,
      context: context,
      builder: builder
    )
  default:
    return nil
  }
}

func swiftmutMakeConditionAlternative(
  _ mutation: SwiftmutMutation,
  comparison: BuiltinInst?,
  originalCondition: Value,
  builder: Builder
) -> Value? {
  switch mutation.mutatedBuiltinName {
  case "condition_true":
    return builder.createBoolLiteral(true)
  case "condition_false":
    return builder.createBoolLiteral(false)
  default:
    guard let comparison,
          let firstArgument = comparison.arguments.first else {
      return nil
    }
    return builder.createBuiltinBinaryFunction(
      name: mutation.mutatedBuiltinName,
      operandType: firstArgument.type,
      resultType: originalCondition.type,
      arguments: Array(comparison.arguments))
  }
}

func swiftmutCreateConditionBranch(
  condition: Value,
  trueBlock: BasicBlock,
  falseBlock: BasicBlock,
  trueArguments: [Value],
  falseArguments: [Value],
  insertionBuilder: Builder,
  function: Function,
  location: Location,
  _ context: FunctionPassContext
) {
  let trueEdgeBlock = function.appendNewBlock(context)
  let falseEdgeBlock = function.appendNewBlock(context)
  insertionBuilder.createCondBranch(
    condition: condition,
    trueBlock: trueEdgeBlock,
    falseBlock: falseEdgeBlock
  )
  Builder(atEndOf: trueEdgeBlock, location: location, context).createBranch(
    to: trueBlock,
    arguments: trueArguments
  )
  Builder(atEndOf: falseEdgeBlock, location: location, context).createBranch(
    to: falseBlock,
    arguments: falseArguments
  )
}

func swiftmutMakeRuntimeSiteID(
  _ siteID: UInt64,
  visitFunction: Function,
  insertionPoint: Instruction,
  _ context: FunctionPassContext
) -> Value? {
  let convention = FunctionConvention(
    for: visitFunction.loweredFunctionType,
    in: insertionPoint.parentFunction
  )
  guard let parameter = convention.parameters.first else {
    return nil
  }
  let parameterType = parameter.type.loweredType(in: insertionPoint.parentFunction)
  let builder = Builder(before: insertionPoint, context)
  if parameterType.canonicalType.isBuiltinInteger {
    return builder.createIntegerLiteral(siteID, type: parameterType)
  }
  guard let fields = parameterType.getNominalFields(in: insertionPoint.parentFunction),
        fields.count == 1 else {
    return nil
  }
  let literal = builder.createIntegerLiteral(siteID, type: fields[0])
  return builder.createStruct(type: parameterType, elements: [literal])
}

func swiftmutRuntimeChoiceRawValue(
  _ choice: Value,
  builder: Builder,
  function: Function
) -> Value? {
  if choice.type.canonicalType.isBuiltinInteger {
    return choice
  }
  guard let fields = choice.type.getNominalFields(in: function),
        fields.count == 1,
        fields[0].canonicalType.isBuiltinInteger else {
    return nil
  }
  return builder.createStructExtract(struct: choice, fieldIndex: 0)
}

