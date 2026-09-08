//===--- SwiftmutSourceFacts.h - Retained inlining provenance -------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2026 Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

#ifndef SWIFT_SIL_SWIFTMUTSOURCEFACTS_H
#define SWIFT_SIL_SWIFTMUTSOURCEFACTS_H

namespace swift {
class SILInstruction;

/// Retain AST handles discarded by mandatory inlining without changing
/// diagnostic locations or debug scopes. No mutation work runs here.
void recordSwiftmutInlinedSource(const SILInstruction *original,
                                const SILInstruction *cloned);
void forgetSwiftmutInstructionSource(const SILInstruction *instruction);
} // namespace swift

#endif
