// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for Swift project authors

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
import Darwin
#elseif os(Linux) || os(Android)
import Glibc
#endif

// Demangles through the Swift runtime hosted in this frontend process, so
// emitted names always match the mangling scheme of this exact compiler.
private typealias SwiftmutDemangleFunction = @convention(c) (
  UnsafePointer<CChar>?,
  Int,
  UnsafeMutablePointer<CChar>?,
  UnsafeMutablePointer<Int>?,
  UInt32
) -> UnsafeMutablePointer<CChar>?

private let swiftmutRuntimeDemangle: SwiftmutDemangleFunction? = {
  guard let handle = dlopen(nil, RTLD_NOW),
        let symbol = dlsym(handle, "swift_demangle") else {
    return nil
  }
  return unsafeBitCast(symbol, to: SwiftmutDemangleFunction.self)
}()

func swiftmutDemangledFunctionName(_ mangledName: String) -> String? {
  guard mangledName.hasPrefix("$s") || mangledName.hasPrefix("_$s"),
        let demangle = swiftmutRuntimeDemangle else {
    return nil
  }
  return mangledName.withCString { cString in
    guard let buffer = demangle(cString, strlen(cString), nil, nil, 0) else {
      return nil
    }
    defer { free(buffer) }
    let demangled = String(cString: buffer)
    // The runtime echoes the input back when it cannot demangle.
    return demangled == mangledName ? nil : demangled
  }
}

func swiftmutDemangledFunctionJSONField(_ function: String) -> String? {
  guard let demangled = swiftmutDemangledFunctionName(function) else {
    return nil
  }
  return #""demangledFunction":"\#(swiftmutEscapeJSON(demangled))""#
}

func swiftmutWriteMetamutantFragment(
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

func swiftmutConditionSiteJSON(_ site: SwiftmutConditionSite) -> String {
  var fields: [String] = []
  fields.append(#""siteID":\#(site.siteID)"#)
  fields.append(#""module":"\#(swiftmutEscapeJSON(site.module))""#)
  fields.append(#""function":"\#(swiftmutEscapeJSON(site.function))""#)
  if let demangledField = swiftmutDemangledFunctionJSONField(site.function) {
    fields.append(demangledField)
  }
  fields.append(
    #""sourceLocation":{"file":"\#(swiftmutEscapeJSON(site.file))","line":\#(site.line),"column":\#(site.column)}"#
  )
  fields.append(#""siteKind":"condition""#)
  fields.append(#""resultKind":"condition""#)
  fields.append(#""alternatives":[\#(site.alternatives.map(swiftmutConditionAlternativeJSON).joined(separator: ","))]"#)
  return "{\(fields.joined(separator: ","))}"
}

private func swiftmutConditionAlternativeJSON(_ alternative: SwiftmutConditionAlternative) -> String {
  swiftmutAlternativeJSON(
    mutantID: alternative.mutantID,
    alternativeIndex: alternative.alternativeIndex,
    mutation: alternative.mutation)
}

func swiftmutArithmeticSiteJSON(_ site: SwiftmutArithmeticSite) -> String {
  swiftmutValueSiteJSON(
    siteID: site.siteID,
    module: site.module,
    function: site.function,
    file: site.file,
    line: site.line,
    column: site.column,
    siteKind: "arithmetic",
    alternatives: site.alternatives.map(swiftmutArithmeticAlternativeJSON))
}

private func swiftmutArithmeticAlternativeJSON(_ alternative: SwiftmutArithmeticAlternative) -> String {
  swiftmutAlternativeJSON(
    mutantID: alternative.mutantID,
    alternativeIndex: alternative.alternativeIndex,
    mutation: alternative.mutation)
}

func swiftmutScalarValueSiteJSON(_ site: SwiftmutScalarValueSite) -> String {
  swiftmutValueSiteJSON(
    siteID: site.siteID,
    module: site.module,
    function: site.function,
    file: site.file,
    line: site.line,
    column: site.column,
    siteKind: "scalarValue",
    alternatives: site.alternatives.map(swiftmutScalarValueAlternativeJSON))
}

private func swiftmutScalarValueAlternativeJSON(_ alternative: SwiftmutScalarValueAlternative) -> String {
  swiftmutAlternativeJSON(
    mutantID: alternative.mutantID,
    alternativeIndex: alternative.alternativeIndex,
    mutation: alternative.mutation)
}

func swiftmutValueApplySiteJSON(_ site: SwiftmutValueApplySite) -> String {
  swiftmutValueSiteJSON(
    siteID: site.siteID,
    module: site.module,
    function: site.function,
    file: site.file,
    line: site.line,
    column: site.column,
    siteKind: "valueApply",
    alternatives: site.alternatives.map(swiftmutValueApplyAlternativeJSON))
}

private func swiftmutValueApplyAlternativeJSON(_ alternative: SwiftmutValueApplyAlternative) -> String {
  swiftmutAlternativeJSON(
    mutantID: alternative.mutantID,
    alternativeIndex: alternative.alternativeIndex,
    mutation: alternative.mutation)
}

func swiftmutAssignmentValueSiteJSON(_ site: SwiftmutAssignmentValueSite) -> String {
  swiftmutValueSiteJSON(
    siteID: site.siteID,
    module: site.module,
    function: site.function,
    file: site.file,
    line: site.line,
    column: site.column,
    siteKind: "assignmentValue",
    alternatives: site.alternatives.map(swiftmutAssignmentValueAlternativeJSON))
}

private func swiftmutAssignmentValueAlternativeJSON(_ alternative: SwiftmutAssignmentValueAlternative) -> String {
  swiftmutAlternativeJSON(
    mutantID: alternative.mutantID,
    alternativeIndex: alternative.alternativeIndex,
    mutation: alternative.mutation)
}

func swiftmutReturnSiteJSON(_ site: SwiftmutReturnSite) -> String {
  swiftmutReturnSiteJSON(
    siteID: site.siteID,
    module: site.module,
    function: site.function,
    file: site.file,
    line: site.line,
    column: site.column,
    siteKind: "returnValue",
    alternatives: site.alternatives.map(swiftmutReturnAlternativeJSON))
}

func swiftmutReturnBranchSiteJSON(_ site: SwiftmutReturnBranchSite) -> String {
  swiftmutReturnSiteJSON(
    siteID: site.siteID,
    module: site.module,
    function: site.function,
    file: site.file,
    line: site.line,
    column: site.column,
    siteKind: "returnBranchValue",
    alternatives: site.alternatives.map(swiftmutReturnAlternativeJSON))
}

private func swiftmutReturnAlternativeJSON(_ alternative: SwiftmutReturnAlternative) -> String {
  swiftmutAlternativeJSON(
    mutantID: alternative.mutantID,
    alternativeIndex: alternative.alternativeIndex,
    mutation: alternative.mutation)
}

func swiftmutVoidCallSiteJSON(_ site: SwiftmutVoidCallSite) -> String {
  var fields: [String] = []
  fields.append(#""siteID":\#(site.siteID)"#)
  fields.append(#""module":"\#(swiftmutEscapeJSON(site.module))""#)
  fields.append(#""function":"\#(swiftmutEscapeJSON(site.function))""#)
  if let demangledField = swiftmutDemangledFunctionJSONField(site.function) {
    fields.append(demangledField)
  }
  fields.append(
    #""sourceLocation":{"file":"\#(swiftmutEscapeJSON(site.file))","line":\#(site.line),"column":\#(site.column)}"#
  )
  fields.append(#""siteKind":"voidCall""#)
  fields.append(#""resultKind":"statement""#)
  fields.append(#""alternatives":[\#(site.alternatives.map(swiftmutVoidCallAlternativeJSON).joined(separator: ","))]"#)
  return "{\(fields.joined(separator: ","))}"
}

private func swiftmutVoidCallAlternativeJSON(_ alternative: SwiftmutVoidCallAlternative) -> String {
  swiftmutAlternativeJSON(
    mutantID: alternative.mutantID,
    alternativeIndex: alternative.alternativeIndex,
    mutation: alternative.mutation)
}

private func swiftmutValueSiteJSON(
  siteID: UInt64,
  module: String,
  function: String,
  file: String,
  line: Int,
  column: Int,
  siteKind: String,
  alternatives: [String]
) -> String {
  var fields: [String] = []
  fields.append(#""siteID":\#(siteID)"#)
  fields.append(#""module":"\#(swiftmutEscapeJSON(module))""#)
  fields.append(#""function":"\#(swiftmutEscapeJSON(function))""#)
  if let demangledField = swiftmutDemangledFunctionJSONField(function) {
    fields.append(demangledField)
  }
  fields.append(#""sourceLocation":{"file":"\#(swiftmutEscapeJSON(file))","line":\#(line),"column":\#(column)}"#)
  fields.append(#""siteKind":"\#(siteKind)""#)
  fields.append(#""resultKind":"value""#)
  fields.append(#""alternatives":[\#(alternatives.joined(separator: ","))]"#)
  return "{\(fields.joined(separator: ","))}"
}

private func swiftmutReturnSiteJSON(
  siteID: UInt64,
  module: String,
  function: String,
  file: String,
  line: Int,
  column: Int,
  siteKind: String,
  alternatives: [String]
) -> String {
  var fields: [String] = []
  fields.append(#""siteID":\#(siteID)"#)
  fields.append(#""module":"\#(swiftmutEscapeJSON(module))""#)
  fields.append(#""function":"\#(swiftmutEscapeJSON(function))""#)
  if let demangledField = swiftmutDemangledFunctionJSONField(function) {
    fields.append(demangledField)
  }
  fields.append(
    #""sourceLocation":{"file":"\#(swiftmutEscapeJSON(file))","line":\#(line),"column":\#(column)}"#
  )
  fields.append(#""siteKind":"\#(siteKind)""#)
  fields.append(#""resultKind":"returnValue""#)
  fields.append(#""alternatives":[\#(alternatives.joined(separator: ","))]"#)
  return "{\(fields.joined(separator: ","))}"
}

func swiftmutAlternativeJSON(
  mutantID: String,
  alternativeIndex: UInt32,
  mutation: SwiftmutMutation
) -> String {
  var fields: [String] = []
  fields.append(#""mutantID":"\#(swiftmutEscapeJSON(mutantID))""#)
  fields.append(#""alternativeIndex":\#(alternativeIndex)"#)
  fields.append(#""mutator":"\#(swiftmutEscapeJSON(mutation.mutator))""#)
  fields.append(#""sourceOriginal":"\#(swiftmutEscapeJSON(mutation.sourceOriginal))""#)
  fields.append(#""sourceMutated":"\#(swiftmutEscapeJSON(mutation.sourceMutated))""#)
  fields.append(#""behaviorKey":"\#(swiftmutEscapeJSON(mutation.silMutated))""#)
  return "{\(fields.joined(separator: ","))}"
}

func swiftmutStableSiteID(
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

func swiftmutStableHash(_ text: String) -> UInt64 {
  var hash: UInt64 = 0xcbf29ce484222325
  for byte in text.utf8 {
    hash ^= UInt64(byte)
    hash = hash &* 0x100000001b3
  }
  return hash
}

func swiftmutHex(_ value: UInt64) -> String {
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
