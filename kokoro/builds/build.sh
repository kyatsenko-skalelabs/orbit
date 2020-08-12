#!/bin/bash -x
#
# Copyright (c) 2020 The Orbit Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

# Fail on any error.
set -e

if [ -z "$CONAN_PROFILE" ]; then
  readonly CONAN_PROFILE="$(basename $(dirname "$KOKORO_JOB_NAME"))"
fi

source $(cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd)/upload_symbols.sh

if [ -n "$1" ]; then
  # We are inside the docker container

  readonly REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../../" >/dev/null 2>&1 && pwd )"

  if [ -z "$BUILD_TYPE" ]; then
    readonly BUILD_TYPE="$(basename "$KOKORO_JOB_NAME")"
  fi

  set +e
  if [ "$BUILD_TYPE" = "release" ] \
     && ! git -C "${REPO_ROOT}" describe --tags --exact-match > /dev/null; then
    echo -n "We are currently conducting a release build, but we aren't on a tag."
    echo    " Aborting the build..."
    echo -n "Maybe you missed pushing the release version tag?"
    echo    "Please consult the release playbook for advice."
    #exit 1
  fi
  set -e

  pip3 install conan==1.27.1 conan-package-tools==0.34.0

  echo "Installing conan configuration (profiles, settings, etc.)..."
  ${REPO_ROOT}/third_party/conan/configs/install.sh



  if [ "$(uname -s)" == "Linux" ]; then
    readonly OS="linux"
  else
    readonly OS="windows"
  fi

  if [[ $CONAN_PROFILE == ggp_* ]]; then
    readonly PACKAGING_OPTION="-o debian_packaging=True"
  else
    readonly PACKAGING_OPTION=""
  fi

  CRASHDUMP_SERVER=""

  # Building Orbit
  mkdir -p "${REPO_ROOT}/build/"
  cp -v "${REPO_ROOT}/third_party/conan/lockfiles/${OS}/${CONAN_PROFILE}/conan.lock" \
        "${REPO_ROOT}/build/conan.lock"
  sed -i -e "s|crashdump_server=|crashdump_server=$CRASHDUMP_SERVER|" \
            "${REPO_ROOT}/build/conan.lock"
  conan install -u -pr ${CONAN_PROFILE} -if "${REPO_ROOT}/build/" \
          --build outdated \
          -o crashdump_server="$CRASHDUMP_SERVER" \
          $PACKAGING_OPTION \
          --lockfile="${REPO_ROOT}/build/conan.lock" \
          "${REPO_ROOT}"
  conan build -bf "${REPO_ROOT}/build/" "${REPO_ROOT}"
  conan package -bf "${REPO_ROOT}/build/" "${REPO_ROOT}"

  if [ "${BUILD_TYPE}" == "release" ] \
     || [ "${BUILD_TYPE}" == "nightly" ] \
     || [ "${BUILD_TYPE}" == "continuous_on_release_branch" ]; then
    set +e
    upload_debug_symbols "${CRASH_SYMBOL_COLLECTOR_API_KEY}" "${REPO_ROOT}/build/bin"
    set -e
  fi

  exit $?
fi

# We can't access the Keys-API inside of a docker container. So we retrieve
# the key before entering the containers and transport it via environment variable.
install_oauth2l
set_api_key
remove_oauth2l

# This only executes when NOT in docker:
if [ "$(uname -s)" == "Linux" ]; then
  gcloud auth configure-docker --quiet
  docker run --rm -v ${KOKORO_ARTIFACTS_DIR}:/mnt \
    -e KOKORO_JOB_NAME -e CONAN_PROFILE -e BUILD_TYPE \
    -e CRASH_SYMBOL_COLLECTOR_API_KEY \
    gcr.io/orbitprofiler/${CONAN_PROFILE}:latest \
    /mnt/github/orbitprofiler/kokoro/builds/build.sh in_docker
else
  gcloud.cmd auth configure-docker --quiet
  docker run --rm -v ${KOKORO_ARTIFACTS_DIR}:C:/mnt \
    -e KOKORO_JOB_NAME -e CONAN_PROFILE -e BUILD_TYPE \
    -e CRASH_SYMBOL_COLLECTOR_API_KEY \
    --isolation=process --storage-opt 'size=50GB' \
    gcr.io/orbitprofiler/${CONAN_PROFILE}:latest \
    'C:/Program Files/Git/bin/bash.exe' -c \
    "/c/mnt/github/orbitprofiler/kokoro/builds/build.sh in_docker"
fi
