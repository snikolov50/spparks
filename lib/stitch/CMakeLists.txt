cmake_minimum_required(VERSION 3.14)
project(ExampleProject NONE)    # no C or C++ needed at this level

# -----------------------------------------------------------------------------
# 1) Pull in your existing make-based build as an ExternalProject
# -----------------------------------------------------------------------------
include(ExternalProject)

ExternalProject_Add(libstitch_build
  # where your sources live
  SOURCE_DIR   ${CMAKE_SOURCE_DIR}/src/stitch/libstitch
  BUILD_IN_SOURCE  1
  # we have no configure step
  CONFIGURE_COMMAND    ""
  # build just the 'stitch.lib' target
  BUILD_COMMAND       ${CMAKE_MAKE_PROGRAM} stitch.lib
  # skip any install step
  INSTALL_COMMAND     ""
)

# -----------------------------------------------------------------------------
# 2) After building, make the two symlinks in the top-level directory
#    (mimics:  
#       cd /stitch;  
#       ln -s /src/stitch/libstitch liblink;  
#       ln -s /src/stitch/libstitch includelink  
#     )
# -----------------------------------------------------------------------------
add_custom_target(setup_links ALL
  COMMENT "Creating liblink & includelink in ${CMAKE_SOURCE_DIR}"
  # remove stale links if they exist
  COMMAND ${CMAKE_COMMAND} -E remove -f ${CMAKE_SOURCE_DIR}/liblink
  COMMAND ${CMAKE_COMMAND} -E remove -f ${CMAKE_SOURCE_DIR}/includelink

  # create fresh symlinks
  COMMAND ${CMAKE_COMMAND} -E create_symlink
          ${CMAKE_SOURCE_DIR}/src/stitch/libstitch
          ${CMAKE_SOURCE_DIR}/liblink

  COMMAND ${CMAKE_COMMAND} -E create_symlink
          ${CMAKE_SOURCE_DIR}/src/stitch/libstitch
          ${CMAKE_SOURCE_DIR}/includelink
)

# make sure we build the library before trying to create the links
add_dependencies(setup_links libstitch_build)
