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

usage() {
  printf "Usage: %s [-jnoprv] [-f PATH] [PODNAME...]\n" "$(basename "${0}")"
  cat <<"EOF"
             -c: Show the container name for each POD PID; separate PID info by newlines
             -f: Search for a pod by the existence of PATH in the container.
             -j: Find Java child PIDs.
             -n: Show the pod name and namespace for each POD PID; separate PID info by newlines
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

DEBUG=0
VERBOSE=0
PASSVERBOSE=""
OUTPUTTYPE=0
FINDJAVA=0
SHOWCONTAINER=0
SHOWPOD=0
FINDPATH=""

CONTAINER_RUNTIME_RUNC=1
CONTAINER_RUNTIME_CONTAINERD=2

# TODO https://github.com/opencontainers/runc/issues/3462#issuecomment-1155422205
CMD_RUNC="chroot /host runc"
CMD_CONTAINERD="chroot /host ctr --namespace k8s.io containers"
CMD_CONTAINERD2="chroot /host runc --root /run/containerd/runc/k8s.io"

OPTIND=1
while getopts "cdf:hjnoprv?" opt; do
  case "$opt" in
    c)
      SHOWCONTAINER=1
      ;;
    d)
      DEBUG=1
      ;;
    f)
      FINDPATH="${OPTARG}"
      ;;
    h|\?)
      usage
      ;;
    j)
      FINDJAVA=1
      ;;
    n)
      SHOWPOD=1
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
      PASSVERBOSE="-v"
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

if [ "${VERBOSE}" -eq "1" ]; then
  printVerbose "started with ${@}"
  if [ "${FINDPATH}" != "" ]; then
    printVerbose "With -f ${FINDPATH}"
  fi
fi

CONTAINER_RUNTIME=0

[ "${VERBOSE}" -eq "1" ] && printVerbose "Checking container runtime: runc"

# TODO https://github.com/opencontainers/runc/issues/3462#issuecomment-1155422205
CONTAINER_LIST_OUTPUT="$(${CMD_RUNC} list)"

[ "${VERBOSE}" -eq "1" ] && printVerbose "runc list: ${CONTAINER_LIST_OUTPUT}"

RUNCLIST_LINES="$(echo "${CONTAINER_LIST_OUTPUT}" | wc -l)"

[ "${VERBOSE}" -eq "1" ] && printVerbose "runc list lines: ${RUNCLIST_LINES}"

if [ "${RUNCLIST_LINES}" -eq "1" ]; then
  # runc list didn't return any containers, so try containerd

  [ "${VERBOSE}" -eq "1" ] && printVerbose "Checking container runtime: containerd"

  # TODO https://github.com/opencontainers/runc/issues/3462#issuecomment-1155422205
  CONTAINER_LIST_OUTPUT="$(${CMD_CONTAINERD} list)"

  [ "${VERBOSE}" -eq "1" ] && printVerbose "ctr --namespace k8s.io containers list: ${CONTAINER_LIST_OUTPUT}"

  CONTAINERDLIST_LINES="$(echo "${CONTAINER_LIST_OUTPUT}" | wc -l)"

  [ "${VERBOSE}" -eq "1" ] && printVerbose "runc list lines: ${CONTAINERDLIST_LINES}"

  if [ "${CONTAINERDLIST_LINES}" -eq "1" ]; then
    # Unknown container runtime
    printError "Unknown container runtime. runc and ctr both returned 0 containers. Please re-run with -v and open an issue with the output."
    exit 1
  else
    # Successfully found containerd
    CONTAINER_RUNTIME=${CONTAINER_RUNTIME_CONTAINERD}
  fi
else
  # Successfully found runc
  CONTAINER_RUNTIME=${CONTAINER_RUNTIME_RUNC}

  # Remove any stopped containers
  CONTAINER_LIST_OUTPUT="$(echo "${CONTAINER_LIST_OUTPUT}" | grep -v stopped)"
fi

[ "${VERBOSE}" -eq "1" ] && printVerbose "Container runtime: ${CONTAINER_RUNTIME}"

FOUND=0

for ID in $(echo "${CONTAINER_LIST_OUTPUT}" | awk 'NR > 1 && NF > 2 {print $1}'); do

  [ "${VERBOSE}" -eq "1" ] && printVerbose "Processing ID ${ID}"

  PID=""
  CONTAINERTYPE=""

  if [ "${CONTAINER_RUNTIME}" -eq "${CONTAINER_RUNTIME_RUNC}" ]; then

    [ "${VERBOSE}" -eq "1" ] && printVerbose "${CMD_RUNC} state ${ID}"
    
    RUNCSTATE="$(${CMD_RUNC} state ${ID} 2>/dev/null)"

    if [ "${?}" -eq "0" ]; then
      [ "${VERBOSE}" -eq "1" ] && printVerbose "runc state output: ${RUNCSTATE}"

      RUNCSTATEROWS="$(echo "${RUNCSTATE}" | jq -r '.pid, .annotations."io.kubernetes.container.name", .annotations."io.kubernetes.pod.namespace", .annotations."io.kubernetes.pod.name", .rootfs, .annotations."io.kubernetes.cri-o.LogPath"')"

      PID="$(echo "${RUNCSTATEROWS}" | awk 'NR==1')"
      CONTAINERNAME="$(echo "${RUNCSTATEROWS}" | awk 'NR==2')"
      CONTAINERNAMESPACE="$(echo "${RUNCSTATEROWS}" | awk 'NR==3')"
      PODNAME="$(echo "${RUNCSTATEROWS}" | awk 'NR==4')"
      ROOTFS="$(echo "${RUNCSTATEROWS}" | awk 'NR==5')"
      STDOUTERR="$(echo "${RUNCSTATEROWS}" | awk 'NR==6')"
    fi

  elif [ "${CONTAINER_RUNTIME}" -eq "${CONTAINER_RUNTIME_CONTAINERD}" ]; then

    [ "${VERBOSE}" -eq "1" ] && printVerbose "${CMD_CONTAINERD} info ${ID}"

    CONTAINERDINFO="$(${CMD_CONTAINERD} info ${ID} 2>/dev/null)"

    if [ "${?}" -eq "0" ]; then
      [ "${VERBOSE}" -eq "1" ] && printVerbose "ctr info output: ${CONTAINERDINFO}"

      [ "${VERBOSE}" -eq "1" ] && printVerbose "${CMD_CONTAINERD2} state ${ID}"

      CONTAINERDSTATE="$(${CMD_CONTAINERD2} state ${ID} 2>/dev/null)"

      if [ "${?}" -eq "0" ]; then
        [ "${VERBOSE}" -eq "1" ] && printVerbose "runc state output: ${CONTAINERDSTATE}"

        CONTAINERDSTATESTATEROWS="$(echo "${CONTAINERDSTATE}" | jq -r '.pid, .annotations."io.kubernetes.cri.container-name", .annotations."io.kubernetes.cri.sandbox-namespace", .annotations."io.kubernetes.cri.sandbox-name", .rootfs, .annotations."io.kubernetes.cri.sandbox-namespace", .annotations."io.kubernetes.cri.sandbox-uid", .annotations."io.kubernetes.cri.container-type"')"

        PID="$(echo "${CONTAINERDSTATESTATEROWS}" | awk 'NR==1')"
        CONTAINERNAME="$(echo "${CONTAINERDSTATESTATEROWS}" | awk 'NR==2')"
        CONTAINERNAMESPACE="$(echo "${CONTAINERDSTATESTATEROWS}" | awk 'NR==3')"
        PODNAME="$(echo "${CONTAINERDSTATESTATEROWS}" | awk 'NR==4')"
        ROOTFS="$(echo "${CONTAINERDSTATESTATEROWS}" | awk 'NR==5')"
        STDOUTERR="/var/log/pods/$(echo "${CONTAINERDSTATESTATEROWS}" | awk 'NR==6')_${PODNAME}_$(echo "${CONTAINERDSTATESTATEROWS}" | awk 'NR==7')/${CONTAINERNAME}/0.log"
        CONTAINERTYPE="$(echo "${CONTAINERDSTATESTATEROWS}" | awk 'NR==8')"
        if [ "${CONTAINERTYPE}" != "sandbox" ]; then
          CONTAINERTYPE=""
        fi
      fi
    fi
  fi
  
  [ "${VERBOSE}" -eq "1" ] && printVerbose "pid: ${PID}, container: ${CONTAINERNAME}, pod: ${PODNAME}, namespace: ${CONTAINERNAMESPACE}, rootfs: ${ROOTFS}, stdouterr: ${STDOUTERR}"

  if [ "${PID}" != "" ] && [ "${CONTAINERTYPE}" = "" ]; then
    for SEARCH in "${@}"; do

      ISMATCH=0

      if [ "${SEARCH}" = "${PODNAME}" ]; then

        [ "${VERBOSE}" -eq "1" ] && printVerbose "Found matching pod1 ${PODNAME}"

        ISMATCH=1

      elif [ "${FINDPATH}" != "" ]; then
        FOUNDPATH="$(podfspath.sh ${PASSVERBOSE} "${ROOTFS}" "${FINDPATH}")"

        [ "${VERBOSE}" -eq "1" ] && printVerbose "Search for ${FINDPATH}: ${FOUNDPATH}"

        if [ "${FOUNDPATH}" != "" ]; then

          if [ -d "${FOUNDPATH}" ]; then
            [ "${VERBOSE}" -eq "1" ] && printVerbose "Found matching pod2 ${PODNAME}"
            ISMATCH=1
          else
            [ "${VERBOSE}" -eq "1" ] && printVerbose "Directory does not exist"
          fi
        fi
      fi

      if [ "${ISMATCH}" -eq "1" ]; then
        if [ "${FOUND}" -gt 0 ]; then
          if [ "${SHOWCONTAINER}" -eq 0 ] || [ "${SHOWPOD}" -eq 0 ]; then
            printf " "
          fi
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
        if [ "${PIDFOUND}" -eq "1" ]; then
          if [ "${SHOWCONTAINER}" -eq 1 ]; then
            printf " %s\n" "${CONTAINERNAME}"
          elif [ "${SHOWPOD}" -eq 1 ]; then
            printf " %s %s\n" "${PODNAME}" "${CONTAINERNAMESPACE}"
          fi
        fi
        FOUND="$(((${FOUND}+1)))"
      fi
    done
  fi
done

if [ "${FOUND}" -gt 0 ]; then
  printf "\n"
fi

[ "${VERBOSE}" -eq "1" ] && printVerbose "script returning"
