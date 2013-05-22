# bin dir variables in installspace
set(GENPY_BIN_DIR /opt/ros/groovy/lib/genpy)

set(GENMSG_PY_BIN ${GENPY_BIN_DIR}/genmsg_py.py)
set(GENSRV_PY_BIN ${GENPY_BIN_DIR}/gensrv_py.py)

include(CMakeParseArguments)

macro(thrift_add_service_files)
  cmake_parse_arguments(ARG "NOINSTALL" "DIRECTORY" "FILES" ${ARGN})
  if(ARG_UNPARSED_ARGUMENTS)
    message(FATAL_ERROR "thrift_add_service_files() called with unused arguments: ${ARG_UNPARSED_ARGUMENTS}")
  endif()

  if(NOT ARG_DIRECTORY)
    set(ARG_DIRECTORY "thrift")
  endif()

  set(SERVICE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/${ARG_DIRECTORY})

  if(NOT IS_DIRECTORY ${SERVICE_DIR})
    message(FATAL_ERROR "thrift_add_service_files() directory not found: ${SERVICE_DIR}")
  endif()

  # if FILES are not passed search service files in the given directory
  # note: ARGV is not variable, so it can not be passed to list(FIND) directly
  set(_argv ${ARGV})
  list(FIND _argv "FILES" _index)
  if(_index EQUAL -1)
    file(GLOB ARG_FILES RELATIVE "${SERVICE_DIR}" "${SERVICE_DIR}/*.thrift")
    list(SORT ARG_FILES)
  endif()
  _prepend_path(${SERVICE_DIR} "${ARG_FILES}" FILES_W_PATH)

  list(APPEND ${PROJECT_NAME}_THRIFT_SERVICE_FILES ${FILES_W_PATH})
  foreach(file ${FILES_W_PATH})
    debug_message(2 "thrift_add_service_files() srv file: ${file}")
    assert_file_exists(${file} "service file not found")
  endforeach()

  if(NOT ARG_NOINSTALL)
    # ensure that destination variables are initialized
    catkin_destinations()

    install(FILES ${FILES_W_PATH}
      DESTINATION ${CATKIN_PACKAGE_SHARE_DESTINATION}/${ARG_DIRECTORY})
  endif()


endmacro()


macro(thrift_generate_messages)
  cmake_parse_arguments(ARG "" "" "DEPENDENCIES;LANGS" ${ARGN})
  if(ARG_UNPARSED_ARGUMENTS)
    message(FATAL_ERROR "thrift_generate_messages() called with unused arguments: ${ARG_UNPARSED_ARGUMENTS}")
  endif()

  if(${PROJECT_NAME}_CATKIN_PACKAGE)
    message(FATAL_ERROR "thrift_generate_messages() must be called before catkin_package() in project '${PROJECT_NAME}'")
  endif()

  set(ARG_MESSAGES ${${PROJECT_NAME}_THRIFT_MESSAGE_FILES})
  set(ARG_SERVICES ${${PROJECT_NAME}_THRIFT_SERVICE_FILES})
  set(ARG_DEPENDENCIES ${ARG_DEPENDENCIES})

  if(ARG_LANGS)
    set(GEN_LANGS ${ARG_LANGS})
  else()
    #set(GEN_LANGS ${CATKIN_MESSAGE_GENERATORS})
    # XXX hardcoded generator
    set(GEN_LANGS "genpythrift")
  endif()

  # cmake dir in installspace
  set(genmsg_CMAKE_DIR ${genmsg_DIR})

  # ensure that destination variables are initialized
  catkin_destinations()

  # generate devel space config of message include dirs for project
  set(PKG_MSG_INCLUDE_DIRS "${${PROJECT_NAME}_MSG_INCLUDE_DIRS_DEVELSPACE}")
  configure_file(
    ${genmsg_CMAKE_DIR}/pkg-msg-paths.cmake.in
    ${CATKIN_DEVEL_PREFIX}/share/${PROJECT_NAME}/cmake/${PROJECT_NAME}-msg-paths.cmake
    @ONLY)
  # generate and install config of message include dirs for project
  _prepend_path(${CMAKE_INSTALL_PREFIX}/share/${PROJECT_NAME} "${${PROJECT_NAME}_MSG_INCLUDE_DIRS_INSTALLSPACE}" INCLUDE_DIRS_W_PATH)
  set(PKG_MSG_INCLUDE_DIRS "${INCLUDE_DIRS_W_PATH}")
  configure_file(
    ${genmsg_CMAKE_DIR}/pkg-msg-paths.cmake.in
    ${CMAKE_CURRENT_BINARY_DIR}/catkin_generated/installspace/${PROJECT_NAME}-msg-paths.cmake
    @ONLY)
  install(FILES ${CMAKE_CURRENT_BINARY_DIR}/catkin_generated/installspace/${PROJECT_NAME}-msg-paths.cmake
    DESTINATION ${CATKIN_PACKAGE_SHARE_DESTINATION}/cmake)

  # find configuration containing include dirs for projects in all devel- and installspaces
  set(workspaces ${CATKIN_WORKSPACES})
  list(FIND workspaces ${CATKIN_DEVEL_PREFIX} _index)
  if(_index EQUAL -1)
    list(INSERT workspaces 0 ${CATKIN_DEVEL_PREFIX})
  endif()

  set(pending_deps ${PROJECT_NAME} ${ARG_DEPENDENCIES})
  set(handled_deps "")
  while(pending_deps)
    list(GET pending_deps 0 dep)
    list(REMOVE_AT pending_deps 0)
    list(APPEND handled_deps ${dep})

    if(NOT ${dep}_FOUND AND NOT ${dep}_SOURCE_DIR)
      message(FATAL_ERROR "Messages depends on unknown pkg: ${dep} (Missing find_package(${dep}?))")
    endif()

    unset(config CACHE)
    set(filename "share/${dep}/cmake/${dep}-msg-paths.cmake")
    find_file(config ${filename} PATHS ${workspaces}
      NO_DEFAULT_PATH NO_CMAKE_FIND_ROOT_PATH)
    if("${config}" STREQUAL "config-NOTFOUND")
      message(FATAL_ERROR "Could not find '${filename}' (searched in '${workspaces}').")
    endif()
    include(${config})
    unset(config CACHE)

    foreach(path ${${dep}_MSG_INCLUDE_DIRS})
      list(APPEND MSG_INCLUDE_DIRS "${dep}")
      list(APPEND MSG_INCLUDE_DIRS "${path}")
    endforeach()

    # add transitive msg dependencies
    if(NOT ${dep} STREQUAL ${PROJECT_NAME})
      foreach(recdep ${${dep}_MSG_DEPENDENCIES})
        set(all_deps ${handled_deps} ${pending_deps})
        list(FIND all_deps ${recdep} _index)
        if(_index EQUAL -1)
          list(APPEND pending_deps ${recdep})
        endif()
      endforeach()
    endif()
  endwhile()

  # mark that thrift_generate_messages() was called in order to detect wrong order of calling with catkin_python_setup()
  set(${PROJECT_NAME}_GENERATE_MESSAGES TRUE)
  # check if catkin_python_setup() was called in order to skip installation of generated __init__.py file
  set(package_has_static_sources ${${PROJECT_NAME}_CATKIN_PYTHON_SETUP})

  em_expand(${genmsg_CMAKE_DIR}/pkg-genmsg.context.in
    ${CMAKE_CURRENT_BINARY_DIR}/cmake/${PROJECT_NAME}-genmsg-context-thrift.py
    ${CMAKE_SOURCE_DIR}/rosthrift/cmake/Resources/pkg-genmsg.cmake.em
    ${CMAKE_CURRENT_BINARY_DIR}/cmake/${PROJECT_NAME}-genmsg-thrift.cmake)

  set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} "${CMAKE_SOURCE_DIR}/rosthrift/cmake/Modules")
  include(${CMAKE_CURRENT_BINARY_DIR}/cmake/${PROJECT_NAME}-genmsg-thrift.cmake)
endmacro()

#todo, these macros are practically equal. Check for input file extension instead
macro(_generate_srv_pythrift ARG_PKG ARG_SRV ARG_IFLAGS ARG_MSG_DEPS ARG_GEN_OUTPUT_DIR)
  #Append msg to output dir
  set(GEN_OUTPUT_DIR "${ARG_GEN_OUTPUT_DIR}/thrift")
  file(MAKE_DIRECTORY ${GEN_OUTPUT_DIR})
  file(MAKE_DIRECTORY ${GEN_OUTPUT_DIR}_twisted)

  #Create input and output filenames
  get_filename_component(SRV_SHORT_NAME ${ARG_SRV} NAME_WE)

  set(SRV_GENERATED_NAME ${SRV_SHORT_NAME})
  set(GEN_OUTPUT_FILE ${GEN_OUTPUT_DIR}/${SRV_GENERATED_NAME})

  add_custom_command(OUTPUT ${GEN_OUTPUT_FILE}
    COMMAND ${CATKIN_ENV} "/usr/bin/thrift"
    -out ${GEN_OUTPUT_DIR}
    -r
    --gen py
    ${ARG_SRV}
    COMMENT "Generating Python code from Thrift ${ARG_PKG}/${SRV_SHORT_NAME}"
    )

  add_custom_command(OUTPUT ${GEN_OUTPUT_DIR}_twisted/${SRV_GENERATED_NAME}
    COMMAND ${CATKIN_ENV} "/usr/bin/thrift"
    -out ${GEN_OUTPUT_DIR}_twisted
    -r
    --gen py:twisted
    ${ARG_SRV}
    COMMENT "Generating Twisted Python code from Thrift ${ARG_PKG}/${SRV_SHORT_NAME}"
    )

  list(APPEND ALL_GEN_OUTPUT_FILES_pythrift ${GEN_OUTPUT_FILE} ${GEN_OUTPUT_DIR}_twisted/${SRV_GENERATED_NAME})

endmacro()

if(NOT EXISTS genpythrift_SOURCE_DIR)
  set(genpythrift_INSTALL_DIR ${PYTHON_INSTALL_DIR})
endif()
