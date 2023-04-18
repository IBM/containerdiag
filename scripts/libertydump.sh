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

printInfo "started with ${PODNAMES}"

processPod() {
  PODNAME="${1}"
  [ "${VERBOSE}" -eq "1" ] && printVerbose "processPod ${PODNAME}"
  PODPID="$(podinfo.sh -c -p "${PODNAME}")"
  [ "${VERBOSE}" -eq "1" ] && printVerbose "processPod PODPID=${PODPID}"

  OLDIFS="${IFS}"
  # Subshell strips newline so add a random character to the end (/) and then strip it
  IFS="$(printf '\n/')"
  IFS="${IFS%/}"

  for LINE in ${PODPID}; do
    IFS="${OLDIFS}"
    processContainer ${PODNAME} ${LINE} "${@}"
  done
}

processContainer() {
  PODNAME="${1}"
  shift
  PODPID="${1}"
  shift
  CONTAINER="${1}"
  shift

  printInfo "processing pod ${PODNAME}, container ${CONTAINER}, PID ${PODPID}"

  [ "${VERBOSE}" -eq "1" ] && printVerbose "processContainer PODNAME=${PODNAME} PODPID=${PODPID} CONTAINER=${CONTAINER}"

  if [ -e "/proc/${PODPID}" ]; then
    # Check if this is Liberty and get the server name
    if grep -q ws-server.jar "/proc/${PODPID}/cmdline" ; then
      LIBERTYSERVER="$(cat /proc/${PODPID}/cmdline | tr '\0' ' ' | awk '{print $NF;}')"
      [ "${VERBOSE}" -eq "1" ] && printVerbose "processContainer LIBERTYSERVER=${LIBERTYSERVER}"

      PODEXE="$(cat /proc/${PODPID}/cmdline | tr '\0' '\n' | awk 'NR==1')"
      [ "${VERBOSE}" -eq "1" ] && printVerbose "processContainer PODEXE=${PODEXE}"

      if [ "${PODEXE}" != "" ]; then
        cat "/proc/${PODPID}/environ" | tr '\0' '\n' > /tmp/envars.txt
        while read LINE; do
          [ "${VERBOSE}" -eq "1" ] && printVerbose "processContainer envar: ${LINE}"

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
        
        [ "${VERBOSE}" -eq "1" ] && printVerbose "processContainer WLP_USER_DIR=${WLP_USER_DIR}"
        [ "${VERBOSE}" -eq "1" ] && printVerbose "processContainer WLP_OUTPUT_DIR=${WLP_OUTPUT_DIR}"

        POD_PID_OWNER="$(stat -c "%u" /proc/${PODPID}/)"
        if [ "${POD_PID_OWNER}" != "" ]; then

          [ "${VERBOSE}" -eq "1" ] && printVerbose "processContainer pod PID owner: ${POD_PID_OWNER}"

          OUTPUT="$(nsenter -a --follow-context --setuid ${POD_PID_OWNER} --target ${PODPID} "${PODEXE}" -jar "${LIBERTYROOT}/bin/tools/ws-server.jar" "${LIBERTYSERVER}" --dump)"
          RC="${?}"
          [ "${VERBOSE}" -eq "1" ] && printVerbose "processContainer server dump output with RC ${RC}: ${OUTPUT}"

          DUMP="$(echo ${OUTPUT} | awk '/dump complete in/ { gsub(/\.$/, "", $NF); print $NF; }')"
          [ "${VERBOSE}" -eq "1" ] && printVerbose "processContainer DUMP=${DUMP}"

          if [ "${DUMP}" != "" ]; then
            printInfo "succeeded for ${PODNAME} with dump in ${DUMP}"

            FOUND="$(((${FOUND}+1)))"
            if [ "${FOUND}" -gt 0 ]; then
              printf " "
            fi
            printf "%s" "${DUMP}"
          fi
        else
          printWarning "Could not stat the owner ID of PID ${PODPID}"
        fi
      else
        printError "Could not explore /proc/${PODPID}"
      fi
    fi
  else
    printError "Could not find proc information for pod ${PODNAME} PID ${PODPID}"
  fi
}

for PODNAME in ${PODNAMES}; do
  processPod "${PODNAME}" "${@}"
done

if [ "${FOUND}" -gt 0 ]; then
  printf "\n"
fi

printInfo "script returning"
