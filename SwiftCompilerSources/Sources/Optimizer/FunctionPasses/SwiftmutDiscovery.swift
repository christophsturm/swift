//===--- SwiftmutDiscovery.swift ----------------------------------------------===//
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

func swiftmutDiscoverVoidCallSites(
  in function: Function,
  moduleName: String,
  config: SwiftmutConfig
) -> SwiftmutVoidCallDiscoveryResult {
  var sites: [SwiftmutVoidCallSite] = []
  var stats = SwiftmutVoidCallDiscoveryStats()
  var localOrdinal = 1
  let functionName = function.name.string

  for block in function.blocks {
    for instruction in block.instructions {
      guard let apply = instruction as? ApplyInst else {
        continue
      }
      stats.applyInstructions += 1
      guard apply.type.isVoid else {
        continue
      }
      stats.voidApplyInstructions += 1
      guard let mutation = swiftmutVoidCallMutation(for: apply, config: config),
            swiftmutMutatorIsEnabled(mutation.mutator, config: config) else {
        continue
      }
      stats.mutationEligibleApplyInstructions += 1
      let location: (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)
      switch swiftmutVoidCallSourceLocation(
        for: apply,
        mutation: mutation,
        config: config
      ) {
      case .found(let file, let line, let column, let sourceOriginal, let sourceMutated):
        location = (file, line, column, sourceOriginal, sourceMutated)
      case .nonStatement:
        stats.nonStatementSourceLocations += 1
        continue
      case .missing:
        stats.sourceLocationMisses += 1
        continue
      }
      guard swiftmutSourceOriginalIsComplete(location.sourceOriginal) else {
        stats.sourceLocationMisses += 1
        continue
      }

      let displayMutation = mutation.withSource(
        original: location.sourceOriginal,
        mutated: location.sourceMutated
      )
      let siteID = swiftmutStableSiteID(
        packageRoot: config.packageRoot,
        module: moduleName,
        file: location.file,
        line: location.line,
        column: location.column,
        function: functionName,
        siteKind: "voidCall",
        localOrdinal: localOrdinal
      )
      sites.append(SwiftmutVoidCallSite(
        siteID: siteID,
        runtimeFunctionName: swiftmutRuntimeVisitThunkName(file: location.file, config: config),
        module: moduleName,
        function: functionName,
        file: location.file,
        line: location.line,
        column: location.column,
        apply: apply,
        alternatives: [
          SwiftmutVoidCallAlternative(
            mutantID: "local-void-call-\(localOrdinal)-1",
            alternativeIndex: 1,
            mutation: displayMutation
          )
        ]
      ))
      localOrdinal += 1
    }
  }

  return SwiftmutVoidCallDiscoveryResult(sites: sites, stats: stats)
}

func swiftmutDiscoverConditionSites(
  in function: Function,
  moduleName: String,
  config: SwiftmutConfig
) -> SwiftmutConditionDiscoveryResult {
  var sites: [SwiftmutConditionSite] = []
  var stats = SwiftmutConditionDiscoveryStats()
  var localOrdinal = 1
  let functionName = function.name.string

  for block in function.blocks {
    guard let branch = block.terminator as? CondBranchInst else {
      continue
    }
    stats.branches += 1
    if !branch.trueOperands.isEmpty || !branch.falseOperands.isEmpty {
      stats.branchesWithArguments += 1
    }

    var comparison: BuiltinInst?
    let mutations: [SwiftmutMutation]
    if let branchComparison = branch.condition as? BuiltinInst,
       swiftmutIsComparisonBuiltin(branchComparison) {
      stats.comparisonBranches += 1
      comparison = branchComparison
      mutations = swiftmutConditionSiteMutations(for: branchComparison, config: config)
    } else {
      stats.genericBranches += 1
      mutations = swiftmutGenericConditionSiteMutations(config: config)
    }
    guard !mutations.isEmpty else {
      stats.noMutationBranches += 1
      continue
    }
    stats.mutationAlternatives += mutations.count

    var alternatives: [SwiftmutConditionAlternative] = []
    var sourceLocation: (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)?
    for mutation in mutations {
      let location: (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)?
      if let comparison {
        location = swiftmutSourceLocation(
          for: comparison,
          branch: branch,
          function: function,
          moduleName: moduleName,
          mutation: mutation,
          config: config
        ) ?? swiftmutSourceLocation(
          for: comparison,
          function: function,
          moduleName: moduleName,
          mutation: mutation,
          config: config
        )
      } else {
        location = swiftmutBranchSourceLocation(
          for: branch,
          mutation: mutation,
          config: config)
        if let location,
           !swiftmutGenericConditionSourceLocationIsExplicit(location, config: config) {
          stats.genericNonExplicitSourceLocations += 1
          continue
        }
      }
      let resolvedLocation: (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)?
      if let location {
        resolvedLocation = location
      } else if mutation.sourceOriginal == "condition",
                let siteLocation = sourceLocation {
        resolvedLocation = (
          siteLocation.file,
          siteLocation.line,
          siteLocation.column,
          siteLocation.sourceOriginal,
          mutation.sourceMutated)
      } else {
        resolvedLocation = nil
      }
      guard let location = resolvedLocation else {
        if comparison != nil,
           let functionSourceLocation = swiftmutFunctionSourceLocation(for: function, config: config),
           !swiftmutFunctionBodyContainsExplicitCondition(
             path: functionSourceLocation.path,
             preferredLine: functionSourceLocation.line,
             config: config
           ) {
          stats.genericNonExplicitSourceLocations += 1
          continue
        }
        stats.sourceLocationMisses += 1
        if swiftmutConditionSourceLocationMissSamples < 500 {
          swiftmutConditionSourceLocationMissSamples += 1
          swiftmutLogConditionSourceLocationMiss(
            branch: branch,
            comparison: comparison,
            mutation: mutation,
            moduleName: moduleName,
            functionName: functionName,
            config: config
          )
        }
        continue
      }
      guard swiftmutSourceOriginalIsComplete(location.sourceOriginal) else {
        stats.sourceLocationMisses += 1
        continue
      }
      if sourceLocation == nil {
        sourceLocation = location
      } else if !swiftmutSourceLocationMatchesSite(location, sourceLocation!) {
        continue
      }
      let displayMutation = mutation.withSource(
        original: location.sourceOriginal,
        mutated: location.sourceMutated
      )
      alternatives.append(SwiftmutConditionAlternative(
        mutantID: "local-\(localOrdinal)-\(alternatives.count + 1)",
        alternativeIndex: UInt32(alternatives.count + 1),
        mutation: displayMutation
      ))
    }

    guard let location = sourceLocation, !alternatives.isEmpty else {
      continue
    }

    let siteID = swiftmutStableSiteID(
      packageRoot: config.packageRoot,
      module: moduleName,
      file: location.file,
      line: location.line,
      column: location.column,
      function: functionName,
      siteKind: "condition",
      localOrdinal: localOrdinal
    )
    localOrdinal += 1

    sites.append(SwiftmutConditionSite(
      siteID: siteID,
      runtimeFunctionName: swiftmutRuntimeVisitThunkName(file: location.file, config: config),
      module: moduleName,
      function: functionName,
      file: location.file,
      line: location.line,
      column: location.column,
      comparison: comparison,
      branch: branch,
      alternatives: alternatives
    ))
  }

  return SwiftmutConditionDiscoveryResult(sites: sites, stats: stats)
}

func swiftmutDiscoverReturnSites(
  in function: Function,
  moduleName: String,
  config: SwiftmutConfig
) -> SwiftmutReturnDiscoveryResult {
  var sites: [SwiftmutReturnSite] = []
  var stats = SwiftmutReturnDiscoveryStats()
  var localOrdinal = 1
  let functionName = function.name.string
  guard !functionName.hasSuffix("TW") else {
    return SwiftmutReturnDiscoveryResult(sites: [], stats: stats)
  }

  for block in function.blocks {
    guard let returnInst = block.terminator as? ReturnInst else {
      continue
    }
    stats.terminators += 1
    let returnType = returnInst.returnedValue.type
    swiftmutRecordReturnType(returnType, in: function, stats: &stats)
    guard returnType.isTrivial(in: function) else {
      continue
    }

    let mutations = swiftmutMetamutantReturnMutations(for: returnInst, config: config)
    guard !mutations.isEmpty else {
      continue
    }
    stats.mutationEligibleTerminators += 1
    stats.mutationAlternatives += mutations.count

    var alternatives: [SwiftmutReturnAlternative] = []
    var sourceLocation: (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)?
    for mutation in mutations {
      guard let location = swiftmutReturnSourceLocation(
        for: returnInst,
        mutation: mutation,
        config: config
      ) else {
        stats.missingSourceLocations += 1
        swiftmutRecordReturnSourceLocationMiss(returnType, in: function, stats: &stats)
        if stats.missingSourceLocationSamples < 500 {
          stats.missingSourceLocationSamples += 1
          swiftmutLogReturnSourceLocationMiss(
            returnInst: returnInst,
            mutation: mutation,
            returnType: returnType,
            moduleName: moduleName,
            functionName: functionName,
            config: config
          )
        }
        continue
      }
      if location.sourceOriginal == "return",
         !swiftmutReturnSourceLooksLikeStatement(file: location.file, line: location.line, config: config) {
        stats.nonStatementSourceLocations += 1
        continue
      }
      guard swiftmutSourceOriginalIsComplete(location.sourceOriginal) else {
        stats.missingSourceLocations += 1
        swiftmutRecordReturnSourceLocationMiss(returnType, in: function, stats: &stats)
        continue
      }
      if sourceLocation == nil {
        sourceLocation = location
      } else if !swiftmutSourceLocationMatchesSite(location, sourceLocation!) {
        continue
      }
      let displayMutation = mutation.withSource(
        original: location.sourceOriginal,
        mutated: location.sourceMutated
      )
      alternatives.append(SwiftmutReturnAlternative(
        mutantID: "local-return-\(localOrdinal)-\(alternatives.count + 1)",
        alternativeIndex: UInt32(alternatives.count + 1),
        mutation: displayMutation
      ))
    }

    guard let location = sourceLocation, !alternatives.isEmpty else {
      continue
    }

    let siteID = swiftmutStableSiteID(
      packageRoot: config.packageRoot,
      module: moduleName,
      file: location.file,
      line: location.line,
      column: location.column,
      function: functionName,
      siteKind: "returnValue",
      localOrdinal: localOrdinal
    )
    localOrdinal += 1

    sites.append(SwiftmutReturnSite(
      siteID: siteID,
      runtimeFunctionName: swiftmutRuntimeVisitThunkName(file: location.file, config: config),
      module: moduleName,
      function: functionName,
      file: location.file,
      line: location.line,
      column: location.column,
      returnInst: returnInst,
      alternatives: alternatives
    ))
  }

  return SwiftmutReturnDiscoveryResult(sites: sites, stats: stats)
}

func swiftmutDiscoverReturnBranchSites(
  in function: Function,
  moduleName: String,
  config: SwiftmutConfig
) -> SwiftmutReturnBranchDiscoveryResult {
  var sites: [SwiftmutReturnBranchSite] = []
  var stats = SwiftmutReturnBranchDiscoveryStats()
  var localOrdinal = 1
  let functionName = function.name.string
  guard !functionName.hasSuffix("TW") else {
    return SwiftmutReturnBranchDiscoveryResult(sites: [], stats: stats)
  }

  for block in function.blocks {
    guard let branch = block.terminator as? BranchInst,
          swiftmutBranchFeedsReturnValue(branch),
          let value = branch.operands.first?.value else {
      continue
    }
    stats.branches += 1
    let mutations = swiftmutReturnBranchMutations(for: branch, config: config)
    guard !mutations.isEmpty else {
      continue
    }
    stats.mutationEligibleBranches += 1
    stats.mutationAlternatives += mutations.count

    var alternatives: [SwiftmutReturnAlternative] = []
    var sourceLocation: (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)?
    for mutation in mutations {
      guard let location = swiftmutReturnBranchSourceLocation(
        for: branch,
        mutation: mutation,
        config: config
      ) else {
        stats.sourceLocationMisses += 1
        continue
      }
      guard swiftmutSourceOriginalIsComplete(location.sourceOriginal) else {
        stats.sourceLocationMisses += 1
        continue
      }
      if sourceLocation == nil {
        sourceLocation = location
      } else if !swiftmutSourceLocationMatchesSite(location, sourceLocation!) {
        continue
      }
      let displayMutation = mutation.withSource(
        original: location.sourceOriginal,
        mutated: location.sourceMutated
      )
      alternatives.append(SwiftmutReturnAlternative(
        mutantID: "local-return-branch-\(localOrdinal)-\(alternatives.count + 1)",
        alternativeIndex: UInt32(alternatives.count + 1),
        mutation: displayMutation
      ))
    }

    guard let location = sourceLocation, !alternatives.isEmpty else {
      continue
    }

    let siteID = swiftmutStableSiteID(
      packageRoot: config.packageRoot,
      module: moduleName,
      file: location.file,
      line: location.line,
      column: location.column,
      function: functionName,
      siteKind: "returnBranchValue",
      localOrdinal: localOrdinal
    )
    localOrdinal += 1

    sites.append(SwiftmutReturnBranchSite(
      siteID: siteID,
      runtimeFunctionName: swiftmutRuntimeVisitThunkName(file: location.file, config: config),
      module: moduleName,
      function: functionName,
      file: location.file,
      line: location.line,
      column: location.column,
      branch: branch,
      value: value,
      alternatives: alternatives
    ))
  }

  return SwiftmutReturnBranchDiscoveryResult(sites: sites, stats: stats)
}

func swiftmutBranchFeedsReturnValue(_ branch: BranchInst) -> Bool {
  guard branch.operands.count == 1,
        branch.targetBlock.arguments.count == 1,
        let returnInst = branch.targetBlock.terminator as? ReturnInst else {
    return false
  }
  return returnInst.returnedValue == branch.targetBlock.arguments[0]
}

func swiftmutDiscoverArithmeticSites(
  in function: Function,
  moduleName: String,
  config: SwiftmutConfig
) -> [SwiftmutArithmeticSite] {
  var sites: [SwiftmutArithmeticSite] = []
  var localOrdinal = 1
  let functionName = function.name.string

  for block in function.blocks {
    for instruction in block.instructions {
      guard let builtin = instruction as? BuiltinInst else {
        continue
      }
      let mutations = swiftmutArithmeticSiteMutations(for: builtin, config: config)
      guard !mutations.isEmpty else {
        continue
      }

      var alternatives: [SwiftmutArithmeticAlternative] = []
      var sourceLocation: (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)?
      for mutation in mutations {
        guard let location = swiftmutSourceLocation(
          for: builtin,
          function: function,
          moduleName: moduleName,
          mutation: mutation,
          config: config
        ) else {
          continue
        }
        guard swiftmutSourceOriginalIsComplete(location.sourceOriginal) else {
          continue
        }
        if sourceLocation == nil {
          sourceLocation = location
        } else if !swiftmutSourceLocationMatchesSite(location, sourceLocation!) {
          continue
        }
        let displayMutation = mutation.withSource(
          original: location.sourceOriginal,
          mutated: location.sourceMutated
        )
        alternatives.append(SwiftmutArithmeticAlternative(
          mutantID: "local-arithmetic-\(localOrdinal)-\(alternatives.count + 1)",
          alternativeIndex: UInt32(alternatives.count + 1),
          mutation: displayMutation
        ))
      }

      guard let location = sourceLocation, !alternatives.isEmpty else {
        continue
      }

      let siteID = swiftmutStableSiteID(
        packageRoot: config.packageRoot,
        module: moduleName,
        file: location.file,
        line: location.line,
        column: location.column,
        function: functionName,
        siteKind: "arithmetic",
        localOrdinal: localOrdinal
      )
      localOrdinal += 1

      sites.append(SwiftmutArithmeticSite(
        siteID: siteID,
        runtimeFunctionName: swiftmutRuntimeVisitThunkName(file: location.file, config: config),
        module: moduleName,
        function: functionName,
        file: location.file,
        line: location.line,
        column: location.column,
        builtin: builtin,
        alternatives: alternatives
      ))
    }
  }

  return sites
}

func swiftmutDiscoverScalarValueSites(
  in function: Function,
  moduleName: String,
  config: SwiftmutConfig
) -> SwiftmutScalarValueDiscoveryResult {
  var sites: [SwiftmutScalarValueSite] = []
  var stats = SwiftmutScalarValueDiscoveryStats()
  var localOrdinal = 1
  let functionName = function.name.string

  for block in function.blocks {
    for instruction in block.instructions {
      guard let structInst = instruction as? StructInst else {
        continue
      }
      stats.structInstructions += 1

      let mutations = swiftmutScalarValueMutations(for: structInst, config: config)
      guard !mutations.isEmpty else {
        continue
      }
      stats.mutationEligibleStructInstructions += 1
      stats.mutationAlternatives += mutations.count

      var alternatives: [SwiftmutScalarValueAlternative] = []
      var sourceLocation: (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)?
      for mutation in mutations {
        guard let location = swiftmutScalarValueSourceLocation(
          for: structInst,
          mutation: mutation,
          config: config
        ) else {
          stats.sourceLocationMisses += 1
          if stats.sourceLocationMissSamples < 500 {
            stats.sourceLocationMissSamples += 1
            swiftmutLogScalarValueSourceLocationMiss(
              value: structInst,
              mutation: mutation,
              moduleName: moduleName,
              functionName: functionName,
              config: config
            )
          }
          continue
        }
        guard swiftmutSourceOriginalIsComplete(location.sourceOriginal) else {
          stats.sourceLocationMisses += 1
          continue
        }
        if sourceLocation == nil {
          sourceLocation = location
        } else if !swiftmutSourceLocationMatchesSite(location, sourceLocation!) {
          continue
        }
        let displayMutation = mutation.withSource(
          original: location.sourceOriginal,
          mutated: location.sourceMutated
        )
        alternatives.append(SwiftmutScalarValueAlternative(
          mutantID: "local-scalar-value-\(localOrdinal)-\(alternatives.count + 1)",
          alternativeIndex: UInt32(alternatives.count + 1),
          mutation: displayMutation
        ))
      }

      guard let location = sourceLocation, !alternatives.isEmpty else {
        continue
      }

      let siteID = swiftmutStableSiteID(
        packageRoot: config.packageRoot,
        module: moduleName,
        file: location.file,
        line: location.line,
        column: location.column,
        function: functionName,
        siteKind: "scalarValue",
        localOrdinal: localOrdinal
      )
      localOrdinal += 1

      sites.append(SwiftmutScalarValueSite(
        siteID: siteID,
        runtimeFunctionName: swiftmutRuntimeVisitThunkName(file: location.file, config: config),
        module: moduleName,
        function: functionName,
        file: location.file,
        line: location.line,
        column: location.column,
        value: structInst,
        alternatives: alternatives
      ))
    }
  }

  return SwiftmutScalarValueDiscoveryResult(sites: sites, stats: stats)
}

func swiftmutDiscoverValueApplySites(
  in function: Function,
  moduleName: String,
  config: SwiftmutConfig
) -> SwiftmutValueApplyDiscoveryResult {
  var sites: [SwiftmutValueApplySite] = []
  var stats = SwiftmutValueApplyDiscoveryStats()
  var localOrdinal = 1
  let functionName = function.name.string

  for block in function.blocks {
    for instruction in block.instructions {
      guard let apply = instruction as? ApplyInst else {
        continue
      }
      stats.applyInstructions += 1
      guard !apply.type.isVoid else {
        continue
      }
      stats.valueApplyInstructions += 1
      guard apply.type.isTrivial(in: function) else {
        continue
      }
      guard swiftmutValueApplyCanBypassOriginalApply(apply) else {
        continue
      }

      let mutations = swiftmutValueReplacementMutations(
        for: apply,
        valueType: apply.type,
        config: config
      )
      guard !mutations.isEmpty else {
        continue
      }
      stats.mutationEligibleApplyInstructions += 1
      stats.mutationAlternatives += mutations.count

      var alternatives: [SwiftmutValueApplyAlternative] = []
      var sourceLocation: (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)?
      for mutation in mutations {
        guard let location = swiftmutValueApplySourceLocation(
          for: apply,
          mutation: mutation,
          config: config
        ) else {
          stats.sourceLocationMisses += 1
          if stats.sourceLocationMissSamples < 500 {
            stats.sourceLocationMissSamples += 1
            swiftmutLogValueApplySourceLocationMiss(
              apply: apply,
              mutation: mutation,
              moduleName: moduleName,
              functionName: functionName,
              config: config
            )
          }
          continue
        }
        if swiftmutValueApplyLocationConflictsWithClosureArgumentPredicate(
          location,
          mutation: mutation,
          config: config
        ) {
          continue
        }
        if swiftmutValueApplyLocationIsOwnedByExplicitCondition(location, config: config) {
          continue
        }
        guard swiftmutSourceOriginalIsComplete(location.sourceOriginal) else {
          stats.sourceLocationMisses += 1
          continue
        }
        if sourceLocation == nil {
          sourceLocation = location
        } else if !swiftmutSourceLocationMatchesSite(location, sourceLocation!) {
          continue
        }
        let displayMutation = mutation.withSource(
          original: location.sourceOriginal,
          mutated: location.sourceMutated
        )
        alternatives.append(SwiftmutValueApplyAlternative(
          mutantID: "local-value-apply-\(localOrdinal)-\(alternatives.count + 1)",
          alternativeIndex: UInt32(alternatives.count + 1),
          mutation: displayMutation
        ))
      }

      guard let location = sourceLocation, !alternatives.isEmpty else {
        continue
      }

      let siteID = swiftmutStableSiteID(
        packageRoot: config.packageRoot,
        module: moduleName,
        file: location.file,
        line: location.line,
        column: location.column,
        function: functionName,
        siteKind: "valueApply",
        localOrdinal: localOrdinal
      )
      localOrdinal += 1

      sites.append(SwiftmutValueApplySite(
        siteID: siteID,
        runtimeFunctionName: swiftmutRuntimeVisitThunkName(file: location.file, config: config),
        module: moduleName,
        function: functionName,
        file: location.file,
        line: location.line,
        column: location.column,
        apply: apply,
        alternatives: alternatives
      ))
    }
  }

  return SwiftmutValueApplyDiscoveryResult(sites: sites, stats: stats)
}

private func swiftmutValueApplyCanBypassOriginalApply(_ apply: ApplyInst) -> Bool {
  for argument in apply.argumentOperands {
    guard let convention = apply.convention(of: argument) else {
      return false
    }
    switch convention {
    case .directGuaranteed, .directUnowned, .packGuaranteed:
      guard argument.value.ownership != .owned else {
        return false
      }
      continue
    case .indirectInout, .indirectInoutAliasable, .packInout,
         .indirectIn, .indirectInGuaranteed, .indirectInCXX,
         .directOwned, .packOwned,
         .indirectOut, .packOut:
      return false
    }
  }
  return true
}

private func swiftmutValueApplyLocationIsOwnedByExplicitCondition(
  _ location: (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String),
  config: SwiftmutConfig
) -> Bool {
  guard let sourceLine = swiftmutSourceLine(file: location.file, line: location.line, config: config),
        let condition = swiftmutGenericConditionExpression(sourceLine) else {
    return false
  }
  return condition.sourceOriginal == location.sourceOriginal
}

private func swiftmutValueApplyLocationConflictsWithClosureArgumentPredicate(
  _ location: (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String),
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> Bool {
  guard let replacement = swiftmutClosureArgumentReturnReplacement(for: mutation),
        location.line > 0 else {
    return false
  }
  let path = location.file.hasPrefix("/")
    ? location.file
    : config.packageRoot + "/" + location.file
  guard let sourceLine = swiftmutAbsoluteSourceLine(path: path, line: location.line),
        let closureArgument = swiftmutClosureArgumentReturnExpression(
          sourceLine,
          replacement: replacement,
          mutation: mutation
        ) else {
    return false
  }
  return location.sourceOriginal != closureArgument.sourceOriginal
}

func swiftmutDiscoverAssignmentValueSites(
  in function: Function,
  moduleName: String,
  config: SwiftmutConfig
) -> SwiftmutAssignmentValueDiscoveryResult {
  var sites: [SwiftmutAssignmentValueSite] = []
  var stats = SwiftmutAssignmentValueDiscoveryStats()
  var localOrdinal = 1
  let functionName = function.name.string

  for block in function.blocks {
    for instruction in block.instructions {
      guard let store = instruction as? StoreInst else {
        continue
      }
      stats.storeInstructions += 1
      guard swiftmutAssignmentStoreIsEligible(store, config: config) else {
        continue
      }

      let mutations = swiftmutAssignmentValueMutations(for: store, config: config)
      guard !mutations.isEmpty else {
        continue
      }
      stats.mutationEligibleStoreInstructions += 1
      stats.mutationAlternatives += mutations.count
      let destinationNames = swiftmutAssignmentDestinationNames(for: store)
      let sourceNames = swiftmutAssignmentSourceNames(for: store)
      let targetNames = destinationNames.isEmpty
        ? swiftmutUniqueAssignmentNames(sourceNames)
        : swiftmutUniqueAssignmentNames(destinationNames)

      var alternatives: [SwiftmutAssignmentValueAlternative] = []
      var sourceLocation: (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)?
      for mutation in mutations {
        guard let location = swiftmutAssignmentValueSourceLocation(
          for: store,
          mutation: mutation,
          config: config
        ) else {
          stats.sourceLocationMisses += 1
          if stats.sourceLocationMissSamples < 500 {
            stats.sourceLocationMissSamples += 1
            swiftmutLogAssignmentValueSourceLocationMiss(
              store: store,
              mutation: mutation,
              moduleName: moduleName,
              functionName: functionName,
              destinationNames: destinationNames,
              sourceNames: sourceNames,
              targetNames: targetNames,
              config: config
            )
          }
          continue
        }
        guard swiftmutSourceOriginalIsComplete(location.sourceOriginal) else {
          stats.sourceLocationMisses += 1
          continue
        }
        if sourceLocation == nil {
          sourceLocation = location
        } else if !swiftmutSourceLocationMatchesSite(location, sourceLocation!) {
          continue
        }
        let displayMutation = mutation.withSource(
          original: location.sourceOriginal,
          mutated: location.sourceMutated
        )
        alternatives.append(SwiftmutAssignmentValueAlternative(
          mutantID: "local-assignment-value-\(localOrdinal)-\(alternatives.count + 1)",
          alternativeIndex: UInt32(alternatives.count + 1),
          mutation: displayMutation
        ))
      }

      guard let location = sourceLocation, !alternatives.isEmpty else {
        continue
      }

      let siteID = swiftmutStableSiteID(
        packageRoot: config.packageRoot,
        module: moduleName,
        file: location.file,
        line: location.line,
        column: location.column,
        function: functionName,
        siteKind: "assignmentValue",
        localOrdinal: localOrdinal
      )
      localOrdinal += 1

      sites.append(SwiftmutAssignmentValueSite(
        siteID: siteID,
        runtimeFunctionName: swiftmutRuntimeVisitThunkName(file: location.file, config: config),
        module: moduleName,
        function: functionName,
        file: location.file,
        line: location.line,
        column: location.column,
        store: store,
        alternatives: alternatives
      ))
    }
  }

  return SwiftmutAssignmentValueDiscoveryResult(sites: sites, stats: stats)
}
