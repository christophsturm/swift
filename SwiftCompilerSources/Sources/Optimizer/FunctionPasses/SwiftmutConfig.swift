// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for Swift project authors

import SIL
import SwiftmutSupport

typealias SwiftmutMode = SwiftmutSupport.SwiftmutMode
typealias SwiftmutConditionMutationRule = SwiftmutSupport.SwiftmutConditionMutationRule
typealias SwiftmutArithmeticMutationRule = SwiftmutSupport.SwiftmutArithmeticMutationRule
typealias SwiftmutContextualArithmeticMutationRule = SwiftmutSupport.SwiftmutContextualArithmeticMutationRule
typealias SwiftmutReturnMutationRule = SwiftmutSupport.SwiftmutReturnMutationRule
typealias SwiftmutVoidCallMutationRule = SwiftmutSupport.SwiftmutVoidCallMutationRule
typealias SwiftmutSourceMutationDisplayRule = SwiftmutSupport.SwiftmutSourceMutationDisplayRule
typealias SwiftmutConfig = SwiftmutSupport.SwiftmutConfig

func swiftmutLoadedConfig() -> SwiftmutConfig? {
  SwiftmutSupport.swiftmutCachedConfig()
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
