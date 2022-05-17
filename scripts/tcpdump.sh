#!/bin/sh
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
INTERFACE="any"

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

run.sh sh -c "echo \"[\$(date '+%Y-%m-%d %H:%M:%S.%N %Z')] tcpdump.sh: Starting tcpdump with duration ${DURATION}s and interface ${INTERFACE}\" && timeout ${DURATION} tcpdump -nn -v -i ${INTERFACE} -B 4096 -s 80 -C 100 -W 10 -Z root -w diag_capture_\$(hostname)_\$(date +%Y%m%d_%H%M%S).pcap &> stdouterr.txt"
