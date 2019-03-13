#!/bin/bash

# By default, search for upgrades from Jewel to Luminous.
CEPH_MAJORVER_EXPECTED_OLD=10
CEPH_MAJORVER_EXPECTED_NEW=12
# By default, include VMs which do not have RBD block devices attached.
INCLUDE_QEMU_WITHOUT_RBD=0
# By default, no debug
DEBUG=1

usage() {
  echo "Usage: $0 [-o 10] [-n 12] [-e] [-d]" 1>&2;
  echo "" 1>&2;
  echo "  -o, expected old ceph version" 1>&2;
  echo "  -n, expected new ceph version" 1>&2;
  echo "  -e, exclude VMs with no RBDs present" 1>&2;
  echo "  -d, debug" 1>&2;
  echo "" 1>&2;
  exit 1
}

while getopts ":o:n:edh" arg; do
  case $arg in
    o)
       CEPH_MAJORVER_EXPECTED_OLD=$OPTARG
       ;;
    n)
       CEPH_MAJORVER_EXPECTED_NEW=$OPTARG
       ;;
    e)
       INCLUDE_QEMU_WITHOUT_RBD=1
       ;;
    d)
       DEBUG=0
       ;;
    h|*)
       usage
       exit 0
       ;;
  esac
done

# Retrieve a list of all yum history event IDs
YUM_HISTORY_EVENTS=$(yum history list all|grep -Po "^\s+\d+")

for YUM_HISTORY_EVENT in $YUM_HISTORY_EVENTS; do
  CEPH_MAJORVER_OLD=$(yum history info $YUM_HISTORY_EVENT|grep -A1 ceph-common|head -1|awk -F':' '{print $2}'|awk -F'.' '{print $1}')
  CEPH_MAJORVER_NEW=$(yum history info $YUM_HISTORY_EVENT|grep -A1 ceph-common|tail -1|awk -F':' '{print $2}'|awk -F'.' '{print $1}')
  # See if this event matches the upgrade path we're looking for
  if [[ "$CEPH_MAJORVER_OLD" == "$CEPH_MAJORVER_EXPECTED_OLD" ]] && [[ "$CEPH_MAJORVER_NEW" == "$CEPH_MAJORVER_EXPECTED_NEW" ]]
  then
    # It did, so mark down event time
    CEPH_UPGRADE_DATE=$(yum history info $YUM_HISTORY_EVENT|grep '^Begin time'|awk -F' : ' '{print $2}')
    CEPH_UPGRADE_TIMESTAMP=$(date -d "$CEPH_UPGRADE_DATE" +%s)
    break
  fi
done

# Retrieve a list of all QEMU process IDs
PIDS=$(pidof /usr/libexec/qemu-kvm)

for PID in $PIDS; do
  # Get QEMU process start time
  QEMU_TIMESTAMP=$(date -d "$(stat -c %x /proc/$PID/stat)" +%s)
  # Get virsh instance name
  INSTANCE_NAME=$(ps -ef -q $PID|grep -Po "(instance-\w+)"|uniq)
  # Look for presence of block devices with "rbd" driver (as opposed to "raw" for local)
  INSTANCE_QEMU_MON_RBD=$(virsh qemu-monitor-command --hmp "$INSTANCE_NAME" 'info block'|grep rbd)
  # Save return code for determining if rbd's were present
  INSTANCE_HAS_RBD=$?
  # Check if instance did NOT have RBDs
  if [[ "$INSTANCE_HAS_RBD" -ne "0" ]]
  then
    # Check if we should not report on these type of instances
    if [[ "$INCLUDE_QEMU_WITHOUT_RBD" -ne "0" ]]
    then
      break
    fi
  fi

  # Check if QEMU process has been running before the Ceph upgrade
  if [[ "$QEMU_TIMESTAMP" -lt "$CEPH_UPGRADE_TIMESTAMP" ]]
  then
    # If it did, print out the instance UUID.
    INSTANCE_UUID=$(virsh dumpxml $INSTANCE_NAME|grep \/uuid|awk -F'>' "{print \$2}"|awk -F'<' "{print \$1}")
    echo $INSTANCE_UUID
    if [[ "$DEBUG" -eq "0" ]]
    then
      INSTANCE_QEMU_MON_RBD_COUNT=$(virsh qemu-monitor-command --hmp "$INSTANCE_NAME" 'info block'|grep -c rbd)
      echo "DEBUG: $INSTANCE_UUID has this many RBD devices configured: $INSTANCE_QEMU_MON_RBD_COUNT"
    fi
  fi
done
