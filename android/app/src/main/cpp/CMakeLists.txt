cmake_minimum_required(VERSION 3.22.1)
project(weiqi_katago LANGUAGES CXX)

include(FetchContent)
FetchContent_Declare(katago
  URL https://codeload.github.com/lightvector/KataGo/tar.gz/refs/tags/v1.16.5
  URL_HASH SHA256=50d2aa0fb4d5e697dcfa47ddc111c17d3d193dce0604a5592f5fc02501cb49e1
  SOURCE_SUBDIR unused
)
FetchContent_Declare(eigen
  URL https://gitlab.com/libeigen/eigen/-/archive/3.4.0/eigen-3.4.0.tar.gz
  URL_HASH SHA256=8586084f71f9bde545ee7fa6d00288b264a2b7ac3607b974e54d13e7162c1c72
  SOURCE_SUBDIR unused
)
FetchContent_MakeAvailable(katago eigen)

set(kg "${katago_SOURCE_DIR}/cpp")
file(GLOB engine_sources CONFIGURE_DEPENDS
  "${kg}/core/*.cpp"
  "${kg}/game/*.cpp"
  "${kg}/search/*.cpp"
)
list(FILTER engine_sources EXCLUDE REGEX "/(commandloop|mainargs|threadtest)\\.cpp$")
add_library(weiqi_katago SHARED
  weiqi_katago.cpp
  ${engine_sources}
  "${kg}/dataio/files.cpp"
  "${kg}/dataio/sgf.cpp"
  "${kg}/neuralnet/desc.cpp"
  "${kg}/neuralnet/eigenbackend.cpp"
  "${kg}/neuralnet/modelversion.cpp"
  "${kg}/neuralnet/nneval.cpp"
  "${kg}/neuralnet/nninputs.cpp"
  "${kg}/neuralnet/sgfmetadata.cpp"
  "${kg}/program/playutils.cpp"
  "${kg}/program/setup.cpp"
)

find_package(Threads REQUIRED)
find_package(ZLIB REQUIRED)
target_link_libraries(weiqi_katago PRIVATE Threads::Threads ZLIB::ZLIB)
target_compile_features(weiqi_katago PRIVATE cxx_std_17)
target_compile_definitions(weiqi_katago PRIVATE USE_EIGEN_BACKEND EIGEN_MPL2_ONLY)
target_compile_options(weiqi_katago PRIVATE -fsigned-char -O3)
target_include_directories(weiqi_katago PRIVATE "${kg}")
target_include_directories(weiqi_katago SYSTEM PRIVATE
  "${eigen_SOURCE_DIR}"
  "${kg}/external/filesystem-1.5.8/include"
)
set_target_properties(weiqi_katago PROPERTIES CXX_VISIBILITY_PRESET hidden VISIBILITY_INLINES_HIDDEN YES)

if(ANDROID)
  set_source_files_properties(
    "${kg}/core/sha2.cpp" "${kg}/neuralnet/desc.cpp"
    PROPERTIES COMPILE_OPTIONS "-include;endian.h"
  )
  target_link_options(weiqi_katago PRIVATE "-Wl,-z,max-page-size=16384")
endif()
