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
# Kubernetes debug pods are transient but we normally want to save output
# for download. The idea of this script is that we run the specified commands
# and then pause for download.
# Example:
# oc debug node/$NODE -t --image=quay.io/ibm/containerdiagsmall -- run.sh sh -c 'echo "Hello World"'

usage() {
  printf "Usage: %s [OPTIONS] COMMAND [ARGUMENTS]\n" "$(basename "${0}")"
  cat <<"EOF"
             -d: DELAY in seconds between checking command and download completion.
             -n: No download necessary
             -v: verbose output to stderr
             -z: Skip statistics collection
EOF
  exit 2
}

VERSION="0.1.20230418"
DESTDIR="/tmp"
VERBOSE=0
PASSVERBOSE=""
SKIPSTATS=0
DELAY=8
NODOWNLOAD=0
OUTPUTFILE="run_stdouterr.log"

echo "Started run.sh version ${VERSION}"

OPTIND=1
while getopts "d:hnvz?" opt; do
  case "$opt" in
    d)
      if [ "${OPTARG}" != "-1" ]; then
        DELAY="${OPTARG}"
      fi
      ;;
    h|\?)
      usage
      ;;
    n)
      NODOWNLOAD=1
      ;;
    v)
      VERBOSE=1
      PASSVERBOSE="-v"
      ;;
    z)
      SKIPSTATS=1
      ;;
  esac
done

shift $((OPTIND-1))

if [ "${1:-}" = "--" ]; then
  shift
fi

# Remove any trailing slash from $DESTDIR
DESTDIR="${DESTDIR%/}"

if [ ! -d "${DESTDIR}" ]; then
  echo "ERROR: Expecting a Kubernetes debug pod that has a mount at ${DESTDIR}"
  exit 1
fi

printVerbose() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S.%N %Z')] $(basename "${0}"): ${@}" >> /dev/stderr
}

printInfo() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S.%N %Z')] $(basename "${0}"): ${@}" | tee -a "${OUTPUTFILE}"
}

printError() {
  printVerbose "ERROR: " "${@}"
}

runOnHost() {
  # unshare -rR /host "${@}"
  chroot /host "${@}"
}

if [ "${#}" -eq 0 ]; then
  echo "ERROR: Missing COMMAND"
  usage
fi

TARGETDIR="$(mktemp -d "${DESTDIR}/containerdiag.XXXXXXXXXX")"

if [ "${TARGETDIR}" = "" ]; then
  echo "ERROR: Failed to create a temporary directory in ${DESTDIR}"
  exit 1
fi

# Add a trailing slash to $TARGETDIR
TMPNAME="$(basename "${TARGETDIR}")"
TARGETDIR="${TARGETDIR}/"

echo "Writing to ${TARGETDIR}"

pushd "${TARGETDIR}" || exit 1

# Now we can finally start the execution
printInfo "started on $(hostname) ($(uname -m)) version ${VERSION}"

# First try to find the name of the debug pod because we'll need it later
# and it's pointless to continue if we can't find it.
# We touch a file in our temp directory which we'll then search for.
touch /tmp/${TMPNAME} || exit 1

[ "${VERBOSE}" -eq "1" ] && printVerbose "Touched /tmp/${TMPNAME}"

DEBUGPODINFO="$(podinfo.sh ${PASSVERBOSE} -n -f "/tmp/${TMPNAME}" -)"

[ "${VERBOSE}" -eq "1" ] && printVerbose "debug podinfo: ${DEBUGPODINFO}"

if [ "${DEBUGPODINFO}" = "" ]; then
  if [ "${VERBOSE}" -eq "1" ]; then
    printError "Could not find the name of the debug pod."
    exit 1
  else
    printError "Could not find the name of the debug pod. Please re-run with -v and report this issue with the output."
    exit 1
  fi
fi

DEBUGPODNAME="$(echo "${DEBUGPODINFO}" | awk '{print $2}')"
DEBUGPODNAMESPACE="$(echo "${DEBUGPODINFO}" | awk '{print $3}')"

if [ "${DEBUGPODNAME}" = "" ] || [ "${DEBUGPODNAMESPACE}" = "" ] || [ "${DEBUGPODNAME}" = "null" ] || [ "${DEBUGPODNAMESPACE}" = "null" ]; then
  if [ "${VERBOSE}" -eq "1" ]; then
    printError "Could not find the name details of the debug pod."
    exit 1
  else
    printError "Could not find the name details of the debug pod. Please re-run with -v and report this issue with the output."
    exit 1
  fi
fi

printInfo "debug node pod name = '${DEBUGPODNAME}' and namespace = '${DEBUGPODNAMESPACE}'"

nodeInfo() {
  mkdir -p node/$1
  top -b -d 1 -n 2 &> node/$1/top.txt
  top -H -b -d 1 -n 2 &> node/$1/topthreads.txt
  ps -elfyww &> node/$1/ps.txt
  iostat -xm 1 2 &> node/$1/iostat.txt
  ip addr &> node/$1/ipaddr.txt
  ip -s link &> node/$1/iplink.txt
  ss --summary &> node/$1/sssummary.txt
  ss -amponeti &> node/$1/ssdetails.txt
  nstat -saz &> node/$1/nstat.txt
  netstat -i &> node/$1/netstati.txt
  netstat -s &> node/$1/netstats.txt
  netstat -anop &> node/$1/netstat.txt
  runOnHost systemd-cgtop -b --depth=5 -d 1 -n 2 &> node/$1/cgtop.txt
  runOnHost cat /proc/loadavg &> node/$1/loadavg.txt
}

# Gather the first set of node info
if [ "${SKIPSTATS}" -eq "0" ]; then
  printInfo "gathering first set of system info."

  nodeInfo "stats_iteration1_$(date +"%Y%m%d_%H%M%S")"
fi

printInfo "executing command: ${@}"

# We can't just run the process directly because some kube/oc debug
# sessions will timeout if nothing happens for a while, so we put
# it in the background and then wait until it's done
( "${@}" 2>&1 | tee -a "${OUTPUTFILE}" ) &

BGPID="${!}"

printInfo "waiting for background commands (PID ${BGPID}) to finish..."

# Some scripts finish in a few seconds, so optimize for that case
sleep 5

if [ -d /proc/${BGPID} ]; then
  while true; do
    printInfo "waiting for script to complete"
    sleep ${DELAY}
    if [ ! -d /proc/${BGPID} ]; then
      break
    fi
  done
fi

printInfo "command completed."

if [ "${SKIPSTATS}" -eq "0" ]; then
  printInfo "gathering second set of system info."
  nodeInfo "stats_iteration2_$(date +"%Y%m%d_%H%M%S")"
fi

mkdir -p node/info
runOnHost date &> node/info/date.txt
runOnHost uname -a &> node/info/uname.txt
runOnHost journalctl -b | head -2000 &> node/info/journalctl_head.txt
runOnHost journalctl -b -n 2000 &> node/info/journalctl_tail.txt
runOnHost journalctl -p warning -n 500 &> node/info/journalctl_errwarn.txt
runOnHost sysctl -a &> node/info/sysctl.txt
runOnHost lscpu &> node/info/lscpu.txt
ulimit -a &> node/info/ulimit.txt
uptime &> node/info/uptime.txt
hostname &> node/info/hostname.txt
runOnHost cat /proc/cpuinfo &> node/info/cpuinfo.txt
runOnHost cat /proc/meminfo &> node/info/meminfo.txt
runOnHost cat /proc/version &> node/info/version.txt
cp -r /host/proc/pressure node/info/ 2>/dev/null
runOnHost cat /etc/*elease* &> node/info/release.txt
runOnHost df -h &> node/info/df.txt
runOnHost systemctl list-units &> node/info/systemctlunits.txt
runOnHost systemd-cgls &> node/info/cgroups.txt
cp /opt/containerdiag_buildinfo.txt node/info/ 2>/dev/null
pstree -pT &> node/info/pstree.txt

# For cgroup v2, the output is cgroup2fs.
# For cgroup v1, the output is tmpfs.
stat -fc %T /host/sys/fs/cgroup/ &> node/info/cgrouptype.txt

chmod -R a+w node

printInfo "All data gathering complete."

if [ "${NODOWNLOAD}" -eq "0" ]; then
  printInfo "Packaging for download."

  # After we're done, we want to package everything up into a tgz
  # and show an example command of how to download it.
  TARFILE="${TARGETDIR%/}.tar.gz"
  tar -czf "${TARFILE}" -C "${TARGETDIR}" . || exit 1

  rm -rf "${TARGETDIR}"

  # Stop using printInfo since we're packaging that output
  echo "[$(date '+%Y-%m-%d %H:%M:%S.%N %Z')] $(basename "${0}"): Finished with output in ${TARFILE}"

  echo "[$(date '+%Y-%m-%d %H:%M:%S.%N %Z')] $(basename "${0}"): Debug pod is ${DEBUGPODNAME} in namespace ${DEBUGPODNAMESPACE}"

  ls -lh "${TARFILE}"

  while true; do
    echo "[$(date '+%Y-%m-%d %H:%M:%S.%N %Z')] $(basename "${0}"): Files are ready for download using one of the following commands in another window:"
    echo ""
    echo "  oc cp ${DEBUGPODNAME}:${TARFILE} $(basename "${TARFILE}") --namespace=${DEBUGPODNAMESPACE}"
    echo ""
    echo "OR"
    echo ""
    echo "  kubectl cp ${DEBUGPODNAME}:${TARFILE} $(basename "${TARFILE}") --namespace=${DEBUGPODNAMESPACE}"
    echo ""
    # We don't just allow a lone ENTER because admins often press ENTER during script execution
    # to visually space output, and those get queued up in the input buffer and would end up
    # immediately returning here before the admin had a chance to download the file.
    #
    # Ctrl^C also works but might cause issues with multi-node executions
    if read -p "After the download is complete, type OK and press ENTER: " -t ${DELAY} READSTR; then
      if [ "${READSTR}" = "OK" ] || [ "${READSTR}" = "ok" ] || [ "${READSTR}" = "O" ] || [ "${READSTR}" = "o" ]; then
        break
      else
        echo "ENTER encountered without OK confirmation; continue waiting..."
      fi
    fi
    echo ""
  done

  echo "[$(date '+%Y-%m-%d %H:%M:%S.%N %Z')] $(basename "${0}"): Processing finished. Deleting ${TARFILE}"

  rm -f "${TARFILE}"
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S.%N %Z')] $(basename "${0}"): finished."
