//===--- SwiftmutJSON.swift ------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2026 swiftmut contributors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

import SwiftmutSupport

func swiftmutEnvironmentValue(_ name: String) -> String? {
  SwiftmutSupport.swiftmutEnvironmentValue(name)
}

func swiftmutJSONStringValue(_ key: String, in json: String) -> String? {
  SwiftmutSupport.swiftmutJSONStringValue(key, in: json)
}

func swiftmutJSONStringArray(_ key: String, in json: String) -> [String] {
  SwiftmutSupport.swiftmutJSONStringArray(key, in: json)
}

func swiftmutParseJSONString(in bytes: [UInt8], index: inout Int) -> String? {
  SwiftmutSupport.swiftmutParseJSONString(in: bytes, index: &index)
}

func swiftmutSkipJSONWhitespace(in bytes: [UInt8], index: inout Int) {
  SwiftmutSupport.swiftmutSkipJSONWhitespace(in: bytes, index: &index)
}

func swiftmutFind(_ needle: [UInt8], in haystack: [UInt8], startingAt start: Int) -> Int? {
  SwiftmutSupport.swiftmutFind(needle, in: haystack, startingAt: start)
}

func swiftmutFormatMutantID(_ ordinal: Int) -> String {
  SwiftmutSupport.swiftmutFormatMutantID(ordinal)
}

func swiftmutEscapeJSON(_ value: String) -> String {
  SwiftmutSupport.swiftmutEscapeJSON(value)
}
