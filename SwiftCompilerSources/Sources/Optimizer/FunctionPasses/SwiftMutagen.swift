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

private struct SwiftMutagenConfig {
  static let defaultPath = ".mutagen/session/compiler-config.json"

  let mode: SwiftMutagenMode
  let activeMutantID: String
  let mutantsPath: String
  let manifestFragmentsDirectory: String
  let packageRoot: String
  let excludePathFragments: [String]
  let sourceFiles: [String]
  let enabledMutators: [String]

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
    let packageRoot = swiftMutagenJSONStringValue("packageRoot", in: json) ?? ""
    let excludePaths = swiftMutagenJSONStringArray("excludePaths", in: json)
    let sourceFiles = swiftMutagenJSONStringArray("sourceFiles", in: json)
    let enabledMutators = swiftMutagenJSONStringArray("enabledMutators", in: json)

    return SwiftMutagenConfig(
      mode: mode,
      activeMutantID: activeMutantID,
      mutantsPath: mutantsPath,
      manifestFragmentsDirectory: manifestFragmentsDirectory,
      packageRoot: packageRoot,
      excludePathFragments: excludePaths,
      sourceFiles: sourceFiles,
      enabledMutators: enabledMutators)
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
  let module: String
  let function: String
  let file: String
  let line: Int
  let column: Int
  let condition: BuiltinInst
  let branch: CondBranchInst
  let alternatives: [SwiftMutagenConditionAlternative]
}

private var swiftMutagenNextOrdinal = 1
private var swiftMutagenHasTruncatedDiscoveryOutput = false

let swiftMutagen = FunctionPass(name: "swift-mutagen") {
  (function: Function, context: FunctionPassContext) in

  guard let config = SwiftMutagenConfig.load() else {
    return
  }

  let moduleName = context.moduleDecl.name.string
  guard swiftMutagenFunctionName(function.name.string, belongsToModule: moduleName) else {
    return
  }

  if swiftMutagenShouldExclude(function: function, config: config) {
    return
  }

  if config.mode == .metamutant {
    if swiftMutagenInstrumentMetamutantConditionSites(
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
           let mutation = swiftMutagenVoidCallMutation(for: apply),
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

      for mutation in swiftMutagenMutations(for: builtin) {
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

private func swiftMutagenInstrumentMetamutantConditionSites(
  in function: Function,
  moduleName: String,
  config: SwiftMutagenConfig,
  _ context: FunctionPassContext
) -> Bool {
  let sites = swiftMutagenDiscoverConditionSites(
    in: function,
    moduleName: moduleName,
    config: config
  )
  guard !sites.isEmpty else {
    return false
  }

  swiftMutagenWriteMetamutantFragment(sites, config: config)

  var changed = false
  for site in sites {
    if swiftMutagenInjectConditionSite(site, context) {
      changed = true
    }
  }
  return changed
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
          branch.falseOperands.isEmpty,
          let condition = branch.condition as? BuiltinInst,
          swiftMutagenIsComparisonBuiltin(condition) else {
      continue
    }

    let mutations = swiftMutagenConditionSiteMutations(for: condition, config: config)
    guard !mutations.isEmpty else {
      continue
    }

    var alternatives: [SwiftMutagenConditionAlternative] = []
    var sourceLocation: (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)?
    for mutation in mutations {
      guard let location = swiftMutagenSourceLocation(
        for: condition,
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
      module: moduleName,
      function: functionName,
      file: location.file,
      line: location.line,
      column: location.column,
      condition: condition,
      branch: branch,
      alternatives: alternatives
    ))
  }

  return sites
}

private func swiftMutagenConditionSiteMutations(
  for builtin: BuiltinInst,
  config: SwiftMutagenConfig
) -> [SwiftMutagenMutation] {
  var mutations = swiftMutagenMutations(for: builtin)
  mutations.append(SwiftMutagenMutation(
    originalID: builtin.id,
    mutator: "CONDITION_TRUE",
    mutatedBuiltinName: "condition_true",
    sourceOriginal: builtin.name.string,
    sourceMutated: "true",
    silOriginal: builtin.name.string,
    silMutated: "condition_true"))
  mutations.append(SwiftMutagenMutation(
    originalID: builtin.id,
    mutator: "CONDITION_FALSE",
    mutatedBuiltinName: "condition_false",
    sourceOriginal: builtin.name.string,
    sourceMutated: "false",
    silOriginal: builtin.name.string,
    silMutated: "condition_false"))

  return mutations.filter {
    ($0.mutator == "CONDITIONALS_BOUNDARY"
      || $0.mutator == "NEGATE_CONDITIONALS"
      || $0.mutator == "CONDITION_TRUE"
      || $0.mutator == "CONDITION_FALSE")
      && swiftMutagenMutatorIsEnabled($0.mutator, config: config)
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
  guard let visitFunction = context.lookupFunction(name: "__swift_mutagen_visit"),
        let siteID = swiftMutagenMakeRuntimeSiteID(
          site.siteID,
          visitFunction: visitFunction,
          insertionPoint: site.branch,
          context
        ) else {
    return false
  }

  guard let firstArgument = site.condition.arguments.first else {
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
  let rawChoice = dispatchBuilder.createStructExtract(struct: choice, fieldIndex: 0)

  for (index, alternative) in site.alternatives.enumerated() {
    let builder = Builder(atEndOf: alternativeBlocks[index], location: site.branch.location, context)
    let mutatedCondition = swiftMutagenMakeConditionAlternative(
      alternative.mutation,
      originalCondition: site.condition,
      firstArgumentType: firstArgument.type,
      builder: builder
    )
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

private func swiftMutagenMakeConditionAlternative(
  _ mutation: SwiftMutagenMutation,
  originalCondition: BuiltinInst,
  firstArgumentType: Type,
  builder: Builder
) -> Value {
  switch mutation.mutatedBuiltinName {
  case "condition_true":
    return builder.createBoolLiteral(true)
  case "condition_false":
    return builder.createBoolLiteral(false)
  default:
    return builder.createBuiltinBinaryFunction(
      name: mutation.mutatedBuiltinName,
      operandType: firstArgumentType,
      resultType: originalCondition.type,
      arguments: Array(originalCondition.arguments))
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
  guard let fields = parameterType.getNominalFields(in: insertionPoint.parentFunction),
        fields.count == 1 else {
    return nil
  }

  let builder = Builder(before: insertionPoint, context)
  let literal = builder.createIntegerLiteral(siteID, type: fields[0])
  return builder.createStruct(type: parameterType, elements: [literal])
}

private func swiftMutagenWriteMetamutantFragment(
  _ sites: [SwiftMutagenConditionSite],
  config: SwiftMutagenConfig
) {
  guard !config.manifestFragmentsDirectory.isEmpty else {
    return
  }

  var output = #"{"sites":["#
  for (siteIndex, site) in sites.enumerated() {
    if siteIndex != 0 {
      output += ","
    }
    output += swiftMutagenConditionSiteJSON(site)
  }
  output += "]}\n"

  let module = sites.first?.module ?? "module"
  let function = sites.first?.function ?? "function"
  let path = config.manifestFragmentsDirectory
    + "/"
    + swiftMutagenSanitizeFileComponent(module)
    + "-"
    + "\(swiftMutagenProcessID())"
    + "-"
    + swiftMutagenHex(swiftMutagenStableHash(function))
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

private func swiftMutagenReturnMutations(
  for returnInst: ReturnInst,
  config: SwiftMutagenConfig
) -> [SwiftMutagenMutation] {
  let returnedValue = returnInst.returnedValue
  let returnType = returnedValue.type
  var mutations: [SwiftMutagenMutation] = []

  if swiftMutagenIsBoolType(returnType, in: returnInst.parentFunction) {
    let literal = swiftMutagenBoolLiteralValue(returnedValue)
    if literal != false {
      mutations.append(SwiftMutagenMutation(
        originalID: nil,
        mutator: "FALSE_RETURNS",
        mutatedBuiltinName: "return_false",
        sourceOriginal: "return",
        sourceMutated: "return false",
        silOriginal: returnType.description,
        silMutated: "false"))
    }
    if literal != true {
      mutations.append(SwiftMutagenMutation(
        originalID: nil,
        mutator: "TRUE_RETURNS",
        mutatedBuiltinName: "return_true",
        sourceOriginal: "return",
        sourceMutated: "return true",
        silOriginal: returnType.description,
        silMutated: "true"))
    }
    return mutations
  }

  if returnType.isOptional && !swiftMutagenIsOptionalNone(returnedValue) {
    let mutator = swiftMutagenMutatorIsEnabled("EMPTY_RETURNS", config: config)
      ? "EMPTY_RETURNS"
      : "NULL_RETURNS"
    mutations.append(SwiftMutagenMutation(
      originalID: nil,
      mutator: mutator,
      mutatedBuiltinName: "return_nil",
      sourceOriginal: "return",
      sourceMutated: "return nil",
      silOriginal: returnType.description,
      silMutated: "Optional.none"))
    return mutations
  }

  if swiftMutagenIsIntegerStructType(returnType, in: returnInst.parentFunction),
     swiftMutagenIntegerStructLiteralValue(returnedValue) != 0 {
    mutations.append(SwiftMutagenMutation(
      originalID: nil,
      mutator: "PRIMITIVE_RETURNS",
      mutatedBuiltinName: "return_zero",
      sourceOriginal: "return",
      sourceMutated: "return 0",
      silOriginal: returnType.description,
      silMutated: "0"))
  }

  return mutations
}

private func swiftMutagenVoidCallMutation(for apply: ApplyInst) -> SwiftMutagenMutation? {
  guard apply.type.isVoid else {
    return nil
  }

  return SwiftMutagenMutation(
    originalID: nil,
    mutator: "VOID_METHOD_CALLS",
    mutatedBuiltinName: "remove_void_call",
    sourceOriginal: "call",
    sourceMutated: "removed call",
    silOriginal: apply.description,
    silMutated: "removed")
}

private func swiftMutagenMutations(for builtin: BuiltinInst) -> [SwiftMutagenMutation] {
  var mutations: [SwiftMutagenMutation] = []
  switch builtin.id {
  case .ICMP_EQ:
    mutations.append(SwiftMutagenMutation(
      originalID: .ICMP_EQ,
      mutator: "NEGATE_CONDITIONALS",
      mutatedBuiltinName: "cmp_ne",
      sourceOriginal: "==",
      sourceMutated: "!=",
      silOriginal: builtin.name.string,
      silMutated: "cmp_ne"))
  case .ICMP_NE:
    mutations.append(SwiftMutagenMutation(
      originalID: .ICMP_NE,
      mutator: "NEGATE_CONDITIONALS",
      mutatedBuiltinName: "cmp_eq",
      sourceOriginal: "!=",
      sourceMutated: "==",
      silOriginal: builtin.name.string,
      silMutated: "cmp_eq"))
  case .ICMP_SGE:
    mutations.append(SwiftMutagenMutation(
      originalID: .ICMP_SGE,
      mutator: "CONDITIONALS_BOUNDARY",
      mutatedBuiltinName: "cmp_sgt",
      sourceOriginal: ">=",
      sourceMutated: ">",
      silOriginal: builtin.name.string,
      silMutated: "cmp_sgt"))
    mutations.append(SwiftMutagenMutation(
      originalID: .ICMP_SGE,
      mutator: "NEGATE_CONDITIONALS",
      mutatedBuiltinName: "cmp_slt",
      sourceOriginal: ">=",
      sourceMutated: "<",
      silOriginal: builtin.name.string,
      silMutated: "cmp_slt"))
  case .ICMP_SGT:
    mutations.append(SwiftMutagenMutation(
      originalID: .ICMP_SGT,
      mutator: "CONDITIONALS_BOUNDARY",
      mutatedBuiltinName: "cmp_sge",
      sourceOriginal: ">",
      sourceMutated: ">=",
      silOriginal: builtin.name.string,
      silMutated: "cmp_sge"))
    mutations.append(SwiftMutagenMutation(
      originalID: .ICMP_SGT,
      mutator: "NEGATE_CONDITIONALS",
      mutatedBuiltinName: "cmp_sle",
      sourceOriginal: ">",
      sourceMutated: "<=",
      silOriginal: builtin.name.string,
      silMutated: "cmp_sle"))
  case .ICMP_SLE:
    mutations.append(SwiftMutagenMutation(
      originalID: .ICMP_SLE,
      mutator: "CONDITIONALS_BOUNDARY",
      mutatedBuiltinName: "cmp_slt",
      sourceOriginal: "<=",
      sourceMutated: "<",
      silOriginal: builtin.name.string,
      silMutated: "cmp_slt"))
    mutations.append(SwiftMutagenMutation(
      originalID: .ICMP_SLE,
      mutator: "NEGATE_CONDITIONALS",
      mutatedBuiltinName: "cmp_sgt",
      sourceOriginal: "<=",
      sourceMutated: ">",
      silOriginal: builtin.name.string,
      silMutated: "cmp_sgt"))
  case .ICMP_SLT:
    mutations.append(SwiftMutagenMutation(
      originalID: .ICMP_SLT,
      mutator: "CONDITIONALS_BOUNDARY",
      mutatedBuiltinName: "cmp_sle",
      sourceOriginal: "<",
      sourceMutated: "<=",
      silOriginal: builtin.name.string,
      silMutated: "cmp_sle"))
    mutations.append(SwiftMutagenMutation(
      originalID: .ICMP_SLT,
      mutator: "NEGATE_CONDITIONALS",
      mutatedBuiltinName: "cmp_sge",
      sourceOriginal: "<",
      sourceMutated: ">=",
      silOriginal: builtin.name.string,
      silMutated: "cmp_sge"))
  case .ICMP_UGE:
    mutations.append(SwiftMutagenMutation(
      originalID: .ICMP_UGE,
      mutator: "CONDITIONALS_BOUNDARY",
      mutatedBuiltinName: "cmp_ugt",
      sourceOriginal: ">=",
      sourceMutated: ">",
      silOriginal: builtin.name.string,
      silMutated: "cmp_ugt"))
    mutations.append(SwiftMutagenMutation(
      originalID: .ICMP_UGE,
      mutator: "NEGATE_CONDITIONALS",
      mutatedBuiltinName: "cmp_ult",
      sourceOriginal: ">=",
      sourceMutated: "<",
      silOriginal: builtin.name.string,
      silMutated: "cmp_ult"))
  case .ICMP_UGT:
    mutations.append(SwiftMutagenMutation(
      originalID: .ICMP_UGT,
      mutator: "CONDITIONALS_BOUNDARY",
      mutatedBuiltinName: "cmp_uge",
      sourceOriginal: ">",
      sourceMutated: ">=",
      silOriginal: builtin.name.string,
      silMutated: "cmp_uge"))
    mutations.append(SwiftMutagenMutation(
      originalID: .ICMP_UGT,
      mutator: "NEGATE_CONDITIONALS",
      mutatedBuiltinName: "cmp_ule",
      sourceOriginal: ">",
      sourceMutated: "<=",
      silOriginal: builtin.name.string,
      silMutated: "cmp_ule"))
  case .ICMP_ULE:
    mutations.append(SwiftMutagenMutation(
      originalID: .ICMP_ULE,
      mutator: "CONDITIONALS_BOUNDARY",
      mutatedBuiltinName: "cmp_ult",
      sourceOriginal: "<=",
      sourceMutated: "<",
      silOriginal: builtin.name.string,
      silMutated: "cmp_ult"))
    mutations.append(SwiftMutagenMutation(
      originalID: .ICMP_ULE,
      mutator: "NEGATE_CONDITIONALS",
      mutatedBuiltinName: "cmp_ugt",
      sourceOriginal: "<=",
      sourceMutated: ">",
      silOriginal: builtin.name.string,
      silMutated: "cmp_ugt"))
  case .ICMP_ULT:
    mutations.append(SwiftMutagenMutation(
      originalID: .ICMP_ULT,
      mutator: "CONDITIONALS_BOUNDARY",
      mutatedBuiltinName: "cmp_ule",
      sourceOriginal: "<",
      sourceMutated: "<=",
      silOriginal: builtin.name.string,
      silMutated: "cmp_ule"))
    mutations.append(SwiftMutagenMutation(
      originalID: .ICMP_ULT,
      mutator: "NEGATE_CONDITIONALS",
      mutatedBuiltinName: "cmp_uge",
      sourceOriginal: "<",
      sourceMutated: ">=",
      silOriginal: builtin.name.string,
      silMutated: "cmp_uge"))
  case .SAddOver:
    mutations.append(SwiftMutagenMutation(
      originalID: .SAddOver,
      mutator: swiftMutagenIsIncrementBuiltin(builtin) ? "INCREMENTS" : "MATH",
      mutatedBuiltinName: "ssub_with_overflow",
      sourceOriginal: "+",
      sourceMutated: "-",
      silOriginal: builtin.name.string,
      silMutated: "ssub_with_overflow"))
  case .SSubOver:
    if swiftMutagenIsUnaryNegationBuiltin(builtin) {
      mutations.append(SwiftMutagenMutation(
        originalID: .SSubOver,
        mutator: "INVERT_NEGS",
        mutatedBuiltinName: "sadd_with_overflow",
        sourceOriginal: "-",
        sourceMutated: "",
        silOriginal: builtin.name.string,
        silMutated: "sadd_with_overflow"))
    } else {
      mutations.append(SwiftMutagenMutation(
        originalID: .SSubOver,
        mutator: swiftMutagenIsIncrementBuiltin(builtin) ? "INCREMENTS" : "MATH",
        mutatedBuiltinName: "sadd_with_overflow",
        sourceOriginal: "-",
        sourceMutated: "+",
        silOriginal: builtin.name.string,
        silMutated: "sadd_with_overflow"))
    }
  case .Add:
    mutations.append(swiftMutagenBinaryMutation(builtin, mutator: "MATH", mutatedBuiltinName: "sub", sourceOriginal: "+", sourceMutated: "-"))
  case .Sub:
    mutations.append(swiftMutagenBinaryMutation(builtin, mutator: "MATH", mutatedBuiltinName: "add", sourceOriginal: "-", sourceMutated: "+"))
  case .Mul:
    mutations.append(swiftMutagenBinaryMutation(builtin, mutator: "MATH", mutatedBuiltinName: "sdiv", sourceOriginal: "*", sourceMutated: "/"))
  case .SDiv:
    mutations.append(swiftMutagenBinaryMutation(builtin, mutator: "MATH", mutatedBuiltinName: "mul", sourceOriginal: "/", sourceMutated: "*"))
  case .SRem:
    mutations.append(swiftMutagenBinaryMutation(builtin, mutator: "MATH", mutatedBuiltinName: "mul", sourceOriginal: "%", sourceMutated: "*"))
  case .UDiv:
    mutations.append(swiftMutagenBinaryMutation(builtin, mutator: "MATH", mutatedBuiltinName: "mul", sourceOriginal: "/", sourceMutated: "*"))
  case .URem:
    mutations.append(swiftMutagenBinaryMutation(builtin, mutator: "MATH", mutatedBuiltinName: "mul", sourceOriginal: "%", sourceMutated: "*"))
  case .FAdd:
    mutations.append(swiftMutagenBinaryMutation(builtin, mutator: "MATH", mutatedBuiltinName: "fsub", sourceOriginal: "+", sourceMutated: "-"))
  case .FSub:
    mutations.append(swiftMutagenBinaryMutation(builtin, mutator: "MATH", mutatedBuiltinName: "fadd", sourceOriginal: "-", sourceMutated: "+"))
  case .FMul:
    mutations.append(swiftMutagenBinaryMutation(builtin, mutator: "MATH", mutatedBuiltinName: "fdiv", sourceOriginal: "*", sourceMutated: "/"))
  case .FDiv:
    mutations.append(swiftMutagenBinaryMutation(builtin, mutator: "MATH", mutatedBuiltinName: "fmul", sourceOriginal: "/", sourceMutated: "*"))
  case .FRem:
    mutations.append(swiftMutagenBinaryMutation(builtin, mutator: "MATH", mutatedBuiltinName: "fmul", sourceOriginal: "%", sourceMutated: "*"))
  case .And:
    mutations.append(swiftMutagenBinaryMutation(builtin, mutator: "MATH", mutatedBuiltinName: "or", sourceOriginal: "&", sourceMutated: "|"))
  case .Or:
    mutations.append(swiftMutagenBinaryMutation(builtin, mutator: "MATH", mutatedBuiltinName: "and", sourceOriginal: "|", sourceMutated: "&"))
  case .Xor:
    mutations.append(swiftMutagenBinaryMutation(builtin, mutator: "MATH", mutatedBuiltinName: "and", sourceOriginal: "^", sourceMutated: "&"))
  case .Shl:
    mutations.append(swiftMutagenBinaryMutation(builtin, mutator: "MATH", mutatedBuiltinName: "ashr", sourceOriginal: "<<", sourceMutated: ">>"))
  case .AShr, .LShr:
    mutations.append(swiftMutagenBinaryMutation(builtin, mutator: "MATH", mutatedBuiltinName: "shl", sourceOriginal: ">>", sourceMutated: "<<"))
  default:
    break
  }
  return mutations
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
    replacement = builder.createOptionalNone(type: returnType)
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
  return enumInst.type.isOptional && enumInst.caseIndex == Builder.optionalNoneCaseIndex
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

private func swiftMutagenFindSourceOperator(
  moduleName: String,
  functionLocation: String,
  mutation: SwiftMutagenMutation,
  config: SwiftMutagenConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard !config.packageRoot.isEmpty else {
    return nil
  }

  let operatorPairs: [(String, String)]
  if mutation.mutator == "INCREMENTS" {
    if mutation.originalID == .some(.SAddOver) {
      operatorPairs = [("+=", "-="), ("+", "-")]
    } else if mutation.originalID == .some(.SSubOver) {
      operatorPairs = [("-=", "+="), ("-", "+")]
    } else {
      operatorPairs = [(mutation.sourceOriginal, mutation.sourceMutated)]
    }
  } else if mutation.mutator == "INVERT_NEGS" {
    operatorPairs = [("-", "")]
  } else if mutation.mutator == "CONDITION_TRUE" || mutation.mutator == "CONDITION_FALSE" {
    switch mutation.originalID {
    case .some(.ICMP_EQ):
      operatorPairs = [("==", "==")]
    case .some(.ICMP_NE):
      operatorPairs = [("!=", "!=")]
    case .some(.ICMP_SGE), .some(.ICMP_UGE):
      operatorPairs = [(">=", ">="), ("<=", "<=")]
    case .some(.ICMP_SGT), .some(.ICMP_UGT):
      operatorPairs = [(">", ">"), ("<", "<")]
    case .some(.ICMP_SLE), .some(.ICMP_ULE):
      operatorPairs = [("<=", "<="), (">=", ">=")]
    case .some(.ICMP_SLT), .some(.ICMP_ULT):
      operatorPairs = [("<", "<"), (">", ">")]
    default:
      operatorPairs = [(mutation.sourceOriginal, mutation.sourceOriginal)]
    }
  } else if mutation.mutator == "NEGATE_CONDITIONALS" {
    switch mutation.originalID {
    case .some(.ICMP_EQ):
      operatorPairs = [("==", "!=")]
    case .some(.ICMP_NE):
      operatorPairs = [("!=", "==")]
    case .some(.ICMP_SGE), .some(.ICMP_UGE):
      operatorPairs = [(">=", "<"), ("<=", ">")]
    case .some(.ICMP_SGT), .some(.ICMP_UGT):
      operatorPairs = [(">", "<="), ("<", ">=")]
    case .some(.ICMP_SLE), .some(.ICMP_ULE):
      operatorPairs = [("<=", ">"), (">=", "<")]
    case .some(.ICMP_SLT), .some(.ICMP_ULT):
      operatorPairs = [("<", ">="), (">", "<=")]
    default:
      operatorPairs = [(mutation.sourceOriginal, mutation.sourceMutated)]
    }
  } else if mutation.mutator == "CONDITIONALS_BOUNDARY" {
    switch mutation.originalID {
    case .some(.ICMP_SGE), .some(.ICMP_UGE):
      operatorPairs = [(">=", ">"), ("<=", "<")]
    case .some(.ICMP_SGT), .some(.ICMP_UGT):
      operatorPairs = [(">", ">="), ("<", "<=")]
    case .some(.ICMP_SLE), .some(.ICMP_ULE):
      operatorPairs = [("<=", "<"), (">=", ">")]
    case .some(.ICMP_SLT), .some(.ICMP_ULT):
      operatorPairs = [("<", "<="), (">", ">=")]
    default:
      operatorPairs = [(mutation.sourceOriginal, mutation.sourceMutated)]
    }
  } else {
    switch mutation.originalID {
    case .some(.SAddOver), .some(.Add), .some(.FAdd):
      operatorPairs = [("+", "-")]
    case .some(.SSubOver), .some(.Sub), .some(.FSub):
      operatorPairs = [("-", "+")]
    default:
      operatorPairs = [(mutation.sourceOriginal, mutation.sourceMutated)]
    }
  }

  let preferredPrefix = config.packageRoot + "/Sources/" + moduleName + "/"
  let sourcePaths = swiftMutagenSwiftSourcePaths(config: config)
  let orderedSourcePaths = sourcePaths.sorted {
    let lhsMatches = functionLocation.contains($0)
    let rhsMatches = functionLocation.contains($1)
    if lhsMatches != rhsMatches {
      return lhsMatches
    }
    return $0 < $1
  }

  var fallback: (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)?

  for path in orderedSourcePaths {
    guard let text = swiftMutagenRead(path) else {
      continue
    }
    let preferredLine = swiftMutagenPreferredLine(in: functionLocation, path: path)
    var bestForPath: (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)?
    for pair in operatorPairs {
      if let position = swiftMutagenFindOperator(
        pair.0,
        mutatedOperator: pair.1,
        in: text,
        preferredLine: preferredLine
      ) {
        let sourceMutated = mutation.mutator == "CONDITION_TRUE" || mutation.mutator == "CONDITION_FALSE"
          ? mutation.sourceMutated
          : position.sourceMutated
        let result = (
          swiftMutagenTrimPackageRoot(path, config: config),
          position.line,
          position.column,
          position.sourceOriginal,
          sourceMutated)
        if let existing = bestForPath,
           let preferredLine = preferredLine,
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

private func swiftMutagenFindOperator(
  _ op: String,
  mutatedOperator: String,
  in text: String,
  preferredLine: Int?
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
  return true
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
