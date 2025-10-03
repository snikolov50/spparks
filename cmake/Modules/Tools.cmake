if(BUILD_TOOLS)
  add_executable(binary2txt ${SPPARKS_TOOLS_DIR}/binary2txt.cpp)
  target_compile_definitions(binary2txt PRIVATE -DSPPARKS_${SPPARKS_SIZES})
  install(TARGETS binary2txt DESTINATION ${CMAKE_INSTALL_BINDIR})

  add_executable(stl_bin2txt ${SPPARKS_TOOLS_DIR}/stl_bin2txt.cpp)
  install(TARGETS stl_bin2txt DESTINATION ${CMAKE_INSTALL_BINDIR})

  add_executable(reformat-json ${SPPARKS_TOOLS_DIR}/json/reformat-json.cpp)
  target_include_directories(reformat-json PRIVATE ${SPPARKS_SOURCE_DIR})
  install(TARGETS reformat-json DESTINATION ${CMAKE_INSTALL_BINDIR})

  include(CheckGeneratorSupport)
  if(CMAKE_GENERATOR_SUPPORT_FORTRAN)
    include(CheckLanguage)
    check_language(Fortran)
    if(CMAKE_Fortran_COMPILER)
      enable_language(Fortran)
      add_executable(chain.x ${SPPARKS_TOOLS_DIR}/chain.f90)
      target_link_libraries(chain.x PRIVATE ${CMAKE_Fortran_IMPLICIT_LINK_LIBRARIES})
      add_executable(micelle2d.x ${SPPARKS_TOOLS_DIR}/micelle2d.f90)
      target_link_libraries(micelle2d.x PRIVATE ${CMAKE_Fortran_IMPLICIT_LINK_LIBRARIES})
      install(TARGETS chain.x micelle2d.x DESTINATION ${CMAKE_INSTALL_BINDIR})
    else()
      message(WARNING "No suitable Fortran compiler found, skipping build of 'chain.x' and 'micelle2d.x'")
    endif()
  else()
    message(WARNING "CMake build doesn't support Fortran, skipping build of 'chain.x' and 'micelle2d.x'")
  endif()

  enable_language(C)
  get_filename_component(MSI2LMP_SOURCE_DIR ${SPPARKS_TOOLS_DIR}/msi2spk/src ABSOLUTE)
  file(GLOB MSI2LMP_SOURCES CONFIGURE_DEPENDS ${MSI2LMP_SOURCE_DIR}/[^.]*.c)
  add_executable(msi2spk ${MSI2LMP_SOURCES})
  if(STANDARD_MATH_LIB)
    target_link_libraries(msi2spk PRIVATE ${STANDARD_MATH_LIB})
  endif()
  install(TARGETS msi2spk DESTINATION ${CMAKE_INSTALL_BINDIR})
  install(FILES ${SPPARKS_DOC_DIR}/msi2spk.1 DESTINATION ${CMAKE_INSTALL_MANDIR}/man1)

  add_subdirectory(${SPPARKS_TOOLS_DIR}/phonon ${CMAKE_BINARY_DIR}/phana_build)
endif()

if(BUILD_SPPARKS_GUI)
  include(ExternalProject)
  # When building SPPARKS-GUI with SPPARKS we don't support plugin mode and don't include docs.
  ExternalProject_Add(spparks-gui_build
    GIT_REPOSITORY https://github.com/akohlmey/spparks-gui.git
    GIT_TAG main
    GIT_SHALLOW TRUE
    GIT_PROGRESS TRUE
    CMAKE_ARGS -D BUILD_DOC=OFF
               -D SPPARKS_GUI_USE_PLUGIN=OFF
               -D SPPARKS_SOURCE_DIR=${SPPARKS_SOURCE_DIR}
               -D SPPARKS_LIBRARY=$<TARGET_FILE:spparks>
               -D CMAKE_C_COMPILER=${CMAKE_C_COMPILER}
               -D CMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER}
               -D CMAKE_INSTALL_PREFIX=<INSTALL_DIR>
               -D CMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}
               -D CMAKE_MAKE_PROGRAM=${CMAKE_MAKE_PROGRAM}
               -D CMAKE_TOOLCHAIN_FILE=${CMAKE_TOOLCHAIN_FILE}
    DEPENDS spparks
    BUILD_BYPRODUCTS <INSTALL_DIR>/bin/spparks-gui
  )
  add_custom_target(spparks-gui ALL
          ${CMAKE_COMMAND} -E copy_if_different spparks-gui_build-prefix/bin/spparks-gui* ${CMAKE_BINARY_DIR}
          DEPENDS spparks-gui_build
  )

  # packaging support for SPPARKS-GUI when compiled with SPPARKS
  option(BUILD_WHAM "Download and compile WHAM executable from Grossfield Lab" YES)
  if(BUILD_WHAM)
    set(WHAM_URL "http://membrane.urmc.rochester.edu/sites/default/files/wham/wham-release-2.1.0.tgz" CACHE STRING "URL for WHAM tarball")
    set(WHAM_MD5 "4ed6e24254925ec124f44bb381c3b87f" CACHE STRING "MD5 checksum of WHAM tarball")
    mark_as_advanced(WHAM_URL)
    mark_as_advanced(WHAM_MD5)

    get_filename_component(archive ${WHAM_URL} NAME)
    file(MAKE_DIRECTORY ${CMAKE_BINARY_DIR}/_deps/src)
    if(EXISTS ${CMAKE_BINARY_DIR}/_deps/${archive})
      file(MD5 ${CMAKE_BINARY_DIR}/_deps/${archive} DL_MD5)
    endif()
    if(NOT "${DL_MD5}" STREQUAL "${WHAM_MD5}")
      message(STATUS "Downloading ${WHAM_URL}")
      file(DOWNLOAD ${WHAM_URL} ${CMAKE_BINARY_DIR}/_deps/${archive} STATUS DL_STATUS SHOW_PROGRESS)
      file(MD5 ${CMAKE_BINARY_DIR}/_deps/${archive} DL_MD5)
      if((NOT DL_STATUS EQUAL 0) OR (NOT "${DL_MD5}" STREQUAL "${WHAM_MD5}"))
        message(ERROR "Download of WHAM sources from ${WHAM_URL} failed")
      endif()
    else()
      message(STATUS "Using already downloaded archive ${CMAKE_BINARY_DIR}/_deps/${archive}")
    endif()
    message(STATUS "Unpacking and configuring ${archive}")

    execute_process(COMMAND ${CMAKE_COMMAND} -E tar xf ${CMAKE_BINARY_DIR}/_deps/${archive}
      WORKING_DIRECTORY ${CMAKE_BINARY_DIR}/_deps/src)
    find_package(Patch)
    if(PATCH_FOUND)
      message(STATUS "Apply patch to customize WHAM using ${Patch_EXECUTABLE}")
      execute_process(
        COMMAND ${Patch_EXECUTABLE} -p1 -i ${CMAKE_SOURCE_DIR}/cmake/packaging/update-wham-2.1.0.patch
        WORKING_DIRECTORY ${CMAKE_BINARY_DIR}/_deps/src/wham/
      )
    endif()
    file(REMOVE_RECURSE ${CMAKE_BINARY_DIR}/_deps/wham-src)
    file(RENAME "${CMAKE_BINARY_DIR}/_deps/src/wham" ${CMAKE_BINARY_DIR}/_deps/wham-src)
    file(COPY packaging/CMakeLists.wham DESTINATION ${CMAKE_BINARY_DIR}/_deps/wham-src/)
    file(RENAME "${CMAKE_BINARY_DIR}/_deps/wham-src/CMakeLists.wham"
      "${CMAKE_BINARY_DIR}/_deps/wham-src/CMakeLists.txt")
    add_subdirectory("${CMAKE_BINARY_DIR}/_deps/wham-src" "${CMAKE_BINARY_DIR}/_deps/wham-build")
    set(WHAM_EXE wham wham-2d)
  endif()

  # build SPPARKS-GUI and SPPARKS as flatpak, if tools are installed
  find_program(FLATPAK_COMMAND flatpak DOC "Path to flatpak command")
  find_program(FLATPAK_BUILDER flatpak-builder DOC "Path to flatpak-builder command")
  if(FLATPAK_COMMAND AND FLATPAK_BUILDER)
    file(STRINGS ${SPPARKS_DIR}/src/version.h line REGEX SPPARKS_VERSION)
    string(REGEX REPLACE "#define SPPARKS_VERSION \"([0-9]+) ([A-Za-z][A-Za-z][A-Za-z])[A-Za-z]* ([0-9]+)\""
                        "\\1\\2\\3" SPPARKS_RELEASE "${line}")
    set(FLATPAK_BUNDLE "SPPARKS-Linux-x86_64-GUI-${SPPARKS_RELEASE}.flatpak")
    add_custom_target(flatpak
      COMMAND ${FLATPAK_COMMAND} --user remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
      COMMAND ${FLATPAK_BUILDER} --force-clean --verbose --repo=${CMAKE_CURRENT_BINARY_DIR}/flatpak-repo
                               --install-deps-from=flathub --state-dir=${CMAKE_CURRENT_BINARY_DIR}
                               --user --ccache --default-branch=${SPPARKS_RELEASE}
                               flatpak-build ${SPPARKS_DIR}/cmake/packaging/org.spparks.spparks-gui.yml
      COMMAND ${FLATPAK_COMMAND} build-bundle --runtime-repo=https://flathub.org/repo/flathub.flatpakrepo --verbose
                               ${CMAKE_CURRENT_BINARY_DIR}/flatpak-repo
                               ${FLATPAK_BUNDLE} org.spparks.spparks-gui ${SPPARKS_RELEASE}
      COMMENT "Create Flatpak bundle file of SPPARKS and SPPARKS-GUI"
      BYPRODUCT ${FLATPAK_BUNDLE}
      WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
    )
  else()
    add_custom_target(flatpak
      COMMAND ${CMAKE_COMMAND} -E echo "The flatpak and flatpak-builder commands required to build a SPPARKS-GUI flatpak bundle were not found. Skipping.")
  endif()

  if(APPLE)
    file(STRINGS ${SPPARKS_DIR}/src/version.h line REGEX SPPARKS_VERSION)
    string(REGEX REPLACE "#define SPPARKS_VERSION \"([0-9]+) ([A-Za-z][A-Za-z][A-Za-z])[A-Za-z]* ([0-9]+)\""
                        "\\1\\2\\3" SPPARKS_RELEASE "${line}")

    # additional targets to populate the bundle tree and create the .dmg image file
    set(APP_CONTENTS ${CMAKE_BINARY_DIR}/spparks-gui_build-prefix/bin/spparks-gui.app/Contents)
    if(BUILD_TOOLS)
      file(REMOVE_RECURSE ${CMAKE_BINARY_DIR}/spparks-gui_build-prefix/bin/spparks-gui.app)
      add_custom_target(complete-bundle
        ${CMAKE_COMMAND} -E make_directory ${APP_CONTENTS}/bin
        COMMAND ${CMAKE_COMMAND} -E make_directory ${APP_CONTENTS}/Frameworks
        COMMAND ${CMAKE_COMMAND} -E copy_if_different $<TARGET_FILE:spparks> ${APP_CONTENTS}/Frameworks/
        COMMAND ${CMAKE_COMMAND} -E copy_if_different $<TARGET_FILE:spk> ${APP_CONTENTS}/bin/
        COMMAND ${CMAKE_COMMAND} -E copy_if_different ${CMAKE_BINARY_DIR}/spk ${APP_CONTENTS}/bin/
        COMMAND ${CMAKE_COMMAND} -E copy_if_different ${CMAKE_BINARY_DIR}/msi2spk ${APP_CONTENTS}/bin/
        COMMAND ${CMAKE_COMMAND} -E copy_if_different ${CMAKE_BINARY_DIR}/binary2txt ${APP_CONTENTS}/bin/
        COMMAND ${CMAKE_COMMAND} -E copy_if_different ${CMAKE_BINARY_DIR}/stl_bin2txt ${APP_CONTENTS}/bin/
        COMMAND ${CMAKE_COMMAND} -E copy_if_different ${CMAKE_BINARY_DIR}/phana ${APP_CONTENTS}/bin/
        COMMAND ${CMAKE_COMMAND} -E create_symlink ../MacOS/spparks-gui ${APP_CONTENTS}/bin/spparks-gui
        COMMAND ${CMAKE_COMMAND} -E make_directory ${APP_CONTENTS}/Resources
        COMMAND ${CMAKE_COMMAND} -E copy_if_different ${SPPARKS_DIR}/cmake/packaging/README.macos ${APP_CONTENTS}/Resources/README.txt
        COMMAND ${CMAKE_COMMAND} -E copy_if_different ${SPPARKS_DIR}/cmake/packaging/spparks.icns ${APP_CONTENTS}/Resources
        COMMAND ${CMAKE_COMMAND} -E copy_if_different ${SPPARKS_DIR}/cmake/packaging/spparks-gui.icns ${APP_CONTENTS}/Resources
        COMMAND ${CMAKE_COMMAND} -E copy_if_different ${SPPARKS_DIR}/cmake/packaging/SPPARKS_DMG_Background.png ${APP_CONTENTS}/Resources
        COMMAND ${CMAKE_COMMAND} -E make_directory ${APP_CONTENTS}/share/spparks
        COMMAND ${CMAKE_COMMAND} -E make_directory ${APP_CONTENTS}/share/spparks/man/man1
        COMMAND ${CMAKE_COMMAND} -E copy_directory ${SPPARKS_DIR}/potentials ${APP_CONTENTS}/share/spparks/potentials
        COMMAND ${CMAKE_COMMAND} -E copy_directory ${SPPARKS_DIR}/bench ${APP_CONTENTS}/share/spparks/bench
        COMMAND ${CMAKE_COMMAND} -E copy_directory ${SPPARKS_DIR}/tools/msi2spk/frc_files ${APP_CONTENTS}/share/spparks/frc_files
        COMMAND ${CMAKE_COMMAND} -E copy_if_different ${SPPARKS_DIR}/doc/spparks.1 ${APP_CONTENTS}/share/spparks/man/man1/
        COMMAND ${CMAKE_COMMAND} -E create_symlink spparks.1 ${APP_CONTENTS}/share/spparks/man/man1/spk.1
        COMMAND ${CMAKE_COMMAND} -E copy_if_different ${SPPARKS_DIR}/doc/msi2spk.1 ${APP_CONTENTS}/share/spparks/man/man1
        DEPENDS spparks spk binary2txt stl_bin2txt msi2spk phana spparks-gui_build
        COMMENT "Copying additional files into macOS app bundle tree"
        WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
      )
    else()
      message(FATAL_ERROR "Must use -D BUILD_TOOLS=yes for building app bundle")
    endif()
    if(BUILD_WHAM)
      add_custom_target(copy-wham
        ${CMAKE_COMMAND} -E copy_if_different ${CMAKE_BINARY_DIR}/wham ${APP_CONTENTS}/bin/
        COMMAND ${CMAKE_COMMAND} -E copy_if_different ${CMAKE_BINARY_DIR}/wham-2d ${APP_CONTENTS}/bin/
        DEPENDS complete-bundle wham wham-2d
        COMMENT "Copying WHAM executables into macOS app bundle tree"
      )
      set(WHAM_TARGET copy-wham)
    endif()
    if(FFMPEG_EXECUTABLE)
      add_custom_target(copy-ffmpeg
        COMMAND ${CMAKE_COMMAND} -E copy_if_different ${FFMPEG_EXECUTABLE} ${APP_CONTENTS}/bin/
        COMMENT "Copying FFMpeg into macOS app bundle tree"
        DEPENDS complete-bundle
      )
      set(FFMPEG_TARGET copy-ffmpeg)
    endif()
    add_custom_target(dmg
      COMMAND ${SPPARKS_DIR}/cmake/packaging/build_macos_dmg.sh ${SPPARKS_RELEASE} ${CMAKE_BINARY_DIR}/spparks-gui_build-prefix/bin/spparks-gui.app
      DEPENDS complete-bundle ${WHAM_TARGET} ${FFMPEG_TARGET}
      COMMENT "Create Drag-n-Drop installer disk image from app bundle"
      BYPRODUCT SPPARKS-macOS-multiarch-GUI-${SPPARKS_RELEASE}.dmg
      WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
    )
    # settings or building on Windows with Visual Studio
  elseif(MSVC)
    file(STRINGS ${SPPARKS_DIR}/src/version.h line REGEX SPPARKS_VERSION)
    string(REGEX REPLACE "#define SPPARKS_VERSION \"([0-9]+) ([A-Za-z][A-Za-z][A-Za-z])[A-Za-z]* ([0-9]+)\""
                          "\\1\\2\\3" SPPARKS_RELEASE "${line}")
    #    install(FILES $<TARGET_RUNTIME_DLLS:spparks-gui> TYPE BIN)
    if(BUILD_SHARED_LIBS)
      install(FILES $<TARGET_RUNTIME_DLLS:spparks> TYPE BIN)
    endif()
    install(FILES $<TARGET_RUNTIME_DLLS:spk> TYPE BIN)
    # find path to VC++ init batch file
    get_filename_component(VC_COMPILER_DIR "${CMAKE_CXX_COMPILER}" DIRECTORY)
    get_filename_component(VC_BASE_DIR "${VC_COMPILER_DIR}/../../../../../.." ABSOLUTE)
    set(VC_INIT "${VC_BASE_DIR}/Auxiliary/Build/vcvarsall.bat")
    get_filename_component(QT5_BIN_DIR "${Qt5Core_DIR}/../../../bin" ABSOLUTE)
    get_filename_component(INSTNAME ${CMAKE_INSTALL_PREFIX} NAME)
    install(CODE "execute_process(COMMAND \"${CMAKE_COMMAND}\" -D INSTNAME=${INSTNAME} -D VC_INIT=\"${VC_INIT}\" -D QT5_BIN_DIR=\"${QT5_BIN_DIR}\" -P \"${CMAKE_SOURCE_DIR}/packaging/build_windows_vs.cmake\" WORKING_DIRECTORY \"${CMAKE_INSTALL_PREFIX}/..\" COMMAND_ECHO STDOUT)")
  elseif((CMAKE_SYSTEM_NAME STREQUAL "Windows") AND CMAKE_CROSSCOMPILING)
    file(STRINGS ${SPPARKS_DIR}/src/version.h line REGEX SPPARKS_VERSION)
    string(REGEX REPLACE "#define SPPARKS_VERSION \"([0-9]+) ([A-Za-z][A-Za-z][A-Za-z])[A-Za-z]* ([0-9]+)\""
                          "\\1\\2\\3" SPPARKS_RELEASE "${line}")
    if(BUILD_SHARED_LIBS)
      install(FILES $<TARGET_RUNTIME_DLLS:spparks> TYPE BIN)
    endif()
    install(FILES $<TARGET_RUNTIME_DLLS:spk> TYPE BIN)
    add_custom_target(zip
      COMMAND sh -vx ${SPPARKS_DIR}/cmake/packaging/build_windows_cross_zip.sh ${CMAKE_INSTALL_PREFIX} ${SPPARKS_RELEASE}
      DEPENDS spk spparks-gui_build ${WHAM_EXE}
      COMMENT "Create zip file with windows binaries"
      BYPRODUCT SPPARKS-Win10-amd64-${SPPARKS_VERSION}.zip
      WORKING_DIRECTORY ${CMAKE_BINARY_DIR})
  elseif((CMAKE_SYSTEM_NAME STREQUAL "Linux") AND NOT SPPARKS_GUI_USE_PLUGIN)
    file(STRINGS ${SPPARKS_DIR}/src/version.h line REGEX SPPARKS_VERSION)
    string(REGEX REPLACE "#define SPPARKS_VERSION \"([0-9]+) ([A-Za-z][A-Za-z][A-Za-z])[A-Za-z]* ([0-9]+)\""
      "\\1\\2\\3" SPPARKS_RELEASE "${line}")
    set(SPPARKS_GUI_PACKAGING ${CMAKE_BINARY_DIR}/spparks-gui_build-prefix/src/spparks-gui_build/packaging/)
    set(SPPARKS_GUI_RESOURCES ${CMAKE_BINARY_DIR}/spparks-gui_build-prefix/src/spparks-gui_build/resources/)
    install(PROGRAMS ${CMAKE_BINARY_DIR}/spparks-gui_build-prefix/bin/spparks-gui DESTINATION ${CMAKE_INSTALL_BINDIR})
    install(FILES ${SPPARKS_GUI_PACKAGING}/spparks-gui.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications/)
    install(FILES ${SPPARKS_GUI_PACKAGING}/spparks-gui.appdata.xml DESTINATION ${CMAKE_INSTALL_DATADIR}/appdata/)
    install(FILES ${SPPARKS_GUI_PACKAGING}/spparks-input.xml DESTINATION ${CMAKE_INSTALL_DATADIR}/mime/packages/)
    install(FILES ${SPPARKS_GUI_PACKAGING}/spparks-input.xml DESTINATION ${CMAKE_INSTALL_DATADIR}/mime/text/x-application-spparks.xml)
    install(DIRECTORY ${SPPARKS_GUI_RESOURCES}/icons/hicolor DESTINATION ${CMAKE_INSTALL_DATADIR}/icons/)
    install(CODE [[
      file(GET_RUNTIME_DEPENDENCIES
        LIBRARIES $<TARGET_FILE:spparks>
        EXECUTABLES $<TARGET_FILE:spk> ${CMAKE_BINARY_DIR}/spparks-gui_build-prefix/bin/spparks-gui
        RESOLVED_DEPENDENCIES_VAR _r_deps
        UNRESOLVED_DEPENDENCIES_VAR _u_deps
      )
      foreach(_file ${_r_deps})
        file(INSTALL
          DESTINATION "${CMAKE_INSTALL_PREFIX}/lib"
          TYPE SHARED_LIBRARY
          FOLLOW_SYMLINK_CHAIN
          FILES "${_file}"
        )
      endforeach()
      list(LENGTH _u_deps _u_length)
      if("${_u_length}" GREATER 0)
        message(WARNING "Unresolved dependencies detected: ${_u_deps}")
      endif() ]]
    )

    add_custom_target(tgz
      COMMAND ${SPPARKS_DIR}/cmake/packaging/build_linux_tgz.sh ${SPPARKS_RELEASE}
      DEPENDS spk spparks-gui_build ${WHAM_EXE}
      COMMENT "Create compressed tar file of SPPARKS-GUI with dependent libraries and wrapper"
      BYPRODUCT SPPARKS-Linux-x86_64-GUI-${SPPARKS_RELEASE}.tar.gz
      WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
    )
  endif()
endif()
