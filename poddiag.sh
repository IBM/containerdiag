#!/bin/sh
# Comment about this script

usage() {
  printf "Usage: %s [-k] [-v] [-n NAMESPACE] DEPLOYMENT COMMANDS...\n" "$(basename "${0}")"
  cat <<"EOF"
             -k: Use kubectl instead of oc
             -n: Namespace (optional; defaults to current namespace)
             -v: verbose output to stderr

             COMMANDS will be passed to oc debug node along with the pod name at the end
EOF
  exit 22
}

NAMESPACE=""
VERBOSE=0
CTL="oc"

OPTIND=1
while getopts "hkn:v?" opt; do
  case "$opt" in
    h|\?)
      usage
      ;;
    k)
      CTL="kubectl"
      ;;
    n)
      NAMESPACE="${OPTARG}"
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
  echo "ERROR: Missing DEPLOYMENT"
  usage
fi

DEPLOYMENT="${1}"
shift

if [ "${#}" -eq 0 ]; then
  echo "ERROR: Missing COMMANDS"
  usage
fi

printInfo() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] $(basename "${0}"): ${@}"
}

printVerbose() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] $(basename "${0}"): ${@}" >> /dev/stderr
}

printInfo "Script started for deployment ${DEPLOYMENT}"

[ "${VERBOSE}" -eq "1" ] && printVerbose "Commands: ${@}"

# We'll need the namespace, so if they haven't specified it
# get the current one

if [ "${NAMESPACE}" = "" ]; then
  NAMESPACE="$("${CTL}" config view --minify --output 'jsonpath={..namespace}')"
  if [ "${NAMESPACE}" = "" ]; then
    NAMESPACE="default"
  fi
fi

printInfo "Querying available replicas for deployment ${DEPLOYMENT} in namespace ${NAMESPACE}"

# Let's check if the deployment has any active pods
AVAILABLEREPLICAS="$("${CTL}" get deployment "${DEPLOYMENT}" "--namespace=${NAMESPACE}" "--output=jsonpath={.status.availableReplicas}")"
RC="${?}"

if [ ${RC} -ne 0 ]; then
  printInfo "Error ${RC} getting deployment information (see previous output). Ensure you specify the right namespace with -n NAMESPACE"
  exit ${RC}
fi

if [ "${AVAILABLEREPLICAS}" = "" ]; then
  printInfo "Error getting deployment information. Ensure you specify the right namespace with -n NAMESPACE"
  exit 1
fi

if [ "${AVAILABLEREPLICAS}" -eq 0 ]; then
  printInfo "Error: There are 0 available replicas for this deployment"
  exit 1
fi

printInfo "There are ${AVAILABLEREPLICAS} available replicas"

printInfo "Querying deployment selector label"

# We need to find the selector for the pods
# https://github.com/kubernetes/kubernetes/issues/72794#issuecomment-483502617
SELECTORRAW="$("${CTL}" get --raw "/apis/apps/v1/namespaces/${NAMESPACE}/deployments/${DEPLOYMENT}/scale")"
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

processPod() {
  POD="${1}"; shift
  WORKER="${1}"; shift

  printInfo "Processing pod ${POD} on worker node ${WORKER} with ${@} ${POD}"

  "${CTL}" debug "node/${WORKER}" -t --image=quay.io/ibm/containerdiag -- "${@}" "${POD}"
}

OLDIFS="${IFS}"

# Subshell strips newline so add a random character to the end (+) and then strip it
IFS="$(printf '\n/')"
IFS="${IFS%/}"

for LINE in ${PODS}; do
  IFS="${OLDIFS}"
  processPod ${LINE} "${@}"
done

printInfo "Finished"
