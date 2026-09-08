// RUN: rm -rf %t && split-file %s %t
// RUN: %target-swiftc_driver -parse-as-library -emit-module -module-name Library %t/Library.swift -o %t/Library.swiftmodule
// RUN: %{python} %t/config.py %t
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swiftc_driver -c -emit-module -Onone -no-emit-module-separately -no-emit-module-separately-wmo -swift-version 6 -module-name Main -I %t %t/main.swift -o %t/main.o -emit-module-path %t/Main.swiftmodule
// RUN: %{python} %t/check.py %t
// RUN: rm -rf %t/fragments
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swiftc_driver -c -emit-module -O -whole-module-optimization -no-emit-module-separately -no-emit-module-separately-wmo -swift-version 6 -module-name Main -I %t %t/main.swift -o %t/main.o -emit-module-path %t/Main.swiftmodule
// RUN: %{python} %t/check.py %t

//--- Library.swift
@_silgen_name("__swiftmut_visit")
public func visit(_ siteID: UInt64) -> UInt32 { 0 }
public func amount(_ input: Int = 5) -> Int { input }

//--- main.swift
import Library
let result = amount() + 3

//--- config.py
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
(root / "config.json").write_text(json.dumps({
    "mode": "metamutant", "packageRoot": str(root),
    "sourceFiles": [str(root / "main.swift")], "enabledMutators": ["MATH"],
    "arithmeticMutationRules": ["Add|sub|+|-"],
    "manifestPath": str(root / "mutants.jsonl"),
    "manifestFragmentsDirectory": str(root / "fragments"),
    "compilerEventsPath": str(root / "events.jsonl")
}))

//--- check.py
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
fragments = [json.loads(p.read_text()) for p in (root / "fragments").glob("*.json")]
assert fragments
inventories = [f["sourceMutationInventory"] for f in fragments if "sourceMutationInventory" in f]
assert {name for i in inventories for name in i["files"]} == {"main.swift"}
candidates = [c for i in inventories for c in i["candidates"] if c["site"]["siteKind"] == "arithmetic"]
assert candidates
assert all(c["site"].get("span") and c["behavior"]["operation"] == "subtract" for c in candidates)
statements = [s for f in fragments for s in f.get("statementInventory", {}).get("statements", [])]
assert any(s["span"]["start"]["line"] == 2 and s["kind"] == "declaration" for s in statements)
assert (root / "main.o").is_file()
assert (root / "Main.swiftmodule").is_file()
