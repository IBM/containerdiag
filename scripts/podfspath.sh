#!/bin/sh
# /*******************************************************************************
#  * (c) Copyright IBM Corporation 2023.
#  *
#  * Licensed under the Apache License, Version 2.0 (the "License");
#  * you may not use this file except in compliance with the License.
#  * You may obtain a copy of the License at
#  *
#  *    https://www.apache.org/licenses/LICENSE-2.0
#  *
#  * Unless required by applicable law or agreed to in writing, software
#  * distributed under the License is distributed on an "AS IS" BASIS,
#  * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  * See the License for the specific language governing permissions and
#  * limitations under the License.
#  *******************************************************************************/

# usage: podfspath.sh ROOTFS PATH
# We need to get the absolute path because symlinks won't work as it assumes
# a chroot, and we can't chroot, because then we can't do anything with the files like
# copy them out. In addition, dirname doesn't work if there isn't an actual filename,
# so check if it's a dir.

VERBOSE=0

printVerbose() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S.%N %Z')] $(basename "${0}"): ${@}" >> /dev/stderr
}

printInfo() {
  # We always print to stderr because the whole purpose of this script
  # is to return something in stdout so we can't pollute that.
  printVerbose "${@}"
}

printError() {
  # We always print to stderr because the whole purpose of this script
  # is to return something in stdout so we can't pollute that.
  printVerbose "Error: " "${@}"
}

printWarning() {
  # We always print to stderr because the whole purpose of this script
  # is to return something in stdout so we can't pollute that.
  printVerbose "Warning: " "${@}"
}

OPTIND=1
while getopts "v" opt; do
  case "$opt" in
    v)
      VERBOSE=1
      ;;
  esac
done

shift $((OPTIND-1))

if [ "${1:-}" = "--" ]; then
  shift
fi

[ "${VERBOSE}" -eq "1" ] && printVerbose "Incoming arguments: ${@}"

# TODO https://github.com/opencontainers/runc/issues/3462#issuecomment-1155422205
REALPATH="$(chroot "/host/${1}/" sh -c "if [ -d \"${2}\" ]; then cd \"${2}\"; else cd \$(dirname \"${2}\"); fi && pwd -P" 2>/dev/null)"

if [ "${?}" -eq "0" ]; then
  if [ "${VERBOSE}" -eq "1" ]; then
    printVerbose "REALPATH: ${REALPATH}"
  fi

  if [ "${REALPATH}" != "" ]; then
    # First condition: Same as when getting the REALPATH above
    # Second condition: Outside the chroot, -d won't be able to resolve directory symlinks, so check explicitly
    # Third condition: Outside the chroot, a trailing slash won't be able to resolve the directory, so assume it's one
    if [ -d "/host/${1}/${2}" ] || [ -L "/host/${1}/${2}" ] || [ "${2%/}" != "${2}" ]; then
      echo "/host/${1}/${REALPATH}/"
    else
      echo "/host/${1}/${REALPATH}/$(basename "${2}")"
    fi
  fi
else
  [ "${VERBOSE}" -eq "1" ] && printVerbose "Command failed"
fi
