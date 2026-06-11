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
    config: config
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
        || !voidCallSites.isEmpty else {
    return false
  }

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
  for site in arithmeticSites {
    if swiftmutInjectArithmeticSite(site, context) {
      injectedSiteJSON.append(swiftmutArithmeticSiteJSON(site))
      injectedArithmeticSites += 1
      changed = true
    }
  }
  for site in scalarValueSites {
    if swiftmutInjectScalarValueSite(site, context) {
      injectedSiteJSON.append(swiftmutScalarValueSiteJSON(site))
      injectedScalarValueSites += 1
      changed = true
    }
  }
  for site in valueApplySites {
    if swiftmutInjectValueApplySite(site, context) {
      injectedSiteJSON.append(swiftmutValueApplySiteJSON(site))
      injectedValueApplySites += 1
      changed = true
    }
  }
  for site in assignmentValueSites {
    if swiftmutInjectAssignmentValueSite(site, context) {
      injectedSiteJSON.append(swiftmutAssignmentValueSiteJSON(site))
      injectedAssignmentValueSites += 1
      changed = true
    }
  }
  for site in logicalConnectorSites {
    if swiftmutInjectLogicalConnectorSite(site, context) {
      injectedSiteJSON.append(swiftmutLogicalConnectorSiteJSON(site))
      injectedLogicalConnectorSites += 1
      changed = true
    }
  }
  for site in conditionSites {
    if swiftmutInjectConditionSite(site, context) {
      injectedSiteJSON.append(swiftmutConditionSiteJSON(site))
      injectedConditionSites += 1
      changed = true
    }
  }
  for site in returnSites {
    if swiftmutInjectReturnSite(site, context) {
      injectedSiteJSON.append(swiftmutReturnSiteJSON(site))
      injectedReturnSites += 1
      changed = true
    }
  }
  for site in returnBranchSites {
    if swiftmutInjectReturnBranchSite(site, context) {
      injectedSiteJSON.append(swiftmutReturnBranchSiteJSON(site))
      injectedReturnBranchSites += 1
      changed = true
    }
  }
  for site in voidCallSites {
    if swiftmutInjectVoidCallSite(site, context) {
      injectedSiteJSON.append(swiftmutVoidCallSiteJSON(site))
      injectedVoidCallSites += 1
      changed = true
    }
  }
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
    context
  )
  swiftmutLogEvent(
    "metamutantInjection",
    config: config,
      fields: [
      ("module", moduleName),
      ("function", function.name.string),
      ("attemptedConditionSites", "\(conditionSites.count)"),
      ("injectedConditionSites", "\(injectedConditionSites)"),
      ("attemptedLogicalConnectorSites", "\(logicalConnectorSites.count)"),
      ("injectedLogicalConnectorSites", "\(injectedLogicalConnectorSites)"),
      ("attemptedArithmeticSites", "\(arithmeticSites.count)"),
      ("injectedArithmeticSites", "\(injectedArithmeticSites)"),
      ("attemptedScalarValueSites", "\(scalarValueSites.count)"),
      ("injectedScalarValueSites", "\(injectedScalarValueSites)"),
      ("attemptedValueApplySites", "\(valueApplySites.count)"),
      ("injectedValueApplySites", "\(injectedValueApplySites)"),
      ("attemptedAssignmentValueSites", "\(assignmentValueSites.count)"),
      ("injectedAssignmentValueSites", "\(injectedAssignmentValueSites)"),
      ("attemptedReturnSites", "\(returnSites.count)"),
      ("injectedReturnSites", "\(injectedReturnSites)"),
      ("attemptedReturnBranchSites", "\(returnBranchSites.count)"),
      ("injectedReturnBranchSites", "\(injectedReturnBranchSites)"),
      ("attemptedVoidCallSites", "\(voidCallSites.count)"),
      ("injectedVoidCallSites", "\(injectedVoidCallSites)"),
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

