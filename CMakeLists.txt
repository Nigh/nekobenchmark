cmake_minimum_required(VERSION 3.21)
project(NekoBenchmark LANGUAGES CXX)

include(FetchContent)
# SDL's X11 screensaver integration is unrelated to this application and may
# require an optional Linux development package.
set(SDL_X11_XSCRNSAVER OFF CACHE BOOL "" FORCE)
FetchContent_Declare(
    SDL
    URL https://github.com/libsdl-org/SDL/archive/refs/tags/release-3.4.8.tar.gz
    DOWNLOAD_EXTRACT_TIMESTAMP TRUE
)
FetchContent_MakeAvailable(SDL)

add_executable(nekobenchmark src/main.cpp)
target_compile_features(nekobenchmark PRIVATE cxx_std_20)
target_link_libraries(nekobenchmark PRIVATE SDL3::SDL3)

if(MSVC)
    target_compile_options(nekobenchmark PRIVATE /W4 /permissive-)
else()
    target_compile_options(nekobenchmark PRIVATE -Wall -Wextra -Wpedantic)
endif()

enable_testing()
add_test(NAME self_check COMMAND nekobenchmark --self-test)
