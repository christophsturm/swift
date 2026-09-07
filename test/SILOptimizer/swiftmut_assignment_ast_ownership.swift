// RUN: rm -rf %t
// RUN: split-file %s %t
// RUN: %{python} %t/check.py configure %t
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -parse-as-library -emit-sil -Onone -swift-version 6 -g %t/Subject.swift -module-name SwiftmutAssignment -o %t/debug.sil
// RUN: %{python} %t/check.py verify %t
// RUN: rm -rf %t/fragments
// RUN: env SWIFTMUT_CONFIG=%t/config.json %target-swift-frontend -parse-as-library -emit-sil -O -swift-version 6 %t/Subject.swift -module-name SwiftmutAssignment -o %t/release.sil
// RUN: %{python} %t/check.py verify %t

//--- Subject.swift
public func update(_ value: inout Int, _ first: Int, _ second: Int) {
  value = first; value = second
}
public func compound(_ value: inout Int, _ suffix: Int) {
  value += suffix
}
public final class Box {
  private var storage = 0
  public var value: Int {
    @inline(never) get { storage }
    @inline(never) set { storage = newValue }
  }
}
public func property(_ box: Box, _ next: Int) {
  box.value = next
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
        "enabledMutators": ["STATEMENT_DELETIONS"],
        "statementMutationRules": ["assignment|STATEMENT_DELETIONS|remove_assignment|assignment|removed assignment|removed"],
    }))
else:
    sites = [site for fragment in (root / "fragments").glob("*.json")
             for site in json.loads(fragment.read_text())["sites"]]
    assert len(sites) == 4, sites
    expected = {(2, 3): 16, (2, 18): 32, (5, 3): 18, (15, 3): 19}
    for site in sites:
        assert site["siteKind"] == "statementDeletion", site
        start, end = site["sourceSpan"]["start"], site["sourceSpan"]["end"]
        assert end["line"] == start["line"], site
        assert expected.pop((start["line"], start["column"])) == end["column"], site
        assert site["alternatives"][0]["operation"] == "removeAssignment", site
    assert not expected, expected
