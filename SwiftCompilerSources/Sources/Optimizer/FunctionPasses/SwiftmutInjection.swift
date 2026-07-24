//===--- SwiftmutInjection.swift ----------------------------------------------===//
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

func swiftmutInjectConditionSite(
  _ site: SwiftmutConditionSite,
  _ context: FunctionPassContext
) -> Bool {
  guard let visitFunction = swiftmutRuntimeVisitFunction(
          named: site.runtimeFunctionName,
          context,
          originalFunction: site.branch.parentFunction
        ),
        let siteID = swiftmutMakeRuntimeSiteID(
          site.siteID,
          visitFunction: visitFunction,
          insertionPoint: site.branch,
          context
        ) else {
    return false
  }

  let function = site.branch.parentFunction
  let originalCondition = site.branch.condition
  let trueBlock = site.branch.trueBlock
  let falseBlock = site.branch.falseBlock
  let trueArguments = site.branch.trueOperands.map(\.value)
  let falseArguments = site.branch.falseOperands.map(\.value)
  let originalBlock = function.appendNewBlock(context)
  let alternativeBlocks = site.alternatives.map { _ in function.appendNewBlock(context) }
  let checkBlocks = site.alternatives.dropFirst().map { _ in function.appendNewBlock(context) }

  let dispatchBuilder = Builder(before: site.branch, context)
  let visitRef = dispatchBuilder.createFunctionRef(visitFunction)
  let choice = dispatchBuilder.createApply(
    function: visitRef,
    SubstitutionMap(),
    arguments: [siteID]
  )
  guard let rawChoice = swiftmutRuntimeChoiceRawValue(
    choice,
    builder: dispatchBuilder,
    function: function
  ) else {
    return false
  }

  for (index, alternative) in site.alternatives.enumerated() {
    let builder = Builder(atEndOf: alternativeBlocks[index], location: site.branch.location, context)
    guard let mutatedCondition = swiftmutMakeConditionAlternative(
      alternative.mutation,
      comparison: site.comparison,
      originalCondition: originalCondition,
      builder: builder
    ) else {
      return false
    }
    swiftmutCreateConditionBranch(
      condition: mutatedCondition,
      trueBlock: trueBlock,
      falseBlock: falseBlock,
      trueArguments: trueArguments,
      falseArguments: falseArguments,
      insertionBuilder: builder,
      function: function,
      location: site.branch.location,
      context
    )
  }

  let originalBuilder = Builder(atEndOf: originalBlock, location: site.branch.location, context)
  swiftmutCreateConditionBranch(
    condition: originalCondition,
    trueBlock: trueBlock,
    falseBlock: falseBlock,
    trueArguments: trueArguments,
    falseArguments: falseArguments,
    insertionBuilder: originalBuilder,
    function: function,
    location: site.branch.location,
    context
  )

  for (index, alternative) in site.alternatives.enumerated() {
    let builder = index == 0
      ? dispatchBuilder
      : Builder(atEndOf: checkBlocks[index - 1], location: site.branch.location, context)
    let nextBlock = index + 1 < site.alternatives.count
      ? checkBlocks[index]
      : originalBlock
    let alternativeLiteral = builder.createIntegerLiteral(alternative.alternativeIndex, type: rawChoice.type)
    let isSelected = builder.createBuiltinBinaryFunction(
      name: "cmp_eq",
      operandType: rawChoice.type,
      resultType: originalCondition.type,
      arguments: [rawChoice, alternativeLiteral]
    )
    builder.createCondBranch(
      condition: isSelected,
      trueBlock: alternativeBlocks[index],
      falseBlock: nextBlock
    )
  }

  context.erase(instruction: site.branch)
  return true
}

func swiftmutInjectReturnSite(
  _ site: SwiftmutReturnSite,
  _ context: FunctionPassContext
) -> Bool {
  guard let visitFunction = swiftmutRuntimeVisitFunction(
          named: site.runtimeFunctionName,
          context,
          originalFunction: site.returnInst.parentFunction
        ),
        let siteID = swiftmutMakeRuntimeSiteID(
          site.siteID,
          visitFunction: visitFunction,
          insertionPoint: site.returnInst,
          context
        ) else {
    return false
  }

  let returnType = site.returnInst.returnedValue.type
  let function = site.returnInst.parentFunction
  let originalValue = site.returnInst.returnedValue
  guard swiftmutReturnValueCanBeReplaced(originalValue, in: function),
        site.alternatives.allSatisfy({
    swiftmutCanMakeReturnAlternative(
      $0.mutation,
      returnType: returnType,
      in: function,
      runtimeFunctionName: site.runtimeFunctionName,
      context
    )
  }) else {
    return false
  }

  let originalBlock = function.appendNewBlock(context)
  let alternativeBlocks = site.alternatives.map { _ in function.appendNewBlock(context) }
  let checkBlocks = site.alternatives.dropFirst().map { _ in function.appendNewBlock(context) }
  let returnBlock = function.appendNewBlock(context)
  let selectedReturnValue = returnBlock.addArgument(
    type: returnType,
    ownership: originalValue.ownership,
    context
  )

  let dispatchBuilder = Builder(before: site.returnInst, context)
  let visitRef = dispatchBuilder.createFunctionRef(visitFunction)
  let choice = dispatchBuilder.createApply(
    function: visitRef,
    SubstitutionMap(),
    arguments: [siteID]
  )
  guard let rawChoice = swiftmutRuntimeChoiceRawValue(
    choice,
    builder: dispatchBuilder,
    function: function
  ) else {
    return false
  }

  for (index, alternative) in site.alternatives.enumerated() {
    let builder = Builder(atEndOf: alternativeBlocks[index], location: site.returnInst.location, context)
    guard let replacement = swiftmutMakeReturnAlternative(
      alternative.mutation,
      returnType: returnType,
      function: function,
      runtimeFunctionName: site.runtimeFunctionName,
      context: context,
      builder: builder
    ) else {
      return false
    }
    if !returnType.isTrivial(in: function) {
      builder.createDestroyValue(operand: originalValue)
    }
    builder.createBranch(to: returnBlock, arguments: [replacement])
  }

  Builder(atEndOf: originalBlock, location: site.returnInst.location, context)
    .createBranch(to: returnBlock, arguments: [originalValue])
  Builder(atEndOf: returnBlock, location: site.returnInst.location, context)
    .createReturn(of: selectedReturnValue)

  for (index, alternative) in site.alternatives.enumerated() {
    let builder = index == 0
      ? dispatchBuilder
      : Builder(atEndOf: checkBlocks[index - 1], location: site.returnInst.location, context)
    let nextBlock = index + 1 < site.alternatives.count
      ? checkBlocks[index]
      : originalBlock
    let alternativeLiteral = builder.createIntegerLiteral(alternative.alternativeIndex, type: rawChoice.type)
    let isSelected = builder.createBuiltinBinaryFunction(
      name: "cmp_eq",
      operandType: rawChoice.type,
      resultType: context.getBuiltinIntegerType(bitWidth: 1),
      arguments: [rawChoice, alternativeLiteral]
    )
    builder.createCondBranch(
      condition: isSelected,
      trueBlock: alternativeBlocks[index],
      falseBlock: nextBlock
    )
  }

  context.erase(instruction: site.returnInst)
  return true
}

func swiftmutInjectReturnBranchSite(
  _ site: SwiftmutReturnBranchSite,
  _ context: FunctionPassContext
) -> Bool {
  guard let visitFunction = swiftmutRuntimeVisitFunction(
          named: site.runtimeFunctionName,
          context,
          originalFunction: site.branch.parentFunction
        ),
        let siteID = swiftmutMakeRuntimeSiteID(
          site.siteID,
          visitFunction: visitFunction,
          insertionPoint: site.branch,
          context
        ) else {
    return false
  }

  guard let currentValue = site.branch.operands.first?.value else {
    return false
  }

  let valueType = currentValue.type
  let function = site.branch.parentFunction
  guard valueType.isTrivial(in: function),
        site.alternatives.allSatisfy({
          swiftmutCanMakeReturnAlternative(
            $0.mutation,
            returnType: valueType,
            in: function,
            runtimeFunctionName: site.runtimeFunctionName,
            context
          )
        }) else {
    return false
  }

  let targetBlock = site.branch.targetBlock
  let originalBlock = function.appendNewBlock(context)
  let alternativeBlocks = site.alternatives.map { _ in function.appendNewBlock(context) }
  let checkBlocks = site.alternatives.dropFirst().map { _ in function.appendNewBlock(context) }

  let dispatchBuilder = Builder(before: site.branch, context)
  let visitRef = dispatchBuilder.createFunctionRef(visitFunction)
  let choice = dispatchBuilder.createApply(
    function: visitRef,
    SubstitutionMap(),
    arguments: [siteID]
  )
  guard let rawChoice = swiftmutRuntimeChoiceRawValue(
    choice,
    builder: dispatchBuilder,
    function: function
  ) else {
    return false
  }

  for (index, alternative) in site.alternatives.enumerated() {
    let builder = Builder(atEndOf: alternativeBlocks[index], location: site.branch.location, context)
    guard let replacement = swiftmutMakeReturnAlternative(
      alternative.mutation,
      returnType: valueType,
      function: function,
      runtimeFunctionName: site.runtimeFunctionName,
      context: context,
      builder: builder
    ) else {
      return false
    }
    builder.createBranch(to: targetBlock, arguments: [replacement])
  }

  Builder(atEndOf: originalBlock, location: site.branch.location, context)
    .createBranch(to: targetBlock, arguments: [currentValue])

  for (index, alternative) in site.alternatives.enumerated() {
    let builder = index == 0
      ? dispatchBuilder
      : Builder(atEndOf: checkBlocks[index - 1], location: site.branch.location, context)
    let nextBlock = index + 1 < site.alternatives.count
      ? checkBlocks[index]
      : originalBlock
    let alternativeLiteral = builder.createIntegerLiteral(alternative.alternativeIndex, type: rawChoice.type)
    let isSelected = builder.createBuiltinBinaryFunction(
      name: "cmp_eq",
      operandType: rawChoice.type,
      resultType: context.getBuiltinIntegerType(bitWidth: 1),
      arguments: [rawChoice, alternativeLiteral]
    )
    builder.createCondBranch(
      condition: isSelected,
      trueBlock: alternativeBlocks[index],
      falseBlock: nextBlock
    )
  }

  context.erase(instruction: site.branch)
  return true
}

func swiftmutInjectArithmeticSite(
  _ site: SwiftmutArithmeticSite,
  _ context: FunctionPassContext
) -> Bool {
  guard let visitFunction = swiftmutRuntimeVisitFunction(
          named: site.runtimeFunctionName,
          context,
          originalFunction: site.builtin.parentFunction
        ),
        let siteID = swiftmutMakeRuntimeSiteID(
          site.siteID,
          visitFunction: visitFunction,
          insertionPoint: site.builtin,
          context
        ) else {
    return false
  }
  guard let firstArgument = site.builtin.arguments.first,
        let originalBuiltinName = swiftmutBuiltinFunctionName(site.builtin) else {
    return false
  }

  let function = site.builtin.parentFunction
  let originalPredecessorBlock = site.builtin.parentBlock
  let continuationBlock = context.splitBlock(before: site.builtin)
  let selectedValue = continuationBlock.addArgument(
    type: site.builtin.type,
    ownership: site.builtin.ownership,
    context
  )
  let originalBlock = function.appendNewBlock(context)
  let alternativeBlocks = site.alternatives.map { _ in function.appendNewBlock(context) }
  let checkBlocks = site.alternatives.dropFirst().map { _ in function.appendNewBlock(context) }

  let dispatchBuilder = Builder(atEndOf: originalPredecessorBlock, location: site.builtin.location, context)
  let visitRef = dispatchBuilder.createFunctionRef(visitFunction)
  let choice = dispatchBuilder.createApply(
    function: visitRef,
    SubstitutionMap(),
    arguments: [siteID]
  )
  guard let rawChoice = swiftmutRuntimeChoiceRawValue(
    choice,
    builder: dispatchBuilder,
    function: function
  ) else {
    return false
  }

  for (index, alternative) in site.alternatives.enumerated() {
    let builder = Builder(atEndOf: alternativeBlocks[index], location: site.builtin.location, context)
    let replacement = builder.createBuiltinBinaryFunction(
      name: alternative.mutation.mutatedBuiltinName,
      operandType: firstArgument.type,
      resultType: site.builtin.type,
      arguments: Array(site.builtin.arguments)
    )
    builder.createBranch(to: continuationBlock, arguments: [replacement])
  }

  let originalBuilder = Builder(atEndOf: originalBlock, location: site.builtin.location, context)
  let originalValue = originalBuilder.createBuiltinBinaryFunction(
    name: originalBuiltinName,
    operandType: firstArgument.type,
    resultType: site.builtin.type,
    arguments: Array(site.builtin.arguments)
  )
  originalBuilder.createBranch(to: continuationBlock, arguments: [originalValue])

  for (index, alternative) in site.alternatives.enumerated() {
    let builder = index == 0
      ? dispatchBuilder
      : Builder(atEndOf: checkBlocks[index - 1], location: site.builtin.location, context)
    let nextBlock = index + 1 < site.alternatives.count
      ? checkBlocks[index]
      : originalBlock
    let alternativeLiteral = builder.createIntegerLiteral(alternative.alternativeIndex, type: rawChoice.type)
    let isSelected = builder.createBuiltinBinaryFunction(
      name: "cmp_eq",
      operandType: rawChoice.type,
      resultType: context.getBuiltinIntegerType(bitWidth: 1),
      arguments: [rawChoice, alternativeLiteral]
    )
    builder.createCondBranch(
      condition: isSelected,
      trueBlock: alternativeBlocks[index],
      falseBlock: nextBlock
    )
  }

  site.builtin.replace(with: selectedValue, context)
  return true
}

func swiftmutInjectScalarValueSite(
  _ site: SwiftmutScalarValueSite,
  _ context: FunctionPassContext
) -> Bool {
  guard let visitFunction = swiftmutRuntimeVisitFunction(
          named: site.runtimeFunctionName,
          context,
          originalFunction: site.value.parentFunction
        ),
        let siteID = swiftmutMakeRuntimeSiteID(
          site.siteID,
          visitFunction: visitFunction,
          insertionPoint: site.value,
          context
        ) else {
    return false
  }

  let valueType = site.value.type
  let function = site.value.parentFunction
  guard site.alternatives.allSatisfy({
    swiftmutCanMakeReturnAlternative($0.mutation, returnType: valueType, in: function, context)
  }) else {
    return false
  }

  let originalPredecessorBlock = site.value.parentBlock
  let continuationBlock = context.splitBlock(before: site.value)
  let selectedValue = continuationBlock.addArgument(
    type: valueType,
    ownership: site.value.ownership,
    context
  )
  let originalBlock = function.appendNewBlock(context)
  let alternativeBlocks = site.alternatives.map { _ in function.appendNewBlock(context) }
  let checkBlocks = site.alternatives.dropFirst().map { _ in function.appendNewBlock(context) }

  let dispatchBuilder = Builder(atEndOf: originalPredecessorBlock, location: site.value.location, context)
  let visitRef = dispatchBuilder.createFunctionRef(visitFunction)
  let choice = dispatchBuilder.createApply(
    function: visitRef,
    SubstitutionMap(),
    arguments: [siteID]
  )
  guard let rawChoice = swiftmutRuntimeChoiceRawValue(
    choice,
    builder: dispatchBuilder,
    function: function
  ) else {
    return false
  }

  for (index, alternative) in site.alternatives.enumerated() {
    let builder = Builder(atEndOf: alternativeBlocks[index], location: site.value.location, context)
    guard let replacement = swiftmutMakeReturnAlternative(
      alternative.mutation,
      returnType: valueType,
      function: function,
      context: context,
      builder: builder
    ) else {
      return false
    }
    builder.createBranch(to: continuationBlock, arguments: [replacement])
  }

  let originalBuilder = Builder(atEndOf: originalBlock, location: site.value.location, context)
  let originalValue = originalBuilder.createStruct(type: valueType, elements: Array(site.value.operands.values))
  originalBuilder.createBranch(to: continuationBlock, arguments: [originalValue])

  for (index, alternative) in site.alternatives.enumerated() {
    let builder = index == 0
      ? dispatchBuilder
      : Builder(atEndOf: checkBlocks[index - 1], location: site.value.location, context)
    let nextBlock = index + 1 < site.alternatives.count
      ? checkBlocks[index]
      : originalBlock
    let alternativeLiteral = builder.createIntegerLiteral(alternative.alternativeIndex, type: rawChoice.type)
    let isSelected = builder.createBuiltinBinaryFunction(
      name: "cmp_eq",
      operandType: rawChoice.type,
      resultType: context.getBuiltinIntegerType(bitWidth: 1),
      arguments: [rawChoice, alternativeLiteral]
    )
    builder.createCondBranch(
      condition: isSelected,
      trueBlock: alternativeBlocks[index],
      falseBlock: nextBlock
    )
  }

  site.value.replace(with: selectedValue, context)
  return true
}

func swiftmutInjectValueApplySite(
  _ site: SwiftmutValueApplySite,
  _ context: FunctionPassContext
) -> Bool {
  guard let visitFunction = swiftmutRuntimeVisitFunction(
          named: site.runtimeFunctionName,
          context,
          originalFunction: site.apply.parentFunction
        ),
        let siteID = swiftmutMakeRuntimeSiteID(
          site.siteID,
          visitFunction: visitFunction,
          insertionPoint: site.apply,
          context
        ) else {
    return false
  }

  let valueType = site.apply.type
  let function = site.apply.parentFunction
  guard site.alternatives.allSatisfy({
    swiftmutCanMakeReturnAlternative($0.mutation, returnType: valueType, in: function, context)
  }) else {
    return false
  }

  let originalPredecessorBlock = site.apply.parentBlock
  let continuationBlock: BasicBlock
  if site.preservesOriginalApply {
    guard let successor = site.apply.next else {
      return false
    }
    continuationBlock = context.splitBlock(before: successor)
  } else {
    continuationBlock = context.splitBlock(before: site.apply)
  }
  let selectedValue = continuationBlock.addArgument(
    type: valueType,
    ownership: site.apply.ownership,
    context
  )
  let originalBlock = function.appendNewBlock(context)
  let alternativeBlocks = site.alternatives.map { _ in function.appendNewBlock(context) }
  let checkBlocks = site.alternatives.dropFirst().map { _ in function.appendNewBlock(context) }

  let dispatchBuilder = Builder(atEndOf: originalPredecessorBlock, location: site.apply.location, context)
  let visitRef = dispatchBuilder.createFunctionRef(visitFunction)
  let choice = dispatchBuilder.createApply(
    function: visitRef,
    SubstitutionMap(),
    arguments: [siteID]
  )
  guard let rawChoice = swiftmutRuntimeChoiceRawValue(
    choice,
    builder: dispatchBuilder,
    function: function
  ) else {
    return false
  }

  for (index, alternative) in site.alternatives.enumerated() {
    let builder = Builder(atEndOf: alternativeBlocks[index], location: site.apply.location, context)
    guard let replacement = swiftmutMakeReturnAlternative(
      alternative.mutation,
      returnType: valueType,
      function: function,
      context: context,
      builder: builder
    ) else {
      return false
    }
    builder.createBranch(to: continuationBlock, arguments: [replacement])
  }

  let originalBuilder = Builder(atEndOf: originalBlock, location: site.apply.location, context)
  if site.preservesOriginalApply {
    // The call already ran in the predecessor block; the original branch
    // only forwards its untouched result.
    site.apply.uses.replaceAll(with: selectedValue, context)
    originalBuilder.createBranch(to: continuationBlock, arguments: [site.apply])
  } else {
    let originalValue = originalBuilder.createApply(
      function: site.apply.callee,
      site.apply.substitutionMap,
      arguments: Array(site.apply.arguments),
      isNonThrowing: site.apply.isNonThrowing,
      isNonAsync: site.apply.isNonAsync,
      specializationInfo: site.apply.specializationInfo
    )
    originalBuilder.createBranch(to: continuationBlock, arguments: [originalValue])
  }

  for (index, alternative) in site.alternatives.enumerated() {
    let builder = index == 0
      ? dispatchBuilder
      : Builder(atEndOf: checkBlocks[index - 1], location: site.apply.location, context)
    let nextBlock = index + 1 < site.alternatives.count
      ? checkBlocks[index]
      : originalBlock
    let alternativeLiteral = builder.createIntegerLiteral(alternative.alternativeIndex, type: rawChoice.type)
    let isSelected = builder.createBuiltinBinaryFunction(
      name: "cmp_eq",
      operandType: rawChoice.type,
      resultType: context.getBuiltinIntegerType(bitWidth: 1),
      arguments: [rawChoice, alternativeLiteral]
    )
    builder.createCondBranch(
      condition: isSelected,
      trueBlock: alternativeBlocks[index],
      falseBlock: nextBlock
    )
  }

  if !site.preservesOriginalApply {
    site.apply.replace(with: selectedValue, context)
  }
  return true
}

func swiftmutInjectAssignmentValueSite(
  _ site: SwiftmutAssignmentValueSite,
  _ context: FunctionPassContext
) -> Bool {
  guard let visitFunction = swiftmutRuntimeVisitFunction(
          named: site.runtimeFunctionName,
          context,
          originalFunction: site.store.parentFunction
        ),
        let siteID = swiftmutMakeRuntimeSiteID(
          site.siteID,
          visitFunction: visitFunction,
          insertionPoint: site.store,
          context
        ) else {
    return false
  }

  let valueType = site.store.source.type
  let function = site.store.parentFunction
  guard swiftmutCanDispatchAssignmentValue(site.store),
        site.alternatives.allSatisfy({
          swiftmutCanMakeReturnAlternative(
            $0.mutation,
            returnType: valueType,
            in: function,
            runtimeFunctionName: site.runtimeFunctionName,
            context
          )
        }) else {
    return false
  }

  let originalPredecessorBlock = site.store.parentBlock
  let continuationBlock = context.splitBlock(before: site.store)
  let selectedValue = continuationBlock.addArgument(
    type: valueType,
    ownership: site.store.source.ownership,
    context
  )
  let originalBlock = function.appendNewBlock(context)
  let alternativeBlocks = site.alternatives.map { _ in function.appendNewBlock(context) }
  let checkBlocks = site.alternatives.dropFirst().map { _ in function.appendNewBlock(context) }

  let dispatchBuilder = Builder(atEndOf: originalPredecessorBlock, location: site.store.location, context)
  let visitRef = dispatchBuilder.createFunctionRef(visitFunction)
  let choice = dispatchBuilder.createApply(
    function: visitRef,
    SubstitutionMap(),
    arguments: [siteID]
  )
  guard let rawChoice = swiftmutRuntimeChoiceRawValue(
    choice,
    builder: dispatchBuilder,
    function: function
  ) else {
    return false
  }

  for (index, alternative) in site.alternatives.enumerated() {
    let builder = Builder(atEndOf: alternativeBlocks[index], location: site.store.location, context)
    guard let replacement = swiftmutMakeReturnAlternative(
      alternative.mutation,
      returnType: valueType,
      function: function,
      runtimeFunctionName: site.runtimeFunctionName,
      context: context,
      builder: builder
    ) else {
      return false
    }
    builder.createBranch(to: continuationBlock, arguments: [replacement])
  }

  Builder(atEndOf: originalBlock, location: site.store.location, context)
    .createBranch(to: continuationBlock, arguments: [site.store.source])

  for (index, alternative) in site.alternatives.enumerated() {
    let builder = index == 0
      ? dispatchBuilder
      : Builder(atEndOf: checkBlocks[index - 1], location: site.store.location, context)
    let nextBlock = index + 1 < site.alternatives.count
      ? checkBlocks[index]
      : originalBlock
    let alternativeLiteral = builder.createIntegerLiteral(alternative.alternativeIndex, type: rawChoice.type)
    let isSelected = builder.createBuiltinBinaryFunction(
      name: "cmp_eq",
      operandType: rawChoice.type,
      resultType: context.getBuiltinIntegerType(bitWidth: 1),
      arguments: [rawChoice, alternativeLiteral]
    )
    builder.createCondBranch(
      condition: isSelected,
      trueBlock: alternativeBlocks[index],
      falseBlock: nextBlock
    )
  }

  Builder(before: site.store, context).createStore(
    source: selectedValue,
    destination: site.store.destination,
    ownership: site.store.storeOwnership
  )
  context.erase(instruction: site.store)
  return true
}

func swiftmutInjectVoidCallSite(
  _ site: SwiftmutVoidCallSite,
  _ context: FunctionPassContext
) -> Bool {
  guard let cleanupValues = swiftmutCallDeletionBypassCleanupValues(site.apply),
        let visitFunction = swiftmutRuntimeVisitFunction(
          named: site.runtimeFunctionName,
          context,
          originalFunction: site.apply.parentFunction
        ),
        let siteID = swiftmutMakeRuntimeSiteID(
          site.siteID,
          visitFunction: visitFunction,
          insertionPoint: site.apply,
          context
        ) else {
    return false
  }

  let function = site.apply.parentFunction
  let originalPredecessorBlock = site.apply.parentBlock
  let continuationBlock = context.splitBlock(before: site.apply)
  let selectedVoid = continuationBlock.addArgument(
    type: site.apply.type,
    ownership: site.apply.ownership,
    context
  )
  let callBlock = function.appendNewBlock(context)
  let alternativeBlocks = site.alternatives.map { _ in function.appendNewBlock(context) }
  let checkBlocks = site.alternatives.dropFirst().map { _ in function.appendNewBlock(context) }

  let dispatchBuilder = Builder(atEndOf: originalPredecessorBlock, location: site.apply.location, context)
  let visitRef = dispatchBuilder.createFunctionRef(visitFunction)
  let choice = dispatchBuilder.createApply(
    function: visitRef,
    SubstitutionMap(),
    arguments: [siteID]
  )
  guard let rawChoice = swiftmutRuntimeChoiceRawValue(
    choice,
    builder: dispatchBuilder,
    function: function
  ) else {
    return false
  }

  for (index, _) in site.alternatives.enumerated() {
    let builder = Builder(atEndOf: alternativeBlocks[index], location: site.apply.location, context)
    for value in cleanupValues {
      builder.createDestroyValue(operand: value)
    }
    let skippedVoid = builder.createTuple(type: site.apply.type, elements: [])
    builder.createBranch(to: continuationBlock, arguments: [skippedVoid])
  }
  let callBuilder = Builder(atEndOf: callBlock, location: site.apply.location, context)
  let originalValue = callBuilder.createApply(
    function: site.apply.callee,
    site.apply.substitutionMap,
    arguments: Array(site.apply.arguments),
    isNonThrowing: site.apply.isNonThrowing,
    isNonAsync: site.apply.isNonAsync,
    specializationInfo: site.apply.specializationInfo
  )
  callBuilder.createBranch(to: continuationBlock, arguments: [originalValue])

  for (index, alternative) in site.alternatives.enumerated() {
    let builder = index == 0
      ? dispatchBuilder
      : Builder(atEndOf: checkBlocks[index - 1], location: site.apply.location, context)
    let nextBlock = index + 1 < site.alternatives.count
      ? checkBlocks[index]
      : callBlock
    let alternativeLiteral = builder.createIntegerLiteral(alternative.alternativeIndex, type: rawChoice.type)
    let isSelected = builder.createBuiltinBinaryFunction(
      name: "cmp_eq",
      operandType: rawChoice.type,
      resultType: context.getBuiltinIntegerType(bitWidth: 1),
      arguments: [rawChoice, alternativeLiteral]
    )
    builder.createCondBranch(
      condition: isSelected,
      trueBlock: alternativeBlocks[index],
      falseBlock: nextBlock
    )
  }

  site.apply.replace(with: selectedVoid, context)
  return true
}

func swiftmutInjectStatementDeletionSite(
  _ site: SwiftmutStatementDeletionSite,
  _ context: FunctionPassContext
) -> Bool {
  if let store = site.instruction as? StoreInst {
    return swiftmutInjectStatementDeletionStoreSite(site, store: store, context)
  }
  if let apply = site.instruction as? ApplyInst {
    return swiftmutInjectStatementDeletionApplySite(site, apply: apply, context)
  }
  return false
}

private func swiftmutInjectStatementDeletionStoreSite(
  _ site: SwiftmutStatementDeletionSite,
  store: StoreInst,
  _ context: FunctionPassContext
) -> Bool {
  guard swiftmutCanDeleteStatementAssignment(store),
        let visitFunction = swiftmutRuntimeVisitFunction(
          named: site.runtimeFunctionName,
          context,
          originalFunction: store.parentFunction
        ),
        let siteID = swiftmutMakeRuntimeSiteID(
          site.siteID,
          visitFunction: visitFunction,
          insertionPoint: store,
          context
        ) else {
    return false
  }

  let function = store.parentFunction
  let originalPredecessorBlock = store.parentBlock
  let continuationBlock = context.splitBlock(before: store)
  let originalBlock = function.appendNewBlock(context)
  let alternativeBlocks = site.alternatives.map { _ in function.appendNewBlock(context) }
  let checkBlocks = site.alternatives.dropFirst().map { _ in function.appendNewBlock(context) }

  let dispatchBuilder = Builder(atEndOf: originalPredecessorBlock, location: store.location, context)
  let visitRef = dispatchBuilder.createFunctionRef(visitFunction)
  let choice = dispatchBuilder.createApply(
    function: visitRef,
    SubstitutionMap(),
    arguments: [siteID]
  )
  guard let rawChoice = swiftmutRuntimeChoiceRawValue(
    choice,
    builder: dispatchBuilder,
    function: function
  ) else {
    return false
  }

  for (index, _) in site.alternatives.enumerated() {
    let builder = Builder(atEndOf: alternativeBlocks[index], location: store.location, context)
    if store.source.ownership == .owned {
      builder.createDestroyValue(operand: store.source)
    }
    builder.createBranch(to: continuationBlock, arguments: [])
  }

  let originalBuilder = Builder(atEndOf: originalBlock, location: store.location, context)
  originalBuilder.createStore(
    source: store.source,
    destination: store.destination,
    ownership: store.storeOwnership
  )
  originalBuilder.createBranch(to: continuationBlock, arguments: [])

  for (index, alternative) in site.alternatives.enumerated() {
    let builder = index == 0
      ? dispatchBuilder
      : Builder(atEndOf: checkBlocks[index - 1], location: store.location, context)
    let nextBlock = index + 1 < site.alternatives.count
      ? checkBlocks[index]
      : originalBlock
    let alternativeLiteral = builder.createIntegerLiteral(alternative.alternativeIndex, type: rawChoice.type)
    let isSelected = builder.createBuiltinBinaryFunction(
      name: "cmp_eq",
      operandType: rawChoice.type,
      resultType: context.getBuiltinIntegerType(bitWidth: 1),
      arguments: [rawChoice, alternativeLiteral]
    )
    builder.createCondBranch(
      condition: isSelected,
      trueBlock: alternativeBlocks[index],
      falseBlock: nextBlock
    )
  }

  context.erase(instruction: store)
  return true
}

private func swiftmutInjectStatementDeletionApplySite(
  _ site: SwiftmutStatementDeletionSite,
  apply: ApplyInst,
  _ context: FunctionPassContext
) -> Bool {
  guard !apply.type.isVoid,
        !apply.isCalleeNoReturn,
        apply.uses.isEmpty,
        let cleanupValues = swiftmutCallDeletionBypassCleanupValues(apply),
        let visitFunction = swiftmutRuntimeVisitFunction(
          named: site.runtimeFunctionName,
          context,
          originalFunction: apply.parentFunction
        ),
        let siteID = swiftmutMakeRuntimeSiteID(
          site.siteID,
          visitFunction: visitFunction,
          insertionPoint: apply,
          context
        ) else {
    return false
  }

  let function = apply.parentFunction
  let originalPredecessorBlock = apply.parentBlock
  let continuationBlock = context.splitBlock(before: apply)
  let originalBlock = function.appendNewBlock(context)
  let alternativeBlocks = site.alternatives.map { _ in function.appendNewBlock(context) }
  let checkBlocks = site.alternatives.dropFirst().map { _ in function.appendNewBlock(context) }

  let dispatchBuilder = Builder(atEndOf: originalPredecessorBlock, location: apply.location, context)
  let visitRef = dispatchBuilder.createFunctionRef(visitFunction)
  let choice = dispatchBuilder.createApply(
    function: visitRef,
    SubstitutionMap(),
    arguments: [siteID]
  )
  guard let rawChoice = swiftmutRuntimeChoiceRawValue(
    choice,
    builder: dispatchBuilder,
    function: function
  ) else {
    return false
  }

  for (index, _) in site.alternatives.enumerated() {
    let builder = Builder(atEndOf: alternativeBlocks[index], location: apply.location, context)
    for value in cleanupValues {
      builder.createDestroyValue(operand: value)
    }
    builder.createBranch(to: continuationBlock, arguments: [])
  }

  let originalBuilder = Builder(atEndOf: originalBlock, location: apply.location, context)
  _ = originalBuilder.createApply(
    function: apply.callee,
    apply.substitutionMap,
    arguments: Array(apply.arguments),
    isNonThrowing: apply.isNonThrowing,
    isNonAsync: apply.isNonAsync,
    specializationInfo: apply.specializationInfo
  )
  originalBuilder.createBranch(to: continuationBlock, arguments: [])

  for (index, alternative) in site.alternatives.enumerated() {
    let builder = index == 0
      ? dispatchBuilder
      : Builder(atEndOf: checkBlocks[index - 1], location: apply.location, context)
    let nextBlock = index + 1 < site.alternatives.count
      ? checkBlocks[index]
      : originalBlock
    let alternativeLiteral = builder.createIntegerLiteral(alternative.alternativeIndex, type: rawChoice.type)
    let isSelected = builder.createBuiltinBinaryFunction(
      name: "cmp_eq",
      operandType: rawChoice.type,
      resultType: context.getBuiltinIntegerType(bitWidth: 1),
      arguments: [rawChoice, alternativeLiteral]
    )
    builder.createCondBranch(
      condition: isSelected,
      trueBlock: alternativeBlocks[index],
      falseBlock: nextBlock
    )
  }

  context.erase(instruction: apply)
  return true
}
