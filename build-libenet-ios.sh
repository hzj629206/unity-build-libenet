#!/bin/bash
set -u

TOOLS_PATH="$(dirname $0)"
TOOLS_PATH="$(cur=$(pwd); cd $TOOLS_PATH; pwd -P; cd $cur)"
BUILD_PATH="$(dirname $TOOLS_PATH)/Build"
PROJECT_PATH="$(dirname $TOOLS_PATH)/Source"

# Setup architectures, library name and other vars + cleanup from previous runs
ARCHS=("armv7" "armv7s" "i386" "arm64" "x86_64")
SDKS=("iphoneos" "iphoneos" "macosx" "iphoneos" "macosx")
LIB_NAME="enet-1.3.13"

TEMP_DIR="$BUILD_PATH/tmp"
TEMP_LIB_PATH="$BUILD_PATH/tmp/${LIB_NAME}"

# !!! User configuration required: point this at the directory the openssl headers and libs are to be found
DEPENDENCIES_DIR="$BUILD_PATH"
DEPENDENCIES_DIR_LIB="${DEPENDENCIES_DIR}/lib"
DEPENDENCIES_DIR_HEAD="${DEPENDENCIES_DIR}/include"

PLATFORM_DEPENDENCIES_DIR="${DEPENDENCIES_DIR}/platform"

LIB_DEST_DIR="$BUILD_PATH/libenet-dest-lib"
HEADER_DEST_DIR="$BUILD_PATH/libenet-dest-include"

PLATFORM_LIBS=() # Platform specific lib files to be copied for the build
PLATFORM_HEADERS=() # Platform specific header files to be copied for the build

rm -rf "${TEMP_LIB_PATH}*" "${LIB_NAME}"

###########################################################################
# Unarchive library, then configure and make for specified architectures

# Copy platform dependency libs and headers
copy_platform_dependencies()
{
   ARCH=$1; SDK_PATH=$2;

   PLATFORM_DEPENDENCIES_DIR_H="${PLATFORM_DEPENDENCIES_DIR}/${ARCH}/include"
   PLATFORM_DEPENDENCIES_DIR_LIB="${PLATFORM_DEPENDENCIES_DIR}/${ARCH}/lib"
   mkdir -p "${PLATFORM_DEPENDENCIES_DIR_H}"
   mkdir -p "${PLATFORM_DEPENDENCIES_DIR_LIB}"

   for PLIB in "${PLATFORM_LIBS[@]}"; do
	  cp "${SDK_PATH}/usr/lib/$PLIB" "${PLATFORM_DEPENDENCIES_DIR_LIB}"
   done

   for PHEAD in "${PLATFORM_HEADERS[@]}"; do
	  cp "${SDK_PATH}/usr/include/$PHEAD" "${PLATFORM_DEPENDENCIES_DIR_H}"
   done
}

# Unarchive, setup temp folder and run ./configure, 'make' and 'make install'
configure_make()
{
   ARCH=$1; GCC=$2; SDK_PATH=$3;
   LOG_FILE="${TEMP_LIB_PATH}-${ARCH}.log"
   tar xfz "${LIB_NAME}.tar.gz";

   pushd .; cd "${LIB_NAME}";

   [ ${#PLATFORM_LIBS[@]} -gt 0 ] && copy_platform_dependencies "${ARCH}" "${SDK_PATH}"

   # Configure and make

   if [ "${ARCH}" == "i386" ] || [ "${ARCH}" == "x86_64" ]; then
	  HOST_FLAG=""
	  MIN_FLAG="-mmacosx-version-min=10.10"
	  EXTRA_FLAG=""
   else
	  HOST_FLAG="--host=arm-apple-darwin"
	  MIN_FLAG="-mios-version-min=8.0"
	  EXTRA_FLAG="-fembed-bitcode"
   fi

   mkdir -p "${TEMP_LIB_PATH}-${ARCH}"

   ./configure --disable-shared --enable-static ${HOST_FLAG} \
   --prefix="${TEMP_LIB_PATH}-${ARCH}" \
   CC="${GCC} " \
   LDFLAGS="-L${DEPENDENCIES_DIR_LIB}" \
   CFLAGS=" -arch ${ARCH} ${MIN_FLAG} ${EXTRA_FLAG} -isysroot ${SDK_PATH} -I${DEPENDENCIES_DIR_HEAD}" \
   CPPLAGS=" -arch ${ARCH} ${MIN_FLAG} ${EXTRA_FLAG} -isysroot ${SDK_PATH} -I${DEPENDENCIES_DIR_HEAD} " &> "${LOG_FILE}"

   make -j2 &> "${LOG_FILE}"; make install &> "${LOG_FILE}";

   popd; rm -rf "${LIB_NAME}";
}
for ((i=0; i < ${#ARCHS[@]}; i++));
do
   SDK_PATH=$(xcrun -sdk ${SDKS[i]} --show-sdk-path)
   GCC=$(xcrun -sdk ${SDKS[i]} -find gcc)
   configure_make "${ARCHS[i]}" "${GCC}" "${SDK_PATH}"
done

# Combine libraries for different architectures into one
# Use .a files from the temp directory by providing relative paths
mkdir -p "${LIB_DEST_DIR}"
create_lib()
{
   LIB_SRC=$1; LIB_DST=$2;
   LIB_PATHS=( "${ARCHS[@]/#/${TEMP_LIB_PATH}-}" )
   LIB_PATHS=( "${LIB_PATHS[@]/%//${LIB_SRC}}" )
   lipo ${LIB_PATHS[@]} -create -output "${LIB_DST}"
}
LIBS=("libenet.a")
for DEST_LIB in "${LIBS[@]}";
do
   create_lib "lib/${DEST_LIB}" "${LIB_DEST_DIR}/${DEST_LIB}"
done

# Copy header files + final cleanups
mkdir -p "${HEADER_DEST_DIR}"
cp -R "${TEMP_LIB_PATH}-${ARCHS[0]}/include" "${HEADER_DEST_DIR}"
rm -rf "${TEMP_DIR}"

PROJECT_LIBS=("libenetlibios.a")
for ((i=0; i < ${#LIBS[@]}; i++));
do
	cp "${LIB_DEST_DIR}/${LIBS[i]}" "${PROJECT_PATH}/Assets/Plugins/iOS/${PROJECT_LIBS[i]}"
done
