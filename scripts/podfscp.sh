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
  printf "Usage: %s [-sv] [-p PODNAME]... FILE...\n" "$(basename "${0}")"
  cat <<"EOF"
             -p: PODNAME. May be specified multiple times.
             -s: Gather standard files of each pod as well.
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
GETSTANDARD=0

OPTIND=1
while getopts "hp:sv?" opt; do
  case "$opt" in
    h|\?)
      usage
      ;;
    p)
      PODNAMES="${PODNAMES} ${OPTARG}"
      ;;
    s)
      GETSTANDARD=1
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
  # Allow no files in case someone just wants to grab stdout/stderr
  # but let's print a warning just in case that was done in error
  
  #echo "ERROR: Missing FILEs"
  #usage
  printWarning "No files specified for ${PODNAMES}"
fi

printInfo "started with ${@} for ${PODNAMES}"

processPod() {
  PODNAME="${1}"
  [ "${VERBOSE}" -eq "1" ] && printVerbose "processPod ${PODNAME} with ${@}"
  shift
  CONTAINERFS="$(podinfo.sh -c -r "${PODNAME}")"

  OLDIFS="${IFS}"
  # Subshell strips newline so add a random character to the end (/) and then strip it
  IFS="$(printf '\n/')"
  IFS="${IFS%/}"

  for LINE in ${CONTAINERFS}; do
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

  FSPREFIX="pods/${PODNAME}/containers/${CONTAINER}"

  [ "${VERBOSE}" -eq "1" ] && printVerbose "processContainer PODNAME=${PODNAME} PODFS=${PODFS} CONTAINER=${CONTAINER}"

  printInfo "processing pod ${PODNAME}, container ${CONTAINER}"

  mkdir -p "${FSPREFIX}"

  for ARG in "${@}"; do
  
    [ "${VERBOSE}" -eq "1" ] && printVerbose "processContainer ARG=${ARG}"

    REALPATH="$(podfspath.sh "${PODFS}" "${ARG}")"

    [ "${VERBOSE}" -eq "1" ] && printVerbose "processContainer REALPATH=${REALPATH}"

    if [ "${REALPATH}" != "" ]; then
      cp -r ${REALPATH} "${FSPREFIX}/"
    else
      printVerbose "Path ${ARG} for pod ${PODNAME}, container ${CONTAINER} does not evaluate to a real path within ${PODFS}"
    fi
  done

  if [ "${GETSTANDARD}" -eq "1" ]; then
    PODSTDOUTERR="$(podinfo.sh -c -o "${PODNAME}")"
    if [ "${PODSTDOUTERR}" != "" ]; then

      [ "${VERBOSE}" -eq "1" ] && printVerbose "processContainer PODSTDOUTERR=${PODSTDOUTERR}"

      OLDIFS="${IFS}"
      # Subshell strips newline so add a random character to the end (/) and then strip it
      IFS="$(printf '\n/')"
      IFS="${IFS%/}"

      for LINE in ${PODSTDOUTERR}; do
        IFS="${OLDIFS}"
        processContainerStdouterr "${CONTAINER}" "${FSPREFIX}" ${LINE}
      done
    else
      printVerbose "stdout/stderr file for pod ${PODNAME}, container ${CONTAINER} is blank"
    fi

    # Next let's grab various cgroup info
    # /sys/fs/cgroup/cpuset/cpuset.memory_pressure
    # /sys/fs/cgroup/cpuset/cpuset.cpus /sys/fs/cgroup/cpuset/cpuset.effective_cpus
    PODPID="$(podinfo.sh -c -p "${PODNAME}")"
    if [ "${PODPID}" != "" ]; then

      [ "${VERBOSE}" -eq "1" ] && printVerbose "processContainer PODPID=${PODPID}"

      OLDIFS="${IFS}"
      # Subshell strips newline so add a random character to the end (/) and then strip it
      IFS="$(printf '\n/')"
      IFS="${IFS%/}"

      for LINE in ${PODPID}; do
        IFS="${OLDIFS}"
        processContainerExtras "${CONTAINER}" "${FSPREFIX}" ${LINE}
      done
    else
      printVerbose "PID for pod ${PODNAME}, container ${CONTAINER} is blank"
    fi
  fi
}

processContainerStdouterr() {
  CONTAINER="${1}"
  shift
  FSPREFIX="${1}"
  shift
  PODSTDOUTERR="${1}"
  shift
  SOURCECONTAINER="${1}"
  shift

  if [ "${CONTAINER}" = "${SOURCECONTAINER}" ]; then
    [ "${VERBOSE}" -eq "1" ] && printVerbose "processContainerStdouterr processing source container ${SOURCECONTAINER} to ${FSPREFIX}"
    cp "/host/${PODSTDOUTERR}" "${FSPREFIX}/stdouterr.log"
  fi
}

processContainerExtras() {
  CONTAINER="${1}"
  shift
  FSPREFIX="${1}"
  shift
  PODPID="${1}"
  shift
  SOURCECONTAINER="${1}"
  shift

  if [ "${CONTAINER}" = "${SOURCECONTAINER}" ]; then
    [ "${VERBOSE}" -eq "1" ] && printVerbose "processContainerExtras processing source container ${SOURCECONTAINER} to ${FSPREFIX}"
    mkdir -p "${FSPREFIX}/cgroup/cpuset"
    echo "${PODPID}" > "${FSPREFIX}/pid.txt"
    cp "/host/proc/${PODPID}/cgroup" "${FSPREFIX}/cgroup/"

    # Grab the actual cgroup name
    CGROUP="$(cat "/host/proc/${PODPID}/cgroup" | awk -F: 'NR==1 {print $3;}')"
    if [ "${CGROUP}" != "" ]; then
      ERROUTPUT="/dev/null"
      if [ "${VERBOSE}" -eq "1" ]; then
        printVerbose "processContainerExtras CGROUP=${CGROUP}"
        ERROUTPUT="cmderr.txt"
      fi
      cp -r /host/sys/fs/cgroup/cpu/${CGROUP} "${FSPREFIX}/cgroup/cpu/" 2>>${ERROUTPUT}
      cp -r /host/sys/fs/cgroup/memory/${CGROUP} "${FSPREFIX}/cgroup/memory/" 2>>${ERROUTPUT}
      cp /host/sys/fs/cgroup/cpuset/cpuset.cpus /host/sys/fs/cgroup/cpuset/cpuset.effective_cpus "${FSPREFIX}/cgroup/cpuset/" 2>>${ERROUTPUT}
      
      # This is just a convenience after download
      chmod -R a+w "${FSPREFIX}/cgroup" 2>>${ERROUTPUT}
    else
      printVerbose "processContainerExtras Could not evaluate /host/proc/${PODPID}/cgroup ${CGROUP}"
    fi
  fi
}

for PODNAME in ${PODNAMES}; do
  processPod "${PODNAME}" "${@}"
done

printVerbose "script returning"
