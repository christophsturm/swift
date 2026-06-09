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

var swiftmutNextOrdinal = 1
var swiftmutHasTruncatedDiscoveryOutput = false
var swiftmutConditionSourceLocationMissSamples = 0

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

  if swiftmutIsRuntimeSupportFunctionName(function.name.string) {
    if shouldLogFunction {
      swiftmutLogEvent(
        "functionSkip",
        config: config,
        fields: [
          ("reason", "generatedRuntimeSupport"),
          ("module", moduleName),
          ("function", function.name.string)
        ])
    }
    return
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
