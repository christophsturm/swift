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

  static func load() -> SwiftMutagenConfig? {
    guard let json = swiftMutagenRead(Self.defaultPath),
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

    return SwiftMutagenConfig(
      mode: mode,
      activeMutantID: activeMutantID,
      mutantsPath: mutantsPath,
      packageRoot: packageRoot,
      excludePathFragments: excludePaths,
      sourceFiles: sourceFiles)
  }
}

private struct SwiftMutagenMutation {
  let originalID: BuiltinInst.ID
  let mutatedBuiltinName: String
  let sourceOriginal: String
  let sourceMutated: String
  let silOriginal: String
  let silMutated: String

  func withSource(original: String, mutated: String) -> SwiftMutagenMutation {
    SwiftMutagenMutation(
      originalID: originalID,
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
    fields.append(#""mutator":"ConditionalBoundary""#)
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
      guard let builtin = instruction as? BuiltinInst,
            let mutation = swiftMutagenMutation(for: builtin) else {
        continue
      }

      guard let sourceLocation = swiftMutagenSourceLocation(
        for: builtin,
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

  if changed {
    context.notifyInstructionsChanged()
  }
}

private func swiftMutagenMutation(for builtin: BuiltinInst) -> SwiftMutagenMutation? {
  switch builtin.id {
  case .ICMP_SGT:
    return SwiftMutagenMutation(
      originalID: .ICMP_SGT,
      mutatedBuiltinName: "cmp_sge",
      sourceOriginal: ">",
      sourceMutated: ">=",
      silOriginal: builtin.name.string,
      silMutated: "cmp_sge")
  case .ICMP_SLT:
    return SwiftMutagenMutation(
      originalID: .ICMP_SLT,
      mutatedBuiltinName: "cmp_sle",
      sourceOriginal: "<",
      sourceMutated: "<=",
      silOriginal: builtin.name.string,
      silMutated: "cmp_sle")
  default:
    return nil
  }
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

private func swiftMutagenSourceLocation(
  for instruction: Instruction,
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
  mutation: SwiftMutagenMutation,
  config: SwiftMutagenConfig
) -> (file: String, line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  guard !config.packageRoot.isEmpty else {
    return nil
  }

  let operatorPairs: [(String, String)]
  switch mutation.originalID {
  case .ICMP_SGT:
    operatorPairs = [(">", ">=")]
  case .ICMP_SLT:
    operatorPairs = [("<", "<="), (">", ">=")]
  default:
    operatorPairs = [(mutation.sourceOriginal, mutation.sourceMutated)]
  }

  let preferredPrefix = config.packageRoot + "/Sources/" + moduleName + "/"
  let sourcePaths = swiftMutagenSwiftSourcePaths(config: config)
  var hasModuleSource = false
  for path in sourcePaths {
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
    for pair in operatorPairs {
      if let position = swiftMutagenFindOperator(pair.0, mutatedOperator: pair.1, in: text) {
        let result = (
          swiftMutagenTrimPackageRoot(path, config: config),
          position.line,
          position.column,
          position.sourceOriginal,
          position.sourceMutated)
        if path.hasPrefix(preferredPrefix) {
          return result
        }
        if fallback == nil {
          fallback = result
        }
      }
    }
  }

  return fallback
}

private func swiftMutagenFindOperator(
  _ op: String,
  mutatedOperator: String,
  in text: String
) -> (line: Int, column: Int, sourceOriginal: String, sourceMutated: String)? {
  let bytes = Array(text.utf8)
  let opBytes = Array(op.utf8)
  guard !opBytes.isEmpty else {
    return nil
  }

  var line = 1
  var column = 1
  var index = 0
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
      return (line, column, expression.original, expression.mutated)
    }
    if bytes[index] == 10 {
      line += 1
      column = 1
    } else {
      column += 1
    }
    index += 1
  }
  return nil
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
  while leftStart > 0 && swiftMutagenIsHorizontalWhitespace(bytes[leftStart - 1]) {
    leftStart -= 1
  }
  while leftStart > 0 && swiftMutagenIsExpressionByte(bytes[leftStart - 1]) {
    leftStart -= 1
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
