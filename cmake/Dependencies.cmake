# Third-party dependency bootstrapping for cesium-python.

# Development.Module (not Development): manylinux images ship no libpython and
# an extension module must not link one anyway.
find_package(Python 3.8 REQUIRED COMPONENTS Interpreter Development.Module)

# pybind11 comes from the build environment (pyproject build-system.requires);
# let it tell us where its CMake package is, so a plain `pip install .` works
# with no -Dpybind11_DIR.
if(NOT pybind11_DIR)
    execute_process(
        COMMAND "${Python_EXECUTABLE}" -c "import pybind11; print(pybind11.get_cmake_dir())"
        OUTPUT_VARIABLE _pybind11_cmake_dir
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET)
    if(_pybind11_cmake_dir)
        set(pybind11_DIR "${_pybind11_cmake_dir}")
    endif()
endif()
find_package(pybind11 CONFIG REQUIRED)

# Verify submodules are present
set(CESIUM_NATIVE_DIR "${CMAKE_SOURCE_DIR}/extern/cesium-native")
if(NOT EXISTS "${CESIUM_NATIVE_DIR}/CMakeLists.txt")
    message(FATAL_ERROR "Missing submodule: extern/cesium-native. Run: git submodule update --init --recursive")
endif()

# cesium-native and libzip are built here as static libraries that end up
# inside a shared extension module, so they must be position independent
# (GNU ld otherwise refuses them: "recompile with -fPIC"); vcpkg's own ports
# already are.
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

message(STATUS "Adding cesium-native subdirectory...")
add_subdirectory(extern/cesium-native EXCLUDE_FROM_ALL)

# libzip needs zlib. cesium-native (above) has just had vcpkg install one; point
# FindZLIB at that prefix so libzip does not pick a system zlib (or, on Windows,
# fail to find any). PACKAGE_BUILD_DIR is set by cesium-native's CMakeLists.
get_directory_property(_cesium_pkg_dir DIRECTORY "${CESIUM_NATIVE_DIR}" DEFINITION PACKAGE_BUILD_DIR)
if(_cesium_pkg_dir AND NOT ZLIB_ROOT AND EXISTS "${_cesium_pkg_dir}/include/zlib.h")
    set(ZLIB_ROOT "${_cesium_pkg_dir}")
    set(ZLIB_USE_STATIC_LIBS ON)
    message(STATUS "libzip: using cesium-native's vcpkg zlib at ${ZLIB_ROOT}")
endif()
set(LIBZIP_DIR "${CMAKE_SOURCE_DIR}/extern/libzip")
if(NOT EXISTS "${LIBZIP_DIR}/CMakeLists.txt")
    message(FATAL_ERROR "Missing submodule: extern/libzip. Run: git submodule update --init --recursive")
endif()


# Build all submodules as static libraries (no DLL at runtime).
# Use CACHE+FORCE to override stale values in an existing build directory.
if(DEFINED BUILD_SHARED_LIBS)
    set(_BUILD_SHARED_LIBS_ORIG ${BUILD_SHARED_LIBS})
endif()
cmake_policy(SET CMP0077 NEW)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "Build shared libraries" FORCE)

set(LIBZIP_DO_INSTALL OFF CACHE BOOL "Skip libzip install")
set(ENABLE_BZIP2 OFF CACHE BOOL "Disable bzip2 support")
set(ENABLE_LZMA OFF CACHE BOOL "Disable lzma support")
set(ENABLE_ZSTD OFF CACHE BOOL "Disable zstd support")
add_subdirectory(extern/libzip EXCLUDE_FROM_ALL)


# glm::glm should be an imported target after cesium-native's ezvcpkg runs.
# However, when cmake is invoked without the vcpkg toolchain (e.g., via pip),
# the vcpkg toolchain is set only in the cache after project() has been called,
# so find_package(glm) inside cesium-native never actually creates the target.
# Fetch glm directly as a fallback — it is header-only so there is no conflict.
if(NOT TARGET glm::glm)
    include(FetchContent)
    if(CMAKE_VERSION VERSION_GREATER_EQUAL "3.24")
        cmake_policy(SET CMP0135 NEW)
    endif()
    fetchcontent_declare(
        glm
        URL https://github.com/g-truc/glm/releases/download/1.0.1/glm-1.0.1-light.zip
        URL_HASH SHA256=9a995de4da09723bd33ef194e6b79818950e5a8f2e154792f02e4615277cfb8d
        DOWNLOAD_EXTRACT_TIMESTAMP TRUE
    )
    fetchcontent_makeavailable(glm)
endif()

if(DEFINED _BUILD_SHARED_LIBS_ORIG)
    set(BUILD_SHARED_LIBS ${_BUILD_SHARED_LIBS_ORIG} CACHE BOOL "Build shared libraries" FORCE)
else()
    unset(BUILD_SHARED_LIBS CACHE)
endif()

set(CESIUM_PYTHON_INCLUDE_DIRS
    ${CMAKE_SOURCE_DIR}/extern/cesium-native/extern/rapidjson/include
    ${CMAKE_SOURCE_DIR}/extern/cesium-native/Cesium3DTilesWriter/include
    ${CMAKE_SOURCE_DIR}/extern/cesium-native/Cesium3DTilesSelection/include
    ${CMAKE_SOURCE_DIR}/extern/cesium-native/CesiumClientCommon/include
    ${CMAKE_SOURCE_DIR}/extern/cesium-native/CesiumIonClient/include
    ${CMAKE_SOURCE_DIR}/extern/cesium-native/CesiumITwinClient/include
    ${CMAKE_SOURCE_DIR}/extern/cesium-native/CesiumQuantizedMeshTerrain/include
    ${CMAKE_SOURCE_DIR}/extern/cesium-native/CesiumGltf/include
    ${CMAKE_SOURCE_DIR}/extern/cesium-native/CesiumGltfWriter/include
    ${CMAKE_SOURCE_DIR}/extern/cesium-native/CesiumAsync/include
    ${CMAKE_SOURCE_DIR}/extern/cesium-native/CesiumCurl/include
    ${CMAKE_SOURCE_DIR}/extern/cesium-native/CesiumGeometry/include
    ${CMAKE_SOURCE_DIR}/extern/cesium-native/CesiumGeospatial/include
    ${CMAKE_SOURCE_DIR}/extern/cesium-native/CesiumJsonWriter/include
    ${CMAKE_SOURCE_DIR}/extern/cesium-native/CesiumUtility/include
    ${CMAKE_SOURCE_DIR}/extern/cesium-native/CesiumVectorData/include
)

set(CESIUM_PYTHON_LINK_LIBS
    zip
    Cesium3DTilesWriter
    Cesium3DTilesSelection
    CesiumClientCommon
    CesiumIonClient
    CesiumITwinClient
    CesiumQuantizedMeshTerrain
    CesiumGltf
    CesiumGltfWriter
    CesiumAsync
    CesiumCurl
    CesiumGeometry
    CesiumGeospatial
    CesiumJsonWriter
    CesiumUtility
    CesiumVectorData
    glm::glm
)
