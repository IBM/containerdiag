#!/bin/sh
usage() {
  printf "Usage: %s [-v] [-s SCRIPTSPAN] [-j JAVACORE_INTERVAL] [-t TOP_INTERVAL] [-u TOP_DASH_H_INTERVAL] [-m VMSTAT_INTERVAL] [PODNAME]...\n" "$(basename "${0}")"
  cat <<"EOF"
             -j: JAVACORE_INTERVAL for linperf.sh
             -m: VMSTAT_INTERVAL for linperf.sh
             -s: SCRIPT_SPAN for linperf.sh
             -t: TOP_INTERVAL for linperf.sh
             -u: TOP_DASH_H_INTERVAL for linperf.sh
             -v: verbose output to stderr
EOF
  exit 2
}

VERBOSE=""
JAVACORE_INTERVAL="-1"
SCRIPT_SPAN="-1"
TOP_INTERVAL="-1"
TOP_DASH_H_INTERVAL="-1"
VMSTAT_INTERVAL="-1"

OPTIND=1
while getopts "hj:m:s:t:u:v?" opt; do
  case "$opt" in
    h|\?)
      usage
      ;;
    j)
      JAVACORE_INTERVAL="${OPTARG}"
      ;;
    m)
      VMSTAT_INTERVAL="${OPTARG}"
      ;;
    s)
      SCRIPT_SPAN="${OPTARG}"
      ;;
    t)
      TOP_INTERVAL="${OPTARG}"
      ;;
    u)
      TOP_DASH_H_INTERVAL="${OPTARG}"
      ;;
    v)
      VERBOSE="-v"
      ;;
  esac
done

shift $((OPTIND-1))

if [ "${1:-}" = "--" ]; then
  shift
fi

if [ "${#}" -eq 0 ]; then
  echo "ERROR: Missing PODNAMEs"
  usage
fi

PODARGS=""
for ARG in "${@}"; do
  PODARGS="${PODARGS} -p ${ARG}"
done

run.sh sh -c "linperf.sh -q -s ${SCRIPT_SPAN} -j ${JAVACORE_INTERVAL} -t ${TOP_INTERVAL} -u ${TOP_DASH_H_INTERVAL} -m ${VMSTAT_INTERVAL} $(podinfo.sh ${VERBOSE} -j -p ${@}) && podfscp.sh ${VERBOSE} -s ${PODARGS} /opt/IBM/WebSphere/AppServer/profiles/AppSrv01/logs/ /opt/IBM/WebSphere/AppServer/profiles/AppSrv01/config/ /opt/IBM/WebSphere/AppServer/profiles/AppSrv01/javacore* ; podfsrm.sh ${VERBOSE} ${PODARGS} /opt/IBM/WebSphere/AppServer/profiles/AppSrv01/javacore*"
