# This source file is part of the Swift.org open source project
#
# Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

# NOTE: Subdirectories must be added in dependency order.

add_subdirectory(Basic)
add_subdirectory(AST)
add_subdirectory(SIL)
if(NOT DEFINED SWIFTMUT_SOURCE_ROOT OR SWIFTMUT_SOURCE_ROOT STREQUAL "")
  message(FATAL_ERROR
    "SWIFTMUT_SOURCE_ROOT must point to the swiftmut repository")
endif()
include("${SWIFTMUT_SOURCE_ROOT}/Compiler/Swift64CompilerEngine.cmake")
add_subdirectory(Optimizer)
