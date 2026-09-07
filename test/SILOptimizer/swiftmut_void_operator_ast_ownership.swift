// RUN: rm -rf %t
// RUN: split-file %s %t
// RUN: %{python} %t/check.py configure %t
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -parse-as-library -emit-sil -Onone %t/Subject.swift -module-name SwiftmutVoidOperator -o %t/debug.sil
// RUN: %{python} %t/check.py verify %t

// RUN: rm -rf %t/fragments
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -parse-as-library -emit-sil -Onone -swift-version 6 -g %t/Subject.swift -module-name SwiftmutVoidOperator -o %t/swift6.sil
// RUN: %{python} %t/check.py verify %t
// RUN: rm -rf %t/fragments
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -parse-as-library -emit-sil -O %t/Subject.swift -module-name SwiftmutVoidOperator -o %t/release.sil
// RUN: %{python} %t/check.py verify %t

//--- Subject.swift
public func joined(_ prefix: String, _ suffix: String) -> String {
  var value = prefix
  value += suffix
  return value
}

//--- check.py
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[2])
if sys.argv[1] == "configure":
    (root / "config.json").write_text(json.dumps({
        "mode": "metamutant",
        "manifestFragmentsDirectory": str(root / "fragments"),
        "packageRoot": str(root),
        "sourceFiles": [str(root / "Subject.swift")],
        "enabledMutators": ["VOID_METHOD_CALLS"],
        "voidCallMutationRules": ["VOID_METHOD_CALLS|remove_void_call|call|removed call|noop"],
    }))
else:
    sites = [site for fragment in (root / "fragments").glob("*.json")
             for site in json.loads(fragment.read_text())["sites"]]
    assert len(sites) == 1, sites
    site = sites[0]
    assert site["siteKind"] == "voidCall", site
    assert site["sourceLocation"] == {"file": "Subject.swift", "line": 3, "column": 3}, site
    assert site["sourceSpan"]["start"]["line"] == site["sourceSpan"]["end"]["line"] == 3, site
    assert site["sourceSpan"]["end"]["column"] == 18, site
    assert site["alternatives"][0]["operation"] == "removeCall", site
