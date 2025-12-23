# phoenix-build.cmake
# Phoenix Build System - CMake Helper Module
# Handles version generation, git info, and build number tracking
#
# Usage in your CMakeLists.txt:
#   include(external/phoenix-build-scripts/cmake/phoenix-build.cmake)

message(STATUS "Phoenix Build System: Configuring version information...")

#============================================================================
# Extract version from project()
#============================================================================

if(NOT PROJECT_VERSION)
    message(FATAL_ERROR "Phoenix Build: PROJECT_VERSION not set. Use project(name VERSION x.y.z)")
endif()

set(PHOENIX_VERSION_MAJOR ${PROJECT_VERSION_MAJOR})
set(PHOENIX_VERSION_MINOR ${PROJECT_VERSION_MINOR})
set(PHOENIX_VERSION_PATCH ${PROJECT_VERSION_PATCH})
set(PHOENIX_VERSION_STRING "${PROJECT_VERSION}")

message(STATUS "Phoenix Build: Version ${PHOENIX_VERSION_STRING}")

#============================================================================
# Read build number from .phoenix-build-number
#============================================================================

set(BUILD_NUMBER_FILE "${CMAKE_SOURCE_DIR}/.phoenix-build-number")

if(EXISTS "${BUILD_NUMBER_FILE}")
    file(READ "${BUILD_NUMBER_FILE}" PHOENIX_VERSION_BUILD)
    string(STRIP "${PHOENIX_VERSION_BUILD}" PHOENIX_VERSION_BUILD)
    
    # Validate it's a number
    if(NOT PHOENIX_VERSION_BUILD MATCHES "^[0-9]+$")
        message(WARNING "Phoenix Build: Invalid .phoenix-build-number (${PHOENIX_VERSION_BUILD}), resetting to 0")
        set(PHOENIX_VERSION_BUILD 0)
    endif()
else()
    message(WARNING "Phoenix Build: .phoenix-build-number not found, creating with value 0")
    set(PHOENIX_VERSION_BUILD 0)
    file(WRITE "${BUILD_NUMBER_FILE}" "0")
endif()

message(STATUS "Phoenix Build: Build number ${PHOENIX_VERSION_BUILD}")

#============================================================================
# Get git commit hash and dirty status
#============================================================================

find_package(Git QUIET)

if(GIT_FOUND)
    # Get short commit hash
    execute_process(
        COMMAND ${GIT_EXECUTABLE} rev-parse --short HEAD
        WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
        OUTPUT_VARIABLE PHOENIX_GIT_COMMIT
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET
        RESULT_VARIABLE GIT_RESULT
    )
    
    if(NOT GIT_RESULT EQUAL 0)
        set(PHOENIX_GIT_COMMIT "unknown")
    endif()
    
    # Check for uncommitted changes
    execute_process(
        COMMAND ${GIT_EXECUTABLE} diff-index --quiet HEAD --
        WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
        RESULT_VARIABLE GIT_DIRTY_RESULT
        ERROR_QUIET
    )
    
    if(GIT_DIRTY_RESULT EQUAL 0)
        set(PHOENIX_GIT_DIRTY false)
        set(PHOENIX_GIT_DIRTY_STR "")
    else()
        set(PHOENIX_GIT_DIRTY true)
        set(PHOENIX_GIT_DIRTY_STR "-dirty")
    endif()
else()
    set(PHOENIX_GIT_COMMIT "unknown")
    set(PHOENIX_GIT_DIRTY false)
    set(PHOENIX_GIT_DIRTY_STR "")
endif()

message(STATUS "Phoenix Build: Git commit ${PHOENIX_GIT_COMMIT}${PHOENIX_GIT_DIRTY_STR}")

#============================================================================
# Build full version string
#============================================================================

set(PHOENIX_VERSION_FULL "${PHOENIX_VERSION_STRING}+${PHOENIX_VERSION_BUILD}.${PHOENIX_GIT_COMMIT}${PHOENIX_GIT_DIRTY_STR}")

message(STATUS "Phoenix Build: Full version ${PHOENIX_VERSION_FULL}")

#============================================================================
# Generate version.h from template
#============================================================================

# Look for version.h.in in standard locations
set(VERSION_H_IN "")
if(EXISTS "${CMAKE_SOURCE_DIR}/cmake/version.h.in")
    set(VERSION_H_IN "${CMAKE_SOURCE_DIR}/cmake/version.h.in")
elseif(EXISTS "${CMAKE_SOURCE_DIR}/templates/version.h.in")
    set(VERSION_H_IN "${CMAKE_SOURCE_DIR}/templates/version.h.in")
elseif(EXISTS "${CMAKE_SOURCE_DIR}/external/phoenix-build-scripts/templates/version.h.in")
    set(VERSION_H_IN "${CMAKE_SOURCE_DIR}/external/phoenix-build-scripts/templates/version.h.in")
else()
    message(FATAL_ERROR "Phoenix Build: version.h.in not found. Copy from phoenix-build-scripts/templates/")
endif()

# Generate to build/include/version.h
set(VERSION_H_OUT "${CMAKE_BINARY_DIR}/include/version.h")

configure_file(
    "${VERSION_H_IN}"
    "${VERSION_H_OUT}"
    @ONLY
)

message(STATUS "Phoenix Build: Generated ${VERSION_H_OUT}")

#============================================================================
# Export variables for use in CMakeLists.txt
#============================================================================

# Add include directory for generated version.h
include_directories(${CMAKE_BINARY_DIR}/include)

message(STATUS "Phoenix Build: Configuration complete")
