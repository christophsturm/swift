// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for Swift project authors

import SIL

enum SwiftmutMode {
  case discover
  case apply
  case metamutant
}

struct SwiftmutConditionMutationRule {
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

struct SwiftmutArithmeticMutationRule {
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

struct SwiftmutContextualArithmeticMutationRule {
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

struct SwiftmutReturnMutationRule {
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

struct SwiftmutVoidCallMutationRule {
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

struct SwiftmutSourceMutationDisplayRule {
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

struct SwiftmutConfig {
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

struct SwiftmutMutation {
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
