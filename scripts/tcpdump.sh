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
  printf "Usage: %s [-0 DURATION] [tcpdump arguments...]\n" "$(basename "${0}")"
  cat <<"EOF"
             -0: DURATION (in seconds) for the collection. Default 60
              *: All other options from tcpdump. Overridden defaults:
                 -B 4096
                 -C 100
                 -i any
                 -nn
                 -s 80
                 -v
                 -w diag_capture_$(hostname)_$(date +%Y%m%d_%H%M%S).pcap
                 -W 10
                 -Z root
EOF
  exit 2
}

DURATION=60
INTERFACE="$(guesslink.sh)"
SNAPLEN=80
BUFFERSIZE=4096
FILESIZE=100
FILECOUNT=10

OPTERR=0
OPTIND=1
while getopts "0:B:C:hi:s:W:?" opt; do
  case "$opt" in
    0)
      DURATION="${OPTARG}"
      ;;
    B)
      BUFFERSIZE="${OPTARG}"
      ;;
    C)
      FILESIZE="${OPTARG}"
      ;;
    h|\?)
      usage
      ;;
    i)
      INTERFACE="${OPTARG}"
      ;;
    s)
      SNAPLEN="${OPTARG}"
      ;;
    W)
      FILECOUNT="${OPTARG}"
      ;;
  esac
done

shift $((OPTIND-1))

if [ "${1:-}" = "--" ]; then
  shift
fi

run.sh sh -c "echo \"[\$(date '+%Y-%m-%d %H:%M:%S.%N %Z')] tcpdump.sh: Starting tcpdump with duration ${DURATION}s and interface ${INTERFACE}\" && timeout ${DURATION} tcpdump -nn -v -i ${INTERFACE} -B ${BUFFERSIZE} -s ${SNAPLEN} -C ${FILESIZE} -W ${FILECOUNT} -w diag_capture_\$(hostname)_\$(date +%Y%m%d_%H%M%S).pcap -Z root ${@} &> stdouterr.txt"
