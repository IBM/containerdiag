#!/bin/sh
usage() {
  printf "Usage: %s [OPTIONS] [PODNAME]...\n" "$(basename "${0}")"
  cat <<"EOF"
             -d: DELAY for run.sh
             -j: JAVACORE_INTERVAL for linperf.sh
             -m: VMSTAT_INTERVAL for linperf.sh
             -n: No download necessary (for run.sh)
             -s: SCRIPT_SPAN for linperf.sh
             -t: TOP_INTERVAL for linperf.sh
             -u: TOP_DASH_H_INTERVAL for linperf.sh
             -v: verbose output to stderr
             -z: Skip statistics collection
EOF
  exit 2
}

DELAY=""
NODOWNLOAD=""
SKIPSTATS=""
VERBOSE=""
JAVACORE_INTERVAL=""
SCRIPT_SPAN=""
TOP_INTERVAL=""
TOP_DASH_H_INTERVAL=""
VMSTAT_INTERVAL=""

OPTIND=1
while getopts "d:hj:m:ns:t:u:vz?" opt; do
  case "$opt" in
    d)
      DELAY="-d ${OPTARG}"
      ;;
    h|\?)
      usage
      ;;
    j)
      JAVACORE_INTERVAL="-j ${OPTARG}"
      ;;
    m)
      VMSTAT_INTERVAL="-m ${OPTARG}"
      ;;
    n)
      NODOWNLOAD="-n"
      ;;
    s)
      SCRIPT_SPAN="-s ${OPTARG}"
      ;;
    t)
      TOP_INTERVAL="-t ${OPTARG}"
      ;;
    u)
      TOP_DASH_H_INTERVAL="-u ${OPTARG}"
      ;;
    v)
      VERBOSE="-v"
      ;;
    z)
      SKIPSTATS="-z"
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

run.sh ${DELAY} ${NODOWNLOAD} ${VERBOSE} ${SKIPSTATS} sh -c "linperf.sh -q ${SCRIPT_SPAN} ${JAVACORE_INTERVAL} ${TOP_INTERVAL} ${TOP_DASH_H_INTERVAL} ${VMSTAT_INTERVAL} $(podinfo.sh ${VERBOSE} -p ${@}) && DUMPS=\"\$(libertydump.sh ${VERBOSE} ${PODARGS})\"; podfscp.sh ${VERBOSE} -s ${PODARGS} /logs /config /output/javacore* \${DUMPS} ; podfsrm.sh ${VERBOSE} ${PODARGS} /output/javacore* \${DUMPS}"
