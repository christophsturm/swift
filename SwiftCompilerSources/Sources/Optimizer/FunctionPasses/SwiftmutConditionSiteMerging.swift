//===--- SwiftmutConditionSiteMerging.swift -------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2026 swiftmut contributors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

func swiftmutMergingGenericDuplicateConditionSites(
  _ sites: [SwiftmutConditionSite]
) -> [SwiftmutConditionSite] {
  var merged: [SwiftmutConditionSite] = []
  for site in sites {
    if let index = merged.firstIndex(where: { existing in
      swiftmutConditionSitesShareSourceExpression(existing, site)
        && ((existing.comparison == nil) != (site.comparison == nil))
    }) {
      if merged[index].comparison == nil, site.comparison != nil {
        merged[index] = site
      }
      continue
    }
    merged.append(site)
  }
  return merged
}

func swiftmutConditionSitesShareSourceExpression(
  _ lhs: SwiftmutConditionSite,
  _ rhs: SwiftmutConditionSite
) -> Bool {
  guard let lhsOriginal = lhs.alternatives.first?.mutation.sourceOriginal,
        let rhsOriginal = rhs.alternatives.first?.mutation.sourceOriginal else {
    return false
  }
  return lhs.file == rhs.file
    && lhs.line == rhs.line
    && lhsOriginal == rhsOriginal
}
