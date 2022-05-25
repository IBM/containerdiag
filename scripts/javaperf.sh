#!/bin/sh
usage() {
  printf "Usage: %s [-v] [-s SCRIPTSPAN] [PODNAME]...\n" "$(basename "${0}")"
  cat <<"EOF"
             -s: SCRIPTSPAN for linperf.sh
             -v: verbose output to stderr
EOF
  exit 2
}

VERBOSE=""
SCRIPTSPAN=240

OPTIND=1
while getopts "hs:v?" opt; do
  case "$opt" in
    h|\?)
      usage
      ;;
    s)
      SCRIPTSPAN="${OPTARG}"
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

run.sh sh -c "linperf.sh -q -s ${SCRIPTSPAN} $(podinfo.sh ${VERBOSE} -p ${@}) && podfscp.sh ${VERBOSE} -s ${PODARGS} /logs /config /output/javacore* ; podfsrm.sh ${VERBOSE} ${PODARGS} /output/javacore*"
