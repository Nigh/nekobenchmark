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

add_executable(nekobenchmark src/main.cpp)
target_compile_features(nekobenchmark PRIVATE cxx_std_20)
target_link_libraries(nekobenchmark PRIVATE SDL3::SDL3-static SDL3_ttf::SDL3_ttf-static)

add_custom_command(TARGET nekobenchmark POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
        "${CMAKE_CURRENT_SOURCE_DIR}/assets/MapleMono-Regular.ttf"
        "$<TARGET_FILE_DIR:nekobenchmark>/MapleMono-Regular.ttf"
)

if(MSVC)
    target_compile_options(nekobenchmark PRIVATE /W4 /permissive-)
else()
    target_compile_options(nekobenchmark PRIVATE -Wall -Wextra -Wpedantic)
endif()

enable_testing()
add_test(NAME self_check COMMAND nekobenchmark --self-test)
