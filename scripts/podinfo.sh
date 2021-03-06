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
  printf "Usage: %s [-joprv] PODNAME...\n" "$(basename "${0}")"
  cat <<"EOF"
             -c: Show the container name for each POD PID; separate PID info by newlines
             -j: Find Java child PIDs.
             -o: Print space-delimited list of stdout/stderr file paths matching PODNAME(s)
             -p: Default. Print space-delimited list of PIDs matching PODNAME(s)
             -r: Print space-delimited list of root filesystem paths matching PODNAME(s)
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

# Note: use unshare instead of chroot because of https://github.com/opencontainers/runc/issues/3462#issuecomment-1155422205
RUNC="unshare -rR /host runc"
DEBUG=0
VERBOSE=0
OUTPUTTYPE=0
FINDJAVA=0
SHOWCONTAINER=0

OPTIND=1
while getopts "cdhjnoprv?" opt; do
  case "$opt" in
    c)
      SHOWCONTAINER=1
      ;;
    d)
      DEBUG=1
      ;;
    h|\?)
      usage
      ;;
    j)
      FINDJAVA=1
      ;;
    n)
      RUNC="runc"
      ;;
    o)
      OUTPUTTYPE=2
      ;;
    p)
      OUTPUTTYPE=0
      ;;
    r)
      OUTPUTTYPE=1
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

if [ "${#}" -eq 0 ]; then
  echo "ERROR: Missing pod name(s)"
  usage
fi

[ "${VERBOSE}" -eq "1" ] && printVerbose "started with ${@}"

[ "${VERBOSE}" -eq "1" ] && printVerbose "${RUNC} list"

if [ "${DEBUG}" -eq "0" ]; then
  RUNCLIST="$(${RUNC} list)"
else
  RUNCLIST="$(cat debug/example_runclist.txt)"
fi

[ "${VERBOSE}" -eq "1" ] && printVerbose "${RUNCLIST}"
FOUND=0
for ID in $(echo "${RUNCLIST}" | awk 'NF > 3 && $3 != "stopped" && $3 != "STATUS" {print $1}' -); do
  [ "${VERBOSE}" -eq "1" ] && printVerbose "${RUNC} state ${ID}"
  
  if [ "${DEBUG}" -eq "0" ]; then
    RUNCSTATE="$(${RUNC} state ${ID})"
  else
    RUNCSTATE="$(cat debug/example_runcstate.txt)"
  fi

  [ "${VERBOSE}" -eq "1" ] && printVerbose "runc state: ${RUNCSTATE}"

  RUNCSTATEROWS="$(echo "${RUNCSTATE}" | jq -r '.pid, .annotations."io.kubernetes.container.name", .annotations."io.kubernetes.pod.name", .rootfs, .annotations."io.kubernetes.cri-o.LogPath"')"
  PID="$(echo "${RUNCSTATEROWS}" | awk 'NR==1')"
  CONTAINERNAME="$(echo "${RUNCSTATEROWS}" | awk 'NR==2')"
  PODNAME="$(echo "${RUNCSTATEROWS}" | awk 'NR==3')"
  ROOTFS="$(echo "${RUNCSTATEROWS}" | awk 'NR==4')"
  STDOUTERR="$(echo "${RUNCSTATEROWS}" | awk 'NR==5')"

  [ "${VERBOSE}" -eq "1" ] && printVerbose "pid: ${PID}, container: ${CONTAINERNAME}, pod: ${PODNAME}, rootfs: ${ROOTFS}, stdouterr: ${STDOUTERR}"

  for SEARCH in "${@}"; do
    if [ "${SEARCH}" = "${PODNAME}" ]; then
      if [ "${FOUND}" -gt 0 ] && [ "${SHOWCONTAINER}" -eq 0 ]; then
        printf " "
      fi
      PIDFOUND=1
      if [ "${OUTPUTTYPE}" -eq "0" ]; then
        if [ "${FINDJAVA}" -eq "0" ]; then
          printf "%s" "${PID}"
        else
          # This is the -j option so only look for Java PIDs
          # Example pstree output:
          #   java(14717)
          # So replace ( and ) with a space and then take the last column for the PID
          # By default, pstree shows threads, to use -T to just show PIDs
          printf "%s" "$(pstree -pT ${PID} | awk '/java/ && !/logViewer/ {gsub(/[()]/, " "); print $NF;}' | tr '\n' ' ')"
        fi
      elif [ "${OUTPUTTYPE}" -eq "1" ]; then
        printf "%s" "${ROOTFS}"
      elif [ "${OUTPUTTYPE}" -eq "2" ]; then
        printf "%s" "${STDOUTERR}"
      else
        PIDFOUND=0
      fi
      if [ "${SHOWCONTAINER}" -eq 1 ] && [ "${PIDFOUND}" -eq "1" ]; then
        printf " %s\n" "${CONTAINERNAME}"
      fi
      FOUND="$(((${FOUND}+1)))"
    fi
  done
done

if [ "${FOUND}" -gt 0 ]; then
  printf "\n"
fi

[ "${VERBOSE}" -eq "1" ] && printVerbose "script returning"
