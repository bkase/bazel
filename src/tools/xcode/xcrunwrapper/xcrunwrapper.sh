#!/bin/bash
#
# Copyright 2015 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# xcrunwrapper runs the command passed to it using xcrun. The first arg
# passed is the name of the tool to be invoked via xcrun. (For example, libtool
# or clang).
# xcrunwrapper replaces __BAZEL_XCODE_DEVELOPER_DIR__ with $DEVELOPER_DIR (or
# reasonable default) and __BAZEL_XCODE_SDKROOT__ with a valid path based on
# SDKROOT (or reasonable default).
# These values (__BAZEL_XCODE_*) are a shared secret withIosSdkCommands.java.

set -eu

TOOLNAME=$1
shift

# Pick values for DEVELOPER_DIR and SDKROOT as appropriate (if they weren't set)
WRAPPER_DEVDIR="${DEVELOPER_DIR:-}"
if [[ -z "${WRAPPER_DEVDIR}" ]] ; then
  WRAPPER_DEVDIR="$(xcode-select -p)"
fi

# TODO(blaze-team): Remove this once all build environments are setting SDKROOT
# for us.
WRAPPER_SDKROOT="${SDKROOT:-}"
if [[ -z "${WRAPPER_SDKROOT:-}" ]] ; then
  WRAPPER_SDK=iphonesimulator
  for ARG in "$@" ; do
    case "${ARG}" in
      armv6|armv7|armv7s|arm64)
        WRAPPER_SDK=iphoneos
        ;;
      i386|x86_64)
        WRAPPER_SDK=iphonesimulator
        ;;
    esac
  done
  WRAPPER_SDKROOT="$(/usr/bin/xcrun --show-sdk-path --sdk ${WRAPPER_SDK})"
fi

# Subsitute toolkit path placeholders.
UPDATEDARGS=()
SPLITARGS=()
USE_CLANG39=""
for ARG in "$@" ; do
  # Split args that bazel doesn't want us to duplicate :/
  if [[ $ARG == *"__PIN_SPLIT__"* ]]; then
    SPLITARGS+=("$(echo ${ARG} | awk -F__PIN_SPLIT__ '{ print $1 }')")
    SPLITARGS+=("$(echo ${ARG} | awk -F__PIN_SPLIT__ '{ print $2 }')")
  else
    SPLITARGS+=("${ARG}")
  fi
done

for ARG in "${SPLITARGS[@]}" ; do
  if [[ $ARG == "__USE_CLANG39__" ]]; then
    USE_CLANG39=1
    continue
  fi
  ARG="${ARG//__BAZEL_XCODE_DEVELOPER_DIR__/${WRAPPER_DEVDIR}}"
  ARG="${ARG//__BAZEL_XCODE_SDKROOT__/${WRAPPER_SDKROOT}}"
  # Find args that bazel doesn't let us point to
  if [[ $ARG == *"__PIN_FIND__"* ]]; then
    # 1. First we strip the find prefix
    ARG="${ARG//__PIN_FIND__/}"
    # 2. Then we resolve symlinks to a fixpoint
    # Replacement for readlink -f on OSX
    # see http://stackoverflow.com/questions/7665/how-to-resolve-symbolic-links-in-a-shell-script
    ARG="$(perl -MCwd -le 'print Cwd::abs_path(shift)' "$(find . -name "$ARG" | head -1)")"
    # 3. We can't MMAP on N processes concurrently for N > 1
    #    so atomically copy this file to potentially MMAP the copy
    cp "$ARG" $(basename "$ARG")
    ARG=$(basename "$ARG")
  fi
  UPDATEDARGS+=("${ARG}")
done

if [[ ! -z $USE_CLANG39 ]]; then
  TOOL=$(find . -name "__PIN__${TOOLNAME}.h" | head -1)
  exec ${TOOL} "${UPDATEDARGS[@]}"
else
  /usr/bin/xcrun "${TOOLNAME}" "${UPDATEDARGS[@]}"
fi
