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
  printf "Usage: %s [-v] [-d DURATION]\n" "$(basename "${0}")"
  cat <<"EOF"
             -d: DURATION (in seconds) for the collection
             -v: verbose output to stderr
EOF
  exit 2
}

VERBOSE=""
DURATION=60

OPTIND=1
while getopts "d:hv?" opt; do
  case "$opt" in
    d)
      DURATION="${OPTARG}"
      ;;
    h|\?)
      usage
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

run.sh sh -c "perf record -o perf.data --call-graph dwarf,65528 -F 99 -a -g -- sleep ${DURATION} &>>stdouterr.log && perf script --kallsyms=/host/proc/kallsyms --symfs=/host/ > diag_perfscript_\$(hostname)_\$(date +%Y%m%d_%H%M%S_%N).txt 2>>stdouterr.log && cat diag_perfscript_*.txt | stackcollapse-perf.pl | flamegraph.pl --width 1024 > perf.svg && perf archive &>>stdouterr.log"
