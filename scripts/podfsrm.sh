#!/bin/sh
# /*******************************************************************************
#  * (c) Copyright IBM Corporation 2022.
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

usage() {
  printf "Usage: %s [-v] [-p PODNAME]... FILE...\n" "$(basename "${0}")"
  cat <<"EOF"
             -p: PODNAME. May be specified multiple times.
             -v: verbose output to stderr
EOF
  exit 2
}

printVerbose() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S.%N %Z')] $(basename "${0}"): ${@}" >> /dev/stderr
}

printInfo() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S.%N %Z')] $(basename "${0}"): ${@}"
}

printError() {
  printInfo "Error: " "${@}"
}

printWarning() {
  printInfo "Warning: " "${@}"
}

PODNAMES=""
VERBOSE=0

OPTIND=1
while getopts "hp:v?" opt; do
  case "$opt" in
    h|\?)
      usage
      ;;
    p)
      PODNAMES="${PODNAMES} ${OPTARG}"
      ;;
    v)
      VERBOSE=1
      ;;
  esac
done

shift $((OPTIND-1))

if [ "${1:-}" = "--" ]; then
  shift
fi

if [ "${PODNAMES}" = "" ]; then
  echo "ERROR: Missing -p PODNAME"
  usage
fi

if [ "${#}" -eq 0 ]; then
  echo "ERROR: Missing FILEs"
  usage
fi

printInfo "started with ${@} for ${PODNAMES}"

processPod() {
  PODNAME="${1}"
  shift

  [ "${VERBOSE}" -eq "1" ] && printVerbose "processPod ${PODNAME} with ${@}"

  PODFS="$(podinfo.sh -c -r "${PODNAME}")"
  [ "${VERBOSE}" -eq "1" ] && printVerbose "processPod PODFS=${PODFS}"

  OLDIFS="${IFS}"
  # Subshell strips newline so add a random character to the end (/) and then strip it
  IFS="$(printf '\n/')"
  IFS="${IFS%/}"

  for LINE in ${PODFS}; do
    IFS="${OLDIFS}"
    processContainer ${PODNAME} ${LINE} "${@}"
  done
}

processContainer() {
  PODNAME="${1}"
  shift
  PODFS="${1}"
  shift
  CONTAINER="${1}"
  shift

  printInfo "processing pod ${PODNAME}, container ${CONTAINER}"

  [ "${VERBOSE}" -eq "1" ] && printVerbose "processContainer PODNAME=${PODNAME} PODFS=${PODFS} CONTAINER=${CONTAINER}"

  for ARG in "${@}"; do
    [ "${VERBOSE}" -eq "1" ] && printVerbose "processContainer ARG=${ARG}"

    REALPATH="$(podfspath.sh "${PODFS}" "${ARG}")"

    [ "${VERBOSE}" -eq "1" ] && printVerbose "processContainer REALPATH=${REALPATH}"

    if [ "${REALPATH}" != "" ]; then
      printVerbose "Removing ${REALPATH} for pod ${PODNAME}"
      rm -r ${REALPATH}
    else
      printVerbose "Path ${ARG} for pod ${PODNAME}, container ${CONTAINER} does not evaluate to a real path within ${PODFS}"
    fi
  done
}

for PODNAME in ${PODNAMES}; do
  processPod "${PODNAME}" "${@}"
done

printInfo "script returning"
