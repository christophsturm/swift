//===--- SwiftMutagen.swift ----------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2026 Swift Mutagen contributors
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

private enum SwiftMutagenMode {
  case discover
  case apply
  case metamutant
}

private struct SwiftMutagenConditionMutationRule {
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

private struct SwiftMutagenArithmeticMutationRule {
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

private struct SwiftMutagenContextualArithmeticMutationRule {
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

private struct SwiftMutagenReturnMutationRule {
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

private struct SwiftMutagenVoidCallMutationRule {
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

private struct SwiftMutagenSourceMutationDisplayRule {
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

private struct SwiftMutagenConfig {
  static let defaultPath = ".mutagen/session/compiler-config.json"

  let mode: SwiftMutagenMode
  let activeMutantID: String
  let mutantsPath: String
  let manifestFragmentsDirectory: String
  let compilerEventsPath: String
  let packageRoot: String
  let excludePathFragments: [String]
  let sourceFiles: [String]
  let enabledMutators: [String]
  let conditionMutationRules: [SwiftMutagenConditionMutationRule]
  let arithmeticMutationRules: [SwiftMutagenArithmeticMutationRule]
  let contextualArithmeticMutationRules: [SwiftMutagenContextualArithmeticMutationRule]
  let returnMutationRules: [SwiftMutagenReturnMutationRule]
  let voidCallMutationRules: [SwiftMutagenVoidCallMutationRule]
  let sourceMutationDisplayRules: [SwiftMutagenSourceMutationDisplayRule]

  static func load() -> SwiftMutagenConfig? {
    let configPath = swiftMutagenEnvironmentValue("SWIFT_MUTAGEN_CONFIG") ?? Self.defaultPath
    guard let json = swiftMutagenRead(configPath),
          let rawMode = swiftMutagenJSONStringValue("mode", in: json) else {
      return nil
    }

    let mode: SwiftMutagenMode
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

    guard let mutantsPath = swiftMutagenJSONStringValue("manifestPath", in: json),
          !mutantsPath.isEmpty else {
      return nil
    }

    let activeMutantID = swiftMutagenJSONStringValue("activeMutantID", in: json) ?? ""
    let manifestFragmentsDirectory = swiftMutagenJSONStringValue("manifestFragmentsDirectory", in: json) ?? ""
    let compilerEventsPath = swiftMutagenJSONStringValue("compilerEventsPath", in: json) ?? ""
    let packageRoot = swiftMutagenJSONStringValue("packageRoot", in: json) ?? ""
    let excludePaths = swiftMutagenJSONStringArray("excludePaths", in: json)
    let sourceFiles = swiftMutagenJSONStringArray("sourceFiles", in: json)
    let enabledMutators = swiftMutagenJSONStringArray("enabledMutators", in: json)
    let conditionMutationRules = swiftMutagenJSONStringArray("conditionMutationRules", in: json).compactMap {
      SwiftMutagenConditionMutationRule(wireFormat: $0)
    }
    let arithmeticMutationRules = swiftMutagenJSONStringArray("arithmeticMutationRules", in: json).compactMap {
      SwiftMutagenArithmeticMutationRule(wireFormat: $0)
    }
    let contextualArithmeticMutationRules = swiftMutagenJSONStringArray("contextualArithmeticMutationRules", in: json).compactMap {
      SwiftMutagenContextualArithmeticMutationRule(wireFormat: $0)
    }
    let returnMutationRules = swiftMutagenJSONStringArray("returnMutationRules", in: json).compactMap {
      SwiftMutagenReturnMutationRule(wireFormat: $0)
    }
    let voidCallMutationRules = swiftMutagenJSONStringArray("voidCallMutationRules", in: json).compactMap {
      SwiftMutagenVoidCallMutationRule(wireFormat: $0)
    }
    let sourceMutationDisplayRules = swiftMutagenJSONStringArray("sourceMutationDisplayRules", in: json).compactMap {
      SwiftMutagenSourceMutationDisplayRule(wireFormat: $0)
    }

    return SwiftMutagenConfig(
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

private func swiftMutagenEnvironmentValue(_ name: String) -> String? {
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

private struct SwiftMutagenMutation {
  let originalID: BuiltinInst.ID?
  let mutator: String
  let mutatedBuiltinName: String
  let sourceOriginal: String
  let sourceMutated: String
  let silOriginal: String
  let silMutated: String

  func withSource(original: String, mutated: String) -> SwiftMutagenMutation {
    SwiftMutagenMutation(
      originalID: originalID,
      mutator: mutator,
      mutatedBuiltinName: mutatedBuiltinName,
      sourceOriginal: original,
      sourceMutated: mutated,
      silOriginal: silOriginal,
      silMutated: silMutated)
  }
}

private struct SwiftMutagenCandidate {
  let id: String
  let module: String
  let function: String
  let file: String
  let line: Int
  let column: Int
  let mutation: SwiftMutagenMutation

  var jsonLine: String {
    var fields: [String] = []
    fields.append(#""id":"\#(swiftMutagenEscapeJSON(id))""#)
    fields.append(#""mutator":"\#(swiftMutagenEscapeJSON(mutation.mutator))""#)
    fields.append(#""module":"\#(swiftMutagenEscapeJSON(module))""#)
    fields.append(#""function":"\#(swiftMutagenEscapeJSON(function))""#)
    fields.append(#""file":"\#(swiftMutagenEscapeJSON(file))""#)
    fields.append(#""line":\#(line)"#)
    fields.append(#""column":\#(column)"#)
    fields.append(#""sourceOriginal":"\#(swiftMutagenEscapeJSON(mutation.sourceOriginal))""#)
    fields.append(#""sourceMutated":"\#(swiftMutagenEscapeJSON(mutation.sourceMutated))""#)
    fields.append(#""silOriginal":"\#(swiftMutagenEscapeJSON(mutation.silOriginal))""#)
    fields.append(#""silMutated":"\#(swiftMutagenEscapeJSON(mutation.silMutated))""#)
    return "{\(fields.joined(separator: ","))}\n"
  }
}

private struct SwiftMutagenConditionAlternative {
  let mutantID: String
  let alternativeIndex: UInt32
  let mutation: SwiftMutagenMutation
}

private struct SwiftMutagenConditionSite {
  let siteID: UInt64
  let runtimeFunctionName: String
  let module: String
  let function: String
  let file: String
  let line: Int
  let column: Int
  let comparison: BuiltinInst?
  let branch: CondBranchInst
  let alternatives: [SwiftMutagenConditionAlternative]
}

private struct SwiftMutagenConditionDiscoveryStats {
  var branches = 0
  var branchesWithArguments = 0
  var comparisonBranches = 0
  var genericBranches = 0
  var noMutationBranches = 0
  var mutationAlternatives = 0
  var sourceLocationMisses = 0
  var genericNonExplicitSourceLocations = 0
}

private struct SwiftMutagenConditionDiscoveryResult {
  let sites: [SwiftMutagenConditionSite]
  let stats: SwiftMutagenConditionDiscoveryStats
}

private struct SwiftMutagenReturnAlternative {
  let mutantID: String
  let alternativeIndex: UInt32
  let mutation: SwiftMutagenMutation
}

private struct SwiftMutagenArithmeticAlternative {
  let mutantID: String
  let alternativeIndex: UInt32
  let mutation: SwiftMutagenMutation
}

private struct SwiftMutagenScalarValueAlternative {
  let mutantID: String
  let alternativeIndex: UInt32
  let mutation: SwiftMutagenMutation
}

private struct SwiftMutagenValueApplyAlternative {
  let mutantID: String
  let alternativeIndex: UInt32
  let mutation: SwiftMutagenMutation
}

private struct SwiftMutagenAssignmentValueAlternative {
  let mutantID: String
  let alternativeIndex: UInt32
  let mutation: SwiftMutagenMutation
}

private struct SwiftMutagenVoidCallAlternative {
  let mutantID: String
  let alternativeIndex: UInt32
  let mutation: SwiftMutagenMutation
}

private struct SwiftMutagenReturnSite {
  let siteID: UInt64
  let runtimeFunctionName: String
  let module: String
  let function: String
  let file: String
  let line: Int
  let column: Int
  let returnInst: ReturnInst
  let alternatives: [SwiftMutagenReturnAlternative]
}

private struct SwiftMutagenReturnBranchSite {
  let siteID: UInt64
  let runtimeFunctionName: String
  let module: String
  let function: String
  let file: String
  let line: Int
  let column: Int
  let branch: BranchInst
  let value: Value
  let alternatives: [SwiftMutagenReturnAlternative]
}

private struct SwiftMutagenReturnDiscoveryStats {
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
  var nonStatementSourceLocations = 0
}

private struct SwiftMutagenReturnDiscoveryResult {
  let sites: [SwiftMutagenReturnSite]
  let stats: SwiftMutagenReturnDiscoveryStats
}

private struct SwiftMutagenReturnBranchDiscoveryStats {
  var branches = 0
  var mutationEligibleBranches = 0
  var mutationAlternatives = 0
  var sourceLocationMisses = 0
}

private struct SwiftMutagenReturnBranchDiscoveryResult {
  let sites: [SwiftMutagenReturnBranchSite]
  let stats: SwiftMutagenReturnBranchDiscoveryStats
}

private struct SwiftMutagenArithmeticSite {
  let siteID: UInt64
  let runtimeFunctionName: String
  let module: String
  let function: String
  let file: String
  let line: Int
  let column: Int
  let builtin: BuiltinInst
  let alternatives: [SwiftMutagenArithmeticAlternative]
}

private struct SwiftMutagenScalarValueSite {
  let siteID: UInt64
  let runtimeFunctionName: String
  let module: String
  let function: String
  let file: String
  let line: Int
  let column: Int
  let value: StructInst
  let alternatives: [SwiftMutagenScalarValueAlternative]
}

private struct SwiftMutagenScalarValueDiscoveryStats {
  var structInstructions = 0
  var mutationEligibleStructInstructions = 0
  var mutationAlternatives = 0
  var sourceLocationMisses = 0
}

private struct SwiftMutagenScalarValueDiscoveryResult {
  let sites: [SwiftMutagenScalarValueSite]
  let stats: SwiftMutagenScalarValueDiscoveryStats
}

private struct SwiftMutagenValueApplySite {
  let siteID: UInt64
  let runtimeFunctionName: String
  let module: String
  let function: String
  let file: String
  let line: Int
  let column: Int
  let apply: ApplyInst
  let alternatives: [SwiftMutagenValueApplyAlternative]
}

private struct SwiftMutagenValueApplyDiscoveryStats {
  var applyInstructions = 0
  var valueApplyInstructions = 0
  var mutationEligibleApplyInstructions = 0
  var mutationAlternatives = 0
  var sourceLocationMisses = 0
}

private struct SwiftMutagenValueApplyDiscoveryResult {
  let sites: [SwiftMutagenValueApplySite]
  let stats: SwiftMutagenValueApplyDiscoveryStats
}

private struct SwiftMutagenAssignmentValueSite {
  let siteID: UInt64
  let runtimeFunctionName: String
  let module: String
  let function: String
  let file: String
  let line: Int
  let column: Int
  let store: StoreInst
  let alternatives: [SwiftMutagenAssignmentValueAlternative]
}

private struct SwiftMutagenAssignmentValueDiscoveryStats {
  var storeInstructions = 0
  var mutationEligibleStoreInstructions = 0
  var mutationAlternatives = 0
  var sourceLocationMisses = 0
}

private struct SwiftMutagenAssignmentValueDiscoveryResult {
  let sites: [SwiftMutagenAssignmentValueSite]
  let stats: SwiftMutagenAssignmentValueDiscoveryStats
}

private struct SwiftMutagenVoidCallSite {
  let siteID: UInt64
  let runtimeFunctionName: String
  let module: String
  let function: String
  let file: String
  let line: Int
  let column: Int
  let apply: ApplyInst
  let alternatives: [SwiftMutagenVoidCallAlternative]
}

private struct SwiftMutagenVoidCallDiscoveryStats {
  var applyInstructions = 0
  var voidApplyInstructions = 0
  var mutationEligibleApplyInstructions = 0
  var sourceLocationMisses = 0
  var nonStatementSourceLocations = 0
}

private struct SwiftMutagenVoidCallDiscoveryResult {
  let sites: [SwiftMutagenVoidCallSite]
  let stats: SwiftMutagenVoidCallDiscoveryStats
}

private enum SwiftMutagenVoidCallSourceLocationResult {
  case found(file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)
  case nonStatement
  case missing
}

private var swiftMutagenNextOrdinal = 1
private var swiftMutagenHasTruncatedDiscoveryOutput = false

let swiftMutagen = FunctionPass(name: "swift-mutagen") {
  (function: Function, context: FunctionPassContext) in

  guard let config = SwiftMutagenConfig.load() else {
    return
  }

  let moduleName = context.currentModuleContext.name.string
  let shouldLogFunction = swiftMutagenShouldLog(function: function, moduleName: moduleName, config: config)
  let functionStartedAt = swiftMutagenClockMicroseconds()
  if shouldLogFunction {
    swiftMutagenLogEvent(
      "functionVisit",
      config: config,
      fields: [
        ("mode", swiftMutagenModeName(config.mode)),
        ("module", moduleName),
        ("function", function.name.string),
        ("location", function.location.description)
      ])
  }
  defer {
    if shouldLogFunction {
      let finishedAt = swiftMutagenClockMicroseconds()
      let durationUs = finishedAt >= functionStartedAt ? finishedAt - functionStartedAt : 0
      swiftMutagenLogEvent(
        "functionTiming",
        config: config,
        fields: [
          ("mode", swiftMutagenModeName(config.mode)),
          ("module", moduleName),
          ("function", function.name.string),
          ("durationUs", "\(durationUs)")
        ])
    }
  }

  guard swiftMutagenFunctionName(function.name.string, belongsToModule: moduleName) else {
    if shouldLogFunction {
      swiftMutagenLogEvent(
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

  if let exclusionReason = swiftMutagenExclusionReason(function: function, config: config) {
    if shouldLogFunction {
      swiftMutagenLogEvent(
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
    if swiftMutagenInstrumentMetamutantSites(
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
          for mutation in swiftMutagenReturnMutations(for: returnInst, config: config) {
            guard swiftMutagenMutatorIsEnabled(mutation.mutator, config: config) else {
              continue
            }
            guard let sourceLocation = swiftMutagenReturnSourceLocation(
              for: returnInst,
              mutation: mutation,
              config: config
            ) else {
              continue
            }

            let id = swiftMutagenFormatMutantID(swiftMutagenNextOrdinal)
            swiftMutagenNextOrdinal += 1
            let candidate = SwiftMutagenCandidate(
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
              if !swiftMutagenHasTruncatedDiscoveryOutput {
                swiftMutagenCreateParentDirectories(forFile: config.mutantsPath)
                swiftMutagenWrite("", to: config.mutantsPath, append: false)
                swiftMutagenHasTruncatedDiscoveryOutput = true
              }
              swiftMutagenWrite(candidate.jsonLine, to: config.mutantsPath, append: true)
            case .apply:
              if candidate.id == config.activeMutantID {
                swiftMutagenApplyReturn(mutation: mutation, to: returnInst, context)
                changed = true
              }
            case .metamutant:
              break
            }
          }
        }
        if let apply = instruction as? ApplyInst,
           let mutation = swiftMutagenVoidCallMutation(for: apply, config: config),
           swiftMutagenMutatorIsEnabled(mutation.mutator, config: config),
           let sourceLocation = swiftMutagenInstructionSourceLocation(
            for: apply,
            mutation: mutation,
            config: config
           ) {
          let id = swiftMutagenFormatMutantID(swiftMutagenNextOrdinal)
          swiftMutagenNextOrdinal += 1
          let candidate = SwiftMutagenCandidate(
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
            if !swiftMutagenHasTruncatedDiscoveryOutput {
              swiftMutagenCreateParentDirectories(forFile: config.mutantsPath)
              swiftMutagenWrite("", to: config.mutantsPath, append: false)
              swiftMutagenHasTruncatedDiscoveryOutput = true
            }
            swiftMutagenWrite(candidate.jsonLine, to: config.mutantsPath, append: true)
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

      for mutation in swiftMutagenMutations(for: builtin, config: config) {
        guard swiftMutagenMutatorIsEnabled(mutation.mutator, config: config) else {
          continue
        }
        guard let sourceLocation = swiftMutagenSourceLocation(
          for: builtin,
          function: function,
          moduleName: moduleName,
          mutation: mutation,
          config: config
        ) else {
          continue
        }

        let id = swiftMutagenFormatMutantID(swiftMutagenNextOrdinal)
        swiftMutagenNextOrdinal += 1

        let displayMutation = sourceLocation.sourceOriginal.isEmpty
          ? mutation
          : mutation.withSource(
            original: sourceLocation.sourceOriginal,
            mutated: sourceLocation.sourceMutated)
        let candidate = SwiftMutagenCandidate(
          id: id,
          module: moduleName,
          function: functionName,
          file: sourceLocation.file,
          line: sourceLocation.line,
          column: sourceLocation.column,
          mutation: displayMutation)

        switch config.mode {
        case .discover:
          if !swiftMutagenHasTruncatedDiscoveryOutput {
            swiftMutagenCreateParentDirectories(forFile: config.mutantsPath)
            swiftMutagenWrite("", to: config.mutantsPath, append: false)
            swiftMutagenHasTruncatedDiscoveryOutput = true
          }
          swiftMutagenWrite(candidate.jsonLine, to: config.mutantsPath, append: true)
        case .apply:
          if candidate.id == config.activeMutantID {
            swiftMutagenApply(mutation: mutation, to: builtin, context)
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

private func swiftMutagenInstrumentMetamutantSites(
  in function: Function,
  moduleName: String,
  config: SwiftMutagenConfig,
  _ context: FunctionPassContext
) -> Bool {
  let conditionDiscovery = swiftMutagenDiscoverConditionSites(
    in: function,
    moduleName: moduleName,
    config: config
  )
  let conditionSites = conditionDiscovery.sites
  let arithmeticSites = swiftMutagenDiscoverArithmeticSites(
    in: function,
    moduleName: moduleName,
    config: config
  )
  let scalarValueDiscovery = swiftMutagenDiscoverScalarValueSites(
    in: function,
    moduleName: moduleName,
    config: config
  )
  let scalarValueSites = scalarValueDiscovery.sites
  let valueApplyDiscovery = swiftMutagenDiscoverValueApplySites(
    in: function,
    moduleName: moduleName,
    config: config
  )
  let valueApplySites = valueApplyDiscovery.sites
  let assignmentValueDiscovery = swiftMutagenDiscoverAssignmentValueSites(
    in: function,
    moduleName: moduleName,
    config: config
  )
  let assignmentValueSites = assignmentValueDiscovery.sites
  let returnDiscovery = swiftMutagenDiscoverReturnSites(
    in: function,
    moduleName: moduleName,
    config: config
  )
  let returnSites = returnDiscovery.sites
  let returnBranchDiscovery = swiftMutagenDiscoverReturnBranchSites(
    in: function,
    moduleName: moduleName,
    config: config
  )
  let returnBranchSites = returnBranchDiscovery.sites
  let voidCallDiscovery = swiftMutagenDiscoverVoidCallSites(
    in: function,
    moduleName: moduleName,
    config: config
  )
  let voidCallSites = voidCallDiscovery.sites
  swiftMutagenLogEvent(
    "metamutantDiscovery",
    config: config,
    fields: [
      ("module", moduleName),
      ("function", function.name.string),
      ("conditionBranches", "\(swiftMutagenConditionBranchCount(in: function))"),
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
    if swiftMutagenInjectArithmeticSite(site, context) {
      injectedSiteJSON.append(swiftMutagenArithmeticSiteJSON(site))
      injectedArithmeticSites += 1
      changed = true
    }
  }
  for site in scalarValueSites {
    if swiftMutagenInjectScalarValueSite(site, context) {
      injectedSiteJSON.append(swiftMutagenScalarValueSiteJSON(site))
      injectedScalarValueSites += 1
      changed = true
    }
  }
  for site in valueApplySites {
    if swiftMutagenInjectValueApplySite(site, context) {
      injectedSiteJSON.append(swiftMutagenValueApplySiteJSON(site))
      injectedValueApplySites += 1
      changed = true
    }
  }
  for site in assignmentValueSites {
    if swiftMutagenInjectAssignmentValueSite(site, context) {
      injectedSiteJSON.append(swiftMutagenAssignmentValueSiteJSON(site))
      injectedAssignmentValueSites += 1
      changed = true
    }
  }
  for site in conditionSites {
    if swiftMutagenInjectConditionSite(site, context) {
      injectedSiteJSON.append(swiftMutagenConditionSiteJSON(site))
      injectedConditionSites += 1
      changed = true
    }
  }
  for site in returnSites {
    if swiftMutagenInjectReturnSite(site, context) {
      injectedSiteJSON.append(swiftMutagenReturnSiteJSON(site))
      injectedReturnSites += 1
      changed = true
    }
  }
  for site in returnBranchSites {
    if swiftMutagenInjectReturnBranchSite(site, context) {
      injectedSiteJSON.append(swiftMutagenReturnBranchSiteJSON(site))
      injectedReturnBranchSites += 1
      changed = true
    }
  }
  for site in voidCallSites {
    if swiftMutagenInjectVoidCallSite(site, context) {
      injectedSiteJSON.append(swiftMutagenVoidCallSiteJSON(site))
      injectedVoidCallSites += 1
      changed = true
    }
  }
  let runtimeVisitAvailable = swiftMutagenAnyRuntimeVisitFunctionAvailable(
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
  swiftMutagenLogEvent(
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
    swiftMutagenWriteMetamutantFragment(
      injectedSiteJSON,
      moduleName: moduleName,
      functionName: function.name.string,
      config: config
    )
  }
  return changed
}

private func swiftMutagenDiscoverVoidCallSites(
  in function: Function,
  moduleName: String,
  config: SwiftMutagenConfig
) -> SwiftMutagenVoidCallDiscoveryResult {
  var sites: [SwiftMutagenVoidCallSite] = []
  var stats = SwiftMutagenVoidCallDiscoveryStats()
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
      guard let mutation = swiftMutagenVoidCallMutation(for: apply, config: config),
            swiftMutagenMutatorIsEnabled(mutation.mutator, config: config) else {
        continue
      }
      stats.mutationEligibleApplyInstructions += 1
      let location: (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)
      switch swiftMutagenVoidCallSourceLocation(
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
      let siteID = swiftMutagenStableSiteID(
        packageRoot: config.packageRoot,
        module: moduleName,
        file: location.file,
        line: location.line,
        column: location.column,
        function: functionName,
        siteKind: "voidCall",
        localOrdinal: localOrdinal
      )
      sites.append(SwiftMutagenVoidCallSite(
        siteID: siteID,
        runtimeFunctionName: swiftMutagenRuntimeVisitThunkName(file: location.file, config: config),
        module: moduleName,
        function: functionName,
        file: location.file,
        line: location.line,
        column: location.column,
        apply: apply,
        alternatives: [
          SwiftMutagenVoidCallAlternative(
            mutantID: "local-void-call-\(localOrdinal)-1",
            alternativeIndex: 1,
            mutation: displayMutation
          )
        ]
      ))
      localOrdinal += 1
    }
  }

  return SwiftMutagenVoidCallDiscoveryResult(sites: sites, stats: stats)
}

private func swiftMutagenDiscoverConditionSites(
  in function: Function,
  moduleName: String,
  config: SwiftMutagenConfig
) -> SwiftMutagenConditionDiscoveryResult {
  var sites: [SwiftMutagenConditionSite] = []
  var stats = SwiftMutagenConditionDiscoveryStats()
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
    let mutations: [SwiftMutagenMutation]
    if let branchComparison = branch.condition as? BuiltinInst,
       swiftMutagenIsComparisonBuiltin(branchComparison) {
      stats.comparisonBranches += 1
      comparison = branchComparison
      mutations = swiftMutagenConditionSiteMutations(for: branchComparison, config: config)
    } else {
      stats.genericBranches += 1
      mutations = swiftMutagenGenericConditionSiteMutations(config: config)
    }
    guard !mutations.isEmpty else {
      stats.noMutationBranches += 1
      continue
    }
    stats.mutationAlternatives += mutations.count

    var alternatives: [SwiftMutagenConditionAlternative] = []
    var sourceLocation: (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)?
    for mutation in mutations {
      let location: (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)?
      if let comparison {
        location = swiftMutagenSourceLocation(
          for: comparison,
          function: function,
          moduleName: moduleName,
          mutation: mutation,
          config: config)
      } else {
        location = swiftMutagenBranchSourceLocation(
          for: branch,
          mutation: mutation,
          config: config)
        if let location,
           !swiftMutagenGenericConditionSourceIsExplicit(file: location.file, line: location.line, config: config) {
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
      }
      let displayMutation = mutation.withSource(
        original: location.sourceOriginal,
        mutated: location.sourceMutated
      )
      alternatives.append(SwiftMutagenConditionAlternative(
        mutantID: "local-\(localOrdinal)-\(alternatives.count + 1)",
        alternativeIndex: UInt32(alternatives.count + 1),
        mutation: displayMutation
      ))
    }

    guard let location = sourceLocation, !alternatives.isEmpty else {
      continue
    }

    let siteID = swiftMutagenStableSiteID(
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

    sites.append(SwiftMutagenConditionSite(
      siteID: siteID,
      runtimeFunctionName: swiftMutagenRuntimeVisitThunkName(file: location.file, config: config),
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

  return SwiftMutagenConditionDiscoveryResult(sites: sites, stats: stats)
}

private func swiftMutagenDiscoverReturnSites(
  in function: Function,
  moduleName: String,
  config: SwiftMutagenConfig
) -> SwiftMutagenReturnDiscoveryResult {
  var sites: [SwiftMutagenReturnSite] = []
  var stats = SwiftMutagenReturnDiscoveryStats()
  var localOrdinal = 1
  let functionName = function.name.string
  guard !functionName.hasSuffix("TW") else {
    return SwiftMutagenReturnDiscoveryResult(sites: [], stats: stats)
  }

  for block in function.blocks {
    guard let returnInst = block.terminator as? ReturnInst else {
      continue
    }
    stats.terminators += 1
    let returnType = returnInst.returnedValue.type
    swiftMutagenRecordReturnType(returnType, in: function, stats: &stats)

    let mutations = swiftMutagenMetamutantReturnMutations(for: returnInst, config: config)
    guard !mutations.isEmpty else {
      continue
    }
    stats.mutationEligibleTerminators += 1
    stats.mutationAlternatives += mutations.count

    var alternatives: [SwiftMutagenReturnAlternative] = []
    var sourceLocation: (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)?
    for mutation in mutations {
      guard let location = swiftMutagenReturnSourceLocation(
        for: returnInst,
        mutation: mutation,
        config: config
      ) else {
        stats.missingSourceLocations += 1
        swiftMutagenRecordReturnSourceLocationMiss(returnType, in: function, stats: &stats)
        continue
      }
      if location.sourceOriginal == "return",
         !swiftMutagenReturnSourceLooksLikeStatement(file: location.file, line: location.line, config: config) {
        stats.nonStatementSourceLocations += 1
        continue
      }
      if sourceLocation == nil {
        sourceLocation = location
      }
      let displayMutation = mutation.withSource(
        original: location.sourceOriginal,
        mutated: location.sourceMutated
      )
      alternatives.append(SwiftMutagenReturnAlternative(
        mutantID: "local-return-\(localOrdinal)-\(alternatives.count + 1)",
        alternativeIndex: UInt32(alternatives.count + 1),
        mutation: displayMutation
      ))
    }

    guard let location = sourceLocation, !alternatives.isEmpty else {
      continue
    }

    let siteID = swiftMutagenStableSiteID(
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

    sites.append(SwiftMutagenReturnSite(
      siteID: siteID,
      runtimeFunctionName: swiftMutagenRuntimeVisitThunkName(file: location.file, config: config),
      module: moduleName,
      function: functionName,
      file: location.file,
      line: location.line,
      column: location.column,
      returnInst: returnInst,
      alternatives: alternatives
    ))
  }

  return SwiftMutagenReturnDiscoveryResult(sites: sites, stats: stats)
}

private func swiftMutagenDiscoverReturnBranchSites(
  in function: Function,
  moduleName: String,
  config: SwiftMutagenConfig
) -> SwiftMutagenReturnBranchDiscoveryResult {
  var sites: [SwiftMutagenReturnBranchSite] = []
  var stats = SwiftMutagenReturnBranchDiscoveryStats()
  var localOrdinal = 1
  let functionName = function.name.string
  guard !functionName.hasSuffix("TW") else {
    return SwiftMutagenReturnBranchDiscoveryResult(sites: [], stats: stats)
  }

  for block in function.blocks {
    guard let branch = block.terminator as? BranchInst,
          swiftMutagenBranchFeedsReturnValue(branch),
          let value = branch.operands.first?.value else {
      continue
    }
    stats.branches += 1
    let mutations = swiftMutagenReturnBranchMutations(for: branch, config: config)
    guard !mutations.isEmpty else {
      continue
    }
    stats.mutationEligibleBranches += 1
    stats.mutationAlternatives += mutations.count

    var alternatives: [SwiftMutagenReturnAlternative] = []
    var sourceLocation: (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)?
    for mutation in mutations {
      guard let location = swiftMutagenReturnBranchSourceLocation(
        for: branch,
        mutation: mutation,
        config: config
      ) else {
        stats.sourceLocationMisses += 1
        continue
      }
      if sourceLocation == nil {
        sourceLocation = location
      }
      let displayMutation = mutation.withSource(
        original: location.sourceOriginal,
        mutated: location.sourceMutated
      )
      alternatives.append(SwiftMutagenReturnAlternative(
        mutantID: "local-return-branch-\(localOrdinal)-\(alternatives.count + 1)",
        alternativeIndex: UInt32(alternatives.count + 1),
        mutation: displayMutation
      ))
    }

    guard let location = sourceLocation, !alternatives.isEmpty else {
      continue
    }

    let siteID = swiftMutagenStableSiteID(
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

    sites.append(SwiftMutagenReturnBranchSite(
      siteID: siteID,
      runtimeFunctionName: swiftMutagenRuntimeVisitThunkName(file: location.file, config: config),
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

  return SwiftMutagenReturnBranchDiscoveryResult(sites: sites, stats: stats)
}

private func swiftMutagenBranchFeedsReturnValue(_ branch: BranchInst) -> Bool {
  guard branch.operands.count == 1,
        branch.targetBlock.arguments.count == 1,
        let returnInst = branch.targetBlock.terminator as? ReturnInst else {
    return false
  }
  return returnInst.returnedValue == branch.targetBlock.arguments[0]
}

private func swiftMutagenDiscoverArithmeticSites(
  in function: Function,
  moduleName: String,
  config: SwiftMutagenConfig
) -> [SwiftMutagenArithmeticSite] {
  var sites: [SwiftMutagenArithmeticSite] = []
  var localOrdinal = 1
  let functionName = function.name.string

  for block in function.blocks {
    for instruction in block.instructions {
      guard let builtin = instruction as? BuiltinInst else {
        continue
      }
      let mutations = swiftMutagenArithmeticSiteMutations(for: builtin, config: config)
      guard !mutations.isEmpty else {
        continue
      }

      var alternatives: [SwiftMutagenArithmeticAlternative] = []
      var sourceLocation: (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)?
      for mutation in mutations {
        guard let location = swiftMutagenSourceLocation(
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
        }
        let displayMutation = mutation.withSource(
          original: location.sourceOriginal,
          mutated: location.sourceMutated
        )
        alternatives.append(SwiftMutagenArithmeticAlternative(
          mutantID: "local-arithmetic-\(localOrdinal)-\(alternatives.count + 1)",
          alternativeIndex: UInt32(alternatives.count + 1),
          mutation: displayMutation
        ))
      }

      guard let location = sourceLocation, !alternatives.isEmpty else {
        continue
      }

      let siteID = swiftMutagenStableSiteID(
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

      sites.append(SwiftMutagenArithmeticSite(
        siteID: siteID,
        runtimeFunctionName: swiftMutagenRuntimeVisitThunkName(file: location.file, config: config),
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

private func swiftMutagenDiscoverScalarValueSites(
  in function: Function,
  moduleName: String,
  config: SwiftMutagenConfig
) -> SwiftMutagenScalarValueDiscoveryResult {
  var sites: [SwiftMutagenScalarValueSite] = []
  var stats = SwiftMutagenScalarValueDiscoveryStats()
  var localOrdinal = 1
  let functionName = function.name.string

  for block in function.blocks {
    for instruction in block.instructions {
      guard let structInst = instruction as? StructInst else {
        continue
      }
      stats.structInstructions += 1

      let mutations = swiftMutagenScalarValueMutations(for: structInst, config: config)
      guard !mutations.isEmpty else {
        continue
      }
      stats.mutationEligibleStructInstructions += 1
      stats.mutationAlternatives += mutations.count

      var alternatives: [SwiftMutagenScalarValueAlternative] = []
      var sourceLocation: (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)?
      for mutation in mutations {
        guard let location = swiftMutagenScalarValueSourceLocation(
          for: structInst,
          mutation: mutation,
          config: config
        ) else {
          stats.sourceLocationMisses += 1
          continue
        }
        if sourceLocation == nil {
          sourceLocation = location
        }
        let displayMutation = mutation.withSource(
          original: location.sourceOriginal,
          mutated: location.sourceMutated
        )
        alternatives.append(SwiftMutagenScalarValueAlternative(
          mutantID: "local-scalar-value-\(localOrdinal)-\(alternatives.count + 1)",
          alternativeIndex: UInt32(alternatives.count + 1),
          mutation: displayMutation
        ))
      }

      guard let location = sourceLocation, !alternatives.isEmpty else {
        continue
      }

      let siteID = swiftMutagenStableSiteID(
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

      sites.append(SwiftMutagenScalarValueSite(
        siteID: siteID,
        runtimeFunctionName: swiftMutagenRuntimeVisitThunkName(file: location.file, config: config),
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

  return SwiftMutagenScalarValueDiscoveryResult(sites: sites, stats: stats)
}

private func swiftMutagenDiscoverValueApplySites(
  in function: Function,
  moduleName: String,
  config: SwiftMutagenConfig
) -> SwiftMutagenValueApplyDiscoveryResult {
  var sites: [SwiftMutagenValueApplySite] = []
  var stats = SwiftMutagenValueApplyDiscoveryStats()
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

      let mutations = swiftMutagenValueReplacementMutations(
        for: apply,
        valueType: apply.type,
        config: config
      )
      guard !mutations.isEmpty else {
        continue
      }
      stats.mutationEligibleApplyInstructions += 1
      stats.mutationAlternatives += mutations.count

      var alternatives: [SwiftMutagenValueApplyAlternative] = []
      var sourceLocation: (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)?
      for mutation in mutations {
        guard let location = swiftMutagenValueApplySourceLocation(
          for: apply,
          mutation: mutation,
          config: config
        ) else {
          stats.sourceLocationMisses += 1
          continue
        }
        if sourceLocation == nil {
          sourceLocation = location
        }
        let displayMutation = mutation.withSource(
          original: location.sourceOriginal,
          mutated: location.sourceMutated
        )
        alternatives.append(SwiftMutagenValueApplyAlternative(
          mutantID: "local-value-apply-\(localOrdinal)-\(alternatives.count + 1)",
          alternativeIndex: UInt32(alternatives.count + 1),
          mutation: displayMutation
        ))
      }

      guard let location = sourceLocation, !alternatives.isEmpty else {
        continue
      }

      let siteID = swiftMutagenStableSiteID(
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

      sites.append(SwiftMutagenValueApplySite(
        siteID: siteID,
        runtimeFunctionName: swiftMutagenRuntimeVisitThunkName(file: location.file, config: config),
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

  return SwiftMutagenValueApplyDiscoveryResult(sites: sites, stats: stats)
}

private func swiftMutagenDiscoverAssignmentValueSites(
  in function: Function,
  moduleName: String,
  config: SwiftMutagenConfig
) -> SwiftMutagenAssignmentValueDiscoveryResult {
  var sites: [SwiftMutagenAssignmentValueSite] = []
  var stats = SwiftMutagenAssignmentValueDiscoveryStats()
  var localOrdinal = 1
  let functionName = function.name.string

  for block in function.blocks {
    for instruction in block.instructions {
      guard let store = instruction as? StoreInst else {
        continue
      }
      stats.storeInstructions += 1
      guard swiftMutagenAssignmentStoreIsEligible(store) else {
        continue
      }

      let mutations = swiftMutagenAssignmentValueMutations(for: store, config: config)
      guard !mutations.isEmpty else {
        continue
      }
      stats.mutationEligibleStoreInstructions += 1
      stats.mutationAlternatives += mutations.count

      var alternatives: [SwiftMutagenAssignmentValueAlternative] = []
      var sourceLocation: (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)?
      for mutation in mutations {
        guard let location = swiftMutagenAssignmentValueSourceLocation(
          for: store,
          mutation: mutation,
          config: config
        ) else {
          stats.sourceLocationMisses += 1
          continue
        }
        if sourceLocation == nil {
          sourceLocation = location
        }
        let displayMutation = mutation.withSource(
          original: location.sourceOriginal,
          mutated: location.sourceMutated
        )
        alternatives.append(SwiftMutagenAssignmentValueAlternative(
          mutantID: "local-assignment-value-\(localOrdinal)-\(alternatives.count + 1)",
          alternativeIndex: UInt32(alternatives.count + 1),
          mutation: displayMutation
        ))
      }

      guard let location = sourceLocation, !alternatives.isEmpty else {
        continue
      }

      let siteID = swiftMutagenStableSiteID(
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

      sites.append(SwiftMutagenAssignmentValueSite(
        siteID: siteID,
        runtimeFunctionName: swiftMutagenRuntimeVisitThunkName(file: location.file, config: config),
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

  return SwiftMutagenAssignmentValueDiscoveryResult(sites: sites, stats: stats)
}

private func swiftMutagenMetamutantReturnMutations(
  for returnInst: ReturnInst,
  config: SwiftMutagenConfig
) -> [SwiftMutagenMutation] {
  swiftMutagenReturnMutations(for: returnInst, config: config).filter { mutation in
    switch mutation.mutatedBuiltinName {
    case "return_false", "return_true", "return_nil", "return_zero", "return_empty_string",
         "return_empty_array", "return_empty_dictionary", "return_empty_set":
      return true
    default:
      return false
    }
  }
}

private func swiftMutagenScalarValueMutations(
  for structInst: StructInst,
  config: SwiftMutagenConfig
) -> [SwiftMutagenMutation] {
  let valueType = structInst.type
  var mutations: [SwiftMutagenMutation] = []

  if swiftMutagenIsBoolType(valueType, in: structInst.parentFunction) {
    let literal = swiftMutagenBoolLiteralValue(structInst)
    if literal != false,
       let rule = swiftMutagenFirstReturnRule(context: "boolToFalse", config: config) {
      mutations.append(swiftMutagenReturnMutation(rule, silOriginal: valueType.description))
    }
    if literal != true,
       let rule = swiftMutagenFirstReturnRule(context: "boolToTrue", config: config) {
      mutations.append(swiftMutagenReturnMutation(rule, silOriginal: valueType.description))
    }
    return mutations
  }

  if swiftMutagenIsIntegerStructType(valueType, in: structInst.parentFunction),
     swiftMutagenIntegerStructLiteralValue(structInst) != 0,
     let rule = swiftMutagenFirstReturnRule(context: "integerToZero", config: config) {
    mutations.append(swiftMutagenReturnMutation(rule, silOriginal: valueType.description))
  }

  return mutations
}

private func swiftMutagenValueReplacementMutations(
  for apply: ApplyInst,
  valueType: Type,
  config: SwiftMutagenConfig
) -> [SwiftMutagenMutation] {
  swiftMutagenValueReplacementMutations(
    valueType: valueType,
    function: apply.parentFunction,
    config: config
  )
}

private func swiftMutagenReturnBranchMutations(
  for branch: BranchInst,
  config: SwiftMutagenConfig
) -> [SwiftMutagenMutation] {
  guard swiftMutagenBranchFeedsReturnValue(branch),
        let value = branch.operands.first?.value,
        value.type.isTrivial(in: branch.parentFunction) else {
    return []
  }
  if let structInst = value.definingInstruction as? StructInst,
     !swiftMutagenScalarValueMutations(for: structInst, config: config).isEmpty {
    return []
  }
  return swiftMutagenValueReplacementMutations(
    valueType: value.type,
    function: branch.parentFunction,
    config: config
  )
}

private func swiftMutagenAssignmentValueMutations(
  for store: StoreInst,
  config: SwiftMutagenConfig
) -> [SwiftMutagenMutation] {
  guard swiftMutagenCanDispatchAssignmentValue(store) else {
    return []
  }
  return swiftMutagenValueReplacementMutations(
    valueType: store.source.type,
    function: store.parentFunction,
    config: config
  )
}

private func swiftMutagenCanDispatchAssignmentValue(_ store: StoreInst) -> Bool {
  store.source.type.isTrivial(in: store.parentFunction) || store.source.ownership == .owned
}

private func swiftMutagenAssignmentStoreIsEligible(_ store: StoreInst) -> Bool {
  guard !store.source.type.isAddress else {
    return false
  }
  guard let definingInstruction = store.source.definingInstruction else {
    return true
  }
  switch definingInstruction {
  case is StructInst, is BuiltinInst, is ApplyInst:
    return false
  default:
    return true
  }
}

private func swiftMutagenValueReplacementMutations(
  valueType: Type,
  function: Function,
  config: SwiftMutagenConfig
) -> [SwiftMutagenMutation] {
  var mutations: [SwiftMutagenMutation] = []

  if swiftMutagenIsBoolType(valueType, in: function) {
    if let rule = swiftMutagenFirstReturnRule(context: "boolToFalse", config: config) {
      mutations.append(swiftMutagenReturnMutation(rule, silOriginal: valueType.description))
    }
    if let rule = swiftMutagenFirstReturnRule(context: "boolToTrue", config: config) {
      mutations.append(swiftMutagenReturnMutation(rule, silOriginal: valueType.description))
    }
    return mutations
  }

  if valueType.isOptional,
     let rule = swiftMutagenFirstReturnRule(context: "optionalToNil", config: config) {
    mutations.append(swiftMutagenReturnMutation(rule, silOriginal: valueType.description))
    return mutations
  }

  if swiftMutagenIsIntegerStructType(valueType, in: function),
     let rule = swiftMutagenFirstReturnRule(context: "integerToZero", config: config) {
    mutations.append(swiftMutagenReturnMutation(rule, silOriginal: valueType.description))
  }

  if swiftMutagenIsStringType(valueType),
     let rule = swiftMutagenFirstReturnRule(context: "stringToEmpty", config: config) {
    mutations.append(swiftMutagenReturnMutation(rule, silOriginal: valueType.description))
  }

  return mutations
}

private func swiftMutagenConditionBranchCount(in function: Function) -> Int {
  var count = 0
  for block in function.blocks {
    if block.terminator is CondBranchInst {
      count += 1
    }
  }
  return count
}

private func swiftMutagenConditionSiteMutations(
  for builtin: BuiltinInst,
  config: SwiftMutagenConfig
) -> [SwiftMutagenMutation] {
  swiftMutagenConditionMutations(for: builtin, config: config, includeGenericComparisonRules: true)
}

private func swiftMutagenGenericConditionSiteMutations(
  config: SwiftMutagenConfig
) -> [SwiftMutagenMutation] {
  var mutations: [SwiftMutagenMutation] = []
  for rule in config.conditionMutationRules where rule.builtinID == "COMPARISON" {
    guard swiftMutagenMutatorIsEnabled(rule.mutator, config: config) else {
      continue
    }
    mutations.append(SwiftMutagenMutation(
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

private func swiftMutagenConditionMutations(
  for builtin: BuiltinInst,
  config: SwiftMutagenConfig,
  includeGenericComparisonRules: Bool
) -> [SwiftMutagenMutation] {
  guard let builtinID = swiftMutagenComparisonBuiltinIDName(builtin) else {
    return []
  }

  var mutations: [SwiftMutagenMutation] = []
  for rule in config.conditionMutationRules {
    let appliesToBuiltin = rule.builtinID == builtinID
      || (includeGenericComparisonRules && rule.builtinID == "COMPARISON")
    guard appliesToBuiltin, swiftMutagenMutatorIsEnabled(rule.mutator, config: config) else {
      continue
    }
    mutations.append(SwiftMutagenMutation(
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

private func swiftMutagenArithmeticSiteMutations(
  for builtin: BuiltinInst,
  config: SwiftMutagenConfig
) -> [SwiftMutagenMutation] {
  var mutations: [SwiftMutagenMutation] = []

  switch builtin.id {
  case .SAddOver:
    if let rule = swiftMutagenContextualArithmeticRule(for: builtin, builtinID: "SAddOver", config: config),
       swiftMutagenMutatorIsEnabled(rule.mutator, config: config) {
      mutations.append(swiftMutagenContextualArithmeticMutation(rule, for: builtin))
    }
  case .SSubOver:
    if let rule = swiftMutagenContextualArithmeticRule(for: builtin, builtinID: "SSubOver", config: config),
       swiftMutagenMutatorIsEnabled(rule.mutator, config: config) {
      mutations.append(swiftMutagenContextualArithmeticMutation(rule, for: builtin))
    }
  default:
    break
  }

  if let builtinID = swiftMutagenArithmeticBuiltinIDName(builtin) {
    for rule in config.arithmeticMutationRules where rule.builtinID == builtinID {
      guard swiftMutagenMutatorIsEnabled("MATH", config: config) else {
        continue
      }
      mutations.append(swiftMutagenBinaryMutation(
        builtin,
        mutator: "MATH",
        mutatedBuiltinName: rule.mutatedBuiltinName,
        sourceOriginal: rule.sourceOriginal,
        sourceMutated: rule.sourceMutated))
    }
  }

  return mutations
}

private func swiftMutagenComparisonBuiltinIDName(_ builtin: BuiltinInst) -> String? {
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

private func swiftMutagenIsComparisonBuiltin(_ builtin: BuiltinInst) -> Bool {
  switch builtin.id {
  case .ICMP_EQ, .ICMP_NE,
       .ICMP_SGE, .ICMP_SGT, .ICMP_SLE, .ICMP_SLT,
       .ICMP_UGE, .ICMP_UGT, .ICMP_ULE, .ICMP_ULT:
    return true
  default:
    return false
  }
}

private func swiftMutagenInjectConditionSite(
  _ site: SwiftMutagenConditionSite,
  _ context: FunctionPassContext
) -> Bool {
  guard let visitFunction = swiftMutagenRuntimeVisitFunction(named: site.runtimeFunctionName, context),
        let siteID = swiftMutagenMakeRuntimeSiteID(
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
  guard let rawChoice = swiftMutagenRuntimeChoiceRawValue(
    choice,
    builder: dispatchBuilder,
    function: function
  ) else {
    return false
  }

  for (index, alternative) in site.alternatives.enumerated() {
    let builder = Builder(atEndOf: alternativeBlocks[index], location: site.branch.location, context)
    guard let mutatedCondition = swiftMutagenMakeConditionAlternative(
      alternative.mutation,
      comparison: site.comparison,
      originalCondition: originalCondition,
      builder: builder
    ) else {
      return false
    }
    swiftMutagenCreateConditionBranch(
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
  swiftMutagenCreateConditionBranch(
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

private func swiftMutagenInjectReturnSite(
  _ site: SwiftMutagenReturnSite,
  _ context: FunctionPassContext
) -> Bool {
  guard let visitFunction = swiftMutagenRuntimeVisitFunction(named: site.runtimeFunctionName, context),
        let siteID = swiftMutagenMakeRuntimeSiteID(
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
    swiftMutagenCanMakeReturnAlternative(
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
  guard let rawChoice = swiftMutagenRuntimeChoiceRawValue(
    choice,
    builder: dispatchBuilder,
    function: function
  ) else {
    return false
  }

  for (index, alternative) in site.alternatives.enumerated() {
    let builder = Builder(atEndOf: alternativeBlocks[index], location: site.returnInst.location, context)
    guard let replacement = swiftMutagenMakeReturnAlternative(
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

private func swiftMutagenInjectReturnBranchSite(
  _ site: SwiftMutagenReturnBranchSite,
  _ context: FunctionPassContext
) -> Bool {
  guard let visitFunction = swiftMutagenRuntimeVisitFunction(named: site.runtimeFunctionName, context),
        let siteID = swiftMutagenMakeRuntimeSiteID(
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
          swiftMutagenCanMakeReturnAlternative(
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
  guard let rawChoice = swiftMutagenRuntimeChoiceRawValue(
    choice,
    builder: dispatchBuilder,
    function: function
  ) else {
    return false
  }

  for (index, alternative) in site.alternatives.enumerated() {
    let builder = Builder(atEndOf: alternativeBlocks[index], location: site.branch.location, context)
    guard let replacement = swiftMutagenMakeReturnAlternative(
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

private func swiftMutagenInjectArithmeticSite(
  _ site: SwiftMutagenArithmeticSite,
  _ context: FunctionPassContext
) -> Bool {
  guard let visitFunction = swiftMutagenRuntimeVisitFunction(named: site.runtimeFunctionName, context),
        let siteID = swiftMutagenMakeRuntimeSiteID(
          site.siteID,
          visitFunction: visitFunction,
          insertionPoint: site.builtin,
          context
        ) else {
    return false
  }
  guard let firstArgument = site.builtin.arguments.first,
        let originalBuiltinName = swiftMutagenBuiltinFunctionName(site.builtin) else {
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
  guard let rawChoice = swiftMutagenRuntimeChoiceRawValue(
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

private func swiftMutagenInjectScalarValueSite(
  _ site: SwiftMutagenScalarValueSite,
  _ context: FunctionPassContext
) -> Bool {
  guard let visitFunction = swiftMutagenRuntimeVisitFunction(named: site.runtimeFunctionName, context),
        let siteID = swiftMutagenMakeRuntimeSiteID(
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
    swiftMutagenCanMakeReturnAlternative($0.mutation, returnType: valueType, in: function, context)
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
  guard let rawChoice = swiftMutagenRuntimeChoiceRawValue(
    choice,
    builder: dispatchBuilder,
    function: function
  ) else {
    return false
  }

  for (index, alternative) in site.alternatives.enumerated() {
    let builder = Builder(atEndOf: alternativeBlocks[index], location: site.value.location, context)
    guard let replacement = swiftMutagenMakeReturnAlternative(
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

private func swiftMutagenInjectValueApplySite(
  _ site: SwiftMutagenValueApplySite,
  _ context: FunctionPassContext
) -> Bool {
  guard let visitFunction = swiftMutagenRuntimeVisitFunction(named: site.runtimeFunctionName, context),
        let siteID = swiftMutagenMakeRuntimeSiteID(
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
    swiftMutagenCanMakeReturnAlternative($0.mutation, returnType: valueType, in: function, context)
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
  guard let rawChoice = swiftMutagenRuntimeChoiceRawValue(
    choice,
    builder: dispatchBuilder,
    function: function
  ) else {
    return false
  }

  for (index, alternative) in site.alternatives.enumerated() {
    let builder = Builder(atEndOf: alternativeBlocks[index], location: site.apply.location, context)
    guard let replacement = swiftMutagenMakeReturnAlternative(
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

private func swiftMutagenInjectAssignmentValueSite(
  _ site: SwiftMutagenAssignmentValueSite,
  _ context: FunctionPassContext
) -> Bool {
  guard let visitFunction = swiftMutagenRuntimeVisitFunction(named: site.runtimeFunctionName, context),
        let siteID = swiftMutagenMakeRuntimeSiteID(
          site.siteID,
          visitFunction: visitFunction,
          insertionPoint: site.store,
          context
        ) else {
    return false
  }

  let valueType = site.store.source.type
  let function = site.store.parentFunction
  guard swiftMutagenCanDispatchAssignmentValue(site.store),
        site.alternatives.allSatisfy({
          swiftMutagenCanMakeReturnAlternative(
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
  guard let rawChoice = swiftMutagenRuntimeChoiceRawValue(
    choice,
    builder: dispatchBuilder,
    function: function
  ) else {
    return false
  }

  for (index, alternative) in site.alternatives.enumerated() {
    let builder = Builder(atEndOf: alternativeBlocks[index], location: site.store.location, context)
    guard let replacement = swiftMutagenMakeReturnAlternative(
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

private func swiftMutagenInjectVoidCallSite(
  _ site: SwiftMutagenVoidCallSite,
  _ context: FunctionPassContext
) -> Bool {
  guard let visitFunction = swiftMutagenRuntimeVisitFunction(named: site.runtimeFunctionName, context),
        let siteID = swiftMutagenMakeRuntimeSiteID(
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
  guard let rawChoice = swiftMutagenRuntimeChoiceRawValue(
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

private func swiftMutagenRuntimeVisitFunction(_ context: FunctionPassContext) -> Function? {
  context.lookupFunction(name: "__swift_mutagen_visit")
    ?? context.lookupFunction(name: "@__swift_mutagen_visit")
    ?? context.loadFunction(name: "__swift_mutagen_visit", loadCalleesRecursively: false)
    ?? context.loadFunction(name: "@__swift_mutagen_visit", loadCalleesRecursively: false)
}

private func swiftMutagenRuntimeVisitFunction(
  named functionName: String,
  _ context: FunctionPassContext
) -> Function? {
  context.lookupFunction(name: functionName)
    ?? context.lookupFunction(name: "@\(functionName)")
    ?? swiftMutagenRuntimeVisitFunction(context)
}

private func swiftMutagenAnyRuntimeVisitFunctionAvailable(
  conditionSites: [SwiftMutagenConditionSite],
  arithmeticSites: [SwiftMutagenArithmeticSite],
  scalarValueSites: [SwiftMutagenScalarValueSite],
  valueApplySites: [SwiftMutagenValueApplySite],
  assignmentValueSites: [SwiftMutagenAssignmentValueSite],
  returnSites: [SwiftMutagenReturnSite],
  returnBranchSites: [SwiftMutagenReturnBranchSite],
  voidCallSites: [SwiftMutagenVoidCallSite],
  _ context: FunctionPassContext
) -> Bool {
  for site in conditionSites where swiftMutagenRuntimeVisitFunction(named: site.runtimeFunctionName, context) != nil {
    return true
  }
  for site in arithmeticSites where swiftMutagenRuntimeVisitFunction(named: site.runtimeFunctionName, context) != nil {
    return true
  }
  for site in scalarValueSites where swiftMutagenRuntimeVisitFunction(named: site.runtimeFunctionName, context) != nil {
    return true
  }
  for site in valueApplySites where swiftMutagenRuntimeVisitFunction(named: site.runtimeFunctionName, context) != nil {
    return true
  }
  for site in assignmentValueSites where swiftMutagenRuntimeVisitFunction(named: site.runtimeFunctionName, context) != nil {
    return true
  }
  for site in returnSites where swiftMutagenRuntimeVisitFunction(named: site.runtimeFunctionName, context) != nil {
    return true
  }
  for site in returnBranchSites where swiftMutagenRuntimeVisitFunction(named: site.runtimeFunctionName, context) != nil {
    return true
  }
  for site in voidCallSites where swiftMutagenRuntimeVisitFunction(named: site.runtimeFunctionName, context) != nil {
    return true
  }
  return swiftMutagenRuntimeVisitFunction(context) != nil
}

private func swiftMutagenRuntimeVisitThunkName(file: String, config: SwiftMutagenConfig) -> String {
  let absolutePath: String
  if file.hasPrefix("/") {
    absolutePath = file
  } else if config.packageRoot.isEmpty {
    absolutePath = file
  } else {
    absolutePath = config.packageRoot + "/" + file
  }
  return "__swift_mutagen_visit_\(swiftMutagenHex(swiftMutagenStableHash(absolutePath)))"
}

private func swiftMutagenCanMakeReturnAlternative(
  _ mutation: SwiftMutagenMutation,
  returnType: Type,
  in function: Function,
  runtimeFunctionName: String? = nil,
  _ context: FunctionPassContext
) -> Bool {
  switch mutation.mutatedBuiltinName {
  case "return_false", "return_true":
    return swiftMutagenIsBoolType(returnType, in: function)
  case "return_nil":
    return returnType.isOptional
  case "return_zero":
    return swiftMutagenIsIntegerStructType(returnType, in: function)
  case "return_empty_string":
    return swiftMutagenIsStringType(returnType)
      && swiftMutagenEmptyStringFunction(named: swiftMutagenRuntimeHelperThunkName(
        runtimeFunctionName: runtimeFunctionName,
        suffix: "empty_string"
      ), context) != nil
  case "return_empty_array":
    return swiftMutagenIsCollectionType(returnType, named: "Array")
      && swiftMutagenEmptyCollectionFunction(named: swiftMutagenRuntimeHelperThunkName(
        runtimeFunctionName: runtimeFunctionName,
        suffix: "empty_array",
        fallbackName: "__swift_mutagen_empty_array"
      ), context) != nil
  case "return_empty_dictionary":
    return swiftMutagenIsCollectionType(returnType, named: "Dictionary")
      && swiftMutagenEmptyCollectionFunction(named: swiftMutagenRuntimeHelperThunkName(
        runtimeFunctionName: runtimeFunctionName,
        suffix: "empty_dictionary",
        fallbackName: "__swift_mutagen_empty_dictionary"
      ), context) != nil
  case "return_empty_set":
    return swiftMutagenIsCollectionType(returnType, named: "Set")
      && swiftMutagenEmptyCollectionFunction(named: swiftMutagenRuntimeHelperThunkName(
        runtimeFunctionName: runtimeFunctionName,
        suffix: "empty_set",
        fallbackName: "__swift_mutagen_empty_set"
      ), context) != nil
  default:
    return false
  }
}

private func swiftMutagenMakeReturnAlternative(
  _ mutation: SwiftMutagenMutation,
  returnType: Type,
  function: Function,
  runtimeFunctionName: String? = nil,
  context: FunctionPassContext,
  builder: Builder
) -> Value? {
  switch mutation.mutatedBuiltinName {
  case "return_false":
    return swiftMutagenMakeBool(false, type: returnType, builder: builder)
  case "return_true":
    return swiftMutagenMakeBool(true, type: returnType, builder: builder)
  case "return_nil":
    return swiftMutagenMakeOptionalNone(type: returnType, builder: builder)
  case "return_zero":
    return swiftMutagenMakeIntegerZero(type: returnType, in: function, builder: builder)
  case "return_empty_string":
    return swiftMutagenMakeEmptyString(
      type: returnType,
      helperName: swiftMutagenRuntimeHelperThunkName(
        runtimeFunctionName: runtimeFunctionName,
        suffix: "empty_string"
      ),
      context: context,
      builder: builder
    )
  case "return_empty_array":
    return swiftMutagenMakeEmptyCollection(
      type: returnType,
      helperName: swiftMutagenRuntimeHelperThunkName(
        runtimeFunctionName: runtimeFunctionName,
        suffix: "empty_array",
        fallbackName: "__swift_mutagen_empty_array"
      ),
      expectedReplacementCount: 1,
      context: context,
      builder: builder
    )
  case "return_empty_dictionary":
    return swiftMutagenMakeEmptyCollection(
      type: returnType,
      helperName: swiftMutagenRuntimeHelperThunkName(
        runtimeFunctionName: runtimeFunctionName,
        suffix: "empty_dictionary",
        fallbackName: "__swift_mutagen_empty_dictionary"
      ),
      expectedReplacementCount: 2,
      context: context,
      builder: builder
    )
  case "return_empty_set":
    return swiftMutagenMakeEmptyCollection(
      type: returnType,
      helperName: swiftMutagenRuntimeHelperThunkName(
        runtimeFunctionName: runtimeFunctionName,
        suffix: "empty_set",
        fallbackName: "__swift_mutagen_empty_set"
      ),
      expectedReplacementCount: 1,
      context: context,
      builder: builder
    )
  default:
    return nil
  }
}

private func swiftMutagenMakeConditionAlternative(
  _ mutation: SwiftMutagenMutation,
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

private func swiftMutagenCreateConditionBranch(
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

private func swiftMutagenMakeRuntimeSiteID(
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

private func swiftMutagenRuntimeChoiceRawValue(
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

private func swiftMutagenWriteMetamutantFragment(
  _ siteJSON: [String],
  moduleName: String,
  functionName: String,
  config: SwiftMutagenConfig
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
    + swiftMutagenSanitizeFileComponent(moduleName)
    + "-"
    + "\(swiftMutagenProcessID())"
    + "-"
    + swiftMutagenHex(swiftMutagenStableHash(functionName))
    + ".json"
  swiftMutagenCreateParentDirectories(forFile: path)
  swiftMutagenWrite(output, to: path, append: false)
}

private func swiftMutagenConditionSiteJSON(_ site: SwiftMutagenConditionSite) -> String {
  var fields: [String] = []
  fields.append(#""siteID":\#(site.siteID)"#)
  fields.append(#""module":"\#(swiftMutagenEscapeJSON(site.module))""#)
  fields.append(#""function":"\#(swiftMutagenEscapeJSON(site.function))""#)
  fields.append(
    #""sourceLocation":{"file":"\#(swiftMutagenEscapeJSON(site.file))","line":\#(site.line),"column":\#(site.column)}"#
  )
  fields.append(#""siteKind":"condition""#)
  fields.append(#""resultKind":"condition""#)
  var alternatives: [String] = []
  for alternative in site.alternatives {
    alternatives.append(swiftMutagenConditionAlternativeJSON(alternative))
  }
  fields.append(#""alternatives":[\#(alternatives.joined(separator: ","))]"#)
  return "{\(fields.joined(separator: ","))}"
}

private func swiftMutagenConditionAlternativeJSON(_ alternative: SwiftMutagenConditionAlternative) -> String {
  var fields: [String] = []
  fields.append(#""mutantID":"\#(swiftMutagenEscapeJSON(alternative.mutantID))""#)
  fields.append(#""alternativeIndex":\#(alternative.alternativeIndex)"#)
  fields.append(#""mutator":"\#(swiftMutagenEscapeJSON(alternative.mutation.mutator))""#)
  fields.append(#""sourceOriginal":"\#(swiftMutagenEscapeJSON(alternative.mutation.sourceOriginal))""#)
  fields.append(#""sourceMutated":"\#(swiftMutagenEscapeJSON(alternative.mutation.sourceMutated))""#)
  fields.append(#""behaviorKey":"\#(swiftMutagenEscapeJSON(alternative.mutation.silMutated))""#)
  return "{\(fields.joined(separator: ","))}"
}

private func swiftMutagenArithmeticSiteJSON(_ site: SwiftMutagenArithmeticSite) -> String {
  var fields: [String] = []
  fields.append(#""siteID":\#(site.siteID)"#)
  fields.append(#""module":"\#(swiftMutagenEscapeJSON(site.module))""#)
  fields.append(#""function":"\#(swiftMutagenEscapeJSON(site.function))""#)
  fields.append(#""sourceLocation":{"file":"\#(swiftMutagenEscapeJSON(site.file))","line":\#(site.line),"column":\#(site.column)}"#)
  fields.append(#""siteKind":"arithmetic""#)
  fields.append(#""resultKind":"value""#)
  fields.append(#""alternatives":[\#(site.alternatives.map(swiftMutagenArithmeticAlternativeJSON).joined(separator: ","))]"#)
  return "{\(fields.joined(separator: ","))}"
}

private func swiftMutagenArithmeticAlternativeJSON(_ alternative: SwiftMutagenArithmeticAlternative) -> String {
  var fields: [String] = []
  fields.append(#""mutantID":"\#(swiftMutagenEscapeJSON(alternative.mutantID))""#)
  fields.append(#""alternativeIndex":\#(alternative.alternativeIndex)"#)
  fields.append(#""mutator":"\#(swiftMutagenEscapeJSON(alternative.mutation.mutator))""#)
  fields.append(#""sourceOriginal":"\#(swiftMutagenEscapeJSON(alternative.mutation.sourceOriginal))""#)
  fields.append(#""sourceMutated":"\#(swiftMutagenEscapeJSON(alternative.mutation.sourceMutated))""#)
  fields.append(#""behaviorKey":"\#(swiftMutagenEscapeJSON(alternative.mutation.silMutated))""#)
  return "{\(fields.joined(separator: ","))}"
}

private func swiftMutagenScalarValueSiteJSON(_ site: SwiftMutagenScalarValueSite) -> String {
  var fields: [String] = []
  fields.append(#""siteID":\#(site.siteID)"#)
  fields.append(#""module":"\#(swiftMutagenEscapeJSON(site.module))""#)
  fields.append(#""function":"\#(swiftMutagenEscapeJSON(site.function))""#)
  fields.append(#""sourceLocation":{"file":"\#(swiftMutagenEscapeJSON(site.file))","line":\#(site.line),"column":\#(site.column)}"#)
  fields.append(#""siteKind":"scalarValue""#)
  fields.append(#""resultKind":"value""#)
  fields.append(#""alternatives":[\#(site.alternatives.map(swiftMutagenScalarValueAlternativeJSON).joined(separator: ","))]"#)
  return "{\(fields.joined(separator: ","))}"
}

private func swiftMutagenScalarValueAlternativeJSON(_ alternative: SwiftMutagenScalarValueAlternative) -> String {
  var fields: [String] = []
  fields.append(#""mutantID":"\#(swiftMutagenEscapeJSON(alternative.mutantID))""#)
  fields.append(#""alternativeIndex":\#(alternative.alternativeIndex)"#)
  fields.append(#""mutator":"\#(swiftMutagenEscapeJSON(alternative.mutation.mutator))""#)
  fields.append(#""sourceOriginal":"\#(swiftMutagenEscapeJSON(alternative.mutation.sourceOriginal))""#)
  fields.append(#""sourceMutated":"\#(swiftMutagenEscapeJSON(alternative.mutation.sourceMutated))""#)
  fields.append(#""behaviorKey":"\#(swiftMutagenEscapeJSON(alternative.mutation.silMutated))""#)
  return "{\(fields.joined(separator: ","))}"
}

private func swiftMutagenValueApplySiteJSON(_ site: SwiftMutagenValueApplySite) -> String {
  var fields: [String] = []
  fields.append(#""siteID":\#(site.siteID)"#)
  fields.append(#""module":"\#(swiftMutagenEscapeJSON(site.module))""#)
  fields.append(#""function":"\#(swiftMutagenEscapeJSON(site.function))""#)
  fields.append(#""sourceLocation":{"file":"\#(swiftMutagenEscapeJSON(site.file))","line":\#(site.line),"column":\#(site.column)}"#)
  fields.append(#""siteKind":"valueApply""#)
  fields.append(#""resultKind":"value""#)
  fields.append(#""alternatives":[\#(site.alternatives.map(swiftMutagenValueApplyAlternativeJSON).joined(separator: ","))]"#)
  return "{\(fields.joined(separator: ","))}"
}

private func swiftMutagenValueApplyAlternativeJSON(_ alternative: SwiftMutagenValueApplyAlternative) -> String {
  var fields: [String] = []
  fields.append(#""mutantID":"\#(swiftMutagenEscapeJSON(alternative.mutantID))""#)
  fields.append(#""alternativeIndex":\#(alternative.alternativeIndex)"#)
  fields.append(#""mutator":"\#(swiftMutagenEscapeJSON(alternative.mutation.mutator))""#)
  fields.append(#""sourceOriginal":"\#(swiftMutagenEscapeJSON(alternative.mutation.sourceOriginal))""#)
  fields.append(#""sourceMutated":"\#(swiftMutagenEscapeJSON(alternative.mutation.sourceMutated))""#)
  fields.append(#""behaviorKey":"\#(swiftMutagenEscapeJSON(alternative.mutation.silMutated))""#)
  return "{\(fields.joined(separator: ","))}"
}

private func swiftMutagenAssignmentValueSiteJSON(_ site: SwiftMutagenAssignmentValueSite) -> String {
  var fields: [String] = []
  fields.append(#""siteID":\#(site.siteID)"#)
  fields.append(#""module":"\#(swiftMutagenEscapeJSON(site.module))""#)
  fields.append(#""function":"\#(swiftMutagenEscapeJSON(site.function))""#)
  fields.append(#""sourceLocation":{"file":"\#(swiftMutagenEscapeJSON(site.file))","line":\#(site.line),"column":\#(site.column)}"#)
  fields.append(#""siteKind":"assignmentValue""#)
  fields.append(#""resultKind":"value""#)
  fields.append(#""alternatives":[\#(site.alternatives.map(swiftMutagenAssignmentValueAlternativeJSON).joined(separator: ","))]"#)
  return "{\(fields.joined(separator: ","))}"
}

private func swiftMutagenAssignmentValueAlternativeJSON(_ alternative: SwiftMutagenAssignmentValueAlternative) -> String {
  var fields: [String] = []
  fields.append(#""mutantID":"\#(swiftMutagenEscapeJSON(alternative.mutantID))""#)
  fields.append(#""alternativeIndex":\#(alternative.alternativeIndex)"#)
  fields.append(#""mutator":"\#(swiftMutagenEscapeJSON(alternative.mutation.mutator))""#)
  fields.append(#""sourceOriginal":"\#(swiftMutagenEscapeJSON(alternative.mutation.sourceOriginal))""#)
  fields.append(#""sourceMutated":"\#(swiftMutagenEscapeJSON(alternative.mutation.sourceMutated))""#)
  fields.append(#""behaviorKey":"\#(swiftMutagenEscapeJSON(alternative.mutation.silMutated))""#)
  return "{\(fields.joined(separator: ","))}"
}

private func swiftMutagenReturnSiteJSON(_ site: SwiftMutagenReturnSite) -> String {
  var fields: [String] = []
  fields.append(#""siteID":\#(site.siteID)"#)
  fields.append(#""module":"\#(swiftMutagenEscapeJSON(site.module))""#)
  fields.append(#""function":"\#(swiftMutagenEscapeJSON(site.function))""#)
  fields.append(
    #""sourceLocation":{"file":"\#(swiftMutagenEscapeJSON(site.file))","line":\#(site.line),"column":\#(site.column)}"#
  )
  fields.append(#""siteKind":"returnValue""#)
  fields.append(#""resultKind":"returnValue""#)
  var alternatives: [String] = []
  for alternative in site.alternatives {
    alternatives.append(swiftMutagenReturnAlternativeJSON(alternative))
  }
  fields.append(#""alternatives":[\#(alternatives.joined(separator: ","))]"#)
  return "{\(fields.joined(separator: ","))}"
}

private func swiftMutagenReturnBranchSiteJSON(_ site: SwiftMutagenReturnBranchSite) -> String {
  var fields: [String] = []
  fields.append(#""siteID":\#(site.siteID)"#)
  fields.append(#""module":"\#(swiftMutagenEscapeJSON(site.module))""#)
  fields.append(#""function":"\#(swiftMutagenEscapeJSON(site.function))""#)
  fields.append(
    #""sourceLocation":{"file":"\#(swiftMutagenEscapeJSON(site.file))","line":\#(site.line),"column":\#(site.column)}"#
  )
  fields.append(#""siteKind":"returnBranchValue""#)
  fields.append(#""resultKind":"returnValue""#)
  var alternatives: [String] = []
  for alternative in site.alternatives {
    alternatives.append(swiftMutagenReturnAlternativeJSON(alternative))
  }
  fields.append(#""alternatives":[\#(alternatives.joined(separator: ","))]"#)
  return "{\(fields.joined(separator: ","))}"
}

private func swiftMutagenReturnAlternativeJSON(_ alternative: SwiftMutagenReturnAlternative) -> String {
  var fields: [String] = []
  fields.append(#""mutantID":"\#(swiftMutagenEscapeJSON(alternative.mutantID))""#)
  fields.append(#""alternativeIndex":\#(alternative.alternativeIndex)"#)
  fields.append(#""mutator":"\#(swiftMutagenEscapeJSON(alternative.mutation.mutator))""#)
  fields.append(#""sourceOriginal":"\#(swiftMutagenEscapeJSON(alternative.mutation.sourceOriginal))""#)
  fields.append(#""sourceMutated":"\#(swiftMutagenEscapeJSON(alternative.mutation.sourceMutated))""#)
  fields.append(#""behaviorKey":"\#(swiftMutagenEscapeJSON(alternative.mutation.silMutated))""#)
  return "{\(fields.joined(separator: ","))}"
}

private func swiftMutagenVoidCallSiteJSON(_ site: SwiftMutagenVoidCallSite) -> String {
  var fields: [String] = []
  fields.append(#""siteID":\#(site.siteID)"#)
  fields.append(#""module":"\#(swiftMutagenEscapeJSON(site.module))""#)
  fields.append(#""function":"\#(swiftMutagenEscapeJSON(site.function))""#)
  fields.append(
    #""sourceLocation":{"file":"\#(swiftMutagenEscapeJSON(site.file))","line":\#(site.line),"column":\#(site.column)}"#
  )
  fields.append(#""siteKind":"voidCall""#)
  fields.append(#""resultKind":"statement""#)
  fields.append(#""alternatives":[\#(site.alternatives.map(swiftMutagenVoidCallAlternativeJSON).joined(separator: ","))]"#)
  return "{\(fields.joined(separator: ","))}"
}

private func swiftMutagenVoidCallAlternativeJSON(_ alternative: SwiftMutagenVoidCallAlternative) -> String {
  var fields: [String] = []
  fields.append(#""mutantID":"\#(swiftMutagenEscapeJSON(alternative.mutantID))""#)
  fields.append(#""alternativeIndex":\#(alternative.alternativeIndex)"#)
  fields.append(#""mutator":"\#(swiftMutagenEscapeJSON(alternative.mutation.mutator))""#)
  fields.append(#""sourceOriginal":"\#(swiftMutagenEscapeJSON(alternative.mutation.sourceOriginal))""#)
  fields.append(#""sourceMutated":"\#(swiftMutagenEscapeJSON(alternative.mutation.sourceMutated))""#)
  fields.append(#""behaviorKey":"\#(swiftMutagenEscapeJSON(alternative.mutation.silMutated))""#)
  return "{\(fields.joined(separator: ","))}"
}

private func swiftMutagenModeName(_ mode: SwiftMutagenMode) -> String {
  switch mode {
  case .discover:
    return "discover"
  case .apply:
    return "apply"
  case .metamutant:
    return "metamutant"
  }
}

private func swiftMutagenShouldLog(
  function: Function,
  moduleName: String,
  config: SwiftMutagenConfig
) -> Bool {
  if config.compilerEventsPath.isEmpty {
    return false
  }
  if swiftMutagenFunctionName(function.name.string, belongsToModule: moduleName) {
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

private func swiftMutagenLogEvent(
  _ event: String,
  config: SwiftMutagenConfig,
  fields: [(String, String)]
) {
  guard !config.compilerEventsPath.isEmpty else {
    return
  }

  var jsonFields = [#""event":"\#(swiftMutagenEscapeJSON(event))""#]
  for (key, value) in fields {
    jsonFields.append(#""\#(swiftMutagenEscapeJSON(key))":"\#(swiftMutagenEscapeJSON(value))""#)
  }
  swiftMutagenCreateParentDirectories(forFile: config.compilerEventsPath)
  swiftMutagenWrite("{\(jsonFields.joined(separator: ","))}\n", to: config.compilerEventsPath, append: true)
}

private func swiftMutagenFunctionName(_ functionName: String, belongsToModule moduleName: String) -> Bool {
  let mangledModulePrefix = "$s\(moduleName.utf8.count)\(moduleName)"
  if functionName.hasPrefix(mangledModulePrefix) {
    return true
  }
  return functionName.hasPrefix("@\(mangledModulePrefix)")
}

private func swiftMutagenStableSiteID(
  packageRoot: String,
  module: String,
  file: String,
  line: Int,
  column: Int,
  function: String,
  siteKind: String,
  localOrdinal: Int
) -> UInt64 {
  swiftMutagenStableHash([
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

private func swiftMutagenStableHash(_ text: String) -> UInt64 {
  var hash: UInt64 = 0xcbf29ce484222325
  for byte in text.utf8 {
    hash ^= UInt64(byte)
    hash = hash &* 0x100000001b3
  }
  return hash
}

private func swiftMutagenHex(_ value: UInt64) -> String {
  let digits = Array("0123456789ABCDEF".utf8)
  var output = [UInt8](repeating: 48, count: 16)
  for index in 0..<16 {
    let shift = UInt64((15 - index) * 4)
    let nibble = Int((value >> shift) & 0xf)
    output[index] = digits[nibble]
  }
  return String(decoding: output, as: UTF8.self)
}

private func swiftMutagenSanitizeFileComponent(_ value: String) -> String {
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

private func swiftMutagenProcessID() -> Int32 {
  #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(Linux) || os(Android)
  return getpid()
  #else
  return 0
  #endif
}

private func swiftMutagenClockMicroseconds() -> UInt64 {
  #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(Linux) || os(Android)
  var now = timeval()
  gettimeofday(&now, nil)
  return UInt64(now.tv_sec) * 1_000_000 + UInt64(now.tv_usec)
  #else
  return 0
  #endif
}

private func swiftMutagenReturnMutations(
  for returnInst: ReturnInst,
  config: SwiftMutagenConfig
) -> [SwiftMutagenMutation] {
  let returnedValue = returnInst.returnedValue
  let returnType = returnedValue.type
  var mutations: [SwiftMutagenMutation] = []

  if swiftMutagenIsBoolType(returnType, in: returnInst.parentFunction) {
    let literal = swiftMutagenBoolLiteralValue(returnedValue)
    if literal != false,
       let rule = swiftMutagenFirstReturnRule(context: "boolToFalse", config: config) {
      mutations.append(swiftMutagenReturnMutation(rule, silOriginal: returnType.description))
    }
    if literal != true,
       let rule = swiftMutagenFirstReturnRule(context: "boolToTrue", config: config) {
      mutations.append(swiftMutagenReturnMutation(rule, silOriginal: returnType.description))
    }
    return mutations
  }

  if returnType.isOptional && !swiftMutagenIsOptionalNone(returnedValue) {
    if let rule = swiftMutagenFirstReturnRule(context: "optionalToNil", config: config) {
      mutations.append(swiftMutagenReturnMutation(rule, silOriginal: returnType.description))
    }
    return mutations
  }

  if swiftMutagenIsIntegerStructType(returnType, in: returnInst.parentFunction),
     swiftMutagenIntegerStructLiteralValue(returnedValue) != 0,
     let rule = swiftMutagenFirstReturnRule(context: "integerToZero", config: config) {
    mutations.append(swiftMutagenReturnMutation(rule, silOriginal: returnType.description))
  }

  if swiftMutagenIsStringType(returnType),
     let rule = swiftMutagenFirstReturnRule(context: "stringToEmpty", config: config) {
    mutations.append(swiftMutagenReturnMutation(rule, silOriginal: returnType.description))
  }

  if swiftMutagenIsCollectionType(returnType, named: "Array"),
     let rule = swiftMutagenFirstReturnRule(context: "arrayToEmpty", config: config) {
    mutations.append(swiftMutagenReturnMutation(rule, silOriginal: returnType.description))
  }

  if swiftMutagenIsCollectionType(returnType, named: "Dictionary"),
     let rule = swiftMutagenFirstReturnRule(context: "dictionaryToEmpty", config: config) {
    mutations.append(swiftMutagenReturnMutation(rule, silOriginal: returnType.description))
  }

  if swiftMutagenIsCollectionType(returnType, named: "Set"),
     let rule = swiftMutagenFirstReturnRule(context: "setToEmpty", config: config) {
    mutations.append(swiftMutagenReturnMutation(rule, silOriginal: returnType.description))
  }

  return mutations
}

private func swiftMutagenReturnMutation(
  _ rule: SwiftMutagenReturnMutationRule,
  silOriginal: String
) -> SwiftMutagenMutation {
  return SwiftMutagenMutation(
    originalID: nil,
    mutator: rule.mutator,
    mutatedBuiltinName: rule.mutatedBuiltinName,
    sourceOriginal: rule.sourceOriginal,
    sourceMutated: rule.sourceMutated,
    silOriginal: silOriginal,
    silMutated: rule.silMutated)
}

private func swiftMutagenFirstReturnRule(
  context: String,
  config: SwiftMutagenConfig
) -> SwiftMutagenReturnMutationRule? {
  for rule in config.returnMutationRules where rule.context == context {
    if swiftMutagenMutatorIsEnabled(rule.mutator, config: config) {
      return rule
    }
  }
  return nil
}

private func swiftMutagenVoidCallMutation(
  for apply: ApplyInst,
  config: SwiftMutagenConfig
) -> SwiftMutagenMutation? {
  guard apply.type.isVoid else {
    return nil
  }
  guard let rule = swiftMutagenFirstVoidCallRule(config: config) else {
    return nil
  }

  return SwiftMutagenMutation(
    originalID: nil,
    mutator: rule.mutator,
    mutatedBuiltinName: rule.mutatedBuiltinName,
    sourceOriginal: rule.sourceOriginal,
    sourceMutated: rule.sourceMutated,
    silOriginal: apply.description,
    silMutated: rule.silMutated)
}

private func swiftMutagenFirstVoidCallRule(
  config: SwiftMutagenConfig
) -> SwiftMutagenVoidCallMutationRule? {
  for rule in config.voidCallMutationRules {
    if swiftMutagenMutatorIsEnabled(rule.mutator, config: config) {
      return rule
    }
  }
  return nil
}

private func swiftMutagenMutations(
  for builtin: BuiltinInst,
  config: SwiftMutagenConfig
) -> [SwiftMutagenMutation] {
  var mutations = swiftMutagenConditionMutations(
    for: builtin,
    config: config,
    includeGenericComparisonRules: false)
  mutations += swiftMutagenArithmeticSiteMutations(for: builtin, config: config)
  return mutations
}

private func swiftMutagenContextualArithmeticRule(
  for builtin: BuiltinInst,
  builtinID: String,
  config: SwiftMutagenConfig
) -> SwiftMutagenContextualArithmeticMutationRule? {
  for rule in config.contextualArithmeticMutationRules where rule.builtinID == builtinID {
    if swiftMutagenContext(rule.context, matches: builtin) {
      return rule
    }
  }
  return nil
}

private func swiftMutagenContext(
  _ context: String,
  matches builtin: BuiltinInst
) -> Bool {
  switch context {
  case "increment":
    return swiftMutagenIsIncrementBuiltin(builtin)
  case "unaryNegation":
    return swiftMutagenIsUnaryNegationBuiltin(builtin)
  case "otherwise":
    return true
  default:
    return false
  }
}

private func swiftMutagenContextualArithmeticMutation(
  _ rule: SwiftMutagenContextualArithmeticMutationRule,
  for builtin: BuiltinInst
) -> SwiftMutagenMutation {
  SwiftMutagenMutation(
    originalID: builtin.id,
    mutator: rule.mutator,
    mutatedBuiltinName: rule.mutatedBuiltinName,
    sourceOriginal: rule.sourceOriginal,
    sourceMutated: rule.sourceMutated,
    silOriginal: builtin.name.string,
    silMutated: rule.mutatedBuiltinName)
}

private func swiftMutagenArithmeticBuiltinIDName(_ builtin: BuiltinInst) -> String? {
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

private func swiftMutagenBuiltinFunctionName(_ builtin: BuiltinInst) -> String? {
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

private func swiftMutagenBuiltinIDName(_ id: BuiltinInst.ID?) -> String? {
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

private func swiftMutagenBinaryMutation(
  _ builtin: BuiltinInst,
  mutator: String,
  mutatedBuiltinName: String,
  sourceOriginal: String,
  sourceMutated: String
) -> SwiftMutagenMutation {
  SwiftMutagenMutation(
    originalID: builtin.id,
    mutator: mutator,
    mutatedBuiltinName: mutatedBuiltinName,
    sourceOriginal: sourceOriginal,
    sourceMutated: sourceMutated,
    silOriginal: builtin.name.string,
    silMutated: mutatedBuiltinName)
}

private func swiftMutagenIsIncrementBuiltin(_ builtin: BuiltinInst) -> Bool {
  let arguments = Array(builtin.arguments)
  guard arguments.count >= 2 else {
    return false
  }
  return swiftMutagenIsOneInteger(arguments[0]) || swiftMutagenIsOneInteger(arguments[1])
}

private func swiftMutagenIsUnaryNegationBuiltin(_ builtin: BuiltinInst) -> Bool {
  let arguments = Array(builtin.arguments)
  guard arguments.count >= 2 else {
    return false
  }
  return swiftMutagenIsZeroInteger(arguments[0]) && !swiftMutagenIsZeroInteger(arguments[1])
}

private func swiftMutagenIsOneInteger(_ value: Value) -> Bool {
  guard let literal = value as? IntegerLiteralInst,
        let literalValue = literal.value else {
    return false
  }
  return literalValue == 1
}

private func swiftMutagenIsZeroInteger(_ value: Value) -> Bool {
  guard let literal = value as? IntegerLiteralInst,
        let literalValue = literal.value else {
    return false
  }
  return literalValue == 0
}

private func swiftMutagenApply(
  mutation: SwiftMutagenMutation,
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

private func swiftMutagenApplyReturn(
  mutation: SwiftMutagenMutation,
  to returnInst: ReturnInst,
  _ context: FunctionPassContext
) {
  let builder = Builder(before: returnInst, context)
  let returnType = returnInst.returnedValue.type
  let replacement: Value?
  switch mutation.mutatedBuiltinName {
  case "return_false":
    replacement = swiftMutagenMakeBool(false, type: returnType, builder: builder)
  case "return_true":
    replacement = swiftMutagenMakeBool(true, type: returnType, builder: builder)
  case "return_nil":
    replacement = swiftMutagenMakeOptionalNone(type: returnType, builder: builder)
  case "return_zero":
    replacement = swiftMutagenMakeIntegerZero(type: returnType, in: returnInst.parentFunction, builder: builder)
  case "return_empty_string":
    replacement = swiftMutagenMakeEmptyString(
      type: returnType,
      helperName: "__swift_mutagen_empty_string",
      context: context,
      builder: builder
    )
  case "return_empty_array":
    replacement = swiftMutagenMakeEmptyCollection(
      type: returnType,
      helperName: "__swift_mutagen_empty_array",
      expectedReplacementCount: 1,
      context: context,
      builder: builder
    )
  case "return_empty_dictionary":
    replacement = swiftMutagenMakeEmptyCollection(
      type: returnType,
      helperName: "__swift_mutagen_empty_dictionary",
      expectedReplacementCount: 2,
      context: context,
      builder: builder
    )
  case "return_empty_set":
    replacement = swiftMutagenMakeEmptyCollection(
      type: returnType,
      helperName: "__swift_mutagen_empty_set",
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

private func swiftMutagenMakeBool(
  _ value: Bool,
  type: Type,
  builder: Builder
) -> Value {
  let literal = builder.createBoolLiteral(value)
  return builder.createStruct(type: type, elements: [literal])
}

private func swiftMutagenMakeIntegerZero(
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

private func swiftMutagenMakeOptionalNone(
  type: Type,
  builder: Builder
) -> Value {
  return builder.createEnum(caseIndex: 0, payload: nil, enumType: type)
}

private func swiftMutagenMakeEmptyString(
  type: Type,
  helperName: String,
  context: FunctionPassContext,
  builder: Builder
) -> Value? {
  guard swiftMutagenIsStringType(type),
        let emptyStringFunction = swiftMutagenEmptyStringFunction(named: helperName, context) else {
    return nil
  }
  let functionRef = builder.createFunctionRef(emptyStringFunction)
  return builder.createApply(
    function: functionRef,
    SubstitutionMap(),
    arguments: []
  )
}

private func swiftMutagenEmptyStringFunction(
  named helperName: String,
  _ context: FunctionPassContext
) -> Function? {
  if let helper = context.lookupFunction(name: helperName)
    ?? context.lookupFunction(name: "@\(helperName)") {
    return helper
  }
  return context.lookupFunction(name: "__swift_mutagen_empty_string")
    ?? context.lookupFunction(name: "@__swift_mutagen_empty_string")
    ?? context.loadFunction(name: "__swift_mutagen_empty_string", loadCalleesRecursively: false)
    ?? context.loadFunction(name: "@__swift_mutagen_empty_string", loadCalleesRecursively: false)
}

private func swiftMutagenRuntimeHelperThunkName(
  runtimeFunctionName: String?,
  suffix: String,
  fallbackName: String = "__swift_mutagen_empty_string"
) -> String {
  guard let runtimeFunctionName else {
    return fallbackName
  }
  return "\(runtimeFunctionName)_\(suffix)"
}

private func swiftMutagenMakeEmptyCollection(
  type: Type,
  helperName: String,
  expectedReplacementCount: Int,
  context: FunctionPassContext,
  builder: Builder
) -> Value? {
  guard let emptyCollectionFunction = swiftMutagenEmptyCollectionFunction(named: helperName, context) else {
    return nil
  }
  let replacements = Array(type.contextSubstitutionMap.replacementTypes)
  guard replacements.count == expectedReplacementCount else {
    return nil
  }
  let functionRef = builder.createFunctionRef(emptyCollectionFunction)
  return builder.createApply(
    function: functionRef,
    SubstitutionMap(
      genericSignature: emptyCollectionFunction.genericSignature,
      replacementTypes: replacements
    ),
    arguments: []
  )
}

private func swiftMutagenEmptyCollectionFunction(
  named helperName: String,
  _ context: FunctionPassContext
) -> Function? {
  if let helper = context.lookupFunction(name: helperName)
    ?? context.lookupFunction(name: "@\(helperName)") {
    return helper
  }
  switch helperName {
  case "__swift_mutagen_empty_array":
    return context.lookupFunction(name: "__swift_mutagen_empty_array")
      ?? context.lookupFunction(name: "@__swift_mutagen_empty_array")
      ?? context.loadFunction(name: "__swift_mutagen_empty_array", loadCalleesRecursively: false)
      ?? context.loadFunction(name: "@__swift_mutagen_empty_array", loadCalleesRecursively: false)
  case "__swift_mutagen_empty_dictionary":
    return context.lookupFunction(name: "__swift_mutagen_empty_dictionary")
      ?? context.lookupFunction(name: "@__swift_mutagen_empty_dictionary")
      ?? context.loadFunction(name: "__swift_mutagen_empty_dictionary", loadCalleesRecursively: false)
      ?? context.loadFunction(name: "@__swift_mutagen_empty_dictionary", loadCalleesRecursively: false)
  case "__swift_mutagen_empty_set":
    return context.lookupFunction(name: "__swift_mutagen_empty_set")
      ?? context.lookupFunction(name: "@__swift_mutagen_empty_set")
      ?? context.loadFunction(name: "__swift_mutagen_empty_set", loadCalleesRecursively: false)
      ?? context.loadFunction(name: "@__swift_mutagen_empty_set", loadCalleesRecursively: false)
  default:
    return nil
  }
}

private func swiftMutagenIsBoolType(_ type: Type, in function: Function) -> Bool {
  guard let nominal = type.nominal,
        nominal.name.string == "Bool",
        let fields = type.getNominalFields(in: function),
        fields.count == 1 else {
    return false
  }
  return fields[0].canonicalType.isBuiltinInteger(withFixedWidth: 1)
}

private func swiftMutagenIsIntegerStructType(_ type: Type, in function: Function) -> Bool {
  guard let nominal = type.nominal,
        nominal.name.string != "Bool",
        let fields = type.getNominalFields(in: function),
        fields.count == 1 else {
    return false
  }
  return fields[0].canonicalType.isBuiltinInteger
}

private func swiftMutagenIsStringType(_ type: Type) -> Bool {
  guard let nominal = type.nominal else {
    return false
  }
  return nominal.name.string == "String"
}

private func swiftMutagenIsCollectionType(_ type: Type, named name: String) -> Bool {
  guard let nominal = type.nominal else {
    return false
  }
  return nominal.name.string == name
}

private func swiftMutagenRecordReturnType(
  _ type: Type,
  in function: Function,
  stats: inout SwiftMutagenReturnDiscoveryStats
) {
  if swiftMutagenIsBoolType(type, in: function) {
    stats.boolTerminators += 1
    return
  }
  if type.isOptional {
    stats.optionalTerminators += 1
    return
  }
  if swiftMutagenIsIntegerStructType(type, in: function) {
    stats.integerTerminators += 1
    return
  }
  if swiftMutagenIsStringType(type) {
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

private func swiftMutagenRecordReturnSourceLocationMiss(
  _ type: Type,
  in function: Function,
  stats: inout SwiftMutagenReturnDiscoveryStats
) {
  if swiftMutagenIsBoolType(type, in: function) {
    stats.missingBoolSourceLocations += 1
    return
  }
  if type.isOptional {
    stats.missingOptionalSourceLocations += 1
    return
  }
  if swiftMutagenIsIntegerStructType(type, in: function) {
    stats.missingIntegerSourceLocations += 1
    return
  }
  if swiftMutagenIsStringType(type) {
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

private func swiftMutagenBoolLiteralValue(_ value: Value) -> Bool? {
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

private func swiftMutagenIntegerStructLiteralValue(_ value: Value) -> Int? {
  guard let structInst = value as? StructInst,
        let literal = structInst.operands.first?.value as? IntegerLiteralInst else {
    return nil
  }
  return literal.value
}

private func swiftMutagenIsOptionalNone(_ value: Value) -> Bool {
  guard let enumInst = value as? EnumInst else {
    return false
  }
  return enumInst.type.isOptional && enumInst.caseIndex == 0
}

private func swiftMutagenMutatorIsEnabled(
  _ mutator: String,
  config: SwiftMutagenConfig
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

private func swiftMutagenReturnSourceLocation(
  for returnInst: ReturnInst,
  mutation: SwiftMutagenMutation,
  config: SwiftMutagenConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  if let fileNameAndPosition = returnInst.location.fileNameAndPosition {
    let path = fileNameAndPosition.path.string
    if let matchedPath = swiftMutagenIncludedSourcePath(path, config: config) {
      let candidate = (
        swiftMutagenTrimPackageRoot(matchedPath, config: config),
        fileNameAndPosition.line,
        fileNameAndPosition.column,
        mutation.sourceOriginal,
        mutation.sourceMutated)
      if swiftMutagenReturnSourceLocationIsUsable(candidate, mutation: mutation, config: config) {
        return candidate
      }
      if let anchored = swiftMutagenFindAssignmentReturnSourceLocation(
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        mutation: mutation,
        config: config
      ) {
        return anchored
      }
      if let anchored = swiftMutagenFindDescribedExplicitReturnSourceLocation(
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        locationDescription: returnInst.location.description,
        mutation: mutation,
        config: config
      ) {
        return anchored
      }
      if let anchored = swiftMutagenFindUniqueExplicitReturnSourceLocation(
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        mutation: mutation,
        config: config
      ) {
        return anchored
      }
      if let anchored = swiftMutagenFindNearestPriorExplicitReturnSourceLocation(
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        mutation: mutation,
        config: config
      ) {
        return anchored
      }
      if let anchored = swiftMutagenFindNearestPriorImplicitReturnSourceLocation(
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        mutation: mutation,
        config: config
      ) {
        return anchored
      }
      if let anchored = swiftMutagenFindUniqueImplicitReturnSourceLocation(
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        mutation: mutation,
        config: config
      ) {
        return anchored
      }
      if let anchored = swiftMutagenFindPropertyGetterReturnSourceLocation(
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
    if let matchedPath = swiftMutagenIncludedSourcePath(path, config: config) {
      let candidate = (
        swiftMutagenTrimPackageRoot(matchedPath, config: config),
        fileNameAndPosition.line,
        fileNameAndPosition.column,
        mutation.sourceOriginal,
        mutation.sourceMutated)
      if swiftMutagenReturnSourceLocationIsUsable(candidate, mutation: mutation, config: config) {
        return candidate
      }
      if let anchored = swiftMutagenFindAssignmentReturnSourceLocation(
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        mutation: mutation,
        config: config
      ) {
        return anchored
      }
      if let anchored = swiftMutagenFindDescribedExplicitReturnSourceLocation(
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        locationDescription: returnInst.location.description,
        mutation: mutation,
        config: config
      ) {
        return anchored
      }
      if let anchored = swiftMutagenFindUniqueExplicitReturnSourceLocation(
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        mutation: mutation,
        config: config
      ) {
        return anchored
      }
      if let anchored = swiftMutagenFindNearestPriorExplicitReturnSourceLocation(
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        mutation: mutation,
        config: config
      ) {
        return anchored
      }
      if let anchored = swiftMutagenFindNearestPriorImplicitReturnSourceLocation(
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        mutation: mutation,
        config: config
      ) {
        return anchored
      }
      if let anchored = swiftMutagenFindUniqueImplicitReturnSourceLocation(
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        mutation: mutation,
        config: config
      ) {
        return anchored
      }
      if let anchored = swiftMutagenFindPropertyGetterReturnSourceLocation(
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        mutation: mutation,
        config: config
      ) {
        return anchored
      }
    }
  }

  let returnLocation = returnInst.location.description
  for path in swiftMutagenSwiftSourcePaths(config: config) {
    guard returnLocation.contains(path),
          let line = swiftMutagenPreferredLine(in: returnLocation, path: path) else {
      continue
    }
    let candidate = (
      swiftMutagenTrimPackageRoot(path, config: config),
      line,
      1,
      mutation.sourceOriginal,
      mutation.sourceMutated)
    if swiftMutagenReturnSourceLocationIsUsable(candidate, mutation: mutation, config: config) {
      return candidate
    }
    if let anchored = swiftMutagenFindAssignmentReturnSourceLocation(
      path: path,
      preferredLine: line,
      mutation: mutation,
      config: config
    ) {
      return anchored
    }
    if let anchored = swiftMutagenFindDescribedExplicitReturnSourceLocation(
      path: path,
      preferredLine: line,
      locationDescription: returnLocation,
      mutation: mutation,
      config: config
    ) {
      return anchored
    }
    if let anchored = swiftMutagenFindUniqueExplicitReturnSourceLocation(
      path: path,
      preferredLine: line,
      mutation: mutation,
      config: config
    ) {
      return anchored
    }
    if let anchored = swiftMutagenFindNearestPriorExplicitReturnSourceLocation(
      path: path,
      preferredLine: line,
      mutation: mutation,
      config: config
    ) {
      return anchored
    }
    if let anchored = swiftMutagenFindNearestPriorImplicitReturnSourceLocation(
      path: path,
      preferredLine: line,
      mutation: mutation,
      config: config
    ) {
      return anchored
    }
    if let anchored = swiftMutagenFindUniqueImplicitReturnSourceLocation(
      path: path,
      preferredLine: line,
      mutation: mutation,
      config: config
    ) {
      return anchored
    }
    if let anchored = swiftMutagenFindPropertyGetterReturnSourceLocation(
      path: path,
      preferredLine: line,
      mutation: mutation,
      config: config
    ) {
      return anchored
    }
  }

  let location = returnInst.parentFunction.location.description
  for path in swiftMutagenSwiftSourcePaths(config: config) {
    guard location.contains(path),
          let line = swiftMutagenPreferredLine(in: location, path: path) else {
      continue
    }
    let candidate = (
      swiftMutagenTrimPackageRoot(path, config: config),
      line,
      1,
      mutation.sourceOriginal,
      mutation.sourceMutated)
    if swiftMutagenReturnSourceLocationIsUsable(candidate, mutation: mutation, config: config) {
      return candidate
    }
    if let anchored = swiftMutagenFindAssignmentReturnSourceLocation(
      path: path,
      preferredLine: line,
      mutation: mutation,
      config: config
    ) {
      return anchored
    }
    if let anchored = swiftMutagenFindDescribedExplicitReturnSourceLocation(
      path: path,
      preferredLine: line,
      locationDescription: returnInst.location.description,
      mutation: mutation,
      config: config
    ) {
      return anchored
    }
    if let anchored = swiftMutagenFindUniqueExplicitReturnSourceLocation(
      path: path,
      preferredLine: line,
      mutation: mutation,
      config: config
    ) {
      return anchored
    }
    if let anchored = swiftMutagenFindUniqueImplicitReturnSourceLocation(
      path: path,
      preferredLine: line,
      mutation: mutation,
      config: config
    ) {
      return anchored
    }
    if let anchored = swiftMutagenFindPropertyGetterReturnSourceLocation(
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

private func swiftMutagenFindPropertyGetterReturnSourceLocation(
  path: String,
  preferredLine: Int,
  mutation: SwiftMutagenMutation,
  config: SwiftMutagenConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard preferredLine > 0,
        mutation.sourceOriginal == "return",
        let text = swiftMutagenRead(path) else {
    return nil
  }

  if let exact = swiftMutagenPropertyGetterReturnSourceLocation(
    in: text,
    path: path,
    lineRange: preferredLine...preferredLine,
    mutation: mutation,
    config: config
  ) {
    return exact
  }

  let firstLine = preferredLine > 1 ? preferredLine - 1 : 1
  return swiftMutagenPropertyGetterReturnSourceLocation(
    in: text,
    path: path,
    lineRange: firstLine...(preferredLine + 2),
    mutation: mutation,
    config: config
  )
}

private func swiftMutagenPropertyGetterReturnSourceLocation(
  in text: String,
  path: String,
  lineRange: ClosedRange<Int>,
  mutation: SwiftMutagenMutation,
  config: SwiftMutagenConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  var matches: [(line: Int, column: Int, sourceOriginal: String, sourceMutated: String)] = []
  var currentLine = 1
  var lineStart = text.startIndex
  var index = text.startIndex

  func inspectLine(_ lineText: String, line: Int) {
    guard lineRange.contains(line),
          matches.count < 2,
          let property = swiftMutagenStoredPropertyDeclaration(lineText, mutation: mutation) else {
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
    swiftMutagenTrimPackageRoot(path, config: config),
    match.line,
    match.column,
    match.sourceOriginal,
    match.sourceMutated)
}

private func swiftMutagenStoredPropertyDeclaration(
  _ line: String,
  mutation: SwiftMutagenMutation
) -> (column: Int, sourceOriginal: String, sourceMutated: String)? {
  let bytes = Array(line.utf8)
  let lineStart = swiftMutagenSkipHorizontalWhitespace(bytes, from: 0)
  let lineEnd = swiftMutagenTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  guard lineStart < lineEnd,
        !swiftMutagenASCIIHasPrefix(bytes, start: lineStart, prefix: "case "),
        !swiftMutagenASCIIHasPrefix(bytes, start: lineStart, prefix: "func "),
        !swiftMutagenASCIIHasPrefix(bytes, start: lineStart, prefix: "init"),
        !swiftMutagenASCIIHasPrefix(bytes, start: lineStart, prefix: "return "),
        !swiftMutagenASCIIHasPrefix(bytes, start: lineStart, prefix: "//") else {
    return nil
  }

  guard let keyword = swiftMutagenPropertyDeclarationKeyword(bytes: bytes, start: lineStart, end: lineEnd) else {
    return nil
  }
  let nameStart = swiftMutagenSkipHorizontalWhitespace(bytes, from: keyword.end)
  if nameStart < lineEnd && bytes[nameStart] == 40 {
    return nil
  }
  guard nameStart < lineEnd,
        swiftMutagenIsASCIIIdentifierStart(bytes[nameStart]) else {
    return nil
  }
  var nameEnd = nameStart + 1
  while nameEnd < lineEnd && swiftMutagenIsASCIILetterNumberOrUnderscore(bytes[nameEnd]) {
    nameEnd += 1
  }
  var afterName = swiftMutagenSkipHorizontalWhitespace(bytes, from: nameEnd)
  guard afterName < lineEnd,
        bytes[afterName] == 58 else {
    return nil
  }
  afterName = swiftMutagenSkipHorizontalWhitespace(bytes, from: afterName + 1)
  guard afterName < lineEnd else {
    return nil
  }
  for index in afterName..<lineEnd {
    if bytes[index] == 123 {
      return nil
    }
  }

  return (
    nameStart + 1,
    String(decoding: bytes[nameStart..<nameEnd], as: UTF8.self),
    swiftMutagenImplicitReturnSourceMutation(for: mutation))
}

private func swiftMutagenPropertyDeclarationKeyword(bytes: [UInt8], start: Int, end: Int) -> (start: Int, end: Int)? {
  var index = start
  while index < end {
    let tokenStart = swiftMutagenSkipHorizontalWhitespace(bytes, from: index)
    guard tokenStart < end else {
      return nil
    }
    var tokenEnd = tokenStart
    while tokenEnd < end && swiftMutagenIsASCIILetterNumberOrUnderscore(bytes[tokenEnd]) {
      tokenEnd += 1
    }
    guard tokenEnd > tokenStart else {
      return nil
    }
    let token = String(decoding: bytes[tokenStart..<tokenEnd], as: UTF8.self)
    if token == "let" || token == "var" {
      return (tokenStart, tokenEnd)
    }
    if !swiftMutagenIsPropertyDeclarationModifier(token) {
      return nil
    }
    index = swiftMutagenSkipPropertyDeclarationModifierSuffix(bytes: bytes, from: tokenEnd, end: end)
  }
  return nil
}

private func swiftMutagenSkipPropertyDeclarationModifierSuffix(bytes: [UInt8], from index: Int, end: Int) -> Int {
  guard index + 5 <= end,
        bytes[index] == 40,
        swiftMutagenASCIIHasExactPrefix(bytes, start: index, prefix: "(set)") else {
    return index
  }
  return index + 5
}

private func swiftMutagenIsPropertyDeclarationModifier(_ token: String) -> Bool {
  switch token {
  case "public", "private", "internal", "fileprivate", "open", "package",
       "static", "class", "final", "lazy", "weak", "unowned", "nonisolated",
       "isolated", "mutating", "nonmutating":
    return true
  default:
    return false
  }
}

private func swiftMutagenScalarValueSourceLocation(
  for value: StructInst,
  mutation: SwiftMutagenMutation,
  config: SwiftMutagenConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  let functionSourceLocation = swiftMutagenFunctionSourceLocation(
    for: value.parentFunction,
    config: config
  )
  if let fileNameAndPosition = value.location.fileNameAndPosition {
    let path = fileNameAndPosition.path.string
    if let matchedPath = swiftMutagenIncludedSourcePath(path, config: config) {
      if let assignment = swiftMutagenFindAssignmentValueSourceLocation(
        path: matchedPath,
        preferredLine: fileNameAndPosition.line,
        mutation: mutation,
        config: config,
        requiresDirectValueExpression: true
      ) {
        return assignment
      }
      if let returned = swiftMutagenFindReturnedScalarValueSourceLocation(
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
         let anchored = swiftMutagenFindOrdinalScalarValueSourceLocation(
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
    if let anchored = swiftMutagenFindAssignmentValueSourceLocation(
      path: functionSourceLocation.path,
      preferredLine: functionSourceLocation.line,
      mutation: mutation,
      config: config,
      requiresDirectValueExpression: true
    ) {
      return anchored
    }
    if let anchored = swiftMutagenFindReturnedScalarValueSourceLocation(
      for: value,
      path: functionSourceLocation.path,
      preferredLine: functionSourceLocation.line,
      mutation: mutation,
      config: config
    ) {
      return anchored
    }
    if let anchored = swiftMutagenFindOrdinalScalarValueSourceLocation(
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

private func swiftMutagenFindOrdinalScalarValueSourceLocation(
  for value: StructInst,
  path: String,
  preferredLine: Int,
  mutation: SwiftMutagenMutation,
  config: SwiftMutagenConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard let ordinal = swiftMutagenScalarValueOrdinalAndCount(
    for: value,
    mutation: mutation,
    config: config
  ), ordinal.count <= 200 else {
    return nil
  }
  return swiftMutagenFindOrdinalValueExpressionSourceLocation(
    path: path,
    preferredLine: preferredLine,
    ordinal: ordinal.ordinal,
    expectedCount: ordinal.count,
    mutation: mutation,
    config: config
  )
}

private func swiftMutagenScalarValueOrdinalAndCount(
  for value: StructInst,
  mutation: SwiftMutagenMutation,
  config: SwiftMutagenConfig
) -> (ordinal: Int, count: Int)? {
  var ordinal = 0
  var count = 0
  var foundValue = false

  for block in value.parentFunction.blocks {
    for instruction in block.instructions {
      guard let candidate = instruction as? StructInst else {
        continue
      }
      let mutations = swiftMutagenScalarValueMutations(for: candidate, config: config)
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

private func swiftMutagenFindReturnedScalarValueSourceLocation(
  for value: StructInst,
  path: String,
  preferredLine: Int,
  mutation: SwiftMutagenMutation,
  config: SwiftMutagenConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard swiftMutagenScalarValueIsDirectReturnBranchValue(value),
        let ordinal = swiftMutagenReturnedScalarValueOrdinalAndCount(
          for: value,
          mutation: mutation,
          config: config
        ), ordinal.count <= 20 else {
    return nil
  }
  return swiftMutagenFindOrdinalExplicitReturnSourceLocation(
    path: path,
    preferredLine: preferredLine,
    ordinal: ordinal.ordinal,
    expectedCount: ordinal.count,
    mutation: mutation,
    config: config
  )
}

private func swiftMutagenScalarValueIsDirectReturnBranchValue(_ value: StructInst) -> Bool {
  for use in value.uses.ignoreDebugUses {
    guard let branch = use.instruction as? BranchInst,
          branch.targetBlock.terminator is ReturnInst else {
      continue
    }
    return true
  }
  return false
}

private func swiftMutagenReturnedScalarValueOrdinalAndCount(
  for value: StructInst,
  mutation: SwiftMutagenMutation,
  config: SwiftMutagenConfig
) -> (ordinal: Int, count: Int)? {
  var ordinal = 0
  var count = 0
  var foundValue = false

  for block in value.parentFunction.blocks {
    for instruction in block.instructions {
      guard let candidate = instruction as? StructInst,
            swiftMutagenScalarValueIsDirectReturnBranchValue(candidate) else {
        continue
      }
      let mutations = swiftMutagenScalarValueMutations(for: candidate, config: config)
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

private func swiftMutagenReturnBranchSourceLocation(
  for branch: BranchInst,
  mutation: SwiftMutagenMutation,
  config: SwiftMutagenConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  let functionSourceLocation = swiftMutagenFunctionSourceLocation(
    for: branch.parentFunction,
    config: config
  )
  if let fileNameAndPosition = branch.location.fileNameAndPosition {
    let path = fileNameAndPosition.path.string
    if let matchedPath = swiftMutagenIncludedSourcePath(path, config: config),
       let anchored = swiftMutagenFindReturnBranchSourceLocation(
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
    if let matchedPath = swiftMutagenIncludedSourcePath(path, config: config),
       let anchored = swiftMutagenFindReturnBranchSourceLocation(
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
    return swiftMutagenFindReturnBranchSourceLocation(
      for: branch,
      path: functionSourceLocation.path,
      preferredLine: functionSourceLocation.line,
      mutation: mutation,
      config: config
    )
  }
  return nil
}

private func swiftMutagenFindReturnBranchSourceLocation(
  for branch: BranchInst,
  path: String,
  preferredLine: Int,
  mutation: SwiftMutagenMutation,
  config: SwiftMutagenConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  if let exact = swiftMutagenFindUniqueExplicitReturnSourceLocation(
    path: path,
    preferredLine: preferredLine,
    mutation: mutation,
    config: config
  ) {
    return exact
  }
  guard let ordinal = swiftMutagenReturnBranchOrdinalAndCount(
    for: branch,
    mutation: mutation,
    config: config
  ), ordinal.count <= 40 else {
    return nil
  }
  return swiftMutagenFindOrdinalExplicitReturnSourceLocation(
    path: path,
    preferredLine: preferredLine,
    ordinal: ordinal.ordinal,
    expectedCount: ordinal.count,
    mutation: mutation,
    config: config
  )
}

private func swiftMutagenReturnBranchOrdinalAndCount(
  for branch: BranchInst,
  mutation: SwiftMutagenMutation,
  config: SwiftMutagenConfig
) -> (ordinal: Int, count: Int)? {
  var ordinal = 0
  var count = 0
  var foundBranch = false

  for block in branch.parentFunction.blocks {
    guard let candidate = block.terminator as? BranchInst else {
      continue
    }
    let mutations = swiftMutagenReturnBranchMutations(for: candidate, config: config)
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

private func swiftMutagenFindAssignmentValueSourceLocation(
  path: String,
  preferredLine: Int,
  mutation: SwiftMutagenMutation,
  config: SwiftMutagenConfig,
  targetNames: [String] = [],
  requiresDirectValueExpression: Bool = false
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard preferredLine > 0,
        let text = swiftMutagenRead(path) else {
    return nil
  }
  if let exact = swiftMutagenAssignmentValueSourceLocation(
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
  return swiftMutagenAssignmentValueSourceLocation(
    in: text,
    path: path,
    lineRange: firstLine...lastLine,
    mutation: mutation,
    config: config,
    targetNames: targetNames,
    requiresDirectValueExpression: requiresDirectValueExpression
  )
}

private func swiftMutagenFindScopedAssignmentValueSourceLocation(
  path: String,
  functionLine: Int,
  mutation: SwiftMutagenMutation,
  config: SwiftMutagenConfig,
  targetNames: [String],
  requiresDirectValueExpression: Bool
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard functionLine > 0,
        !targetNames.isEmpty,
        let text = swiftMutagenRead(path) else {
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
          let expression = swiftMutagenAssignmentValueExpression(
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
    swiftMutagenTrimPackageRoot(path, config: config),
    match.line,
    match.column,
    match.sourceOriginal,
    match.sourceMutated)
}

private func swiftMutagenFindScopedLocalBindingValueSourceLocation(
  path: String,
  functionLine: Int,
  mutation: SwiftMutagenMutation,
  config: SwiftMutagenConfig,
  targetNames: [String]
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard functionLine > 0,
        !targetNames.isEmpty,
        let text = swiftMutagenRead(path) else {
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
          let expression = swiftMutagenLocalBindingValueExpression(
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
    swiftMutagenTrimPackageRoot(path, config: config),
    match.line,
    match.column,
    match.sourceOriginal,
    match.sourceMutated)
}

private func swiftMutagenFindScopedLabeledAssignmentValueSourceLocation(
  path: String,
  functionLine: Int,
  mutation: SwiftMutagenMutation,
  config: SwiftMutagenConfig,
  targetNames: [String]
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard functionLine > 0,
        !targetNames.isEmpty,
        let text = swiftMutagenRead(path) else {
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
          swiftMutagenLineContainsAnyIdentifier(lineText, identifiers: targetNames),
          let expression = swiftMutagenStandaloneLabeledValueExpression(
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
    swiftMutagenTrimPackageRoot(path, config: config),
    match.line,
    match.column,
    match.sourceOriginal,
    match.sourceMutated)
}

private func swiftMutagenAssignmentValueSourceLocation(
  in text: String,
  path: String,
  lineRange: ClosedRange<Int>,
  mutation: SwiftMutagenMutation,
  config: SwiftMutagenConfig,
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
          let expression = swiftMutagenAssignmentValueExpression(
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
    swiftMutagenTrimPackageRoot(path, config: config),
    match.line,
    match.column,
    match.sourceOriginal,
    match.sourceMutated)
}

private func swiftMutagenFindOrdinalAssignmentValueSourceLocation(
  for store: StoreInst,
  path: String,
  preferredLine: Int,
  mutation: SwiftMutagenMutation,
  config: SwiftMutagenConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard let ordinal = swiftMutagenAssignmentValueOrdinalAndCount(
    for: store,
    mutation: mutation,
    config: config
  ), ordinal.count <= 200 else {
    return nil
  }
  return swiftMutagenFindOrdinalAssignmentValueSourceLocation(
    path: path,
    preferredLine: preferredLine,
    ordinal: ordinal.ordinal,
    expectedCount: ordinal.count,
    mutation: mutation,
    config: config
  )
}

private func swiftMutagenAssignmentValueOrdinalAndCount(
  for store: StoreInst,
  mutation: SwiftMutagenMutation,
  config: SwiftMutagenConfig
) -> (ordinal: Int, count: Int)? {
  var ordinal = 0
  var count = 0
  var foundStore = false

  for block in store.parentFunction.blocks {
    for instruction in block.instructions {
      guard let candidate = instruction as? StoreInst,
            swiftMutagenAssignmentStoreIsEligible(candidate) else {
        continue
      }
      let mutations = swiftMutagenAssignmentValueMutations(for: candidate, config: config)
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

private func swiftMutagenFindOrdinalAssignmentValueSourceLocation(
  path: String,
  preferredLine: Int,
  ordinal: Int,
  expectedCount: Int,
  mutation: SwiftMutagenMutation,
  config: SwiftMutagenConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard preferredLine > 0,
        ordinal > 0,
        ordinal <= expectedCount,
        expectedCount > 1,
        let text = swiftMutagenRead(path) else {
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
          let expression = swiftMutagenAssignmentValueExpression(
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
    swiftMutagenTrimPackageRoot(path, config: config),
    match.line,
    match.column,
    match.sourceOriginal,
    match.sourceMutated)
}

private func swiftMutagenValueApplySourceLocation(
  for apply: ApplyInst,
  mutation: SwiftMutagenMutation,
  config: SwiftMutagenConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  let functionSourceLocation = swiftMutagenFunctionSourceLocation(
    for: apply.parentFunction,
    config: config
  )
  if let fileNameAndPosition = apply.location.fileNameAndPosition {
    let path = fileNameAndPosition.path.string
    if let matchedPath = swiftMutagenIncludedSourcePath(path, config: config) {
      if let anchored = swiftMutagenFindValueExpressionSourceLocation(
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
        let anchored = swiftMutagenFindDescribedValueExpressionSourceLocation(
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
         let anchored = swiftMutagenFindOrdinalValueExpressionSourceLocation(
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
    if let anchored = swiftMutagenFindValueExpressionSourceLocation(
      for: apply,
      path: functionSourceLocation.path,
      preferredLine: functionSourceLocation.line,
      mutation: mutation,
      config: config
    ) {
      return anchored
    }
    if let anchored = swiftMutagenFindDescribedValueExpressionSourceLocation(
      for: apply,
      path: functionSourceLocation.path,
      functionLine: functionSourceLocation.line,
      locationDescription: apply.location.description,
      mutation: mutation,
      config: config
    ) {
      return anchored
    }
    if let anchored = swiftMutagenFindOrdinalValueExpressionSourceLocation(
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

private func swiftMutagenAssignmentValueSourceLocation(
  for store: StoreInst,
  mutation: SwiftMutagenMutation,
  config: SwiftMutagenConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  let targetNames = swiftMutagenUniqueAssignmentNames(
    swiftMutagenAssignmentDestinationNames(for: store) +
    swiftMutagenAssignmentSourceNames(for: store)
  )
  let functionSourceLocation = swiftMutagenFunctionSourceLocation(
    for: store.parentFunction,
    config: config
  )
  if let fileNameAndPosition = store.location.fileNameAndPosition {
    let path = fileNameAndPosition.path.string
    if let matchedPath = swiftMutagenIncludedSourcePath(path, config: config) {
      if let anchored = swiftMutagenFindAssignmentValueSourceLocation(
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
         let anchored = swiftMutagenFindAssignmentValueSourceLocation(
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
         let anchored = swiftMutagenFindOrdinalAssignmentValueSourceLocation(
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

  if let functionSourceLocation {
    if let anchored = swiftMutagenFindScopedAssignmentValueSourceLocation(
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
       let anchored = swiftMutagenFindScopedAssignmentValueSourceLocation(
         path: functionSourceLocation.path,
         functionLine: functionSourceLocation.line,
         mutation: mutation,
         config: config,
         targetNames: targetNames,
         requiresDirectValueExpression: false
       ) {
      return anchored
    }
    if let anchored = swiftMutagenFindStoreSnippetAssignmentValueSourceLocation(
      for: store,
      path: functionSourceLocation.path,
      functionLine: functionSourceLocation.line,
      mutation: mutation,
      config: config,
      targetNames: targetNames
    ) {
      return anchored
    }
    if let anchored = swiftMutagenFindStoreUsageSnippetAssignmentValueSourceLocation(
      for: store,
      path: functionSourceLocation.path,
      functionLine: functionSourceLocation.line,
      mutation: mutation,
      config: config,
      targetNames: targetNames
    ) {
      return anchored
    }
    if let anchored = swiftMutagenFindAssignmentValueSourceLocation(
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
       let anchored = swiftMutagenFindAssignmentValueSourceLocation(
         path: functionSourceLocation.path,
         preferredLine: functionSourceLocation.line,
         mutation: mutation,
         config: config,
         targetNames: targetNames,
         requiresDirectValueExpression: false
       ) {
      return anchored
    }
    if let anchored = swiftMutagenFindOrdinalAssignmentValueSourceLocation(
      for: store,
      path: functionSourceLocation.path,
      preferredLine: functionSourceLocation.line,
      mutation: mutation,
      config: config
    ) {
      return anchored
    }
    if let anchored = swiftMutagenFindScopedLocalBindingValueSourceLocation(
      path: functionSourceLocation.path,
      functionLine: functionSourceLocation.line,
      mutation: mutation,
      config: config,
      targetNames: targetNames
    ) {
      return anchored
    }
    if let anchored = swiftMutagenFindScopedLabeledAssignmentValueSourceLocation(
      path: functionSourceLocation.path,
      functionLine: functionSourceLocation.line,
      mutation: mutation,
      config: config,
      targetNames: targetNames
    ) {
      return anchored
    }
  }
  return nil
}

private func swiftMutagenFindStoreSnippetAssignmentValueSourceLocation(
  for store: StoreInst,
  path: String,
  functionLine: Int,
  mutation: SwiftMutagenMutation,
  config: SwiftMutagenConfig,
  targetNames: [String]
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard functionLine > 0,
        !targetNames.isEmpty,
        let expectedExpression = swiftMutagenStoreLocationAssignedExpression(store.location.description),
        let text = swiftMutagenRead(path) else {
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
          let expression = swiftMutagenAssignmentValueExpression(
            lineText,
            mutation: mutation,
            targetNames: targetNames,
            requiresDirectValueExpression: false
          ),
          expression.sourceOriginal == expectedExpression else {
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
    swiftMutagenTrimPackageRoot(path, config: config),
    match.line,
    match.column,
    match.sourceOriginal,
    match.sourceMutated)
}

private func swiftMutagenFindStoreUsageSnippetAssignmentValueSourceLocation(
  for store: StoreInst,
  path: String,
  functionLine: Int,
  mutation: SwiftMutagenMutation,
  config: SwiftMutagenConfig,
  targetNames: [String]
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard functionLine > 0,
        !targetNames.isEmpty,
        let snippet = swiftMutagenQuotedSourceSnippetPrefix(store.location.description),
        let comparison = swiftMutagenStoreUsageComparisonSnippet(snippet),
        let text = swiftMutagenRead(path) else {
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
      guard let column = swiftMutagenLineColumn(
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
        swiftMutagenImplicitReturnSourceMutation(for: mutation)))
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
    swiftMutagenTrimPackageRoot(path, config: config),
    match.line,
    match.column,
    match.sourceOriginal,
    match.sourceMutated)
}

private func swiftMutagenStoreLocationAssignedExpression(_ description: String) -> String? {
  let bytes = Array(description.utf8)
  guard bytes.count > 3,
        bytes[0] == 34,
        bytes[1] == 61 else {
    return nil
  }

  let expressionStart = swiftMutagenSkipHorizontalWhitespace(bytes, from: 2)
  var expressionEnd = expressionStart
  while expressionEnd < bytes.count {
    switch bytes[expressionEnd] {
    case 10, 13, 34:
      let trimmedEnd = swiftMutagenTrimTrailingHorizontalWhitespace(bytes, end: expressionEnd)
      guard expressionStart < trimmedEnd else {
        return nil
      }
      return String(decoding: bytes[expressionStart..<trimmedEnd], as: UTF8.self)
    default:
      expressionEnd += 1
    }
  }
  let trimmedEnd = swiftMutagenTrimTrailingHorizontalWhitespace(bytes, end: expressionEnd)
  guard expressionStart < trimmedEnd else {
    return nil
  }
  return String(decoding: bytes[expressionStart..<trimmedEnd], as: UTF8.self)
}

private func swiftMutagenStoreUsageComparisonSnippet(_ snippet: String) -> (operatorText: String, rhsText: String)? {
  let bytes = Array(snippet.utf8)
  var index = swiftMutagenSkipHorizontalWhitespace(bytes, from: 0)
  guard index < bytes.count else {
    return nil
  }

  let operators = ["!=", "==", ">=", "<=", ">", "<"]
  var matchedOperator: String?
  for operatorText in operators {
    if swiftMutagenASCIIHasExactPrefix(bytes, start: index, prefix: operatorText) {
      matchedOperator = operatorText
      index += operatorText.utf8.count
      break
    }
  }
  guard let operatorText = matchedOperator else {
    return nil
  }

  index = swiftMutagenSkipHorizontalWhitespace(bytes, from: index)
  let rhsStart = index
  while index < bytes.count && !swiftMutagenIsHorizontalWhitespace(bytes[index]) {
    index += 1
  }
  guard rhsStart < index else {
    return nil
  }
  let rhsText = String(decoding: bytes[rhsStart..<index], as: UTF8.self)
  return (operatorText, rhsText)
}

private func swiftMutagenLineColumn(
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
    if swiftMutagenIdentifierTokenMatches(bytes, index: index, end: bytes.count, tokenBytes: targetBytes) {
      var cursor = swiftMutagenSkipHorizontalWhitespace(bytes, from: index + targetBytes.count)
      if swiftMutagenBytesMatch(bytes, start: cursor, pattern: operatorBytes) {
        cursor = swiftMutagenSkipHorizontalWhitespace(bytes, from: cursor + operatorBytes.count)
        if swiftMutagenBytesMatch(bytes, start: cursor, pattern: rhsBytes) {
          return index + 1
        }
      }
    }
    index += 1
  }
  return nil
}

private func swiftMutagenIdentifierTokenMatches(
  _ bytes: [UInt8],
  index: Int,
  end: Int,
  tokenBytes: [UInt8]
) -> Bool {
  guard index + tokenBytes.count <= end else {
    return false
  }
  if index > 0 && swiftMutagenIsIdentifierByte(bytes[index - 1]) {
    return false
  }
  let after = index + tokenBytes.count
  if after < end && swiftMutagenIsIdentifierByte(bytes[after]) {
    return false
  }
  return swiftMutagenBytesMatch(bytes, start: index, pattern: tokenBytes)
}

private func swiftMutagenBytesMatch(_ bytes: [UInt8], start: Int, pattern: [UInt8]) -> Bool {
  guard start >= 0,
        start + pattern.count <= bytes.count else {
    return false
  }
  for offset in 0..<pattern.count where bytes[start + offset] != pattern[offset] {
    return false
  }
  return true
}

private func swiftMutagenQuotedSourceSnippetPrefix(_ description: String) -> String? {
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

  let trimmedEnd = swiftMutagenTrimTrailingHorizontalWhitespace(bytes, end: end)
  guard trimmedEnd > 1 else {
    return nil
  }
  return String(decoding: bytes[1..<trimmedEnd], as: UTF8.self)
}

private func swiftMutagenFunctionSourceLocation(
  for function: Function,
  config: SwiftMutagenConfig
) -> (path: String, line: Int)? {
  let location = function.location.description
  for path in swiftMutagenSwiftSourcePaths(config: config) {
    guard location.contains(path),
          let line = swiftMutagenPreferredLine(in: location, path: path) else {
      continue
    }
    return (path, line)
  }
  return nil
}

private func swiftMutagenFindValueExpressionSourceLocation(
  for apply: ApplyInst,
  path: String,
  preferredLine: Int,
  mutation: SwiftMutagenMutation,
  config: SwiftMutagenConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  if let anchored = swiftMutagenFindAssignmentValueSourceLocation(
    path: path,
    preferredLine: preferredLine,
    mutation: mutation,
    config: config
  ) {
    return anchored
  }
  if let anchored = swiftMutagenFindLabeledValueExpressionSourceLocation(
    path: path,
    preferredLine: preferredLine,
    mutation: mutation,
    config: config
  ) {
    return anchored
  }
  if let anchored = swiftMutagenFindStandaloneValueExpressionSourceLocation(
    path: path,
    preferredLine: preferredLine,
    mutation: mutation,
    config: config
  ) {
    return anchored
  }
  if let anchored = swiftMutagenFindUniqueExplicitReturnSourceLocation(
    path: path,
    preferredLine: preferredLine,
    mutation: mutation,
    config: config
  ) {
    return anchored
  }
  if let anchored = swiftMutagenFindUniqueImplicitReturnSourceLocation(
    path: path,
    preferredLine: preferredLine,
    mutation: mutation,
    config: config
  ) {
    return anchored
  }
  if let anchored = swiftMutagenFindCalleeOrdinalValueExpressionSourceLocation(
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

private func swiftMutagenFindOrdinalValueExpressionSourceLocation(
  for apply: ApplyInst,
  path: String,
  preferredLine: Int,
  mutation: SwiftMutagenMutation,
  config: SwiftMutagenConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard let ordinal = swiftMutagenValueApplyOrdinalAndCount(
    for: apply,
    mutation: mutation,
    config: config
  ), ordinal.count <= 200 else {
    return nil
  }
  return swiftMutagenFindOrdinalValueExpressionSourceLocation(
    path: path,
    preferredLine: preferredLine,
    ordinal: ordinal.ordinal,
    expectedCount: ordinal.count,
    mutation: mutation,
    config: config
  )
}

private func swiftMutagenValueApplyOrdinalAndCount(
  for apply: ApplyInst,
  mutation: SwiftMutagenMutation,
  config: SwiftMutagenConfig
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
      let mutations = swiftMutagenValueReplacementMutations(
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

private func swiftMutagenFindOrdinalValueExpressionSourceLocation(
  path: String,
  preferredLine: Int,
  ordinal: Int,
  expectedCount: Int,
  mutation: SwiftMutagenMutation,
  config: SwiftMutagenConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard preferredLine > 0,
        ordinal > 0,
        ordinal <= expectedCount,
        expectedCount > 1,
        let text = swiftMutagenRead(path) else {
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
          let expression = swiftMutagenOrdinalValueExpression(lineText, mutation: mutation) else {
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
    swiftMutagenTrimPackageRoot(path, config: config),
    match.line,
    match.column,
    match.sourceOriginal,
    match.sourceMutated)
}

private func swiftMutagenFindCalleeOrdinalValueExpressionSourceLocation(
  for apply: ApplyInst,
  path: String,
  preferredLine: Int,
  mutation: SwiftMutagenMutation,
  config: SwiftMutagenConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  let identifiers = swiftMutagenSourceExpressionIdentifiers(for: apply)
  guard !identifiers.isEmpty,
        let ordinal = swiftMutagenValueApplyOrdinal(for: apply, matchingAnyOf: identifiers, config: config),
        let text = swiftMutagenRead(path) else {
    return nil
  }

  let candidates = swiftMutagenCalleeExpressionSourceCandidates(
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

private func swiftMutagenFindStandaloneValueExpressionSourceLocation(
  path: String,
  preferredLine: Int,
  mutation: SwiftMutagenMutation,
  config: SwiftMutagenConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard preferredLine > 0,
        let sourceLine = swiftMutagenAbsoluteSourceLine(path: path, line: preferredLine),
        let expression = swiftMutagenStandaloneValueExpression(sourceLine, mutation: mutation) else {
    return nil
  }
  return (
    swiftMutagenTrimPackageRoot(path, config: config),
    preferredLine,
    expression.column,
    expression.sourceOriginal,
    expression.sourceMutated)
}

private func swiftMutagenValueApplyOrdinal(
  for apply: ApplyInst,
  matchingAnyOf identifiers: [String],
  config: SwiftMutagenConfig
) -> Int? {
  var ordinal = 0
  for block in apply.parentFunction.blocks {
    for instruction in block.instructions {
      guard let candidate = instruction as? ApplyInst,
            !candidate.type.isVoid,
            !swiftMutagenValueReplacementMutations(
              for: candidate,
              valueType: candidate.type,
              config: config
            ).isEmpty,
            swiftMutagenSourceCalleeIdentifiers(for: candidate).contains(where: { identifiers.contains($0) }) else {
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

private func swiftMutagenCalleeExpressionSourceCandidates(
  in text: String,
  path: String,
  preferredLine: Int,
  identifiers: [String],
  mutation: SwiftMutagenMutation,
  config: SwiftMutagenConfig
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
          swiftMutagenSourceLineContainsExpressionIdentifier(lineText, identifiers: identifiers),
          let expression = swiftMutagenValueExpressionOnLine(
            lineText,
            identifiers: identifiers,
            mutation: mutation
          ) else {
      return
    }
    candidates.append((
      swiftMutagenTrimPackageRoot(path, config: config),
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

private func swiftMutagenFindDescribedValueExpressionSourceLocation(
  for apply: ApplyInst,
  path: String,
  functionLine: Int,
  locationDescription: String,
  mutation: SwiftMutagenMutation,
  config: SwiftMutagenConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard functionLine > 0,
        let snippet = swiftMutagenQuotedSourceSnippetPrefix(locationDescription),
        swiftMutagenDescribedValueSnippetLooksMappable(snippet),
        let text = swiftMutagenRead(path) else {
    return nil
  }

  let prefixes = swiftMutagenDescribedValueSnippetPrefixes(snippet)
  guard !prefixes.isEmpty else {
    return nil
  }

  let identifiers = swiftMutagenSourceExpressionIdentifiers(for: apply)
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
    let start = swiftMutagenSkipHorizontalWhitespace(bytes, from: 0)
    let end = swiftMutagenTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
    guard start < end else {
      return
    }

    for prefix in prefixes {
      guard let matchStart = swiftMutagenASCIIIndex(bytes, start: start, end: end, pattern: prefix),
            let expression = swiftMutagenDescribedValueExpression(
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
    swiftMutagenTrimPackageRoot(path, config: config),
    match.line,
    match.column,
    match.sourceOriginal,
    match.sourceMutated)
}

private func swiftMutagenDescribedValueSnippetLooksMappable(_ snippet: String) -> Bool {
  let bytes = Array(snippet.utf8)
  var start = swiftMutagenSkipHorizontalWhitespace(bytes, from: 0)
  guard start < bytes.count else {
    return false
  }
  if start + 1 < bytes.count
      && (bytes[start] == 38 || bytes[start] == 124)
      && bytes[start + 1] == bytes[start] {
    start = swiftMutagenSkipHorizontalWhitespace(bytes, from: start + 2)
  }
  if start < bytes.count && bytes[start] == 33 {
    start = swiftMutagenSkipHorizontalWhitespace(bytes, from: start + 1)
  }
  guard start < bytes.count,
        !swiftMutagenASCIIHasExactPrefix(bytes, start: start, prefix: "()") else {
    return false
  }
  let first = bytes[start]
  return (first >= 65 && first <= 90) || (first >= 97 && first <= 122) || first == 95
}

private func swiftMutagenDescribedValueSnippetPrefixes(_ snippet: String) -> [String] {
  let bytes = Array(snippet.utf8)
  let start = swiftMutagenSkipHorizontalWhitespace(bytes, from: 0)
  let end = swiftMutagenTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  guard start < end else {
    return []
  }

  var prefixes: [String] = []
  func appendPrefix(start: Int) {
    let trimmedStart = swiftMutagenSkipHorizontalWhitespace(bytes, from: start)
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

private func swiftMutagenDescribedValueExpression(
  bytes: [UInt8],
  matchStart: Int,
  lineEnd: Int,
  identifiers: [String],
  mutation: SwiftMutagenMutation
) -> (column: Int, sourceOriginal: String, sourceMutated: String)? {
  let expressionSearchStart = swiftMutagenDescribedValueExpressionSearchStart(
    bytes: bytes,
    matchStart: matchStart,
    lineEnd: lineEnd
  )

  for identifier in identifiers {
    guard let tokenRange = swiftMutagenFindSourceIdentifier(
      identifier,
      in: bytes,
      start: expressionSearchStart,
      end: lineEnd
    ),
    let expressionRange = swiftMutagenSourceExpressionRange(
      around: tokenRange,
      in: bytes,
      lineEnd: lineEnd
    ),
    swiftMutagenReturnValueIsEligible(bytes: bytes, start: expressionRange.start, mutation: mutation) else {
      continue
    }
    return swiftMutagenDescribedValueExpressionResult(
      bytes: bytes,
      expressionRange: expressionRange,
      mutation: mutation
    )
  }

  guard let tokenRange = swiftMutagenFirstCallLikeSourceIdentifier(
    bytes: bytes,
    start: expressionSearchStart,
    end: lineEnd
  ),
  let expressionRange = swiftMutagenSourceExpressionRange(
    around: tokenRange,
    in: bytes,
    lineEnd: lineEnd
  ),
  swiftMutagenReturnValueIsEligible(bytes: bytes, start: expressionRange.start, mutation: mutation) else {
    return nil
  }
  return swiftMutagenDescribedValueExpressionResult(
    bytes: bytes,
    expressionRange: expressionRange,
    mutation: mutation
  )
}

private func swiftMutagenDescribedValueExpressionSearchStart(
  bytes: [UInt8],
  matchStart: Int,
  lineEnd: Int
) -> Int {
  var start = swiftMutagenSkipHorizontalWhitespace(bytes, from: matchStart)
  if start + 1 < lineEnd
      && (bytes[start] == 38 || bytes[start] == 124)
      && bytes[start + 1] == bytes[start] {
    start = swiftMutagenSkipHorizontalWhitespace(bytes, from: start + 2)
  }
  if start < lineEnd && bytes[start] == 33 {
    start = swiftMutagenSkipHorizontalWhitespace(bytes, from: start + 1)
  }
  return start
}

private func swiftMutagenDescribedValueExpressionResult(
  bytes: [UInt8],
  expressionRange: (start: Int, end: Int),
  mutation: SwiftMutagenMutation
) -> (column: Int, sourceOriginal: String, sourceMutated: String) {
  let sourceOriginal = String(decoding: bytes[expressionRange.start..<expressionRange.end], as: UTF8.self)
  return (
    expressionRange.start + 1,
    sourceOriginal,
    swiftMutagenImplicitReturnSourceMutation(for: mutation))
}

private func swiftMutagenFirstCallLikeSourceIdentifier(
  bytes: [UInt8],
  start: Int,
  end: Int
) -> (start: Int, end: Int)? {
  var index = start
  while index < end {
    guard swiftMutagenIsASCIIIdentifierStart(bytes[index]) else {
      index += 1
      continue
    }
    let tokenStart = index
    index += 1
    while index < end && swiftMutagenIsASCIILetterNumberOrUnderscore(bytes[index]) {
      index += 1
    }
    let suffixStart = swiftMutagenSkipHorizontalWhitespace(bytes, from: index)
    if suffixStart < end && (bytes[suffixStart] == 40 || bytes[suffixStart] == 123) {
      return (tokenStart, index)
    }
  }
  return nil
}

private func swiftMutagenValueExpressionOnLine(
  _ line: String,
  identifiers: [String],
  mutation: SwiftMutagenMutation
) -> (column: Int, sourceOriginal: String, sourceMutated: String)? {
  if let expression = swiftMutagenOrdinalValueExpression(line, mutation: mutation) {
    return expression
  }
  if let expression = swiftMutagenIdentifierValueExpression(line, identifiers: identifiers, mutation: mutation) {
    return expression
  }
  return nil
}

private func swiftMutagenOrdinalValueExpression(
  _ line: String,
  mutation: SwiftMutagenMutation
) -> (column: Int, sourceOriginal: String, sourceMutated: String)? {
  if let expression = swiftMutagenAssignmentValueExpression(line, mutation: mutation) {
    return expression
  }
  if let expression = swiftMutagenStandaloneLabeledValueExpression(line, mutation: mutation) {
    return expression
  }
  if let expression = swiftMutagenStandaloneValueExpression(line, mutation: mutation) {
    return expression
  }
  if let expression = swiftMutagenExplicitReturnValueExpression(line, mutation: mutation) {
    return expression
  }
  return nil
}

private func swiftMutagenExplicitReturnValueExpression(
  _ line: String,
  mutation: SwiftMutagenMutation
) -> (column: Int, sourceOriginal: String, sourceMutated: String)? {
  let bytes = Array(line.utf8)
  let lineStart = swiftMutagenSkipHorizontalWhitespace(bytes, from: 0)
  let lineEnd = swiftMutagenTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  guard lineStart < lineEnd,
        swiftMutagenASCIIHasExactPrefix(bytes, start: lineStart, prefix: "return ") else {
    return nil
  }

  let valueStart = swiftMutagenSkipHorizontalWhitespace(bytes, from: lineStart + 7)
  guard valueStart < lineEnd,
        swiftMutagenReturnValueIsEligible(bytes: bytes, start: valueStart, mutation: mutation) else {
    return nil
  }

  let sourceOriginal = String(decoding: bytes[valueStart..<lineEnd], as: UTF8.self)
  return (
    valueStart + 1,
    sourceOriginal,
    swiftMutagenImplicitReturnSourceMutation(for: mutation))
}

private func swiftMutagenSourceExpressionIdentifiers(for apply: ApplyInst) -> [String] {
  swiftMutagenSourceCalleeIdentifiers(for: apply).filter(swiftMutagenIdentifierLooksLikeSourceExpression)
}

private func swiftMutagenSourceCalleeIdentifiers(for apply: ApplyInst) -> [String] {
  guard let name = apply.referencedFunction?.name.string else {
    return []
  }
  return swiftMutagenMangledIdentifiers(in: name).filter { identifier in
    identifier.count >= 3 && !identifier.hasPrefix("__")
  }
}

private func swiftMutagenMangledIdentifiers(in name: String) -> [String] {
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
          swiftMutagenBytesAreIdentifier(bytes, start: cursor, end: cursor + length) else {
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

private func swiftMutagenIdentifierLooksLikeSourceExpression(_ identifier: String) -> Bool {
  guard let first = identifier.utf8.first else {
    return false
  }
  return (first >= 97 && first <= 122) || first == 95
}

private func swiftMutagenBytesAreIdentifier(_ bytes: [UInt8], start: Int, end: Int) -> Bool {
  guard start < end else {
    return false
  }
  for index in start..<end {
    if !swiftMutagenIsASCIILetterNumberOrUnderscore(bytes[index]) {
      return false
    }
  }
  return true
}

private func swiftMutagenSourceLineContainsExpressionIdentifier(_ line: String, identifiers: [String]) -> Bool {
  let bytes = Array(line.utf8)
  let start = swiftMutagenSkipHorizontalWhitespace(bytes, from: 0)
  let end = swiftMutagenTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  guard start < end else {
    return false
  }
  for identifier in identifiers where swiftMutagenSourceLineContainsExpressionIdentifier(
    bytes,
    start: start,
    end: end,
    identifier: identifier
  ) {
    return true
  }
  return false
}

private func swiftMutagenSourceLineContainsExpressionIdentifier(
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
      if !swiftMutagenIsASCIILetterNumberOrUnderscore(before)
          && !swiftMutagenIsASCIILetterNumberOrUnderscore(after) {
        let callStart = swiftMutagenSkipHorizontalWhitespace(bytes, from: tokenEnd)
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

private func swiftMutagenIdentifierValueExpression(
  _ line: String,
  identifiers: [String],
  mutation: SwiftMutagenMutation
) -> (column: Int, sourceOriginal: String, sourceMutated: String)? {
  let bytes = Array(line.utf8)
  let lineStart = swiftMutagenSkipHorizontalWhitespace(bytes, from: 0)
  let lineEnd = swiftMutagenTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  guard lineStart < lineEnd else {
    return nil
  }

  for identifier in identifiers {
    guard let tokenRange = swiftMutagenFindSourceIdentifier(
      identifier,
      in: bytes,
      start: lineStart,
      end: lineEnd
    ),
    let expressionRange = swiftMutagenSourceExpressionRange(
      around: tokenRange,
      in: bytes,
      lineEnd: lineEnd
    ),
    swiftMutagenReturnValueIsEligible(bytes: bytes, start: expressionRange.start, mutation: mutation) else {
      continue
    }
    let sourceOriginal = String(decoding: bytes[expressionRange.start..<expressionRange.end], as: UTF8.self)
    return (
      expressionRange.start + 1,
      sourceOriginal,
      swiftMutagenImplicitReturnSourceMutation(for: mutation))
  }
  return nil
}

private func swiftMutagenLineContainsAnyIdentifier(_ line: String, identifiers: [String]) -> Bool {
  let bytes = Array(line.utf8)
  let start = swiftMutagenSkipHorizontalWhitespace(bytes, from: 0)
  let end = swiftMutagenTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  guard start < end else {
    return false
  }
  for identifier in identifiers where swiftMutagenFindSourceIdentifier(identifier, in: bytes, start: start, end: end) != nil {
    return true
  }
  return false
}

private func swiftMutagenFindSourceIdentifier(
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
      if !swiftMutagenIsASCIILetterNumberOrUnderscore(before)
          && !swiftMutagenIsASCIILetterNumberOrUnderscore(after) {
        return (index, tokenEnd)
      }
    }
    index += 1
  }
  return nil
}

private func swiftMutagenSourceExpressionRange(
  around tokenRange: (start: Int, end: Int),
  in bytes: [UInt8],
  lineEnd: Int
) -> (start: Int, end: Int)? {
  var expressionStart = tokenRange.start
  while expressionStart > 0 && swiftMutagenIsSourceExpressionPrefixByte(bytes[expressionStart - 1]) {
    expressionStart -= 1
  }

  let suffixStart = swiftMutagenSkipHorizontalWhitespace(bytes, from: tokenRange.end)
  if suffixStart < lineEnd && bytes[suffixStart] == 40 {
    guard let callEnd = swiftMutagenBalancedExpressionEnd(
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
    guard let closureEnd = swiftMutagenBalancedExpressionEnd(
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

private func swiftMutagenIsSourceExpressionPrefixByte(_ byte: UInt8) -> Bool {
  swiftMutagenIsASCIILetterNumberOrUnderscore(byte) || byte == 46 || byte == 63 || byte == 33
}

private func swiftMutagenBalancedExpressionEnd(
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

private func swiftMutagenFindLabeledValueExpressionSourceLocation(
  path: String,
  preferredLine: Int,
  mutation: SwiftMutagenMutation,
  config: SwiftMutagenConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard preferredLine > 0,
        let text = swiftMutagenRead(path) else {
    return nil
  }

  if let exact = swiftMutagenLabeledValueExpressionSourceLocation(
    in: text,
    path: path,
    lineRange: preferredLine...preferredLine,
    mutation: mutation,
    config: config
  ) {
    return exact
  }

  let firstLine = preferredLine > 2 ? preferredLine - 2 : 1
  return swiftMutagenLabeledValueExpressionSourceLocation(
    in: text,
    path: path,
    lineRange: firstLine...(preferredLine + 24),
    mutation: mutation,
    config: config
  )
}

private func swiftMutagenLabeledValueExpressionSourceLocation(
  in text: String,
  path: String,
  lineRange: ClosedRange<Int>,
  mutation: SwiftMutagenMutation,
  config: SwiftMutagenConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  var matches: [(line: Int, column: Int, sourceOriginal: String, sourceMutated: String)] = []
  var currentLine = 1
  var lineStart = text.startIndex
  var index = text.startIndex

  func inspectLine(_ lineText: String, line: Int) {
    guard lineRange.contains(line),
          matches.count < 2,
          let expression = swiftMutagenStandaloneLabeledValueExpression(lineText, mutation: mutation) else {
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
    swiftMutagenTrimPackageRoot(path, config: config),
    match.line,
    match.column,
    match.sourceOriginal,
    match.sourceMutated)
}

private func swiftMutagenStandaloneLabeledValueExpression(
  _ line: String,
  mutation: SwiftMutagenMutation,
  requiresCallExpression: Bool = true
) -> (column: Int, sourceOriginal: String, sourceMutated: String)? {
  let bytes = Array(line.utf8)
  let lineStart = swiftMutagenSkipHorizontalWhitespace(bytes, from: 0)
  let lineEnd = swiftMutagenTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  guard lineStart < lineEnd,
        !swiftMutagenLineStartsWithAssignmentReturnBlockedPrefix(bytes: bytes, start: lineStart),
        swiftMutagenSourceLineLooksLikeArgumentLabel(bytes: bytes, start: lineStart, end: lineEnd),
        let colon = swiftMutagenFirstLabeledArgumentSeparator(bytes: bytes, start: lineStart, end: lineEnd) else {
    return nil
  }

  let valueStart = swiftMutagenSkipHorizontalWhitespace(bytes, from: colon + 1)
  var valueEnd = lineEnd
  if valueEnd > valueStart && bytes[valueEnd - 1] == 44 {
    valueEnd = swiftMutagenTrimTrailingHorizontalWhitespace(bytes, end: valueEnd - 1)
  }
  guard valueStart < valueEnd,
        swiftMutagenLabeledArgumentRHSLooksLikeValueExpression(bytes: bytes, start: valueStart, end: valueEnd),
        (!requiresCallExpression || swiftMutagenLabeledArgumentRHSLooksLikeCallExpression(bytes: bytes, start: valueStart, end: valueEnd)),
        swiftMutagenReturnValueIsEligible(bytes: bytes, start: valueStart, mutation: mutation) else {
    return nil
  }

  let sourceOriginal = String(decoding: bytes[valueStart..<valueEnd], as: UTF8.self)
  return (
    valueStart + 1,
    sourceOriginal,
    swiftMutagenImplicitReturnSourceMutation(for: mutation))
}

private func swiftMutagenStandaloneValueExpression(
  _ line: String,
  mutation: SwiftMutagenMutation
) -> (column: Int, sourceOriginal: String, sourceMutated: String)? {
  let bytes = Array(line.utf8)
  let lineStart = swiftMutagenSkipHorizontalWhitespace(bytes, from: 0)
  let lineEnd = swiftMutagenTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  guard lineStart < lineEnd,
        swiftMutagenLineLooksLikeImplicitReturnExpression(bytes: bytes, start: lineStart, end: lineEnd),
        !swiftMutagenLineLooksLikeImplicitReturnContinuation(bytes: bytes, start: lineStart),
        swiftMutagenReturnValueIsEligible(bytes: bytes, start: lineStart, mutation: mutation) else {
    return nil
  }

  let sourceOriginal = String(decoding: bytes[lineStart..<lineEnd], as: UTF8.self)
  return (
    lineStart + 1,
    sourceOriginal,
    swiftMutagenImplicitReturnSourceMutation(for: mutation))
}

private func swiftMutagenAssignmentValueExpression(
  _ line: String,
  mutation: SwiftMutagenMutation,
  targetNames: [String] = [],
  requiresDirectValueExpression: Bool = false
) -> (column: Int, sourceOriginal: String, sourceMutated: String)? {
  let bytes = Array(line.utf8)
  let lineStart = swiftMutagenSkipHorizontalWhitespace(bytes, from: 0)
  let lineEnd = swiftMutagenTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  guard lineStart < lineEnd,
        !swiftMutagenLineStartsWithAssignmentReturnBlockedPrefix(bytes: bytes, start: lineStart) else {
    return nil
  }

  guard let equals = swiftMutagenFirstAssignmentOperator(bytes: bytes, start: lineStart, end: lineEnd) else {
    return swiftMutagenLabeledArgumentValueExpression(
      bytes: bytes,
      lineStart: lineStart,
      lineEnd: lineEnd,
      mutation: mutation,
      targetNames: targetNames,
      requiresDirectValueExpression: requiresDirectValueExpression
    )
  }

  guard swiftMutagenAssignmentLeftHandSideMatchesTargetNames(
    bytes: bytes,
    start: lineStart,
    end: equals,
    targetNames: targetNames
  ) else {
    return nil
  }

  let valueStart = swiftMutagenSkipHorizontalWhitespace(bytes, from: equals + 1)
  var valueEnd = lineEnd
  if valueEnd > valueStart && bytes[valueEnd - 1] == 44 {
    valueEnd = swiftMutagenTrimTrailingHorizontalWhitespace(bytes, end: valueEnd - 1)
  }
  guard valueStart < valueEnd,
        swiftMutagenAssignmentValueRHSIsDirectValueExpression(
          bytes: bytes,
          start: valueStart,
          end: valueEnd,
          isRequired: requiresDirectValueExpression
        ),
        swiftMutagenReturnValueIsEligible(bytes: bytes, start: valueStart, mutation: mutation) else {
    return nil
  }

  let sourceOriginal = String(decoding: bytes[valueStart..<valueEnd], as: UTF8.self)
  return (
    valueStart + 1,
    sourceOriginal,
    swiftMutagenImplicitReturnSourceMutation(for: mutation))
}

private func swiftMutagenLabeledArgumentValueExpression(
  bytes: [UInt8],
  lineStart: Int,
  lineEnd: Int,
  mutation: SwiftMutagenMutation,
  targetNames: [String],
  requiresDirectValueExpression: Bool
) -> (column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard !targetNames.isEmpty,
        let colon = swiftMutagenFirstLabeledArgumentSeparator(bytes: bytes, start: lineStart, end: lineEnd),
        swiftMutagenAssignmentLeftHandSideMatchesTargetNames(
          bytes: bytes,
          start: lineStart,
          end: colon,
          targetNames: targetNames
        ) else {
    return nil
  }

  let valueStart = swiftMutagenSkipHorizontalWhitespace(bytes, from: colon + 1)
  var valueEnd = lineEnd
  if valueEnd > valueStart && bytes[valueEnd - 1] == 44 {
    valueEnd = swiftMutagenTrimTrailingHorizontalWhitespace(bytes, end: valueEnd - 1)
  }
  guard valueStart < valueEnd,
        swiftMutagenLabeledArgumentRHSLooksLikeValueExpression(bytes: bytes, start: valueStart, end: valueEnd),
        swiftMutagenAssignmentValueRHSIsDirectValueExpression(
          bytes: bytes,
          start: valueStart,
          end: valueEnd,
          isRequired: requiresDirectValueExpression
        ),
        swiftMutagenReturnValueIsEligible(bytes: bytes, start: valueStart, mutation: mutation) else {
    return nil
  }

  let sourceOriginal = String(decoding: bytes[valueStart..<valueEnd], as: UTF8.self)
  return (
    valueStart + 1,
    sourceOriginal,
    swiftMutagenImplicitReturnSourceMutation(for: mutation))
}

private func swiftMutagenLocalBindingValueExpression(
  _ line: String,
  mutation: SwiftMutagenMutation,
  targetNames: [String]
) -> (column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard !targetNames.isEmpty else {
    return nil
  }
  let bytes = Array(line.utf8)
  let lineStart = swiftMutagenSkipHorizontalWhitespace(bytes, from: 0)
  let lineEnd = swiftMutagenTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  guard lineStart < lineEnd,
        !swiftMutagenASCIIHasPrefix(bytes, start: lineStart, prefix: "//") else {
    return nil
  }

  var matches: [(column: Int, name: String)] = []
  var index = lineStart
  while index < lineEnd {
    if swiftMutagenLocalBindingTokenMatches(bytes: bytes, index: index, end: lineEnd, token: "let")
        || swiftMutagenLocalBindingTokenMatches(bytes: bytes, index: index, end: lineEnd, token: "var") {
      let nameStart = swiftMutagenSkipHorizontalWhitespace(bytes, from: index + 3)
      if nameStart < lineEnd && swiftMutagenIsIdentifierStartByte(bytes[nameStart]) {
        var nameEnd = nameStart + 1
        while nameEnd < lineEnd && swiftMutagenIsIdentifierByte(bytes[nameEnd]) {
          nameEnd += 1
        }
        let name = String(decoding: bytes[nameStart..<nameEnd], as: UTF8.self)
        if targetNames.contains(name),
           swiftMutagenReturnValueIsEligible(bytes: bytes, start: nameStart, mutation: mutation) {
          matches.append((nameStart + 1, name))
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
    match.name,
    swiftMutagenImplicitReturnSourceMutation(for: mutation))
}

private func swiftMutagenLocalBindingTokenMatches(
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
  if index > 0 && swiftMutagenIsIdentifierByte(bytes[index - 1]) {
    return false
  }
  for offset in 0..<tokenBytes.count where bytes[index + offset] != tokenBytes[offset] {
    return false
  }
  let after = index + tokenBytes.count
  return after < end && swiftMutagenIsHorizontalWhitespace(bytes[after])
}

private func swiftMutagenFirstLabeledArgumentSeparator(bytes: [UInt8], start: Int, end: Int) -> Int? {
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

private func swiftMutagenLabeledArgumentRHSLooksLikeValueExpression(
  bytes: [UInt8],
  start: Int,
  end: Int
) -> Bool {
  guard start < end else {
    return false
  }
  if bytes[start] >= 65 && bytes[start] <= 90 && !swiftMutagenASCIIContains(bytes, start: start, end: end, pattern: ".") {
    return false
  }
  if swiftMutagenASCIIHasPrefix(bytes, start: start, prefix: "some ")
      || swiftMutagenASCIIHasPrefix(bytes, start: start, prefix: "any ") {
    return false
  }
  return true
}

private func swiftMutagenLabeledArgumentRHSLooksLikeCallExpression(
  bytes: [UInt8],
  start: Int,
  end: Int
) -> Bool {
  guard start < end,
        swiftMutagenASCIIContains(bytes, start: start, end: end, pattern: "(") else {
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

private func swiftMutagenAssignmentValueRHSIsDirectValueExpression(
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

private func swiftMutagenAssignmentDestinationNames(for store: StoreInst) -> [String] {
  var names: [String] = []
  swiftMutagenCollectAssignmentDestinationNames(
    from: store.destination,
    in: store.parentFunction,
    names: &names,
    depth: 0
  )
  return swiftMutagenUniqueAssignmentNames(names)
}

private func swiftMutagenAssignmentSourceNames(for store: StoreInst) -> [String] {
  var names: [String] = []
  swiftMutagenCollectAssignmentSourceNames(
    from: store.source,
    names: &names,
    depth: 0
  )
  return swiftMutagenUniqueAssignmentNames(names)
}

private func swiftMutagenUniqueAssignmentNames(_ names: [String]) -> [String] {
  var seen = Set<String>()
  var uniqueNames: [String] = []
  for name in names where swiftMutagenIdentifierIsUsable(name) && !seen.contains(name) {
    seen.insert(name)
    uniqueNames.append(name)
  }
  return uniqueNames
}

private func swiftMutagenCollectAssignmentSourceNames(
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
    swiftMutagenCollectAssignmentSourceNames(
      from: copyValue.fromValue,
      names: &names,
      depth: depth + 1
    )
  case let explicitCopyValue as ExplicitCopyValueInst:
    swiftMutagenCollectAssignmentSourceNames(
      from: explicitCopyValue.fromValue,
      names: &names,
      depth: depth + 1
    )
  case let moveValue as MoveValueInst:
    swiftMutagenCollectAssignmentSourceNames(
      from: moveValue.fromValue,
      names: &names,
      depth: depth + 1
    )
  default:
    break
  }
}

private func swiftMutagenCollectAssignmentDestinationNames(
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
    swiftMutagenCollectAssignmentDestinationNames(
      from: beginAccess.address,
      in: function,
      names: &names,
      depth: depth + 1
    )
  case let markUninitialized as MarkUninitializedInst:
    swiftMutagenCollectAssignmentDestinationNames(
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
    swiftMutagenCollectAssignmentDestinationNames(
      from: structElementAddr.struct,
      in: function,
      names: &names,
      depth: depth + 1
    )
  case let refElementAddr as RefElementAddrInst:
    if let declaration = refElementAddr.varDecl {
      names.append(declaration.userFacingName.string)
    }
    swiftMutagenCollectAssignmentDestinationNames(
      from: refElementAddr.instance,
      in: function,
      names: &names,
      depth: depth + 1
    )
  case let projectBox as ProjectBoxInst:
    swiftMutagenCollectAssignmentDestinationNames(
      from: projectBox.box,
      in: function,
      names: &names,
      depth: depth + 1
    )
  default:
    break
  }
}

private func swiftMutagenIdentifierIsUsable(_ name: String) -> Bool {
  guard !name.isEmpty,
        name != "_",
        name != "self" else {
    return false
  }
  for byte in name.utf8 {
    guard swiftMutagenIsIdentifierByte(byte) else {
      return false
    }
  }
  return true
}

private func swiftMutagenAssignmentLeftHandSideMatchesTargetNames(
  bytes: [UInt8],
  start: Int,
  end: Int,
  targetNames: [String]
) -> Bool {
  guard !targetNames.isEmpty else {
    return true
  }
  for targetName in targetNames {
    guard swiftMutagenIdentifierIsUsable(targetName) else {
      continue
    }
    if swiftMutagenLeftHandSideContainsIdentifier(
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

private func swiftMutagenLeftHandSideContainsIdentifier(
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
    if swiftMutagenIsIdentifierStartByte(bytes[index]) {
      let identifierStart = index
      index += 1
      while index < end && swiftMutagenIsIdentifierByte(bytes[index]) {
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

private func swiftMutagenIsIdentifierStartByte(_ byte: UInt8) -> Bool {
  byte == 95 || (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122)
}

private func swiftMutagenIsIdentifierByte(_ byte: UInt8) -> Bool {
  swiftMutagenIsIdentifierStartByte(byte) || (byte >= 48 && byte <= 57)
}

private func swiftMutagenFindAssignmentReturnSourceLocation(
  path: String,
  preferredLine: Int,
  mutation: SwiftMutagenMutation,
  config: SwiftMutagenConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard preferredLine > 0,
        mutation.sourceOriginal == "return",
        let text = swiftMutagenRead(path) else {
    return nil
  }

  if let exact = swiftMutagenAssignmentReturnSourceLocation(
    in: text,
    path: path,
    lineRange: preferredLine...preferredLine,
    mutation: mutation,
    config: config
  ) {
    return exact
  }

  let firstLine = preferredLine > 2 ? preferredLine - 2 : 1
  return swiftMutagenAssignmentReturnSourceLocation(
    in: text,
    path: path,
    lineRange: firstLine...(preferredLine + 8),
    mutation: mutation,
    config: config
  )
}

private func swiftMutagenAssignmentReturnSourceLocation(
  in text: String,
  path: String,
  lineRange: ClosedRange<Int>,
  mutation: SwiftMutagenMutation,
  config: SwiftMutagenConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  var matches: [(line: Int, column: Int, sourceOriginal: String, sourceMutated: String)] = []
  var currentLine = 1
  var lineStart = text.startIndex
  var index = text.startIndex

  func inspectLine(_ lineText: String, line: Int) {
    guard lineRange.contains(line),
          matches.count < 2,
          let expression = swiftMutagenAssignmentReturnExpression(lineText, mutation: mutation) else {
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
    swiftMutagenTrimPackageRoot(path, config: config),
    match.line,
    match.column,
    match.sourceOriginal,
    match.sourceMutated)
}

private func swiftMutagenAssignmentReturnExpression(
  _ line: String,
  mutation: SwiftMutagenMutation
) -> (column: Int, sourceOriginal: String, sourceMutated: String)? {
  let bytes = Array(line.utf8)
  let lineStart = swiftMutagenSkipHorizontalWhitespace(bytes, from: 0)
  let lineEnd = swiftMutagenTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  guard lineStart < lineEnd,
        !swiftMutagenLineStartsWithAssignmentReturnBlockedPrefix(bytes: bytes, start: lineStart),
        let equals = swiftMutagenFirstAssignmentOperator(bytes: bytes, start: lineStart, end: lineEnd) else {
    return nil
  }

  let valueStart = swiftMutagenSkipHorizontalWhitespace(bytes, from: equals + 1)
  var valueEnd = lineEnd
  if valueEnd > valueStart && bytes[valueEnd - 1] == 44 {
    valueEnd = swiftMutagenTrimTrailingHorizontalWhitespace(bytes, end: valueEnd - 1)
  }
  guard valueStart < valueEnd,
        swiftMutagenReturnValueIsEligible(bytes: bytes, start: valueStart, mutation: mutation) else {
    return nil
  }

  let sourceOriginal = String(decoding: bytes[valueStart..<valueEnd], as: UTF8.self)
  return (
    valueStart + 1,
    sourceOriginal,
    swiftMutagenImplicitReturnSourceMutation(for: mutation))
}

private func swiftMutagenLineStartsWithAssignmentReturnBlockedPrefix(bytes: [UInt8], start: Int) -> Bool {
  [
    "if ", "if(", "guard ", "guard(", "while ", "while(", "for ", "for(",
    "switch ", "switch(", "return ", "throw ", "import ", "//", "/*"
  ].contains { swiftMutagenASCIIHasPrefix(bytes, start: start, prefix: $0) }
}

private func swiftMutagenFirstAssignmentOperator(bytes: [UInt8], start: Int, end: Int) -> Int? {
  guard start < end else {
    return nil
  }
  for index in start..<end where bytes[index] == 61 {
    let before = index > start ? bytes[index - 1] : 0
    let after = index + 1 < end ? bytes[index + 1] : 0
    if swiftMutagenIsAssignmentOperatorNeighbor(before) || swiftMutagenIsAssignmentOperatorNeighbor(after) {
      continue
    }
    return index
  }
  return nil
}

private func swiftMutagenIsAssignmentOperatorNeighbor(_ byte: UInt8) -> Bool {
  switch byte {
  case 33, 37, 38, 42, 43, 45, 47, 60, 61, 62, 63, 94, 124, 126:
    return true
  default:
    return false
  }
}

private func swiftMutagenReturnSourceLocationIsUsable(
  _ location: (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String),
  mutation: SwiftMutagenMutation,
  config: SwiftMutagenConfig
) -> Bool {
  if mutation.sourceOriginal == "return" {
    return swiftMutagenReturnSourceLooksLikeStatement(file: location.file, line: location.line, config: config)
  }
  return true
}

private func swiftMutagenFindUniqueExplicitReturnSourceLocation(
  path: String,
  preferredLine: Int,
  mutation: SwiftMutagenMutation,
  config: SwiftMutagenConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard preferredLine > 0,
        let text = swiftMutagenRead(path) else {
    return nil
  }

  if let exactLine = swiftMutagenAbsoluteSourceLine(path: path, line: preferredLine) {
    let bytes = Array(exactLine.utf8)
    let start = swiftMutagenSkipHorizontalWhitespace(bytes, from: 0)
    if swiftMutagenReturnLineIsEligible(bytes: bytes, start: start, mutation: mutation) {
      return (
        swiftMutagenTrimPackageRoot(path, config: config),
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
    let start = swiftMutagenSkipHorizontalWhitespace(bytes, from: 0)
    if swiftMutagenReturnLineIsEligible(bytes: bytes, start: start, mutation: mutation) {
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
    swiftMutagenTrimPackageRoot(path, config: config),
    match.line,
    match.column,
    mutation.sourceOriginal,
    mutation.sourceMutated)
}

private func swiftMutagenFindNearestPriorExplicitReturnSourceLocation(
  path: String,
  preferredLine: Int,
  mutation: SwiftMutagenMutation,
  config: SwiftMutagenConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard preferredLine > 1,
        let text = swiftMutagenRead(path) else {
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
    let start = swiftMutagenSkipHorizontalWhitespace(bytes, from: 0)
    if swiftMutagenReturnLineIsEligible(bytes: bytes, start: start, mutation: mutation) {
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
    swiftMutagenTrimPackageRoot(path, config: config),
    nearest.line,
    nearest.column,
    mutation.sourceOriginal,
    mutation.sourceMutated)
}

private func swiftMutagenFindDescribedExplicitReturnSourceLocation(
  path: String,
  preferredLine: Int,
  locationDescription: String,
  mutation: SwiftMutagenMutation,
  config: SwiftMutagenConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard preferredLine > 0,
        let snippet = swiftMutagenQuotedSourceSnippetPrefix(locationDescription),
        snippet.hasPrefix("return "),
        let text = swiftMutagenRead(path) else {
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
    let start = swiftMutagenSkipHorizontalWhitespace(bytes, from: 0)
    guard swiftMutagenReturnLineIsEligible(bytes: bytes, start: start, mutation: mutation) else {
      return
    }
    let trimmed = String(decoding: bytes[start..<swiftMutagenTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)], as: UTF8.self)
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
    swiftMutagenTrimPackageRoot(path, config: config),
    match.line,
    match.column,
    mutation.sourceOriginal,
    mutation.sourceMutated)
}

private func swiftMutagenFindNearestPriorImplicitReturnSourceLocation(
  path: String,
  preferredLine: Int,
  mutation: SwiftMutagenMutation,
  config: SwiftMutagenConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard mutation.sourceOriginal == "return",
        preferredLine > 1,
        let text = swiftMutagenRead(path) else {
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
    let start = swiftMutagenSkipHorizontalWhitespace(bytes, from: 0)
    let end = swiftMutagenTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
    guard start < end,
          !swiftMutagenLineLooksLikeImplicitReturnContinuation(bytes: bytes, start: start),
          swiftMutagenImplicitReturnExpressionIsEligible(
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
      swiftMutagenImplicitReturnSourceMutation(for: mutation))
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
    swiftMutagenTrimPackageRoot(path, config: config),
    nearest.line,
    nearest.column,
    nearest.sourceOriginal,
    nearest.sourceMutated)
}

private func swiftMutagenFindOrdinalExplicitReturnSourceLocation(
  path: String,
  preferredLine: Int,
  ordinal: Int,
  expectedCount: Int,
  mutation: SwiftMutagenMutation,
  config: SwiftMutagenConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard preferredLine > 0,
        ordinal > 0,
        ordinal <= expectedCount,
        expectedCount > 1,
        let text = swiftMutagenRead(path) else {
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
    let start = swiftMutagenSkipHorizontalWhitespace(bytes, from: 0)
    if swiftMutagenReturnLineIsEligible(bytes: bytes, start: start, mutation: mutation) {
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
    swiftMutagenTrimPackageRoot(path, config: config),
    match.line,
    match.column,
    mutation.sourceOriginal,
    mutation.sourceMutated)
}

private func swiftMutagenFindUniqueImplicitReturnSourceLocation(
  path: String,
  preferredLine: Int,
  mutation: SwiftMutagenMutation,
  config: SwiftMutagenConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard mutation.sourceOriginal == "return",
        preferredLine > 0,
        let text = swiftMutagenRead(path) else {
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
    let start = swiftMutagenSkipHorizontalWhitespace(bytes, from: 0)
    guard swiftMutagenImplicitReturnExpressionIsEligible(
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
      swiftMutagenImplicitReturnSourceMutation(for: mutation)
    ))
  }

  func inspectLine(_ lineText: String, line: Int) {
    guard line >= preferredLine,
          line <= preferredLine + 80,
          matches.count < 2 else {
      return
    }

    let bytes = Array(lineText.utf8)
    let start = swiftMutagenSkipHorizontalWhitespace(bytes, from: 0)
    let end = swiftMutagenTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
    guard start < end else {
      return
    }
    if swiftMutagenLineLooksLikeImplicitReturnContinuation(bytes: bytes, start: start) {
      return
    }

    if line == preferredLine,
       let expression = swiftMutagenInlineImplicitReturnExpression(lineText) {
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
    guard swiftMutagenLineLooksLikeImplicitReturnExpression(
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
    swiftMutagenTrimPackageRoot(path, config: config),
    match.line,
    match.column,
    match.sourceOriginal,
    match.sourceMutated)
}

private func swiftMutagenInlineImplicitReturnExpression(_ line: String) -> (text: String, column: Int)? {
  guard let openBrace = line.firstIndex(of: "{"),
        let closeBrace = line.lastIndex(of: "}"),
        openBrace < closeBrace else {
    return nil
  }
  let expressionStart = line.index(after: openBrace)
  let text = String(line[expressionStart..<closeBrace])
  let bytes = Array(text.utf8)
  let start = swiftMutagenSkipHorizontalWhitespace(bytes, from: 0)
  let end = swiftMutagenTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  guard start < end else {
    return nil
  }
  return (String(text), line.distance(from: line.startIndex, to: expressionStart) + 1)
}

private func swiftMutagenLineLooksLikeImplicitReturnExpression(
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
    if swiftMutagenASCIIHasPrefix(bytes, start: start, prefix: prefix) {
      return false
    }
  }
  for index in start..<end {
    if bytes[index] == 59 {
      return false
    }
    if !allowsInlineBraces && (bytes[index] == 123 || bytes[index] == 125) {
      return false
    }
  }
  if allowsInlineBraces && !swiftMutagenLineHasBalancedInlineBraces(bytes: bytes, start: start, end: end) {
    return false
  }
  if !allowsInlineBraces && swiftMutagenASCIIContains(bytes, start: start, end: end, pattern: " in ") {
    return false
  }
  return true
}

private func swiftMutagenLineHasBalancedInlineBraces(bytes: [UInt8], start: Int, end: Int) -> Bool {
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

private func swiftMutagenLineLooksLikeImplicitReturnContinuation(bytes: [UInt8], start: Int) -> Bool {
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

private func swiftMutagenImplicitReturnExpressionIsEligible(
  bytes: [UInt8],
  start: Int,
  mutation: SwiftMutagenMutation,
  allowsInlineBraces: Bool = false
) -> Bool {
  start < bytes.count
    && swiftMutagenLineLooksLikeImplicitReturnExpression(
      bytes: bytes,
      start: start,
      end: swiftMutagenTrimTrailingHorizontalWhitespace(bytes, end: bytes.count),
      allowsInlineBraces: allowsInlineBraces
    )
    && swiftMutagenReturnValueIsEligible(bytes: bytes, start: start, mutation: mutation)
}

private func swiftMutagenImplicitReturnSourceMutation(for mutation: SwiftMutagenMutation) -> String {
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

private func swiftMutagenReturnLineIsEligible(
  bytes: [UInt8],
  start: Int,
  mutation: SwiftMutagenMutation
) -> Bool {
  guard swiftMutagenASCIIHasExactPrefix(bytes, start: start, prefix: "return ") else {
    return false
  }
  let valueStart = swiftMutagenSkipHorizontalWhitespace(bytes, from: start + 7)
  return swiftMutagenReturnValueIsEligible(bytes: bytes, start: valueStart, mutation: mutation)
}

private func swiftMutagenReturnValueIsEligible(
  bytes: [UInt8],
  start: Int,
  mutation: SwiftMutagenMutation
) -> Bool {
  switch mutation.mutatedBuiltinName {
  case "return_false":
    return !swiftMutagenASCIIHasToken(bytes, start: start, token: "false")
  case "return_true":
    return !swiftMutagenASCIIHasToken(bytes, start: start, token: "true")
  case "return_nil":
    return !swiftMutagenASCIIHasToken(bytes, start: start, token: "nil")
  case "return_zero":
    return !swiftMutagenASCIIHasNumericZeroToken(bytes, start: start)
  case "return_empty_string":
    return !swiftMutagenASCIIHasEmptyStringLiteral(bytes, start: start)
  case "return_empty_array", "return_empty_set":
    return !swiftMutagenASCIIHasEmptyArrayLiteral(bytes, start: start)
  case "return_empty_dictionary":
    return !swiftMutagenASCIIHasEmptyDictionaryLiteral(bytes, start: start)
  default:
    return true
  }
}

private func swiftMutagenASCIIHasEmptyArrayLiteral(_ bytes: [UInt8], start: Int) -> Bool {
  guard start >= 0 && start + 2 <= bytes.count,
        bytes[start] == 91,
        bytes[start + 1] == 93 else {
    return false
  }
  let end = start + 2
  return end == bytes.count || !swiftMutagenIsASCIILetterNumberOrUnderscore(bytes[end])
}

private func swiftMutagenASCIIHasEmptyDictionaryLiteral(_ bytes: [UInt8], start: Int) -> Bool {
  guard start >= 0 && start + 3 <= bytes.count,
        bytes[start] == 91,
        bytes[start + 1] == 58,
        bytes[start + 2] == 93 else {
    return false
  }
  let end = start + 3
  return end == bytes.count || !swiftMutagenIsASCIILetterNumberOrUnderscore(bytes[end])
}

private func swiftMutagenASCIIHasEmptyStringLiteral(_ bytes: [UInt8], start: Int) -> Bool {
  guard start >= 0 && start + 2 <= bytes.count,
        bytes[start] == 34,
        bytes[start + 1] == 34 else {
    return false
  }
  let end = start + 2
  return end == bytes.count || !swiftMutagenIsASCIILetterNumberOrUnderscore(bytes[end])
}

private func swiftMutagenASCIIHasToken(_ bytes: [UInt8], start: Int, token: String) -> Bool {
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
  return end == bytes.count || !swiftMutagenIsASCIILetterNumberOrUnderscore(bytes[end])
}

private func swiftMutagenASCIIHasNumericZeroToken(_ bytes: [UInt8], start: Int) -> Bool {
  guard start >= 0 && start < bytes.count && bytes[start] == 48 else {
    return false
  }
  let end = start + 1
  return end == bytes.count || bytes[end] < 48 || bytes[end] > 57
}

private func swiftMutagenInstructionSourceLocation(
  for instruction: Instruction,
  mutation: SwiftMutagenMutation,
  config: SwiftMutagenConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  if let fileNameAndPosition = instruction.location.fileNameAndPosition {
    let path = fileNameAndPosition.path.string
    if let matchedPath = swiftMutagenIncludedSourcePath(path, config: config) {
      return (
        swiftMutagenTrimPackageRoot(matchedPath, config: config),
        fileNameAndPosition.line,
        fileNameAndPosition.column,
        mutation.sourceOriginal,
        mutation.sourceMutated)
    }
  }

  let location = instruction.parentFunction.location.description
  for path in swiftMutagenSwiftSourcePaths(config: config) {
    guard location.contains(path),
          let line = swiftMutagenPreferredLine(in: location, path: path) else {
      continue
    }
    return (
      swiftMutagenTrimPackageRoot(path, config: config),
      line,
      1,
      mutation.sourceOriginal,
      mutation.sourceMutated)
  }
  return nil
}

private func swiftMutagenVoidCallSourceLocation(
  for apply: ApplyInst,
  mutation: SwiftMutagenMutation,
  config: SwiftMutagenConfig
) -> SwiftMutagenVoidCallSourceLocationResult {
  if let fileNameAndPosition = apply.location.fileNameAndPosition {
    let path = fileNameAndPosition.path.string
    if let matchedPath = swiftMutagenIncludedSourcePath(path, config: config) {
      let candidate = (
        swiftMutagenTrimPackageRoot(matchedPath, config: config),
        fileNameAndPosition.line,
        fileNameAndPosition.column,
        mutation.sourceOriginal,
        mutation.sourceMutated)
      if swiftMutagenVoidCallSourceLooksLikeStatement(file: candidate.0, line: candidate.1, config: config) {
        return .found(
          file: candidate.0,
          line: candidate.1,
          column: candidate.2,
          sourceOriginal: candidate.3,
          sourceMutated: candidate.4
        )
      }
      if let anchored = swiftMutagenFindUniqueVoidCallSourceLocation(
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

  if let fallback = swiftMutagenInstructionSourceLocation(
    for: apply,
    mutation: mutation,
    config: config
  ) {
    if swiftMutagenVoidCallSourceLooksLikeStatement(file: fallback.file, line: fallback.line, config: config) {
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
    if let anchored = swiftMutagenFindUniqueVoidCallSourceLocation(
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

private func swiftMutagenFindUniqueVoidCallSourceLocation(
  path: String,
  preferredLine: Int,
  mutation: SwiftMutagenMutation,
  config: SwiftMutagenConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard preferredLine > 0,
        let text = swiftMutagenRead(path) else {
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
          swiftMutagenSourceLineLooksLikeVoidCallStatement(lineText) else {
      return
    }
    let bytes = Array(lineText.utf8)
    let start = swiftMutagenSkipHorizontalWhitespace(bytes, from: 0)
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
    swiftMutagenTrimPackageRoot(path, config: config),
    match.line,
    match.column,
    mutation.sourceOriginal,
    mutation.sourceMutated)
}

private func swiftMutagenBranchSourceLocation(
  for branch: CondBranchInst,
  mutation: SwiftMutagenMutation,
  config: SwiftMutagenConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  if let fileNameAndPosition = branch.location.fileNameAndPosition {
    let path = fileNameAndPosition.path.string
    if let matchedPath = swiftMutagenIncludedSourcePath(path, config: config) {
      if let sourceLocation = swiftMutagenGenericConditionSourceLocation(
        path: matchedPath,
        line: fileNameAndPosition.line,
        fallbackColumn: fileNameAndPosition.column,
        mutation: mutation,
        config: config
      ) {
        return sourceLocation
      }
      return (
        swiftMutagenTrimPackageRoot(matchedPath, config: config),
        fileNameAndPosition.line,
        fileNameAndPosition.column,
        mutation.sourceOriginal,
        mutation.sourceMutated)
    }
  }

  let location = branch.parentFunction.location.description
  for path in swiftMutagenSwiftSourcePaths(config: config) {
    guard location.contains(path),
          let line = swiftMutagenPreferredLine(in: location, path: path) else {
      continue
    }
    if let anchored = swiftMutagenFindUniqueExplicitConditionSourceLocation(
      path: path,
      preferredLine: line,
      mutation: mutation,
      config: config
    ) {
      return anchored
    }
    return (
      swiftMutagenTrimPackageRoot(path, config: config),
      line,
      1,
      mutation.sourceOriginal,
      mutation.sourceMutated)
  }
  return nil
}

private func swiftMutagenFindUniqueExplicitConditionSourceLocation(
  path: String,
  preferredLine: Int,
  mutation: SwiftMutagenMutation,
  config: SwiftMutagenConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard preferredLine > 0,
        let text = swiftMutagenRead(path) else {
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
          let expression = swiftMutagenGenericConditionExpression(lineText) else {
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
    swiftMutagenTrimPackageRoot(path, config: config),
    match.line,
    match.column,
    match.sourceOriginal,
    mutation.sourceMutated)
}

private func swiftMutagenGenericConditionSourceLocation(
  path: String,
  line: Int,
  fallbackColumn: Int,
  mutation: SwiftMutagenMutation,
  config: SwiftMutagenConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard let sourceLine = swiftMutagenAbsoluteSourceLine(path: path, line: line),
        let expression = swiftMutagenGenericConditionExpression(sourceLine) else {
    return nil
  }
  return (
    swiftMutagenTrimPackageRoot(path, config: config),
    line,
    expression.column > 0 ? expression.column : fallbackColumn,
    expression.sourceOriginal,
    mutation.sourceMutated)
}

private func swiftMutagenSourceLocation(
  for instruction: Instruction,
  function: Function,
  moduleName: String,
  mutation: SwiftMutagenMutation,
  config: SwiftMutagenConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  if let fileNameAndPosition = instruction.location.fileNameAndPosition {
    let path = fileNameAndPosition.path.string
    guard let matchedPath = swiftMutagenIncludedSourcePath(path, config: config) else {
      return nil
    }
    return (
      swiftMutagenTrimPackageRoot(matchedPath, config: config),
      fileNameAndPosition.line,
      fileNameAndPosition.column,
      "",
      "")
  }

  if let located = swiftMutagenFindSourceOperator(
    moduleName: moduleName,
    functionLocation: function.location.description,
    mutation: mutation,
    config: config) {
    return located
  }

  if let located = swiftMutagenFindDescribedSourceOperator(
    moduleName: moduleName,
    functionLocation: function.location.description,
    locationDescription: instruction.location.description,
    mutation: mutation,
    config: config) {
    return located
  }

  if let comparison = instruction as? BuiltinInst,
     swiftMutagenIsComparisonBuiltin(comparison),
     let ordinal = swiftMutagenComparisonOrdinalAndCount(for: comparison, in: function),
     ordinal.count <= 12 {
    return swiftMutagenFindOrdinalSourceOperator(
      moduleName: moduleName,
      functionLocation: function.location.description,
      ordinal: ordinal.ordinal,
      expectedCount: ordinal.count,
      mutation: mutation,
      config: config)
  }

  return nil
}

private func swiftMutagenGenericConditionSourceIsExplicit(
  file: String,
  line: Int,
  config: SwiftMutagenConfig
) -> Bool {
  guard let sourceLine = swiftMutagenSourceLine(file: file, line: line, config: config) else {
    return true
  }
  return swiftMutagenSourceLineLooksLikeExplicitCondition(sourceLine)
}

private func swiftMutagenSourceLine(
  file: String,
  line: Int,
  config: SwiftMutagenConfig
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
  guard let matchedPath = swiftMutagenIncludedSourcePath(path, config: config),
        let text = swiftMutagenRead(matchedPath) else {
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

private func swiftMutagenAbsoluteSourceLine(path: String, line: Int) -> String? {
  guard line > 0,
        let text = swiftMutagenRead(path) else {
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

private func swiftMutagenGenericConditionExpression(
  _ line: String
) -> (column: Int, sourceOriginal: String)? {
  let bytes = Array(line.utf8)
  let lineEnd = swiftMutagenTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  var start = swiftMutagenSkipHorizontalWhitespace(bytes, from: 0)
  guard start < lineEnd else {
    return nil
  }

  if bytes[start] == 125 {
    start = swiftMutagenSkipHorizontalWhitespace(bytes, from: start + 1)
    if swiftMutagenASCIIHasPrefix(bytes, start: start, prefix: "else ") {
      start = swiftMutagenSkipHorizontalWhitespace(bytes, from: start + 5)
    }
  }

  guard !swiftMutagenSourceLineLooksLikeOptionalBindingCondition(bytes: bytes, start: start),
        !swiftMutagenTopLevelASCIIContains(bytes, start: start, end: lineEnd, pattern: ", let "),
        !swiftMutagenTopLevelASCIIContains(bytes, start: start, end: lineEnd, pattern: ", var ") else {
    return nil
  }

  let expressionRange: (start: Int, end: Int)?
  if swiftMutagenASCIIHasPrefix(bytes, start: start, prefix: "if ") {
    expressionRange = swiftMutagenControlConditionRange(bytes: bytes, start: start + 3, end: lineEnd)
  } else if swiftMutagenASCIIHasPrefix(bytes, start: start, prefix: "if(") {
    expressionRange = swiftMutagenParenthesizedControlConditionRange(bytes: bytes, open: start + 2, end: lineEnd)
  } else if swiftMutagenASCIIHasPrefix(bytes, start: start, prefix: "guard ") {
    expressionRange = swiftMutagenGuardConditionRange(bytes: bytes, start: start + 6, end: lineEnd)
  } else if swiftMutagenASCIIHasPrefix(bytes, start: start, prefix: "guard(") {
    expressionRange = swiftMutagenParenthesizedControlConditionRange(bytes: bytes, open: start + 5, end: lineEnd)
  } else if swiftMutagenASCIIHasPrefix(bytes, start: start, prefix: "while ") {
    expressionRange = swiftMutagenControlConditionRange(bytes: bytes, start: start + 6, end: lineEnd)
  } else if swiftMutagenASCIIHasPrefix(bytes, start: start, prefix: "while(") {
    expressionRange = swiftMutagenParenthesizedControlConditionRange(bytes: bytes, open: start + 5, end: lineEnd)
  } else if swiftMutagenASCIIHasPrefix(bytes, start: start, prefix: "for ")
      || swiftMutagenASCIIHasPrefix(bytes, start: start, prefix: "for(") {
    expressionRange = swiftMutagenForWhereConditionRange(bytes: bytes, start: start, end: lineEnd)
  } else {
    expressionRange = nil
  }

  guard var range = expressionRange else {
    return nil
  }
  range.start = swiftMutagenSkipHorizontalWhitespace(bytes, from: range.start)
  range.end = swiftMutagenTrimTrailingHorizontalWhitespace(bytes, end: range.end)
  guard range.start < range.end else {
    return nil
  }
  return (
    range.start + 1,
    String(decoding: bytes[range.start..<range.end], as: UTF8.self))
}

private func swiftMutagenControlConditionRange(
  bytes: [UInt8],
  start: Int,
  end: Int
) -> (start: Int, end: Int)? {
  let conditionEnd = swiftMutagenTopLevelByteIndex(bytes, start: start, end: end, byte: 123) ?? end
  return (start, conditionEnd)
}

private func swiftMutagenGuardConditionRange(
  bytes: [UInt8],
  start: Int,
  end: Int
) -> (start: Int, end: Int)? {
  let elseIndex = swiftMutagenTopLevelASCIIIndex(bytes, start: start, end: end, pattern: " else ")
  let braceIndex = swiftMutagenTopLevelByteIndex(bytes, start: start, end: end, byte: 123)
  let conditionEnd = elseIndex ?? braceIndex ?? end
  return (start, conditionEnd)
}

private func swiftMutagenForWhereConditionRange(
  bytes: [UInt8],
  start: Int,
  end: Int
) -> (start: Int, end: Int)? {
  guard let whereIndex = swiftMutagenTopLevelASCIIIndex(bytes, start: start, end: end, pattern: " where ") else {
    return nil
  }
  let valueStart = whereIndex + 7
  let valueEnd = swiftMutagenTopLevelByteIndex(bytes, start: valueStart, end: end, byte: 123) ?? end
  return (valueStart, valueEnd)
}

private func swiftMutagenParenthesizedControlConditionRange(
  bytes: [UInt8],
  open: Int,
  end: Int
) -> (start: Int, end: Int)? {
  guard open < end,
        bytes[open] == 40,
        let close = swiftMutagenBalancedExpressionEnd(
          in: bytes,
          openIndex: open,
          close: 41,
          lineEnd: end
        ) else {
    return nil
  }
  return (open + 1, close - 1)
}

private func swiftMutagenTopLevelASCIIContains(
  _ bytes: [UInt8],
  start: Int,
  end: Int,
  pattern: String
) -> Bool {
  swiftMutagenTopLevelASCIIIndex(bytes, start: start, end: end, pattern: pattern) != nil
}

private func swiftMutagenTopLevelASCIIIndex(
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
  return swiftMutagenFirstTopLevelIndex(bytes, start: start, end: end) { index in
    guard index + patternBytes.count <= end else {
      return false
    }
    for offset in 0..<patternBytes.count where bytes[index + offset] != patternBytes[offset] {
      return false
    }
    return true
  }
}

private func swiftMutagenTopLevelByteIndex(
  _ bytes: [UInt8],
  start: Int,
  end: Int,
  byte: UInt8
) -> Int? {
  swiftMutagenFirstTopLevelIndex(bytes, start: start, end: end) { index in
    bytes[index] == byte
  }
}

private func swiftMutagenFirstTopLevelIndex(
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

private func swiftMutagenSourceLineLooksLikeExplicitCondition(_ line: String) -> Bool {
  let bytes = Array(line.utf8)
  var start = swiftMutagenSkipHorizontalWhitespace(bytes, from: 0)
  guard start < bytes.count else {
    return false
  }

  if bytes[start] == 125 {
    start = swiftMutagenSkipHorizontalWhitespace(bytes, from: start + 1)
    if swiftMutagenASCIIHasPrefix(bytes, start: start, prefix: "else ") {
      start = swiftMutagenSkipHorizontalWhitespace(bytes, from: start + 5)
    }
  }

  if swiftMutagenSourceLineLooksLikeOptionalBindingCondition(bytes: bytes, start: start) {
    return false
  }

  return swiftMutagenASCIIHasPrefix(bytes, start: start, prefix: "if ")
    || swiftMutagenASCIIHasPrefix(bytes, start: start, prefix: "if(")
    || swiftMutagenASCIIHasPrefix(bytes, start: start, prefix: "guard ")
    || swiftMutagenASCIIHasPrefix(bytes, start: start, prefix: "guard(")
    || swiftMutagenASCIIHasPrefix(bytes, start: start, prefix: "while ")
    || swiftMutagenASCIIHasPrefix(bytes, start: start, prefix: "while(")
    || swiftMutagenASCIIHasPrefix(bytes, start: start, prefix: "for ")
    || swiftMutagenASCIIHasPrefix(bytes, start: start, prefix: "for(")
}

private func swiftMutagenSourceLineLooksLikeOptionalBindingCondition(bytes: [UInt8], start: Int) -> Bool {
  swiftMutagenASCIIHasPrefix(bytes, start: start, prefix: "if let ")
    || swiftMutagenASCIIHasPrefix(bytes, start: start, prefix: "if var ")
    || swiftMutagenASCIIHasPrefix(bytes, start: start, prefix: "guard let ")
    || swiftMutagenASCIIHasPrefix(bytes, start: start, prefix: "guard var ")
}

private func swiftMutagenReturnSourceLooksLikeStatement(
  file: String,
  line: Int,
  config: SwiftMutagenConfig
) -> Bool {
  guard let sourceLine = swiftMutagenSourceLine(file: file, line: line, config: config) else {
    return true
  }
  let bytes = Array(sourceLine.utf8)
  let start = swiftMutagenSkipHorizontalWhitespace(bytes, from: 0)
  return swiftMutagenASCIIHasExactPrefix(bytes, start: start, prefix: "return ")
}

private func swiftMutagenVoidCallSourceLooksLikeStatement(
  file: String,
  line: Int,
  config: SwiftMutagenConfig
) -> Bool {
  guard let sourceLine = swiftMutagenSourceLine(file: file, line: line, config: config) else {
    return true
  }
  return swiftMutagenSourceLineLooksLikeVoidCallStatement(sourceLine)
}

private func swiftMutagenSourceLineLooksLikeVoidCallStatement(_ line: String) -> Bool {
  let bytes = Array(line.utf8)
  let start = swiftMutagenSkipHorizontalWhitespace(bytes, from: 0)
  let end = swiftMutagenTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
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
    if swiftMutagenASCIIHasPrefix(bytes, start: start, prefix: prefix) {
      return false
    }
  }
  if swiftMutagenASCIIContains(bytes, start: start, end: end, pattern: " = ") {
    return false
  }
  if swiftMutagenSourceLineLooksLikeArgumentLabel(bytes: bytes, start: start, end: end) {
    return false
  }
  if swiftMutagenASCIIContains(bytes, start: start, end: end, pattern: ":")
      && !swiftMutagenASCIIContains(bytes, start: start, end: end, pattern: "(") {
    return false
  }
  return swiftMutagenASCIIContains(bytes, start: start, end: end, pattern: "(")
}

private func swiftMutagenTrimTrailingHorizontalWhitespace(_ bytes: [UInt8], end: Int) -> Int {
  var index = end
  while index > 0 && swiftMutagenIsHorizontalWhitespace(bytes[index - 1]) {
    index -= 1
  }
  return index
}

private func swiftMutagenSourceLineLooksLikeArgumentLabel(bytes: [UInt8], start: Int, end: Int) -> Bool {
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
  while labelEnd > start && swiftMutagenIsHorizontalWhitespace(bytes[labelEnd - 1]) {
    labelEnd -= 1
  }
  guard start < labelEnd else {
    return false
  }
  for labelIndex in start..<labelEnd {
    guard swiftMutagenIsASCIILetterNumberOrUnderscore(bytes[labelIndex]) else {
      return false
    }
  }
  return true
}

private func swiftMutagenSkipHorizontalWhitespace(_ bytes: [UInt8], from start: Int) -> Int {
  var index = start
  while index < bytes.count && swiftMutagenIsHorizontalWhitespace(bytes[index]) {
    index += 1
  }
  return index
}

private func swiftMutagenASCIIContains(_ bytes: [UInt8], start: Int, end: Int, pattern: String) -> Bool {
  swiftMutagenASCIIIndex(bytes, start: start, end: end, pattern: pattern) != nil
}

private func swiftMutagenASCIIIndex(_ bytes: [UInt8], start: Int, end: Int, pattern: String) -> Int? {
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

private func swiftMutagenASCIIHasExactPrefix(_ bytes: [UInt8], start: Int, prefix: String) -> Bool {
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

private func swiftMutagenASCIIHasPrefix(_ bytes: [UInt8], start: Int, prefix: String) -> Bool {
  let prefixBytes = Array(prefix.utf8)
  guard start >= 0 && start + prefixBytes.count <= bytes.count else {
    return false
  }
  for offset in 0..<prefixBytes.count {
    if swiftMutagenASCIILowercase(bytes[start + offset]) != swiftMutagenASCIILowercase(prefixBytes[offset]) {
      return false
    }
  }
  return true
}

private func swiftMutagenASCIILowercase(_ byte: UInt8) -> UInt8 {
  if byte >= 65 && byte <= 90 {
    return byte + 32
  }
  return byte
}

private func swiftMutagenIsASCIIIdentifierStart(_ byte: UInt8) -> Bool {
  if byte >= 65 && byte <= 90 {
    return true
  }
  if byte >= 97 && byte <= 122 {
    return true
  }
  return byte == 95
}

private func swiftMutagenIsASCIILetterNumberOrUnderscore(_ byte: UInt8) -> Bool {
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

private func swiftMutagenExclusionReason(
  function: Function,
  config: SwiftMutagenConfig
) -> String? {
  if swiftMutagenIsGeneratedInvalidLocationFunction(function) {
    return "generatedInvalidLocation"
  }
  if swiftMutagenIsGeneratedSpecializationFunctionName(function.name.string) {
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

private func swiftMutagenIsGeneratedInvalidLocationFunction(_ function: Function) -> Bool {
  let location = function.location.description
  guard location.contains("<invalid loc>") else {
    return false
  }

  let name = function.name.string
  return name.contains("__derived_")
    || name.contains("CodingKeys")
    || name.hasSuffix("TW")
}

private func swiftMutagenIsGeneratedSpecializationFunctionName(_ name: String) -> Bool {
  name.contains("Tf4")
}

private func swiftMutagenFindSourceOperator(
  moduleName: String,
  functionLocation: String,
  mutation: SwiftMutagenMutation,
  config: SwiftMutagenConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard !config.packageRoot.isEmpty else {
    return nil
  }

  let displayRules = swiftMutagenSourceMutationDisplayRules(for: mutation, config: config)

  let preferredPrefix = config.packageRoot + "/Sources/" + moduleName + "/"
  let locatedSourcePaths = swiftMutagenSwiftSourcePaths(config: config).compactMap { path
    -> (path: String, preferredLine: Int)? in
    guard functionLocation.contains(path),
          let preferredLine = swiftMutagenPreferredLine(in: functionLocation, path: path) else {
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
    guard let text = swiftMutagenRead(path) else {
      continue
    }
    var bestForPath: (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)?
    for rule in displayRules {
      if let position = swiftMutagenFindOperator(
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
          swiftMutagenTrimPackageRoot(path, config: config),
          position.line,
          position.column,
          position.sourceOriginal,
          sourceMutated)
        if let existing = bestForPath,
           swiftMutagenLineDistance(existing.line, preferredLine) <= swiftMutagenLineDistance(result.1, preferredLine) {
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

    if let result = swiftMutagenFindUniqueSourceOperatorInFunctionBody(
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

private func swiftMutagenFindUniqueSourceOperatorInFunctionBody(
  path: String,
  preferredLine: Int,
  displayRules: [SwiftMutagenSourceMutationDisplayRule],
  config: SwiftMutagenConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard preferredLine > 0,
        let text = swiftMutagenRead(path) else {
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
      guard let position = swiftMutagenFindOperator(
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
    swiftMutagenTrimPackageRoot(path, config: config),
    match.line,
    match.column,
    match.sourceOriginal,
    match.sourceMutated)
}

private func swiftMutagenFindDescribedSourceOperator(
  moduleName: String,
  functionLocation: String,
  locationDescription: String,
  mutation: SwiftMutagenMutation,
  config: SwiftMutagenConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard let snippet = swiftMutagenQuotedSourceSnippetPrefix(locationDescription),
        let needle = swiftMutagenDescribedSourceOperatorNeedle(snippet) else {
    return nil
  }

  let displayRules = swiftMutagenSourceMutationDisplayRules(for: mutation, config: config)
  let preferredPrefix = config.packageRoot + "/Sources/" + moduleName + "/"
  let locatedSourcePaths = swiftMutagenSwiftSourcePaths(config: config).compactMap { path
    -> (path: String, preferredLine: Int)? in
    guard functionLocation.contains(path),
          let preferredLine = swiftMutagenPreferredLine(in: functionLocation, path: path) else {
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
    guard let result = swiftMutagenFindDescribedSourceOperatorInFunctionBody(
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

private func swiftMutagenDescribedSourceOperatorNeedle(_ snippet: String) -> String? {
  let bytes = Array(snippet.utf8)
  var start = swiftMutagenSkipHorizontalWhitespace(bytes, from: 0)
  var end = swiftMutagenTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  guard start < end else {
    return nil
  }
  if start + 1 < end
      && (bytes[start] == 38 || bytes[start] == 124)
      && bytes[start + 1] == bytes[start] {
    start = swiftMutagenSkipHorizontalWhitespace(bytes, from: start + 2)
  }
  while end > start {
    let byte = bytes[end - 1]
    if byte == 44 || byte == 123 || byte == 125 {
      end = swiftMutagenTrimTrailingHorizontalWhitespace(bytes, end: end - 1)
      continue
    }
    break
  }
  guard end - start >= 2 else {
    return nil
  }
  let result = String(decoding: bytes[start..<end], as: UTF8.self)
  return swiftMutagenSourceOperatorNeedleContainsOperator(result) ? result : nil
}

private func swiftMutagenSourceOperatorNeedleContainsOperator(_ needle: String) -> Bool {
  let operators = ["!=", "==", ">=", "<=", ">", "<"]
  let bytes = Array(needle.utf8)
  let start = swiftMutagenSkipHorizontalWhitespace(bytes, from: 0)
  let end = swiftMutagenTrimTrailingHorizontalWhitespace(bytes, end: bytes.count)
  guard start < end else {
    return false
  }
  for operatorText in operators where swiftMutagenASCIIContains(bytes, start: start, end: end, pattern: operatorText) {
    return true
  }
  return false
}

private func swiftMutagenFindDescribedSourceOperatorInFunctionBody(
  path: String,
  preferredLine: Int,
  displayRules: [SwiftMutagenSourceMutationDisplayRule],
  needle: String,
  config: SwiftMutagenConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard preferredLine > 0,
        let text = swiftMutagenRead(path) else {
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
      for position in swiftMutagenFindOperatorMatches(
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
    swiftMutagenTrimPackageRoot(path, config: config),
    match.line,
    match.column,
    match.sourceOriginal,
    match.sourceMutated)
}

private func swiftMutagenComparisonOrdinalAndCount(
  for comparison: BuiltinInst,
  in function: Function
) -> (ordinal: Int, count: Int)? {
  guard let targetID = swiftMutagenComparisonBuiltinIDName(comparison) else {
    return nil
  }

  var ordinal = 0
  var count = 0
  for block in function.blocks {
    for instruction in block.instructions {
      guard let candidate = instruction as? BuiltinInst,
            swiftMutagenComparisonBuiltinIDName(candidate) == targetID else {
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

private func swiftMutagenFindOrdinalSourceOperator(
  moduleName: String,
  functionLocation: String,
  ordinal: Int,
  expectedCount: Int,
  mutation: SwiftMutagenMutation,
  config: SwiftMutagenConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard ordinal > 0, expectedCount > 0 else {
    return nil
  }

  let displayRules = swiftMutagenSourceMutationDisplayRules(for: mutation, config: config)
  let preferredPrefix = config.packageRoot + "/Sources/" + moduleName + "/"
  let locatedSourcePaths = swiftMutagenSwiftSourcePaths(config: config).compactMap { path
    -> (path: String, preferredLine: Int)? in
    guard functionLocation.contains(path),
          let preferredLine = swiftMutagenPreferredLine(in: functionLocation, path: path) else {
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
    guard let result = swiftMutagenFindOrdinalSourceOperatorInFunctionBody(
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

private func swiftMutagenFindOrdinalSourceOperatorInFunctionBody(
  path: String,
  preferredLine: Int,
  displayRules: [SwiftMutagenSourceMutationDisplayRule],
  ordinal: Int,
  expectedCount: Int,
  config: SwiftMutagenConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard preferredLine > 0,
        let text = swiftMutagenRead(path) else {
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
      for position in swiftMutagenFindOperatorMatches(
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
    swiftMutagenTrimPackageRoot(path, config: config),
    match.line,
    match.column,
    match.sourceOriginal,
    match.sourceMutated)
}

private func swiftMutagenSourceMutationDisplayRules(
  for mutation: SwiftMutagenMutation,
  config: SwiftMutagenConfig
) -> [SwiftMutagenSourceMutationDisplayRule] {
  let builtinID = swiftMutagenBuiltinIDName(mutation.originalID) ?? ""
  let rules = config.sourceMutationDisplayRules.filter {
    $0.mutator == mutation.mutator && $0.builtinID == builtinID
  }
  if !rules.isEmpty {
    return rules
  }
  return [
    SwiftMutagenSourceMutationDisplayRule(
      mutator: mutation.mutator,
      builtinID: builtinID,
      sourceOriginal: mutation.sourceOriginal,
      sourceMutated: mutation.sourceMutated,
      sourceMutatedOverride: ""
    )
  ]
}

private func swiftMutagenFindOperator(
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
      if !swiftMutagenIsSourceComparisonOperator(
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
      let expression = swiftMutagenSourceExpression(
        in: bytes,
        operatorStart: index,
        operatorEnd: index + opBytes.count,
        mutatedOperator: mutatedOperator)
      let candidate = (line, column, expression.original, expression.mutated)
      guard let preferredLine = preferredLine else {
        return candidate
      }
      if let maxPreferredLineDistance = maxPreferredLineDistance,
         swiftMutagenLineDistance(line, preferredLine) > maxPreferredLineDistance {
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
        if swiftMutagenLineDistance(line, preferredLine) < swiftMutagenLineDistance(existing.line, preferredLine) {
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

private func swiftMutagenFindOperatorMatches(
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
       swiftMutagenIsSourceComparisonOperator(
        bytes: bytes,
        operatorStart: index,
        operatorEnd: index + opBytes.count
       ) {
      let expression = swiftMutagenSourceExpression(
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

private func swiftMutagenPreferredLine(in location: String, path: String) -> Int? {
  let locationBytes = Array(location.utf8)
  let pathBytes = Array(path.utf8)
  guard let pathIndex = swiftMutagenFind(pathBytes, in: locationBytes, startingAt: 0) else {
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

private func swiftMutagenLineDistance(_ lhs: Int, _ rhs: Int) -> Int {
  lhs >= rhs ? lhs - rhs : rhs - lhs
}

private func swiftMutagenIsSourceComparisonOperator(
  bytes: [UInt8],
  operatorStart: Int,
  operatorEnd: Int
) -> Bool {
  if operatorStart > 0 && bytes[operatorStart - 1] == 45 {
    return false
  }
  if operatorStart > 0 && swiftMutagenIsOperatorByte(bytes[operatorStart - 1]) {
    return false
  }
  if operatorEnd < bytes.count && swiftMutagenIsOperatorByte(bytes[operatorEnd]) {
    return false
  }
  if swiftMutagenIsOperatorFunctionDeclaration(bytes: bytes, operatorStart: operatorStart) {
    return false
  }
  if swiftMutagenIsLikelyGenericAngleBracket(
    bytes: bytes,
    operatorStart: operatorStart,
    operatorEnd: operatorEnd
  ) {
    return false
  }
  return true
}

private func swiftMutagenIsLikelyGenericAngleBracket(
  bytes: [UInt8],
  operatorStart: Int,
  operatorEnd: Int
) -> Bool {
  guard operatorEnd == operatorStart + 1 else {
    return false
  }
  if bytes[operatorStart] == 60 {
    return swiftMutagenHasIdentifierBefore(bytes: bytes, index: operatorStart)
      && swiftMutagenHasIdentifierAfter(bytes: bytes, index: operatorEnd)
      && swiftMutagenHasClosingAngleBeforeExpressionDelimiter(bytes: bytes, index: operatorEnd)
  }
  if bytes[operatorStart] == 62 {
    return swiftMutagenHasIdentifierBefore(bytes: bytes, index: operatorStart)
      && swiftMutagenHasOpeningAngleBeforeExpressionDelimiter(bytes: bytes, index: operatorStart)
  }
  return false
}

private func swiftMutagenHasIdentifierBefore(bytes: [UInt8], index: Int) -> Bool {
  index > 0 && swiftMutagenIsExpressionByte(bytes[index - 1])
}

private func swiftMutagenIsOperatorFunctionDeclaration(bytes: [UInt8], operatorStart: Int) -> Bool {
  var offset = operatorStart
  while offset > 0 && swiftMutagenIsHorizontalWhitespace(bytes[offset - 1]) {
    offset -= 1
  }

  let tokenEnd = offset
  while offset > 0 && swiftMutagenIsExpressionByte(bytes[offset - 1]) {
    offset -= 1
  }

  guard tokenEnd > offset else {
    return false
  }
  return String(decoding: bytes[offset..<tokenEnd], as: UTF8.self) == "func"
}

private func swiftMutagenHasIdentifierAfter(bytes: [UInt8], index: Int) -> Bool {
  index < bytes.count && swiftMutagenIsExpressionByte(bytes[index])
}

private func swiftMutagenHasClosingAngleBeforeExpressionDelimiter(bytes: [UInt8], index: Int) -> Bool {
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

private func swiftMutagenHasOpeningAngleBeforeExpressionDelimiter(bytes: [UInt8], index: Int) -> Bool {
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

private func swiftMutagenIsOperatorByte(_ byte: UInt8) -> Bool {
  switch byte {
  case 33, 37, 38, 42, 43, 45, 47, 58, 60, 61, 62, 63, 94, 124, 126:
    return true
  default:
    return false
  }
}

private func swiftMutagenSourceExpression(
  in bytes: [UInt8],
  operatorStart: Int,
  operatorEnd: Int,
  mutatedOperator: String
) -> (original: String, mutated: String) {
  var leftStart = operatorStart
  if !mutatedOperator.isEmpty {
    while leftStart > 0 && swiftMutagenIsHorizontalWhitespace(bytes[leftStart - 1]) {
      leftStart -= 1
    }
    while leftStart > 0 && swiftMutagenIsExpressionByte(bytes[leftStart - 1]) {
      leftStart -= 1
    }
  }

  var rightEnd = operatorEnd
  while rightEnd < bytes.count && swiftMutagenIsHorizontalWhitespace(bytes[rightEnd]) {
    rightEnd += 1
  }
  while rightEnd < bytes.count && swiftMutagenIsExpressionByte(bytes[rightEnd]) {
    rightEnd += 1
  }

  let original = String(decoding: bytes[leftStart..<rightEnd], as: UTF8.self)
  let mutatedPrefix = String(decoding: bytes[leftStart..<operatorStart], as: UTF8.self)
  let mutatedSuffix = String(decoding: bytes[operatorEnd..<rightEnd], as: UTF8.self)
  return (original, mutatedPrefix + mutatedOperator + mutatedSuffix)
}

private func swiftMutagenIsHorizontalWhitespace(_ byte: UInt8) -> Bool {
  byte == 32 || byte == 9
}

private func swiftMutagenIsExpressionByte(_ byte: UInt8) -> Bool {
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

private func swiftMutagenSwiftSourcePaths(config: SwiftMutagenConfig) -> [String] {
  var paths: [String] = []
  for path in config.sourceFiles {
    if swiftMutagenPathIsIncluded(path, config: config) {
      paths.append(path)
    }
  }
  return paths
}

private func swiftMutagenPathIsIncluded(
  _ path: String,
  config: SwiftMutagenConfig
) -> Bool {
  if !config.packageRoot.isEmpty && !path.hasPrefix(config.packageRoot + "/") {
    return false
  }
  if !config.sourceFiles.isEmpty && !swiftMutagenPathIsConfiguredSource(path, config: config) {
    return false
  }
  for fragment in config.excludePathFragments {
    if path.contains(fragment) {
      return false
    }
  }
  return true
}

private func swiftMutagenPathIsConfiguredSource(
  _ path: String,
  config: SwiftMutagenConfig
) -> Bool {
  for sourcePath in config.sourceFiles {
    if path == sourcePath {
      return true
    }
  }
  return false
}

private func swiftMutagenIncludedSourcePath(
  _ path: String,
  config: SwiftMutagenConfig
) -> String? {
  if swiftMutagenPathIsIncluded(path, config: config) {
    return path
  }
  let suffix = path.hasPrefix("/") ? path : "/" + path
  for sourceFile in config.sourceFiles {
    if sourceFile.hasSuffix(suffix),
       swiftMutagenPathIsIncluded(sourceFile, config: config) {
      return sourceFile
    }
  }
  return nil
}

private func swiftMutagenTrimPackageRoot(
  _ path: String,
  config: SwiftMutagenConfig
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

private func swiftMutagenCreateParentDirectories(forFile path: String) {
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

private func swiftMutagenRead(_ path: String) -> String? {
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

private func swiftMutagenWrite(
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

private func swiftMutagenJSONStringValue(_ key: String, in json: String) -> String? {
  let bytes = Array(json.utf8)
  let keyBytes = Array(("\"" + key + "\"").utf8)
  guard let keyIndex = swiftMutagenFind(keyBytes, in: bytes, startingAt: 0) else {
    return nil
  }

  var index = keyIndex + keyBytes.count
  swiftMutagenSkipJSONWhitespace(in: bytes, index: &index)
  guard index < bytes.count, bytes[index] == 58 else {
    return nil
  }
  index += 1
  swiftMutagenSkipJSONWhitespace(in: bytes, index: &index)
  return swiftMutagenParseJSONString(in: bytes, index: &index)
}

private func swiftMutagenJSONStringArray(_ key: String, in json: String) -> [String] {
  let bytes = Array(json.utf8)
  let keyBytes = Array(("\"" + key + "\"").utf8)
  guard let keyIndex = swiftMutagenFind(keyBytes, in: bytes, startingAt: 0) else {
    return []
  }

  var index = keyIndex + keyBytes.count
  swiftMutagenSkipJSONWhitespace(in: bytes, index: &index)
  guard index < bytes.count, bytes[index] == 58 else {
    return []
  }
  index += 1
  swiftMutagenSkipJSONWhitespace(in: bytes, index: &index)
  guard index < bytes.count, bytes[index] == 91 else {
    return []
  }
  index += 1

  var values: [String] = []
  while index < bytes.count {
    swiftMutagenSkipJSONWhitespace(in: bytes, index: &index)
    guard index < bytes.count else {
      break
    }
    if bytes[index] == 93 {
      break
    }
    if let value = swiftMutagenParseJSONString(in: bytes, index: &index) {
      values.append(value)
    } else {
      index += 1
    }
  }
  return values
}

private func swiftMutagenParseJSONString(in bytes: [UInt8], index: inout Int) -> String? {
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

private func swiftMutagenSkipJSONWhitespace(in bytes: [UInt8], index: inout Int) {
  while index < bytes.count {
    switch bytes[index] {
    case 32, 10, 13, 9:
      index += 1
    default:
      return
    }
  }
}

private func swiftMutagenFind(_ needle: [UInt8], in haystack: [UInt8], startingAt start: Int) -> Int? {
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

private func swiftMutagenFormatMutantID(_ ordinal: Int) -> String {
  if ordinal < 10 {
    return "M00\(ordinal)"
  }
  if ordinal < 100 {
    return "M0\(ordinal)"
  }
  return "M\(ordinal)"
}

private func swiftMutagenEscapeJSON(_ value: String) -> String {
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
