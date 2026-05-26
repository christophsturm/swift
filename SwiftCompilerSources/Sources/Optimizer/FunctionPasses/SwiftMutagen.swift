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

import SIL

private enum SwiftMutagenMode {
  case discover
  case apply
}

private struct SwiftMutagenConfig {
  static let defaultPath = ".mutagen/session/compiler-config.json"

  let mode: SwiftMutagenMode
  let activeMutantID: String
  let mutantsPath: String
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
    default:
      return nil
    }

    guard let mutantsPath = swiftMutagenJSONStringValue("manifestPath", in: json),
          !mutantsPath.isEmpty else {
      return nil
    }

    let activeMutantID = swiftMutagenJSONStringValue("activeMutantID", in: json) ?? ""
    let packageRoot = swiftMutagenJSONStringValue("packageRoot", in: json) ?? ""
    let excludePaths = swiftMutagenJSONStringArray("excludePaths", in: json)
    let sourceFiles = swiftMutagenJSONStringArray("sourceFiles", in: json)
    let enabledMutators = swiftMutagenJSONStringArray("enabledMutators", in: json)

    return SwiftMutagenConfig(
      mode: mode,
      activeMutantID: activeMutantID,
      mutantsPath: mutantsPath,
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
  let originalID: BuiltinInst.ID
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

private var swiftMutagenNextOrdinal = 1
private var swiftMutagenHasTruncatedDiscoveryOutput = false

let swiftMutagen = FunctionPass(name: "swift-mutagen") {
  (function: Function, context: FunctionPassContext) in

  guard let config = SwiftMutagenConfig.load() else {
    return
  }

  if swiftMutagenShouldExclude(function: function, config: config) {
    return
  }

  let moduleName = context.moduleDecl.name.string
  let functionName = function.name.string
  var changed = false

  for block in function.blocks {
    for instruction in block.instructions {
      guard let builtin = instruction as? BuiltinInst else {
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
        }
      }
    }
  }

  if changed {
    context.notifyInstructionsChanged()
  }
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

private func swiftMutagenSourceLocation(
  for instruction: Instruction,
  function: Function,
  moduleName: String,
  mutation: SwiftMutagenMutation,
  config: SwiftMutagenConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  if let fileNameAndPosition = instruction.location.fileNameAndPosition {
    let path = fileNameAndPosition.path.string
    guard swiftMutagenPathIsIncluded(path, config: config) else {
      return nil
    }
    return (
      swiftMutagenTrimPackageRoot(path, config: config),
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
  switch function.sourceFileKind {
  case .library?, .main?:
    break
  default:
    return true
  }

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
    if mutation.originalID == .SAddOver {
      operatorPairs = [("+=", "-="), ("+", "-")]
    } else if mutation.originalID == .SSubOver {
      operatorPairs = [("-=", "+="), ("-", "+")]
    } else {
      operatorPairs = [(mutation.sourceOriginal, mutation.sourceMutated)]
    }
  } else if mutation.mutator == "INVERT_NEGS" {
    operatorPairs = [("-", "")]
  } else if mutation.mutator == "NEGATE_CONDITIONALS" {
    switch mutation.originalID {
    case .ICMP_EQ:
      operatorPairs = [("==", "!=")]
    case .ICMP_NE:
      operatorPairs = [("!=", "==")]
    case .ICMP_SGE, .ICMP_UGE:
      operatorPairs = [(">=", "<"), ("<=", ">")]
    case .ICMP_SGT, .ICMP_UGT:
      operatorPairs = [(">", "<="), ("<", ">=")]
    case .ICMP_SLE, .ICMP_ULE:
      operatorPairs = [("<=", ">"), (">=", "<")]
    case .ICMP_SLT, .ICMP_ULT:
      operatorPairs = [("<", ">="), (">", "<=")]
    default:
      operatorPairs = [(mutation.sourceOriginal, mutation.sourceMutated)]
    }
  } else if mutation.mutator == "CONDITIONALS_BOUNDARY" {
    switch mutation.originalID {
    case .ICMP_SGE, .ICMP_UGE:
      operatorPairs = [(">=", ">"), ("<=", "<")]
    case .ICMP_SGT, .ICMP_UGT:
      operatorPairs = [(">", ">="), ("<", "<=")]
    case .ICMP_SLE, .ICMP_ULE:
      operatorPairs = [("<=", "<"), (">=", ">")]
    case .ICMP_SLT, .ICMP_ULT:
      operatorPairs = [("<", "<="), (">", ">=")]
    default:
      operatorPairs = [(mutation.sourceOriginal, mutation.sourceMutated)]
    }
  } else {
    switch mutation.originalID {
    case .SAddOver, .Add, .FAdd:
      operatorPairs = [("+", "-")]
    case .SSubOver, .Sub, .FSub:
      operatorPairs = [("-", "+")]
    default:
      operatorPairs = [(mutation.sourceOriginal, mutation.sourceMutated)]
    }
  }

  let preferredPrefix = config.packageRoot + "/Sources/" + moduleName + "/"
  let sourcePaths = swiftMutagenSwiftSourcePaths(config: config)
  var hasModuleSource = false
  let orderedSourcePaths = sourcePaths.sorted {
    let lhsMatches = functionLocation.contains($0)
    let rhsMatches = functionLocation.contains($1)
    if lhsMatches != rhsMatches {
      return lhsMatches
    }
    return $0 < $1
  }

  for path in orderedSourcePaths {
    if path.hasPrefix(preferredPrefix) {
      hasModuleSource = true
      break
    }
  }
  guard hasModuleSource else {
    return nil
  }

  var fallback: (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)?

  for path in sourcePaths {
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
        let result = (
          swiftMutagenTrimPackageRoot(path, config: config),
          position.line,
          position.column,
          position.sourceOriginal,
          position.sourceMutated)
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
