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

usage() {
  printf "Usage: %s [OPTIONS] [PODNAME]...\n" "$(basename "${0}")"
  cat <<"EOF"
             -c: Path to javacores (default /opt/IBM/WebSphere/AppServer/profiles/AppSrv01/javacore*)
             -d: DELAY (for run.sh)
             -f: Configuration directory (default /opt/IBM/WebSphere/AppServer/profiles/AppSrv01/config/)
             -j: JAVACORE_INTERVAL for linperf.sh
             -l: Logs directory (default /opt/IBM/WebSphere/AppServer/profiles/AppSrv01/logs/)
             -m: VMSTAT_INTERVAL for linperf.sh
             -n: No download necessary (for run.sh)
             -s: SCRIPT_SPAN for linperf.sh
             -t: TOP_INTERVAL for linperf.sh
             -u: TOP_DASH_H_INTERVAL for linperf.sh
             -v: verbose output to stderr
             -z: Skip statistics collection (for run.sh)
EOF
  exit 2
}

# We periodically observe a strange issue where the first few seconds
# of output are not sent to the console, so sleep to try to avoid this.
sleep 5
echo "Started $(basename "${0}")"

DELAY=""
NODOWNLOAD=""
SKIPSTATS=""
VERBOSE=""
JAVACORE_INTERVAL=""
SCRIPT_SPAN=""
TOP_INTERVAL=""
TOP_DASH_H_INTERVAL=""
VMSTAT_INTERVAL=""
JAVACORE_PATH="/opt/IBM/WebSphere/AppServer/profiles/AppSrv01/javacore*"
LOGS_DIR="/opt/IBM/WebSphere/AppServer/profiles/AppSrv01/logs/"
CONFIG_DIR="/opt/IBM/WebSphere/AppServer/profiles/AppSrv01/config/"

OPTIND=1
while getopts "c:d:f:hj:l:m:ns:t:u:vz?" opt; do
  case "$opt" in
    c)
      JAVACORE_PATH="${OPTARG}"
      ;;
    d)
      DELAY="-d ${OPTARG}"
      ;;
    f)
      CONFIG_DIR="${OPTARG}"
      ;;
    h|\?)
      usage
      ;;
    j)
      JAVACORE_INTERVAL="-j ${OPTARG}"
      ;;
    l)
      LOGS_DIR="${OPTARG}"
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

run.sh ${DELAY} ${NODOWNLOAD} ${VERBOSE} ${SKIPSTATS} sh -c "linperf.sh -q ${SCRIPT_SPAN} ${JAVACORE_INTERVAL} ${TOP_INTERVAL} ${TOP_DASH_H_INTERVAL} ${VMSTAT_INTERVAL} $(podinfo.sh ${VERBOSE} -j -p ${@}) && podfscp.sh ${VERBOSE} -s ${PODARGS} ${LOGS_DIR} ${CONFIG_DIR} ${JAVACORE_PATH} ; podfsrm.sh ${VERBOSE} ${PODARGS} ${JAVACORE_PATH}"
