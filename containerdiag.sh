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
# 
# Run specified COMMANDS on a specific pod or all pods of a deployment
# For details, see https://www.ibm.com/support/pages/mustgather-performance-hang-or-high-cpu-issues-websphere-application-server-linux-containers

usage() {
  printf "Usage: %s [options] [-d DEPLOYMENT] [-p POD] COMMANDS...\n" "$(basename "${0}")"
  cat <<"EOF"
             -d DEPLOYMENT: Run COMMANDS on all pods in the specified DEPLOYMENT
             -i IMAGE: The image used for the debug pod (default quay.io/ibm/containerdiag)
             -k: By default, this script uses oc if available. This options forces the use of kubectl
             -n NAMESPACE: Namespace (optional; defaults to current namespace)
             -p POD: Run COMMANDS on the specified POD
             -q: Do not append the pod name to COMMANDS
             -v: verbose output to stderr

             COMMANDS will be passed to oc debug node along with the pod name at the end
             (unless -q is specified in which case the pod name is not appended)
EOF
  exit 22
}

VERSION="0.1.20230301"
NAMESPACE=""
VERBOSE=0
APPEND=1
CTL="oc"
CTL_DEBUG_FLAGS="-t"
IMAGE="quay.io/ibm/containerdiag:latest"
TARGETDEPLOYMENT=""
TARGETPOD=""

use_kubectl() {
  CTL="kubectl"
  CTL_DEBUG_FLAGS="-it"
}

command_exists() {
  command -v "${1}" >/dev/null 2>&1
}

OPTIND=1
while getopts "d:hi:kn:p:qv?" opt; do
  case "$opt" in
    d)
      TARGETDEPLOYMENT="${OPTARG}"
      ;;
    h|\?)
      usage
      ;;
    i)
      IMAGE="${OPTARG}"
      ;;
    k)
      if ! command_exists kubectl ; then
        echo "ERROR: Could not find the command kubectl on PATH"
        exit 1
      fi
      use_kubectl
      ;;
    n)
      NAMESPACE="${OPTARG}"
      ;;
    p)
      TARGETPOD="${OPTARG}"
      ;;
    q)
      APPEND=0
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

if ! command_exists oc && ! command_exists kubectl ; then
  echo "ERROR: Could not find the command oc or kubectl on PATH"
  exit 1
elif ! command_exists oc ; then
  use_kubectl
fi

if [ "${TARGETDEPLOYMENT}" = "" ] && [ "${TARGETPOD}" = "" ]; then
  echo "ERROR: Either -d DEPLOYMENT or -p POD must be specified"
  usage
fi

if [ "${#}" -eq 0 ]; then
  echo "ERROR: Missing COMMANDS"
  usage
fi

printInfo() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] $(basename "${0}"): ${*}" | tee -a diag.log
}

printVerbose() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] $(basename "${0}"): ${*}" | tee -a diag.log
}

printInfo "Script version ${VERSION} started with ${CTL} and ${IMAGE}"

[ "${VERBOSE}" -eq "1" ] && printVerbose "Commands: ${*}"

# We'll need the namespace, so if they haven't specified it
# get the current one

if [ "${NAMESPACE}" = "" ]; then
  NAMESPACE="$("${CTL}" config view --minify --output 'jsonpath={..namespace}')"
  if [ "${NAMESPACE}" = "" ]; then
    NAMESPACE="default"
  fi
fi

processPod() {
  POD="${1}"; shift
  WORKER="${1}"; shift

  if [ "${APPEND}" -eq 1 ]; then
    printInfo "Processing: ${CTL} debug node/${WORKER} ${CTL_DEBUG_FLAGS} --image=${IMAGE} -- ${@} ${POD}"
    "${CTL}" debug "node/${WORKER}" ${CTL_DEBUG_FLAGS} "--image=${IMAGE}" -- "${@}" "${POD}" | tee -a diag.log
  else
    printInfo "Processing: ${CTL} debug node/${WORKER} ${CTL_DEBUG_FLAGS} --image=${IMAGE} -- ${@}"
    "${CTL}" debug "node/${WORKER}" ${CTL_DEBUG_FLAGS} "--image=${IMAGE}" -- "${@}" | tee -a diag.log
  fi
}

if [ "${TARGETDEPLOYMENT}" != "" ]; then
  printInfo "Querying replicas for deployment ${TARGETDEPLOYMENT} in namespace ${NAMESPACE}"

  # Let's check if the deployment has any active pods
  REPLICAS="$("${CTL}" get deployment "${TARGETDEPLOYMENT}" "--namespace=${NAMESPACE}" "--output=jsonpath={.status.replicas}")"
  RC="${?}"

  if [ ${RC} -ne 0 ]; then
    printInfo "Error ${RC} getting deployment information (see previous output). Ensure you specify the right namespace with -n NAMESPACE"
    exit ${RC}
  fi

  if [ "${REPLICAS}" = "" ]; then
    printInfo "Error getting deployment information. Ensure you specify the right namespace with -n NAMESPACE"
    exit 1
  fi

  if [ "${REPLICAS}" -eq 0 ]; then
    printInfo "Error: There are 0 replicas for this deployment"
    exit 1
  fi

  printInfo "There are ${REPLICAS} replicas"

  printInfo "Querying deployment selector label"

  # We need to find the selector for the pods
  # https://github.com/kubernetes/kubernetes/issues/72794#issuecomment-483502617
  SELECTORRAW="$("${CTL}" get --raw "/apis/apps/v1/namespaces/${NAMESPACE}/deployments/${TARGETDEPLOYMENT}/scale")"
  RC="${?}"

  if [ ${RC} -ne 0 ]; then
    printInfo "Error ${RC} getting scale information (see previous output)."
    exit ${RC}
  fi

  SELECTOR="$(echo "${SELECTORRAW}" | sed 's/.*"selector":"//g' | sed 's/".*//g')"
  if [ "${SELECTOR}" = "" ]; then
    printInfo "Error getting scale selector from: ${SELECTORRAW}"
    exit 1
  fi

  printInfo "Selector labels are ${SELECTOR}"

  printInfo "Getting pods by selector"

  # Now that we have the selector, we can get the pods
  PODS="$("${CTL}" get pods --namespace "${NAMESPACE}" --selector "${SELECTOR}" --output "jsonpath={range .items[*]}{.metadata.name}{' '}{.spec.nodeName}{'\n'}{end}")"
  RC="${?}"

  if [ ${RC} -ne 0 ]; then
    printInfo "Error ${RC} getting pod information (see previous output)."
    exit ${RC}
  fi

  printInfo "Found the following pods:\n${PODS}"

  OLDIFS="${IFS}"

  # Subshell strips newline so add a random character to the end (/) and then strip it
  IFS="$(printf '\n/')"
  IFS="${IFS%/}"

  for LINE in ${PODS}; do
    IFS="${OLDIFS}"
    processPod ${LINE} "${@}"
  done
elif [ "${TARGETPOD}" != "" ]; then

  # We just need to find the worker node
  printInfo "Querying worker node for pod ${TARGETPOD} in namespace ${NAMESPACE}"
  WORKER="$("${CTL}" get pod "${TARGETPOD}" --namespace "${NAMESPACE}" --output "jsonpath={.spec.nodeName}")"
  RC="${?}"

  if [ ${RC} -ne 0 ] || [ "${WORKER}" = "" ]; then
    printInfo "Error ${RC} getting pod information (see previous output). Ensure you specify the right namespace with -n NAMESPACE"
    exit ${RC}
  fi

  processPod "${TARGETPOD}" "${WORKER}" "${@}"
fi

printInfo "Finished"
