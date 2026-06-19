//===--- SwiftmutLogicalConnector.swift ----------------------------------===//
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

let swiftmutChangeLogicalConnectorMutator = "CHANGE_LOGICAL_CONNECTOR"

/// A short-circuit diamond: a `cond_br` where one edge feeds a constant
/// Bool into the merge block (the short-circuit result of `||`/`&&`) and
/// the other edge evaluates the right-hand clause.
///
/// The mutation never restructures the diamond. XORing the branch condition
/// with the mutant-active flag takes the other edge, and XORing the
/// short-circuit constant with the same flag flips the merged result; the
/// two rewrites together turn `a || b` into `a && b` and back. The flag is
/// zero when the mutant is inactive, so both rewrites self-gate.
struct SwiftmutLogicalConnectorSite {
  let siteID: UInt64
  let runtimeFunctionName: String
  let module: String
  let function: String
  let file: String
  let line: Int
  let column: Int
  let branch: CondBranchInst
  let form: SwiftmutLogicalConnectorForm
  let alternatives: [SwiftmutLogicalConnectorAlternative]
}

enum SwiftmutLogicalConnectorForm {
  /// One edge of the branch feeds a constant Bool into the merge block.
  case diamond(
    /// The constant the chain short-circuits to: true for `||`, false for `&&`.
    constantValue: Bool,
    /// The constant as it appears in SIL, used to rebuild the flipped value
    /// with the same shape (bare `Builtin.Int1` or `struct $Bool`).
    constantOperand: Value,
    constantEdge: SwiftmutLogicalConnectorConstantEdge)
  /// Two consecutive `||` ladder rungs: the branch's false edge evaluates
  /// the next clause, whose branch shares the same then-target.
  case ladderPair(nextBranch: CondBranchInst)
}

enum SwiftmutLogicalConnectorConstantEdge {
  /// The constant travels as an argument of the `cond_br` itself.
  case branchArgument(operandIndex: Int)
  /// The constant travels through a dedicated single-predecessor block
  /// that forwards it to the merge.
  case forwardingBranch(BranchInst, operandIndex: Int)
}

struct SwiftmutLogicalConnectorAlternative {
  let mutantID: String
  let alternativeIndex: UInt32
  let mutation: SwiftmutMutation
}

struct SwiftmutLogicalConnectorDiscoveryStats {
  var diamondBranches = 0
  var ladderPairBranches = 0
  var conditionOwnedBranches = 0
  var mutationAlternatives = 0
  var sourceLocationMisses = 0
}

struct SwiftmutLogicalConnectorDiscoveryResult {
  let sites: [SwiftmutLogicalConnectorSite]
  let stats: SwiftmutLogicalConnectorDiscoveryStats
}

func swiftmutDiscoverLogicalConnectorSites(
  in function: Function,
  moduleName: String,
  conditionOwnedBranches: [CondBranchInst],
  config: SwiftmutConfig
) -> SwiftmutLogicalConnectorDiscoveryResult {
  var sites: [SwiftmutLogicalConnectorSite] = []
  var stats = SwiftmutLogicalConnectorDiscoveryStats()
  guard swiftmutMutatorIsEnabled(swiftmutChangeLogicalConnectorMutator, config: config) else {
    return SwiftmutLogicalConnectorDiscoveryResult(sites: sites, stats: stats)
  }

  let functionName = function.name.string
  var localOrdinal = 1
  var snippetOccurrences: [String: Int] = [:]

  func emitSite(
    branch: CondBranchInst,
    form: SwiftmutLogicalConnectorForm,
    sourceOriginal: String,
    computedValue: Value?,
    conditionOwned: Bool
  ) {
    let sourceMutated = sourceOriginal == "||" ? "&&" : "||"
    // Identical clause prefixes share a truncated snippet; the n-th branch
    // carrying a snippet maps to the n-th matching source line. Chained
    // clauses are data-dependent, so block order follows clause order.
    // Condition-owned branches still consume their occurrence so the
    // remaining branches keep pointing at their own clause lines.
    var occurrence = 0
    if let snippet = swiftmutLogicalConnectorSnippet(
      computedValue: computedValue,
      branch: branch,
      operatorText: sourceOriginal
    ) {
      occurrence = (snippetOccurrences[snippet] ?? 0) + 1
      snippetOccurrences[snippet] = occurrence
    }
    if conditionOwned {
      stats.conditionOwnedBranches += 1
      return
    }
    guard occurrence > 0,
          let location = swiftmutLogicalConnectorSourceLocation(
            computedValue: computedValue,
            branch: branch,
            function: function,
            operatorText: sourceOriginal,
            occurrence: occurrence,
            config: config
          ) else {
      stats.sourceLocationMisses += 1
      if stats.sourceLocationMisses <= 25 {
        swiftmutLogEvent(
          "logicalConnectorSourceLocationMiss",
          config: config,
          fields: [
            ("module", moduleName),
            ("function", functionName),
            ("branchLocation", branch.location.description),
            ("computedLocation", computedValue?.definingInstruction?.location.description ?? "<none>")
          ])
      }
      return
    }

    stats.mutationAlternatives += 1
    let mutation = SwiftmutMutation(
      originalID: nil,
      mutator: swiftmutChangeLogicalConnectorMutator,
      mutatedBuiltinName: sourceOriginal == "||" ? "logical_and" : "logical_or",
      sourceOriginal: sourceOriginal,
      sourceMutated: sourceMutated,
      silOriginal: sourceOriginal,
      silMutated: sourceMutated)
    let alternative = SwiftmutLogicalConnectorAlternative(
      mutantID: "local-logical-connector-\(localOrdinal)-1",
      alternativeIndex: 1,
      mutation: mutation)
    let siteID = swiftmutStableSiteID(
      packageRoot: config.packageRoot,
      module: moduleName,
      file: location.file,
      line: location.line,
      column: location.column,
      function: functionName,
      siteKind: "logicalConnector",
      localOrdinal: localOrdinal
    )
    localOrdinal += 1

    sites.append(SwiftmutLogicalConnectorSite(
      siteID: siteID,
      runtimeFunctionName: swiftmutRuntimeVisitThunkName(file: location.file, config: config),
      module: moduleName,
      function: functionName,
      file: location.file,
      line: location.line,
      column: location.column,
      branch: branch,
      form: form,
      alternatives: [alternative]
    ))
  }

  for block in function.blocks {
    guard let branch = block.terminator as? CondBranchInst else {
      continue
    }
    if let diamond = swiftmutLogicalConnectorDiamond(for: branch, in: function) {
      stats.diamondBranches += 1
      emitSite(
        branch: branch,
        form: .diamond(
          constantValue: diamond.constantValue,
          constantOperand: diamond.constantOperand,
          constantEdge: diamond.constantEdge),
        sourceOriginal: diamond.constantValue ? "||" : "&&",
        computedValue: diamond.computedValue,
        conditionOwned: conditionOwnedBranches.contains(where: { $0 === branch })
      )
      continue
    }
    if let nextBranch = swiftmutNextLadderRung(after: branch) {
      stats.ladderPairBranches += 1
      // Ladder injection only wraps condition values, so it composes with
      // condition-site injection on the same branch; nothing is owned.
      emitSite(
        branch: branch,
        form: .ladderPair(nextBranch: nextBranch),
        sourceOriginal: "||",
        computedValue: nextBranch.condition,
        conditionOwned: false
      )
    }
  }

  return SwiftmutLogicalConnectorDiscoveryResult(sites: sites, stats: stats)
}

/// A `||` ladder rung branches through a cleanup trampoline to the chain's
/// shared then-target, or falls through to the next clause. Consecutive
/// rungs sharing a then-target form a connector pair.
private func swiftmutNextLadderRung(after branch: CondBranchInst) -> CondBranchInst? {
  // The pass can visit a function more than once, and a wrapped ladder
  // still matches the ladder shape; an existing runtime-visit dispatch in
  // the rung's block means this connector is already instrumented.
  guard !swiftmutBlockContainsRuntimeVisitApply(branch.parentBlock),
        branch.trueOperands.isEmpty,
        let exitTarget = swiftmutLadderExitTarget(from: branch.trueBlock),
        branch.falseOperands.isEmpty else {
    return nil
  }

  var current = branch.falseBlock
  for _ in 0..<16 {
    if let candidate = current.terminator as? CondBranchInst {
      if candidate.trueOperands.isEmpty,
         swiftmutLadderExitTarget(from: candidate.trueBlock) === exitTarget {
        return candidate
      }
      // Inner guards of inlined stdlib code branch to no-return blocks;
      // the spine continues on the surviving side.
      let trueDead = swiftmutBlockEndsUnreachable(candidate.trueBlock)
      let falseDead = swiftmutBlockEndsUnreachable(candidate.falseBlock)
      if trueDead && !falseDead {
        current = candidate.falseBlock
        continue
      }
      if falseDead && !trueDead {
        current = candidate.trueBlock
        continue
      }
      return nil
    }
    guard let forwarding = current.terminator as? BranchInst else {
      return nil
    }
    current = forwarding.targetBlock
  }
  return nil
}

/// Resolves a rung's true edge through argument-less cleanup trampolines to
/// the block the chain exits into.
private func swiftmutLadderExitTarget(from block: BasicBlock) -> BasicBlock? {
  var current = block
  for _ in 0..<4 {
    guard swiftmutBlockOnlyCleansUp(current),
          let forwarding = current.terminator as? BranchInst,
          forwarding.operands.isEmpty else {
      return current
    }
    current = forwarding.targetBlock
  }
  return current
}

private func swiftmutBlockOnlyCleansUp(_ block: BasicBlock) -> Bool {
  for instruction in block.instructions {
    switch instruction {
    case is ReleaseValueInst, is StrongReleaseInst, is DestroyValueInst,
         is EndBorrowInst, is EndAccessInst, is DeallocStackInst,
         is DebugValueInst, is BranchInst:
      continue
    default:
      return false
    }
  }
  return true
}

private func swiftmutBlockEndsUnreachable(_ block: BasicBlock) -> Bool {
  block.terminator is UnreachableInst
}

private func swiftmutBlockContainsRuntimeVisitApply(_ block: BasicBlock) -> Bool {
  for instruction in block.instructions {
    if let apply = instruction as? ApplyInst,
       let functionRef = apply.callee as? FunctionRefInst,
       swiftmutIsRuntimeSupportFunctionName(functionRef.referencedFunction.name.string) {
      return true
    }
  }
  return false
}

private struct SwiftmutLogicalConnectorDiamond {
  let constantValue: Bool
  let constantOperand: Value
  let constantEdge: SwiftmutLogicalConnectorConstantEdge
  let computedValue: Value?
}

private enum SwiftmutShortCircuitEdge {
  case constant(
    merge: BasicBlock,
    value: Bool,
    operand: Value,
    edge: SwiftmutLogicalConnectorConstantEdge)
  case computed(merge: BasicBlock, value: Value?)
}

private func swiftmutLogicalConnectorDiamond(
  for branch: CondBranchInst,
  in function: Function
) -> SwiftmutLogicalConnectorDiamond? {
  guard let trueEdge = swiftmutShortCircuitEdge(
          branch: branch,
          target: branch.trueBlock,
          edgeOperands: branch.trueOperands,
          function: function
        ),
        let falseEdge = swiftmutShortCircuitEdge(
          branch: branch,
          target: branch.falseBlock,
          edgeOperands: branch.falseOperands,
          function: function
        ) else {
    return nil
  }

  switch (trueEdge, falseEdge) {
  case (.constant(let merge, let value, let operand, let edge),
        .computed(let otherMerge, let computed)),
       (.computed(let otherMerge, let computed),
        .constant(let merge, let value, let operand, let edge)):
    guard merge === otherMerge else {
      return nil
    }
    return SwiftmutLogicalConnectorDiamond(
      constantValue: value,
      constantOperand: operand,
      constantEdge: edge,
      computedValue: computed)
  default:
    return nil
  }
}

private func swiftmutShortCircuitEdge(
  branch: CondBranchInst,
  target: BasicBlock,
  edgeOperands: OperandArray,
  function: Function
) -> SwiftmutShortCircuitEdge? {
  if !edgeOperands.isEmpty {
    for operand in edgeOperands {
      if let constant = swiftmutShortCircuitConstantValue(operand.value, in: function) {
        return .constant(
          merge: target,
          value: constant,
          operand: operand.value,
          edge: .branchArgument(operandIndex: operand.index))
      }
    }
    return .computed(merge: target, value: edgeOperands.first?.value)
  }
  guard let forwarding = target.terminator as? BranchInst,
        !forwarding.operands.isEmpty else {
    return nil
  }
  for operand in forwarding.operands {
    if let constant = swiftmutShortCircuitConstantValue(operand.value, in: function),
       target.hasSinglePredecessor {
      return .constant(
        merge: forwarding.targetBlock,
        value: constant,
        operand: operand.value,
        edge: .forwardingBranch(forwarding, operandIndex: operand.index))
    }
  }
  return .computed(merge: forwarding.targetBlock, value: forwarding.operands.first?.value)
}

/// Only boolean constants qualify: the merged short-circuit result of a
/// logical chain is a `Bool` (or its `Builtin.Int1` payload), never any
/// other single-field integer struct such as `Int`.
private func swiftmutShortCircuitConstantValue(
  _ value: Value,
  in function: Function
) -> Bool? {
  if value is StructInst {
    guard swiftmutIsBoolType(value.type, in: function) else {
      return nil
    }
    return swiftmutBoolLiteralValue(value)
  }
  guard let literal = value as? IntegerLiteralInst,
        let literalValue = literal.value,
        literal.type.canonicalType.isBuiltinInteger(withFixedWidth: 1) else {
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

/// Chain branches carry no file position; the patched location description
/// quotes the leading source text of the clause instead (truncated, for
/// example `"|| combinedOutput.co[...]"`). The snippet starts with the
/// connector being mutated.
private func swiftmutLogicalConnectorSnippet(
  computedValue: Value?,
  branch: CondBranchInst,
  operatorText: String
) -> String? {
  var descriptions: [String] = []
  if let definingInstruction = computedValue?.definingInstruction {
    descriptions.append(definingInstruction.location.description)
    if let operandDefinition = definingInstruction.operands.first?.value.definingInstruction {
      descriptions.append(operandDefinition.location.description)
    }
  }
  descriptions.append(branch.location.description)

  for description in descriptions {
    guard let snippet = swiftmutQuotedSourceSnippetPrefix(description) else {
      continue
    }
    let trimmed = swiftmutTrimmedSnippet(snippet)
    if trimmed.hasPrefix(operatorText) {
      return trimmed
    }
  }
  return nil
}

private func swiftmutLogicalConnectorSourceLocation(
  computedValue: Value?,
  branch: CondBranchInst,
  function: Function,
  operatorText: String,
  occurrence: Int,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int)? {
  guard let functionSourceLocation = swiftmutFunctionSourceLocation(
    for: function,
    config: config
  ),
        let snippet = swiftmutLogicalConnectorSnippet(
          computedValue: computedValue,
          branch: branch,
          operatorText: operatorText
        ),
        let match = swiftmutFunctionBodyLine(
          startingWith: snippet,
          occurrence: occurrence,
          path: functionSourceLocation.path,
          functionLine: functionSourceLocation.line
        ),
        let operatorOffset = swiftmutByteOffset(of: operatorText, in: match.text) else {
    return nil
  }
  return (
    swiftmutTrimPackageRoot(functionSourceLocation.path, config: config),
    match.line,
    operatorOffset + 1
  )
}

private func swiftmutTrimmedSnippet(_ snippet: String) -> String {
  let bytes = Array(snippet.utf8)
  let start = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
  let end = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  guard start < end else {
    return ""
  }
  return String(decoding: bytes[start..<end], as: UTF8.self)
}

/// Finds the n-th line inside the function body whose trimmed text starts
/// with the snippet.
private func swiftmutFunctionBodyLine(
  startingWith snippet: String,
  occurrence: Int,
  path: String,
  functionLine: Int
) -> (line: Int, text: String)? {
  guard !snippet.isEmpty,
        occurrence > 0,
        let text = swiftmutRead(path) else {
    return nil
  }

  var seen = 0
  var braceDepth = 0
  var sawOpeningBrace = false
  for (number, lineText) in swiftmutNumberedSourceLines(text) {
    guard number >= functionLine else {
      continue
    }
    if braceDepth > 0,
       swiftmutTrimmedSnippet(lineText).hasPrefix(snippet) {
      seen += 1
      if seen == occurrence {
        return (number, lineText)
      }
    }
    for byte in lineText.utf8 {
      if byte == 123 {
        braceDepth += 1
        sawOpeningBrace = true
      } else if byte == 125 {
        braceDepth -= 1
      }
    }
    if sawOpeningBrace && braceDepth <= 0 {
      break
    }
  }
  return nil
}

private func swiftmutByteOffset(of pattern: String, in line: String) -> Int? {
  let bytes = Array(line.utf8)
  let patternBytes = Array(pattern.utf8)
  guard !patternBytes.isEmpty else {
    return nil
  }
  var index = 0
  while index + patternBytes.count <= bytes.count {
    var offset = 0
    while offset < patternBytes.count, bytes[index + offset] == patternBytes[offset] {
      offset += 1
    }
    if offset == patternBytes.count {
      return index
    }
    index += 1
  }
  return nil
}

func swiftmutInjectLogicalConnectorSite(
  _ site: SwiftmutLogicalConnectorSite,
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
        ),
        let alternative = site.alternatives.first else {
    return false
  }

  let builder = Builder(before: site.branch, context)
  let visitRef = builder.createFunctionRef(visitFunction)
  let choice = builder.createApply(
    function: visitRef,
    SubstitutionMap(),
    arguments: [siteID]
  )
  guard let rawChoice = swiftmutRuntimeChoiceRawValue(
    choice,
    builder: builder,
    function: site.branch.parentFunction
  ) else {
    return false
  }

  let conditionType = site.branch.condition.type
  let alternativeLiteral = builder.createIntegerLiteral(
    Int(alternative.alternativeIndex),
    type: rawChoice.type
  )
  let active = builder.createBuiltinBinaryFunction(
    name: "cmp_eq",
    operandType: rawChoice.type,
    resultType: conditionType,
    arguments: [rawChoice, alternativeLiteral]
  )

  switch site.form {
  case .diamond(let constantValue, let constantOperand, let constantEdge):
    let mutatedCondition = builder.createBuiltinBinaryFunction(
      name: "xor",
      operandType: conditionType,
      resultType: conditionType,
      arguments: [site.branch.condition, active]
    )
    let constantLiteral = builder.createIntegerLiteral(
      constantValue ? -1 : 0,
      type: conditionType
    )
    let toggledConstant = builder.createBuiltinBinaryFunction(
      name: "xor",
      operandType: conditionType,
      resultType: conditionType,
      arguments: [constantLiteral, active]
    )
    let replacementConstant: Value
    if constantOperand is StructInst {
      replacementConstant = builder.createStruct(
        type: constantOperand.type,
        elements: [toggledConstant]
      )
    } else {
      replacementConstant = toggledConstant
    }

    switch constantEdge {
    case .branchArgument(let operandIndex):
      site.branch.operands[operandIndex].set(to: replacementConstant, context)
    case .forwardingBranch(let forwarding, let operandIndex):
      forwarding.operands[operandIndex].set(to: replacementConstant, context)
    }
    site.branch.operands[0].set(to: mutatedCondition, context)
  case .ladderPair(let nextBranch):
    // `(a && b)` over two rungs: when active, rung k always falls through
    // into clause k+1, whose rung only stays true if a was. Wrapping the
    // condition values keeps the CFG intact and composes with neighboring
    // connector mutants and condition-site injection on the same branches.
    let trueLiteral = builder.createIntegerLiteral(-1, type: conditionType)
    let inactive = builder.createBuiltinBinaryFunction(
      name: "xor",
      operandType: conditionType,
      resultType: conditionType,
      arguments: [active, trueLiteral]
    )
    let rungCondition = site.branch.operands[0].value
    let mutatedCondition = builder.createBuiltinBinaryFunction(
      name: "and",
      operandType: conditionType,
      resultType: conditionType,
      arguments: [rungCondition, inactive]
    )
    site.branch.operands[0].set(to: mutatedCondition, context)

    let nextBuilder = Builder(before: nextBranch, context)
    let gate = nextBuilder.createBuiltinBinaryFunction(
      name: "or",
      operandType: conditionType,
      resultType: conditionType,
      arguments: [inactive, rungCondition]
    )
    let mutatedNextCondition = nextBuilder.createBuiltinBinaryFunction(
      name: "and",
      operandType: conditionType,
      resultType: conditionType,
      arguments: [nextBranch.operands[0].value, gate]
    )
    nextBranch.operands[0].set(to: mutatedNextCondition, context)
  }
  return true
}

func swiftmutLogicalConnectorSiteJSON(_ site: SwiftmutLogicalConnectorSite) -> String {
  var fields: [String] = []
  fields.append(#""siteID":\#(site.siteID)"#)
  fields.append(#""module":"\#(swiftmutEscapeJSON(site.module))""#)
  fields.append(#""function":"\#(swiftmutEscapeJSON(site.function))""#)
  if let demangledField = swiftmutDemangledFunctionJSONField(site.function) {
    fields.append(demangledField)
  }
  fields.append(
    #""sourceLocation":{"file":"\#(swiftmutEscapeJSON(site.file))","line":\#(site.line),"column":\#(site.column)}"#
  )
  fields.append(#""siteKind":"logicalConnector""#)
  fields.append(#""resultKind":"condition""#)
  fields.append(#""alternatives":[\#(site.alternatives.map(swiftmutLogicalConnectorAlternativeJSON).joined(separator: ","))]"#)
  return "{\(fields.joined(separator: ","))}"
}

private func swiftmutLogicalConnectorAlternativeJSON(
  _ alternative: SwiftmutLogicalConnectorAlternative
) -> String {
  swiftmutAlternativeJSON(
    mutantID: alternative.mutantID,
    alternativeIndex: alternative.alternativeIndex,
    mutation: alternative.mutation)
}
