// RUN: rm -rf %t
// RUN: split-file %s %t
// RUN: %{python} %t/check.py configure %t
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-build-swift -O -whole-module-optimization -emit-sil %t/Subject.swift %t/Empty.swift %t/EmptySource.swift -module-name SwiftmutStatementInventory -o %t/output.sil
// RUN: %{python} %t/check.py verify %t
// RUN: rm -rf %t/fragments
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-build-swift -parse-as-library -O -whole-module-optimization -emit-sil %t/OnlyEmpty.swift -module-name SwiftmutStatementInventory -o %t/empty.sil
// RUN: %{python} %t/check.py verify-empty %t
// RUN: rm -rf %t/fragments
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -parse-as-library -O -emit-sil -primary-file %t/Subject.swift %t/Empty.swift -module-name SwiftmutStatementInventory -o %t/primary.sil
// RUN: %{python} %t/check.py verify-primary %t

//--- Subject.swift
public struct Limits {
  public let maximum = 10
}
public func observe(_ flag: Bool) -> Int {
  print("observation")
  #if NEVER_ENABLED
  let unavailable = 123
  print(unavailable)
  #endif
  var value = 1; if flag { value = 2 }; return value
}

//--- Empty.swift
public struct Empty {}

//--- OnlyEmpty.swift
public enum OnlyEmpty {}

//--- EmptySource.swift
// A file without declarations or statements still belongs to the inventory.

//--- check.py
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[2])
if sys.argv[1] == "configure":
    config = {
        "mode": "metamutant",
        "manifestFragmentsDirectory": str(root / "fragments"),
        "packageRoot": str(root),
        "sourceFiles": [str(root / "Subject.swift"), str(root / "Empty.swift"), str(root / "EmptySource.swift")],
    }
    (root / "config.json").write_text(json.dumps(config))
else:
    fragments = list((root / "fragments").glob("*-statements.json"))
    assert len(fragments) == 1, fragments
    inventory = json.loads(fragments[0].read_text())["statementInventory"]
    if sys.argv[1] == "verify-empty":
        assert [pathlib.Path(f).name for f in inventory["files"]] == ["OnlyEmpty.swift"]
        assert inventory["statements"] == []
        sys.exit(0)
    expected_files = ["Subject.swift"] if sys.argv[1] == "verify-primary" else ["Empty.swift", "EmptySource.swift", "Subject.swift"]
    assert sorted(pathlib.Path(f).name for f in inventory["files"]) == expected_files
    statements = inventory["statements"]
    assert len(statements) == 8, statements
    assert all(pathlib.Path(s["file"]).name == "Subject.swift" for s in statements)
    assert [(s["span"]["start"]["line"], s["span"]["start"]["column"], s["kind"]) for s in statements] == [
        (2, 24, "expression"),
        (5, 3, "expression"),
        (7, 3, "declaration"),
        (8, 3, "expression"),
        (10, 3, "declaration"),
        (10, 18, "statement"),
        (10, 28, "expression"),
        (10, 41, "statement"),
    ], statements
    assert all(s["span"]["start"]["utf8Offset"] < s["span"]["end"]["utf8Offset"] for s in statements)
    assert all(set(s) == {"file", "span", "kind"} for s in statements)
