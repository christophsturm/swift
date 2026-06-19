//===--- SwiftmutConfig.swift ---------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2026 swiftmut contributors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

public enum SwiftmutMode {
  case discover
  case apply
  case metamutant
}

public func swiftmutPipeFields(_ value: String, count expectedCount: Int) -> [String]? {
  var fields: [String] = []
  fields.reserveCapacity(expectedCount)
  var fieldStart = value.startIndex
  var index = value.startIndex

  while index < value.endIndex {
    if value[index] == "|" {
      fields.append(String(value[fieldStart..<index]))
      guard fields.count < expectedCount else {
        return nil
      }
      index = value.index(after: index)
      fieldStart = index
      continue
    }
    index = value.index(after: index)
  }

  fields.append(String(value[fieldStart..<value.endIndex]))
  guard fields.count == expectedCount else {
    return nil
  }
  return fields
}

public struct SwiftmutConditionMutationRule {
  public let builtinID: String
  public let mutator: String
  public let mutatedBuiltinName: String
  public let sourceOriginal: String
  public let sourceMutated: String

  public init?(wireFormat: String) {
    guard let fields = swiftmutPipeFields(wireFormat, count: 5) else {
      return nil
    }
    builtinID = fields[0]
    mutator = fields[1]
    mutatedBuiltinName = fields[2]
    sourceOriginal = fields[3]
    sourceMutated = fields[4]
  }
}

public struct SwiftmutArithmeticMutationRule {
  public let builtinID: String
  public let mutatedBuiltinName: String
  public let sourceOriginal: String
  public let sourceMutated: String

  public init?(wireFormat: String) {
    guard let fields = swiftmutPipeFields(wireFormat, count: 4) else {
      return nil
    }
    builtinID = fields[0]
    mutatedBuiltinName = fields[1]
    sourceOriginal = fields[2]
    sourceMutated = fields[3]
  }
}

public struct SwiftmutContextualArithmeticMutationRule {
  public let builtinID: String
  public let context: String
  public let mutator: String
  public let mutatedBuiltinName: String
  public let sourceOriginal: String
  public let sourceMutated: String

  public init?(wireFormat: String) {
    guard let fields = swiftmutPipeFields(wireFormat, count: 6) else {
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

public struct SwiftmutReturnMutationRule {
  public let context: String
  public let mutator: String
  public let mutatedBuiltinName: String
  public let sourceOriginal: String
  public let sourceMutated: String
  public let silMutated: String

  public init?(wireFormat: String) {
    guard let fields = swiftmutPipeFields(wireFormat, count: 6) else {
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

public struct SwiftmutVoidCallMutationRule {
  public let mutator: String
  public let mutatedBuiltinName: String
  public let sourceOriginal: String
  public let sourceMutated: String
  public let silMutated: String

  public init?(wireFormat: String) {
    guard let fields = swiftmutPipeFields(wireFormat, count: 5) else {
      return nil
    }
    mutator = fields[0]
    mutatedBuiltinName = fields[1]
    sourceOriginal = fields[2]
    sourceMutated = fields[3]
    silMutated = fields[4]
  }
}

public struct SwiftmutSourceMutationDisplayRule {
  public let mutator: String
  public let builtinID: String
  public let sourceOriginal: String
  public let sourceMutated: String
  public let sourceMutatedOverride: String

  public init(
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

  public init?(wireFormat: String) {
    guard let fields = swiftmutPipeFields(wireFormat, count: 5) else {
      return nil
    }
    mutator = fields[0]
    builtinID = fields[1]
    sourceOriginal = fields[2]
    sourceMutated = fields[3]
    sourceMutatedOverride = fields[4]
  }
}

public struct SwiftmutConfig {
  public static let defaultPath = ".swiftmut/session/compiler-config.json"

  public let mode: SwiftmutMode
  public let activeMutantID: String
  public let mutantsPath: String
  public let manifestFragmentsDirectory: String
  public let compilerEventsPath: String
  public let packageRoot: String
  public let excludePathFragments: [String]
  public let sourceFiles: [String]
  public let enabledMutators: [String]
  public let conditionMutationRules: [SwiftmutConditionMutationRule]
  public let arithmeticMutationRules: [SwiftmutArithmeticMutationRule]
  public let contextualArithmeticMutationRules: [SwiftmutContextualArithmeticMutationRule]
  public let returnMutationRules: [SwiftmutReturnMutationRule]
  public let voidCallMutationRules: [SwiftmutVoidCallMutationRule]
  public let sourceMutationDisplayRules: [SwiftmutSourceMutationDisplayRule]

  public init(
    mode: SwiftmutMode,
    activeMutantID: String,
    mutantsPath: String,
    manifestFragmentsDirectory: String,
    compilerEventsPath: String,
    packageRoot: String,
    excludePathFragments: [String],
    sourceFiles: [String],
    enabledMutators: [String],
    conditionMutationRules: [SwiftmutConditionMutationRule],
    arithmeticMutationRules: [SwiftmutArithmeticMutationRule],
    contextualArithmeticMutationRules: [SwiftmutContextualArithmeticMutationRule],
    returnMutationRules: [SwiftmutReturnMutationRule],
    voidCallMutationRules: [SwiftmutVoidCallMutationRule],
    sourceMutationDisplayRules: [SwiftmutSourceMutationDisplayRule]
  ) {
    self.mode = mode
    self.activeMutantID = activeMutantID
    self.mutantsPath = mutantsPath
    self.manifestFragmentsDirectory = manifestFragmentsDirectory
    self.compilerEventsPath = compilerEventsPath
    self.packageRoot = packageRoot
    self.excludePathFragments = excludePathFragments
    self.sourceFiles = sourceFiles
    self.enabledMutators = enabledMutators
    self.conditionMutationRules = conditionMutationRules
    self.arithmeticMutationRules = arithmeticMutationRules
    self.contextualArithmeticMutationRules = contextualArithmeticMutationRules
    self.returnMutationRules = returnMutationRules
    self.voidCallMutationRules = voidCallMutationRules
    self.sourceMutationDisplayRules = sourceMutationDisplayRules
  }

  public static func load(
    read: (String) -> String? = swiftmutRead,
    environment: (String) -> String? = swiftmutEnvironmentValue
  ) -> SwiftmutConfig? {
    let configPath = environment("SWIFTMUT_CONFIG") ?? Self.defaultPath
    return load(configPath: configPath, read: read)
  }

  public static func load(
    configPath: String,
    read: (String) -> String? = swiftmutRead
  ) -> SwiftmutConfig? {
    guard let json = read(configPath) else {
      return nil
    }
    let fields = SwiftmutJSONTopLevelObject(json)
    guard let rawMode = fields.stringValue("mode") else {
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

    guard let mutantsPath = fields.stringValue("manifestPath"),
          !mutantsPath.isEmpty else {
      return nil
    }

    let activeMutantID = fields.stringValue("activeMutantID") ?? ""
    let manifestFragmentsDirectory = fields.stringValue("manifestFragmentsDirectory") ?? ""
    let compilerEventsPath = fields.stringValue("compilerEventsPath") ?? ""
    let packageRoot = fields.stringValue("packageRoot") ?? ""
    let excludePaths = fields.stringArray("excludePaths")
    let sourceFiles = fields.stringArray("sourceFiles")
    let enabledMutators = fields.stringArray("enabledMutators")
    let conditionMutationRules = fields.stringArray("conditionMutationRules").compactMap {
      SwiftmutConditionMutationRule(wireFormat: $0)
    }
    let arithmeticMutationRules = fields.stringArray("arithmeticMutationRules").compactMap {
      SwiftmutArithmeticMutationRule(wireFormat: $0)
    }
    let contextualArithmeticMutationRules = fields.stringArray("contextualArithmeticMutationRules").compactMap {
      SwiftmutContextualArithmeticMutationRule(wireFormat: $0)
    }
    let returnMutationRules = fields.stringArray("returnMutationRules").compactMap {
      SwiftmutReturnMutationRule(wireFormat: $0)
    }
    let voidCallMutationRules = fields.stringArray("voidCallMutationRules").compactMap {
      SwiftmutVoidCallMutationRule(wireFormat: $0)
    }
    let sourceMutationDisplayRules = fields.stringArray("sourceMutationDisplayRules").compactMap {
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

private var swiftmutCachedConfigPath: String?
private var swiftmutCachedConfig: SwiftmutConfig?

public func swiftmutCachedConfig(
  read: (String) -> String? = swiftmutRead,
  environment: (String) -> String? = swiftmutEnvironmentValue
) -> SwiftmutConfig? {
  let configPath = environment("SWIFTMUT_CONFIG") ?? SwiftmutConfig.defaultPath
  if configPath == swiftmutCachedConfigPath {
    return swiftmutCachedConfig
  }
  let config = SwiftmutConfig.load(configPath: configPath, read: read)
  swiftmutCachedConfigPath = configPath
  swiftmutCachedConfig = config
  return config
}

public func swiftmutResetConfigCache() {
  swiftmutCachedConfigPath = nil
  swiftmutCachedConfig = nil
}
