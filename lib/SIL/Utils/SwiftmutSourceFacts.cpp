//===--- SwiftmutSourceFacts.cpp - Retained AST provenance ------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2026 Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

#include "swift/SIL/SILBridging.h"
#include "swift/SIL/SILBridgingImpl.h"
#include "swift/AST/ASTWalker.h"
#include "swift/AST/Expr.h"
#include "swift/AST/ParseRequests.h"
#include "swift/AST/Pattern.h"
#include "swift/AST/SourceFile.h"
#include "swift/AST/Stmt.h"
#include "swift/Bridging/ASTGen.h"
#include "swift/SIL/SILContext.h"
#include "swift/SIL/SILDebugScope.h"
#include <algorithm>

using namespace swift;

namespace {

SwiftInt identity(ASTNode node) {
  return node ? reinterpret_cast<SwiftInt>(node.getOpaqueValue()) : 0;
}

ASTNode parentNode(ASTWalker::ParentTy parent) {
  if (auto *node = parent.getAsExpr())
    return node;
  if (auto *node = parent.getAsStmt())
    return node;
  if (auto *node = parent.getAsDecl())
    return node;
  if (auto *node = parent.getAsPattern())
    return node;
  return {};
}

struct TokenEnd {
  unsigned start;
  unsigned end;
  unsigned line;
  unsigned column;
};

class SourceNodeWalker final : public ASTWalker {
  SourceFile &sourceFile;
  void *outputContext;
  void (*visit)(void *, BridgedSourceNode);
  SmallVector<TokenEnd, 128> tokens;

  StringRef role(Expr *expression) {
    if (auto *statement = Parent.getAsStmt()) {
      if (isa<BraceStmt>(statement))
        return "statement";
      if (auto *returned = dyn_cast<ReturnStmt>(statement)) {
        if (returned->getResult() == expression)
          return "returnedValue";
      }
      if (auto *conditional = dyn_cast<LabeledConditionalStmt>(statement)) {
        for (const auto &condition : conditional->getCond()) {
          if (condition.getBooleanOrNull() == expression)
            return "condition";
          if (condition.getInitializerOrNull() == expression)
            return "conditionBinding";
        }
      }
      if (auto *loop = dyn_cast<RepeatWhileStmt>(statement)) {
        if (loop->getCond() == expression)
          return "condition";
      }
      if (auto *loop = dyn_cast<ForEachStmt>(statement)) {
        if (loop->getWhere() == expression)
          return "condition";
      }
      if (auto *caseStmt = dyn_cast<CaseStmt>(statement)) {
        for (const auto &item : caseStmt->getCaseLabelItems()) {
          if (item.getGuardExpr() == expression)
            return "condition";
        }
      }
    }
    if (auto *declaration = Parent.getAsDecl()) {
      if (auto *binding = dyn_cast<PatternBindingDecl>(declaration)) {
        for (unsigned i = 0; i < binding->getNumPatternEntries(); ++i) {
          if (binding->getInit(i) == expression ||
              binding->getOriginalInit(i) == expression) {
            bool bindsVariable = false;
            binding->getPattern(i)->forEachVariable(
                [&](VarDecl *) { bindsVariable = true; });
            return bindsVariable ? "initializer" : "discardedInitializer";
          }
        }
      }
    }
    if (auto *parent = Parent.getAsExpr()) {
      if (auto *ternary = dyn_cast<TernaryExpr>(parent)) {
        if (ternary->getCondExpr() == expression)
          return "condition";
      }
      if (auto *assignment = dyn_cast<AssignExpr>(parent)) {
        if (assignment->getSrc() == expression)
          return "assignmentValue";
        if (assignment->getDest() == expression)
          return "assignmentDestination";
      }
      if (auto *apply = dyn_cast<ApplyExpr>(parent))
        return apply->getFn() == expression ? "callee" : "argument";
    }
    return "child";
  }

  void addRange(BridgedSourceNode &result, SourceRange range) {
    if (range.isInvalid())
      return;
    auto &manager = sourceFile.getASTContext().SourceMgr;
    unsigned buffer = sourceFile.getBufferID();
    if (manager.findBufferContainingLoc(range.Start) != buffer ||
        manager.findBufferContainingLoc(range.End) != buffer)
      return;
    unsigned lastToken = manager.getLocOffsetInBuffer(range.End, buffer);
    auto end = llvm::upper_bound(tokens, lastToken,
                                [](unsigned offset, const TokenEnd &token) {
                                  return offset < token.start;
                                });
    if (end == tokens.begin())
      return;
    --end;
    if (lastToken >= end->end)
      return;
    auto start = manager.getLineAndColumnInBuffer(range.Start, buffer);
    result.file = sourceFile.getFilename();
    result.startLine = start.first;
    result.startColumn = start.second;
    result.startOffset = manager.getLocOffsetInBuffer(range.Start, buffer);
    result.endLine = end->line;
    result.endColumn = end->column;
    result.endOffset = end->end;
  }

  void addDeclaration(BridgedSourceNode &result, ValueDecl *declaration) {
    if (!declaration)
      return;
    result.referencedDeclaration = identity(ASTNode{declaration});
    result.declarationName = declaration->getBaseName().userFacingName();
    result.declarationModule = declaration->getModuleContext()->getName().str();
    result.localDeclaration = declaration->getDeclContext()->isLocalContext();
    if (auto *variable = dyn_cast<VarDecl>(declaration))
      result.constantDeclaration = variable->isLet();
  }

  void addType(BridgedSourceNode &result, Type type) {
    if (!type)
      return;
    result.optionalType = bool(type->getOptionalObjectType());
    result.voidType = type->isVoid();
    if (auto *nominal = type->getAnyNominal()) {
      result.typeName = nominal->getName().str();
      result.typeModule = nominal->getModuleContext()->getName().str();
    }
  }

  BridgedSourceNode makeNode(ASTNode node, StringRef category, StringRef kind) {
    BridgedSourceNode result{};
    result.identity = identity(node);
    result.parent = identity(parentNode(Parent));
    result.category = category;
    result.kind = kind;
    result.role = StringRef("child");
    result.implicit = node.isImplicit();
    addRange(result, node.getSourceRange());
    return result;
  }

public:
  SourceNodeWalker(SourceFile &file, void *syntax, void *outputContext,
                   void (*visit)(void *, BridgedSourceNode))
      : sourceFile(file), outputContext(outputContext), visit(visit) {
    swift_ASTGen_visitTokenRanges(
        syntax, &tokens,
        [](void *context, intptr_t start, intptr_t end, intptr_t line,
           intptr_t column) {
          auto &tokens = *static_cast<SmallVector<TokenEnd, 128> *>(context);
          tokens.push_back({unsigned(start), unsigned(end), unsigned(line),
                            unsigned(column)});
        });
  }

  PreWalkResult<Expr *> walkToExprPre(Expr *expression) override {
    auto result = makeNode(expression, "expression",
                           Expr::getKindName(expression->getKind()));
    result.role = role(expression);
    result.semanticExpression =
        identity(ASTNode{expression->getSemanticsProvidingExpr()});
    addType(result, expression->getType());
    addDeclaration(result, expression->getReferencedDecl().getDecl());
    if (auto *apply = dyn_cast<ApplyExpr>(expression)) {
      result.callee = identity(ASTNode{apply->getFn()});
      addDeclaration(result,
                     apply->getCalledValue(/*skipFunctionConversions=*/true));
    }
    if (auto *assignment = dyn_cast<AssignExpr>(expression))
      result.value = identity(ASTNode{assignment->getSrc()});
    if (auto *conversion = dyn_cast<ImplicitConversionExpr>(expression))
      result.value = identity(ASTNode{conversion->getSubExpr()});
    visit(outputContext, result);
    return Action::Continue(expression);
  }

  PreWalkResult<Stmt *> walkToStmtPre(Stmt *statement) override {
    auto result = makeNode(statement, "statement",
                           Stmt::getKindName(statement->getKind()));
    if (auto *returned = dyn_cast<ReturnStmt>(statement))
      result.value = identity(ASTNode{returned->getResult()});
    visit(outputContext, result);
    return Action::Continue(statement);
  }

  PreWalkAction walkToDeclPre(Decl *declaration) override {
    auto result = makeNode(declaration, "declaration",
                           Decl::getKindName(declaration->getKind()));
    if (auto *accessor = dyn_cast<AccessorDecl>(declaration)) {
      if (accessor->isGetter() && accessor->getStorage()->hasStorage())
        result.role = StringRef("storedPropertyGetter");
    }
    if (auto *value = dyn_cast<ValueDecl>(declaration)) {
      addDeclaration(result, value);
      addType(result, value->getInterfaceType());
    }
    visit(outputContext, result);
    return Action::Continue();
  }

  PreWalkResult<Pattern *> walkToPatternPre(Pattern *pattern) override {
    auto result = makeNode(pattern, "pattern",
                           Pattern::getKindName(pattern->getKind()));
    if (auto *named = dyn_cast<NamedPattern>(pattern))
      addDeclaration(result, named->getDecl());
    visit(outputContext, result);
    return Action::Continue(pattern);
  }
};

} // namespace

bool BridgedContext::visitSourceNodes(
    void *outputContext,
    void (*visit)(void *, BridgedSourceNode)) const {
#if SWIFT_BUILD_SWIFT_SYNTAX
  auto *module = context->getModule()->getSwiftModule();
  bool hasPrimaryFiles = !module->getPrimarySourceFiles().empty();
  for (auto *file : module->getFiles()) {
    auto *sourceFile = dyn_cast<SourceFile>(file);
    if (!sourceFile || (sourceFile->Kind != SourceFileKind::Library &&
                        sourceFile->Kind != SourceFileKind::Main) ||
        (hasPrimaryFiles && !sourceFile->isPrimary()))
      continue;
    if (!sourceFile->getASTContext().evaluator.hasCachedResult(
            ExportedSourceFileRequest{sourceFile}))
      return false;
    auto *syntax = sourceFile->getExportedSourceFile();
    if (!syntax)
      return false;
    SourceNodeWalker walker(*sourceFile, syntax, outputContext, visit);
    sourceFile->walk(walker);
  }
  return true;
#else
  return false;
#endif
}

void BridgedLocation::visitASTProvenance(
    void *outputContext, void (*visit)(void *, SwiftInt)) const {
  auto emit = [&](SILLocation location) {
    if (auto node = location.getASTNode())
      visit(outputContext, identity(node));
  };
  emit(getLoc().getLocation());
  auto *scope = getLoc().getScope();
  while (scope && scope->InlinedCallSite) {
    scope = scope->InlinedCallSite;
    emit(scope->Loc);
  }
}
