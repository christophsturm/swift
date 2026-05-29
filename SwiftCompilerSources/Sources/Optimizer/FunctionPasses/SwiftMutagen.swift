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

  if swiftMutagenIsGeneratedFunctionClone(function.name.string) {
    if shouldLogFunction {
      swiftMutagenLogEvent(
        "functionSkip",
        config: config,
        fields: [
          ("reason", "generatedClone"),
          ("module", moduleName),
          ("function", function.name.string)
        ])
    }
    return
  }

  if swiftMutagenShouldExclude(function: function, config: config) {
    if shouldLogFunction {
      swiftMutagenLogEvent(
        "functionSkip",
        config: config,
        fields: [
          ("reason", "excludedPath"),
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
  let conditionSites = swiftMutagenDiscoverConditionSites(
    in: function,
    moduleName: moduleName,
    config: config
  )
  let arithmeticSites = swiftMutagenDiscoverArithmeticSites(
    in: function,
    moduleName: moduleName,
    config: config
  )
  let returnSites = swiftMutagenDiscoverReturnSites(
    in: function,
    moduleName: moduleName,
    config: config
  )
  let voidCallSites = swiftMutagenDiscoverVoidCallSites(
    in: function,
    moduleName: moduleName,
    config: config
  )
  swiftMutagenLogEvent(
    "metamutantDiscovery",
    config: config,
    fields: [
      ("module", moduleName),
      ("function", function.name.string),
      ("conditionBranches", "\(swiftMutagenConditionBranchCount(in: function))"),
      ("conditionSites", "\(conditionSites.count)"),
      ("arithmeticSites", "\(arithmeticSites.count)"),
      ("voidCallSites", "\(voidCallSites.count)"),
      ("returnSites", "\(returnSites.count)")
    ])
  guard !conditionSites.isEmpty || !arithmeticSites.isEmpty || !returnSites.isEmpty || !voidCallSites.isEmpty else {
    return false
  }

  var changed = false
  var injectedSiteJSON: [String] = []
  var injectedArithmeticSites = 0
  var injectedConditionSites = 0
  var injectedReturnSites = 0
  var injectedVoidCallSites = 0
  for site in arithmeticSites {
    if swiftMutagenInjectArithmeticSite(site, context) {
      injectedSiteJSON.append(swiftMutagenArithmeticSiteJSON(site))
      injectedArithmeticSites += 1
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
    returnSites: returnSites,
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
      ("attemptedReturnSites", "\(returnSites.count)"),
      ("injectedReturnSites", "\(injectedReturnSites)"),
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
) -> [SwiftMutagenVoidCallSite] {
  var sites: [SwiftMutagenVoidCallSite] = []
  var localOrdinal = 1
  let functionName = function.name.string

  for block in function.blocks {
    for instruction in block.instructions {
      guard let apply = instruction as? ApplyInst,
            let mutation = swiftMutagenVoidCallMutation(for: apply, config: config),
            swiftMutagenMutatorIsEnabled(mutation.mutator, config: config),
            let location = swiftMutagenInstructionSourceLocation(
              for: apply,
              mutation: mutation,
              config: config
            ) else {
        continue
      }
      guard swiftMutagenVoidCallSourceLooksLikeStatement(file: location.file, line: location.line, config: config) else {
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

  return sites
}

private func swiftMutagenDiscoverConditionSites(
  in function: Function,
  moduleName: String,
  config: SwiftMutagenConfig
) -> [SwiftMutagenConditionSite] {
  var sites: [SwiftMutagenConditionSite] = []
  var localOrdinal = 1
  let functionName = function.name.string

  for block in function.blocks {
    guard let branch = block.terminator as? CondBranchInst,
          branch.trueOperands.isEmpty,
          branch.falseOperands.isEmpty else {
      continue
    }

    var comparison: BuiltinInst?
    let mutations: [SwiftMutagenMutation]
    if let branchComparison = branch.condition as? BuiltinInst,
       swiftMutagenIsComparisonBuiltin(branchComparison) {
      comparison = branchComparison
      mutations = swiftMutagenConditionSiteMutations(for: branchComparison, config: config)
    } else {
      mutations = swiftMutagenGenericConditionSiteMutations(config: config)
    }
    guard !mutations.isEmpty else {
      continue
    }

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
          continue
        }
      }
      guard let location else {
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

  return sites
}

private func swiftMutagenDiscoverReturnSites(
  in function: Function,
  moduleName: String,
  config: SwiftMutagenConfig
) -> [SwiftMutagenReturnSite] {
  var sites: [SwiftMutagenReturnSite] = []
  var localOrdinal = 1
  let functionName = function.name.string
  guard !functionName.hasSuffix("TW") else {
    return []
  }

  for block in function.blocks {
    guard let returnInst = block.terminator as? ReturnInst else {
      continue
    }

    let mutations = swiftMutagenMetamutantReturnMutations(for: returnInst, config: config)
    guard !mutations.isEmpty else {
      continue
    }

    var alternatives: [SwiftMutagenReturnAlternative] = []
    var sourceLocation: (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)?
    for mutation in mutations {
      guard let location = swiftMutagenReturnSourceLocation(
        for: returnInst,
        mutation: mutation,
        config: config
      ) else {
        continue
      }
      if mutation.sourceOriginal == "return",
         !swiftMutagenReturnSourceLooksLikeStatement(file: location.file, line: location.line, config: config) {
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

  return sites
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

private func swiftMutagenMetamutantReturnMutations(
  for returnInst: ReturnInst,
  config: SwiftMutagenConfig
) -> [SwiftMutagenMutation] {
  swiftMutagenReturnMutations(for: returnInst, config: config).filter { mutation in
    switch mutation.mutatedBuiltinName {
    case "return_false", "return_true", "return_nil", "return_zero":
      return true
    default:
      return false
    }
  }
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
    swiftMutagenCanMakeReturnAlternative($0.mutation, returnType: returnType, in: function)
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
  returnSites: [SwiftMutagenReturnSite],
  voidCallSites: [SwiftMutagenVoidCallSite],
  _ context: FunctionPassContext
) -> Bool {
  for site in conditionSites where swiftMutagenRuntimeVisitFunction(named: site.runtimeFunctionName, context) != nil {
    return true
  }
  for site in arithmeticSites where swiftMutagenRuntimeVisitFunction(named: site.runtimeFunctionName, context) != nil {
    return true
  }
  for site in returnSites where swiftMutagenRuntimeVisitFunction(named: site.runtimeFunctionName, context) != nil {
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
  in function: Function
) -> Bool {
  switch mutation.mutatedBuiltinName {
  case "return_false", "return_true":
    return swiftMutagenIsBoolType(returnType, in: function)
  case "return_nil":
    return returnType.isOptional
  case "return_zero":
    return swiftMutagenIsIntegerStructType(returnType, in: function)
  default:
    return false
  }
}

private func swiftMutagenMakeReturnAlternative(
  _ mutation: SwiftMutagenMutation,
  returnType: Type,
  function: Function,
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
  Builder(atEndOf: trueEdgeBlock, location: location, context).createBranch(to: trueBlock)
  Builder(atEndOf: falseEdgeBlock, location: location, context).createBranch(to: falseBlock)
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
    guard let matchedPath = swiftMutagenIncludedSourcePath(path, config: config) else {
      return nil
    }
    return (
      swiftMutagenTrimPackageRoot(matchedPath, config: config),
      fileNameAndPosition.line,
      fileNameAndPosition.column,
      mutation.sourceOriginal,
      mutation.sourceMutated)
  }

  let location = returnInst.parentFunction.location.description
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

private func swiftMutagenBranchSourceLocation(
  for branch: CondBranchInst,
  mutation: SwiftMutagenMutation,
  config: SwiftMutagenConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  if let fileNameAndPosition = branch.location.fileNameAndPosition {
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

  let location = branch.parentFunction.location.description
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

  return swiftMutagenFindSourceOperator(
    moduleName: moduleName,
    functionLocation: function.location.description,
    mutation: mutation,
    config: config)
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
  let patternBytes = Array(pattern.utf8)
  guard !patternBytes.isEmpty,
        start >= 0,
        start <= end,
        end <= bytes.count,
        patternBytes.count <= end - start else {
    return false
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
      return true
    }
    index += 1
  }
  return false
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

private func swiftMutagenShouldExclude(
  function: Function,
  config: SwiftMutagenConfig
) -> Bool {
  let location = function.location.description
  for fragment in config.excludePathFragments {
    if location.contains(fragment) {
      return true
    }
  }
  return false
}

private func swiftMutagenIsGeneratedFunctionClone(_ function: String) -> Bool {
  function.hasPrefix("$s") && function.contains("Tf4")
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
    }
  }

  return fallback
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
