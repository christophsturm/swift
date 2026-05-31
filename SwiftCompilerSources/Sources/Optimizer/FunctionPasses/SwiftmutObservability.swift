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

import SIL

func swiftmutModeName(_ mode: SwiftmutMode) -> String {
  switch mode {
  case .discover:
    return "discover"
  case .apply:
    return "apply"
  case .metamutant:
    return "metamutant"
  }
}

func swiftmutShouldLog(
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

func swiftmutLogEvent(
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

func swiftmutLogAssignmentValueSourceLocationMiss(
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

func swiftmutLogConditionSourceLocationMiss(
  branch: CondBranchInst,
  comparison: BuiltinInst?,
  mutation: SwiftmutMutation,
  moduleName: String,
  functionName: String,
  config: SwiftmutConfig
) {
  swiftmutLogEvent(
    "conditionSourceLocationMiss",
    config: config,
    fields: [
      ("mode", swiftmutModeName(config.mode)),
      ("module", moduleName),
      ("function", functionName),
      ("functionLocation", branch.parentFunction.location.description),
      ("branchLocation", branch.location.description),
      ("conditionLocation", branch.condition.definingInstruction?.location.description ?? "<no defining instruction>"),
      ("conditionType", branch.condition.type.description),
      ("conditionKind", comparison == nil ? "generic" : "comparison"),
      ("comparisonBuiltin", comparison.flatMap(swiftmutComparisonBuiltinIDName) ?? ""),
      ("mutator", mutation.mutator),
      ("mutatedBuiltinName", mutation.mutatedBuiltinName),
      ("sourceOriginal", mutation.sourceOriginal),
      ("sourceMutated", mutation.sourceMutated)
    ])
}

func swiftmutLogReturnSourceLocationMiss(
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

func swiftmutFunctionName(_ functionName: String, belongsToModule moduleName: String) -> Bool {
  let mangledModulePrefix = "$s\(moduleName.utf8.count)\(moduleName)"
  if functionName.hasPrefix(mangledModulePrefix) {
    return true
  }
  return functionName.hasPrefix("@\(mangledModulePrefix)")
}

func swiftmutClockMicroseconds() -> UInt64 {
  #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(Linux) || os(Android)
  var now = timeval()
  gettimeofday(&now, nil)
  return UInt64(now.tv_sec) * 1_000_000 + UInt64(now.tv_usec)
  #else
  return 0
  #endif
}
