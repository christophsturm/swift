//===--- SourceNode.swift - Retained AST facts -------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2026 Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

import SILBridging
import AST

/// A snapshot of one node in the compiler's existing typechecked AST.
///
/// Identities are transient handles for relating SIL locations to this
/// snapshot. They must not be persisted as source or mutation identities.
public struct SourceNode {
  public struct Position {
    public let line: Int
    public let column: Int
    public let utf8Offset: Int
  }

  public let identity: Int
  public let parent: Int
  public let semanticExpression: Int
  public let referencedDeclaration: Int
  public let value: Int
  public let callee: Int
  public let category: String
  public let kind: String
  public let role: String
  public let file: String
  public let declarationName: String
  public let declarationModule: String
  public let typeName: String
  public let typeModule: String
  public let literalKind: String
  public let closureParameterCount: Int
  public let start: Position
  public let end: Position
  public let isImplicit: Bool
  public let isLocalDeclaration: Bool
  public let isConstantDeclaration: Bool
  public let isOptionalType: Bool
  public let isVoidType: Bool

  fileprivate init(_ node: BridgedSourceNode) {
    identity = node.identity
    parent = node.parent
    semanticExpression = node.semanticExpression
    referencedDeclaration = node.referencedDeclaration
    value = node.value
    callee = node.callee
    category = StringRef(bridged: node.category).string
    kind = StringRef(bridged: node.kind).string
    role = StringRef(bridged: node.role).string
    file = StringRef(bridged: node.file).string
    declarationName = StringRef(bridged: node.declarationName).string
    declarationModule = StringRef(bridged: node.declarationModule).string
    typeName = StringRef(bridged: node.typeName).string
    typeModule = StringRef(bridged: node.typeModule).string
    literalKind = StringRef(bridged: node.literalKind).string
    closureParameterCount = node.closureParameterCount
    start = Position(line: node.startLine, column: node.startColumn, utf8Offset: node.startOffset)
    end = Position(line: node.endLine, column: node.endColumn, utf8Offset: node.endOffset)
    isImplicit = node.implicit
    isLocalDeclaration = node.localDeclaration
    isConstantDeclaration = node.constantDeclaration
    isOptionalType = node.optionalType
    isVoidType = node.voidType
  }
}

extension Context {
  /// Snapshots nodes in already typechecked primary files. Nil means the
  /// required compiler syntax was not cached; this method cannot parse it.
  public func sourceNodes() -> [SourceNode]? {
    var nodes: [SourceNode] = []
    let complete = withUnsafeMutablePointer(to: &nodes) { pointer in
      _bridged.visitSourceNodes(pointer) { context, node in
        context.assumingMemoryBound(to: [SourceNode].self).pointee.append(SourceNode(node))
      }
    }
    return complete ? nodes : nil
  }
}

extension Location {
  /// The location's AST node followed by its inlined call-site ancestors.
  /// Only compiler handles are inspected; no diagnostic text is produced.
  public var astProvenance: [Int] {
    var identities: [Int] = []
    withUnsafeMutablePointer(to: &identities) { pointer in
      bridged.visitASTProvenance(pointer) { context, identity in
        context.assumingMemoryBound(to: [Int].self).pointee.append(identity)
      }
    }
    return identities
  }
}
