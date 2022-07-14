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
# 

usage() {
  printf "Usage: %s [OPTIONS] [PODNAME]...\n" "$(basename "${0}")"
  cat <<"EOF"
             -d: DELAY (for run.sh)
             -j: JAVACORE_INTERVAL for linperf.sh
             -m: VMSTAT_INTERVAL for linperf.sh
             -n: No download necessary (for run.sh)
             -p: Skip the Liberty server dump
             -s: SCRIPT_SPAN for linperf.sh
             -t: TOP_INTERVAL for linperf.sh
             -u: TOP_DASH_H_INTERVAL for linperf.sh
             -v: verbose output to stderr
             -z: Skip statistics collection (for run.sh)
EOF
  exit 2
}

DELAY=""
NODOWNLOAD=""
SKIPSTATS=""
SKIPSERVERDUMP=0
VERBOSE=""
JAVACORE_INTERVAL=""
SCRIPT_SPAN=""
TOP_INTERVAL=""
TOP_DASH_H_INTERVAL=""
VMSTAT_INTERVAL=""

OPTIND=1
while getopts "d:hj:m:nps:t:u:vz?" opt; do
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
    p)
      SKIPSERVERDUMP=1
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

if [ "${SKIPSERVERDUMP}" -eq "0" ]; then
  run.sh ${DELAY} ${NODOWNLOAD} ${VERBOSE} ${SKIPSTATS} sh -c "linperf.sh -q ${SCRIPT_SPAN} ${JAVACORE_INTERVAL} ${TOP_INTERVAL} ${TOP_DASH_H_INTERVAL} ${VMSTAT_INTERVAL} $(podinfo.sh ${VERBOSE} -j -p ${@}) && DUMPS=\"\$(libertydump.sh ${VERBOSE} ${PODARGS})\"; podfscp.sh ${VERBOSE} -s ${PODARGS} /logs /config /output/javacore* \${DUMPS} ; podfsrm.sh ${VERBOSE} ${PODARGS} /output/javacore* \${DUMPS}"
else
  run.sh ${DELAY} ${NODOWNLOAD} ${VERBOSE} ${SKIPSTATS} sh -c "linperf.sh -q ${SCRIPT_SPAN} ${JAVACORE_INTERVAL} ${TOP_INTERVAL} ${TOP_DASH_H_INTERVAL} ${VMSTAT_INTERVAL} $(podinfo.sh ${VERBOSE} -j -p ${@}) && podfscp.sh ${VERBOSE} -s ${PODARGS} /logs /config /output/javacore* ; podfsrm.sh ${VERBOSE} ${PODARGS} /output/javacore*"
fi
