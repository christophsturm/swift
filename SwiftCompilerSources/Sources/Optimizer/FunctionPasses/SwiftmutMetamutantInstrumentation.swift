//===--- SwiftmutMetamutantInstrumentation.swift ----------------------------------------------===//
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

func swiftmutInstrumentMetamutantSites(
  in function: Function,
  moduleName: String,
  config: SwiftmutConfig,
  _ context: FunctionPassContext
) -> Bool {
  let conditionDiscovery = swiftmutDiscoverConditionSites(
    in: function,
    moduleName: moduleName,
    config: config
  )
  let conditionSites = conditionDiscovery.sites
  let logicalConnectorDiscovery = swiftmutDiscoverLogicalConnectorSites(
    in: function,
    moduleName: moduleName,
    conditionOwnedBranches: conditionSites.map(\.branch),
    config: config,
    context
  )
  let logicalConnectorSites = logicalConnectorDiscovery.sites
  let arithmeticSites = swiftmutDiscoverArithmeticSites(
    in: function,
    moduleName: moduleName,
    config: config
  )
  let scalarValueDiscovery = swiftmutDiscoverScalarValueSites(
    in: function,
    moduleName: moduleName,
    config: config
  )
  let scalarValueSites = scalarValueDiscovery.sites
  let valueApplyDiscovery = swiftmutDiscoverValueApplySites(
    in: function,
    moduleName: moduleName,
    config: config
  )
  let valueApplySites = valueApplyDiscovery.sites
  let assignmentValueDiscovery = swiftmutDiscoverAssignmentValueSites(
    in: function,
    moduleName: moduleName,
    config: config
  )
  let assignmentValueSites = assignmentValueDiscovery.sites
  let returnDiscovery = swiftmutDiscoverReturnSites(
    in: function,
    moduleName: moduleName,
    config: config
  )
  let returnSites = returnDiscovery.sites
  let returnBranchDiscovery = swiftmutDiscoverReturnBranchSites(
    in: function,
    moduleName: moduleName,
    config: config
  )
  let returnBranchSites = returnBranchDiscovery.sites
  let voidCallDiscovery = swiftmutDiscoverVoidCallSites(
    in: function,
    moduleName: moduleName,
    config: config
  )
  let voidCallSites = voidCallDiscovery.sites
  let statementDeletionDiscovery = swiftmutDiscoverStatementDeletionSites(
    in: function,
    moduleName: moduleName,
    config: config
  )
  let statementDeletionSites = statementDeletionDiscovery.sites
  swiftmutLogEvent(
    "metamutantDiscovery",
    config: config,
    fields: [
      ("module", moduleName),
      ("function", function.name.string),
      ("conditionBranches", "\(swiftmutConditionBranchCount(in: function))"),
      ("conditionSites", "\(conditionSites.count)"),
      ("conditionBranchesWithArguments", "\(conditionDiscovery.stats.branchesWithArguments)"),
      ("conditionComparisonBranches", "\(conditionDiscovery.stats.comparisonBranches)"),
      ("conditionGenericBranches", "\(conditionDiscovery.stats.genericBranches)"),
      ("conditionNoMutationBranches", "\(conditionDiscovery.stats.noMutationBranches)"),
      ("conditionMutationAlternatives", "\(conditionDiscovery.stats.mutationAlternatives)"),
      ("conditionSourceLocationMisses", "\(conditionDiscovery.stats.sourceLocationMisses)"),
      ("conditionGenericNonExplicitSourceLocations", "\(conditionDiscovery.stats.genericNonExplicitSourceLocations)"),
      ("logicalConnectorSites", "\(logicalConnectorSites.count)"),
      ("logicalConnectorDiamondBranches", "\(logicalConnectorDiscovery.stats.diamondBranches)"),
      ("logicalConnectorLadderPairBranches", "\(logicalConnectorDiscovery.stats.ladderPairBranches)"),
      ("logicalConnectorNonDominatingLadderPairBranches", "\(logicalConnectorDiscovery.stats.nonDominatingLadderPairBranches)"),
      ("logicalConnectorConditionOwnedBranches", "\(logicalConnectorDiscovery.stats.conditionOwnedBranches)"),
      ("logicalConnectorSourceLocationMisses", "\(logicalConnectorDiscovery.stats.sourceLocationMisses)"),
      ("arithmeticSites", "\(arithmeticSites.count)"),
      ("scalarValueSites", "\(scalarValueSites.count)"),
      ("scalarValueStructInstructions", "\(scalarValueDiscovery.stats.structInstructions)"),
      ("scalarValueMutationEligibleStructInstructions", "\(scalarValueDiscovery.stats.mutationEligibleStructInstructions)"),
      ("scalarValueMutationAlternatives", "\(scalarValueDiscovery.stats.mutationAlternatives)"),
      ("scalarValueSourceLocationMisses", "\(scalarValueDiscovery.stats.sourceLocationMisses)"),
      ("valueApplySites", "\(valueApplySites.count)"),
      ("valueApplyInstructions", "\(valueApplyDiscovery.stats.applyInstructions)"),
      ("valueApplyValueInstructions", "\(valueApplyDiscovery.stats.valueApplyInstructions)"),
      ("valueApplyMutationEligibleInstructions", "\(valueApplyDiscovery.stats.mutationEligibleApplyInstructions)"),
      ("valueApplyMutationAlternatives", "\(valueApplyDiscovery.stats.mutationAlternatives)"),
      ("valueApplySourceLocationMisses", "\(valueApplyDiscovery.stats.sourceLocationMisses)"),
      ("assignmentValueSites", "\(assignmentValueSites.count)"),
      ("assignmentValueStoreInstructions", "\(assignmentValueDiscovery.stats.storeInstructions)"),
      ("assignmentValueMutationEligibleInstructions", "\(assignmentValueDiscovery.stats.mutationEligibleStoreInstructions)"),
      ("assignmentValueMutationAlternatives", "\(assignmentValueDiscovery.stats.mutationAlternatives)"),
      ("assignmentValueSourceLocationMisses", "\(assignmentValueDiscovery.stats.sourceLocationMisses)"),
      ("voidCallSites", "\(voidCallSites.count)"),
      ("voidCallApplyInstructions", "\(voidCallDiscovery.stats.applyInstructions)"),
      ("voidCallVoidApplyInstructions", "\(voidCallDiscovery.stats.voidApplyInstructions)"),
      ("voidCallMutationEligibleApplyInstructions", "\(voidCallDiscovery.stats.mutationEligibleApplyInstructions)"),
      ("voidCallSourceLocationMisses", "\(voidCallDiscovery.stats.sourceLocationMisses)"),
      ("voidCallNonStatementSourceLocations", "\(voidCallDiscovery.stats.nonStatementSourceLocations)"),
      ("statementDeletionSites", "\(statementDeletionSites.count)"),
      ("statementDeletionStoreInstructions", "\(statementDeletionDiscovery.stats.storeInstructions)"),
      ("statementDeletionAssignmentStoreInstructions", "\(statementDeletionDiscovery.stats.assignmentStoreInstructions)"),
      ("statementDeletionMutationEligibleInstructions", "\(statementDeletionDiscovery.stats.mutationEligibleStoreInstructions)"),
      ("statementDeletionApplyInstructions", "\(statementDeletionDiscovery.stats.applyInstructions)"),
      ("statementDeletionUnusedResultApplyInstructions", "\(statementDeletionDiscovery.stats.unusedResultApplyInstructions)"),
      ("statementDeletionMutationEligibleApplyInstructions", "\(statementDeletionDiscovery.stats.mutationEligibleApplyInstructions)"),
      ("statementDeletionSourceLocationMisses", "\(statementDeletionDiscovery.stats.sourceLocationMisses)"),
      ("statementDeletionNonStatementSourceLocations", "\(statementDeletionDiscovery.stats.nonStatementSourceLocations)"),
      ("returnSites", "\(returnSites.count)"),
      ("returnTerminators", "\(returnDiscovery.stats.terminators)"),
      ("returnBoolTerminators", "\(returnDiscovery.stats.boolTerminators)"),
      ("returnOptionalTerminators", "\(returnDiscovery.stats.optionalTerminators)"),
      ("returnIntegerTerminators", "\(returnDiscovery.stats.integerTerminators)"),
      ("returnStringTerminators", "\(returnDiscovery.stats.stringTerminators)"),
      ("returnCollectionTerminators", "\(returnDiscovery.stats.collectionTerminators)"),
      ("returnOtherTerminators", "\(returnDiscovery.stats.otherTerminators)"),
      ("returnMutationEligibleTerminators", "\(returnDiscovery.stats.mutationEligibleTerminators)"),
      ("returnMutationAlternatives", "\(returnDiscovery.stats.mutationAlternatives)"),
      ("returnSourceLocationMisses", "\(returnDiscovery.stats.missingSourceLocations)"),
      ("returnBoolSourceLocationMisses", "\(returnDiscovery.stats.missingBoolSourceLocations)"),
      ("returnOptionalSourceLocationMisses", "\(returnDiscovery.stats.missingOptionalSourceLocations)"),
      ("returnIntegerSourceLocationMisses", "\(returnDiscovery.stats.missingIntegerSourceLocations)"),
      ("returnStringSourceLocationMisses", "\(returnDiscovery.stats.missingStringSourceLocations)"),
      ("returnCollectionSourceLocationMisses", "\(returnDiscovery.stats.missingCollectionSourceLocations)"),
      ("returnOtherSourceLocationMisses", "\(returnDiscovery.stats.missingOtherSourceLocations)"),
      ("returnNonStatementSourceLocations", "\(returnDiscovery.stats.nonStatementSourceLocations)"),
      ("returnBranchSites", "\(returnBranchSites.count)"),
      ("returnBranchBranches", "\(returnBranchDiscovery.stats.branches)"),
      ("returnBranchMutationEligibleBranches", "\(returnBranchDiscovery.stats.mutationEligibleBranches)"),
      ("returnBranchMutationAlternatives", "\(returnBranchDiscovery.stats.mutationAlternatives)"),
      ("returnBranchSourceLocationMisses", "\(returnBranchDiscovery.stats.sourceLocationMisses)")
    ])
  guard !conditionSites.isEmpty
        || !logicalConnectorSites.isEmpty
        || !arithmeticSites.isEmpty
        || !scalarValueSites.isEmpty
        || !valueApplySites.isEmpty
        || !assignmentValueSites.isEmpty
        || !returnSites.isEmpty
        || !returnBranchSites.isEmpty
        || !voidCallSites.isEmpty
        || !statementDeletionSites.isEmpty else {
    return false
  }

  // Freeze every manifest fragment and every fact-only observation before the
  // first injection can erase or replace a discovered SIL instruction.
  let preparedArithmeticSites = swiftmutPrepareManifestSites(
    arithmeticSites,
    serialize: swiftmutArithmeticSiteJSON
  )
  let preparedScalarValueSites = swiftmutPrepareManifestSites(
    scalarValueSites,
    serialize: swiftmutScalarValueSiteJSON
  )
  let preparedValueApplySites = swiftmutPrepareManifestSites(
    valueApplySites,
    serialize: swiftmutValueApplySiteJSON
  )
  let preparedAssignmentValueSites = swiftmutPrepareManifestSites(
    assignmentValueSites,
    serialize: swiftmutAssignmentValueSiteJSON
  )
  let preparedLogicalConnectorSites = swiftmutPrepareManifestSites(
    logicalConnectorSites,
    serialize: swiftmutLogicalConnectorSiteJSON
  )
  let preparedConditionSites = swiftmutPrepareManifestSites(
    conditionSites,
    serialize: swiftmutConditionSiteJSON
  )
  let preparedReturnSites = swiftmutPrepareManifestSites(
    returnSites,
    serialize: swiftmutReturnSiteJSON
  )
  let preparedReturnBranchSites = swiftmutPrepareManifestSites(
    returnBranchSites,
    serialize: swiftmutReturnBranchSiteJSON
  )
  let preparedVoidCallSites = swiftmutPrepareManifestSites(
    voidCallSites,
    serialize: swiftmutVoidCallSiteJSON
  )
  let preparedStatementDeletionSites = swiftmutPrepareManifestSites(
    statementDeletionSites,
    serialize: swiftmutStatementDeletionSiteJSON
  )
  let runtimeVisitAvailable = swiftmutAnyRuntimeVisitFunctionAvailable(
    conditionSites: conditionSites,
    logicalConnectorSites: logicalConnectorSites,
    arithmeticSites: arithmeticSites,
    scalarValueSites: scalarValueSites,
    valueApplySites: valueApplySites,
    assignmentValueSites: assignmentValueSites,
    returnSites: returnSites,
    returnBranchSites: returnBranchSites,
    voidCallSites: voidCallSites,
    statementDeletionSites: statementDeletionSites,
    originalFunction: function,
    context
  )
  let attemptedArithmeticSites = arithmeticSites.count
  let attemptedScalarValueSites = scalarValueSites.count
  let attemptedValueApplySites = valueApplySites.count
  let attemptedAssignmentValueSites = assignmentValueSites.count
  let attemptedLogicalConnectorSites = logicalConnectorSites.count
  let attemptedConditionSites = conditionSites.count
  let attemptedReturnSites = returnSites.count
  let attemptedReturnBranchSites = returnBranchSites.count
  let attemptedVoidCallSites = voidCallSites.count
  let attemptedStatementDeletionSites = statementDeletionSites.count

  var changed = false
  var injectedSiteJSON: [String] = []
  var injectedArithmeticSites = 0
  var injectedScalarValueSites = 0
  var injectedValueApplySites = 0
  var injectedAssignmentValueSites = 0
  var injectedConditionSites = 0
  var injectedLogicalConnectorSites = 0
  var injectedReturnSites = 0
  var injectedReturnBranchSites = 0
  var injectedVoidCallSites = 0
  var injectedStatementDeletionSites = 0
  for preparedSite in preparedArithmeticSites {
    if let manifestFragment = swiftmutManifestFragmentIfInjected(
      preparedSite,
      inject: { swiftmutInjectArithmeticSite($0, context) }
    ) {
      injectedSiteJSON.append(manifestFragment)
      injectedArithmeticSites += 1
      changed = true
    }
  }
  for preparedSite in preparedScalarValueSites {
    if let manifestFragment = swiftmutManifestFragmentIfInjected(
      preparedSite,
      inject: { swiftmutInjectScalarValueSite($0, context) }
    ) {
      injectedSiteJSON.append(manifestFragment)
      injectedScalarValueSites += 1
      changed = true
    }
  }
  for preparedSite in preparedValueApplySites {
    if let manifestFragment = swiftmutManifestFragmentIfInjected(
      preparedSite,
      inject: { swiftmutInjectValueApplySite($0, context) }
    ) {
      injectedSiteJSON.append(manifestFragment)
      injectedValueApplySites += 1
      changed = true
    }
  }
  for preparedSite in preparedAssignmentValueSites {
    if let manifestFragment = swiftmutManifestFragmentIfInjected(
      preparedSite,
      inject: { swiftmutInjectAssignmentValueSite($0, context) }
    ) {
      injectedSiteJSON.append(manifestFragment)
      injectedAssignmentValueSites += 1
      changed = true
    }
  }
  for preparedSite in preparedLogicalConnectorSites {
    if let manifestFragment = swiftmutManifestFragmentIfInjected(
      preparedSite,
      inject: { swiftmutInjectLogicalConnectorSite($0, context) }
    ) {
      injectedSiteJSON.append(manifestFragment)
      injectedLogicalConnectorSites += 1
      changed = true
    }
  }
  for preparedSite in preparedConditionSites {
    if let manifestFragment = swiftmutManifestFragmentIfInjected(
      preparedSite,
      inject: { swiftmutInjectConditionSite($0, context) }
    ) {
      injectedSiteJSON.append(manifestFragment)
      injectedConditionSites += 1
      changed = true
    }
  }
  for preparedSite in preparedReturnSites {
    if let manifestFragment = swiftmutManifestFragmentIfInjected(
      preparedSite,
      inject: { swiftmutInjectReturnSite($0, context) }
    ) {
      injectedSiteJSON.append(manifestFragment)
      injectedReturnSites += 1
      changed = true
    }
  }
  for preparedSite in preparedReturnBranchSites {
    if let manifestFragment = swiftmutManifestFragmentIfInjected(
      preparedSite,
      inject: { swiftmutInjectReturnBranchSite($0, context) }
    ) {
      injectedSiteJSON.append(manifestFragment)
      injectedReturnBranchSites += 1
      changed = true
    }
  }
  for preparedSite in preparedVoidCallSites {
    if let manifestFragment = swiftmutManifestFragmentIfInjected(
      preparedSite,
      inject: { swiftmutInjectVoidCallSite($0, context) }
    ) {
      injectedSiteJSON.append(manifestFragment)
      injectedVoidCallSites += 1
      changed = true
    }
  }
  for preparedSite in preparedStatementDeletionSites {
    if let manifestFragment = swiftmutManifestFragmentIfInjected(
      preparedSite,
      inject: { swiftmutInjectStatementDeletionSite($0, context) }
    ) {
      injectedSiteJSON.append(manifestFragment)
      injectedStatementDeletionSites += 1
      changed = true
    }
  }
  swiftmutLogEvent(
    "metamutantInjection",
    config: config,
      fields: [
      ("module", moduleName),
      ("function", function.name.string),
      ("attemptedConditionSites", "\(attemptedConditionSites)"),
      ("injectedConditionSites", "\(injectedConditionSites)"),
      ("attemptedLogicalConnectorSites", "\(attemptedLogicalConnectorSites)"),
      ("injectedLogicalConnectorSites", "\(injectedLogicalConnectorSites)"),
      ("attemptedArithmeticSites", "\(attemptedArithmeticSites)"),
      ("injectedArithmeticSites", "\(injectedArithmeticSites)"),
      ("attemptedScalarValueSites", "\(attemptedScalarValueSites)"),
      ("injectedScalarValueSites", "\(injectedScalarValueSites)"),
      ("attemptedValueApplySites", "\(attemptedValueApplySites)"),
      ("injectedValueApplySites", "\(injectedValueApplySites)"),
      ("attemptedAssignmentValueSites", "\(attemptedAssignmentValueSites)"),
      ("injectedAssignmentValueSites", "\(injectedAssignmentValueSites)"),
      ("attemptedReturnSites", "\(attemptedReturnSites)"),
      ("injectedReturnSites", "\(injectedReturnSites)"),
      ("attemptedReturnBranchSites", "\(attemptedReturnBranchSites)"),
      ("injectedReturnBranchSites", "\(injectedReturnBranchSites)"),
      ("attemptedVoidCallSites", "\(attemptedVoidCallSites)"),
      ("injectedVoidCallSites", "\(injectedVoidCallSites)"),
      ("attemptedStatementDeletionSites", "\(attemptedStatementDeletionSites)"),
      ("injectedStatementDeletionSites", "\(injectedStatementDeletionSites)"),
      ("runtimeVisitAvailable", "\(runtimeVisitAvailable)")
    ])
  if !injectedSiteJSON.isEmpty {
    swiftmutWriteMetamutantFragment(
      injectedSiteJSON,
      moduleName: moduleName,
      functionName: function.name.string,
      config: config
    )
  }
  return changed
}
