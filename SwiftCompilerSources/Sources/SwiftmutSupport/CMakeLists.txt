# This source file is part of the Swift.org open source project
#
# Copyright (c) 2026 swiftmut contributors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See https://swift.org/LICENSE.txt for license information

add_swift_compiler_module(SwiftmutSupport
  SOURCES
  SwiftmutConfig.swift
  SwiftmutFilesystem.swift
  SwiftmutJSON.swift
  SwiftmutSourceLookup.swift)
