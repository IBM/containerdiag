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
             -d: DELAY (for run.sh)
             -n: No download necessary (for run.sh)
             -v: verbose output to stderr
             -z: Skip statistics collection (for run.sh)
EOF
  exit 2
}

DELAY=""
NODOWNLOAD=""
VERBOSE=""
SKIPSTATS=""

# We periodically observe a strange issue where the first few seconds
# of output are not sent to the console, so sleep to try to avoid this.
sleep 5
echo "Started $(basename "${0}")"

OPTIND=1
while getopts "d:hnvz?" opt; do
  case "$opt" in
    d)
      DELAY="-d ${OPTARG}"
      ;;
    h|\?)
      usage
      ;;
    n)
      NODOWNLOAD="-n"
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

run.sh ${DELAY} ${NODOWNLOAD} ${VERBOSE} ${SKIPSTATS} sh -c "echo 'Pod info for ${@}:'; podinfo.sh ${VERBOSE} -c -p ${@}; echo 'Gathering basic pod logs and info'; podfscp.sh ${VERBOSE} -s ${PODARGS} /etc/hostname"

echo "Finished test.sh"
