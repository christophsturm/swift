// RUN: rm -rf %t
// RUN: split-file %s %t
// RUN: %{python} %t/check.py configure %t
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -parse-as-library -emit-sil -Onone %t/Subject.swift -module-name SwiftmutOperations -o %t/debug.sil
// RUN: %{python} %t/check.py verify %t
// RUN: rm -rf %t/fragments
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -parse-as-library -emit-sil -O %t/Subject.swift -module-name SwiftmutOperations -o %t/release.sil
// RUN: %{python} %t/check.py verify %t

//--- Subject.swift
public func equal(_ lhs: Int, _ rhs: Int) -> Int {
  if lhs == rhs { return 11 }
  return 12
}
public func notEqual(_ lhs: Int, _ rhs: Int) -> Int {
  if lhs != rhs { return 21 }
  return 22
}
public func less(_ lhs: Int, _ rhs: Int) -> Int {
  if lhs < rhs { return 31 }
  return 32
}
public func lessEqual(_ lhs: Int, _ rhs: Int) -> Int {
  if lhs <= rhs { return 41 }
  return 42
}
public func greater(_ lhs: Int, _ rhs: Int) -> Int {
  if lhs > rhs { return 51 }
  return 52
}
public func greaterEqual(_ lhs: Int, _ rhs: Int) -> Int {
  if lhs >= rhs { return 61 }
  return 62
}
public func negated(_ value: Int) -> Int {
  return -value
}

//--- check.py
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[2])
if sys.argv[1] == "configure":
    predicates = [
        ("EQ", "NE", "==", "!="), ("NE", "EQ", "!=", "=="),
        ("SLT", "SGE", "<", ">="), ("SLE", "SGT", "<=", ">"),
        ("SGT", "SLE", ">", "<="), ("SGE", "SLT", ">=", "<"),
    ]
    rules = [f"ICMP_{old}|NEGATE_CONDITIONALS|cmp_{new.lower()}|{before}|{after}"
             for old, new, before, after in predicates]
    rules += ["COMPARISON|CONDITION_FALSE|condition_false|condition|false"]
    rules += [
        "ICMP_SLT|CONDITIONALS_BOUNDARY|cmp_sle|<|<=",
        "ICMP_SLE|CONDITIONALS_BOUNDARY|cmp_slt|<=|<",
        "ICMP_SGT|CONDITIONALS_BOUNDARY|cmp_sge|>|>=",
        "ICMP_SGE|CONDITIONALS_BOUNDARY|cmp_sgt|>=|>",
    ]
    (root / "config.json").write_text(json.dumps({
        "mode": "metamutant",
        "manifestFragmentsDirectory": str(root / "fragments"),
        "packageRoot": str(root),
        "sourceFiles": [str(root / "Subject.swift")],
        "enabledMutators": ["NEGATE_CONDITIONALS", "CONDITIONALS_BOUNDARY", "CONDITION_FALSE", "PRIMITIVE_RETURNS", "INVERT_NEGS"],
        "conditionMutationRules": rules,
        "returnMutationRules": ["integerToZero|PRIMITIVE_RETURNS|return_zero|return|return 0|0"],
        "contextualArithmeticMutationRules": ["SSubOver|unaryNegation|INVERT_NEGS|sadd_with_overflow|-|"],
    }))
else:
    sites = [site for fragment in (root / "fragments").glob("*.json")
             for site in json.loads(fragment.read_text())["sites"]]
    conditions = [site for site in sites if site["siteKind"] == "condition"]
    expected = {2: "notEqual", 6: "equal", 10: "greaterThanOrEqual",
                14: "greaterThan", 18: "lessThanOrEqual", 22: "lessThan"}
    boundaries = {10: "lessThanOrEqual", 14: "lessThan", 18: "greaterThanOrEqual", 22: "greaterThan"}
    assert {site["sourceLocation"]["line"] for site in conditions} == set(expected), conditions
    for site in conditions:
        for alternative in site["alternatives"]:
            line = site["sourceLocation"]["line"]
            if alternative["mutator"] == "CONDITION_FALSE":
                operation = "replaceWithFalse"
            elif alternative["mutator"] == "CONDITIONALS_BOUNDARY":
                operation = boundaries[line]
            else:
                operation = expected[line]
            assert alternative.get("operation") == operation, (site, operation)
    returned = [alternative for site in sites for alternative in site["alternatives"]
                if alternative["mutator"] == "PRIMITIVE_RETURNS"]
    assert returned and all(alternative.get("operation") == "replaceWithZero" for alternative in returned), returned
    negated = [alternative for site in sites for alternative in site["alternatives"]
               if alternative["mutator"] == "INVERT_NEGS"]
    assert negated and all(alternative.get("operation") == "removeNegation" for alternative in negated), negated
