//===--- Swiftmut.swift ----------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2026 swiftmut contributors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
import Darwin
#elseif os(Linux) || os(Android)
import Glibc
#endif

import AST
import SIL

private enum SwiftmutMode {
  case discover
  case apply
  case metamutant
}

private struct SwiftmutConditionMutationRule {
  let builtinID: String
  let mutator: String
  let mutatedBuiltinName: String
  let sourceOriginal: String
  let sourceMutated: String

  init?(wireFormat: String) {
    let fields = wireFormat.split(separator: "|", omittingEmptySubsequences: false).map { String($0) }
    guard fields.count == 5 else {
      return nil
    }
    builtinID = fields[0]
    mutator = fields[1]
    mutatedBuiltinName = fields[2]
    sourceOriginal = fields[3]
    sourceMutated = fields[4]
  }
}

private struct SwiftmutArithmeticMutationRule {
  let builtinID: String
  let mutatedBuiltinName: String
  let sourceOriginal: String
  let sourceMutated: String

  init?(wireFormat: String) {
    let fields = wireFormat.split(separator: "|", omittingEmptySubsequences: false).map { String($0) }
    guard fields.count == 4 else {
      return nil
    }
    builtinID = fields[0]
    mutatedBuiltinName = fields[1]
    sourceOriginal = fields[2]
    sourceMutated = fields[3]
  }
}

private struct SwiftmutContextualArithmeticMutationRule {
  let builtinID: String
  let context: String
  let mutator: String
  let mutatedBuiltinName: String
  let sourceOriginal: String
  let sourceMutated: String

  init?(wireFormat: String) {
    let fields = wireFormat.split(separator: "|", omittingEmptySubsequences: false).map { String($0) }
    guard fields.count == 6 else {
      return nil
    }
    builtinID = fields[0]
    context = fields[1]
    mutator = fields[2]
    mutatedBuiltinName = fields[3]
    sourceOriginal = fields[4]
    sourceMutated = fields[5]
  }
}

private struct SwiftmutReturnMutationRule {
  let context: String
  let mutator: String
  let mutatedBuiltinName: String
  let sourceOriginal: String
  let sourceMutated: String
  let silMutated: String

  init?(wireFormat: String) {
    let fields = wireFormat.split(separator: "|", omittingEmptySubsequences: false).map { String($0) }
    guard fields.count == 6 else {
      return nil
    }
    context = fields[0]
    mutator = fields[1]
    mutatedBuiltinName = fields[2]
    sourceOriginal = fields[3]
    sourceMutated = fields[4]
    silMutated = fields[5]
  }
}

private struct SwiftmutVoidCallMutationRule {
  let mutator: String
  let mutatedBuiltinName: String
  let sourceOriginal: String
  let sourceMutated: String
  let silMutated: String

  init?(wireFormat: String) {
    let fields = wireFormat.split(separator: "|", omittingEmptySubsequences: false).map { String($0) }
    guard fields.count == 5 else {
      return nil
    }
    mutator = fields[0]
    mutatedBuiltinName = fields[1]
    sourceOriginal = fields[2]
    sourceMutated = fields[3]
    silMutated = fields[4]
  }
}

private struct SwiftmutSourceMutationDisplayRule {
  let mutator: String
  let builtinID: String
  let sourceOriginal: String
  let sourceMutated: String
  let sourceMutatedOverride: String

  init(
    mutator: String,
    builtinID: String,
    sourceOriginal: String,
    sourceMutated: String,
    sourceMutatedOverride: String
  ) {
    self.mutator = mutator
    self.builtinID = builtinID
    self.sourceOriginal = sourceOriginal
    self.sourceMutated = sourceMutated
    self.sourceMutatedOverride = sourceMutatedOverride
  }

  init?(wireFormat: String) {
    let fields = wireFormat.split(separator: "|", omittingEmptySubsequences: false).map { String($0) }
    guard fields.count == 5 else {
      return nil
    }
    mutator = fields[0]
    builtinID = fields[1]
    sourceOriginal = fields[2]
    sourceMutated = fields[3]
    sourceMutatedOverride = fields[4]
  }
}

private struct SwiftmutConfig {
  static let defaultPath = ".swiftmut/session/compiler-config.json"

  let mode: SwiftmutMode
  let activeMutantID: String
  let mutantsPath: String
  let manifestFragmentsDirectory: String
  let compilerEventsPath: String
  let packageRoot: String
  let excludePathFragments: [String]
  let sourceFiles: [String]
  let enabledMutators: [String]
  let conditionMutationRules: [SwiftmutConditionMutationRule]
  let arithmeticMutationRules: [SwiftmutArithmeticMutationRule]
  let contextualArithmeticMutationRules: [SwiftmutContextualArithmeticMutationRule]
  let returnMutationRules: [SwiftmutReturnMutationRule]
  let voidCallMutationRules: [SwiftmutVoidCallMutationRule]
  let sourceMutationDisplayRules: [SwiftmutSourceMutationDisplayRule]

  static func load() -> SwiftmutConfig? {
    let configPath = swiftmutEnvironmentValue("SWIFTMUT_CONFIG") ?? Self.defaultPath
    guard let json = swiftmutRead(configPath),
          let rawMode = swiftmutJSONStringValue("mode", in: json) else {
      return nil
    }

    let mode: SwiftmutMode
    switch rawMode {
    case "discover":
      mode = .discover
    case "apply":
      mode = .apply
    case "metamutant":
      mode = .metamutant
    default:
      return nil
    }

    guard let mutantsPath = swiftmutJSONStringValue("manifestPath", in: json),
          !mutantsPath.isEmpty else {
      return nil
    }

    let activeMutantID = swiftmutJSONStringValue("activeMutantID", in: json) ?? ""
    let manifestFragmentsDirectory = swiftmutJSONStringValue("manifestFragmentsDirectory", in: json) ?? ""
    let compilerEventsPath = swiftmutJSONStringValue("compilerEventsPath", in: json) ?? ""
    let packageRoot = swiftmutJSONStringValue("packageRoot", in: json) ?? ""
    let excludePaths = swiftmutJSONStringArray("excludePaths", in: json)
    let sourceFiles = swiftmutJSONStringArray("sourceFiles", in: json)
    let enabledMutators = swiftmutJSONStringArray("enabledMutators", in: json)
    let conditionMutationRules = swiftmutJSONStringArray("conditionMutationRules", in: json).compactMap {
      SwiftmutConditionMutationRule(wireFormat: $0)
    }
    let arithmeticMutationRules = swiftmutJSONStringArray("arithmeticMutationRules", in: json).compactMap {
      SwiftmutArithmeticMutationRule(wireFormat: $0)
    }
    let contextualArithmeticMutationRules = swiftmutJSONStringArray("contextualArithmeticMutationRules", in: json).compactMap {
      SwiftmutContextualArithmeticMutationRule(wireFormat: $0)
    }
    let returnMutationRules = swiftmutJSONStringArray("returnMutationRules", in: json).compactMap {
      SwiftmutReturnMutationRule(wireFormat: $0)
    }
    let voidCallMutationRules = swiftmutJSONStringArray("voidCallMutationRules", in: json).compactMap {
      SwiftmutVoidCallMutationRule(wireFormat: $0)
    }
    let sourceMutationDisplayRules = swiftmutJSONStringArray("sourceMutationDisplayRules", in: json).compactMap {
      SwiftmutSourceMutationDisplayRule(wireFormat: $0)
    }

    return SwiftmutConfig(
      mode: mode,
      activeMutantID: activeMutantID,
      mutantsPath: mutantsPath,
      manifestFragmentsDirectory: manifestFragmentsDirectory,
      compilerEventsPath: compilerEventsPath,
      packageRoot: packageRoot,
      excludePathFragments: excludePaths,
      sourceFiles: sourceFiles,
      enabledMutators: enabledMutators,
      conditionMutationRules: conditionMutationRules,
      arithmeticMutationRules: arithmeticMutationRules,
      contextualArithmeticMutationRules: contextualArithmeticMutationRules,
      returnMutationRules: returnMutationRules,
      voidCallMutationRules: voidCallMutationRules,
      sourceMutationDisplayRules: sourceMutationDisplayRules)
  }
}

private func swiftmutEnvironmentValue(_ name: String) -> String? {
  #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(Linux) || os(Android)
  return name.withCString { namePointer in
    guard let valuePointer = getenv(namePointer) else {
      return nil
    }
    return String(cString: valuePointer)
  }
  #else
  return nil
  #endif
}

private struct SwiftmutMutation {
  let originalID: BuiltinInst.ID?
  let mutator: String
  let mutatedBuiltinName: String
  let sourceOriginal: String
  let sourceMutated: String
  let silOriginal: String
  let silMutated: String

  func withSource(original: String, mutated: String) -> SwiftmutMutation {
    SwiftmutMutation(
      originalID: originalID,
      mutator: mutator,
      mutatedBuiltinName: mutatedBuiltinName,
      sourceOriginal: original,
      sourceMutated: mutated,
      silOriginal: silOriginal,
      silMutated: silMutated)
  }
}

private struct SwiftmutCandidate {
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

private struct SwiftmutConditionAlternative {
  let mutantID: String
  let alternativeIndex: UInt32
  let mutation: SwiftmutMutation
}

private struct SwiftmutConditionSite {
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

private struct SwiftmutConditionDiscoveryStats {
  var branches = 0
  var branchesWithArguments = 0
  var comparisonBranches = 0
  var genericBranches = 0
  var noMutationBranches = 0
  var mutationAlternatives = 0
  var sourceLocationMisses = 0
  var genericNonExplicitSourceLocations = 0
}

private struct SwiftmutConditionDiscoveryResult {
  let sites: [SwiftmutConditionSite]
  let stats: SwiftmutConditionDiscoveryStats
}

private struct SwiftmutReturnAlternative {
  let mutantID: String
  let alternativeIndex: UInt32
  let mutation: SwiftmutMutation
}

private struct SwiftmutArithmeticAlternative {
  let mutantID: String
  let alternativeIndex: UInt32
  let mutation: SwiftmutMutation
}

private struct SwiftmutScalarValueAlternative {
  let mutantID: String
  let alternativeIndex: UInt32
  let mutation: SwiftmutMutation
}

private struct SwiftmutValueApplyAlternative {
  let mutantID: String
  let alternativeIndex: UInt32
  let mutation: SwiftmutMutation
}

private struct SwiftmutAssignmentValueAlternative {
  let mutantID: String
  let alternativeIndex: UInt32
  let mutation: SwiftmutMutation
}

private struct SwiftmutVoidCallAlternative {
  let mutantID: String
  let alternativeIndex: UInt32
  let mutation: SwiftmutMutation
}

private struct SwiftmutReturnSite {
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

private struct SwiftmutReturnBranchSite {
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

private struct SwiftmutReturnDiscoveryStats {
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

private struct SwiftmutReturnDiscoveryResult {
  let sites: [SwiftmutReturnSite]
  let stats: SwiftmutReturnDiscoveryStats
}

private struct SwiftmutReturnBranchDiscoveryStats {
  var branches = 0
  var mutationEligibleBranches = 0
  var mutationAlternatives = 0
  var sourceLocationMisses = 0
}

private struct SwiftmutReturnBranchDiscoveryResult {
  let sites: [SwiftmutReturnBranchSite]
  let stats: SwiftmutReturnBranchDiscoveryStats
}

private struct SwiftmutArithmeticSite {
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

private struct SwiftmutScalarValueSite {
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

private struct SwiftmutScalarValueDiscoveryStats {
  var structInstructions = 0
  var mutationEligibleStructInstructions = 0
  var mutationAlternatives = 0
  var sourceLocationMisses = 0
}

private struct SwiftmutScalarValueDiscoveryResult {
  let sites: [SwiftmutScalarValueSite]
  let stats: SwiftmutScalarValueDiscoveryStats
}

private struct SwiftmutValueApplySite {
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

private struct SwiftmutValueApplyDiscoveryStats {
  var applyInstructions = 0
  var valueApplyInstructions = 0
  var mutationEligibleApplyInstructions = 0
  var mutationAlternatives = 0
  var sourceLocationMisses = 0
}

private struct SwiftmutValueApplyDiscoveryResult {
  let sites: [SwiftmutValueApplySite]
  let stats: SwiftmutValueApplyDiscoveryStats
}

private struct SwiftmutAssignmentValueSite {
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

private struct SwiftmutAssignmentValueDiscoveryStats {
  var storeInstructions = 0
  var mutationEligibleStoreInstructions = 0
  var mutationAlternatives = 0
  var sourceLocationMisses = 0
  var sourceLocationMissSamples = 0
}

private struct SwiftmutAssignmentValueDiscoveryResult {
  let sites: [SwiftmutAssignmentValueSite]
  let stats: SwiftmutAssignmentValueDiscoveryStats
}

private struct SwiftmutVoidCallSite {
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

private struct SwiftmutVoidCallDiscoveryStats {
  var applyInstructions = 0
  var voidApplyInstructions = 0
  var mutationEligibleApplyInstructions = 0
  var sourceLocationMisses = 0
  var nonStatementSourceLocations = 0
}

private struct SwiftmutVoidCallDiscoveryResult {
  let sites: [SwiftmutVoidCallSite]
  let stats: SwiftmutVoidCallDiscoveryStats
}

private enum SwiftmutVoidCallSourceLocationResult {
  case found(file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)
  case nonStatement
  case missing
}

private var swiftmutNextOrdinal = 1
private var swiftmutHasTruncatedDiscoveryOutput = false

let swiftmut = FunctionPass(name: "swiftmut") {
  (function: Function, context: FunctionPassContext) in

  guard let config = SwiftmutConfig.load() else {
    return
  }

  let moduleName = context.currentModuleContext.name.string
  let shouldLogFunction = swiftmutShouldLog(function: function, moduleName: moduleName, config: config)
  let functionStartedAt = swiftmutClockMicroseconds()
  if shouldLogFunction {
    swiftmutLogEvent(
      "functionVisit",
      config: config,
      fields: [
        ("mode", swiftmutModeName(config.mode)),
        ("module", moduleName),
        ("function", function.name.string),
        ("location", function.location.description)
      ])
  }
  defer {
    if shouldLogFunction {
      let finishedAt = swiftmutClockMicroseconds()
      let durationUs = finishedAt >= functionStartedAt ? finishedAt - functionStartedAt : 0
      swiftmutLogEvent(
        "functionTiming",
        config: config,
        fields: [
          ("mode", swiftmutModeName(config.mode)),
          ("module", moduleName),
          ("function", function.name.string),
          ("durationUs", "\(durationUs)")
        ])
    }
  }

  guard swiftmutFunctionName(function.name.string, belongsToModule: moduleName) else {
    if shouldLogFunction {
      swiftmutLogEvent(
        "functionSkip",
        config: config,
        fields: [
          ("reason", "moduleNameMismatch"),
          ("module", moduleName),
          ("function", function.name.string)
        ])
    }
    return
  }

  if let exclusionReason = swiftmutExclusionReason(function: function, config: config) {
    if shouldLogFunction {
      swiftmutLogEvent(
        "functionSkip",
        config: config,
        fields: [
          ("reason", exclusionReason),
          ("module", moduleName),
          ("function", function.name.string)
        ])
    }
    return
  }

  if config.mode == .metamutant {
    if swiftmutInstrumentMetamutantSites(
      in: function,
      moduleName: moduleName,
      config: config,
      context
    ) {
      context.notifyInstructionsChanged()
    }
    return
  }

  let functionName = function.name.string
  var changed = false

  for block in function.blocks {
    for instruction in block.instructions {
      guard let builtin = instruction as? BuiltinInst else {
        if let returnInst = instruction as? ReturnInst {
          for mutation in swiftmutReturnMutations(for: returnInst, config: config) {
            guard swiftmutMutatorIsEnabled(mutation.mutator, config: config) else {
              continue
            }
            guard let sourceLocation = swiftmutReturnSourceLocation(
              for: returnInst,
              mutation: mutation,
              config: config
            ) else {
              continue
            }

            let id = swiftmutFormatMutantID(swiftmutNextOrdinal)
            swiftmutNextOrdinal += 1
            let candidate = SwiftmutCandidate(
              id: id,
              module: moduleName,
              function: functionName,
              file: sourceLocation.file,
              line: sourceLocation.line,
              column: sourceLocation.column,
              mutation: mutation.withSource(
                original: sourceLocation.sourceOriginal,
                mutated: sourceLocation.sourceMutated))

            switch config.mode {
            case .discover:
              if !swiftmutHasTruncatedDiscoveryOutput {
                swiftmutCreateParentDirectories(forFile: config.mutantsPath)
                swiftmutWrite("", to: config.mutantsPath, append: false)
                swiftmutHasTruncatedDiscoveryOutput = true
              }
              swiftmutWrite(candidate.jsonLine, to: config.mutantsPath, append: true)
            case .apply:
              if candidate.id == config.activeMutantID {
                swiftmutApplyReturn(mutation: mutation, to: returnInst, context)
                changed = true
              }
            case .metamutant:
              break
            }
          }
        }
        if let apply = instruction as? ApplyInst,
           let mutation = swiftmutVoidCallMutation(for: apply, config: config),
           swiftmutMutatorIsEnabled(mutation.mutator, config: config),
           let sourceLocation = swiftmutInstructionSourceLocation(
            for: apply,
            mutation: mutation,
            config: config
           ) {
          let id = swiftmutFormatMutantID(swiftmutNextOrdinal)
          swiftmutNextOrdinal += 1
          let candidate = SwiftmutCandidate(
            id: id,
            module: moduleName,
            function: functionName,
            file: sourceLocation.file,
            line: sourceLocation.line,
            column: sourceLocation.column,
            mutation: mutation.withSource(
              original: sourceLocation.sourceOriginal,
              mutated: sourceLocation.sourceMutated))

          switch config.mode {
          case .discover:
            if !swiftmutHasTruncatedDiscoveryOutput {
              swiftmutCreateParentDirectories(forFile: config.mutantsPath)
              swiftmutWrite("", to: config.mutantsPath, append: false)
              swiftmutHasTruncatedDiscoveryOutput = true
            }
            swiftmutWrite(candidate.jsonLine, to: config.mutantsPath, append: true)
          case .apply:
            if candidate.id == config.activeMutantID {
              context.erase(instruction: apply)
              changed = true
            }
          case .metamutant:
            break
          }
        }
        continue
      }

      for mutation in swiftmutMutations(for: builtin, config: config) {
        guard swiftmutMutatorIsEnabled(mutation.mutator, config: config) else {
          continue
        }
        guard let sourceLocation = swiftmutSourceLocation(
          for: builtin,
          function: function,
          moduleName: moduleName,
          mutation: mutation,
          config: config
        ) else {
          continue
        }

        let id = swiftmutFormatMutantID(swiftmutNextOrdinal)
        swiftmutNextOrdinal += 1

        let displayMutation = sourceLocation.sourceOriginal.isEmpty
          ? mutation
          : mutation.withSource(
            original: sourceLocation.sourceOriginal,
            mutated: sourceLocation.sourceMutated)
        let candidate = SwiftmutCandidate(
          id: id,
          module: moduleName,
          function: functionName,
          file: sourceLocation.file,
          line: sourceLocation.line,
          column: sourceLocation.column,
          mutation: displayMutation)

        switch config.mode {
        case .discover:
          if !swiftmutHasTruncatedDiscoveryOutput {
            swiftmutCreateParentDirectories(forFile: config.mutantsPath)
            swiftmutWrite("", to: config.mutantsPath, append: false)
            swiftmutHasTruncatedDiscoveryOutput = true
          }
          swiftmutWrite(candidate.jsonLine, to: config.mutantsPath, append: true)
        case .apply:
          if candidate.id == config.activeMutantID {
            swiftmutApply(mutation: mutation, to: builtin, context)
            changed = true
          }
        case .metamutant:
          break
        }
      }
    }
  }

  if changed {
    context.notifyInstructionsChanged()
  }
}

private func swiftmutInstrumentMetamutantSites(
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

private func swiftmutDiscoverVoidCallSites(
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

private func swiftmutDiscoverConditionSites(
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
          function: function,
          moduleName: moduleName,
          mutation: mutation,
          config: config)
      } else {
        location = swiftmutBranchSourceLocation(
          for: branch,
          mutation: mutation,
          config: config)
        if let location,
           !swiftmutGenericConditionSourceIsExplicit(file: location.file, line: location.line, config: config) {
          stats.genericNonExplicitSourceLocations += 1
          continue
        }
      }
      guard let location else {
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

private func swiftmutDiscoverReturnSites(
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

private func swiftmutDiscoverReturnBranchSites(
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

private func swiftmutBranchFeedsReturnValue(_ branch: BranchInst) -> Bool {
  guard branch.operands.count == 1,
        branch.targetBlock.arguments.count == 1,
        let returnInst = branch.targetBlock.terminator as? ReturnInst else {
    return false
  }
  return returnInst.returnedValue == branch.targetBlock.arguments[0]
}

private func swiftmutDiscoverArithmeticSites(
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

private func swiftmutDiscoverScalarValueSites(
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

private func swiftmutDiscoverValueApplySites(
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

private func swiftmutDiscoverAssignmentValueSites(
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

private func swiftmutSourceLocationMatchesSite(
  _ candidate: (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String),
  _ site: (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)
) -> Bool {
  candidate.file == site.file
    && candidate.line == site.line
    && candidate.column == site.column
    && candidate.sourceOriginal == site.sourceOriginal
}

private func swiftmutMetamutantReturnMutations(
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

private func swiftmutScalarValueMutations(
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

private func swiftmutValueReplacementMutations(
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

private func swiftmutReturnBranchMutations(
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

private func swiftmutAssignmentValueMutations(
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
  )
}

private func swiftmutCanDispatchAssignmentValue(_ store: StoreInst) -> Bool {
  store.source.type.isTrivial(in: store.parentFunction) || store.source.ownership == .owned
}

private func swiftmutAssignmentStoreIsEligible(_ store: StoreInst, config: SwiftmutConfig) -> Bool {
  guard !store.source.type.isAddress else {
    return false
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

private func swiftmutScalarValueHasMappedSource(_ value: StructInst, config: SwiftmutConfig) -> Bool {
  for mutation in swiftmutScalarValueMutations(for: value, config: config) {
    if swiftmutScalarValueSourceLocation(for: value, mutation: mutation, config: config) != nil {
      return true
    }
  }
  return false
}

private func swiftmutValueApplyHasMappedSource(_ apply: ApplyInst, config: SwiftmutConfig) -> Bool {
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

private func swiftmutValueReplacementMutations(
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

private func swiftmutConditionBranchCount(in function: Function) -> Int {
  var count = 0
  for block in function.blocks {
    if block.terminator is CondBranchInst {
      count += 1
    }
  }
  return count
}

private func swiftmutConditionSiteMutations(
  for builtin: BuiltinInst,
  config: SwiftmutConfig
) -> [SwiftmutMutation] {
  swiftmutConditionMutations(for: builtin, config: config, includeGenericComparisonRules: true)
}

private func swiftmutGenericConditionSiteMutations(
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

private func swiftmutConditionMutations(
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

private func swiftmutArithmeticSiteMutations(
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

private func swiftmutComparisonBuiltinIDName(_ builtin: BuiltinInst) -> String? {
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

private func swiftmutIsComparisonBuiltin(_ builtin: BuiltinInst) -> Bool {
  switch builtin.id {
  case .ICMP_EQ, .ICMP_NE,
       .ICMP_SGE, .ICMP_SGT, .ICMP_SLE, .ICMP_SLT,
       .ICMP_UGE, .ICMP_UGT, .ICMP_ULE, .ICMP_ULT:
    return true
  default:
    return false
  }
}

private func swiftmutInjectConditionSite(
  _ site: SwiftmutConditionSite,
  _ context: FunctionPassContext
) -> Bool {
  guard let visitFunction = swiftmutRuntimeVisitFunction(named: site.runtimeFunctionName, context),
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

private func swiftmutInjectReturnSite(
  _ site: SwiftmutReturnSite,
  _ context: FunctionPassContext
) -> Bool {
  guard let visitFunction = swiftmutRuntimeVisitFunction(named: site.runtimeFunctionName, context),
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
  guard site.alternatives.allSatisfy({
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

  let originalValue = site.returnInst.returnedValue
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

private func swiftmutInjectReturnBranchSite(
  _ site: SwiftmutReturnBranchSite,
  _ context: FunctionPassContext
) -> Bool {
  guard let visitFunction = swiftmutRuntimeVisitFunction(named: site.runtimeFunctionName, context),
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

private func swiftmutInjectArithmeticSite(
  _ site: SwiftmutArithmeticSite,
  _ context: FunctionPassContext
) -> Bool {
  guard let visitFunction = swiftmutRuntimeVisitFunction(named: site.runtimeFunctionName, context),
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

private func swiftmutInjectScalarValueSite(
  _ site: SwiftmutScalarValueSite,
  _ context: FunctionPassContext
) -> Bool {
  guard let visitFunction = swiftmutRuntimeVisitFunction(named: site.runtimeFunctionName, context),
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

private func swiftmutInjectValueApplySite(
  _ site: SwiftmutValueApplySite,
  _ context: FunctionPassContext
) -> Bool {
  guard let visitFunction = swiftmutRuntimeVisitFunction(named: site.runtimeFunctionName, context),
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
  let continuationBlock = context.splitBlock(before: site.apply)
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
  let originalValue = originalBuilder.createApply(
    function: site.apply.callee,
    site.apply.substitutionMap,
    arguments: Array(site.apply.arguments),
    isNonThrowing: site.apply.isNonThrowing,
    isNonAsync: site.apply.isNonAsync,
    specializationInfo: site.apply.specializationInfo
  )
  originalBuilder.createBranch(to: continuationBlock, arguments: [originalValue])

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

  site.apply.replace(with: selectedValue, context)
  return true
}

private func swiftmutInjectAssignmentValueSite(
  _ site: SwiftmutAssignmentValueSite,
  _ context: FunctionPassContext
) -> Bool {
  guard let visitFunction = swiftmutRuntimeVisitFunction(named: site.runtimeFunctionName, context),
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

private func swiftmutInjectVoidCallSite(
  _ site: SwiftmutVoidCallSite,
  _ context: FunctionPassContext
) -> Bool {
  guard let visitFunction = swiftmutRuntimeVisitFunction(named: site.runtimeFunctionName, context),
        let siteID = swiftmutMakeRuntimeSiteID(
          site.siteID,
          visitFunction: visitFunction,
          insertionPoint: site.apply,
          context
        ) else {
    return false
  }

  let function = site.apply.parentFunction
  let dispatchBlock = site.apply.parentBlock
  let continuationBlock = context.splitBlock(after: site.apply)
  let callBlock = context.splitBlock(before: site.apply)
  let alternativeBlocks = site.alternatives.map { _ in function.appendNewBlock(context) }
  let checkBlocks = site.alternatives.dropFirst().map { _ in function.appendNewBlock(context) }

  let dispatchBuilder = Builder(atEndOf: dispatchBlock, location: site.apply.location, context)
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
    Builder(atEndOf: alternativeBlocks[index], location: site.apply.location, context)
      .createBranch(to: continuationBlock)
  }
  Builder(atEndOf: callBlock, location: site.apply.location, context)
    .createBranch(to: continuationBlock)

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

  return true
}

private func swiftmutRuntimeVisitFunction(_ context: FunctionPassContext) -> Function? {
  context.lookupFunction(name: "__swiftmut_visit")
    ?? context.lookupFunction(name: "@__swiftmut_visit")
    ?? context.loadFunction(name: "__swiftmut_visit", loadCalleesRecursively: false)
    ?? context.loadFunction(name: "@__swiftmut_visit", loadCalleesRecursively: false)
}

private func swiftmutRuntimeVisitFunction(
  named functionName: String,
  _ context: FunctionPassContext
) -> Function? {
  context.lookupFunction(name: functionName)
    ?? context.lookupFunction(name: "@\(functionName)")
    ?? swiftmutRuntimeVisitFunction(context)
}

private func swiftmutAnyRuntimeVisitFunctionAvailable(
  conditionSites: [SwiftmutConditionSite],
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

private func swiftmutRuntimeVisitThunkName(file: String, config: SwiftmutConfig) -> String {
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

private func swiftmutCanMakeReturnAlternative(
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

private func swiftmutMakeReturnAlternative(
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

private func swiftmutMakeConditionAlternative(
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

private func swiftmutCreateConditionBranch(
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

private func swiftmutMakeRuntimeSiteID(
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

private func swiftmutRuntimeChoiceRawValue(
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

private func swiftmutWriteMetamutantFragment(
  _ siteJSON: [String],
  moduleName: String,
  functionName: String,
  config: SwiftmutConfig
) {
  guard !config.manifestFragmentsDirectory.isEmpty else {
    return
  }

  var output = #"{"sites":["#
  for (siteIndex, site) in siteJSON.enumerated() {
    if siteIndex != 0 {
      output += ","
    }
    output += site
  }
  output += "]}\n"

  let path = config.manifestFragmentsDirectory
    + "/"
    + swiftmutSanitizeFileComponent(moduleName)
    + "-"
    + "\(swiftmutProcessID())"
    + "-"
    + swiftmutHex(swiftmutStableHash(functionName))
    + ".json"
  swiftmutCreateParentDirectories(forFile: path)
  swiftmutWrite(output, to: path, append: false)
}

private func swiftmutConditionSiteJSON(_ site: SwiftmutConditionSite) -> String {
  var fields: [String] = []
  fields.append(#""siteID":\#(site.siteID)"#)
  fields.append(#""module":"\#(swiftmutEscapeJSON(site.module))""#)
  fields.append(#""function":"\#(swiftmutEscapeJSON(site.function))""#)
  fields.append(
    #""sourceLocation":{"file":"\#(swiftmutEscapeJSON(site.file))","line":\#(site.line),"column":\#(site.column)}"#
  )
  fields.append(#""siteKind":"condition""#)
  fields.append(#""resultKind":"condition""#)
  var alternatives: [String] = []
  for alternative in site.alternatives {
    alternatives.append(swiftmutConditionAlternativeJSON(alternative))
  }
  fields.append(#""alternatives":[\#(alternatives.joined(separator: ","))]"#)
  return "{\(fields.joined(separator: ","))}"
}

private func swiftmutConditionAlternativeJSON(_ alternative: SwiftmutConditionAlternative) -> String {
  var fields: [String] = []
  fields.append(#""mutantID":"\#(swiftmutEscapeJSON(alternative.mutantID))""#)
  fields.append(#""alternativeIndex":\#(alternative.alternativeIndex)"#)
  fields.append(#""mutator":"\#(swiftmutEscapeJSON(alternative.mutation.mutator))""#)
  fields.append(#""sourceOriginal":"\#(swiftmutEscapeJSON(alternative.mutation.sourceOriginal))""#)
  fields.append(#""sourceMutated":"\#(swiftmutEscapeJSON(alternative.mutation.sourceMutated))""#)
  fields.append(#""behaviorKey":"\#(swiftmutEscapeJSON(alternative.mutation.silMutated))""#)
  return "{\(fields.joined(separator: ","))}"
}

private func swiftmutArithmeticSiteJSON(_ site: SwiftmutArithmeticSite) -> String {
  var fields: [String] = []
  fields.append(#""siteID":\#(site.siteID)"#)
  fields.append(#""module":"\#(swiftmutEscapeJSON(site.module))""#)
  fields.append(#""function":"\#(swiftmutEscapeJSON(site.function))""#)
  fields.append(#""sourceLocation":{"file":"\#(swiftmutEscapeJSON(site.file))","line":\#(site.line),"column":\#(site.column)}"#)
  fields.append(#""siteKind":"arithmetic""#)
  fields.append(#""resultKind":"value""#)
  fields.append(#""alternatives":[\#(site.alternatives.map(swiftmutArithmeticAlternativeJSON).joined(separator: ","))]"#)
  return "{\(fields.joined(separator: ","))}"
}

private func swiftmutArithmeticAlternativeJSON(_ alternative: SwiftmutArithmeticAlternative) -> String {
  var fields: [String] = []
  fields.append(#""mutantID":"\#(swiftmutEscapeJSON(alternative.mutantID))""#)
  fields.append(#""alternativeIndex":\#(alternative.alternativeIndex)"#)
  fields.append(#""mutator":"\#(swiftmutEscapeJSON(alternative.mutation.mutator))""#)
  fields.append(#""sourceOriginal":"\#(swiftmutEscapeJSON(alternative.mutation.sourceOriginal))""#)
  fields.append(#""sourceMutated":"\#(swiftmutEscapeJSON(alternative.mutation.sourceMutated))""#)
  fields.append(#""behaviorKey":"\#(swiftmutEscapeJSON(alternative.mutation.silMutated))""#)
  return "{\(fields.joined(separator: ","))}"
}

private func swiftmutScalarValueSiteJSON(_ site: SwiftmutScalarValueSite) -> String {
  var fields: [String] = []
  fields.append(#""siteID":\#(site.siteID)"#)
  fields.append(#""module":"\#(swiftmutEscapeJSON(site.module))""#)
  fields.append(#""function":"\#(swiftmutEscapeJSON(site.function))""#)
  fields.append(#""sourceLocation":{"file":"\#(swiftmutEscapeJSON(site.file))","line":\#(site.line),"column":\#(site.column)}"#)
  fields.append(#""siteKind":"scalarValue""#)
  fields.append(#""resultKind":"value""#)
  fields.append(#""alternatives":[\#(site.alternatives.map(swiftmutScalarValueAlternativeJSON).joined(separator: ","))]"#)
  return "{\(fields.joined(separator: ","))}"
}

private func swiftmutScalarValueAlternativeJSON(_ alternative: SwiftmutScalarValueAlternative) -> String {
  var fields: [String] = []
  fields.append(#""mutantID":"\#(swiftmutEscapeJSON(alternative.mutantID))""#)
  fields.append(#""alternativeIndex":\#(alternative.alternativeIndex)"#)
  fields.append(#""mutator":"\#(swiftmutEscapeJSON(alternative.mutation.mutator))""#)
  fields.append(#""sourceOriginal":"\#(swiftmutEscapeJSON(alternative.mutation.sourceOriginal))""#)
  fields.append(#""sourceMutated":"\#(swiftmutEscapeJSON(alternative.mutation.sourceMutated))""#)
  fields.append(#""behaviorKey":"\#(swiftmutEscapeJSON(alternative.mutation.silMutated))""#)
  return "{\(fields.joined(separator: ","))}"
}

private func swiftmutValueApplySiteJSON(_ site: SwiftmutValueApplySite) -> String {
  var fields: [String] = []
  fields.append(#""siteID":\#(site.siteID)"#)
  fields.append(#""module":"\#(swiftmutEscapeJSON(site.module))""#)
  fields.append(#""function":"\#(swiftmutEscapeJSON(site.function))""#)
  fields.append(#""sourceLocation":{"file":"\#(swiftmutEscapeJSON(site.file))","line":\#(site.line),"column":\#(site.column)}"#)
  fields.append(#""siteKind":"valueApply""#)
  fields.append(#""resultKind":"value""#)
  fields.append(#""alternatives":[\#(site.alternatives.map(swiftmutValueApplyAlternativeJSON).joined(separator: ","))]"#)
  return "{\(fields.joined(separator: ","))}"
}

private func swiftmutValueApplyAlternativeJSON(_ alternative: SwiftmutValueApplyAlternative) -> String {
  var fields: [String] = []
  fields.append(#""mutantID":"\#(swiftmutEscapeJSON(alternative.mutantID))""#)
  fields.append(#""alternativeIndex":\#(alternative.alternativeIndex)"#)
  fields.append(#""mutator":"\#(swiftmutEscapeJSON(alternative.mutation.mutator))""#)
  fields.append(#""sourceOriginal":"\#(swiftmutEscapeJSON(alternative.mutation.sourceOriginal))""#)
  fields.append(#""sourceMutated":"\#(swiftmutEscapeJSON(alternative.mutation.sourceMutated))""#)
  fields.append(#""behaviorKey":"\#(swiftmutEscapeJSON(alternative.mutation.silMutated))""#)
  return "{\(fields.joined(separator: ","))}"
}

private func swiftmutAssignmentValueSiteJSON(_ site: SwiftmutAssignmentValueSite) -> String {
  var fields: [String] = []
  fields.append(#""siteID":\#(site.siteID)"#)
  fields.append(#""module":"\#(swiftmutEscapeJSON(site.module))""#)
  fields.append(#""function":"\#(swiftmutEscapeJSON(site.function))""#)
  fields.append(#""sourceLocation":{"file":"\#(swiftmutEscapeJSON(site.file))","line":\#(site.line),"column":\#(site.column)}"#)
  fields.append(#""siteKind":"assignmentValue""#)
  fields.append(#""resultKind":"value""#)
  fields.append(#""alternatives":[\#(site.alternatives.map(swiftmutAssignmentValueAlternativeJSON).joined(separator: ","))]"#)
  return "{\(fields.joined(separator: ","))}"
}

private func swiftmutAssignmentValueAlternativeJSON(_ alternative: SwiftmutAssignmentValueAlternative) -> String {
  var fields: [String] = []
  fields.append(#""mutantID":"\#(swiftmutEscapeJSON(alternative.mutantID))""#)
  fields.append(#""alternativeIndex":\#(alternative.alternativeIndex)"#)
  fields.append(#""mutator":"\#(swiftmutEscapeJSON(alternative.mutation.mutator))""#)
  fields.append(#""sourceOriginal":"\#(swiftmutEscapeJSON(alternative.mutation.sourceOriginal))""#)
  fields.append(#""sourceMutated":"\#(swiftmutEscapeJSON(alternative.mutation.sourceMutated))""#)
  fields.append(#""behaviorKey":"\#(swiftmutEscapeJSON(alternative.mutation.silMutated))""#)
  return "{\(fields.joined(separator: ","))}"
}

private func swiftmutReturnSiteJSON(_ site: SwiftmutReturnSite) -> String {
  var fields: [String] = []
  fields.append(#""siteID":\#(site.siteID)"#)
  fields.append(#""module":"\#(swiftmutEscapeJSON(site.module))""#)
  fields.append(#""function":"\#(swiftmutEscapeJSON(site.function))""#)
  fields.append(
    #""sourceLocation":{"file":"\#(swiftmutEscapeJSON(site.file))","line":\#(site.line),"column":\#(site.column)}"#
  )
  fields.append(#""siteKind":"returnValue""#)
  fields.append(#""resultKind":"returnValue""#)
  var alternatives: [String] = []
  for alternative in site.alternatives {
    alternatives.append(swiftmutReturnAlternativeJSON(alternative))
  }
  fields.append(#""alternatives":[\#(alternatives.joined(separator: ","))]"#)
  return "{\(fields.joined(separator: ","))}"
}

private func swiftmutReturnBranchSiteJSON(_ site: SwiftmutReturnBranchSite) -> String {
  var fields: [String] = []
  fields.append(#""siteID":\#(site.siteID)"#)
  fields.append(#""module":"\#(swiftmutEscapeJSON(site.module))""#)
  fields.append(#""function":"\#(swiftmutEscapeJSON(site.function))""#)
  fields.append(
    #""sourceLocation":{"file":"\#(swiftmutEscapeJSON(site.file))","line":\#(site.line),"column":\#(site.column)}"#
  )
  fields.append(#""siteKind":"returnBranchValue""#)
  fields.append(#""resultKind":"returnValue""#)
  var alternatives: [String] = []
  for alternative in site.alternatives {
    alternatives.append(swiftmutReturnAlternativeJSON(alternative))
  }
  fields.append(#""alternatives":[\#(alternatives.joined(separator: ","))]"#)
  return "{\(fields.joined(separator: ","))}"
}

private func swiftmutReturnAlternativeJSON(_ alternative: SwiftmutReturnAlternative) -> String {
  var fields: [String] = []
  fields.append(#""mutantID":"\#(swiftmutEscapeJSON(alternative.mutantID))""#)
  fields.append(#""alternativeIndex":\#(alternative.alternativeIndex)"#)
  fields.append(#""mutator":"\#(swiftmutEscapeJSON(alternative.mutation.mutator))""#)
  fields.append(#""sourceOriginal":"\#(swiftmutEscapeJSON(alternative.mutation.sourceOriginal))""#)
  fields.append(#""sourceMutated":"\#(swiftmutEscapeJSON(alternative.mutation.sourceMutated))""#)
  fields.append(#""behaviorKey":"\#(swiftmutEscapeJSON(alternative.mutation.silMutated))""#)
  return "{\(fields.joined(separator: ","))}"
}

private func swiftmutVoidCallSiteJSON(_ site: SwiftmutVoidCallSite) -> String {
  var fields: [String] = []
  fields.append(#""siteID":\#(site.siteID)"#)
  fields.append(#""module":"\#(swiftmutEscapeJSON(site.module))""#)
  fields.append(#""function":"\#(swiftmutEscapeJSON(site.function))""#)
  fields.append(
    #""sourceLocation":{"file":"\#(swiftmutEscapeJSON(site.file))","line":\#(site.line),"column":\#(site.column)}"#
  )
  fields.append(#""siteKind":"voidCall""#)
  fields.append(#""resultKind":"statement""#)
  fields.append(#""alternatives":[\#(site.alternatives.map(swiftmutVoidCallAlternativeJSON).joined(separator: ","))]"#)
  return "{\(fields.joined(separator: ","))}"
}

private func swiftmutVoidCallAlternativeJSON(_ alternative: SwiftmutVoidCallAlternative) -> String {
  var fields: [String] = []
  fields.append(#""mutantID":"\#(swiftmutEscapeJSON(alternative.mutantID))""#)
  fields.append(#""alternativeIndex":\#(alternative.alternativeIndex)"#)
  fields.append(#""mutator":"\#(swiftmutEscapeJSON(alternative.mutation.mutator))""#)
  fields.append(#""sourceOriginal":"\#(swiftmutEscapeJSON(alternative.mutation.sourceOriginal))""#)
  fields.append(#""sourceMutated":"\#(swiftmutEscapeJSON(alternative.mutation.sourceMutated))""#)
  fields.append(#""behaviorKey":"\#(swiftmutEscapeJSON(alternative.mutation.silMutated))""#)
  return "{\(fields.joined(separator: ","))}"
}

private func swiftmutModeName(_ mode: SwiftmutMode) -> String {
  switch mode {
  case .discover:
    return "discover"
  case .apply:
    return "apply"
  case .metamutant:
    return "metamutant"
  }
}

private func swiftmutShouldLog(
  function: Function,
  moduleName: String,
  config: SwiftmutConfig
) -> Bool {
  if config.compilerEventsPath.isEmpty {
    return false
  }
  if swiftmutFunctionName(function.name.string, belongsToModule: moduleName) {
    return true
  }
  let location = function.location.description
  for path in config.sourceFiles {
    if location.contains(path) {
      return true
    }
  }
  return false
}

private func swiftmutLogEvent(
  _ event: String,
  config: SwiftmutConfig,
  fields: [(String, String)]
) {
  guard !config.compilerEventsPath.isEmpty else {
    return
  }

  var jsonFields = [#""event":"\#(swiftmutEscapeJSON(event))""#]
  for (key, value) in fields {
    jsonFields.append(#""\#(swiftmutEscapeJSON(key))":"\#(swiftmutEscapeJSON(value))""#)
  }
  swiftmutCreateParentDirectories(forFile: config.compilerEventsPath)
  swiftmutWrite("{\(jsonFields.joined(separator: ","))}\n", to: config.compilerEventsPath, append: true)
}

private func swiftmutLogAssignmentValueSourceLocationMiss(
  store: StoreInst,
  mutation: SwiftmutMutation,
  moduleName: String,
  functionName: String,
  destinationNames: [String],
  sourceNames: [String],
  targetNames: [String],
  config: SwiftmutConfig
) {
  swiftmutLogEvent(
    "assignmentValueSourceLocationMiss",
    config: config,
    fields: [
      ("mode", swiftmutModeName(config.mode)),
      ("module", moduleName),
      ("function", functionName),
      ("functionLocation", store.parentFunction.location.description),
      ("storeLocation", store.location.description),
      ("sourceLocation", store.source.definingInstruction?.location.description ?? "<no defining instruction>"),
      ("destinationNames", destinationNames.joined(separator: ",")),
      ("sourceNames", sourceNames.joined(separator: ",")),
      ("targetNames", targetNames.joined(separator: ",")),
      ("mutator", mutation.mutator),
      ("mutatedBuiltinName", mutation.mutatedBuiltinName),
      ("sourceOriginal", mutation.sourceOriginal),
      ("sourceMutated", mutation.sourceMutated)
    ])
}

private func swiftmutLogReturnSourceLocationMiss(
  returnInst: ReturnInst,
  mutation: SwiftmutMutation,
  returnType: Type,
  moduleName: String,
  functionName: String,
  config: SwiftmutConfig
) {
  swiftmutLogEvent(
    "returnSourceLocationMiss",
    config: config,
    fields: [
      ("mode", swiftmutModeName(config.mode)),
      ("module", moduleName),
      ("function", functionName),
      ("functionLocation", returnInst.parentFunction.location.description),
      ("returnLocation", returnInst.location.description),
      ("returnedValueLocation", returnInst.returnedValue.definingInstruction?.location.description ?? "<no defining instruction>"),
      ("returnType", returnType.description),
      ("mutator", mutation.mutator),
      ("mutatedBuiltinName", mutation.mutatedBuiltinName),
      ("sourceOriginal", mutation.sourceOriginal),
      ("sourceMutated", mutation.sourceMutated)
    ])
}

private func swiftmutFunctionName(_ functionName: String, belongsToModule moduleName: String) -> Bool {
  let mangledModulePrefix = "$s\(moduleName.utf8.count)\(moduleName)"
  if functionName.hasPrefix(mangledModulePrefix) {
    return true
  }
  return functionName.hasPrefix("@\(mangledModulePrefix)")
}

private func swiftmutStableSiteID(
  packageRoot: String,
  module: String,
  file: String,
  line: Int,
  column: Int,
  function: String,
  siteKind: String,
  localOrdinal: Int
) -> UInt64 {
  swiftmutStableHash([
    packageRoot,
    module,
    file,
    "\(line)",
    "\(column)",
    function,
    siteKind,
    "\(localOrdinal)"
  ].joined(separator: "\u{1f}"))
}

private func swiftmutStableHash(_ text: String) -> UInt64 {
  var hash: UInt64 = 0xcbf29ce484222325
  for byte in text.utf8 {
    hash ^= UInt64(byte)
    hash = hash &* 0x100000001b3
  }
  return hash
}

private func swiftmutHex(_ value: UInt64) -> String {
  let digits = Array("0123456789ABCDEF".utf8)
  var output = [UInt8](repeating: 48, count: 16)
  for index in 0..<16 {
    let shift = UInt64((15 - index) * 4)
    let nibble = Int((value >> shift) & 0xf)
    output[index] = digits[nibble]
  }
  return String(decoding: output, as: UTF8.self)
}

private func swiftmutSanitizeFileComponent(_ value: String) -> String {
  var output = ""
  for byte in value.utf8 {
    let isDigit = byte >= 48 && byte <= 57
    let isUppercase = byte >= 65 && byte <= 90
    let isLowercase = byte >= 97 && byte <= 122
    if isDigit || isUppercase || isLowercase || byte == 45 || byte == 95 {
      output.append(Character(UnicodeScalar(byte)))
    } else {
      output.append("_")
    }
  }
  return output.isEmpty ? "fragment" : output
}

private func swiftmutProcessID() -> Int32 {
  #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(Linux) || os(Android)
  return getpid()
  #else
  return 0
  #endif
}

private func swiftmutClockMicroseconds() -> UInt64 {
  #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(Linux) || os(Android)
  var now = timeval()
  gettimeofday(&now, nil)
  return UInt64(now.tv_sec) * 1_000_000 + UInt64(now.tv_usec)
  #else
  return 0
  #endif
}

private func swiftmutReturnMutations(
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

  if swiftmutIsIntegerStructType(returnType, in: returnInst.parentFunction),
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

private func swiftmutReturnMutation(
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

private func swiftmutFirstReturnRule(
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

private func swiftmutVoidCallMutation(
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

private func swiftmutFirstVoidCallRule(
  config: SwiftmutConfig
) -> SwiftmutVoidCallMutationRule? {
  for rule in config.voidCallMutationRules {
    if swiftmutMutatorIsEnabled(rule.mutator, config: config) {
      return rule
    }
  }
  return nil
}

private func swiftmutMutations(
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

private func swiftmutContextualArithmeticRule(
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

private func swiftmutContext(
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

private func swiftmutContextualArithmeticMutation(
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

private func swiftmutArithmeticBuiltinIDName(_ builtin: BuiltinInst) -> String? {
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

private func swiftmutBuiltinFunctionName(_ builtin: BuiltinInst) -> String? {
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

private func swiftmutBuiltinIDName(_ id: BuiltinInst.ID?) -> String? {
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

private func swiftmutBinaryMutation(
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

private func swiftmutIsIncrementBuiltin(_ builtin: BuiltinInst) -> Bool {
  let arguments = Array(builtin.arguments)
  guard arguments.count >= 2 else {
    return false
  }
  return swiftmutIsOneInteger(arguments[0]) || swiftmutIsOneInteger(arguments[1])
}

private func swiftmutIsUnaryNegationBuiltin(_ builtin: BuiltinInst) -> Bool {
  let arguments = Array(builtin.arguments)
  guard arguments.count >= 2 else {
    return false
  }
  return swiftmutIsZeroInteger(arguments[0]) && !swiftmutIsZeroInteger(arguments[1])
}

private func swiftmutIsOneInteger(_ value: Value) -> Bool {
  guard let literal = value as? IntegerLiteralInst,
        let literalValue = literal.value else {
    return false
  }
  return literalValue == 1
}

private func swiftmutIsZeroInteger(_ value: Value) -> Bool {
  guard let literal = value as? IntegerLiteralInst,
        let literalValue = literal.value else {
    return false
  }
  return literalValue == 0
}

private func swiftmutApply(
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

private func swiftmutApplyReturn(
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

private func swiftmutMakeBool(
  _ value: Bool,
  type: Type,
  builder: Builder
) -> Value {
  let literal = builder.createBoolLiteral(value)
  return builder.createStruct(type: type, elements: [literal])
}

private func swiftmutMakeIntegerZero(
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

private func swiftmutMakeOptionalNone(
  type: Type,
  builder: Builder
) -> Value {
  return builder.createEnum(caseIndex: 0, payload: nil, enumType: type)
}

private func swiftmutMakeEmptyString(
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

private func swiftmutEmptyStringFunction(
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

private func swiftmutRuntimeHelperThunkName(
  runtimeFunctionName: String?,
  suffix: String,
  fallbackName: String = "__swiftmut_empty_string"
) -> String {
  guard let runtimeFunctionName else {
    return fallbackName
  }
  return "\(runtimeFunctionName)_\(suffix)"
}

private func swiftmutMakeEmptyCollection(
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

private func swiftmutCanApplyEmptyCollection(
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

private func swiftmutEmptyCollectionSubstitutionMap(
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

private func swiftmutEmptyCollectionFunction(
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

private func swiftmutIsBoolType(_ type: Type, in function: Function) -> Bool {
  guard let nominal = type.nominal,
        nominal.name.string == "Bool",
        let fields = type.getNominalFields(in: function),
        fields.count == 1 else {
    return false
  }
  return fields[0].canonicalType.isBuiltinInteger(withFixedWidth: 1)
}

private func swiftmutIsIntegerStructType(_ type: Type, in function: Function) -> Bool {
  guard let nominal = type.nominal,
        nominal.name.string != "Bool",
        let fields = type.getNominalFields(in: function),
        fields.count == 1 else {
    return false
  }
  return fields[0].canonicalType.isBuiltinInteger
}

private func swiftmutIsStringType(_ type: Type) -> Bool {
  guard let nominal = type.nominal else {
    return false
  }
  return nominal.name.string == "String"
}

private func swiftmutIsCollectionType(_ type: Type, named name: String) -> Bool {
  guard let nominal = type.nominal else {
    return false
  }
  return nominal.name.string == name
}

private func swiftmutRecordReturnType(
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
  if swiftmutIsIntegerStructType(type, in: function) {
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

private func swiftmutRecordReturnSourceLocationMiss(
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
  if swiftmutIsIntegerStructType(type, in: function) {
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

private func swiftmutBoolLiteralValue(_ value: Value) -> Bool? {
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

private func swiftmutIntegerStructLiteralValue(_ value: Value) -> Int? {
  guard let structInst = value as? StructInst,
        let literal = structInst.operands.first?.value as? IntegerLiteralInst else {
    return nil
  }
  return literal.value
}

private func swiftmutIsOptionalNone(_ value: Value) -> Bool {
  guard let enumInst = value as? EnumInst else {
    return false
  }
  return enumInst.type.isOptional && enumInst.caseIndex == 0
}

private func swiftmutMutatorIsEnabled(
  _ mutator: String,
  config: SwiftmutConfig
) -> Bool {
  if config.enabledMutators.isEmpty {
    return true
  }
  for enabledMutator in config.enabledMutators {
    if enabledMutator == mutator {
      return true
    }
  }
  return false
}

private func swiftmutReturnSourceLocation(
  for returnInst: ReturnInst,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  if let fileNameAndPosition = returnInst.location.fileNameAndPosition {
    let path = fileNameAndPosition.path.string
    if let matchedPath = swiftmutIncludedSourcePath(path, config: config) {
      let candidate = (
        swiftmutTrimPackageRoot(matchedPath, config: config),
        fileNameAndPosition.line,
        fileNameAndPosition.column,
        mutation.sourceOriginal,
        mutation.sourceMutated)
      if swiftmutReturnSourceLocationIsUsable(candidate, mutation: mutation, config: config) {
        return candidate
      }
      if let anchored = swiftmutFindAssignmentReturnSourceLocation(
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        mutation: mutation,
        config: config
      ) {
        return anchored
      }
      if let anchored = swiftmutFindDescribedExplicitReturnSourceLocation(
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        locationDescription: returnInst.location.description,
        mutation: mutation,
        config: config
      ) {
        return anchored
      }
      if let anchored = swiftmutFindUniqueExplicitReturnSourceLocation(
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        mutation: mutation,
        config: config
      ) {
        return anchored
      }
      if let anchored = swiftmutFindNearestPriorExplicitReturnSourceLocation(
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        mutation: mutation,
        config: config
      ) {
        return anchored
      }
      if let anchored = swiftmutFindNearestPriorImplicitReturnSourceLocation(
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        mutation: mutation,
        config: config
      ) {
        return anchored
      }
      if let anchored = swiftmutFindUniqueImplicitReturnSourceLocation(
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        mutation: mutation,
        config: config
      ) {
        return anchored
      }
      if let anchored = swiftmutFindPropertyGetterReturnSourceLocation(
        functionName: returnInst.parentFunction.name.string,
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        mutation: mutation,
        config: config
      ) {
        return anchored
      }
    }
  }

  if let definingInstruction = returnInst.returnedValue.definingInstruction,
     let fileNameAndPosition = definingInstruction.location.fileNameAndPosition {
    let path = fileNameAndPosition.path.string
    if let matchedPath = swiftmutIncludedSourcePath(path, config: config) {
      let candidate = (
        swiftmutTrimPackageRoot(matchedPath, config: config),
        fileNameAndPosition.line,
        fileNameAndPosition.column,
        mutation.sourceOriginal,
        mutation.sourceMutated)
      if swiftmutReturnSourceLocationIsUsable(candidate, mutation: mutation, config: config) {
        return candidate
      }
      if let anchored = swiftmutFindAssignmentReturnSourceLocation(
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        mutation: mutation,
        config: config
      ) {
        return anchored
      }
      if let anchored = swiftmutFindDescribedExplicitReturnSourceLocation(
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        locationDescription: returnInst.location.description,
        mutation: mutation,
        config: config
      ) {
        return anchored
      }
      if let anchored = swiftmutFindUniqueExplicitReturnSourceLocation(
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        mutation: mutation,
        config: config
      ) {
        return anchored
      }
      if let anchored = swiftmutFindNearestPriorExplicitReturnSourceLocation(
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        mutation: mutation,
        config: config
      ) {
        return anchored
      }
      if let anchored = swiftmutFindNearestPriorImplicitReturnSourceLocation(
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        mutation: mutation,
        config: config
      ) {
        return anchored
      }
      if let anchored = swiftmutFindUniqueImplicitReturnSourceLocation(
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        mutation: mutation,
        config: config
      ) {
        return anchored
      }
      if let anchored = swiftmutFindPropertyGetterReturnSourceLocation(
        functionName: returnInst.parentFunction.name.string,
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        mutation: mutation,
        config: config
      ) {
        return anchored
      }
    }
  }

  if let anchored = swiftmutFindDescribedDefaultArgumentReturnSourceLocation(
    functionName: returnInst.parentFunction.name.string,
    locationDescription: returnInst.location.description,
    mutation: mutation,
    config: config
  ) {
    return anchored
  }
  if let definingInstruction = returnInst.returnedValue.definingInstruction,
     let anchored = swiftmutFindDescribedDefaultArgumentReturnSourceLocation(
       functionName: returnInst.parentFunction.name.string,
       locationDescription: definingInstruction.location.description,
       mutation: mutation,
       config: config
     ) {
    return anchored
  }

  let returnLocation = returnInst.location.description
  for path in swiftmutSwiftSourcePaths(config: config) {
    guard returnLocation.contains(path),
          let line = swiftmutPreferredLine(in: returnLocation, path: path) else {
      continue
    }
    let candidate = (
      swiftmutTrimPackageRoot(path, config: config),
      line,
      1,
      mutation.sourceOriginal,
      mutation.sourceMutated)
    if swiftmutReturnSourceLocationIsUsable(candidate, mutation: mutation, config: config) {
      return candidate
    }
    if let anchored = swiftmutFindAssignmentReturnSourceLocation(
      path: path,
      preferredLine: line,
      mutation: mutation,
      config: config
    ) {
      return anchored
    }
    if let anchored = swiftmutFindDescribedExplicitReturnSourceLocation(
      path: path,
      preferredLine: line,
      locationDescription: returnLocation,
      mutation: mutation,
      config: config
    ) {
      return anchored
    }
    if let anchored = swiftmutFindUniqueExplicitReturnSourceLocation(
      path: path,
      preferredLine: line,
      mutation: mutation,
      config: config
    ) {
      return anchored
    }
    if let anchored = swiftmutFindNearestPriorExplicitReturnSourceLocation(
      path: path,
      preferredLine: line,
      mutation: mutation,
      config: config
    ) {
      return anchored
    }
    if let anchored = swiftmutFindNearestPriorImplicitReturnSourceLocation(
      path: path,
      preferredLine: line,
      mutation: mutation,
      config: config
    ) {
      return anchored
    }
    if let anchored = swiftmutFindUniqueImplicitReturnSourceLocation(
      path: path,
      preferredLine: line,
      mutation: mutation,
      config: config
    ) {
      return anchored
    }
    if let anchored = swiftmutFindPropertyGetterReturnSourceLocation(
      functionName: returnInst.parentFunction.name.string,
      path: path,
      preferredLine: line,
      mutation: mutation,
      config: config
    ) {
      return anchored
    }
  }

  let location = returnInst.parentFunction.location.description
  for path in swiftmutSwiftSourcePaths(config: config) {
    guard location.contains(path),
          let line = swiftmutPreferredLine(in: location, path: path) else {
      continue
    }
    let candidate = (
      swiftmutTrimPackageRoot(path, config: config),
      line,
      1,
      mutation.sourceOriginal,
      mutation.sourceMutated)
    if swiftmutReturnSourceLocationIsUsable(candidate, mutation: mutation, config: config) {
      return candidate
    }
    if let anchored = swiftmutFindAssignmentReturnSourceLocation(
      path: path,
      preferredLine: line,
      mutation: mutation,
      config: config
    ) {
      return anchored
    }
    if let anchored = swiftmutFindDescribedExplicitReturnSourceLocation(
      path: path,
      preferredLine: line,
      locationDescription: returnInst.location.description,
      mutation: mutation,
      config: config
    ) {
      return anchored
    }
    if let anchored = swiftmutFindUniqueExplicitReturnSourceLocation(
      path: path,
      preferredLine: line,
      mutation: mutation,
      config: config
    ) {
      return anchored
    }
    if let anchored = swiftmutFindUniqueImplicitReturnSourceLocation(
      path: path,
      preferredLine: line,
      mutation: mutation,
      config: config
    ) {
      return anchored
    }
    if let anchored = swiftmutFindPropertyGetterReturnSourceLocation(
      functionName: returnInst.parentFunction.name.string,
      path: path,
      preferredLine: line,
      mutation: mutation,
      config: config
    ) {
      return anchored
    }
  }
  return nil
}

private func swiftmutFindPropertyGetterReturnSourceLocation(
  functionName: String,
  path: String,
  preferredLine: Int,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard preferredLine > 0,
        mutation.sourceOriginal == "return",
        let text = swiftmutRead(path) else {
    return nil
  }

  if let exact = swiftmutPropertyGetterReturnSourceLocation(
    in: text,
    functionName: functionName,
    path: path,
    lineRange: preferredLine...preferredLine,
    mutation: mutation,
    config: config
  ) {
    return exact
  }

  let firstLine = preferredLine > 1 ? preferredLine - 1 : 1
  return swiftmutPropertyGetterReturnSourceLocation(
    in: text,
    functionName: functionName,
    path: path,
    lineRange: firstLine...(preferredLine + 2),
    mutation: mutation,
    config: config
  )
}

private func swiftmutPropertyGetterReturnSourceLocation(
  in text: String,
  functionName: String,
  path: String,
  lineRange: ClosedRange<Int>,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  var matches: [(line: Int, column: Int, sourceOriginal: String, sourceMutated: String)] = []
  var currentLine = 1
  var lineStart = text.startIndex
  var index = text.startIndex

  func inspectLine(_ lineText: String, line: Int) {
    guard lineRange.contains(line),
          matches.count < 2,
          let property = swiftmutStoredPropertyDeclaration(lineText, mutation: mutation) else {
      return
    }
    guard swiftmutFunctionName(functionName, containsPropertyName: property.name) else {
      return
    }
    matches.append((line, property.column, property.sourceOriginal, property.sourceMutated))
  }

  while index < text.endIndex {
    if text[index] == "\n" {
      inspectLine(String(text[lineStart..<index]), line: currentLine)
      if currentLine >= lineRange.upperBound || matches.count >= 2 {
        break
      }
      currentLine += 1
      lineStart = text.index(after: index)
    }
    index = text.index(after: index)
  }

  if index == text.endIndex && currentLine <= lineRange.upperBound {
    inspectLine(String(text[lineStart..<text.endIndex]), line: currentLine)
  }

  guard matches.count == 1,
        let match = matches.first else {
    return nil
  }
  return (
    swiftmutTrimPackageRoot(path, config: config),
    match.line,
    match.column,
    match.sourceOriginal,
    match.sourceMutated)
}

private func swiftmutStoredPropertyDeclaration(
  _ line: String,
  mutation: SwiftmutMutation
) -> (name: String, column: Int, sourceOriginal: String, sourceMutated: String)? {
  let bytes = Array(line.utf8)
  let lineStart = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
  let lineEnd = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  guard lineStart < lineEnd,
        !swiftmutASCIIHasPrefix(bytes, start: lineStart, prefix: "case "),
        !swiftmutASCIIHasPrefix(bytes, start: lineStart, prefix: "func "),
        !swiftmutASCIIHasPrefix(bytes, start: lineStart, prefix: "init"),
        !swiftmutASCIIHasPrefix(bytes, start: lineStart, prefix: "return "),
        !swiftmutASCIIHasPrefix(bytes, start: lineStart, prefix: "//") else {
    return nil
  }

  guard let keyword = swiftmutPropertyDeclarationKeyword(bytes: bytes, start: lineStart, end: lineEnd) else {
    return nil
  }
  let nameStart = swiftmutSkipHorizontalWhitespace(bytes, from: keyword.end)
  if nameStart < lineEnd && bytes[nameStart] == 40 {
    return nil
  }
  guard nameStart < lineEnd,
        swiftmutIsASCIIIdentifierStart(bytes[nameStart]) else {
    return nil
  }
  var nameEnd = nameStart + 1
  while nameEnd < lineEnd && swiftmutIsASCIILetterNumberOrUnderscore(bytes[nameEnd]) {
    nameEnd += 1
  }
  var afterName = swiftmutSkipHorizontalWhitespace(bytes, from: nameEnd)
  guard afterName < lineEnd,
        bytes[afterName] == 58 else {
    return nil
  }
  afterName = swiftmutSkipHorizontalWhitespace(bytes, from: afterName + 1)
  guard afterName < lineEnd else {
    return nil
  }
  for index in afterName..<lineEnd {
    if bytes[index] == 123 {
      return nil
    }
  }

  let name = String(decoding: bytes[nameStart..<nameEnd], as: UTF8.self)
  return (
    name,
    nameStart + 1,
    name,
    swiftmutImplicitReturnSourceMutation(for: mutation))
}

private func swiftmutFunctionName(_ functionName: String, containsPropertyName propertyName: String) -> Bool {
  guard !propertyName.isEmpty else {
    return false
  }
  return swiftmutMangledNameContainsIdentifier(functionName, identifier: propertyName)
}

private func swiftmutPropertyDeclarationKeyword(bytes: [UInt8], start: Int, end: Int) -> (start: Int, end: Int)? {
  var index = start
  while index < end {
    let tokenStart = swiftmutSkipHorizontalWhitespace(bytes, from: index)
    guard tokenStart < end else {
      return nil
    }
    var tokenEnd = tokenStart
    while tokenEnd < end && swiftmutIsASCIILetterNumberOrUnderscore(bytes[tokenEnd]) {
      tokenEnd += 1
    }
    guard tokenEnd > tokenStart else {
      return nil
    }
    let token = String(decoding: bytes[tokenStart..<tokenEnd], as: UTF8.self)
    if token == "let" || token == "var" {
      return (tokenStart, tokenEnd)
    }
    if !swiftmutIsPropertyDeclarationModifier(token) {
      return nil
    }
    index = swiftmutSkipPropertyDeclarationModifierSuffix(bytes: bytes, from: tokenEnd, end: end)
  }
  return nil
}

private func swiftmutSkipPropertyDeclarationModifierSuffix(bytes: [UInt8], from index: Int, end: Int) -> Int {
  guard index + 5 <= end,
        bytes[index] == 40,
        swiftmutASCIIHasExactPrefix(bytes, start: index, prefix: "(set)") else {
    return index
  }
  return index + 5
}

private func swiftmutIsPropertyDeclarationModifier(_ token: String) -> Bool {
  switch token {
  case "public", "private", "internal", "fileprivate", "open", "package",
       "static", "class", "final", "lazy", "weak", "unowned", "nonisolated",
       "isolated", "mutating", "nonmutating":
    return true
  default:
    return false
  }
}

private func swiftmutScalarValueSourceLocation(
  for value: StructInst,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  let functionSourceLocation = swiftmutFunctionSourceLocation(
    for: value.parentFunction,
    config: config
  )
  if let fileNameAndPosition = value.location.fileNameAndPosition {
    let path = fileNameAndPosition.path.string
    if let matchedPath = swiftmutIncludedSourcePath(path, config: config) {
      if let assignment = swiftmutFindAssignmentValueSourceLocation(
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        mutation: mutation,
        config: config,
        requiresDirectValueExpression: true
      ) {
        return assignment
      }
      if let returned = swiftmutFindReturnedScalarValueSourceLocation(
        for: value,
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        mutation: mutation,
        config: config
      ) {
        return returned
      }
      if let functionSourceLocation,
         functionSourceLocation.path == matchedPath,
         let anchored = swiftmutFindOrdinalScalarValueSourceLocation(
           for: value,
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
    if let anchored = swiftmutFindAssignmentValueSourceLocation(
      path: functionSourceLocation.path,
      preferredLine: functionSourceLocation.line,
      mutation: mutation,
      config: config,
      requiresDirectValueExpression: true
    ) {
      return anchored
    }
    if let anchored = swiftmutFindReturnedScalarValueSourceLocation(
      for: value,
      path: functionSourceLocation.path,
      preferredLine: functionSourceLocation.line,
      mutation: mutation,
      config: config
    ) {
      return anchored
    }
    if let anchored = swiftmutFindOrdinalScalarValueSourceLocation(
      for: value,
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

private func swiftmutFindOrdinalScalarValueSourceLocation(
  for value: StructInst,
  path: String,
  preferredLine: Int,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard let ordinal = swiftmutScalarValueOrdinalAndCount(
    for: value,
    mutation: mutation,
    config: config
  ), ordinal.count <= 200 else {
    return nil
  }
  return swiftmutFindOrdinalValueExpressionSourceLocation(
    path: path,
    preferredLine: preferredLine,
    ordinal: ordinal.ordinal,
    expectedCount: ordinal.count,
    mutation: mutation,
    config: config
  )
}

private func swiftmutScalarValueOrdinalAndCount(
  for value: StructInst,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (ordinal: Int, count: Int)? {
  var ordinal = 0
  var count = 0
  var foundValue = false

  for block in value.parentFunction.blocks {
    for instruction in block.instructions {
      guard let candidate = instruction as? StructInst else {
        continue
      }
      let mutations = swiftmutScalarValueMutations(for: candidate, config: config)
      guard mutations.contains(where: { $0.mutatedBuiltinName == mutation.mutatedBuiltinName }) else {
        continue
      }
      count += 1
      if candidate === value {
        ordinal = count
        foundValue = true
      }
    }
  }

  guard foundValue else {
    return nil
  }
  return (ordinal, count)
}

private func swiftmutFindReturnedScalarValueSourceLocation(
  for value: StructInst,
  path: String,
  preferredLine: Int,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard swiftmutScalarValueIsDirectReturnBranchValue(value),
        let ordinal = swiftmutReturnedScalarValueOrdinalAndCount(
          for: value,
          mutation: mutation,
          config: config
        ), ordinal.count <= 20 else {
    return nil
  }
  return swiftmutFindOrdinalExplicitReturnSourceLocation(
    path: path,
    preferredLine: preferredLine,
    ordinal: ordinal.ordinal,
    expectedCount: ordinal.count,
    mutation: mutation,
    config: config
  )
}

private func swiftmutScalarValueIsDirectReturnBranchValue(_ value: StructInst) -> Bool {
  for use in value.uses.ignoreDebugUses {
    guard let branch = use.instruction as? BranchInst,
          branch.targetBlock.terminator is ReturnInst else {
      continue
    }
    return true
  }
  return false
}

private func swiftmutReturnedScalarValueOrdinalAndCount(
  for value: StructInst,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (ordinal: Int, count: Int)? {
  var ordinal = 0
  var count = 0
  var foundValue = false

  for block in value.parentFunction.blocks {
    for instruction in block.instructions {
      guard let candidate = instruction as? StructInst,
            swiftmutScalarValueIsDirectReturnBranchValue(candidate) else {
        continue
      }
      let mutations = swiftmutScalarValueMutations(for: candidate, config: config)
      guard mutations.contains(where: { $0.mutatedBuiltinName == mutation.mutatedBuiltinName }) else {
        continue
      }
      count += 1
      if candidate === value {
        ordinal = count
        foundValue = true
      }
    }
  }

  guard foundValue else {
    return nil
  }
  return (ordinal, count)
}

private func swiftmutReturnBranchSourceLocation(
  for branch: BranchInst,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  let functionSourceLocation = swiftmutFunctionSourceLocation(
    for: branch.parentFunction,
    config: config
  )
  if let fileNameAndPosition = branch.location.fileNameAndPosition {
    let path = fileNameAndPosition.path.string
    if let matchedPath = swiftmutIncludedSourcePath(path, config: config),
       let anchored = swiftmutFindReturnBranchSourceLocation(
        for: branch,
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        mutation: mutation,
        config: config
       ) {
      return anchored
    }
  }

  if let definingInstruction = branch.operands.first?.value.definingInstruction,
     let fileNameAndPosition = definingInstruction.location.fileNameAndPosition {
    let path = fileNameAndPosition.path.string
    if let matchedPath = swiftmutIncludedSourcePath(path, config: config),
       let anchored = swiftmutFindReturnBranchSourceLocation(
        for: branch,
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        mutation: mutation,
        config: config
       ) {
      return anchored
    }
  }

  if let functionSourceLocation {
    return swiftmutFindReturnBranchSourceLocation(
      for: branch,
      path: functionSourceLocation.path,
      preferredLine: functionSourceLocation.line,
      mutation: mutation,
      config: config
    )
  }
  return nil
}

private func swiftmutFindReturnBranchSourceLocation(
  for branch: BranchInst,
  path: String,
  preferredLine: Int,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  if let exact = swiftmutFindUniqueExplicitReturnSourceLocation(
    path: path,
    preferredLine: preferredLine,
    mutation: mutation,
    config: config
  ) {
    return exact
  }
  guard let ordinal = swiftmutReturnBranchOrdinalAndCount(
    for: branch,
    mutation: mutation,
    config: config
  ), ordinal.count <= 40 else {
    return nil
  }
  return swiftmutFindOrdinalExplicitReturnSourceLocation(
    path: path,
    preferredLine: preferredLine,
    ordinal: ordinal.ordinal,
    expectedCount: ordinal.count,
    mutation: mutation,
    config: config
  )
}

private func swiftmutReturnBranchOrdinalAndCount(
  for branch: BranchInst,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (ordinal: Int, count: Int)? {
  var ordinal = 0
  var count = 0
  var foundBranch = false

  for block in branch.parentFunction.blocks {
    guard let candidate = block.terminator as? BranchInst else {
      continue
    }
    let mutations = swiftmutReturnBranchMutations(for: candidate, config: config)
    guard mutations.contains(where: { $0.mutatedBuiltinName == mutation.mutatedBuiltinName }) else {
      continue
    }
    count += 1
    if candidate === branch {
      ordinal = count
      foundBranch = true
    }
  }

  guard foundBranch else {
    return nil
  }
  return (ordinal, count)
}

private func swiftmutFindAssignmentValueSourceLocation(
  path: String,
  preferredLine: Int,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig,
  targetNames: [String] = [],
  requiresDirectValueExpression: Bool = false
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard preferredLine > 0,
        let text = swiftmutRead(path) else {
    return nil
  }
  if let exact = swiftmutAssignmentValueSourceLocation(
    in: text,
    path: path,
    lineRange: preferredLine...preferredLine,
    mutation: mutation,
    config: config,
    targetNames: targetNames,
    requiresDirectValueExpression: requiresDirectValueExpression
  ) {
    return exact
  }

  let firstLine = preferredLine > 2 ? preferredLine - 2 : 1
  let lastLine = preferredLine + (targetNames.isEmpty ? 8 : 240)
  return swiftmutAssignmentValueSourceLocation(
    in: text,
    path: path,
    lineRange: firstLine...lastLine,
    mutation: mutation,
    config: config,
    targetNames: targetNames,
    requiresDirectValueExpression: requiresDirectValueExpression
  )
}

private func swiftmutFindScopedAssignmentValueSourceLocation(
  path: String,
  functionLine: Int,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig,
  targetNames: [String],
  requiresDirectValueExpression: Bool
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard functionLine > 0,
        !targetNames.isEmpty,
        let text = swiftmutRead(path) else {
    return nil
  }

  var matches: [(line: Int, column: Int, sourceOriginal: String, sourceMutated: String)] = []
  var currentLine = 1
  var lineStart = text.startIndex
  var index = text.startIndex
  var braceDepth = 0
  var sawOpeningBrace = false

  func inspectLine(_ lineText: String, line: Int) {
    guard line >= functionLine,
          matches.count < 2,
          let expression = swiftmutAssignmentValueExpression(
            lineText,
            mutation: mutation,
            targetNames: targetNames,
            requiresDirectValueExpression: requiresDirectValueExpression
          ) else {
      return
    }
    matches.append((line, expression.column, expression.sourceOriginal, expression.sourceMutated))
  }

  func updateBraceDepth(_ lineText: String) {
    for byte in lineText.utf8 {
      if byte == 123 {
        braceDepth += 1
        sawOpeningBrace = true
      } else if byte == 125 {
        braceDepth -= 1
      }
    }
  }

  while index < text.endIndex {
    if text[index] == "\n" {
      let lineText = String(text[lineStart..<index])
      if currentLine >= functionLine {
        if sawOpeningBrace && braceDepth > 0 {
          inspectLine(lineText, line: currentLine)
          if matches.count >= 2 {
            break
          }
        }
        updateBraceDepth(lineText)
        if sawOpeningBrace && braceDepth <= 0 {
          break
        }
      }
      currentLine += 1
      lineStart = text.index(after: index)
    }
    index = text.index(after: index)
  }

  if index == text.endIndex && currentLine >= functionLine && sawOpeningBrace && braceDepth > 0 {
    inspectLine(String(text[lineStart..<text.endIndex]), line: currentLine)
  }

  guard matches.count == 1,
        let match = matches.first else {
    return nil
  }
  return (
    swiftmutTrimPackageRoot(path, config: config),
    match.line,
    match.column,
    match.sourceOriginal,
    match.sourceMutated)
}

private func swiftmutFindScopedLocalBindingValueSourceLocation(
  path: String,
  functionLine: Int,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig,
  targetNames: [String]
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard functionLine > 0,
        !targetNames.isEmpty,
        let text = swiftmutRead(path) else {
    return nil
  }

  var matches: [(line: Int, column: Int, sourceOriginal: String, sourceMutated: String)] = []
  var currentLine = 1
  var lineStart = text.startIndex
  var index = text.startIndex
  var braceDepth = 0
  var sawOpeningBrace = false

  func inspectLine(_ lineText: String, line: Int) {
    guard line >= functionLine,
          matches.count < 2,
          let expression = swiftmutLocalBindingValueExpression(
            lineText,
            mutation: mutation,
            targetNames: targetNames
          ) else {
      return
    }
    matches.append((line, expression.column, expression.sourceOriginal, expression.sourceMutated))
  }

  func updateBraceDepth(_ lineText: String) {
    for byte in lineText.utf8 {
      if byte == 123 {
        braceDepth += 1
        sawOpeningBrace = true
      } else if byte == 125 {
        braceDepth -= 1
      }
    }
  }

  while index < text.endIndex {
    if text[index] == "\n" {
      let lineText = String(text[lineStart..<index])
      if currentLine >= functionLine {
        if sawOpeningBrace && braceDepth > 0 {
          inspectLine(lineText, line: currentLine)
          if matches.count >= 2 {
            break
          }
        }
        updateBraceDepth(lineText)
        if sawOpeningBrace && braceDepth <= 0 {
          break
        }
      }
      currentLine += 1
      lineStart = text.index(after: index)
    }
    index = text.index(after: index)
  }

  if index == text.endIndex && currentLine >= functionLine && sawOpeningBrace && braceDepth > 0 {
    inspectLine(String(text[lineStart..<text.endIndex]), line: currentLine)
  }

  guard matches.count == 1,
        let match = matches.first else {
    return nil
  }
  return (
    swiftmutTrimPackageRoot(path, config: config),
    match.line,
    match.column,
    match.sourceOriginal,
    match.sourceMutated)
}

private func swiftmutFindScopedLabeledAssignmentValueSourceLocation(
  path: String,
  functionLine: Int,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig,
  targetNames: [String]
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard functionLine > 0,
        !targetNames.isEmpty,
        let text = swiftmutRead(path) else {
    return nil
  }

  var matches: [(line: Int, column: Int, sourceOriginal: String, sourceMutated: String)] = []
  var currentLine = 1
  var lineStart = text.startIndex
  var index = text.startIndex
  var braceDepth = 0
  var sawOpeningBrace = false

  func inspectLine(_ lineText: String, line: Int) {
    guard line >= functionLine,
          matches.count < 2,
          swiftmutLineContainsAnyIdentifier(lineText, identifiers: targetNames),
          let expression = swiftmutStandaloneLabeledValueExpression(
            lineText,
            mutation: mutation,
            requiresCallExpression: false
          ) else {
      return
    }
    matches.append((line, expression.column, expression.sourceOriginal, expression.sourceMutated))
  }

  func updateBraceDepth(_ lineText: String) {
    for byte in lineText.utf8 {
      if byte == 123 {
        braceDepth += 1
        sawOpeningBrace = true
      } else if byte == 125 {
        braceDepth -= 1
      }
    }
  }

  while index < text.endIndex {
    if text[index] == "\n" {
      let lineText = String(text[lineStart..<index])
      if currentLine >= functionLine {
        if sawOpeningBrace && braceDepth > 0 {
          inspectLine(lineText, line: currentLine)
          if matches.count >= 2 {
            break
          }
        }
        updateBraceDepth(lineText)
        if sawOpeningBrace && braceDepth <= 0 {
          break
        }
      }
      currentLine += 1
      lineStart = text.index(after: index)
    }
    index = text.index(after: index)
  }

  if index == text.endIndex && currentLine >= functionLine && sawOpeningBrace && braceDepth > 0 {
    inspectLine(String(text[lineStart..<text.endIndex]), line: currentLine)
  }

  guard matches.count == 1,
        let match = matches.first else {
    return nil
  }
  return (
    swiftmutTrimPackageRoot(path, config: config),
    match.line,
    match.column,
    match.sourceOriginal,
    match.sourceMutated)
}

private func swiftmutAssignmentValueSourceLocation(
  in text: String,
  path: String,
  lineRange: ClosedRange<Int>,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig,
  targetNames: [String] = [],
  requiresDirectValueExpression: Bool = false
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  var matches: [(line: Int, column: Int, sourceOriginal: String, sourceMutated: String)] = []
  var currentLine = 1
  var lineStart = text.startIndex
  var index = text.startIndex

  func inspectLine(_ lineText: String, line: Int) {
    guard lineRange.contains(line),
          matches.count < 2,
          let expression = swiftmutAssignmentValueExpression(
            lineText,
            mutation: mutation,
            targetNames: targetNames,
            requiresDirectValueExpression: requiresDirectValueExpression
          ) else {
      return
    }
    matches.append((line, expression.column, expression.sourceOriginal, expression.sourceMutated))
  }

  while index < text.endIndex {
    if text[index] == "\n" {
      inspectLine(String(text[lineStart..<index]), line: currentLine)
      if currentLine >= lineRange.upperBound || matches.count >= 2 {
        break
      }
      currentLine += 1
      lineStart = text.index(after: index)
    }
    index = text.index(after: index)
  }

  if index == text.endIndex && currentLine <= lineRange.upperBound {
    inspectLine(String(text[lineStart..<text.endIndex]), line: currentLine)
  }

  guard matches.count == 1,
        let match = matches.first else {
    return nil
  }
  return (
    swiftmutTrimPackageRoot(path, config: config),
    match.line,
    match.column,
    match.sourceOriginal,
    match.sourceMutated)
}

private func swiftmutFindOrdinalAssignmentValueSourceLocation(
  for store: StoreInst,
  path: String,
  preferredLine: Int,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard let ordinal = swiftmutAssignmentValueOrdinalAndCount(
    for: store,
    mutation: mutation,
    config: config
  ), ordinal.count <= 200 else {
    return nil
  }
  return swiftmutFindOrdinalAssignmentValueSourceLocation(
    path: path,
    preferredLine: preferredLine,
    ordinal: ordinal.ordinal,
    expectedCount: ordinal.count,
    mutation: mutation,
    config: config
  )
}

private func swiftmutAssignmentValueOrdinalAndCount(
  for store: StoreInst,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (ordinal: Int, count: Int)? {
  var ordinal = 0
  var count = 0
  var foundStore = false

  for block in store.parentFunction.blocks {
    for instruction in block.instructions {
      guard let candidate = instruction as? StoreInst,
            swiftmutAssignmentStoreIsEligible(candidate, config: config) else {
        continue
      }
      let mutations = swiftmutAssignmentValueMutations(for: candidate, config: config)
      guard mutations.contains(where: { $0.mutatedBuiltinName == mutation.mutatedBuiltinName }) else {
        continue
      }
      count += 1
      if candidate === store {
        ordinal = count
        foundStore = true
      }
    }
  }

  guard foundStore else {
    return nil
  }
  return (ordinal, count)
}

private func swiftmutFindOrdinalAssignmentValueSourceLocation(
  path: String,
  preferredLine: Int,
  ordinal: Int,
  expectedCount: Int,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard preferredLine > 0,
        ordinal > 0,
        ordinal <= expectedCount,
        expectedCount > 1,
        let text = swiftmutRead(path) else {
    return nil
  }

  var matches: [(line: Int, column: Int, sourceOriginal: String, sourceMutated: String)] = []
  var currentLine = 1
  var lineStart = text.startIndex
  var index = text.startIndex
  var braceDepth = 0
  var sawOpeningBrace = false

  func inspectLine(_ lineText: String, line: Int) {
    guard line >= preferredLine,
          matches.count <= expectedCount,
          let expression = swiftmutAssignmentValueExpression(
            lineText,
            mutation: mutation,
            requiresDirectValueExpression: true
          ) else {
      return
    }
    matches.append((line, expression.column, expression.sourceOriginal, expression.sourceMutated))
  }

  func updateBraceDepth(_ lineText: String) {
    for byte in lineText.utf8 {
      if byte == 123 {
        braceDepth += 1
        sawOpeningBrace = true
      } else if byte == 125 {
        braceDepth -= 1
      }
    }
  }

  while index < text.endIndex {
    if text[index] == "\n" {
      let lineText = String(text[lineStart..<index])
      if currentLine >= preferredLine {
        if sawOpeningBrace && braceDepth > 0 {
          inspectLine(lineText, line: currentLine)
          if matches.count > expectedCount {
            break
          }
        }
        updateBraceDepth(lineText)
        if sawOpeningBrace && braceDepth <= 0 {
          break
        }
      }
      currentLine += 1
      lineStart = text.index(after: index)
    }
    index = text.index(after: index)
  }

  if index == text.endIndex && currentLine >= preferredLine && sawOpeningBrace && braceDepth > 0 {
    inspectLine(String(text[lineStart..<text.endIndex]), line: currentLine)
  }

  guard matches.count == expectedCount else {
    return nil
  }
  let match = matches[ordinal - 1]
  return (
    swiftmutTrimPackageRoot(path, config: config),
    match.line,
    match.column,
    match.sourceOriginal,
    match.sourceMutated)
}

private func swiftmutValueApplySourceLocation(
  for apply: ApplyInst,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  let functionSourceLocation = swiftmutFunctionSourceLocation(
    for: apply.parentFunction,
    config: config
  )
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

private func swiftmutAssignmentValueSourceLocation(
  for store: StoreInst,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  let destinationNames = swiftmutAssignmentDestinationNames(for: store)
  let sourceNames = swiftmutAssignmentSourceNames(for: store)
  let targetNames = destinationNames.isEmpty
    ? swiftmutUniqueAssignmentNames(sourceNames)
    : swiftmutUniqueAssignmentNames(destinationNames)
  let functionSourceLocation = swiftmutFunctionSourceLocation(
    for: store.parentFunction,
    config: config
  )
  if let fileNameAndPosition = store.location.fileNameAndPosition {
    let path = fileNameAndPosition.path.string
    if let matchedPath = swiftmutIncludedSourcePath(path, config: config) {
      if let anchored = swiftmutFindAssignmentValueSourceLocation(
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        mutation: mutation,
        config: config,
        targetNames: targetNames,
        requiresDirectValueExpression: true
      ) {
        return anchored
      }
      if !targetNames.isEmpty,
         let anchored = swiftmutFindAssignmentValueSourceLocation(
           path: matchedPath,
           preferredLine: fileNameAndPosition.line,
           mutation: mutation,
           config: config,
           targetNames: targetNames,
           requiresDirectValueExpression: false
         ) {
        return anchored
      }
      if let functionSourceLocation,
         functionSourceLocation.path == matchedPath,
         let anchored = swiftmutFindOrdinalAssignmentValueSourceLocation(
           for: store,
           path: matchedPath,
           preferredLine: functionSourceLocation.line,
           mutation: mutation,
           config: config
         ) {
        return anchored
      }
    }
  }

  if let definingInstruction = store.source.definingInstruction,
     let fileNameAndPosition = definingInstruction.location.fileNameAndPosition {
    let path = fileNameAndPosition.path.string
    if let matchedPath = swiftmutIncludedSourcePath(path, config: config) {
      if let anchored = swiftmutFindAssignmentValueSourceLocation(
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        mutation: mutation,
        config: config,
        targetNames: targetNames,
        requiresDirectValueExpression: true
      ) {
        return anchored
      }
      if !targetNames.isEmpty,
         let anchored = swiftmutFindAssignmentValueSourceLocation(
           path: matchedPath,
           preferredLine: fileNameAndPosition.line,
           mutation: mutation,
           config: config,
           targetNames: targetNames,
           requiresDirectValueExpression: false
         ) {
        return anchored
      }
    }
  }

  if let functionSourceLocation {
    if let anchored = swiftmutFindScopedAssignmentValueSourceLocation(
      path: functionSourceLocation.path,
      functionLine: functionSourceLocation.line,
      mutation: mutation,
      config: config,
      targetNames: targetNames,
      requiresDirectValueExpression: true
    ) {
      return anchored
    }
    if !targetNames.isEmpty,
       let anchored = swiftmutFindScopedAssignmentValueSourceLocation(
         path: functionSourceLocation.path,
         functionLine: functionSourceLocation.line,
         mutation: mutation,
         config: config,
         targetNames: targetNames,
         requiresDirectValueExpression: false
       ) {
      return anchored
    }
    if let anchored = swiftmutFindStoreSnippetAssignmentValueSourceLocation(
      for: store,
      path: functionSourceLocation.path,
      functionLine: functionSourceLocation.line,
      mutation: mutation,
      config: config,
      targetNames: targetNames
    ) {
      return anchored
    }
    if let anchored = swiftmutFindStoreUsageSnippetAssignmentValueSourceLocation(
      for: store,
      path: functionSourceLocation.path,
      functionLine: functionSourceLocation.line,
      mutation: mutation,
      config: config,
      targetNames: targetNames
    ) {
      return anchored
    }
    if let anchored = swiftmutFindAssignmentValueSourceLocation(
      path: functionSourceLocation.path,
      preferredLine: functionSourceLocation.line,
      mutation: mutation,
      config: config,
      targetNames: targetNames,
      requiresDirectValueExpression: true
    ) {
      return anchored
    }
    if !targetNames.isEmpty,
       let anchored = swiftmutFindAssignmentValueSourceLocation(
         path: functionSourceLocation.path,
         preferredLine: functionSourceLocation.line,
         mutation: mutation,
         config: config,
         targetNames: targetNames,
         requiresDirectValueExpression: false
       ) {
      return anchored
    }
    if let anchored = swiftmutFindOrdinalAssignmentValueSourceLocation(
      for: store,
      path: functionSourceLocation.path,
      preferredLine: functionSourceLocation.line,
      mutation: mutation,
      config: config
    ) {
      return anchored
    }
    if let anchored = swiftmutFindScopedLocalBindingValueSourceLocation(
      path: functionSourceLocation.path,
      functionLine: functionSourceLocation.line,
      mutation: mutation,
      config: config,
      targetNames: targetNames
    ) {
      return anchored
    }
    if let anchored = swiftmutFindScopedLabeledAssignmentValueSourceLocation(
      path: functionSourceLocation.path,
      functionLine: functionSourceLocation.line,
      mutation: mutation,
      config: config,
      targetNames: targetNames
    ) {
      return anchored
    }
    if let anchored = swiftmutFindFunctionSignatureAssignmentValueSourceLocation(
      path: functionSourceLocation.path,
      functionLine: functionSourceLocation.line,
      mutation: mutation,
      config: config,
      targetNames: targetNames
    ) {
      return anchored
    }
    if let definingInstruction = store.source.definingInstruction,
       let anchored = swiftmutFindSourceSnippetAssignmentValueSourceLocation(
         path: functionSourceLocation.path,
         locationDescription: definingInstruction.location.description,
         mutation: mutation,
         config: config,
         targetNames: targetNames
       ) {
      return anchored
    }
  }
  if !targetNames.isEmpty {
    if let definingInstruction = store.source.definingInstruction,
       let anchored = swiftmutFindDescribedAssignmentValueSourceLocation(
         locationDescription: definingInstruction.location.description,
         mutation: mutation,
         config: config,
         targetNames: targetNames
       ) {
      return anchored
    }
    if let anchored = swiftmutFindDescribedAssignmentValueSourceLocation(
      locationDescription: store.location.description,
      mutation: mutation,
      config: config,
      targetNames: targetNames
    ) {
      return anchored
    }
  }
  return nil
}

private func swiftmutFindDescribedAssignmentValueSourceLocation(
  locationDescription: String,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig,
  targetNames: [String]
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard !targetNames.isEmpty,
        let rawSnippet = swiftmutQuotedSourceSearchSnippet(locationDescription),
        rawSnippet.count >= 2 else {
    return nil
  }

  let snippet = swiftmutDecodedSourceSnippet(rawSnippet)
  let expressionStart = swiftmutSnippetExpressionStartOffset(snippet)
  guard expressionStart >= 0,
        let expression = swiftmutDefaultArgumentSnippetExpression(snippet, mutation: mutation) else {
    return nil
  }

  var matches: [(path: String, line: Int, column: Int)] = []
  for path in swiftmutSwiftSourcePaths(config: config) {
    guard let text = swiftmutRead(path) else {
      continue
    }
    for match in swiftmutSourceSnippetMatches(snippet, in: text) {
      let expressionColumn = match.column + expressionStart
      guard let lineText = swiftmutSourceLine(text, line: match.line),
            swiftmutDescribedAssignmentLineIsMappable(
              lineText,
              expression: expression,
              expressionColumn: expressionColumn,
              targetNames: targetNames
            ) else {
        continue
      }
      matches.append((path, match.line, expressionColumn))
      if matches.count >= 2 {
        break
      }
    }
    if matches.count >= 2 {
      break
    }
  }

  guard matches.count == 1,
        let match = matches.first else {
    return nil
  }
  return (
    swiftmutTrimPackageRoot(match.path, config: config),
    match.line,
    match.column,
    expression,
    swiftmutImplicitReturnSourceMutation(for: mutation))
}

private func swiftmutDescribedAssignmentLineIsMappable(
  _ line: String,
  expression: String,
  expressionColumn: Int,
  targetNames: [String]
) -> Bool {
  guard swiftmutLineContainsAnyIdentifier(line, identifiers: targetNames) else {
    return false
  }

  let bytes = Array(line.utf8)
  let expressionStart = max(0, min(bytes.count, expressionColumn - 1))
  if expressionStart > 0 {
    for index in 0..<expressionStart where bytes[index] == 61 {
      return true
    }
  }

  if targetNames.contains(expression) {
    return false
  }

  for targetName in targetNames {
    guard let targetRange = swiftmutFindSourceIdentifier(
      targetName,
      in: bytes,
      start: 0,
      end: expressionStart
    ) else {
      continue
    }
    let colonIndex = swiftmutSkipHorizontalWhitespace(bytes, from: targetRange.end)
    if colonIndex < expressionStart && bytes[colonIndex] == 58 {
      return true
    }
  }
  return false
}

private func swiftmutFindFunctionSignatureAssignmentValueSourceLocation(
  path: String,
  functionLine: Int,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig,
  targetNames: [String]
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard functionLine > 0,
        !targetNames.isEmpty,
        let text = swiftmutRead(path) else {
    return nil
  }

  var matches: [(line: Int, column: Int, sourceOriginal: String, sourceMutated: String)] = []
  var currentLine = 1
  var lineStart = text.startIndex
  var index = text.startIndex

  func inspectLine(_ lineText: String, line: Int) {
    guard line >= functionLine,
          matches.count < 2,
          let expression = swiftmutSignatureAssignmentValueExpression(
            lineText,
            mutation: mutation,
            targetNames: targetNames
          ) else {
      return
    }
    matches.append((line, expression.column, expression.sourceOriginal, expression.sourceMutated))
  }

  while index < text.endIndex {
    if text[index] == "\n" {
      let lineText = String(text[lineStart..<index])
      if currentLine >= functionLine {
        inspectLine(lineText, line: currentLine)
        if matches.count >= 2 || swiftmutLineOpensFunctionBody(lineText) || currentLine > functionLine + 120 {
          break
        }
      }
      currentLine += 1
      lineStart = text.index(after: index)
    }
    index = text.index(after: index)
  }

  if index == text.endIndex && currentLine >= functionLine {
    let lineText = String(text[lineStart..<text.endIndex])
    inspectLine(lineText, line: currentLine)
  }

  guard matches.count == 1,
        let match = matches.first else {
    return nil
  }
  return (
    swiftmutTrimPackageRoot(path, config: config),
    match.line,
    match.column,
    match.sourceOriginal,
    match.sourceMutated)
}

private func swiftmutFindSourceSnippetAssignmentValueSourceLocation(
  path: String,
  locationDescription: String,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig,
  targetNames: [String]
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard !targetNames.isEmpty,
        let expectedExpression = swiftmutSourceSnippetValueExpression(locationDescription),
        let text = swiftmutRead(path) else {
    return nil
  }

  var matches: [(line: Int, column: Int, sourceOriginal: String, sourceMutated: String)] = []
  var currentLine = 1
  var lineStart = text.startIndex
  var index = text.startIndex

  func inspectLine(_ lineText: String, line: Int) {
    guard matches.count < 2,
          let expression = swiftmutAssignmentOrLocalBindingValueExpression(
            lineText,
            mutation: mutation,
            targetNames: targetNames
          ),
          swiftmutStoreLocationExpressionMatches(
            expression.sourceOriginal,
            expected: expectedExpression
          ) else {
      return
    }
    matches.append((line, expression.column, expression.sourceOriginal, expression.sourceMutated))
  }

  while index < text.endIndex {
    if text[index] == "\n" {
      inspectLine(String(text[lineStart..<index]), line: currentLine)
      if matches.count >= 2 {
        break
      }
      currentLine += 1
      lineStart = text.index(after: index)
    }
    index = text.index(after: index)
  }

  if index == text.endIndex {
    inspectLine(String(text[lineStart..<text.endIndex]), line: currentLine)
  }

  guard matches.count == 1,
        let match = matches.first else {
    return nil
  }
  return (
    swiftmutTrimPackageRoot(path, config: config),
    match.line,
    match.column,
    match.sourceOriginal,
    match.sourceMutated)
}

private func swiftmutAssignmentOrLocalBindingValueExpression(
  _ line: String,
  mutation: SwiftmutMutation,
  targetNames: [String]
) -> (column: Int, sourceOriginal: String, sourceMutated: String)? {
  if let assignment = swiftmutAssignmentValueExpression(
    line,
    mutation: mutation,
    targetNames: targetNames,
    requiresDirectValueExpression: false
  ) {
    return assignment
  }
  return swiftmutLocalBindingValueExpression(
    line,
    mutation: mutation,
    targetNames: targetNames
  )
}

private func swiftmutFindStoreSnippetAssignmentValueSourceLocation(
  for store: StoreInst,
  path: String,
  functionLine: Int,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig,
  targetNames: [String]
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard functionLine > 0,
        !targetNames.isEmpty,
        let expectedExpression = swiftmutStoreLocationAssignedExpression(store.location.description),
        let text = swiftmutRead(path) else {
    return nil
  }

  var matches: [(line: Int, column: Int, sourceOriginal: String, sourceMutated: String)] = []
  var currentLine = 1
  var lineStart = text.startIndex
  var index = text.startIndex
  var braceDepth = 0
  var sawOpeningBrace = false

  func inspectLine(_ lineText: String, line: Int) {
    guard line >= functionLine,
          matches.count < 2,
          let expression = swiftmutAssignmentValueExpression(
            lineText,
            mutation: mutation,
            targetNames: targetNames,
            requiresDirectValueExpression: false
          ),
          swiftmutStoreLocationExpressionMatches(
            expression.sourceOriginal,
            expected: expectedExpression
          ) else {
      return
    }
    matches.append((line, expression.column, expression.sourceOriginal, expression.sourceMutated))
  }

  func updateBraceDepth(_ lineText: String) {
    for byte in lineText.utf8 {
      if byte == 123 {
        braceDepth += 1
        sawOpeningBrace = true
      } else if byte == 125 {
        braceDepth -= 1
      }
    }
  }

  while index < text.endIndex {
    if text[index] == "\n" {
      let lineText = String(text[lineStart..<index])
      if currentLine >= functionLine {
        if sawOpeningBrace && braceDepth > 0 {
          inspectLine(lineText, line: currentLine)
          if matches.count >= 2 {
            break
          }
        }
        updateBraceDepth(lineText)
        if sawOpeningBrace && braceDepth <= 0 {
          break
        }
      }
      currentLine += 1
      lineStart = text.index(after: index)
    }
    index = text.index(after: index)
  }

  if index == text.endIndex && currentLine >= functionLine && sawOpeningBrace && braceDepth > 0 {
    inspectLine(String(text[lineStart..<text.endIndex]), line: currentLine)
  }

  guard matches.count == 1,
        let match = matches.first else {
    return nil
  }
  return (
    swiftmutTrimPackageRoot(path, config: config),
    match.line,
    match.column,
    match.sourceOriginal,
    match.sourceMutated)
}

private func swiftmutFindStoreUsageSnippetAssignmentValueSourceLocation(
  for store: StoreInst,
  path: String,
  functionLine: Int,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig,
  targetNames: [String]
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard functionLine > 0,
        !targetNames.isEmpty,
        let snippet = swiftmutQuotedSourceSnippetPrefix(store.location.description),
        let comparison = swiftmutStoreUsageComparisonSnippet(snippet),
        let text = swiftmutRead(path) else {
    return nil
  }

  var matches: [(line: Int, column: Int, sourceOriginal: String, sourceMutated: String)] = []
  var currentLine = 1
  var lineStart = text.startIndex
  var index = text.startIndex
  var braceDepth = 0
  var sawOpeningBrace = false

  func inspectLine(_ lineText: String, line: Int) {
    guard line >= functionLine,
          matches.count < 2 else {
      return
    }
    for targetName in targetNames {
      guard let column = swiftmutLineColumn(
        ofTarget: targetName,
        followedBy: comparison,
        in: lineText
      ) else {
        continue
      }
      matches.append((
        line,
        column,
        targetName,
        swiftmutImplicitReturnSourceMutation(for: mutation)))
      if matches.count >= 2 {
        return
      }
    }
  }

  func updateBraceDepth(_ lineText: String) {
    for byte in lineText.utf8 {
      if byte == 123 {
        braceDepth += 1
        sawOpeningBrace = true
      } else if byte == 125 {
        braceDepth -= 1
      }
    }
  }

  while index < text.endIndex {
    if text[index] == "\n" {
      let lineText = String(text[lineStart..<index])
      if currentLine >= functionLine {
        if sawOpeningBrace && braceDepth > 0 {
          inspectLine(lineText, line: currentLine)
          if matches.count >= 2 {
            break
          }
        }
        updateBraceDepth(lineText)
        if sawOpeningBrace && braceDepth <= 0 {
          break
        }
      }
      currentLine += 1
      lineStart = text.index(after: index)
    }
    index = text.index(after: index)
  }

  if index == text.endIndex && currentLine >= functionLine && sawOpeningBrace && braceDepth > 0 {
    inspectLine(String(text[lineStart..<text.endIndex]), line: currentLine)
  }

  guard matches.count == 1,
        let match = matches.first else {
    return nil
  }
  return (
    swiftmutTrimPackageRoot(path, config: config),
    match.line,
    match.column,
    match.sourceOriginal,
    match.sourceMutated)
}

private func swiftmutStoreLocationAssignedExpression(_ description: String) -> String? {
  guard let snippet = swiftmutQuotedSourceSnippetPrefix(description) else {
    return nil
  }

  let bytes = Array(snippet.utf8)
  guard bytes.count > 1,
        bytes[0] == 61 else {
    return nil
  }
  let expressionStart = swiftmutSkipHorizontalWhitespace(bytes, from: 2)
  let trimmedEnd = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  guard expressionStart < trimmedEnd else {
    return nil
  }
  return String(decoding: bytes[expressionStart..<trimmedEnd], as: UTF8.self)
}

private func swiftmutSourceSnippetValueExpression(_ description: String) -> String? {
  guard let snippet = swiftmutQuotedSourceSnippetPrefix(description) else {
    return nil
  }

  let bytes = Array(snippet.utf8)
  let start = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
  var end = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  if end > start && bytes[end - 1] == 44 {
    end = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: end - 1)
  }
  guard start < end else {
    return nil
  }

  if bytes[start] == 40 {
    var index = start + 1
    while index + 4 <= end {
      if swiftmutASCIIHasExactPrefix(bytes, start: index, prefix: "let ") {
        let nameStart = swiftmutSkipHorizontalWhitespace(bytes, from: index + 3)
        guard nameStart < end && swiftmutIsIdentifierStartByte(bytes[nameStart]) else {
          return nil
        }
        var nameEnd = nameStart + 1
        while nameEnd < end && swiftmutIsIdentifierByte(bytes[nameEnd]) {
          nameEnd += 1
        }
        return String(decoding: bytes[nameStart..<nameEnd], as: UTF8.self)
      }
      index += 1
    }
  }

  while end > start {
    let byte = bytes[end - 1]
    if byte == 41 || byte == 93 || byte == 125 {
      end = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: end - 1)
      continue
    }
    break
  }
  guard start < end else {
    return nil
  }
  return String(decoding: bytes[start..<end], as: UTF8.self)
}

private func swiftmutStoreLocationExpressionMatches(
  _ expression: String,
  expected: String
) -> Bool {
  if expression == expected {
    return true
  }
  guard expected.utf8.count >= 8 else {
    return false
  }
  return expression.hasPrefix(expected)
}

private func swiftmutStoreUsageComparisonSnippet(_ snippet: String) -> (operatorText: String, rhsText: String)? {
  let bytes = Array(snippet.utf8)
  var index = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
  guard index < bytes.count else {
    return nil
  }

  let operators = ["!=", "==", ">=", "<=", ">", "<"]
  var matchedOperator: String?
  for operatorText in operators {
    if swiftmutASCIIHasExactPrefix(bytes, start: index, prefix: operatorText) {
      matchedOperator = operatorText
      index += operatorText.utf8.count
      break
    }
  }
  guard let operatorText = matchedOperator else {
    return nil
  }

  index = swiftmutSkipHorizontalWhitespace(bytes, from: index)
  let rhsStart = index
  while index < bytes.count && !swiftmutIsHorizontalWhitespace(bytes[index]) {
    index += 1
  }
  guard rhsStart < index else {
    return nil
  }
  let rhsText = String(decoding: bytes[rhsStart..<index], as: UTF8.self)
  return (operatorText, rhsText)
}

private func swiftmutLineColumn(
  ofTarget targetName: String,
  followedBy comparison: (operatorText: String, rhsText: String),
  in line: String
) -> Int? {
  let bytes = Array(line.utf8)
  let targetBytes = Array(targetName.utf8)
  let operatorBytes = Array(comparison.operatorText.utf8)
  let rhsBytes = Array(comparison.rhsText.utf8)
  guard !targetBytes.isEmpty,
        !operatorBytes.isEmpty,
        !rhsBytes.isEmpty,
        bytes.count >= targetBytes.count else {
    return nil
  }

  var index = 0
  while index + targetBytes.count <= bytes.count {
    if swiftmutIdentifierTokenMatches(bytes, index: index, end: bytes.count, tokenBytes: targetBytes) {
      var cursor = swiftmutSkipHorizontalWhitespace(bytes, from: index + targetBytes.count)
      if swiftmutBytesMatch(bytes, start: cursor, pattern: operatorBytes) {
        cursor = swiftmutSkipHorizontalWhitespace(bytes, from: cursor + operatorBytes.count)
        if swiftmutBytesMatch(bytes, start: cursor, pattern: rhsBytes) {
          return index + 1
        }
      }
    }
    index += 1
  }
  return nil
}

private func swiftmutIdentifierTokenMatches(
  _ bytes: [UInt8],
  index: Int,
  end: Int,
  tokenBytes: [UInt8]
) -> Bool {
  guard index + tokenBytes.count <= end else {
    return false
  }
  if index > 0 && swiftmutIsIdentifierByte(bytes[index - 1]) {
    return false
  }
  let after = index + tokenBytes.count
  if after < end && swiftmutIsIdentifierByte(bytes[after]) {
    return false
  }
  return swiftmutBytesMatch(bytes, start: index, pattern: tokenBytes)
}

private func swiftmutBytesMatch(_ bytes: [UInt8], start: Int, pattern: [UInt8]) -> Bool {
  guard start >= 0,
        start + pattern.count <= bytes.count else {
    return false
  }
  for offset in 0..<pattern.count where bytes[start + offset] != pattern[offset] {
    return false
  }
  return true
}

private func swiftmutQuotedSourceSnippetPrefix(_ description: String) -> String? {
  let bytes = Array(description.utf8)
  guard bytes.count > 1,
        bytes[0] == 34 else {
    return nil
  }

  var end = 1
  while end < bytes.count {
    if bytes[end] == 10 || bytes[end] == 13 {
      break
    }
    if end + 4 <= bytes.count,
       bytes[end] == 91,
       bytes[end + 1] == 46,
       bytes[end + 2] == 46,
       bytes[end + 3] == 46 {
      break
    }
    if end + 9 <= bytes.count,
       bytes[end] == 34,
       bytes[end + 1] == 44,
       bytes[end + 2] == 32,
       bytes[end + 3] == 115,
       bytes[end + 4] == 99,
       bytes[end + 5] == 111,
       bytes[end + 6] == 112,
       bytes[end + 7] == 101,
       bytes[end + 8] == 61 {
      break
    }
    end += 1
  }

  let trimmedEnd = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: end)
  guard trimmedEnd > 1 else {
    return nil
  }
  return String(decoding: bytes[1..<trimmedEnd], as: UTF8.self)
}

private func swiftmutFunctionSourceLocation(
  for function: Function,
  config: SwiftmutConfig
) -> (path: String, line: Int)? {
  let location = function.location.description
  for path in swiftmutSwiftSourcePaths(config: config) {
    guard location.contains(path),
          let line = swiftmutPreferredLine(in: location, path: path) else {
      continue
    }
    return (path, line)
  }
  return nil
}

private func swiftmutFindValueExpressionSourceLocation(
  for apply: ApplyInst,
  path: String,
  preferredLine: Int,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  if let anchored = swiftmutFindAssignmentValueSourceLocation(
    path: path,
    preferredLine: preferredLine,
    mutation: mutation,
    config: config
  ) {
    return anchored
  }
  if let anchored = swiftmutFindLabeledValueExpressionSourceLocation(
    path: path,
    preferredLine: preferredLine,
    mutation: mutation,
    config: config
  ) {
    return anchored
  }
  if let anchored = swiftmutFindStandaloneValueExpressionSourceLocation(
    path: path,
    preferredLine: preferredLine,
    mutation: mutation,
    config: config
  ) {
    return anchored
  }
  if let anchored = swiftmutFindUniqueExplicitReturnSourceLocation(
    path: path,
    preferredLine: preferredLine,
    mutation: mutation,
    config: config
  ) {
    return anchored
  }
  if let anchored = swiftmutFindUniqueImplicitReturnSourceLocation(
    path: path,
    preferredLine: preferredLine,
    mutation: mutation,
    config: config
  ) {
    return anchored
  }
  if let anchored = swiftmutFindCalleeOrdinalValueExpressionSourceLocation(
    for: apply,
    path: path,
    preferredLine: preferredLine,
    mutation: mutation,
    config: config
  ) {
    return anchored
  }
  return nil
}

private func swiftmutFindOrdinalValueExpressionSourceLocation(
  for apply: ApplyInst,
  path: String,
  preferredLine: Int,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard let ordinal = swiftmutValueApplyOrdinalAndCount(
    for: apply,
    mutation: mutation,
    config: config
  ), ordinal.count <= 200 else {
    return nil
  }
  return swiftmutFindOrdinalValueExpressionSourceLocation(
    path: path,
    preferredLine: preferredLine,
    ordinal: ordinal.ordinal,
    expectedCount: ordinal.count,
    mutation: mutation,
    config: config
  )
}

private func swiftmutValueApplyOrdinalAndCount(
  for apply: ApplyInst,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (ordinal: Int, count: Int)? {
  var ordinal = 0
  var count = 0
  var foundApply = false

  for block in apply.parentFunction.blocks {
    for instruction in block.instructions {
      guard let candidate = instruction as? ApplyInst,
            !candidate.type.isVoid else {
        continue
      }
      let mutations = swiftmutValueReplacementMutations(
        for: candidate,
        valueType: candidate.type,
        config: config
      )
      guard mutations.contains(where: { $0.mutatedBuiltinName == mutation.mutatedBuiltinName }) else {
        continue
      }
      count += 1
      if candidate === apply {
        ordinal = count
        foundApply = true
      }
    }
  }

  guard foundApply else {
    return nil
  }
  return (ordinal, count)
}

private func swiftmutFindOrdinalValueExpressionSourceLocation(
  path: String,
  preferredLine: Int,
  ordinal: Int,
  expectedCount: Int,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard preferredLine > 0,
        ordinal > 0,
        ordinal <= expectedCount,
        expectedCount > 1,
        let text = swiftmutRead(path) else {
    return nil
  }

  var matches: [(line: Int, column: Int, sourceOriginal: String, sourceMutated: String)] = []
  var currentLine = 1
  var lineStart = text.startIndex
  var index = text.startIndex
  var braceDepth = 0
  var sawOpeningBrace = false

  func inspectLine(_ lineText: String, line: Int) {
    guard line >= preferredLine,
          matches.count <= expectedCount,
          let expression = swiftmutOrdinalValueExpression(lineText, mutation: mutation) else {
      return
    }
    matches.append((line, expression.column, expression.sourceOriginal, expression.sourceMutated))
  }

  func updateBraceDepth(_ lineText: String) {
    for byte in lineText.utf8 {
      if byte == 123 {
        braceDepth += 1
        sawOpeningBrace = true
      } else if byte == 125 {
        braceDepth -= 1
      }
    }
  }

  while index < text.endIndex {
    if text[index] == "\n" {
      let lineText = String(text[lineStart..<index])
      if currentLine >= preferredLine {
        if sawOpeningBrace && braceDepth > 0 {
          inspectLine(lineText, line: currentLine)
          if matches.count > expectedCount {
            break
          }
        }
        updateBraceDepth(lineText)
        if sawOpeningBrace && braceDepth <= 0 {
          break
        }
      }
      currentLine += 1
      lineStart = text.index(after: index)
    }
    index = text.index(after: index)
  }

  if index == text.endIndex && currentLine >= preferredLine && sawOpeningBrace && braceDepth > 0 {
    inspectLine(String(text[lineStart..<text.endIndex]), line: currentLine)
  }

  guard matches.count == expectedCount else {
    return nil
  }
  let match = matches[ordinal - 1]
  return (
    swiftmutTrimPackageRoot(path, config: config),
    match.line,
    match.column,
    match.sourceOriginal,
    match.sourceMutated)
}

private func swiftmutFindCalleeOrdinalValueExpressionSourceLocation(
  for apply: ApplyInst,
  path: String,
  preferredLine: Int,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  let identifiers = swiftmutSourceExpressionIdentifiers(for: apply)
  guard !identifiers.isEmpty,
        let ordinal = swiftmutValueApplyOrdinal(for: apply, matchingAnyOf: identifiers, config: config),
        let text = swiftmutRead(path) else {
    return nil
  }

  let candidates = swiftmutCalleeExpressionSourceCandidates(
    in: text,
    path: path,
    preferredLine: preferredLine,
    identifiers: identifiers,
    mutation: mutation,
    config: config
  )
  guard ordinal > 0,
        ordinal <= candidates.count else {
    return nil
  }
  return candidates[ordinal - 1]
}

private func swiftmutFindStandaloneValueExpressionSourceLocation(
  path: String,
  preferredLine: Int,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard preferredLine > 0,
        let sourceLine = swiftmutAbsoluteSourceLine(path: path, line: preferredLine),
        let expression = swiftmutStandaloneValueExpression(sourceLine, mutation: mutation) else {
    return nil
  }
  return (
    swiftmutTrimPackageRoot(path, config: config),
    preferredLine,
    expression.column,
    expression.sourceOriginal,
    expression.sourceMutated)
}

private func swiftmutValueApplyOrdinal(
  for apply: ApplyInst,
  matchingAnyOf identifiers: [String],
  config: SwiftmutConfig
) -> Int? {
  var ordinal = 0
  for block in apply.parentFunction.blocks {
    for instruction in block.instructions {
      guard let candidate = instruction as? ApplyInst,
            !candidate.type.isVoid,
            !swiftmutValueReplacementMutations(
              for: candidate,
              valueType: candidate.type,
              config: config
            ).isEmpty,
            swiftmutSourceCalleeIdentifiers(for: candidate).contains(where: { identifiers.contains($0) }) else {
        continue
      }
      ordinal += 1
      if candidate === apply {
        return ordinal
      }
    }
  }
  return nil
}

private func swiftmutCalleeExpressionSourceCandidates(
  in text: String,
  path: String,
  preferredLine: Int,
  identifiers: [String],
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> [(file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)] {
  guard preferredLine > 0 else {
    return []
  }
  let lastLine = preferredLine + 220
  var candidates: [(file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)] = []
  var currentLine = 1
  var lineStart = text.startIndex
  var index = text.startIndex

  func inspectLine(_ lineText: String, line: Int) {
    guard line >= preferredLine,
          line <= lastLine,
          swiftmutSourceLineContainsExpressionIdentifier(lineText, identifiers: identifiers),
          let expression = swiftmutValueExpressionOnLine(
            lineText,
            identifiers: identifiers,
            mutation: mutation
          ) else {
      return
    }
    candidates.append((
      swiftmutTrimPackageRoot(path, config: config),
      line,
      expression.column,
      expression.sourceOriginal,
      expression.sourceMutated
    ))
  }

  while index < text.endIndex {
    if text[index] == "\n" {
      inspectLine(String(text[lineStart..<index]), line: currentLine)
      if currentLine >= lastLine {
        break
      }
      currentLine += 1
      lineStart = text.index(after: index)
    }
    index = text.index(after: index)
  }

  if index == text.endIndex && currentLine <= lastLine {
    inspectLine(String(text[lineStart..<text.endIndex]), line: currentLine)
  }
  return candidates
}

private func swiftmutFindDescribedValueExpressionSourceLocation(
  for apply: ApplyInst,
  path: String,
  functionLine: Int,
  locationDescription: String,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard functionLine > 0,
        let snippet = swiftmutQuotedSourceSnippetPrefix(locationDescription),
        swiftmutDescribedValueSnippetLooksMappable(snippet),
        let text = swiftmutRead(path) else {
    return nil
  }

  let prefixes = swiftmutDescribedValueSnippetPrefixes(snippet)
  guard !prefixes.isEmpty else {
    return nil
  }

  let identifiers = swiftmutSourceExpressionIdentifiers(for: apply)
  var matches: [(line: Int, column: Int, sourceOriginal: String, sourceMutated: String)] = []
  var currentLine = 1
  var lineStart = text.startIndex
  var index = text.startIndex
  var braceDepth = 0
  var sawOpeningBrace = false

  func inspectLine(_ lineText: String, line: Int) {
    guard line >= functionLine,
          matches.count < 2 else {
      return
    }
    let bytes = Array(lineText.utf8)
    let start = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
    let end = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
    guard start < end else {
      return
    }

    for prefix in prefixes {
      guard let matchStart = swiftmutASCIIIndex(bytes, start: start, end: end, pattern: prefix),
            let expression = swiftmutDescribedValueExpression(
              bytes: bytes,
              matchStart: matchStart,
              lineEnd: end,
              identifiers: identifiers,
              mutation: mutation
            ) else {
        continue
      }
      matches.append((line, expression.column, expression.sourceOriginal, expression.sourceMutated))
      return
    }
  }

  func updateBraceDepth(_ lineText: String) {
    for byte in lineText.utf8 {
      if byte == 123 {
        braceDepth += 1
        sawOpeningBrace = true
      } else if byte == 125 {
        braceDepth -= 1
      }
    }
  }

  while index < text.endIndex {
    if text[index] == "\n" {
      let lineText = String(text[lineStart..<index])
      if currentLine >= functionLine {
        if sawOpeningBrace && braceDepth > 0 {
          inspectLine(lineText, line: currentLine)
          if matches.count >= 2 {
            break
          }
        }
        updateBraceDepth(lineText)
        if sawOpeningBrace && braceDepth <= 0 {
          break
        }
      }
      currentLine += 1
      lineStart = text.index(after: index)
    }
    index = text.index(after: index)
  }

  if index == text.endIndex && currentLine >= functionLine && sawOpeningBrace && braceDepth > 0 {
    inspectLine(String(text[lineStart..<text.endIndex]), line: currentLine)
  }

  guard matches.count == 1,
        let match = matches.first else {
    return nil
  }
  return (
    swiftmutTrimPackageRoot(path, config: config),
    match.line,
    match.column,
    match.sourceOriginal,
    match.sourceMutated)
}

private func swiftmutDescribedValueSnippetLooksMappable(_ snippet: String) -> Bool {
  let bytes = Array(snippet.utf8)
  var start = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
  guard start < bytes.count else {
    return false
  }
  if start + 1 < bytes.count
      && (bytes[start] == 38 || bytes[start] == 124)
      && bytes[start + 1] == bytes[start] {
    start = swiftmutSkipHorizontalWhitespace(bytes, from: start + 2)
  }
  if start < bytes.count && bytes[start] == 33 {
    start = swiftmutSkipHorizontalWhitespace(bytes, from: start + 1)
  }
  guard start < bytes.count,
        !swiftmutASCIIHasExactPrefix(bytes, start: start, prefix: "()") else {
    return false
  }
  let first = bytes[start]
  return (first >= 65 && first <= 90) || (first >= 97 && first <= 122) || first == 95
}

private func swiftmutDescribedValueSnippetPrefixes(_ snippet: String) -> [String] {
  let bytes = Array(snippet.utf8)
  let start = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
  let end = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  guard start < end else {
    return []
  }

  var prefixes: [String] = []
  func appendPrefix(start: Int) {
    let trimmedStart = swiftmutSkipHorizontalWhitespace(bytes, from: start)
    guard trimmedStart < end,
          end - trimmedStart >= 5 else {
      return
    }
    let prefix = String(decoding: bytes[trimmedStart..<end], as: UTF8.self)
    if !prefixes.contains(prefix) {
      prefixes.append(prefix)
    }
  }

  appendPrefix(start: start)
  if start + 1 < end
      && (bytes[start] == 38 || bytes[start] == 124)
      && bytes[start + 1] == bytes[start] {
    appendPrefix(start: start + 2)
  }
  if start < end && bytes[start] == 33 {
    appendPrefix(start: start + 1)
  }
  return prefixes
}

private func swiftmutDescribedValueExpression(
  bytes: [UInt8],
  matchStart: Int,
  lineEnd: Int,
  identifiers: [String],
  mutation: SwiftmutMutation
) -> (column: Int, sourceOriginal: String, sourceMutated: String)? {
  let expressionSearchStart = swiftmutDescribedValueExpressionSearchStart(
    bytes: bytes,
    matchStart: matchStart,
    lineEnd: lineEnd
  )

  for identifier in identifiers {
    guard let tokenRange = swiftmutFindSourceIdentifier(
      identifier,
      in: bytes,
      start: expressionSearchStart,
      end: lineEnd
    ),
    let expressionRange = swiftmutSourceExpressionRange(
      around: tokenRange,
      in: bytes,
      lineEnd: lineEnd
    ),
    swiftmutReturnValueIsEligible(bytes: bytes, start: expressionRange.start, mutation: mutation) else {
      continue
    }
    return swiftmutDescribedValueExpressionResult(
      bytes: bytes,
      expressionRange: expressionRange,
      mutation: mutation
    )
  }

  guard let tokenRange = swiftmutFirstCallLikeSourceIdentifier(
    bytes: bytes,
    start: expressionSearchStart,
    end: lineEnd
  ),
  let expressionRange = swiftmutSourceExpressionRange(
    around: tokenRange,
    in: bytes,
    lineEnd: lineEnd
  ),
  swiftmutReturnValueIsEligible(bytes: bytes, start: expressionRange.start, mutation: mutation) else {
    return nil
  }
  return swiftmutDescribedValueExpressionResult(
    bytes: bytes,
    expressionRange: expressionRange,
    mutation: mutation
  )
}

private func swiftmutDescribedValueExpressionSearchStart(
  bytes: [UInt8],
  matchStart: Int,
  lineEnd: Int
) -> Int {
  var start = swiftmutSkipHorizontalWhitespace(bytes, from: matchStart)
  if start + 1 < lineEnd
      && (bytes[start] == 38 || bytes[start] == 124)
      && bytes[start + 1] == bytes[start] {
    start = swiftmutSkipHorizontalWhitespace(bytes, from: start + 2)
  }
  if start < lineEnd && bytes[start] == 33 {
    start = swiftmutSkipHorizontalWhitespace(bytes, from: start + 1)
  }
  return start
}

private func swiftmutDescribedValueExpressionResult(
  bytes: [UInt8],
  expressionRange: (start: Int, end: Int),
  mutation: SwiftmutMutation
) -> (column: Int, sourceOriginal: String, sourceMutated: String) {
  let sourceOriginal = String(decoding: bytes[expressionRange.start..<expressionRange.end], as: UTF8.self)
  return (
    expressionRange.start + 1,
    sourceOriginal,
    swiftmutImplicitReturnSourceMutation(for: mutation))
}

private func swiftmutFirstCallLikeSourceIdentifier(
  bytes: [UInt8],
  start: Int,
  end: Int
) -> (start: Int, end: Int)? {
  var index = start
  while index < end {
    guard swiftmutIsASCIIIdentifierStart(bytes[index]) else {
      index += 1
      continue
    }
    let tokenStart = index
    index += 1
    while index < end && swiftmutIsASCIILetterNumberOrUnderscore(bytes[index]) {
      index += 1
    }
    let suffixStart = swiftmutSkipHorizontalWhitespace(bytes, from: index)
    if suffixStart < end && (bytes[suffixStart] == 40 || bytes[suffixStart] == 123) {
      return (tokenStart, index)
    }
  }
  return nil
}

private func swiftmutValueExpressionOnLine(
  _ line: String,
  identifiers: [String],
  mutation: SwiftmutMutation
) -> (column: Int, sourceOriginal: String, sourceMutated: String)? {
  if let expression = swiftmutOrdinalValueExpression(line, mutation: mutation) {
    return expression
  }
  if let expression = swiftmutIdentifierValueExpression(line, identifiers: identifiers, mutation: mutation) {
    return expression
  }
  return nil
}

private func swiftmutOrdinalValueExpression(
  _ line: String,
  mutation: SwiftmutMutation
) -> (column: Int, sourceOriginal: String, sourceMutated: String)? {
  if let expression = swiftmutAssignmentValueExpression(line, mutation: mutation) {
    return expression
  }
  if let expression = swiftmutStandaloneLabeledValueExpression(line, mutation: mutation) {
    return expression
  }
  if let expression = swiftmutStandaloneValueExpression(line, mutation: mutation) {
    return expression
  }
  if let expression = swiftmutExplicitReturnValueExpression(line, mutation: mutation) {
    return expression
  }
  return nil
}

private func swiftmutExplicitReturnValueExpression(
  _ line: String,
  mutation: SwiftmutMutation
) -> (column: Int, sourceOriginal: String, sourceMutated: String)? {
  let bytes = Array(line.utf8)
  let lineStart = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
  let lineEnd = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  guard lineStart < lineEnd,
        swiftmutASCIIHasExactPrefix(bytes, start: lineStart, prefix: "return ") else {
    return nil
  }

  let valueStart = swiftmutSkipHorizontalWhitespace(bytes, from: lineStart + 7)
  guard valueStart < lineEnd,
        swiftmutReturnValueIsEligible(bytes: bytes, start: valueStart, mutation: mutation) else {
    return nil
  }

  let sourceOriginal = String(decoding: bytes[valueStart..<lineEnd], as: UTF8.self)
  return (
    valueStart + 1,
    sourceOriginal,
    swiftmutImplicitReturnSourceMutation(for: mutation))
}

private func swiftmutSourceExpressionIdentifiers(for apply: ApplyInst) -> [String] {
  swiftmutSourceCalleeIdentifiers(for: apply).filter(swiftmutIdentifierLooksLikeSourceExpression)
}

private func swiftmutSourceCalleeIdentifiers(for apply: ApplyInst) -> [String] {
  guard let name = apply.referencedFunction?.name.string else {
    return []
  }
  return swiftmutMangledIdentifiers(in: name).filter { identifier in
    identifier.count >= 3 && !identifier.hasPrefix("__")
  }
}

private func swiftmutMangledIdentifiers(in name: String) -> [String] {
  let bytes = Array(name.utf8)
  var identifiers: [String] = []
  var index = 0
  while index < bytes.count {
    guard bytes[index] >= 48 && bytes[index] <= 57 else {
      index += 1
      continue
    }
    var length = 0
    var cursor = index
    while cursor < bytes.count && bytes[cursor] >= 48 && bytes[cursor] <= 57 {
      length = (length * 10) + Int(bytes[cursor] - 48)
      cursor += 1
    }
    guard length > 0,
          cursor + length <= bytes.count,
          swiftmutBytesAreIdentifier(bytes, start: cursor, end: cursor + length) else {
      index += 1
      continue
    }
    let identifier = String(decoding: bytes[cursor..<(cursor + length)], as: UTF8.self)
    if !identifiers.contains(identifier) {
      identifiers.append(identifier)
    }
    index = cursor + length
  }
  return identifiers
}

private func swiftmutIdentifierLooksLikeSourceExpression(_ identifier: String) -> Bool {
  guard let first = identifier.utf8.first else {
    return false
  }
  return (first >= 97 && first <= 122) || first == 95
}

private func swiftmutBytesAreIdentifier(_ bytes: [UInt8], start: Int, end: Int) -> Bool {
  guard start < end else {
    return false
  }
  for index in start..<end {
    if !swiftmutIsASCIILetterNumberOrUnderscore(bytes[index]) {
      return false
    }
  }
  return true
}

private func swiftmutSourceLineContainsExpressionIdentifier(_ line: String, identifiers: [String]) -> Bool {
  let bytes = Array(line.utf8)
  let start = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
  let end = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  guard start < end else {
    return false
  }
  for identifier in identifiers where swiftmutSourceLineContainsExpressionIdentifier(
    bytes,
    start: start,
    end: end,
    identifier: identifier
  ) {
    return true
  }
  return false
}

private func swiftmutSourceLineContainsExpressionIdentifier(
  _ bytes: [UInt8],
  start: Int,
  end: Int,
  identifier: String
) -> Bool {
  let token = Array(identifier.utf8)
  guard !token.isEmpty,
        token.count <= end - start else {
    return false
  }

  var index = start
  while index <= end - token.count {
    var matched = true
    for offset in 0..<token.count where bytes[index + offset] != token[offset] {
      matched = false
      break
    }
    if matched {
      let before = index > start ? bytes[index - 1] : 0
      let tokenEnd = index + token.count
      let after = tokenEnd < end ? bytes[tokenEnd] : 0
      if !swiftmutIsASCIILetterNumberOrUnderscore(before)
          && !swiftmutIsASCIILetterNumberOrUnderscore(after) {
        let callStart = swiftmutSkipHorizontalWhitespace(bytes, from: tokenEnd)
        if callStart < end && bytes[callStart] == 123 {
          return true
        }
        if callStart < end && bytes[callStart] == 40 {
          return true
        }
        if index > start && bytes[index - 1] == 46 {
          return true
        }
      }
    }
    index += 1
  }
  return false
}

private func swiftmutIdentifierValueExpression(
  _ line: String,
  identifiers: [String],
  mutation: SwiftmutMutation
) -> (column: Int, sourceOriginal: String, sourceMutated: String)? {
  let bytes = Array(line.utf8)
  let lineStart = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
  let lineEnd = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  guard lineStart < lineEnd else {
    return nil
  }

  for identifier in identifiers {
    guard let tokenRange = swiftmutFindSourceIdentifier(
      identifier,
      in: bytes,
      start: lineStart,
      end: lineEnd
    ),
    let expressionRange = swiftmutSourceExpressionRange(
      around: tokenRange,
      in: bytes,
      lineEnd: lineEnd
    ),
    swiftmutReturnValueIsEligible(bytes: bytes, start: expressionRange.start, mutation: mutation) else {
      continue
    }
    let sourceOriginal = String(decoding: bytes[expressionRange.start..<expressionRange.end], as: UTF8.self)
    return (
      expressionRange.start + 1,
      sourceOriginal,
      swiftmutImplicitReturnSourceMutation(for: mutation))
  }
  return nil
}

private func swiftmutLineContainsAnyIdentifier(_ line: String, identifiers: [String]) -> Bool {
  let bytes = Array(line.utf8)
  let start = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
  let end = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  guard start < end else {
    return false
  }
  for identifier in identifiers where swiftmutFindSourceIdentifier(identifier, in: bytes, start: start, end: end) != nil {
    return true
  }
  return false
}

private func swiftmutFindSourceIdentifier(
  _ identifier: String,
  in bytes: [UInt8],
  start: Int,
  end: Int
) -> (start: Int, end: Int)? {
  let token = Array(identifier.utf8)
  guard !token.isEmpty,
        token.count <= end - start else {
    return nil
  }

  var index = start
  while index <= end - token.count {
    var matched = true
    for offset in 0..<token.count where bytes[index + offset] != token[offset] {
      matched = false
      break
    }
    if matched {
      let before = index > start ? bytes[index - 1] : 0
      let tokenEnd = index + token.count
      let after = tokenEnd < end ? bytes[tokenEnd] : 0
      if !swiftmutIsASCIILetterNumberOrUnderscore(before)
          && !swiftmutIsASCIILetterNumberOrUnderscore(after) {
        return (index, tokenEnd)
      }
    }
    index += 1
  }
  return nil
}

private func swiftmutSourceExpressionRange(
  around tokenRange: (start: Int, end: Int),
  in bytes: [UInt8],
  lineEnd: Int
) -> (start: Int, end: Int)? {
  var expressionStart = tokenRange.start
  while expressionStart > 0 && swiftmutIsSourceExpressionPrefixByte(bytes[expressionStart - 1]) {
    expressionStart -= 1
  }

  let suffixStart = swiftmutSkipHorizontalWhitespace(bytes, from: tokenRange.end)
  if suffixStart < lineEnd && bytes[suffixStart] == 40 {
    guard let callEnd = swiftmutBalancedExpressionEnd(
      in: bytes,
      openIndex: suffixStart,
      close: 41,
      lineEnd: lineEnd
    ) else {
      return nil
    }
    return (expressionStart, callEnd)
  }
  if suffixStart < lineEnd && bytes[suffixStart] == 123 {
    guard let closureEnd = swiftmutBalancedExpressionEnd(
      in: bytes,
      openIndex: suffixStart,
      close: 125,
      lineEnd: lineEnd
    ) else {
      return nil
    }
    return (expressionStart, closureEnd)
  }

  return (expressionStart, tokenRange.end)
}

private func swiftmutIsSourceExpressionPrefixByte(_ byte: UInt8) -> Bool {
  swiftmutIsASCIILetterNumberOrUnderscore(byte) || byte == 46 || byte == 63 || byte == 33
}

private func swiftmutBalancedExpressionEnd(
  in bytes: [UInt8],
  openIndex: Int,
  close: UInt8,
  lineEnd: Int
) -> Int? {
  let open = bytes[openIndex]
  var depth = 0
  var index = openIndex
  var quote: UInt8?
  var escaped = false
  while index < lineEnd {
    let byte = bytes[index]
    if let activeQuote = quote {
      if escaped {
        escaped = false
      } else if byte == 92 {
        escaped = true
      } else if byte == activeQuote {
        quote = nil
      }
      index += 1
      continue
    }
    if byte == 34 || byte == 39 {
      quote = byte
      index += 1
      continue
    }
    if byte == open {
      depth += 1
    } else if byte == close {
      depth -= 1
      if depth == 0 {
        return index + 1
      }
    }
    index += 1
  }
  return nil
}

private func swiftmutFindLabeledValueExpressionSourceLocation(
  path: String,
  preferredLine: Int,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard preferredLine > 0,
        let text = swiftmutRead(path) else {
    return nil
  }

  if let exact = swiftmutLabeledValueExpressionSourceLocation(
    in: text,
    path: path,
    lineRange: preferredLine...preferredLine,
    mutation: mutation,
    config: config
  ) {
    return exact
  }

  let firstLine = preferredLine > 2 ? preferredLine - 2 : 1
  return swiftmutLabeledValueExpressionSourceLocation(
    in: text,
    path: path,
    lineRange: firstLine...(preferredLine + 24),
    mutation: mutation,
    config: config
  )
}

private func swiftmutLabeledValueExpressionSourceLocation(
  in text: String,
  path: String,
  lineRange: ClosedRange<Int>,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  var matches: [(line: Int, column: Int, sourceOriginal: String, sourceMutated: String)] = []
  var currentLine = 1
  var lineStart = text.startIndex
  var index = text.startIndex

  func inspectLine(_ lineText: String, line: Int) {
    guard lineRange.contains(line),
          matches.count < 2,
          let expression = swiftmutStandaloneLabeledValueExpression(lineText, mutation: mutation) else {
      return
    }
    matches.append((line, expression.column, expression.sourceOriginal, expression.sourceMutated))
  }

  while index < text.endIndex {
    if text[index] == "\n" {
      inspectLine(String(text[lineStart..<index]), line: currentLine)
      if currentLine >= lineRange.upperBound || matches.count >= 2 {
        break
      }
      currentLine += 1
      lineStart = text.index(after: index)
    }
    index = text.index(after: index)
  }

  if index == text.endIndex && currentLine <= lineRange.upperBound {
    inspectLine(String(text[lineStart..<text.endIndex]), line: currentLine)
  }

  guard matches.count == 1,
        let match = matches.first else {
    return nil
  }
  return (
    swiftmutTrimPackageRoot(path, config: config),
    match.line,
    match.column,
    match.sourceOriginal,
    match.sourceMutated)
}

private func swiftmutStandaloneLabeledValueExpression(
  _ line: String,
  mutation: SwiftmutMutation,
  requiresCallExpression: Bool = true
) -> (column: Int, sourceOriginal: String, sourceMutated: String)? {
  let bytes = Array(line.utf8)
  let lineStart = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
  let lineEnd = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  guard lineStart < lineEnd,
        !swiftmutLineStartsWithAssignmentReturnBlockedPrefix(bytes: bytes, start: lineStart),
        swiftmutSourceLineLooksLikeArgumentLabel(bytes: bytes, start: lineStart, end: lineEnd),
        let colon = swiftmutFirstLabeledArgumentSeparator(bytes: bytes, start: lineStart, end: lineEnd) else {
    return nil
  }

  let valueStart = swiftmutSkipHorizontalWhitespace(bytes, from: colon + 1)
  var valueEnd = lineEnd
  if valueEnd > valueStart && bytes[valueEnd - 1] == 44 {
    valueEnd = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: valueEnd - 1)
  }
  guard valueStart < valueEnd,
        swiftmutLabeledArgumentRHSLooksLikeValueExpression(bytes: bytes, start: valueStart, end: valueEnd),
        (!requiresCallExpression || swiftmutLabeledArgumentRHSLooksLikeCallExpression(bytes: bytes, start: valueStart, end: valueEnd)),
        swiftmutReturnValueIsEligible(bytes: bytes, start: valueStart, mutation: mutation) else {
    return nil
  }

  let sourceOriginal = String(decoding: bytes[valueStart..<valueEnd], as: UTF8.self)
  return (
    valueStart + 1,
    sourceOriginal,
    swiftmutImplicitReturnSourceMutation(for: mutation))
}

private func swiftmutStandaloneValueExpression(
  _ line: String,
  mutation: SwiftmutMutation
) -> (column: Int, sourceOriginal: String, sourceMutated: String)? {
  let bytes = Array(line.utf8)
  let lineStart = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
  let lineEnd = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  guard lineStart < lineEnd,
        swiftmutLineLooksLikeImplicitReturnExpression(bytes: bytes, start: lineStart, end: lineEnd),
        !swiftmutLineLooksLikeImplicitReturnContinuation(bytes: bytes, start: lineStart),
        swiftmutReturnValueIsEligible(bytes: bytes, start: lineStart, mutation: mutation) else {
    return nil
  }

  let sourceOriginal = String(decoding: bytes[lineStart..<lineEnd], as: UTF8.self)
  return (
    lineStart + 1,
    sourceOriginal,
    swiftmutImplicitReturnSourceMutation(for: mutation))
}

private func swiftmutAssignmentValueExpression(
  _ line: String,
  mutation: SwiftmutMutation,
  targetNames: [String] = [],
  requiresDirectValueExpression: Bool = false
) -> (column: Int, sourceOriginal: String, sourceMutated: String)? {
  let bytes = Array(line.utf8)
  let lineStart = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
  let lineEnd = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  guard lineStart < lineEnd,
        !swiftmutLineStartsWithAssignmentReturnBlockedPrefix(bytes: bytes, start: lineStart) else {
    return nil
  }

  guard let equals = swiftmutFirstAssignmentOperator(bytes: bytes, start: lineStart, end: lineEnd) else {
    return swiftmutLabeledArgumentValueExpression(
      bytes: bytes,
      lineStart: lineStart,
      lineEnd: lineEnd,
      mutation: mutation,
      targetNames: targetNames,
      requiresDirectValueExpression: requiresDirectValueExpression
    )
  }

  guard swiftmutAssignmentLeftHandSideMatchesTargetNames(
    bytes: bytes,
    start: lineStart,
    end: equals,
    targetNames: targetNames
  ) else {
    return nil
  }

  let valueStart = swiftmutSkipHorizontalWhitespace(bytes, from: equals + 1)
  var valueEnd = lineEnd
  if valueEnd > valueStart && bytes[valueEnd - 1] == 44 {
    valueEnd = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: valueEnd - 1)
  }
  guard valueStart < valueEnd,
        swiftmutAssignmentValueRHSIsDirectValueExpression(
          bytes: bytes,
          start: valueStart,
          end: valueEnd,
          isRequired: requiresDirectValueExpression
        ),
        swiftmutReturnValueIsEligible(bytes: bytes, start: valueStart, mutation: mutation) else {
    return nil
  }

  let sourceOriginal = String(decoding: bytes[valueStart..<valueEnd], as: UTF8.self)
  return (
    valueStart + 1,
    sourceOriginal,
    swiftmutImplicitReturnSourceMutation(for: mutation))
}

private func swiftmutSignatureAssignmentValueExpression(
  _ line: String,
  mutation: SwiftmutMutation,
  targetNames: [String],
  requiresMutationEligibility: Bool = true
) -> (column: Int, sourceOriginal: String, sourceMutated: String)? {
  let bytes = Array(line.utf8)
  let lineStart = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
  var lineEnd = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  if let bodyStart = swiftmutTopLevelByteIndex(bytes, start: lineStart, end: lineEnd, byte: 123) {
    lineEnd = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bodyStart)
  }
  guard lineStart < lineEnd,
        !swiftmutASCIIHasPrefix(bytes, start: lineStart, prefix: "//"),
        let equals = swiftmutFirstAssignmentOperator(bytes: bytes, start: lineStart, end: lineEnd),
        swiftmutAssignmentLeftHandSideMatchesTargetNames(
          bytes: bytes,
          start: lineStart,
          end: equals,
          targetNames: targetNames
        ) else {
    return nil
  }

  let valueStart = swiftmutSkipHorizontalWhitespace(bytes, from: equals + 1)
  var valueEnd = swiftmutTopLevelByteIndex(bytes, start: valueStart, end: lineEnd, byte: 44) ?? lineEnd
  valueEnd = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: valueEnd)
  guard valueStart < valueEnd,
        swiftmutSourceExpressionIsSingleLineComplete(bytes: bytes, start: valueStart, end: valueEnd),
        (!requiresMutationEligibility
         || swiftmutReturnValueIsEligible(bytes: bytes, start: valueStart, mutation: mutation)) else {
    return nil
  }

  let sourceOriginal = String(decoding: bytes[valueStart..<valueEnd], as: UTF8.self)
  return (
    valueStart + 1,
    sourceOriginal,
    swiftmutImplicitReturnSourceMutation(for: mutation))
}

private func swiftmutLabeledArgumentValueExpression(
  bytes: [UInt8],
  lineStart: Int,
  lineEnd: Int,
  mutation: SwiftmutMutation,
  targetNames: [String],
  requiresDirectValueExpression: Bool
) -> (column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard !targetNames.isEmpty,
        let colon = swiftmutFirstLabeledArgumentSeparator(bytes: bytes, start: lineStart, end: lineEnd),
        swiftmutAssignmentLeftHandSideMatchesTargetNames(
          bytes: bytes,
          start: lineStart,
          end: colon,
          targetNames: targetNames
        ) else {
    return nil
  }

  let valueStart = swiftmutSkipHorizontalWhitespace(bytes, from: colon + 1)
  var valueEnd = lineEnd
  if valueEnd > valueStart && bytes[valueEnd - 1] == 44 {
    valueEnd = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: valueEnd - 1)
  }
  guard valueStart < valueEnd,
        swiftmutLabeledArgumentRHSLooksLikeValueExpression(bytes: bytes, start: valueStart, end: valueEnd),
        swiftmutAssignmentValueRHSIsDirectValueExpression(
          bytes: bytes,
          start: valueStart,
          end: valueEnd,
          isRequired: requiresDirectValueExpression
        ),
        swiftmutReturnValueIsEligible(bytes: bytes, start: valueStart, mutation: mutation) else {
    return nil
  }

  let sourceOriginal = String(decoding: bytes[valueStart..<valueEnd], as: UTF8.self)
  return (
    valueStart + 1,
    sourceOriginal,
    swiftmutImplicitReturnSourceMutation(for: mutation))
}

private func swiftmutLocalBindingValueExpression(
  _ line: String,
  mutation: SwiftmutMutation,
  targetNames: [String]
) -> (column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard !targetNames.isEmpty else {
    return nil
  }
  let bytes = Array(line.utf8)
  let lineStart = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
  let lineEnd = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  guard lineStart < lineEnd,
        !swiftmutASCIIHasPrefix(bytes, start: lineStart, prefix: "//") else {
    return nil
  }

  var matches: [(column: Int, sourceOriginal: String)] = []
  var index = lineStart
  while index < lineEnd {
    if swiftmutLocalBindingTokenMatches(bytes: bytes, index: index, end: lineEnd, token: "let")
        || swiftmutLocalBindingTokenMatches(bytes: bytes, index: index, end: lineEnd, token: "var") {
      let nameStart = swiftmutSkipHorizontalWhitespace(bytes, from: index + 3)
      if nameStart < lineEnd && swiftmutIsIdentifierStartByte(bytes[nameStart]) {
        var nameEnd = nameStart + 1
        while nameEnd < lineEnd && swiftmutIsIdentifierByte(bytes[nameEnd]) {
          nameEnd += 1
        }
        let name = String(decoding: bytes[nameStart..<nameEnd], as: UTF8.self)
        if targetNames.contains(name),
           let equals = swiftmutFirstAssignmentOperator(bytes: bytes, start: nameEnd, end: lineEnd) {
          let valueStart = swiftmutSkipHorizontalWhitespace(bytes, from: equals + 1)
          var valueEnd = lineEnd
          if valueEnd > valueStart && bytes[valueEnd - 1] == 44 {
            valueEnd = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: valueEnd - 1)
          }
          guard valueStart < valueEnd,
                swiftmutReturnValueIsEligible(bytes: bytes, start: valueStart, mutation: mutation) else {
            index = nameEnd
            continue
          }
          matches.append((
            valueStart + 1,
            String(decoding: bytes[valueStart..<valueEnd], as: UTF8.self)))
          if matches.count >= 2 {
            return nil
          }
        }
        index = nameEnd
        continue
      }
    }
    index += 1
  }

  guard matches.count == 1,
        let match = matches.first else {
    return nil
  }
  return (
    match.column,
    match.sourceOriginal,
    swiftmutImplicitReturnSourceMutation(for: mutation))
}

private func swiftmutLocalBindingTokenMatches(
  bytes: [UInt8],
  index: Int,
  end: Int,
  token: String
) -> Bool {
  let tokenBytes = Array(token.utf8)
  guard index >= 0,
        index + tokenBytes.count < end else {
    return false
  }
  if index > 0 && swiftmutIsIdentifierByte(bytes[index - 1]) {
    return false
  }
  for offset in 0..<tokenBytes.count where bytes[index + offset] != tokenBytes[offset] {
    return false
  }
  let after = index + tokenBytes.count
  return after < end && swiftmutIsHorizontalWhitespace(bytes[after])
}

private func swiftmutFirstLabeledArgumentSeparator(bytes: [UInt8], start: Int, end: Int) -> Int? {
  guard start < end else {
    return nil
  }
  for index in start..<end where bytes[index] == 58 {
    let before = index > start ? bytes[index - 1] : 0
    let after = index + 1 < end ? bytes[index + 1] : 0
    if before == 58 || after == 58 {
      continue
    }
    return index
  }
  return nil
}

private func swiftmutLabeledArgumentRHSLooksLikeValueExpression(
  bytes: [UInt8],
  start: Int,
  end: Int
) -> Bool {
  guard start < end else {
    return false
  }
  if bytes[start] >= 65 && bytes[start] <= 90 && !swiftmutASCIIContains(bytes, start: start, end: end, pattern: ".") {
    return false
  }
  if swiftmutASCIIHasPrefix(bytes, start: start, prefix: "some ")
      || swiftmutASCIIHasPrefix(bytes, start: start, prefix: "any ") {
    return false
  }
  return true
}

private func swiftmutLabeledArgumentRHSLooksLikeCallExpression(
  bytes: [UInt8],
  start: Int,
  end: Int
) -> Bool {
  guard start < end,
        swiftmutASCIIContains(bytes, start: start, end: end, pattern: "(") else {
    return false
  }
  for index in start..<end {
    switch bytes[index] {
    case 123, 125, 59:
      return false
    default:
      continue
    }
  }
  return true
}

private func swiftmutAssignmentValueRHSIsDirectValueExpression(
  bytes: [UInt8],
  start: Int,
  end: Int,
  isRequired: Bool
) -> Bool {
  guard isRequired else {
    return true
  }
  for index in start..<end {
    switch bytes[index] {
    case 40, 63, 91, 123:
      return false
    default:
      continue
    }
  }
  return true
}

private func swiftmutAssignmentDestinationNames(for store: StoreInst) -> [String] {
  var names: [String] = []
  swiftmutCollectAssignmentDestinationNames(
    from: store.destination,
    in: store.parentFunction,
    names: &names,
    depth: 0
  )
  return swiftmutUniqueAssignmentNames(names)
}

private func swiftmutAssignmentSourceNames(for store: StoreInst) -> [String] {
  var names: [String] = []
  swiftmutCollectAssignmentSourceNames(
    from: store.source,
    names: &names,
    depth: 0
  )
  return swiftmutUniqueAssignmentNames(names)
}

private func swiftmutUniqueAssignmentNames(_ names: [String]) -> [String] {
  var seen = Set<String>()
  var uniqueNames: [String] = []
  for name in names where swiftmutIdentifierIsUsable(name) && !seen.contains(name) {
    seen.insert(name)
    uniqueNames.append(name)
  }
  return uniqueNames
}

private func swiftmutCollectAssignmentSourceNames(
  from value: Value,
  names: inout [String],
  depth: Int
) {
  guard depth < 6 else {
    return
  }

  if let argumentName = (value as? Argument)?.findVarDecl()?.userFacingName.string {
    names.append(argumentName)
  }

  guard let instruction = value.definingInstruction else {
    return
  }

  if let declaration = instruction.findVarDecl() {
    names.append(declaration.userFacingName.string)
  }

  switch instruction {
  case let copyValue as CopyValueInst:
    swiftmutCollectAssignmentSourceNames(
      from: copyValue.fromValue,
      names: &names,
      depth: depth + 1
    )
  case let explicitCopyValue as ExplicitCopyValueInst:
    swiftmutCollectAssignmentSourceNames(
      from: explicitCopyValue.fromValue,
      names: &names,
      depth: depth + 1
    )
  case let moveValue as MoveValueInst:
    swiftmutCollectAssignmentSourceNames(
      from: moveValue.fromValue,
      names: &names,
      depth: depth + 1
    )
  default:
    break
  }
}

private func swiftmutCollectAssignmentDestinationNames(
  from value: Value,
  in function: Function,
  names: inout [String],
  depth: Int
) {
  guard depth < 8,
        let instruction = value.definingInstruction else {
    if let argumentName = (value as? Argument)?.findVarDecl()?.userFacingName.string {
      names.append(argumentName)
    }
    return
  }

  if let declaration = instruction.findVarDecl() {
    names.append(declaration.userFacingName.string)
  }

  switch instruction {
  case let beginAccess as BeginAccessInst:
    swiftmutCollectAssignmentDestinationNames(
      from: beginAccess.address,
      in: function,
      names: &names,
      depth: depth + 1
    )
  case let markUninitialized as MarkUninitializedInst:
    swiftmutCollectAssignmentDestinationNames(
      from: markUninitialized.operand.value,
      in: function,
      names: &names,
      depth: depth + 1
    )
  case let structElementAddr as StructElementAddrInst:
    let structType = structElementAddr.struct.type.objectType
    if let fields = structType.getNominalFields(in: function) {
      names.append(fields.getNameOfField(withIndex: structElementAddr.fieldIndex).string)
    }
    swiftmutCollectAssignmentDestinationNames(
      from: structElementAddr.struct,
      in: function,
      names: &names,
      depth: depth + 1
    )
  case let refElementAddr as RefElementAddrInst:
    if let declaration = refElementAddr.varDecl {
      names.append(declaration.userFacingName.string)
    }
    swiftmutCollectAssignmentDestinationNames(
      from: refElementAddr.instance,
      in: function,
      names: &names,
      depth: depth + 1
    )
  case let projectBox as ProjectBoxInst:
    swiftmutCollectAssignmentDestinationNames(
      from: projectBox.box,
      in: function,
      names: &names,
      depth: depth + 1
    )
  default:
    break
  }
}

private func swiftmutIdentifierIsUsable(_ name: String) -> Bool {
  guard !name.isEmpty,
        name != "_",
        name != "self" else {
    return false
  }
  for byte in name.utf8 {
    guard swiftmutIsIdentifierByte(byte) else {
      return false
    }
  }
  return true
}

private func swiftmutAssignmentLeftHandSideMatchesTargetNames(
  bytes: [UInt8],
  start: Int,
  end: Int,
  targetNames: [String]
) -> Bool {
  guard !targetNames.isEmpty else {
    return true
  }
  for targetName in targetNames {
    guard swiftmutIdentifierIsUsable(targetName) else {
      continue
    }
    if swiftmutLeftHandSideContainsIdentifier(
      bytes: bytes,
      start: start,
      end: end,
      identifier: Array(targetName.utf8)
    ) {
      return true
    }
  }
  return false
}

private func swiftmutLeftHandSideContainsIdentifier(
  bytes: [UInt8],
  start: Int,
  end: Int,
  identifier: [UInt8]
) -> Bool {
  guard !identifier.isEmpty,
        start < end else {
    return false
  }

  var index = start
  while index < end {
    if swiftmutIsIdentifierStartByte(bytes[index]) {
      let identifierStart = index
      index += 1
      while index < end && swiftmutIsIdentifierByte(bytes[index]) {
        index += 1
      }
      if bytes[identifierStart..<index].elementsEqual(identifier) {
        return true
      }
      continue
    }
    index += 1
  }
  return false
}

private func swiftmutIsIdentifierStartByte(_ byte: UInt8) -> Bool {
  byte == 95 || (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122)
}

private func swiftmutIsIdentifierByte(_ byte: UInt8) -> Bool {
  swiftmutIsIdentifierStartByte(byte) || (byte >= 48 && byte <= 57)
}

private func swiftmutFindAssignmentReturnSourceLocation(
  path: String,
  preferredLine: Int,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard preferredLine > 0,
        mutation.sourceOriginal == "return",
        let text = swiftmutRead(path) else {
    return nil
  }

  if let exact = swiftmutAssignmentReturnSourceLocation(
    in: text,
    path: path,
    lineRange: preferredLine...preferredLine,
    mutation: mutation,
    config: config
  ) {
    return exact
  }

  let firstLine = preferredLine > 2 ? preferredLine - 2 : 1
  return swiftmutAssignmentReturnSourceLocation(
    in: text,
    path: path,
    lineRange: firstLine...(preferredLine + 8),
    mutation: mutation,
    config: config
  )
}

private func swiftmutAssignmentReturnSourceLocation(
  in text: String,
  path: String,
  lineRange: ClosedRange<Int>,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  var matches: [(line: Int, column: Int, sourceOriginal: String, sourceMutated: String)] = []
  var currentLine = 1
  var lineStart = text.startIndex
  var index = text.startIndex

  func inspectLine(_ lineText: String, line: Int) {
    guard lineRange.contains(line),
          matches.count < 2,
          let expression = swiftmutAssignmentReturnExpression(lineText, mutation: mutation) else {
      return
    }
    matches.append((line, expression.column, expression.sourceOriginal, expression.sourceMutated))
  }

  while index < text.endIndex {
    if text[index] == "\n" {
      inspectLine(String(text[lineStart..<index]), line: currentLine)
      if currentLine >= lineRange.upperBound || matches.count >= 2 {
        break
      }
      currentLine += 1
      lineStart = text.index(after: index)
    }
    index = text.index(after: index)
  }

  if index == text.endIndex && currentLine <= lineRange.upperBound {
    inspectLine(String(text[lineStart..<text.endIndex]), line: currentLine)
  }

  guard matches.count == 1,
        let match = matches.first else {
    return nil
  }
  return (
    swiftmutTrimPackageRoot(path, config: config),
    match.line,
    match.column,
    match.sourceOriginal,
    match.sourceMutated)
}

private func swiftmutAssignmentReturnExpression(
  _ line: String,
  mutation: SwiftmutMutation
) -> (column: Int, sourceOriginal: String, sourceMutated: String)? {
  let bytes = Array(line.utf8)
  let lineStart = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
  let lineEnd = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  guard lineStart < lineEnd,
        !swiftmutLineStartsWithAssignmentReturnBlockedPrefix(bytes: bytes, start: lineStart),
        let equals = swiftmutFirstAssignmentOperator(bytes: bytes, start: lineStart, end: lineEnd) else {
    return nil
  }

  let valueStart = swiftmutSkipHorizontalWhitespace(bytes, from: equals + 1)
  var valueEnd = lineEnd
  if valueEnd > valueStart && bytes[valueEnd - 1] == 44 {
    valueEnd = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: valueEnd - 1)
  }
  guard valueStart < valueEnd,
        swiftmutReturnValueIsEligible(bytes: bytes, start: valueStart, mutation: mutation) else {
    return nil
  }

  let sourceOriginal = String(decoding: bytes[valueStart..<valueEnd], as: UTF8.self)
  return (
    valueStart + 1,
    sourceOriginal,
    swiftmutImplicitReturnSourceMutation(for: mutation))
}

private func swiftmutLineStartsWithAssignmentReturnBlockedPrefix(bytes: [UInt8], start: Int) -> Bool {
  [
    "if ", "if(", "guard ", "guard(", "while ", "while(", "for ", "for(",
    "switch ", "switch(", "return ", "throw ", "import ", "//", "/*"
  ].contains { swiftmutASCIIHasPrefix(bytes, start: start, prefix: $0) }
}

private func swiftmutFirstAssignmentOperator(bytes: [UInt8], start: Int, end: Int) -> Int? {
  guard start < end else {
    return nil
  }
  for index in start..<end where bytes[index] == 61 {
    let before = index > start ? bytes[index - 1] : 0
    let after = index + 1 < end ? bytes[index + 1] : 0
    if swiftmutIsAssignmentOperatorNeighbor(before) || swiftmutIsAssignmentOperatorNeighbor(after) {
      continue
    }
    return index
  }
  return nil
}

private func swiftmutIsAssignmentOperatorNeighbor(_ byte: UInt8) -> Bool {
  switch byte {
  case 33, 37, 38, 42, 43, 45, 47, 60, 61, 62, 63, 94, 124, 126:
    return true
  default:
    return false
  }
}

private func swiftmutReturnSourceLocationIsUsable(
  _ location: (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String),
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> Bool {
  if mutation.sourceOriginal == "return" {
    return swiftmutReturnSourceLooksLikeStatement(file: location.file, line: location.line, config: config)
  }
  return true
}

private func swiftmutFindUniqueExplicitReturnSourceLocation(
  path: String,
  preferredLine: Int,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard preferredLine > 0,
        let text = swiftmutRead(path) else {
    return nil
  }

  if let exactLine = swiftmutAbsoluteSourceLine(path: path, line: preferredLine) {
    let bytes = Array(exactLine.utf8)
    let start = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
    if swiftmutReturnLineIsEligible(bytes: bytes, start: start, mutation: mutation) {
      return (
        swiftmutTrimPackageRoot(path, config: config),
        preferredLine,
        start + 1,
        mutation.sourceOriginal,
        mutation.sourceMutated)
    }
  }

  var matches: [(line: Int, column: Int)] = []
  var currentLine = 1
  var lineStart = text.startIndex
  var index = text.startIndex
  var braceDepth = 0
  var sawOpeningBrace = false

  func inspectLine(_ lineText: String, line: Int) {
    guard line >= preferredLine,
          line <= preferredLine + 120,
          matches.count < 2 else {
      return
    }
    let bytes = Array(lineText.utf8)
    let start = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
    if swiftmutReturnLineIsEligible(bytes: bytes, start: start, mutation: mutation) {
      matches.append((line, start + 1))
    }
  }

  func updateBraceDepth(_ lineText: String) {
    for byte in lineText.utf8 {
      if byte == 123 {
        braceDepth += 1
        sawOpeningBrace = true
      } else if byte == 125 {
        braceDepth -= 1
      }
    }
  }

  while index < text.endIndex {
    if text[index] == "\n" {
      let lineText = String(text[lineStart..<index])
      inspectLine(lineText, line: currentLine)
      if currentLine >= preferredLine {
        updateBraceDepth(lineText)
        if sawOpeningBrace && braceDepth <= 0 {
          break
        }
        if currentLine >= preferredLine + 120 {
          break
        }
      }
      currentLine += 1
      lineStart = text.index(after: index)
    }
    index = text.index(after: index)
  }

  if index == text.endIndex && currentLine >= preferredLine {
    let lineText = String(text[lineStart..<text.endIndex])
    inspectLine(lineText, line: currentLine)
  }

  guard matches.count == 1,
        let match = matches.first else {
    return nil
  }
  return (
    swiftmutTrimPackageRoot(path, config: config),
    match.line,
    match.column,
    mutation.sourceOriginal,
    mutation.sourceMutated)
}

private func swiftmutFindNearestPriorExplicitReturnSourceLocation(
  path: String,
  preferredLine: Int,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard preferredLine > 1,
        let text = swiftmutRead(path) else {
    return nil
  }

  let firstLine = preferredLine > 8 ? preferredLine - 8 : 1
  var nearest: (line: Int, column: Int)?
  var currentLine = 1
  var lineStart = text.startIndex
  var index = text.startIndex

  func inspectLine(_ lineText: String, line: Int) {
    guard line >= firstLine,
          line < preferredLine else {
      return
    }
    let bytes = Array(lineText.utf8)
    let start = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
    if swiftmutReturnLineIsEligible(bytes: bytes, start: start, mutation: mutation) {
      nearest = (line, start + 1)
    }
  }

  while index < text.endIndex {
    if text[index] == "\n" {
      inspectLine(String(text[lineStart..<index]), line: currentLine)
      if currentLine >= preferredLine {
        break
      }
      currentLine += 1
      lineStart = text.index(after: index)
    }
    index = text.index(after: index)
  }

  guard let nearest else {
    return nil
  }
  return (
    swiftmutTrimPackageRoot(path, config: config),
    nearest.line,
    nearest.column,
    mutation.sourceOriginal,
    mutation.sourceMutated)
}

private func swiftmutFindDescribedExplicitReturnSourceLocation(
  path: String,
  preferredLine: Int,
  locationDescription: String,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard preferredLine > 0,
        let snippet = swiftmutQuotedSourceSnippetPrefix(locationDescription),
        snippet.hasPrefix("return "),
        let text = swiftmutRead(path) else {
    return nil
  }

  var matches: [(line: Int, column: Int)] = []
  var currentLine = 1
  var lineStart = text.startIndex
  var index = text.startIndex
  var braceDepth = 0
  var sawOpeningBrace = false

  func inspectLine(_ lineText: String, line: Int) {
    guard line >= preferredLine,
          line <= preferredLine + 120,
          matches.count < 2 else {
      return
    }
    let bytes = Array(lineText.utf8)
    let start = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
    guard swiftmutReturnLineIsEligible(bytes: bytes, start: start, mutation: mutation) else {
      return
    }
    let trimmed = String(decoding: bytes[start..<swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)], as: UTF8.self)
    if trimmed.hasPrefix(snippet) {
      matches.append((line, start + 1))
    }
  }

  func updateBraceDepth(_ lineText: String) {
    for byte in lineText.utf8 {
      if byte == 123 {
        braceDepth += 1
        sawOpeningBrace = true
      } else if byte == 125 {
        braceDepth -= 1
      }
    }
  }

  while index < text.endIndex {
    if text[index] == "\n" {
      let lineText = String(text[lineStart..<index])
      if currentLine >= preferredLine {
        inspectLine(lineText, line: currentLine)
        updateBraceDepth(lineText)
        if matches.count >= 2 {
          break
        }
        if sawOpeningBrace && braceDepth <= 0 {
          break
        }
        if currentLine >= preferredLine + 120 {
          break
        }
      }
      currentLine += 1
      lineStart = text.index(after: index)
    }
    index = text.index(after: index)
  }

  if index == text.endIndex && currentLine >= preferredLine {
    inspectLine(String(text[lineStart..<text.endIndex]), line: currentLine)
  }

  guard matches.count == 1,
        let match = matches.first else {
    return nil
  }
  return (
    swiftmutTrimPackageRoot(path, config: config),
    match.line,
    match.column,
    mutation.sourceOriginal,
    mutation.sourceMutated)
}

private func swiftmutFindDescribedDefaultArgumentReturnSourceLocation(
  functionName: String,
  locationDescription: String,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard let rawSnippet = swiftmutQuotedSourceSearchSnippet(locationDescription),
        rawSnippet.count >= 4 else {
    return nil
  }

  let snippet = swiftmutDecodedSourceSnippet(rawSnippet)
  guard swiftmutDefaultArgumentSnippetLooksMappable(snippet, functionName: functionName),
        let expression = swiftmutDefaultArgumentSnippetExpression(snippet, mutation: mutation) else {
    return nil
  }

  var matches: [(path: String, line: Int, column: Int, score: Int)] = []
  for path in swiftmutSwiftSourcePaths(config: config) {
    guard let text = swiftmutRead(path) else {
      continue
    }
    let fileMatches = swiftmutSourceSnippetMatches(snippet, in: text)
    for match in fileMatches {
      let score = swiftmutDefaultArgumentDeclarationScore(
        functionName: functionName,
        sourceText: text,
        line: match.line
      )
      matches.append((path, match.line, match.column, score))
    }
  }

  guard !matches.isEmpty else {
    return nil
  }
  let bestScore = matches.map { $0.score }.max() ?? 0
  let bestMatches = matches.filter { $0.score == bestScore }
  guard bestMatches.count == 1,
        let match = bestMatches.first else {
    return nil
  }

  return (
    swiftmutTrimPackageRoot(match.path, config: config),
    match.line,
    match.column,
    expression,
    swiftmutImplicitReturnSourceMutation(for: mutation))
}

private func swiftmutQuotedSourceSearchSnippet(_ description: String) -> String? {
  let bytes = Array(description.utf8)
  guard bytes.count > 1,
        bytes[0] == 34 else {
    return nil
  }

  var end = 1
  while end < bytes.count {
    if end + 4 <= bytes.count,
       bytes[end] == 91,
       bytes[end + 1] == 46,
       bytes[end + 2] == 46,
       bytes[end + 3] == 46 {
      break
    }
    if end + 9 <= bytes.count,
       bytes[end] == 34,
       bytes[end + 1] == 44,
       bytes[end + 2] == 32,
       bytes[end + 3] == 115,
       bytes[end + 4] == 99,
       bytes[end + 5] == 111,
       bytes[end + 6] == 112,
       bytes[end + 7] == 101,
       bytes[end + 8] == 61 {
      break
    }
    end += 1
  }

  let trimmedEnd = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: end)
  guard trimmedEnd > 1 else {
    return nil
  }
  return String(decoding: bytes[1..<trimmedEnd], as: UTF8.self)
}

private func swiftmutDecodedSourceSnippet(_ snippet: String) -> String {
  let bytes = Array(snippet.utf8)
  var decoded: [UInt8] = []
  var index = 0
  while index < bytes.count {
    if bytes[index] == 92,
       index + 1 < bytes.count {
      let next = bytes[index + 1]
      switch next {
      case 34, 92:
        decoded.append(next)
        index += 2
        continue
      case 110:
        decoded.append(10)
        index += 2
        continue
      case 116:
        decoded.append(9)
        index += 2
        continue
      default:
        break
      }
    }
    decoded.append(bytes[index])
    index += 1
  }
  return String(decoding: decoded, as: UTF8.self)
}

private func swiftmutDefaultArgumentSnippetLooksMappable(
  _ snippet: String,
  functionName: String
) -> Bool {
  let bytes = Array(snippet.utf8)
  guard bytes.count >= 4 else {
    return false
  }
  for byte in bytes where byte == 10 || byte == 13 {
    return true
  }
  guard swiftmutFunctionNameLooksDefaultArgumentThunk(functionName) else {
    return false
  }
  for byte in bytes where byte == 41 || byte == 44 {
    return true
  }
  return false
}

private func swiftmutFunctionNameLooksDefaultArgumentThunk(_ functionName: String) -> Bool {
  let bytes = Array(functionName.utf8)
  guard bytes.count >= 3 else {
    return false
  }
  for index in 0..<(bytes.count - 2) {
    if bytes[index] == 102,
       bytes[index + 1] == 65,
       swiftmutIsASCIILetterNumberOrUnderscore(bytes[index + 2]) {
      return true
    }
  }
  return false
}

private func swiftmutDefaultArgumentSnippetExpression(
  _ snippet: String,
  mutation: SwiftmutMutation
) -> String? {
  let bytes = Array(snippet.utf8)
  var index = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
  guard index < bytes.count else {
    return nil
  }

  let start = index
  var inString = false
  var escaped = false
  var squareDepth = 0
  var parenDepth = 0
  while index < bytes.count {
    let byte = bytes[index]
    if inString {
      if escaped {
        escaped = false
      } else if byte == 92 {
        escaped = true
      } else if byte == 34 {
        inString = false
      }
      index += 1
      continue
    }

    if byte == 34 {
      inString = true
    } else if byte == 91 {
      squareDepth += 1
    } else if byte == 93 {
      squareDepth -= 1
    } else if byte == 40 {
      parenDepth += 1
    } else if byte == 41 {
      if parenDepth == 0 {
        break
      }
      parenDepth -= 1
    } else if squareDepth == 0 && parenDepth == 0 && (byte == 44 || byte == 10 || byte == 13) {
      break
    }
    index += 1
  }

  let end = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: index)
  guard end > start else {
    return nil
  }
  let expression = String(decoding: bytes[start..<end], as: UTF8.self)
  let expressionBytes = Array(expression.utf8)
  guard swiftmutImplicitReturnExpressionIsEligible(
    bytes: expressionBytes,
    start: swiftmutSkipHorizontalWhitespace(expressionBytes, from: 0),
    mutation: mutation,
    allowsInlineBraces: true
  ) else {
    return nil
  }
  return expression
}

private func swiftmutSourceSnippetMatches(
  _ snippet: String,
  in text: String
) -> [(line: Int, column: Int)] {
  let source = Array(text.utf8)
  let pattern = Array(snippet.utf8)
  guard !pattern.isEmpty,
        pattern.count <= source.count else {
    return []
  }

  var matches: [(line: Int, column: Int)] = []
  var index = 0
  while index + pattern.count <= source.count {
    var matched = true
    for offset in 0..<pattern.count where source[index + offset] != pattern[offset] {
      matched = false
      break
    }
    if matched {
      matches.append(swiftmutSourceLineAndColumn(source, offset: index))
      if matches.count > 8 {
        return matches
      }
      index += pattern.count
    } else {
      index += 1
    }
  }
  return matches
}

private func swiftmutSnippetExpressionStartOffset(_ snippet: String) -> Int {
  swiftmutSkipHorizontalWhitespace(Array(snippet.utf8), from: 0)
}

private func swiftmutSourceLine(_ text: String, line targetLine: Int) -> String? {
  guard targetLine > 0 else {
    return nil
  }

  var currentLine = 1
  var lineStart = text.startIndex
  var index = text.startIndex
  while index < text.endIndex {
    if text[index] == "\n" {
      if currentLine == targetLine {
        return String(text[lineStart..<index])
      }
      currentLine += 1
      lineStart = text.index(after: index)
    }
    index = text.index(after: index)
  }

  if currentLine == targetLine {
    return String(text[lineStart..<text.endIndex])
  }
  return nil
}

private func swiftmutSourceLineAndColumn(
  _ bytes: [UInt8],
  offset: Int
) -> (line: Int, column: Int) {
  var line = 1
  var column = 1
  var index = 0
  while index < offset && index < bytes.count {
    if bytes[index] == 10 {
      line += 1
      column = 1
    } else {
      column += 1
    }
    index += 1
  }
  return (line, column)
}

private func swiftmutDefaultArgumentDeclarationScore(
  functionName: String,
  sourceText: String,
  line: Int
) -> Int {
  guard line > 0 else {
    return 0
  }
  let lines = sourceText.split(separator: "\n", omittingEmptySubsequences: false)
  let startLine = max(1, line - 160)
  let endLine = min(lines.count, line)
  var signature = ""
  if startLine <= endLine {
    for currentLine in startLine...endLine {
      signature += String(lines[currentLine - 1])
      signature += "\n"
    }
  }

  var score = 0
  if let functionIdentifier = swiftmutNearestFunctionIdentifier(in: signature),
     swiftmutMangledNameContainsIdentifier(functionName, identifier: functionIdentifier) {
    score += 2
  }
  if let typeIdentifier = swiftmutNearestTypeIdentifier(in: signature),
     swiftmutMangledNameContainsIdentifier(functionName, identifier: typeIdentifier) {
    score += 1
  }
  let signatureBytes = Array(signature.utf8)
  if swiftmutASCIIContains(signatureBytes, start: 0, end: signatureBytes.count, pattern: "init("),
     functionName.contains("cf") {
    score += 1
  }
  return score
}

private func swiftmutNearestFunctionIdentifier(in signature: String) -> String? {
  let lines = signature.split(separator: "\n", omittingEmptySubsequences: false)
  var index = lines.count
  while index > 0 {
    index -= 1
    let line = String(lines[index])
    if let identifier = swiftmutDeclarationIdentifier(after: "public static func ", in: line) {
      return identifier
    }
    if let identifier = swiftmutDeclarationIdentifier(after: "static func ", in: line) {
      return identifier
    }
    if let identifier = swiftmutDeclarationIdentifier(after: "public func ", in: line) {
      return identifier
    }
    if let identifier = swiftmutDeclarationIdentifier(after: "private func ", in: line) {
      return identifier
    }
    if let identifier = swiftmutDeclarationIdentifier(after: "func ", in: line) {
      return identifier
    }
    let bytes = Array(line.utf8)
    if swiftmutASCIIContains(bytes, start: 0, end: bytes.count, pattern: "init(") {
      return "init"
    }
  }
  return nil
}

private func swiftmutNearestTypeIdentifier(in signature: String) -> String? {
  let lines = signature.split(separator: "\n", omittingEmptySubsequences: false)
  var index = lines.count
  while index > 0 {
    index -= 1
    let line = String(lines[index])
    if let identifier = swiftmutDeclarationIdentifier(after: "struct ", in: line) {
      return identifier
    }
    if let identifier = swiftmutDeclarationIdentifier(after: "enum ", in: line) {
      return identifier
    }
    if let identifier = swiftmutDeclarationIdentifier(after: "class ", in: line) {
      return identifier
    }
  }
  return nil
}

private func swiftmutDeclarationIdentifier(after marker: String, in line: String) -> String? {
  let bytes = Array(line.utf8)
  guard let markerStart = swiftmutASCIIIndex(bytes, start: 0, end: bytes.count, pattern: marker) else {
    return nil
  }
  var index = markerStart + marker.utf8.count
  index = swiftmutSkipHorizontalWhitespace(bytes, from: index)
  let start = index
  while index < bytes.count && swiftmutIsIdentifierByte(bytes[index]) {
    index += 1
  }
  guard index > start else {
    return nil
  }
  return String(decoding: bytes[start..<index], as: UTF8.self)
}

private func swiftmutMangledNameContainsIdentifier(
  _ functionName: String,
  identifier: String
) -> Bool {
  guard identifier != "init" else {
    return functionName.contains("cf")
  }
  if identifier.count <= 3 {
    return functionName.contains(identifier)
  }
  if functionName.contains(identifier) {
    return true
  }
  let prefixLength = min(identifier.count, 8)
  let prefix = String(identifier.prefix(prefixLength))
  return prefix.count >= 4 && functionName.contains(prefix)
}

private func swiftmutFindNearestPriorImplicitReturnSourceLocation(
  path: String,
  preferredLine: Int,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard mutation.sourceOriginal == "return",
        preferredLine > 1,
        let text = swiftmutRead(path) else {
    return nil
  }

  let firstLine = preferredLine > 8 ? preferredLine - 8 : 1
  var nearest: (line: Int, column: Int, sourceOriginal: String, sourceMutated: String)?
  var currentLine = 1
  var lineStart = text.startIndex
  var index = text.startIndex

  func inspectLine(_ lineText: String, line: Int) {
    guard line >= firstLine,
          line < preferredLine else {
      return
    }
    let bytes = Array(lineText.utf8)
    let start = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
    let end = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
    guard start < end,
          !swiftmutLineLooksLikeImplicitReturnContinuation(bytes: bytes, start: start),
          swiftmutImplicitReturnExpressionIsEligible(
            bytes: bytes,
            start: start,
            mutation: mutation,
            allowsInlineBraces: true
          ) else {
      return
    }
    nearest = (
      line,
      start + 1,
      String(decoding: bytes[start..<end], as: UTF8.self),
      swiftmutImplicitReturnSourceMutation(for: mutation))
  }

  while index < text.endIndex {
    if text[index] == "\n" {
      inspectLine(String(text[lineStart..<index]), line: currentLine)
      if currentLine >= preferredLine {
        break
      }
      currentLine += 1
      lineStart = text.index(after: index)
    }
    index = text.index(after: index)
  }

  guard let nearest else {
    return nil
  }
  return (
    swiftmutTrimPackageRoot(path, config: config),
    nearest.line,
    nearest.column,
    nearest.sourceOriginal,
    nearest.sourceMutated)
}

private func swiftmutFindOrdinalExplicitReturnSourceLocation(
  path: String,
  preferredLine: Int,
  ordinal: Int,
  expectedCount: Int,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard preferredLine > 0,
        ordinal > 0,
        ordinal <= expectedCount,
        expectedCount > 1,
        let text = swiftmutRead(path) else {
    return nil
  }

  var matches: [(line: Int, column: Int)] = []
  var currentLine = 1
  var lineStart = text.startIndex
  var index = text.startIndex
  var braceDepth = 0
  var sawOpeningBrace = false

  func inspectLine(_ lineText: String, line: Int) {
    guard line >= preferredLine,
          line <= preferredLine + 120,
          matches.count <= expectedCount else {
      return
    }
    let bytes = Array(lineText.utf8)
    let start = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
    if swiftmutReturnLineIsEligible(bytes: bytes, start: start, mutation: mutation) {
      matches.append((line, start + 1))
    }
  }

  func updateBraceDepth(_ lineText: String) {
    for byte in lineText.utf8 {
      if byte == 123 {
        braceDepth += 1
        sawOpeningBrace = true
      } else if byte == 125 {
        braceDepth -= 1
      }
    }
  }

  while index < text.endIndex {
    if text[index] == "\n" {
      let lineText = String(text[lineStart..<index])
      if currentLine >= preferredLine {
        inspectLine(lineText, line: currentLine)
        updateBraceDepth(lineText)
        if matches.count > expectedCount {
          break
        }
        if sawOpeningBrace && braceDepth <= 0 {
          break
        }
        if currentLine >= preferredLine + 120 {
          break
        }
      }
      currentLine += 1
      lineStart = text.index(after: index)
    }
    index = text.index(after: index)
  }

  if index == text.endIndex && currentLine >= preferredLine {
    let lineText = String(text[lineStart..<text.endIndex])
    inspectLine(lineText, line: currentLine)
  }

  guard matches.count == expectedCount else {
    return nil
  }
  let match = matches[ordinal - 1]
  return (
    swiftmutTrimPackageRoot(path, config: config),
    match.line,
    match.column,
    mutation.sourceOriginal,
    mutation.sourceMutated)
}

private func swiftmutFindUniqueImplicitReturnSourceLocation(
  path: String,
  preferredLine: Int,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard mutation.sourceOriginal == "return",
        preferredLine > 0,
        let text = swiftmutRead(path) else {
    return nil
  }

  var matches: [(line: Int, column: Int, sourceOriginal: String, sourceMutated: String)] = []
  var currentLine = 1
  var lineStart = text.startIndex
  var index = text.startIndex
  var braceDepth = 0
  var sawOpeningBrace = false
  var sawInvalidTopLevelBodyLine = false

  func recordExpression(_ expression: String, line: Int, column: Int) {
    guard matches.count < 2 else {
      return
    }
    let bytes = Array(expression.utf8)
    let start = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
    guard swiftmutImplicitReturnExpressionIsEligible(
      bytes: bytes,
      start: start,
      mutation: mutation,
      allowsInlineBraces: true
    ) else {
      return
    }
    let trimmedStart = expression.index(expression.startIndex, offsetBy: start)
    let sourceOriginal = String(expression[trimmedStart...])
    matches.append((
      line,
      column + start,
      sourceOriginal,
      swiftmutImplicitReturnSourceMutation(for: mutation)
    ))
  }

  func inspectLine(_ lineText: String, line: Int) {
    guard line >= preferredLine,
          line <= preferredLine + 80,
          matches.count < 2 else {
      return
    }

    let bytes = Array(lineText.utf8)
    let start = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
    let end = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
    guard start < end else {
      return
    }
    if swiftmutLineLooksLikeImplicitReturnContinuation(bytes: bytes, start: start) {
      return
    }

    if line == preferredLine,
       let expression = swiftmutInlineImplicitReturnExpression(lineText) {
      recordExpression(expression.text, line: line, column: expression.column)
      return
    }

    guard sawOpeningBrace,
          braceDepth == 1 else {
      return
    }
    if bytes[start] == 125 {
      return
    }
    guard swiftmutLineLooksLikeImplicitReturnExpression(
      bytes: bytes,
      start: start,
      end: end,
      allowsInlineBraces: true
    ) else {
      sawInvalidTopLevelBodyLine = true
      return
    }
    recordExpression(lineText, line: line, column: 1)
  }

  func updateBraceDepth(_ lineText: String) {
    for byte in lineText.utf8 {
      if byte == 123 {
        braceDepth += 1
        sawOpeningBrace = true
      } else if byte == 125 {
        braceDepth -= 1
      }
    }
  }

  while index < text.endIndex {
    if text[index] == "\n" {
      let lineText = String(text[lineStart..<index])
      if currentLine >= preferredLine {
        inspectLine(lineText, line: currentLine)
        updateBraceDepth(lineText)
        if sawOpeningBrace && braceDepth <= 0 {
          break
        }
        if currentLine >= preferredLine + 80 {
          break
        }
      }
      currentLine += 1
      lineStart = text.index(after: index)
    }
    index = text.index(after: index)
  }

  if index == text.endIndex && currentLine >= preferredLine {
    let lineText = String(text[lineStart..<text.endIndex])
    inspectLine(lineText, line: currentLine)
  }

  guard !sawInvalidTopLevelBodyLine,
        matches.count == 1,
        let match = matches.first else {
    return nil
  }
  return (
    swiftmutTrimPackageRoot(path, config: config),
    match.line,
    match.column,
    match.sourceOriginal,
    match.sourceMutated)
}

private func swiftmutInlineImplicitReturnExpression(_ line: String) -> (text: String, column: Int)? {
  guard let openBrace = line.firstIndex(of: "{"),
        let closeBrace = line.lastIndex(of: "}"),
        openBrace < closeBrace else {
    return nil
  }
  let expressionStart = line.index(after: openBrace)
  let text = String(line[expressionStart..<closeBrace])
  let bytes = Array(text.utf8)
  let start = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
  let end = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  guard start < end else {
    return nil
  }
  return (String(text), line.distance(from: line.startIndex, to: expressionStart) + 1)
}

private func swiftmutLineLooksLikeImplicitReturnExpression(
  bytes: [UInt8],
  start: Int,
  end: Int,
  allowsInlineBraces: Bool = false
) -> Bool {
  if bytes[start] == 125 || bytes[start] == 123 || bytes[start] == 47 {
    return false
  }
  let blockedPrefixes = [
    "return ", "let ", "var ", "if ", "if(", "guard ", "guard(",
    "for ", "for(", "while ", "while(", "switch ", "switch(",
    "case ", "default:", "do ", "catch ", "defer ", "throw ",
    "self.", "_ = "
  ]
  for prefix in blockedPrefixes {
    if swiftmutASCIIHasPrefix(bytes, start: start, prefix: prefix) {
      return false
    }
  }
  if swiftmutPropertyDeclarationKeyword(bytes: bytes, start: start, end: end) != nil {
    return false
  }
  for index in start..<end {
    if bytes[index] == 59 {
      return false
    }
    if !allowsInlineBraces && (bytes[index] == 123 || bytes[index] == 125) {
      return false
    }
  }
  if allowsInlineBraces && !swiftmutLineHasBalancedInlineBraces(bytes: bytes, start: start, end: end) {
    return false
  }
  if !allowsInlineBraces && swiftmutASCIIContains(bytes, start: start, end: end, pattern: " in ") {
    return false
  }
  return true
}

private func swiftmutLineHasBalancedInlineBraces(bytes: [UInt8], start: Int, end: Int) -> Bool {
  var depth = 0
  var sawBrace = false
  for index in start..<end {
    if bytes[index] == 123 {
      if index == start {
        return false
      }
      depth += 1
      sawBrace = true
    } else if bytes[index] == 125 {
      depth -= 1
      if depth < 0 {
        return false
      }
      sawBrace = true
    }
  }
  return !sawBrace || depth == 0
}

private func swiftmutLineLooksLikeImplicitReturnContinuation(bytes: [UInt8], start: Int) -> Bool {
  guard start < bytes.count else {
    return false
  }
  switch bytes[start] {
  case 38, 43, 45, 46, 47, 60, 61, 62, 63, 124:
    return true
  default:
    return false
  }
}

private func swiftmutImplicitReturnExpressionIsEligible(
  bytes: [UInt8],
  start: Int,
  mutation: SwiftmutMutation,
  allowsInlineBraces: Bool = false
) -> Bool {
  start < bytes.count
    && swiftmutLineLooksLikeImplicitReturnExpression(
      bytes: bytes,
      start: start,
      end: swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count),
      allowsInlineBraces: allowsInlineBraces
    )
    && swiftmutReturnValueIsEligible(bytes: bytes, start: start, mutation: mutation)
}

private func swiftmutImplicitReturnSourceMutation(for mutation: SwiftmutMutation) -> String {
  switch mutation.mutatedBuiltinName {
  case "return_false":
    return "false"
  case "return_true":
    return "true"
  case "return_nil":
    return "nil"
  case "return_zero":
    return "0"
  case "return_empty_string":
    return #""""#
  case "return_empty_array", "return_empty_set":
    return "[]"
  case "return_empty_dictionary":
    return "[:]"
  default:
    return mutation.sourceMutated
  }
}

private func swiftmutReturnLineIsEligible(
  bytes: [UInt8],
  start: Int,
  mutation: SwiftmutMutation
) -> Bool {
  guard swiftmutASCIIHasExactPrefix(bytes, start: start, prefix: "return ") else {
    return false
  }
  let valueStart = swiftmutSkipHorizontalWhitespace(bytes, from: start + 7)
  return swiftmutReturnValueIsEligible(bytes: bytes, start: valueStart, mutation: mutation)
}

private func swiftmutReturnValueIsEligible(
  bytes: [UInt8],
  start: Int,
  mutation: SwiftmutMutation
) -> Bool {
  switch mutation.mutatedBuiltinName {
  case "return_false":
    return !swiftmutASCIIHasToken(bytes, start: start, token: "false")
  case "return_true":
    return !swiftmutASCIIHasToken(bytes, start: start, token: "true")
  case "return_nil":
    return !swiftmutASCIIHasToken(bytes, start: start, token: "nil")
  case "return_zero":
    return !swiftmutASCIIHasNumericZeroToken(bytes, start: start)
  case "return_empty_string":
    return !swiftmutASCIIHasEmptyStringLiteral(bytes, start: start)
  case "return_empty_array", "return_empty_set":
    return !swiftmutASCIIHasEmptyArrayLiteral(bytes, start: start)
  case "return_empty_dictionary":
    return !swiftmutASCIIHasEmptyDictionaryLiteral(bytes, start: start)
  default:
    return true
  }
}

private func swiftmutASCIIHasEmptyArrayLiteral(_ bytes: [UInt8], start: Int) -> Bool {
  guard start >= 0 && start + 2 <= bytes.count,
        bytes[start] == 91,
        bytes[start + 1] == 93 else {
    return false
  }
  let end = start + 2
  return end == bytes.count || !swiftmutIsASCIILetterNumberOrUnderscore(bytes[end])
}

private func swiftmutASCIIHasEmptyDictionaryLiteral(_ bytes: [UInt8], start: Int) -> Bool {
  guard start >= 0 && start + 3 <= bytes.count,
        bytes[start] == 91,
        bytes[start + 1] == 58,
        bytes[start + 2] == 93 else {
    return false
  }
  let end = start + 3
  return end == bytes.count || !swiftmutIsASCIILetterNumberOrUnderscore(bytes[end])
}

private func swiftmutASCIIHasEmptyStringLiteral(_ bytes: [UInt8], start: Int) -> Bool {
  guard start >= 0 && start + 2 <= bytes.count,
        bytes[start] == 34,
        bytes[start + 1] == 34 else {
    return false
  }
  let end = start + 2
  return end == bytes.count || !swiftmutIsASCIILetterNumberOrUnderscore(bytes[end])
}

private func swiftmutASCIIHasToken(_ bytes: [UInt8], start: Int, token: String) -> Bool {
  let tokenBytes = Array(token.utf8)
  guard start >= 0 && start + tokenBytes.count <= bytes.count else {
    return false
  }
  for offset in 0..<tokenBytes.count {
    if bytes[start + offset] != tokenBytes[offset] {
      return false
    }
  }
  let end = start + tokenBytes.count
  return end == bytes.count || !swiftmutIsASCIILetterNumberOrUnderscore(bytes[end])
}

private func swiftmutASCIIHasNumericZeroToken(_ bytes: [UInt8], start: Int) -> Bool {
  guard start >= 0 && start < bytes.count && bytes[start] == 48 else {
    return false
  }
  let end = start + 1
  return end == bytes.count || bytes[end] < 48 || bytes[end] > 57
}

private func swiftmutInstructionSourceLocation(
  for instruction: Instruction,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  if let fileNameAndPosition = instruction.location.fileNameAndPosition {
    let path = fileNameAndPosition.path.string
    if let matchedPath = swiftmutIncludedSourcePath(path, config: config) {
      return (
        swiftmutTrimPackageRoot(matchedPath, config: config),
        fileNameAndPosition.line,
        fileNameAndPosition.column,
        mutation.sourceOriginal,
        mutation.sourceMutated)
    }
  }

  let location = instruction.parentFunction.location.description
  for path in swiftmutSwiftSourcePaths(config: config) {
    guard location.contains(path),
          let line = swiftmutPreferredLine(in: location, path: path) else {
      continue
    }
    return (
      swiftmutTrimPackageRoot(path, config: config),
      line,
      1,
      mutation.sourceOriginal,
      mutation.sourceMutated)
  }
  return nil
}

private func swiftmutVoidCallSourceLocation(
  for apply: ApplyInst,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> SwiftmutVoidCallSourceLocationResult {
  if let fileNameAndPosition = apply.location.fileNameAndPosition {
    let path = fileNameAndPosition.path.string
    if let matchedPath = swiftmutIncludedSourcePath(path, config: config) {
      let candidate = (
        swiftmutTrimPackageRoot(matchedPath, config: config),
        fileNameAndPosition.line,
        fileNameAndPosition.column,
        mutation.sourceOriginal,
        mutation.sourceMutated)
      if swiftmutVoidCallSourceLooksLikeStatement(file: candidate.0, line: candidate.1, config: config) {
        return .found(
          file: candidate.0,
          line: candidate.1,
          column: candidate.2,
          sourceOriginal: candidate.3,
          sourceMutated: candidate.4
        )
      }
      if let anchored = swiftmutFindUniqueVoidCallSourceLocation(
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        mutation: mutation,
        config: config
      ) {
        return .found(
          file: anchored.file,
          line: anchored.line,
          column: anchored.column,
          sourceOriginal: anchored.sourceOriginal,
          sourceMutated: anchored.sourceMutated
        )
      }
    }
  }

  if let fallback = swiftmutInstructionSourceLocation(
    for: apply,
    mutation: mutation,
    config: config
  ) {
    if swiftmutVoidCallSourceLooksLikeStatement(file: fallback.file, line: fallback.line, config: config) {
      return .found(
        file: fallback.file,
        line: fallback.line,
        column: fallback.column,
        sourceOriginal: fallback.sourceOriginal,
        sourceMutated: fallback.sourceMutated
      )
    }
    let fallbackPath = fallback.file.hasPrefix("/") || config.packageRoot.isEmpty
      ? fallback.file
      : config.packageRoot + "/" + fallback.file
    if let anchored = swiftmutFindUniqueVoidCallSourceLocation(
      path: fallbackPath,
      preferredLine: fallback.line,
      mutation: mutation,
      config: config
    ) {
      return .found(
        file: anchored.file,
        line: anchored.line,
        column: anchored.column,
        sourceOriginal: anchored.sourceOriginal,
        sourceMutated: anchored.sourceMutated
      )
    }
    return .nonStatement
  }

  return .missing
}

private func swiftmutFindUniqueVoidCallSourceLocation(
  path: String,
  preferredLine: Int,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard preferredLine > 0,
        let text = swiftmutRead(path) else {
    return nil
  }

  let firstLine = preferredLine > 8 ? preferredLine - 8 : 1
  let lastLine = preferredLine + 40
  var matches: [(line: Int, column: Int)] = []
  var currentLine = 1
  var lineStart = text.startIndex
  var index = text.startIndex

  func inspectLine(_ lineText: String, line: Int) {
    guard line >= firstLine,
          line <= lastLine,
          matches.count < 2,
          swiftmutSourceLineLooksLikeVoidCallStatement(lineText) else {
      return
    }
    let bytes = Array(lineText.utf8)
    let start = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
    matches.append((line, start + 1))
  }

  while index < text.endIndex {
    if text[index] == "\n" {
      let lineText = String(text[lineStart..<index])
      inspectLine(lineText, line: currentLine)
      if currentLine >= lastLine || matches.count >= 2 {
        break
      }
      currentLine += 1
      lineStart = text.index(after: index)
    }
    index = text.index(after: index)
  }

  if index == text.endIndex && currentLine <= lastLine {
    let lineText = String(text[lineStart..<text.endIndex])
    inspectLine(lineText, line: currentLine)
  }

  guard matches.count == 1,
        let match = matches.first else {
    return nil
  }
  return (
    swiftmutTrimPackageRoot(path, config: config),
    match.line,
    match.column,
    mutation.sourceOriginal,
    mutation.sourceMutated)
}

private func swiftmutBranchSourceLocation(
  for branch: CondBranchInst,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  if let fileNameAndPosition = branch.location.fileNameAndPosition {
    let path = fileNameAndPosition.path.string
    if let matchedPath = swiftmutIncludedSourcePath(path, config: config) {
      if let sourceLocation = swiftmutGenericConditionSourceLocation(
        path: matchedPath,
        line: fileNameAndPosition.line,
        fallbackColumn: fileNameAndPosition.column,
        mutation: mutation,
        config: config
      ) {
        return sourceLocation
      }
      return (
        swiftmutTrimPackageRoot(matchedPath, config: config),
        fileNameAndPosition.line,
        fileNameAndPosition.column,
        mutation.sourceOriginal,
        mutation.sourceMutated)
    }
  }

  let location = branch.parentFunction.location.description
  for path in swiftmutSwiftSourcePaths(config: config) {
    guard location.contains(path),
          let line = swiftmutPreferredLine(in: location, path: path) else {
      continue
    }
    if let anchored = swiftmutFindUniqueExplicitConditionSourceLocation(
      path: path,
      preferredLine: line,
      mutation: mutation,
      config: config
    ) {
      return anchored
    }
    return (
      swiftmutTrimPackageRoot(path, config: config),
      line,
      1,
      mutation.sourceOriginal,
      mutation.sourceMutated)
  }
  return nil
}

private func swiftmutFindUniqueExplicitConditionSourceLocation(
  path: String,
  preferredLine: Int,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard preferredLine > 0,
        let text = swiftmutRead(path) else {
    return nil
  }

  var matches: [(line: Int, column: Int, sourceOriginal: String)] = []
  var currentLine = 1
  var lineStart = text.startIndex
  var index = text.startIndex
  var braceDepth = 0
  var sawOpeningBrace = false

  func inspectLine(_ lineText: String, line: Int) {
    guard line >= preferredLine,
          line <= preferredLine + 120,
          matches.count < 2,
          let expression = swiftmutGenericConditionExpression(lineText) else {
      return
    }
    matches.append((line, expression.column, expression.sourceOriginal))
  }

  func updateBraceDepth(_ lineText: String) {
    for byte in lineText.utf8 {
      if byte == 123 {
        braceDepth += 1
        sawOpeningBrace = true
      } else if byte == 125 {
        braceDepth -= 1
      }
    }
  }

  while index < text.endIndex {
    if text[index] == "\n" {
      let lineText = String(text[lineStart..<index])
      if currentLine >= preferredLine {
        inspectLine(lineText, line: currentLine)
        updateBraceDepth(lineText)
        if sawOpeningBrace && braceDepth <= 0 {
          break
        }
        if currentLine >= preferredLine + 120 {
          break
        }
      }
      currentLine += 1
      lineStart = text.index(after: index)
    }
    index = text.index(after: index)
  }

  if index == text.endIndex && currentLine >= preferredLine {
    let lineText = String(text[lineStart..<text.endIndex])
    inspectLine(lineText, line: currentLine)
  }

  guard matches.count == 1,
        let match = matches.first else {
    return nil
  }
  return (
    swiftmutTrimPackageRoot(path, config: config),
    match.line,
    match.column,
    match.sourceOriginal,
    mutation.sourceMutated)
}

private func swiftmutGenericConditionSourceLocation(
  path: String,
  line: Int,
  fallbackColumn: Int,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard let sourceLine = swiftmutAbsoluteSourceLine(path: path, line: line),
        let expression = swiftmutGenericConditionExpression(sourceLine) else {
    return nil
  }
  return (
    swiftmutTrimPackageRoot(path, config: config),
    line,
    expression.column > 0 ? expression.column : fallbackColumn,
    expression.sourceOriginal,
    mutation.sourceMutated)
}

private func swiftmutSourceLocation(
  for instruction: Instruction,
  function: Function,
  moduleName: String,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  if let fileNameAndPosition = instruction.location.fileNameAndPosition {
    let path = fileNameAndPosition.path.string
    guard let matchedPath = swiftmutIncludedSourcePath(path, config: config) else {
      return nil
    }
    return (
      swiftmutTrimPackageRoot(matchedPath, config: config),
      fileNameAndPosition.line,
      fileNameAndPosition.column,
      "",
      "")
  }

  if let located = swiftmutFindSourceOperator(
    moduleName: moduleName,
    functionLocation: function.location.description,
    mutation: mutation,
    config: config) {
    return located
  }

  if let located = swiftmutFindDescribedSourceOperator(
    moduleName: moduleName,
    functionLocation: function.location.description,
    locationDescription: instruction.location.description,
    mutation: mutation,
    config: config) {
    return located
  }

  if let comparison = instruction as? BuiltinInst,
     swiftmutIsComparisonBuiltin(comparison),
     let ordinal = swiftmutComparisonOrdinalAndCount(for: comparison, in: function),
     ordinal.count <= 12 {
    return swiftmutFindOrdinalSourceOperator(
      moduleName: moduleName,
      functionLocation: function.location.description,
      ordinal: ordinal.ordinal,
      expectedCount: ordinal.count,
      mutation: mutation,
      config: config)
  }

  return nil
}

private func swiftmutGenericConditionSourceIsExplicit(
  file: String,
  line: Int,
  config: SwiftmutConfig
) -> Bool {
  guard let sourceLine = swiftmutSourceLine(file: file, line: line, config: config) else {
    return true
  }
  return swiftmutSourceLineLooksLikeExplicitCondition(sourceLine)
}

private func swiftmutSourceLine(
  file: String,
  line: Int,
  config: SwiftmutConfig
) -> String? {
  guard line > 0 else {
    return nil
  }

  let path: String
  if file.hasPrefix("/") || config.packageRoot.isEmpty {
    path = file
  } else {
    path = config.packageRoot + "/" + file
  }
  guard let matchedPath = swiftmutIncludedSourcePath(path, config: config),
        let text = swiftmutRead(matchedPath) else {
    return nil
  }

  var currentLine = 1
  var lineStart = text.startIndex
  var index = text.startIndex
  while index < text.endIndex {
    if text[index] == "\n" {
      if currentLine == line {
        return String(text[lineStart..<index])
      }
      currentLine += 1
      lineStart = text.index(after: index)
    }
    index = text.index(after: index)
  }

  if currentLine == line {
    return String(text[lineStart..<text.endIndex])
  }
  return nil
}

private func swiftmutAbsoluteSourceLine(path: String, line: Int) -> String? {
  guard line > 0,
        let text = swiftmutRead(path) else {
    return nil
  }

  var currentLine = 1
  var lineStart = text.startIndex
  var index = text.startIndex
  while index < text.endIndex {
    if text[index] == "\n" {
      if currentLine == line {
        return String(text[lineStart..<index])
      }
      currentLine += 1
      lineStart = text.index(after: index)
    }
    index = text.index(after: index)
  }

  if currentLine == line {
    return String(text[lineStart..<text.endIndex])
  }
  return nil
}

private func swiftmutGenericConditionExpression(
  _ line: String
) -> (column: Int, sourceOriginal: String)? {
  let bytes = Array(line.utf8)
  let lineEnd = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  var start = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
  guard start < lineEnd else {
    return nil
  }

  if bytes[start] == 125 {
    start = swiftmutSkipHorizontalWhitespace(bytes, from: start + 1)
    if swiftmutASCIIHasPrefix(bytes, start: start, prefix: "else ") {
      start = swiftmutSkipHorizontalWhitespace(bytes, from: start + 5)
    }
  }

  guard !swiftmutSourceLineLooksLikeOptionalBindingCondition(bytes: bytes, start: start),
        !swiftmutTopLevelASCIIContains(bytes, start: start, end: lineEnd, pattern: ", let "),
        !swiftmutTopLevelASCIIContains(bytes, start: start, end: lineEnd, pattern: ", var ") else {
    return nil
  }

  let expressionRange: (start: Int, end: Int)?
  if swiftmutASCIIHasPrefix(bytes, start: start, prefix: "if ") {
    expressionRange = swiftmutControlConditionRange(bytes: bytes, start: start + 3, end: lineEnd)
  } else if swiftmutASCIIHasPrefix(bytes, start: start, prefix: "if(") {
    expressionRange = swiftmutParenthesizedControlConditionRange(bytes: bytes, open: start + 2, end: lineEnd)
  } else if swiftmutASCIIHasPrefix(bytes, start: start, prefix: "guard ") {
    expressionRange = swiftmutGuardConditionRange(bytes: bytes, start: start + 6, end: lineEnd)
  } else if swiftmutASCIIHasPrefix(bytes, start: start, prefix: "guard(") {
    expressionRange = swiftmutParenthesizedControlConditionRange(bytes: bytes, open: start + 5, end: lineEnd)
  } else if swiftmutASCIIHasPrefix(bytes, start: start, prefix: "while ") {
    expressionRange = swiftmutControlConditionRange(bytes: bytes, start: start + 6, end: lineEnd)
  } else if swiftmutASCIIHasPrefix(bytes, start: start, prefix: "while(") {
    expressionRange = swiftmutParenthesizedControlConditionRange(bytes: bytes, open: start + 5, end: lineEnd)
  } else if swiftmutASCIIHasPrefix(bytes, start: start, prefix: "for ")
      || swiftmutASCIIHasPrefix(bytes, start: start, prefix: "for(") {
    expressionRange = swiftmutForWhereConditionRange(bytes: bytes, start: start, end: lineEnd)
  } else {
    expressionRange = nil
  }

  guard var range = expressionRange else {
    return nil
  }
  range.start = swiftmutSkipHorizontalWhitespace(bytes, from: range.start)
  range.end = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: range.end)
  guard range.start < range.end else {
    return nil
  }
  return (
    range.start + 1,
    String(decoding: bytes[range.start..<range.end], as: UTF8.self))
}

private func swiftmutControlConditionRange(
  bytes: [UInt8],
  start: Int,
  end: Int
) -> (start: Int, end: Int)? {
  let conditionEnd = swiftmutTopLevelByteIndex(bytes, start: start, end: end, byte: 123) ?? end
  return (start, conditionEnd)
}

private func swiftmutGuardConditionRange(
  bytes: [UInt8],
  start: Int,
  end: Int
) -> (start: Int, end: Int)? {
  let elseIndex = swiftmutTopLevelASCIIIndex(bytes, start: start, end: end, pattern: " else ")
  let braceIndex = swiftmutTopLevelByteIndex(bytes, start: start, end: end, byte: 123)
  let conditionEnd = elseIndex ?? braceIndex ?? end
  return (start, conditionEnd)
}

private func swiftmutForWhereConditionRange(
  bytes: [UInt8],
  start: Int,
  end: Int
) -> (start: Int, end: Int)? {
  guard let whereIndex = swiftmutTopLevelASCIIIndex(bytes, start: start, end: end, pattern: " where ") else {
    return nil
  }
  let valueStart = whereIndex + 7
  let valueEnd = swiftmutTopLevelByteIndex(bytes, start: valueStart, end: end, byte: 123) ?? end
  return (valueStart, valueEnd)
}

private func swiftmutParenthesizedControlConditionRange(
  bytes: [UInt8],
  open: Int,
  end: Int
) -> (start: Int, end: Int)? {
  guard open < end,
        bytes[open] == 40,
        let close = swiftmutBalancedExpressionEnd(
          in: bytes,
          openIndex: open,
          close: 41,
          lineEnd: end
        ) else {
    return nil
  }
  return (open + 1, close - 1)
}

private func swiftmutTopLevelASCIIContains(
  _ bytes: [UInt8],
  start: Int,
  end: Int,
  pattern: String
) -> Bool {
  swiftmutTopLevelASCIIIndex(bytes, start: start, end: end, pattern: pattern) != nil
}

private func swiftmutTopLevelASCIIIndex(
  _ bytes: [UInt8],
  start: Int,
  end: Int,
  pattern: String
) -> Int? {
  let patternBytes = Array(pattern.utf8)
  guard !patternBytes.isEmpty,
        start < end,
        patternBytes.count <= end - start else {
    return nil
  }
  return swiftmutFirstTopLevelIndex(bytes, start: start, end: end) { index in
    guard index + patternBytes.count <= end else {
      return false
    }
    for offset in 0..<patternBytes.count where bytes[index + offset] != patternBytes[offset] {
      return false
    }
    return true
  }
}

private func swiftmutTopLevelByteIndex(
  _ bytes: [UInt8],
  start: Int,
  end: Int,
  byte: UInt8
) -> Int? {
  swiftmutFirstTopLevelIndex(bytes, start: start, end: end) { index in
    bytes[index] == byte
  }
}

private func swiftmutLineOpensFunctionBody(_ line: String) -> Bool {
  let bytes = Array(line.utf8)
  let start = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
  let end = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  return swiftmutTopLevelByteIndex(bytes, start: start, end: end, byte: 123) != nil
}

private func swiftmutFirstTopLevelIndex(
  _ bytes: [UInt8],
  start: Int,
  end: Int,
  matches: (Int) -> Bool
) -> Int? {
  var parenDepth = 0
  var bracketDepth = 0
  var braceDepth = 0
  var quote: UInt8?
  var escaped = false
  var index = start
  while index < end {
    let byte = bytes[index]
    if let activeQuote = quote {
      if escaped {
        escaped = false
      } else if byte == 92 {
        escaped = true
      } else if byte == activeQuote {
        quote = nil
      }
      index += 1
      continue
    }
    if byte == 34 || byte == 39 {
      quote = byte
      index += 1
      continue
    }
    if parenDepth == 0 && bracketDepth == 0 && braceDepth == 0 && matches(index) {
      return index
    }
    switch byte {
    case 40:
      parenDepth += 1
    case 41:
      if parenDepth > 0 { parenDepth -= 1 }
    case 91:
      bracketDepth += 1
    case 93:
      if bracketDepth > 0 { bracketDepth -= 1 }
    case 123:
      braceDepth += 1
    case 125:
      if braceDepth > 0 { braceDepth -= 1 }
    default:
      break
    }
    index += 1
  }
  return nil
}

private func swiftmutSourceExpressionIsSingleLineComplete(
  bytes: [UInt8],
  start: Int,
  end: Int
) -> Bool {
  var parenDepth = 0
  var bracketDepth = 0
  var braceDepth = 0
  var quote: UInt8?
  var escaped = false
  var index = start
  while index < end {
    let byte = bytes[index]
    if let activeQuote = quote {
      if escaped {
        escaped = false
      } else if byte == 92 {
        escaped = true
      } else if byte == activeQuote {
        quote = nil
      }
      index += 1
      continue
    }
    if byte == 34 || byte == 39 {
      quote = byte
      index += 1
      continue
    }
    switch byte {
    case 40:
      parenDepth += 1
    case 41:
      parenDepth -= 1
      if parenDepth < 0 { return false }
    case 91:
      bracketDepth += 1
    case 93:
      bracketDepth -= 1
      if bracketDepth < 0 { return false }
    case 123:
      braceDepth += 1
    case 125:
      braceDepth -= 1
      if braceDepth < 0 { return false }
    default:
      break
    }
    index += 1
  }
  return quote == nil && parenDepth == 0 && bracketDepth == 0 && braceDepth == 0
}

private func swiftmutSourceLineLooksLikeExplicitCondition(_ line: String) -> Bool {
  let bytes = Array(line.utf8)
  var start = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
  guard start < bytes.count else {
    return false
  }

  if bytes[start] == 125 {
    start = swiftmutSkipHorizontalWhitespace(bytes, from: start + 1)
    if swiftmutASCIIHasPrefix(bytes, start: start, prefix: "else ") {
      start = swiftmutSkipHorizontalWhitespace(bytes, from: start + 5)
    }
  }

  if swiftmutSourceLineLooksLikeOptionalBindingCondition(bytes: bytes, start: start) {
    return false
  }

  return swiftmutASCIIHasPrefix(bytes, start: start, prefix: "if ")
    || swiftmutASCIIHasPrefix(bytes, start: start, prefix: "if(")
    || swiftmutASCIIHasPrefix(bytes, start: start, prefix: "guard ")
    || swiftmutASCIIHasPrefix(bytes, start: start, prefix: "guard(")
    || swiftmutASCIIHasPrefix(bytes, start: start, prefix: "while ")
    || swiftmutASCIIHasPrefix(bytes, start: start, prefix: "while(")
    || swiftmutASCIIHasPrefix(bytes, start: start, prefix: "for ")
    || swiftmutASCIIHasPrefix(bytes, start: start, prefix: "for(")
}

private func swiftmutSourceLineLooksLikeOptionalBindingCondition(bytes: [UInt8], start: Int) -> Bool {
  swiftmutASCIIHasPrefix(bytes, start: start, prefix: "if let ")
    || swiftmutASCIIHasPrefix(bytes, start: start, prefix: "if var ")
    || swiftmutASCIIHasPrefix(bytes, start: start, prefix: "guard let ")
    || swiftmutASCIIHasPrefix(bytes, start: start, prefix: "guard var ")
}

private func swiftmutReturnSourceLooksLikeStatement(
  file: String,
  line: Int,
  config: SwiftmutConfig
) -> Bool {
  guard let sourceLine = swiftmutSourceLine(file: file, line: line, config: config) else {
    return true
  }
  let bytes = Array(sourceLine.utf8)
  let start = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
  return swiftmutASCIIHasExactPrefix(bytes, start: start, prefix: "return ")
}

private func swiftmutVoidCallSourceLooksLikeStatement(
  file: String,
  line: Int,
  config: SwiftmutConfig
) -> Bool {
  guard let sourceLine = swiftmutSourceLine(file: file, line: line, config: config) else {
    return true
  }
  return swiftmutSourceLineLooksLikeVoidCallStatement(sourceLine)
}

private func swiftmutSourceLineLooksLikeVoidCallStatement(_ line: String) -> Bool {
  let bytes = Array(line.utf8)
  let start = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
  let end = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  guard start < end else {
    return false
  }

  let nonStatementPrefixes = [
    "let ", "var ", "return ", "if ", "if(", "guard ", "guard(",
    "while ", "while(", "for ", "for(", "switch ", "catch ",
    "public ", "private ", "internal ", "fileprivate ", "open ",
    "static ", "func ", "init(", "deinit", ".", "}", ")", "]"
  ]
  for prefix in nonStatementPrefixes {
    if swiftmutASCIIHasPrefix(bytes, start: start, prefix: prefix) {
      return false
    }
  }
  if swiftmutASCIIContains(bytes, start: start, end: end, pattern: " = ") {
    return false
  }
  if swiftmutSourceLineLooksLikeArgumentLabel(bytes: bytes, start: start, end: end) {
    return false
  }
  if swiftmutASCIIContains(bytes, start: start, end: end, pattern: ":")
      && !swiftmutASCIIContains(bytes, start: start, end: end, pattern: "(") {
    return false
  }
  return swiftmutASCIIContains(bytes, start: start, end: end, pattern: "(")
}

private func swiftmutTrimTrailingHorizontalWhitespace(_ bytes: [UInt8], end: Int) -> Int {
  var index = end
  while index > 0 && swiftmutIsHorizontalWhitespace(bytes[index - 1]) {
    index -= 1
  }
  return index
}

private func swiftmutSourceLineLooksLikeArgumentLabel(bytes: [UInt8], start: Int, end: Int) -> Bool {
  var colonIndex: Int?
  var index = start
  while index < end {
    if bytes[index] == 58 {
      colonIndex = index
      break
    }
    index += 1
  }
  guard let colonIndex else {
    return false
  }

  var labelEnd = colonIndex
  while labelEnd > start && swiftmutIsHorizontalWhitespace(bytes[labelEnd - 1]) {
    labelEnd -= 1
  }
  guard start < labelEnd else {
    return false
  }
  for labelIndex in start..<labelEnd {
    guard swiftmutIsASCIILetterNumberOrUnderscore(bytes[labelIndex]) else {
      return false
    }
  }
  return true
}

private func swiftmutSkipHorizontalWhitespace(_ bytes: [UInt8], from start: Int) -> Int {
  var index = start
  while index < bytes.count && swiftmutIsHorizontalWhitespace(bytes[index]) {
    index += 1
  }
  return index
}

private func swiftmutASCIIContains(_ bytes: [UInt8], start: Int, end: Int, pattern: String) -> Bool {
  swiftmutASCIIIndex(bytes, start: start, end: end, pattern: pattern) != nil
}

private func swiftmutASCIIIndex(_ bytes: [UInt8], start: Int, end: Int, pattern: String) -> Int? {
  let patternBytes = Array(pattern.utf8)
  guard !patternBytes.isEmpty,
        start >= 0,
        start <= end,
        end <= bytes.count,
        patternBytes.count <= end - start else {
    return nil
  }

  var index = start
  while index <= end - patternBytes.count {
    var matched = true
    for offset in 0..<patternBytes.count {
      if bytes[index + offset] != patternBytes[offset] {
        matched = false
        break
      }
    }
    if matched {
      return index
    }
    index += 1
  }
  return nil
}

private func swiftmutASCIIHasExactPrefix(_ bytes: [UInt8], start: Int, prefix: String) -> Bool {
  let prefixBytes = Array(prefix.utf8)
  guard start >= 0 && start + prefixBytes.count <= bytes.count else {
    return false
  }
  for offset in 0..<prefixBytes.count {
    if bytes[start + offset] != prefixBytes[offset] {
      return false
    }
  }
  return true
}

private func swiftmutASCIIHasPrefix(_ bytes: [UInt8], start: Int, prefix: String) -> Bool {
  let prefixBytes = Array(prefix.utf8)
  guard start >= 0 && start + prefixBytes.count <= bytes.count else {
    return false
  }
  for offset in 0..<prefixBytes.count {
    if swiftmutASCIILowercase(bytes[start + offset]) != swiftmutASCIILowercase(prefixBytes[offset]) {
      return false
    }
  }
  return true
}

private func swiftmutASCIILowercase(_ byte: UInt8) -> UInt8 {
  if byte >= 65 && byte <= 90 {
    return byte + 32
  }
  return byte
}

private func swiftmutIsASCIIIdentifierStart(_ byte: UInt8) -> Bool {
  if byte >= 65 && byte <= 90 {
    return true
  }
  if byte >= 97 && byte <= 122 {
    return true
  }
  return byte == 95
}

private func swiftmutIsASCIILetterNumberOrUnderscore(_ byte: UInt8) -> Bool {
  if byte >= 48 && byte <= 57 {
    return true
  }
  if byte >= 65 && byte <= 90 {
    return true
  }
  if byte >= 97 && byte <= 122 {
    return true
  }
  return byte == 95
}

private func swiftmutExclusionReason(
  function: Function,
  config: SwiftmutConfig
) -> String? {
  if swiftmutIsGeneratedInvalidLocationFunction(function) {
    return "generatedInvalidLocation"
  }
  if swiftmutIsGeneratedSpecializationFunctionName(function.name.string) {
    return "generatedSpecialization"
  }
  let location = function.location.description
  for fragment in config.excludePathFragments {
    if location.contains(fragment) {
      return "excludedPath"
    }
  }
  return nil
}

private func swiftmutIsGeneratedInvalidLocationFunction(_ function: Function) -> Bool {
  let location = function.location.description
  guard location.contains("<invalid loc>") else {
    return false
  }

  let name = function.name.string
  return name.contains("__derived_")
    || name.contains("CodingKeys")
    || name.hasSuffix("TW")
}

private func swiftmutIsGeneratedSpecializationFunctionName(_ name: String) -> Bool {
  name.contains("Tf4")
}

private func swiftmutFindSourceOperator(
  moduleName: String,
  functionLocation: String,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard !config.packageRoot.isEmpty else {
    return nil
  }

  let displayRules = swiftmutSourceMutationDisplayRules(for: mutation, config: config)

  let preferredPrefix = config.packageRoot + "/Sources/" + moduleName + "/"
  let locatedSourcePaths = swiftmutSwiftSourcePaths(config: config).compactMap { path
    -> (path: String, preferredLine: Int)? in
    guard functionLocation.contains(path),
          let preferredLine = swiftmutPreferredLine(in: functionLocation, path: path) else {
      return nil
    }
    return (path, preferredLine)
  }.sorted { lhs, rhs in
    lhs.path < rhs.path
  }
  guard !locatedSourcePaths.isEmpty else {
    return nil
  }

  var fallback: (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)?

  for (path, preferredLine) in locatedSourcePaths {
    guard let text = swiftmutRead(path) else {
      continue
    }
    var bestForPath: (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)?
    for rule in displayRules {
      if let position = swiftmutFindOperator(
        rule.sourceOriginal,
        mutatedOperator: rule.sourceMutated,
        in: text,
        preferredLine: preferredLine,
        maxPreferredLineDistance: 4
      ) {
        let sourceMutated = rule.sourceMutatedOverride.isEmpty
          ? position.sourceMutated
          : rule.sourceMutatedOverride
        let result = (
          swiftmutTrimPackageRoot(path, config: config),
          position.line,
          position.column,
          position.sourceOriginal,
          sourceMutated)
        if let existing = bestForPath,
           swiftmutLineDistance(existing.line, preferredLine) <= swiftmutLineDistance(result.1, preferredLine) {
          continue
        }
        bestForPath = result
      }
    }
    if let result = bestForPath {
      if path.hasPrefix(preferredPrefix) {
        return result
      }
      if fallback == nil {
        fallback = result
      }
      continue
    }

    if let result = swiftmutFindUniqueSourceOperatorInFunctionBody(
      path: path,
      preferredLine: preferredLine,
      displayRules: displayRules,
      config: config
    ) {
      if path.hasPrefix(preferredPrefix) {
        return result
      }
      if fallback == nil {
        fallback = result
      }
    }
  }

  return fallback
}

private func swiftmutFindUniqueSourceOperatorInFunctionBody(
  path: String,
  preferredLine: Int,
  displayRules: [SwiftmutSourceMutationDisplayRule],
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard preferredLine > 0,
        let text = swiftmutRead(path) else {
    return nil
  }

  var matches: [(line: Int, column: Int, sourceOriginal: String, sourceMutated: String)] = []
  var currentLine = 1
  var lineStart = text.startIndex
  var index = text.startIndex
  var braceDepth = 0
  var sawOpeningBrace = false

  func inspectLine(_ lineText: String, line: Int) {
    guard line >= preferredLine,
          matches.count < 2 else {
      return
    }
    for rule in displayRules {
      guard let position = swiftmutFindOperator(
        rule.sourceOriginal,
        mutatedOperator: rule.sourceMutated,
        in: lineText,
        preferredLine: nil
      ) else {
        continue
      }
      let sourceMutated = rule.sourceMutatedOverride.isEmpty
        ? position.sourceMutated
        : rule.sourceMutatedOverride
      matches.append((line, position.column, position.sourceOriginal, sourceMutated))
      if matches.count >= 2 {
        return
      }
    }
  }

  func updateBraceDepth(_ lineText: String) {
    for byte in lineText.utf8 {
      if byte == 123 {
        braceDepth += 1
        sawOpeningBrace = true
      } else if byte == 125 {
        braceDepth -= 1
      }
    }
  }

  while index < text.endIndex {
    if text[index] == "\n" {
      let lineText = String(text[lineStart..<index])
      if currentLine >= preferredLine {
        inspectLine(lineText, line: currentLine)
        updateBraceDepth(lineText)
        if sawOpeningBrace && braceDepth <= 0 {
          break
        }
        if currentLine >= preferredLine + 300 {
          break
        }
      }
      currentLine += 1
      lineStart = text.index(after: index)
    }
    index = text.index(after: index)
  }

  if index == text.endIndex && currentLine >= preferredLine {
    let lineText = String(text[lineStart..<text.endIndex])
    inspectLine(lineText, line: currentLine)
  }

  guard matches.count == 1,
        let match = matches.first else {
    return nil
  }
  return (
    swiftmutTrimPackageRoot(path, config: config),
    match.line,
    match.column,
    match.sourceOriginal,
    match.sourceMutated)
}

private func swiftmutFindDescribedSourceOperator(
  moduleName: String,
  functionLocation: String,
  locationDescription: String,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard let snippet = swiftmutQuotedSourceSnippetPrefix(locationDescription),
        let needle = swiftmutDescribedSourceOperatorNeedle(snippet) else {
    return nil
  }

  let displayRules = swiftmutSourceMutationDisplayRules(for: mutation, config: config)
  let preferredPrefix = config.packageRoot + "/Sources/" + moduleName + "/"
  let locatedSourcePaths = swiftmutSwiftSourcePaths(config: config).compactMap { path
    -> (path: String, preferredLine: Int)? in
    guard functionLocation.contains(path),
          let preferredLine = swiftmutPreferredLine(in: functionLocation, path: path) else {
      return nil
    }
    return (path, preferredLine)
  }.sorted { lhs, rhs in
    lhs.path < rhs.path
  }
  guard !locatedSourcePaths.isEmpty else {
    return nil
  }

  var fallback: (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)?
  for (path, preferredLine) in locatedSourcePaths {
    guard let result = swiftmutFindDescribedSourceOperatorInFunctionBody(
      path: path,
      preferredLine: preferredLine,
      displayRules: displayRules,
      needle: needle,
      config: config
    ) else {
      continue
    }
    if path.hasPrefix(preferredPrefix) {
      return result
    }
    if fallback == nil {
      fallback = result
    }
  }
  return fallback
}

private func swiftmutDescribedSourceOperatorNeedle(_ snippet: String) -> String? {
  let bytes = Array(snippet.utf8)
  var start = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
  var end = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  guard start < end else {
    return nil
  }
  if start + 1 < end
      && (bytes[start] == 38 || bytes[start] == 124)
      && bytes[start + 1] == bytes[start] {
    start = swiftmutSkipHorizontalWhitespace(bytes, from: start + 2)
  }
  while end > start {
    let byte = bytes[end - 1]
    if byte == 44 || byte == 123 || byte == 125 {
      end = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: end - 1)
      continue
    }
    break
  }
  guard end - start >= 2 else {
    return nil
  }
  let result = String(decoding: bytes[start..<end], as: UTF8.self)
  return swiftmutSourceOperatorNeedleContainsOperator(result) ? result : nil
}

private func swiftmutSourceOperatorNeedleContainsOperator(_ needle: String) -> Bool {
  let operators = ["!=", "==", ">=", "<=", ">", "<"]
  let bytes = Array(needle.utf8)
  let start = swiftmutSkipHorizontalWhitespace(bytes, from: 0)
  let end = swiftmutTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  guard start < end else {
    return false
  }
  for operatorText in operators where swiftmutASCIIContains(bytes, start: start, end: end, pattern: operatorText) {
    return true
  }
  return false
}

private func swiftmutFindDescribedSourceOperatorInFunctionBody(
  path: String,
  preferredLine: Int,
  displayRules: [SwiftmutSourceMutationDisplayRule],
  needle: String,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard preferredLine > 0,
        let text = swiftmutRead(path) else {
    return nil
  }

  var matches: [(line: Int, column: Int, sourceOriginal: String, sourceMutated: String)] = []
  var currentLine = 1
  var lineStart = text.startIndex
  var index = text.startIndex
  var braceDepth = 0
  var sawOpeningBrace = false

  func inspectLine(_ lineText: String, line: Int) {
    guard line >= preferredLine,
          matches.count < 2,
          lineText.contains(needle) else {
      return
    }

    var lineMatches: [(line: Int, column: Int, sourceOriginal: String, sourceMutated: String)] = []
    for rule in displayRules {
      let sourceMutatedOverride = rule.sourceMutatedOverride
      for position in swiftmutFindOperatorMatches(
        rule.sourceOriginal,
        mutatedOperator: rule.sourceMutated,
        in: lineText
      ) {
        let sourceMutated = sourceMutatedOverride.isEmpty
          ? position.sourceMutated
          : sourceMutatedOverride
        lineMatches.append((line, position.column, position.sourceOriginal, sourceMutated))
      }
    }

    if lineMatches.count == 1,
       let only = lineMatches.first {
      matches.append(only)
      return
    }

    let filtered = lineMatches.filter { $0.sourceOriginal.contains(needle) }
    if filtered.count == 1,
       let only = filtered.first {
      matches.append(only)
    }
  }

  func updateBraceDepth(_ lineText: String) {
    for byte in lineText.utf8 {
      if byte == 123 {
        braceDepth += 1
        sawOpeningBrace = true
      } else if byte == 125 {
        braceDepth -= 1
      }
    }
  }

  while index < text.endIndex {
    if text[index] == "\n" {
      let lineText = String(text[lineStart..<index])
      if currentLine >= preferredLine {
        inspectLine(lineText, line: currentLine)
        updateBraceDepth(lineText)
        if matches.count >= 2 {
          break
        }
        if sawOpeningBrace && braceDepth <= 0 {
          break
        }
        if currentLine >= preferredLine + 300 {
          break
        }
      }
      currentLine += 1
      lineStart = text.index(after: index)
    }
    index = text.index(after: index)
  }

  if index == text.endIndex && currentLine >= preferredLine {
    let lineText = String(text[lineStart..<text.endIndex])
    inspectLine(lineText, line: currentLine)
  }

  guard matches.count == 1,
        let match = matches.first else {
    return nil
  }
  return (
    swiftmutTrimPackageRoot(path, config: config),
    match.line,
    match.column,
    match.sourceOriginal,
    match.sourceMutated)
}

private func swiftmutComparisonOrdinalAndCount(
  for comparison: BuiltinInst,
  in function: Function
) -> (ordinal: Int, count: Int)? {
  guard let targetID = swiftmutComparisonBuiltinIDName(comparison) else {
    return nil
  }

  var ordinal = 0
  var count = 0
  for block in function.blocks {
    for instruction in block.instructions {
      guard let candidate = instruction as? BuiltinInst,
            swiftmutComparisonBuiltinIDName(candidate) == targetID else {
        continue
      }
      count += 1
      if candidate === comparison {
        ordinal = count
      }
    }
  }
  guard ordinal > 0 else {
    return nil
  }
  return (ordinal, count)
}

private func swiftmutFindOrdinalSourceOperator(
  moduleName: String,
  functionLocation: String,
  ordinal: Int,
  expectedCount: Int,
  mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard ordinal > 0, expectedCount > 0 else {
    return nil
  }

  let displayRules = swiftmutSourceMutationDisplayRules(for: mutation, config: config)
  let preferredPrefix = config.packageRoot + "/Sources/" + moduleName + "/"
  let locatedSourcePaths = swiftmutSwiftSourcePaths(config: config).compactMap { path
    -> (path: String, preferredLine: Int)? in
    guard functionLocation.contains(path),
          let preferredLine = swiftmutPreferredLine(in: functionLocation, path: path) else {
      return nil
    }
    return (path, preferredLine)
  }.sorted { lhs, rhs in
    lhs.path < rhs.path
  }
  guard !locatedSourcePaths.isEmpty else {
    return nil
  }

  var fallback: (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)?
  for (path, preferredLine) in locatedSourcePaths {
    guard let result = swiftmutFindOrdinalSourceOperatorInFunctionBody(
      path: path,
      preferredLine: preferredLine,
      displayRules: displayRules,
      ordinal: ordinal,
      expectedCount: expectedCount,
      config: config
    ) else {
      continue
    }
    if path.hasPrefix(preferredPrefix) {
      return result
    }
    if fallback == nil {
      fallback = result
    }
  }
  return fallback
}

private func swiftmutFindOrdinalSourceOperatorInFunctionBody(
  path: String,
  preferredLine: Int,
  displayRules: [SwiftmutSourceMutationDisplayRule],
  ordinal: Int,
  expectedCount: Int,
  config: SwiftmutConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard preferredLine > 0,
        let text = swiftmutRead(path) else {
    return nil
  }

  var matches: [(line: Int, column: Int, sourceOriginal: String, sourceMutated: String)] = []
  var currentLine = 1
  var lineStart = text.startIndex
  var index = text.startIndex
  var braceDepth = 0
  var sawOpeningBrace = false

  func inspectLine(_ lineText: String, line: Int) {
    guard line >= preferredLine,
          matches.count <= expectedCount else {
      return
    }
    for rule in displayRules {
      let sourceMutatedOverride = rule.sourceMutatedOverride
      for position in swiftmutFindOperatorMatches(
        rule.sourceOriginal,
        mutatedOperator: rule.sourceMutated,
        in: lineText
      ) {
        let sourceMutated = sourceMutatedOverride.isEmpty
          ? position.sourceMutated
          : sourceMutatedOverride
        let duplicate = matches.contains {
          $0.line == line
            && $0.column == position.column
            && $0.sourceOriginal == position.sourceOriginal
            && $0.sourceMutated == sourceMutated
        }
        if !duplicate {
          matches.append((line, position.column, position.sourceOriginal, sourceMutated))
        }
      }
    }
    matches.sort {
      if $0.line != $1.line {
        return $0.line < $1.line
      }
      return $0.column < $1.column
    }
  }

  func updateBraceDepth(_ lineText: String) {
    for byte in lineText.utf8 {
      if byte == 123 {
        braceDepth += 1
        sawOpeningBrace = true
      } else if byte == 125 {
        braceDepth -= 1
      }
    }
  }

  while index < text.endIndex {
    if text[index] == "\n" {
      let lineText = String(text[lineStart..<index])
      if currentLine >= preferredLine {
        inspectLine(lineText, line: currentLine)
        updateBraceDepth(lineText)
        if sawOpeningBrace && braceDepth <= 0 {
          break
        }
        if currentLine >= preferredLine + 300 {
          break
        }
      }
      currentLine += 1
      lineStart = text.index(after: index)
    }
    index = text.index(after: index)
  }

  if index == text.endIndex && currentLine >= preferredLine {
    let lineText = String(text[lineStart..<text.endIndex])
    inspectLine(lineText, line: currentLine)
  }

  guard matches.count == expectedCount,
        ordinal <= matches.count else {
    return nil
  }
  let match = matches[ordinal - 1]
  return (
    swiftmutTrimPackageRoot(path, config: config),
    match.line,
    match.column,
    match.sourceOriginal,
    match.sourceMutated)
}

private func swiftmutSourceMutationDisplayRules(
  for mutation: SwiftmutMutation,
  config: SwiftmutConfig
) -> [SwiftmutSourceMutationDisplayRule] {
  let builtinID = swiftmutBuiltinIDName(mutation.originalID) ?? ""
  let rules = config.sourceMutationDisplayRules.filter {
    $0.mutator == mutation.mutator && $0.builtinID == builtinID
  }
  if !rules.isEmpty {
    return rules
  }
  return [
    SwiftmutSourceMutationDisplayRule(
      mutator: mutation.mutator,
      builtinID: builtinID,
      sourceOriginal: mutation.sourceOriginal,
      sourceMutated: mutation.sourceMutated,
      sourceMutatedOverride: ""
    )
  ]
}

private func swiftmutFindOperator(
  _ op: String,
  mutatedOperator: String,
  in text: String,
  preferredLine: Int?,
  maxPreferredLineDistance: Int? = nil
) -> (line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  let bytes = Array(text.utf8)
  let opBytes = Array(op.utf8)
  guard !opBytes.isEmpty else {
    return nil
  }

  var line = 1
  var column = 1
  var index = 0
  var best: (line: Int, column: Int, sourceOriginal: String, sourceMutated: String)?
  while index <= bytes.count - opBytes.count {
    var matched = true
    for opIndex in 0..<opBytes.count {
      if bytes[index + opIndex] != opBytes[opIndex] {
        matched = false
        break
      }
    }
    if matched {
      if !swiftmutIsSourceComparisonOperator(
        bytes: bytes,
        operatorStart: index,
        operatorEnd: index + opBytes.count
      ) {
        if bytes[index] == 10 {
          line += 1
          column = 1
        } else {
          column += 1
        }
        index += 1
        continue
      }
      let expression = swiftmutSourceExpression(
        in: bytes,
        operatorStart: index,
        operatorEnd: index + opBytes.count,
        mutatedOperator: mutatedOperator)
      let candidate = (line, column, expression.original, expression.mutated)
      guard let preferredLine = preferredLine else {
        return candidate
      }
      if let maxPreferredLineDistance = maxPreferredLineDistance,
         swiftmutLineDistance(line, preferredLine) > maxPreferredLineDistance {
        if bytes[index] == 10 {
          line += 1
          column = 1
        } else {
          column += 1
        }
        index += 1
        continue
      }
      if line == preferredLine {
        return candidate
      }
      if let existing = best {
        if swiftmutLineDistance(line, preferredLine) < swiftmutLineDistance(existing.line, preferredLine) {
          best = candidate
        }
      } else {
        best = candidate
      }
    }
    if bytes[index] == 10 {
      line += 1
      column = 1
    } else {
      column += 1
    }
    index += 1
  }
  return best
}

private func swiftmutFindOperatorMatches(
  _ op: String,
  mutatedOperator: String,
  in text: String
) -> [(column: Int, sourceOriginal: String, sourceMutated: String)] {
  let bytes = Array(text.utf8)
  let opBytes = Array(op.utf8)
  guard !opBytes.isEmpty,
        opBytes.count <= bytes.count else {
    return []
  }

  var matches: [(column: Int, sourceOriginal: String, sourceMutated: String)] = []
  var column = 1
  var index = 0
  while index <= bytes.count - opBytes.count {
    var matched = true
    for opIndex in 0..<opBytes.count where bytes[index + opIndex] != opBytes[opIndex] {
      matched = false
      break
    }
    if matched,
       swiftmutIsSourceComparisonOperator(
        bytes: bytes,
        operatorStart: index,
        operatorEnd: index + opBytes.count
       ) {
      let expression = swiftmutSourceExpression(
        in: bytes,
        operatorStart: index,
        operatorEnd: index + opBytes.count,
        mutatedOperator: mutatedOperator)
      matches.append((column, expression.original, expression.mutated))
    }
    column += 1
    index += 1
  }
  return matches
}

private func swiftmutPreferredLine(in location: String, path: String) -> Int? {
  let locationBytes = Array(location.utf8)
  let pathBytes = Array(path.utf8)
  guard let pathIndex = swiftmutFind(pathBytes, in: locationBytes, startingAt: 0) else {
    return nil
  }
  var index = pathIndex + pathBytes.count
  guard index < locationBytes.count, locationBytes[index] == 58 else {
    return nil
  }
  index += 1
  var value = 0
  var hasDigit = false
  while index < locationBytes.count {
    let byte = locationBytes[index]
    guard byte >= 48 && byte <= 57 else {
      break
    }
    value = value * 10 + Int(byte - 48)
    hasDigit = true
    index += 1
  }
  return hasDigit ? value : nil
}

private func swiftmutLineDistance(_ lhs: Int, _ rhs: Int) -> Int {
  lhs >= rhs ? lhs - rhs : rhs - lhs
}

private func swiftmutIsSourceComparisonOperator(
  bytes: [UInt8],
  operatorStart: Int,
  operatorEnd: Int
) -> Bool {
  if operatorStart > 0 && bytes[operatorStart - 1] == 45 {
    return false
  }
  if operatorStart > 0 && swiftmutIsOperatorByte(bytes[operatorStart - 1]) {
    return false
  }
  if operatorEnd < bytes.count && swiftmutIsOperatorByte(bytes[operatorEnd]) {
    return false
  }
  if swiftmutIsOperatorFunctionDeclaration(bytes: bytes, operatorStart: operatorStart) {
    return false
  }
  if swiftmutIsLikelyGenericAngleBracket(
    bytes: bytes,
    operatorStart: operatorStart,
    operatorEnd: operatorEnd
  ) {
    return false
  }
  return true
}

private func swiftmutIsLikelyGenericAngleBracket(
  bytes: [UInt8],
  operatorStart: Int,
  operatorEnd: Int
) -> Bool {
  guard operatorEnd == operatorStart + 1 else {
    return false
  }
  if bytes[operatorStart] == 60 {
    return swiftmutHasIdentifierBefore(bytes: bytes, index: operatorStart)
      && swiftmutHasIdentifierAfter(bytes: bytes, index: operatorEnd)
      && swiftmutHasClosingAngleBeforeExpressionDelimiter(bytes: bytes, index: operatorEnd)
  }
  if bytes[operatorStart] == 62 {
    return swiftmutHasIdentifierBefore(bytes: bytes, index: operatorStart)
      && swiftmutHasOpeningAngleBeforeExpressionDelimiter(bytes: bytes, index: operatorStart)
  }
  return false
}

private func swiftmutHasIdentifierBefore(bytes: [UInt8], index: Int) -> Bool {
  index > 0 && swiftmutIsExpressionByte(bytes[index - 1])
}

private func swiftmutIsOperatorFunctionDeclaration(bytes: [UInt8], operatorStart: Int) -> Bool {
  var offset = operatorStart
  while offset > 0 && swiftmutIsHorizontalWhitespace(bytes[offset - 1]) {
    offset -= 1
  }

  let tokenEnd = offset
  while offset > 0 && swiftmutIsExpressionByte(bytes[offset - 1]) {
    offset -= 1
  }

  guard tokenEnd > offset else {
    return false
  }
  return String(decoding: bytes[offset..<tokenEnd], as: UTF8.self) == "func"
}

private func swiftmutHasIdentifierAfter(bytes: [UInt8], index: Int) -> Bool {
  index < bytes.count && swiftmutIsExpressionByte(bytes[index])
}

private func swiftmutHasClosingAngleBeforeExpressionDelimiter(bytes: [UInt8], index: Int) -> Bool {
  var offset = index
  while offset < bytes.count {
    let byte = bytes[offset]
    if byte == 62 {
      return true
    }
    if byte == 10 || byte == 59 || byte == 123 || byte == 125 || byte == 61 {
      return false
    }
    offset += 1
  }
  return false
}

private func swiftmutHasOpeningAngleBeforeExpressionDelimiter(bytes: [UInt8], index: Int) -> Bool {
  var offset = index
  while offset > 0 {
    offset -= 1
    let byte = bytes[offset]
    if byte == 60 {
      return true
    }
    if byte == 10 || byte == 59 || byte == 123 || byte == 125 || byte == 61 {
      return false
    }
  }
  return false
}

private func swiftmutIsOperatorByte(_ byte: UInt8) -> Bool {
  switch byte {
  case 33, 37, 38, 42, 43, 45, 47, 58, 60, 61, 62, 63, 94, 124, 126:
    return true
  default:
    return false
  }
}

private func swiftmutSourceExpression(
  in bytes: [UInt8],
  operatorStart: Int,
  operatorEnd: Int,
  mutatedOperator: String
) -> (original: String, mutated: String) {
  var leftStart = operatorStart
  if !mutatedOperator.isEmpty {
    while leftStart > 0 && swiftmutIsHorizontalWhitespace(bytes[leftStart - 1]) {
      leftStart -= 1
    }
    while leftStart > 0 && swiftmutIsExpressionByte(bytes[leftStart - 1]) {
      leftStart -= 1
    }
  }

  var rightEnd = operatorEnd
  while rightEnd < bytes.count && swiftmutIsHorizontalWhitespace(bytes[rightEnd]) {
    rightEnd += 1
  }
  while rightEnd < bytes.count && swiftmutIsExpressionByte(bytes[rightEnd]) {
    rightEnd += 1
  }

  let original = String(decoding: bytes[leftStart..<rightEnd], as: UTF8.self)
  let mutatedPrefix = String(decoding: bytes[leftStart..<operatorStart], as: UTF8.self)
  let mutatedSuffix = String(decoding: bytes[operatorEnd..<rightEnd], as: UTF8.self)
  return (original, mutatedPrefix + mutatedOperator + mutatedSuffix)
}

private func swiftmutIsHorizontalWhitespace(_ byte: UInt8) -> Bool {
  byte == 32 || byte == 9
}

private func swiftmutIsExpressionByte(_ byte: UInt8) -> Bool {
  if byte >= 48 && byte <= 57 {
    return true
  }
  if byte >= 65 && byte <= 90 {
    return true
  }
  if byte >= 97 && byte <= 122 {
    return true
  }
  switch byte {
  case 36, 46, 95:
    return true
  default:
    return false
  }
}

private func swiftmutSwiftSourcePaths(config: SwiftmutConfig) -> [String] {
  var paths: [String] = []
  for path in config.sourceFiles {
    if swiftmutPathIsIncluded(path, config: config) {
      paths.append(path)
    }
  }
  return paths
}

private func swiftmutPathIsIncluded(
  _ path: String,
  config: SwiftmutConfig
) -> Bool {
  if !config.packageRoot.isEmpty && !path.hasPrefix(config.packageRoot + "/") {
    return false
  }
  if !config.sourceFiles.isEmpty && !swiftmutPathIsConfiguredSource(path, config: config) {
    return false
  }
  for fragment in config.excludePathFragments {
    if path.contains(fragment) {
      return false
    }
  }
  return true
}

private func swiftmutPathIsConfiguredSource(
  _ path: String,
  config: SwiftmutConfig
) -> Bool {
  for sourcePath in config.sourceFiles {
    if path == sourcePath {
      return true
    }
  }
  return false
}

private func swiftmutIncludedSourcePath(
  _ path: String,
  config: SwiftmutConfig
) -> String? {
  if swiftmutPathIsIncluded(path, config: config) {
    return path
  }
  let suffix = path.hasPrefix("/") ? path : "/" + path
  for sourceFile in config.sourceFiles {
    if sourceFile.hasSuffix(suffix),
       swiftmutPathIsIncluded(sourceFile, config: config) {
      return sourceFile
    }
  }
  return nil
}

private func swiftmutTrimPackageRoot(
  _ path: String,
  config: SwiftmutConfig
) -> String {
  guard !config.packageRoot.isEmpty else {
    return path
  }
  if path == config.packageRoot {
    return "."
  }
  if path.hasPrefix(config.packageRoot + "/") {
    return String(path.dropFirst(config.packageRoot.count + 1))
  }
  return path
}

private func swiftmutCreateParentDirectories(forFile path: String) {
  #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(Linux) || os(Android)
  let components = path.split(separator: "/", omittingEmptySubsequences: true)
  guard components.count > 1 else {
    return
  }

  var current = path.hasPrefix("/") ? "/" : ""
  for component in components.dropLast() {
    if current.isEmpty || current == "/" {
      current += component
    } else {
      current += "/" + component
    }
    _ = current.withCString { mkdir($0, 0o755) }
  }
  #endif
}

private func swiftmutRead(_ path: String) -> String? {
  #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(Linux) || os(Android)
  return path.withCString { pathPointer in
    guard let file = fopen(pathPointer, "r") else {
      return nil
    }
    defer { fclose(file) }

    var output = ""
    var buffer = [CChar](repeating: 0, count: 4096)
    while true {
      let readLine = buffer.withUnsafeMutableBufferPointer {
        fgets($0.baseAddress, Int32($0.count), file)
      }
      guard readLine != nil else {
        break
      }
      output += String(cString: buffer)
    }
    return output
  }
  #else
  return nil
  #endif
}

private func swiftmutWrite(
  _ text: String,
  to path: String,
  append: Bool
) {
  #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(Linux) || os(Android)
  let mode = append ? "a" : "w"
  path.withCString { pathPointer in
    mode.withCString { modePointer in
      guard let file = fopen(pathPointer, modePointer) else {
        return
      }
      _ = text.withCString { textPointer in
        fputs(textPointer, file)
      }
      fclose(file)
    }
  }
  #endif
}

private func swiftmutJSONStringValue(_ key: String, in json: String) -> String? {
  let bytes = Array(json.utf8)
  let keyBytes = Array(("\"" + key + "\"").utf8)
  guard let keyIndex = swiftmutFind(keyBytes, in: bytes, startingAt: 0) else {
    return nil
  }

  var index = keyIndex + keyBytes.count
  swiftmutSkipJSONWhitespace(in: bytes, index: &index)
  guard index < bytes.count, bytes[index] == 58 else {
    return nil
  }
  index += 1
  swiftmutSkipJSONWhitespace(in: bytes, index: &index)
  return swiftmutParseJSONString(in: bytes, index: &index)
}

private func swiftmutJSONStringArray(_ key: String, in json: String) -> [String] {
  let bytes = Array(json.utf8)
  let keyBytes = Array(("\"" + key + "\"").utf8)
  guard let keyIndex = swiftmutFind(keyBytes, in: bytes, startingAt: 0) else {
    return []
  }

  var index = keyIndex + keyBytes.count
  swiftmutSkipJSONWhitespace(in: bytes, index: &index)
  guard index < bytes.count, bytes[index] == 58 else {
    return []
  }
  index += 1
  swiftmutSkipJSONWhitespace(in: bytes, index: &index)
  guard index < bytes.count, bytes[index] == 91 else {
    return []
  }
  index += 1

  var values: [String] = []
  while index < bytes.count {
    swiftmutSkipJSONWhitespace(in: bytes, index: &index)
    guard index < bytes.count else {
      break
    }
    if bytes[index] == 93 {
      break
    }
    if let value = swiftmutParseJSONString(in: bytes, index: &index) {
      values.append(value)
    } else {
      index += 1
    }
  }
  return values
}

private func swiftmutParseJSONString(in bytes: [UInt8], index: inout Int) -> String? {
  guard index < bytes.count, bytes[index] == 34 else {
    return nil
  }
  index += 1

  var value: [UInt8] = []
  var escaped = false
  while index < bytes.count {
    let byte = bytes[index]
    index += 1
    if escaped {
      switch byte {
      case 110:
        value.append(10)
      case 114:
        value.append(13)
      case 116:
        value.append(9)
      default:
        value.append(byte)
      }
      escaped = false
      continue
    }
    if byte == 92 {
      escaped = true
      continue
    }
    if byte == 34 {
      return String(decoding: value, as: UTF8.self)
    }
    value.append(byte)
  }
  return nil
}

private func swiftmutSkipJSONWhitespace(in bytes: [UInt8], index: inout Int) {
  while index < bytes.count {
    switch bytes[index] {
    case 32, 10, 13, 9:
      index += 1
    default:
      return
    }
  }
}

private func swiftmutFind(_ needle: [UInt8], in haystack: [UInt8], startingAt start: Int) -> Int? {
  guard !needle.isEmpty, haystack.count >= needle.count, start <= haystack.count - needle.count else {
    return nil
  }
  var index = start
  while index <= haystack.count - needle.count {
    var matched = true
    for needleIndex in 0..<needle.count {
      if haystack[index + needleIndex] != needle[needleIndex] {
        matched = false
        break
      }
    }
    if matched {
      return index
    }
    index += 1
  }
  return nil
}

private func swiftmutFormatMutantID(_ ordinal: Int) -> String {
  if ordinal < 10 {
    return "M00\(ordinal)"
  }
  if ordinal < 100 {
    return "M0\(ordinal)"
  }
  return "M\(ordinal)"
}

private func swiftmutEscapeJSON(_ value: String) -> String {
  var escaped = ""
  for character in value {
    switch character {
    case "\\":
      escaped += "\\\\"
    case "\"":
      escaped += "\\\""
    case "\n":
      escaped += "\\n"
    case "\r":
      escaped += "\\r"
    case "\t":
      escaped += "\\t"
    default:
      escaped.append(character)
    }
  }
  return escaped
}
