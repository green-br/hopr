# =========================================================================
# Set download locations depending on git origin
# =========================================================================
SET(LIBS_DLPATH "https://gitlab.iag.uni-stuttgart.de/")
# Origin pointing to IAG
IF("${GIT_ORIGIN}" MATCHES ".iag.uni-stuttgart.de" AND "${GIT_ORIGIN}" MATCHES "^git@")
  # SSH is expensive, run it only once
  IF(NOT DEFINED SSH_IAG_CACHED)
    # Check if IAG Gitlab is reachable with SSH
    EXECUTE_PROCESS(COMMAND ssh -T -o BatchMode=yes -o ConnectTimeout=5 git@gitlab.iag.uni-stuttgart.de
                    RESULT_VARIABLE SSH_IAG
                    OUTPUT_QUIET ERROR_QUIET)
    SET(SSH_IAG_CACHED "{SSH_IAG}" CACHE INTERNAL "Exit code of SSH check")
    IF(SSH_IAG EQUAL 0)
      SET(LIBS_DLPATH "git@gitlab.iag.uni-stuttgart.de:")
    ELSE()
      MESSAGE(STATUS "Cannot reach gitlab.iag.uni-stuttgart.de via SSH. Falling back to HTTPS.")
    ENDIF()
  ENDIF()
ENDIF()

# Unset leftover variables from previous runs
UNSET(linkedlibs CACHE)

# =========================================================================
# MPI
# =========================================================================
# Try to find system MPI
SET(MPI_DETERMINE_LIBRARY_VERSION TRUE)
FIND_PACKAGE(MPI QUIET)
IF (MPI_FOUND)
  MESSAGE (STATUS "[MPI] found in system libraries")
  OPTION(LIBS_USE_MPI "Compile SINGLE or MPI version" ON)
ELSE()
  MESSAGE (STATUS "[MPI] not found in system libraries")
  OPTION(LIBS_USE_MPI "Compile SINGLE or MPI version" OFF)
ENDIF()

IF(LIBS_USE_MPI)
  # If library is specifically requested, it is required
  SET(MPI_DETERMINE_LIBRARY_VERSION TRUE)
  FIND_PACKAGE(MPI REQUIRED)

  IF (NOT MPI_Fortran_NO_INTERROGATE)
    FOREACH(DIR ${MPI_INCLUDE_PATH})
      INCLUDE_DIRECTORIES(${DIR})
    ENDFOREACH()
    FOREACH(DIR ${MPI_Fortran_INCLUDE_PATH})
      INCLUDE_DIRECTORIES(${DIR})
    ENDFOREACH()
    LIST(APPEND linkedlibs ${MPI_Fortran_LIBRARIES})
  ENDIF()

  MARK_AS_ADVANCED(FORCE MPI_LIBRARY MPI_EXTRA_LIBRARY)
  ADD_COMPILE_DEFINITIONS(LIBS_MPICH_FIX_SHM_INTERFACE=0)

  # Detect MPI implementation and version since it changes some MPI definitions
  IF(MPI_C_LIBRARY_VERSION_STRING MATCHES ".*CRAY MPICH.*" AND MPI_C_VERSION_MAJOR VERSION_EQUAL "3")
    SET(LIBS_MPI_NAME "Cray MPICH")
    STRING(REGEX MATCH "([0-9]+)\\.([0-9]+)" MPI_C_LIBRARY_VERSION ${MPI_C_LIBRARY_VERSION_STRING})
    # Cray MPICH in combination with GNU has problems with calling the same MPI routine
    # with different arguments in the same compilation unit
    IF (CMAKE_Fortran_COMPILER_ID MATCHES "GNU")
      SET(CMAKE_Fortran_FLAGS  "${CMAKE_Fortran_FLAGS} -fallow-argument-mismatch")
    ENDIF()
  ELSEIF(MPI_C_LIBRARY_VERSION_STRING MATCHES ".*MPICH.*" AND MPI_C_VERSION_MAJOR VERSION_GREATER_EQUAL "3")
    SET(LIBS_MPI_NAME "MPICH")
    STRING(REGEX MATCH "([0-9]+)\\.([0-9]+)" MPI_C_LIBRARY_VERSION ${MPI_C_LIBRARY_VERSION_STRING})
    # Missing interface added in 4.2, see https://github.com/pmodels/mpich/pull/6727
    IF(${MPI_C_LIBRARY_VERSION} VERSION_LESS_EQUAL "4.1")
      ADD_COMPILE_DEFINITIONS(LIBS_MPICH_FIX_SHM_INTERFACE=1)
    ENDIF()
    # MPICH in combination with GNU has problems with calling the same MPI routine
    # with different arguments in the same compilation unit
    IF (CMAKE_Fortran_COMPILER_ID MATCHES "GNU")
      SET(CMAKE_Fortran_FLAGS  "${CMAKE_Fortran_FLAGS} -fallow-argument-mismatch")
    ENDIF()
  ELSEIF(MPI_C_LIBRARY_VERSION_STRING MATCHES ".*Open MPI.*" AND MPI_C_VERSION_MAJOR VERSION_EQUAL "3")
    SET(LIBS_MPI_NAME "OpenMPI")
    STRING(REGEX MATCH "([0-9]+)\\.([0-9]+)\\.([0-9]+)" MPI_C_LIBRARY_VERSION ${MPI_C_LIBRARY_VERSION_STRING})
  ELSEIF(MPI_C_LIBRARY_VERSION_STRING MATCHES ".*HPE MPT.*" AND MPI_C_VERSION_MAJOR VERSION_EQUAL "3")
    #SET(LIBS_MPI_NAME "HPE MPT")
    #STRING(REGEX MATCH "([0-9]+)\\.([0-9]+)" MPI_C_LIBRARY_VERSION ${MPI_C_LIBRARY_VERSION_STRING})
    MESSAGE(FATAL_ERROR "HPE MPT not supported any more")
  ELSEIF(MPI_C_LIBRARY_VERSION_STRING MATCHES ".*Intel.*" AND MPI_C_VERSION_MAJOR VERSION_GREATER_EQUAL "3")
    SET(LIBS_MPI_NAME "Intel MPI")
    STRING(REGEX MATCH "([0-9]+)\\.([0-9]+)" MPI_C_LIBRARY_VERSION ${MPI_C_LIBRARY_VERSION_STRING})
  ELSE()
    MESSAGE(FATAL_ERROR "Cannot detect supported MPI type or version. Valid options are Cray MPICH, IntelMPI, MPICH, and OpenMPI supporting MPI version 3.x")
  ENDIF()

  MESSAGE(STATUS "Compiling with [${LIBS_MPI_NAME}] (v${MPI_C_LIBRARY_VERSION})")
  ADD_COMPILE_DEFINITIONS(USE_MPI=1)

  # LUMI needs even more help here
  IF("${CMAKE_FQDN_HOST}" MATCHES ".can")
    SET(MPI_C_COMPILER       cc)
    SET(MPI_CXX_COMPILER     CC)
    SET(MPI_Fortran_COMPILER ftn)
  ENDIF()
ELSE()
  ADD_COMPILE_DEFINITIONS(USE_MPI=0)
ENDIF()


# =========================================================================
# Add the libraries
# =========================================================================
# Set directory to compile external libraries
IF(LIBS_USE_MPI)
  SET(LIBS_EXTERNAL_LIB_DIR ${CMAKE_CURRENT_SOURCE_DIR}/share/${CMAKE_Fortran_COMPILER_ID}-MPI)
ELSE()
  SET(LIBS_EXTERNAL_LIB_DIR ${CMAKE_CURRENT_SOURCE_DIR}/share/${CMAKE_Fortran_COMPILER_ID})
ENDIF()
MARK_AS_ADVANCED(FORCE LIBS_EXTERNAL_LIB_DIR)

# =========================================================================
# HDF5 library
# =========================================================================
# Try to find system HDF5 using CMake
SET(LIBS_HDF5_CMAKE TRUE)

# Set preferences for HDF5 library
# SET(HDF5_USE_STATIC_LIBRARIES TRUE)
IF (LIBS_USE_MPI)
  SET(HDF5_PREFER_PARALLEL TRUE)
  FIND_PROGRAM(HDF5_COMPILER h5pcc)
ELSE()
  SET(HDF5_PREFER_PARALLEL FALSE)
  FIND_PROGRAM(HDF5_COMPILER h5cc)
ENDIF()

# When using the configure version, CMake takes the directory of the first HDF5 compiler found
# > h5cc  - serial   version
# > h5pcc - parallel version
# > Thus, we need to prepend the PATH to ensure we are picking the correct one first
IF(NOT "${HDF5_COMPILER}" STREQUAL "" AND NOT "${HDF5_COMPILER}" STREQUAL "HDF5_COMPILER-NOTFOUND")
  SET(ORIGINAL_PATH_ENV "$ENV{PATH}")
  GET_FILENAME_COMPONENT(HDF5_PARENT_DIR ${HDF5_COMPILER} DIRECTORY)
  SET(ENV{PATH} "${HDF5_PARENT_DIR}:$ENV{PATH}")
ENDIF()

# Hide all the HDF5 libs paths
MARK_AS_ADVANCED(FORCE HDF5_DIR)
MARK_AS_ADVANCED(FORCE HDF5_C_INCLUDE_DIR)
MARK_AS_ADVANCED(FORCE HDF5_DIFF_EXECUTABLE)
MARK_AS_ADVANCED(FORCE HDF5_Fortran_INCLUDE_DIR)
MARK_AS_ADVANCED(FORCE HDF5_C_LIBRARY_dl)
MARK_AS_ADVANCED(FORCE HDF5_C_LIBRARY_hdf5)
MARK_AS_ADVANCED(FORCE HDF5_C_LIBRARY_m)
MARK_AS_ADVANCED(FORCE HDF5_C_LIBRARY_sz)
MARK_AS_ADVANCED(FORCE HDF5_C_LIBRARY_z)
MARK_AS_ADVANCED(FORCE HDF5_Fortran_LIBRARY_dl)
MARK_AS_ADVANCED(FORCE HDF5_Fortran_LIBRARY_hdf5)
MARK_AS_ADVANCED(FORCE HDF5_Fortran_LIBRARY_hdf5_fortran)
MARK_AS_ADVANCED(FORCE HDF5_Fortran_LIBRARY_m)
MARK_AS_ADVANCED(FORCE HDF5_Fortran_LIBRARY_sz)
MARK_AS_ADVANCED(FORCE HDF5_Fortran_LIBRARY_z)
MARK_AS_ADVANCED(FORCE HDF5_hdf5_LIBRARY_hdf5)
MARK_AS_ADVANCED(FORCE HDF5_hdf5_LIBRARY_RELEASE)
MARK_AS_ADVANCED(FORCE HDF5_Fortran_LIBRARY_hdf5_fortran)
MARK_AS_ADVANCED(FORCE HDF5_Fortran_LIBRARY_hdf5_fortran_RELEASE)

IF (NOT LIBS_BUILD_HDF5)
  FIND_PACKAGE(HDF5 QUIET COMPONENTS C Fortran)

  IF (HDF5_FOUND)
    MESSAGE (STATUS "[HDF5] found in system libraries [${HDF5_DIR}]")
    SET(LIBS_BUILD_HDF5 OFF CACHE BOOL "Compile and build HDF5 library")
  ELSE()
    MESSAGE (STATUS "[HDF5] not found in system libraries")
    SET(LIBS_BUILD_HDF5 ON  CACHE BOOL "Compile and build HDF5 library")
  ENDIF()
ENDIF()

# Use system HDF5
IF(NOT LIBS_BUILD_HDF5)
  # Unset leftover paths from old CMake runs
  UNSET(HDF5_VERSION CACHE)
  UNSET(HDF5_DEFINITIONS)
  UNSET(HDF5_LIBRARIES)
  UNSET(HDF5_INCLUDE_DIR_FORTRAN)
  UNSET(HDF5_INCLUDE_DIR)
  UNSET(HDF5_DIFF_EXECUTABLE)

  # If library is specifically requested, it is required
  FIND_PACKAGE(HDF5 REQUIRED COMPONENTS C Fortran)

  # Check if HDF5 is parallel
  # > HDF5_IS_PARALLEL is set by FIND_PACKAGE(HDF5)
  IF(LIBS_USE_MPI)
    IF(NOT HDF5_IS_PARALLEL)
      MESSAGE(FATAL_ERROR "HDF5 is not built with parallel support. Please install a parallel version of HDF5 or build it yourself.")
    ENDIF()

    # If HDF5 Fortran library is not set, get it from the Fortran target
    IF("${HDF5_Fortran_LIBRARY_hdf5_fortran}" STREQUAL "")
      GET_PROPERTY(HDF5_Fortran_LIBRARY_hdf5_fortran TARGET hdf5::hdf5_fortran PROPERTY LOCATION)
    ENDIF()

    IF(NOT "${HDF5_Fortran_LIBRARY_hdf5_fortran}" STREQUAL "")
      IF(APPLE)
        EXECUTE_PROCESS(COMMAND nm -gU      ${HDF5_Fortran_LIBRARY_hdf5_fortran} COMMAND grep mpio_f08 OUTPUT_VARIABLE HDF5_USES_MPIF08 RESULT_VARIABLE GREP_RESULT OUTPUT_STRIP_TRAILING_WHITESPACE)
      ELSE()
        EXECUTE_PROCESS(COMMAND readelf -Ws ${HDF5_Fortran_LIBRARY_hdf5_fortran} COMMAND grep mpio_f08 OUTPUT_VARIABLE HDF5_USES_MPIF08 RESULT_VARIABLE GREP_RESULT OUTPUT_STRIP_TRAILING_WHITESPACE)
      ENDIF()
    # Cray might still not provide anything, set mpi_f08 to false
    ELSE()
      SET(GREP_RESULT 1)
    ENDIF()

    IF(GREP_RESULT EQUAL 0)
      SET(HDF5_MPI_VERSION "[mpi_f08]")
      SET(HDF5_HAS_MPIF08 TRUE)
    ELSE()
      SET(HDF5_MPI_VERSION "[mpi]")
      SET(HDF5_HAS_MPIF08 FALSE)
    ENDIF()
  ENDIF()

  # Set build status to system
  SET(HDF5_BUILD_STATUS "system")
ELSE()
  MESSAGE(STATUS "Setting [HDF5] to self-build")
  # Origin pointing to Github
  IF("${GIT_ORIGIN}" MATCHES ".github.com")
    SET (HDF5DOWNLOAD "https://github.com/HDFGroup/hdf5.git")
  ELSE()
    SET (HDF5DOWNLOAD ${LIBS_DLPATH}libs/hdf5.git )
  ENDIF()
  SET(HDF5_DOWNLOAD ${HDF5DOWNLOAD} CACHE STRING "HDF5 Download-link")
  MESSAGE(STATUS "Setting [HDF5] download link: ${HDF5DOWNLOAD}")
  MARK_AS_ADVANCED(FORCE HDF5_DOWNLOAD)

  # Set HDF5 tag / version
  SET(HDF5_STR "1.14.5")
  SET(HDF5_TAG "hdf5_${HDF5_STR}" CACHE STRING   "HDF5 version tag")
  MARK_AS_ADVANCED(FORCE HDF5_TAG)
  MESSAGE(STATUS "Setting [HDF5] download tag:  ${HDF5_TAG}")

  # Set HDF5 build dir
  SET(LIBS_HDF5_DIR ${LIBS_EXTERNAL_LIB_DIR}/HDF5/build)

  # Check if HDF5 was already built
  UNSET(HDF5_FOUND)
  UNSET(HDF5_VERSION)
  UNSET(HDF5_INCLUDE_DIR)
  UNSET(HDF5_LIBRARIES)
  UNSET(HDF5_Fortran_LIBRARIES)
  FIND_PACKAGE(HDF5 ${HDF5_STR} QUIET COMPONENTS C Fortran HDF5_PREFER_PARALLEL=${LIBS_USE_MPI} PATHS ${LIBS_HDF5_DIR} NO_DEFAULT_PATH)

  # CMake does not correctly pick-up HDF5 parallel support, thus set it manually
  SET(HDF5_IS_PARALLEL ${LIBS_USE_MPI})
  IF(HDF5_IS_PARALLEL)
    SET(HDF5_MPI_VERSION "[mpi_f08]")
    SET(HDF5_HAS_MPIF08 TRUE)
  ENDIF()

  IF(HDF5_FOUND)
    # If re-running CMake, it might wrongly pick-up the system HDF5
    IF(NOT EXISTS ${LIBS_HDF5_DIR}/lib/libhdf5.so)
      UNSET(HDF5_FOUND)
      SET(HDF5_VERSION     ${HDF5_STR})
    ENDIF()

    # CMake might fail to set the HDF5 paths
    IF(HDF5_FOUND AND "${HDF5_LIBRARIES}" STREQUAL "")
      SET(HDF5_LIBRARIES         ${LIBS_HDF5_DIR}/lib/libhdf5.so ${LIBS_HDF5_DIR}/lib/libhdf5.a ${LIBS_HDF5_DIR}/lib/libhdf5_fortran.so ${LIBS_HDF5_DIR}/lib/libhdf5_fortran.a)
      SET(HDF5_Fortran_LIBRARIES ${LIBS_HDF5_DIR}/lib/libhdf5.so ${LIBS_HDF5_DIR}/lib/libhdf5.a ${LIBS_HDF5_DIR}/lib/libhdf5_fortran.so ${LIBS_HDF5_DIR}/lib/libhdf5_fortran.a)
    ENDIF()
  ENDIF()

  # Check again if HDF5 was found
  IF(NOT HDF5_FOUND)
    # Set parallel build with maximum number of threads
    INCLUDE(ProcessorCount)
    PROCESSORCOUNT(N)

    # Let CMake take care of download, configure and build
    EXTERNALPROJECT_ADD(HDF5
      GIT_REPOSITORY     ${HDF5_DOWNLOAD}
      GIT_TAG            ${HDF5_TAG}
      GIT_PROGRESS       TRUE
      ${${GITSHALLOW}}
      PREFIX             ${LIBS_HDF5_DIR}
      INSTALL_DIR        ${LIBS_HDF5_DIR}
      UPDATE_COMMAND     ""
      # HDF5 explicitely needs "make" to configure
      CMAKE_GENERATOR    "Unix Makefiles"
      BUILD_COMMAND      make -j${N}
      # Set the CMake arguments for HDF5
      CMAKE_ARGS         -DCMAKE_BUILD_TYPE=None -DCMAKE_INSTALL_PREFIX=${LIBS_HDF5_DIR} -DHDF5_INSTALL_CMAKE_DIR=lib/cmake/hdf5 -DCMAKE_POLICY_DEFAULT_CMP0175=OLD -DBUILD_STATIC_LIBS=ON -DHDF5_BUILD_FORTRAN=ON -DHDF5_ENABLE_Z_LIB_SUPPORT=OFF -DHDF5_ENABLE_SZIP_SUPPORT=OFF -DHDF5_ENABLE_PARALLEL=${LIBS_USE_MPI}
      # Set the build byproducts
      INSTALL_BYPRODUCTS ${LIBS_HDF5_DIR}/lib/libhdf5_fortran.a ${LIBS_HDF5_DIR}/lib/libhdf5.a ${LIBS_HDF5_DIR}/lib/libhdf5.so ${LIBS_HDF5_DIR}/lib/libhdf5_fortran.so ${LIBS_HDF5_DIR}/bin/h5diff
    )

    # Add CMake HDF5 to the list of self-built externals
    LIST(APPEND SELFBUILTEXTERNALS HDF5)

    # Set HDF5 version and MPI support
    SET(HDF5_VERSION ${HDF5_STR})

    # Set HDF5 paths
    SET(HDF5_INCLUDE_DIR       ${LIBS_HDF5_DIR}/include)
    SET(HDF5_DIFF_EXECUTABLE   ${LIBS_HDF5_DIR}/bin/h5diff)
    SET(HDF5_LIBRARIES         ${LIBS_HDF5_DIR}/lib/libhdf5.so ${LIBS_HDF5_DIR}/lib/libhdf5.a ${LIBS_HDF5_DIR}/lib/libhdf5_fortran.so ${LIBS_HDF5_DIR}/lib/libhdf5_fortran.a)
    SET(HDF5_Fortran_LIBRARIES ${LIBS_HDF5_DIR}/lib/libhdf5.so ${LIBS_HDF5_DIR}/lib/libhdf5.a ${LIBS_HDF5_DIR}/lib/libhdf5_fortran.so ${LIBS_HDF5_DIR}/lib/libhdf5_fortran.a)
  ENDIF()

  # Set build status to self-built
  SET(HDF5_BUILD_STATUS "self-built")
ENDIF()

# HDF5 1.14 references build directory
# > https://github.com/HDFGroup/hdf5/issues/2422
IF(HDF5_VERSION VERSION_EQUAL "1.14")
  LIST(FILTER HDF5_INCLUDE_DIR EXCLUDE REGEX "src/H5FDsubfiling")
ENDIF()

# Actually add the HDF5 paths (system/self-built) to the linking paths
# > INFO: We could also use the HDF5::HDF5/hdf5::hdf5/hdf5::hdf5_fortran targets here but they are not set before compiling self-built HDF5
INCLUDE_DIRECTORIES(BEFORE ${HDF5_INCLUDE_DIR})
LIST(PREPEND linkedlibs ${HDF5_LIBRARIES} )
IF(${HDF5_IS_PARALLEL})
  MESSAGE(STATUS "Compiling with ${HDF5_BUILD_STATUS} [HDF5] (v${HDF5_VERSION}) with parallel support ${HDF5_MPI_VERSION}")
ELSE()
  MESSAGE(STATUS "Compiling with ${HDF5_BUILD_STATUS} [HDF5] (v${HDF5_VERSION}) without parallel support")
ENDIF()

# Restore the original PATH
SET(ENV{PATH} "${ORIGINAL_PATH_ENV}")


# =========================================================================
# Math libary
# =========================================================================
# Try to find system LAPACK/OpenBLAS
IF (NOT LIBS_BUILD_MATH_LIB)
  FIND_PACKAGE(LAPACK QUIET)
ENDIF()

IF (LAPACK_FOUND)
  MESSAGE (STATUS "[BLAS/Lapack] found in system libraries")
  SET(LIBS_BUILD_MATH_LIB OFF CACHE BOOL "Compile and build math library")
ELSE()
  MESSAGE (STATUS "[BLAS/Lapack] not found in system libraries")
  SET(LIBS_BUILD_MATH_LIB ON  CACHE BOOL "Compile and build math library")
ENDIF()

# Use system LAPACK/MKL
IF(NOT LIBS_BUILD_MATH_LIB)
  # If library is specifically requested, it is required
  FIND_PACKAGE(LAPACK REQUIRED)
  IF (LAPACK_FOUND)
    LIST(APPEND linkedlibs ${LAPACK_LIBRARIES})
    MESSAGE(STATUS "Compiling with system [BLAS/Lapack]")
  ENDIF()

# Build LAPACK/OpenBLAS in HOPR
ELSE()
  # Offer LAPACK and OpenBLAS
  SET (LIBS_BUILD_MATH_LIB_VENDOR LAPACK CACHE STRING "Choose the type of math lib vendor, options are: LAPACK, OpenBLAS.")
  SET_PROPERTY(CACHE LIBS_BUILD_MATH_LIB_VENDOR PROPERTY STRINGS LAPACK OpenBLAS)

  # Build LAPACK
  IF (LIBS_BUILD_MATH_LIB_VENDOR STREQUAL "LAPACK")
    # Origin pointing to Github
    IF("${GIT_ORIGIN}" MATCHES ".github.com")
      SET (MATHLIB_DOWNLOAD "https://github.com/Reference-LAPACK/lapack.git")
    ELSE()
      SET (MATHLIB_DOWNLOAD ${LIBS_DLPATH}libs/lapack.git)
    ENDIF()
    SET (MATH_LIB_DOWNLOAD ${MATHLIB_DOWNLOAD} CACHE STRING "LAPACK Download-link" FORCE)
    SET (MATH_LIB_TAG "v3.12.1")
    MARK_AS_ADVANCED(FORCE MATH_LIB_DOWNLOAD)
    MARK_AS_ADVANCED(FORCE MATH_LIB_TAG)
  # Build OpenBLAS
  ELSEIF (LIBS_BUILD_MATH_LIB_VENDOR STREQUAL "OpenBLAS")
    IF("${GIT_ORIGIN}" MATCHES ".github.com")
      SET (MATHLIB_DOWNLOAD "https://github.com/OpenMathLib/OpenBLAS.git")
    ELSE()
      SET (MATHLIB_DOWNLOAD ${LIBS_DLPATH}libs/OpenBLAS.git)
    ENDIF()
    SET (MATH_LIB_DOWNLOAD ${MATHLIB_DOWNLOAD} CACHE STRING "OpenBLAS Download-link" FORCE)
    SET (MATH_LIB_TAG "v0.3.29")
    MARK_AS_ADVANCED(FORCE MATH_LIB_DOWNLOAD)
    MARK_AS_ADVANCED(FORCE MATH_LIB_TAG)
  # Unknown math lib vendor
  ELSE()
    MESSAGE(FATAL_ERROR "Unknown math lib vendor")
  ENDIF()

  # Set math libs build dir
  SET(LIBS_MATH_DIR  ${LIBS_EXTERNAL_LIB_DIR}/${LIBS_BUILD_MATH_LIB_VENDOR})

  IF (LIBS_BUILD_MATH_LIB_VENDOR STREQUAL "LAPACK")
    # Check if math lib was already built
    IF (NOT EXISTS "${LIBS_MATH_DIR}/lib/liblapack.so")
      # Let CMake take care of download, configure and build
      EXTERNALPROJECT_ADD(${LIBS_BUILD_MATH_LIB_VENDOR}
        GIT_REPOSITORY ${MATH_LIB_DOWNLOAD}
        GIT_TAG ${MATH_LIB_TAG}
        GIT_PROGRESS TRUE
        ${${GITSHALLOW}}
        PREFIX ${LIBS_MATH_DIR}
        UPDATE_COMMAND ""
        CMAKE_ARGS -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_INSTALL_PREFIX=${LIBS_MATH_DIR} -DBLAS++=OFF -DLAPACK++=OFF -DBUILD_SHARED_LIBS=ON -DCBLAS=OFF -DLAPACKE=OFF -DBUILD_TESTING=OFF
        BUILD_BYPRODUCTS ${LIBS_MATH_DIR}/lib/liblapack.so ${LIBS_MATH_DIR}/lib/libblas.so
      )

      LIST(APPEND SELFBUILTEXTERNALS ${LIBS_BUILD_MATH_LIB_VENDOR})
    ENDIF()
  ELSEIF (LIBS_BUILD_MATH_LIB_VENDOR STREQUAL "OpenBLAS")
    # Check if math lib was already built
    IF (NOT EXISTS "${LIBS_MATH_DIR}/libopenblas.so")
      # Let CMake take care of download, configure and build
      EXTERNALPROJECT_ADD(${LIBS_BUILD_MATH_LIB_VENDOR}
        GIT_REPOSITORY ${MATH_LIB_DOWNLOAD}
        GIT_TAG ${MATH_LIB_TAG}
        GIT_PROGRESS TRUE
        ${${GITSHALLOW}}
        PREFIX ${LIBS_MATH_DIR}
        UPDATE_COMMAND ""
        CONFIGURE_COMMAND ""
        BUILD_BYPRODUCTS ${LIBS_MATH_DIR}/src/${LIBS_BUILD_MATH_LIB_VENDOR}/libopenblas.so
        BUILD_IN_SOURCE TRUE
        INSTALL_COMMAND ""
      )

      LIST(APPEND SELFBUILTEXTERNALS ${LIBS_BUILD_MATH_LIB_VENDOR})
    ENDIF()
  ENDIF()

  IF (LIBS_BUILD_MATH_LIB_VENDOR STREQUAL "LAPACK")
    # Set math lib paths
    UNSET(MATH_LIB_LIBRARIES)
    SET(MATH_LIB_LIBRARIES              ${LIBS_MATH_DIR}/lib)

    UNSET(LAPACK_LIBRARY)
    UNSET(BLAS_LIBRARY)
    UNSET(LAPACK_LIBRARIES)

    SET(LAPACK_LIBRARY                  ${MATH_LIB_LIBRARIES}/liblapack.so)
    SET(BLAS_LIBRARY                    ${MATH_LIB_LIBRARIES}/libblas.so)
    SET(LAPACK_LIBRARIES                ${LAPACK_LIBRARY}${BLAS_LIBRARY})

    # Actually add the math lib paths to the linking paths
    INCLUDE_DIRECTORIES (${MATH_LIB_LIBRARIES})
    LIST(APPEND linkedlibs ${LAPACK_LIBRARY} ${BLAS_LIBRARY})
    MESSAGE(STATUS "Compiling with self-built [LAPACK]")
  ELSEIF (LIBS_BUILD_MATH_LIB_VENDOR STREQUAL "OpenBLAS")
    # Set math lib paths
    SET(MATH_LIB_LIBRARIES              ${LIBS_MATH_DIR}/src/${LIBS_BUILD_MATH_LIB_VENDOR})

    UNSET(LAPACK_LIBRARY)
    UNSET(LAPACK_LIBRARIES)

    SET(LAPACK_LIBRARY                  ${MATH_LIB_LIBRARIES}/libopenblas.so)
    SET(LAPACK_LIBRARIES                ${LAPACK_LIBRARY}${BLAS_LIBRARY})

    # Actually add the math lib paths to the linking paths
    INCLUDE_DIRECTORIES (${MATH_LIB_LIBRARIES})
    LIST(APPEND linkedlibs ${LAPACK_LIBRARY} ${BLAS_LIBRARY})
    MESSAGE(STATUS "Compiling with self-built [OpenBLAS]")
  ENDIF()
ENDIF()


# =========================================================================
# CGNS library
# =========================================================================
# Try to find system LAPACK/OpenBLAS
OPTION(LIBS_USE_CGNS "Switch for using cgns as a library (needed for input/output of CGNS files)" ON)

IF (NOT LIBS_USE_CGNS)
  UNSET(LIBS_BUILD_CGNS     CACHE)
  UNSET(LIBS_BUILD_CGNS_INT CACHE)
  UNSET(LIBS_BUILD_CGNS_TAG CACHE)
ELSE()
  ADD_DEFINITIONS(-DPP_USE_CGNS=${HOPR_USE_CGNS})
  SET(LIBS_BUILD_CGNS ON CACHE BOOL "Compile and build CGNS library")
  SET(LIBS_BUILD_CGNS_INT "32" CACHE STRING "integer type in CGNS lib")
  ADD_DEFINITIONS(-DPP_CGNS_INT=${LIBS_BUILD_CGNS_INT})

  # Use system CGNS
  IF (NOT LIBS_BUILD_CGNS)
    FIND_PACKAGE(CGNS)
    IF (CGNS_FOUND)
      MESSAGE(STATUS "CGNS include dir: " ${CGNS_INCLUDE_DIR})
      LIST(INSERT linkedlibs 0 ${CGNS_LIBRARIES})
      INCLUDE_DIRECTORIES (${CGNS_INCLUDE_DIR})

      # Find "^#define CGNS_VERSION" and get only the numbers and remove trailing line breaks
      EXECUTE_PROCESS(COMMAND cat "${CGNS_INCLUDE_DIR}/cgnslib.h" COMMAND grep "^#define CGNS_VERSION" COMMAND grep -o "[[:digit:]]*" COMMAND tr -d '\n' OUTPUT_VARIABLE CGNS_VERSION)
      MESSAGE(STATUS "Found CGNS version in cgnslib.h [${CGNS_VERSION}]")

    ELSE()
      MESSAGE(ERROR "CGNS not found")
    ENDIF()
  ELSE()

    # Set CGNS_Tag
    SET (LIBS_BUILD_CGNS_TAG "v4.3.0" CACHE STRING "CGNS version tag from ${CGNSDOWNLOAD}")
    SET_PROPERTY(CACHE LIBS_BUILD_CGNS_TAG PROPERTY STRINGS "v3.4.1" "v4.0.0" "v4.3.0")
    MESSAGE(STATUS "Compiling CGNS version tag: " ${LIBS_BUILD_CGNS_TAG})

    IF("${LIBS_BUILD_CGNS_TAG}" MATCHES "v4.3.0")
      SET(CGNS_VERSION 4300)
    ELSEIF("${LIBS_BUILD_CGNS_TAG}" MATCHES "v4.0.0")
      SET(CGNS_VERSION 4000)
    ELSEIF("${LIBS_BUILD_CGNS_TAG}" MATCHES "v3.4.1")
      SET(CGNS_VERSION 3401)
    ELSE()
      SET(CGNS_VERSION -1)
    ENDIF()

    SET(LIBS_CGNS_DLDIR ${LIBS_EXTERNAL_LIB_DIR}/CGNS${LIBS_BUILD_CGNS_TAG})
    SET(LIBS_CGNS_DIR   ${LIBS_CGNS_DLDIR})

    IF (NOT EXISTS "${LIBS_CGNS_DIR}/lib/libcgns.a")
      STRING(COMPARE EQUAL ${LIBS_BUILD_CGNS_INT} "64" LIBS_CGNS_64BIT)

      # Origin pointing to Github
      IF("${GIT_ORIGIN}" MATCHES ".github.com")
        SET (CGNSDOWNLOAD "https://github.com/CGNS/CGNS.git")
      ELSE()
        SET (CGNSDOWNLOAD ${LIBS_DLPATH}libs/cgns.git )
      ENDIF()
      MESSAGE(STATUS "Downloading CGNS from ${CGNSDOWNLOAD}")

      # Fallback for disabling HDF5 for CGNS compilation
      OPTION(LIBS_BUILD_CGNS_ENABLE_HDF5 "Build CGNS library with -DCGNS_ENABLE_HDF5=ON" ON)
      MESSAGE(STATUS "Build CGNS library with -DCGNS_ENABLE_HDF5=" ${LIBS_BUILD_CGNS_ENABLE_HDF5})

      # Build CGNS with HDF5 support
      EXTERNALPROJECT_ADD(cgns
        GIT_REPOSITORY ${CGNSDOWNLOAD}
        GIT_TAG ${LIBS_BUILD_CGNS_TAG}
        GIT_PROGRESS TRUE
        ${${GITSHALLOW}}
        PREFIX ${LIBS_CGNS_DIR}
        CMAKE_ARGS  -DCMAKE_INSTALL_PREFIX=${LIBS_CGNS_DIR} -DCMAKE_PREFIX_PATH=${LIBS_HDF5_DIR} -DCGNS_ENABLE_FORTRAN=ON -DCGNS_ENABLE_64BIT=${LIBS_CGNS_64BIT} -DCGNS_BUILD_SHARED=ON -DCGNS_USE_SHARED=ON -DCMAKE_BUILD_TYPE=Release -DCGNS_BUILD_CGNSTOOLS=OFF -DCGNS_ENABLE_HDF5=${LIBS_BUILD_CGNS_ENABLE_HDF5} -DCGNS_ENABLE_PARALLEL=OFF -DCGNS_ENABLE_TESTS=OFF -DCMAKE_SKIP_RPATH=ON
        BUILD_BYPRODUCTS ${LIBS_CGNS_DIR}/lib/libcgns.a
      )
      # If HDF5 is built in HOPR, it must occur before the CGNS compilation (for the support of HDF5-based CGNS files)
      IF(LIBS_BUILD_HDF5)
        IF (NOT EXISTS "${LIBS_HDF5_DIR}/lib/libhdf5.a")
          ADD_DEPENDENCIES(cgns HDF5)
        ENDIF()
      ENDIF()
      LIST(APPEND SELFBUILTEXTERNALS cgns)
    ENDIF()

    LIST(INSERT linkedlibs 0 ${LIBS_CGNS_DIR}/lib/libcgns.a)
    INCLUDE_DIRECTORIES(   ${LIBS_CGNS_DIR}/include)

    MESSAGE(STATUS "Compiling with [CGNS] (${LIBS_BUILD_CGNS_TAG})")
  ENDIF()

  # set pre-processor flag for CGNS version
  ADD_DEFINITIONS(-DPP_CGNS_VERSION=${CGNS_VERSION})

ENDIF()
