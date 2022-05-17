#!/bin/sh
# /*******************************************************************************
#  * (c) Copyright IBM Corporation 2022.
#  *
#  * Licensed under the Apache License, Version 2.0 (the "License");
#  * you may not use this file except in compliance with the License.
#  * You may obtain a copy of the License at
#  *
#  *    http://www.apache.org/licenses/LICENSE-2.0
#  *
#  * Unless required by applicable law or agreed to in writing, software
#  * distributed under the License is distributed on an "AS IS" BASIS,
#  * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  * See the License for the specific language governing permissions and
#  * limitations under the License.
#  *******************************************************************************/

usage() {
  printf "Usage: %s [-v] [-p PODNAME]...\n" "$(basename "${0}")"
  cat <<"EOF"
             -p: PODNAME. May be specified multiple times.
             -v: verbose output to stderr
EOF
  exit 2
}

printVerbose() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S.%N %Z')] $(basename "${0}"): ${@}" >> /dev/stderr
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
  echo "ERROR: Missing -p PODNAME" >>/dev/stderr
  usage
fi

FOUND=0

[ "${VERBOSE}" -eq "1" ] && printVerbose "started with ${PODNAMES}"

processPod() {
  PODNAME="${1}"
  [ "${VERBOSE}" -eq "1" ] && printVerbose "processPod ${PODNAME}"
  PODPID="$(podinfo.sh -p "${PODNAME}")"
  [ "${VERBOSE}" -eq "1" ] && printVerbose "processPod PODPID=${PODPID}"
  PODFS="$(podinfo.sh -r "${PODNAME}")"
  [ "${VERBOSE}" -eq "1" ] && printVerbose "processPod PODFS=${PODFS}"

  if [ -e /proc/${PODPID} ]; then
    # Check if this is Liberty and get the server name
    if grep -q ws-server.jar /proc/${PODPID}/cmdline ; then
      LIBERTYSERVER="$(cat /proc/${PODPID}/cmdline | tr '\0' ' ' | awk '{print $NF;}')"
      [ "${VERBOSE}" -eq "1" ] && printVerbose "processPod LIBERTYSERVER=${LIBERTYSERVER}"

      PODEXE="$(ls -l /proc/${PODPID} | awk '/ exe -/ { print $NF; }')"
      [ "${VERBOSE}" -eq "1" ] && printVerbose "processPod PODEXE=${PODEXE}"

      # Use a sub-shell so that we don't pollute the current envars
      (
        cat /proc/${PODPID}/environ | tr '\0' '\n' > /tmp/envars.txt
        while read LINE; do
          [ "${VERBOSE}" -eq "1" ] && printVerbose "processPod envar: ${LINE}"

          case "${LINE}" in
            WLP_USER_DIR*)
              VAL="$(echo "${LINE}" | sed 's/.*=//g')"
              LIBERTYROOT="$(dirname "${VAL}")"
              export WLP_USER_DIR="${VAL}"
              ;;
            WLP_OUTPUT_DIR*)
              VAL="$(echo "${LINE}" | sed 's/.*=//g')"
              export WLP_OUTPUT_DIR="${VAL}"
              ;;
          esac
        done </tmp/envars.txt
        
        [ "${VERBOSE}" -eq "1" ] && printVerbose "processPod WLP_USER_DIR=${WLP_USER_DIR}"
        [ "${VERBOSE}" -eq "1" ] && printVerbose "processPod WLP_OUTPUT_DIR=${WLP_OUTPUT_DIR}"

        OUTPUT="$(nsenter -a --follow-context --setuid $(stat -c "%u" /proc/${PODPID}/) --target ${PODPID} "${PODEXE}" -jar "${LIBERTYROOT}/bin/tools/ws-server.jar" "${LIBERTYSERVER}" --dump)"
        [ "${VERBOSE}" -eq "1" ] && printVerbose "processPod server dump output: ${OUTPUT}"
        DUMP="$(echo ${OUTPUT} | awk '/dump complete in/ { gsub(/\.$/, "", $NF); print $NF; }')"
        [ "${VERBOSE}" -eq "1" ] && printVerbose "processPod DUMP=${DUMP}"
        if [ "${DUMP}" != "" ]; then
          FOUND="$(((${FOUND}+1)))"
          if [ "${FOUND}" -gt 0 ]; then
            printf " "
          fi
          printf "%s" "${DUMP}"
        fi
      )
    fi
  else
    echo "ERROR: Could not find proc inforrmation for pod ${PODNAME} PID ${PODPID}" >>/dev/stderr
  fi
}

for PODNAME in ${PODNAMES}; do
  processPod "${PODNAME}" "${@}"
done

if [ "${FOUND}" -gt 0 ]; then
  printf "\n"
fi

[ "${VERBOSE}" -eq "1" ] && printVerbose "finished"
