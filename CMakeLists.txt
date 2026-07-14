cmake_minimum_required(VERSION 3.21)
project(NekoBenchmark LANGUAGES CXX)

include(FetchContent)
# SDL's X11 screensaver integration is unrelated to this application and may
# require an optional Linux development package.
set(SDL_X11_XSCRNSAVER OFF CACHE BOOL "" FORCE)
# A static SDL build keeps the Windows self-check and release executable from
# requiring a separately deployed SDL3.dll.
set(SDL_SHARED OFF CACHE BOOL "" FORCE)
set(SDL_STATIC ON CACHE BOOL "" FORCE)
FetchContent_Declare(
    SDL
    URL https://github.com/libsdl-org/SDL/archive/refs/tags/release-3.4.8.tar.gz
    DOWNLOAD_EXTRACT_TIMESTAMP TRUE
)
FetchContent_MakeAvailable(SDL)

set(NOTO_SANS_CJK_FONT "${CMAKE_BINARY_DIR}/NotoSansCJKsc-Regular.otf")
set(NOTO_SANS_CJK_LICENSE "${CMAKE_BINARY_DIR}/NotoSansCJK-OFL.txt")
if(EXISTS "${NOTO_SANS_CJK_FONT}")
    file(SIZE "${NOTO_SANS_CJK_FONT}" NOTO_SANS_CJK_FONT_SIZE)
else()
    set(NOTO_SANS_CJK_FONT_SIZE 0)
endif()
if(NOTO_SANS_CJK_FONT_SIZE EQUAL 0)
    file(DOWNLOAD
        "https://github.com/notofonts/noto-cjk/raw/main/Sans/OTF/SimplifiedChinese/NotoSansCJKsc-Regular.otf"
        "${NOTO_SANS_CJK_FONT}"
        STATUS NOTO_SANS_CJK_DOWNLOAD_STATUS
        EXPECTED_HASH SHA256=2c76254f6fc379fddfce0a7e84fb5385bb135d3e399294f6eeb6680d0365b74b
        TLS_VERIFY ON
    )
    list(GET NOTO_SANS_CJK_DOWNLOAD_STATUS 0 NOTO_SANS_CJK_DOWNLOAD_CODE)
    if(NOT "${NOTO_SANS_CJK_DOWNLOAD_CODE}" STREQUAL "0")
        list(GET NOTO_SANS_CJK_DOWNLOAD_STATUS 1 NOTO_SANS_CJK_DOWNLOAD_ERROR)
        message(FATAL_ERROR "Could not download Noto Sans CJK: ${NOTO_SANS_CJK_DOWNLOAD_ERROR}")
    endif()
endif()
if(EXISTS "${NOTO_SANS_CJK_LICENSE}")
    file(SIZE "${NOTO_SANS_CJK_LICENSE}" NOTO_SANS_CJK_LICENSE_SIZE)
else()
    set(NOTO_SANS_CJK_LICENSE_SIZE 0)
endif()
if(NOTO_SANS_CJK_LICENSE_SIZE EQUAL 0)
    file(DOWNLOAD
        "https://raw.githubusercontent.com/notofonts/noto-cjk/main/Sans/LICENSE"
        "${NOTO_SANS_CJK_LICENSE}"
        STATUS NOTO_SANS_CJK_LICENSE_STATUS
        EXPECTED_HASH SHA256=6a73f9541c2de74158c0e7cf6b0a58ef774f5a780bf191f2d7ec9cc53efe2bf2
        TLS_VERIFY ON
    )
    list(GET NOTO_SANS_CJK_LICENSE_STATUS 0 NOTO_SANS_CJK_LICENSE_CODE)
    if(NOT "${NOTO_SANS_CJK_LICENSE_CODE}" STREQUAL "0")
        list(GET NOTO_SANS_CJK_LICENSE_STATUS 1 NOTO_SANS_CJK_LICENSE_ERROR)
        message(FATAL_ERROR "Could not download Noto Sans CJK license: ${NOTO_SANS_CJK_LICENSE_ERROR}")
    endif()
endif()

set(SDLTTF_VENDORED ON CACHE BOOL "" FORCE)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(SDLTTF_HARFBUZZ OFF CACHE BOOL "" FORCE)
set(SDLTTF_PLUTOSVG OFF CACHE BOOL "" FORCE)
FetchContent_Declare(
    SDL_ttf
    URL https://github.com/libsdl-org/SDL_ttf/archive/refs/tags/release-3.2.2.tar.gz
    DOWNLOAD_EXTRACT_TIMESTAMP TRUE
)
FetchContent_Declare(
    freetype
    URL https://github.com/freetype/freetype/archive/refs/tags/VER-2-13-3.tar.gz
    DOWNLOAD_EXTRACT_TIMESTAMP TRUE
)
# The SDL_ttf source archive does not include its FreeType git submodule.
# Populate it explicitly so the static SDL_ttf build remains self-contained.
FetchContent_Populate(freetype)
FetchContent_Populate(SDL_ttf)
file(COPY "${freetype_SOURCE_DIR}/" DESTINATION "${sdl_ttf_SOURCE_DIR}/external/freetype")
add_subdirectory("${sdl_ttf_SOURCE_DIR}" "${sdl_ttf_BINARY_DIR}")

if(WIN32)
    # This is a graphical SDL application; the WIN32 subsystem prevents a console
    # window from appearing when it is launched from Explorer.
    add_executable(nekobenchmark WIN32 src/main.cpp)
elseif(APPLE)
    # A bundle launches as a native macOS app instead of through Terminal.
    add_executable(nekobenchmark MACOSX_BUNDLE src/main.cpp)
    set_source_files_properties(
        "${CMAKE_CURRENT_SOURCE_DIR}/assets/MapleMono-Regular.ttf"
        "${NOTO_SANS_CJK_FONT}"
        "${NOTO_SANS_CJK_LICENSE}"
        PROPERTIES MACOSX_PACKAGE_LOCATION Resources
    )
    target_sources(nekobenchmark PRIVATE
        "${CMAKE_CURRENT_SOURCE_DIR}/assets/MapleMono-Regular.ttf"
        "${NOTO_SANS_CJK_FONT}"
        "${NOTO_SANS_CJK_LICENSE}"
    )
else()
    add_executable(nekobenchmark src/main.cpp)
endif()
target_compile_features(nekobenchmark PRIVATE cxx_std_20)
target_link_libraries(nekobenchmark PRIVATE SDL3::SDL3-static SDL3_ttf::SDL3_ttf-static)

if(NOT APPLE)
    add_custom_command(TARGET nekobenchmark POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${CMAKE_CURRENT_SOURCE_DIR}/assets/MapleMono-Regular.ttf"
            "$<TARGET_FILE_DIR:nekobenchmark>/MapleMono-Regular.ttf"
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${NOTO_SANS_CJK_FONT}"
            "$<TARGET_FILE_DIR:nekobenchmark>/NotoSansCJKsc-Regular.otf"
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${NOTO_SANS_CJK_LICENSE}"
            "$<TARGET_FILE_DIR:nekobenchmark>/NotoSansCJK-OFL.txt"
    )
endif()

if(MSVC)
    target_compile_options(nekobenchmark PRIVATE /W4 /permissive-)
else()
    target_compile_options(nekobenchmark PRIVATE -Wall -Wextra -Wpedantic)
endif()

enable_testing()
add_test(NAME self_check COMMAND $<TARGET_FILE:nekobenchmark> --self-test)
