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

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
import Darwin
#elseif os(Linux) || os(Android)
import Glibc
#endif

public func swiftmutEnvironmentValue(_ name: String) -> String? {
  #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(Linux) || os(Android)
  return name.withCString { namePointer in
    guard let valuePointer = getenv(namePointer) else {
      return nil
    }
    return String(cString: valuePointer)
  }
  #else
  return nil
  #endif
}

public func swiftmutJSONStringValue(_ key: String, in json: String) -> String? {
  let bytes = Array(json.utf8)
  let keyBytes = Array(("\"" + key + "\"").utf8)
  guard let keyIndex = swiftmutFind(keyBytes, in: bytes, startingAt: 0) else {
    return nil
  }

  var index = keyIndex + keyBytes.count
  swiftmutSkipJSONWhitespace(in: bytes, index: &index)
  guard index < bytes.count, bytes[index] == 58 else {
    return nil
  }
  index += 1
  swiftmutSkipJSONWhitespace(in: bytes, index: &index)
  return swiftmutParseJSONString(in: bytes, index: &index)
}

public func swiftmutJSONStringArray(_ key: String, in json: String) -> [String] {
  let bytes = Array(json.utf8)
  let keyBytes = Array(("\"" + key + "\"").utf8)
  guard let keyIndex = swiftmutFind(keyBytes, in: bytes, startingAt: 0) else {
    return []
  }

  var index = keyIndex + keyBytes.count
  swiftmutSkipJSONWhitespace(in: bytes, index: &index)
  guard index < bytes.count, bytes[index] == 58 else {
    return []
  }
  index += 1
  swiftmutSkipJSONWhitespace(in: bytes, index: &index)
  guard index < bytes.count, bytes[index] == 91 else {
    return []
  }
  index += 1

  var values: [String] = []
  values.reserveCapacity(swiftmutJSONStringArrayInitialCapacity(remainingByteCount: bytes.count - index))
  while index < bytes.count {
    swiftmutSkipJSONWhitespace(in: bytes, index: &index)
    guard index < bytes.count else {
      break
    }
    if bytes[index] == 93 {
      break
    }
    if let value = swiftmutParseJSONString(in: bytes, index: &index) {
      values.append(value)
    } else {
      index += 1
    }
  }
  return values
}

public struct SwiftmutJSONTopLevelObject {
  private var stringValues: [String: String] = [:]
  private var stringArrays: [String: [String]] = [:]

  public init(_ json: String) {
    stringValues.reserveCapacity(8)
    stringArrays.reserveCapacity(10)

    let bytes = Array(json.utf8)
    var index = 0
    swiftmutSkipJSONWhitespace(in: bytes, index: &index)
    guard index < bytes.count, bytes[index] == 123 else {
      return
    }
    index += 1

    while index < bytes.count {
      swiftmutSkipJSONWhitespace(in: bytes, index: &index)
      if index >= bytes.count || bytes[index] == 125 {
        return
      }
      guard let key = swiftmutParseJSONString(in: bytes, index: &index) else {
        index += 1
        continue
      }
      swiftmutSkipJSONWhitespace(in: bytes, index: &index)
      guard index < bytes.count, bytes[index] == 58 else {
        continue
      }
      index += 1
      swiftmutSkipJSONWhitespace(in: bytes, index: &index)
      guard index < bytes.count else {
        return
      }

      if bytes[index] == 34 {
        if let value = swiftmutParseJSONString(in: bytes, index: &index),
           stringValues[key] == nil {
          stringValues[key] = value
        }
      } else if bytes[index] == 91 {
        if stringArrays[key] == nil {
          stringArrays[key] = swiftmutParseJSONStringArray(in: bytes, index: &index)
        } else {
          swiftmutSkipJSONValue(in: bytes, index: &index)
        }
      } else {
        swiftmutSkipJSONValue(in: bytes, index: &index)
      }

      swiftmutSkipJSONWhitespace(in: bytes, index: &index)
      if index < bytes.count, bytes[index] == 44 {
        index += 1
      }
    }
  }

  public func stringValue(_ key: String) -> String? {
    stringValues[key]
  }

  public func stringArray(_ key: String) -> [String] {
    stringArrays[key] ?? []
  }
}

public func swiftmutParseJSONStringArray(in bytes: [UInt8], index: inout Int) -> [String] {
  guard index < bytes.count, bytes[index] == 91 else {
    return []
  }
  index += 1

  var values: [String] = []
  values.reserveCapacity(swiftmutJSONStringArrayInitialCapacity(remainingByteCount: bytes.count - index))
  while index < bytes.count {
    swiftmutSkipJSONWhitespace(in: bytes, index: &index)
    guard index < bytes.count else {
      break
    }
    if bytes[index] == 93 {
      index += 1
      break
    }
    if let value = swiftmutParseJSONString(in: bytes, index: &index) {
      values.append(value)
    } else {
      swiftmutSkipJSONValue(in: bytes, index: &index)
    }
    swiftmutSkipJSONWhitespace(in: bytes, index: &index)
    if index < bytes.count, bytes[index] == 44 {
      index += 1
    }
  }
  return values
}

public func swiftmutJSONStringArrayInitialCapacity(remainingByteCount: Int) -> Int {
  guard remainingByteCount > 0 else {
    return 0
  }
  return max(1, min(2_048, remainingByteCount / 48))
}

public func swiftmutParseJSONString(in bytes: [UInt8], index: inout Int) -> String? {
  guard index < bytes.count, bytes[index] == 34 else {
    return nil
  }
  index += 1

  let valueStart = index
  while index < bytes.count {
    let byte = bytes[index]
    if byte == 34 {
      let value = String(decoding: bytes[valueStart..<index], as: UTF8.self)
      index += 1
      return value
    }
    if byte == 92 {
      break
    }
    index += 1
  }

  var value = Array(bytes[valueStart..<index])
  var escaped = false
  while index < bytes.count {
    let byte = bytes[index]
    index += 1
    if escaped {
      switch byte {
      case 110:
        value.append(10)
      case 114:
        value.append(13)
      case 116:
        value.append(9)
      default:
        value.append(byte)
      }
      escaped = false
      continue
    }
    if byte == 92 {
      escaped = true
      continue
    }
    if byte == 34 {
      return String(decoding: value, as: UTF8.self)
    }
    value.append(byte)
  }
  return nil
}

public func swiftmutSkipJSONWhitespace(in bytes: [UInt8], index: inout Int) {
  while index < bytes.count {
    switch bytes[index] {
    case 32, 10, 13, 9:
      index += 1
    default:
      return
    }
  }
}

public func swiftmutSkipJSONValue(in bytes: [UInt8], index: inout Int) {
  guard index < bytes.count else {
    return
  }
  if bytes[index] == 34 {
    _ = swiftmutParseJSONString(in: bytes, index: &index)
    return
  }
  if bytes[index] == 91 {
    index += 1
    var depth = 1
    while index < bytes.count && depth > 0 {
      if bytes[index] == 34 {
        _ = swiftmutParseJSONString(in: bytes, index: &index)
        continue
      }
      if bytes[index] == 91 {
        depth += 1
      } else if bytes[index] == 93 {
        depth -= 1
      }
      index += 1
    }
    return
  }
  if bytes[index] == 123 {
    index += 1
    var depth = 1
    while index < bytes.count && depth > 0 {
      if bytes[index] == 34 {
        _ = swiftmutParseJSONString(in: bytes, index: &index)
        continue
      }
      if bytes[index] == 123 {
        depth += 1
      } else if bytes[index] == 125 {
        depth -= 1
      }
      index += 1
    }
    return
  }
  while index < bytes.count {
    switch bytes[index] {
    case 44, 93, 125:
      return
    default:
      index += 1
    }
  }
}

public func swiftmutFind(_ needle: [UInt8], in haystack: [UInt8], startingAt start: Int) -> Int? {
  guard !needle.isEmpty, haystack.count >= needle.count, start <= haystack.count - needle.count else {
    return nil
  }
  let firstNeedleByte = needle[0]
  let lastStart = haystack.count - needle.count
  var index = start
  while index <= lastStart {
    while index <= lastStart && haystack[index] != firstNeedleByte {
      index += 1
    }
    guard index <= lastStart else {
      break
    }
    var matched = true
    for needleIndex in 1..<needle.count {
      if haystack[index + needleIndex] != needle[needleIndex] {
        matched = false
        break
      }
    }
    if matched {
      return index
    }
    index += 1
  }
  return nil
}

public func swiftmutFind(
  _ needle: [UInt8],
  in haystack: UnsafeBufferPointer<UInt8>,
  startingAt start: Int
) -> Int? {
  guard !needle.isEmpty, haystack.count >= needle.count, start <= haystack.count - needle.count else {
    return nil
  }
  let firstNeedleByte = needle[0]
  let lastStart = haystack.count - needle.count
  var index = start
  while index <= lastStart {
    while index <= lastStart && haystack[index] != firstNeedleByte {
      index += 1
    }
    guard index <= lastStart else {
      break
    }
    var matched = true
    for needleIndex in 1..<needle.count {
      if haystack[index + needleIndex] != needle[needleIndex] {
        matched = false
        break
      }
    }
    if matched {
      return index
    }
    index += 1
  }
  return nil
}

public func swiftmutFormatMutantID(_ ordinal: Int) -> String {
  if ordinal < 10 {
    return "M00\(ordinal)"
  }
  if ordinal < 100 {
    return "M0\(ordinal)"
  }
  return "M\(ordinal)"
}

public func swiftmutEscapeJSON(_ value: String) -> String {
  var escaped = ""
  for character in value {
    switch character {
    case "\\":
      escaped += "\\\\"
    case "\"":
      escaped += "\\\""
    case "\n":
      escaped += "\\n"
    case "\r":
      escaped += "\\r"
    case "\t":
      escaped += "\\t"
    default:
      escaped.append(character)
    }
  }
  return escaped
}
