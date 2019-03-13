#!/bin/bash

# By default, search for upgrades from Jewel to Luminous.
CEPH_MAJORVER_EXPECTED_OLD=10
CEPH_MAJORVER_EXPECTED_NEW=12

# Expect that Ceph was upgraded from major version $1
if [ -z ${CEPH_MAJORVER_EXPECTED_OLD+x} ]; then
  CEPH_MAJORVER_EXPECTED_OLD=$1
fi
# Expect that Ceph was upgraded from major version $2
if [ -z ${CEPH_MAJORVER_EXPECTED_NEW+x} ]; then
  CEPH_MAJORVER_EXPECTED_NEW=$2
fi

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
  INSTANCE_USE_RBD=$?
  # If QEMU process has been running before the Ceph upgrade and instance uses a RBD driver,
  # then with rather good probability it's running the old Ceph client version.
  if [[ "$QEMU_TIMESTAMP" -lt "$CEPH_UPGRADE_TIMESTAMP" ]] && [ "$INSTANCE_USE_RBD" -eq "0" ]
  then
    # Print out the instance UUID for further processing
    INSTANCE_UUID=$(virsh dumpxml $INSTANCE_NAME|grep \/uuid|awk -F'>' "{print \$2}"|awk -F'<' "{print \$1}")
    echo $INSTANCE_UUID
    # The following two lines can be uncommented if one is also interested about the overall
    # number of RBDs (volume attachments), since that seems to correlate best to the number
    # of clients that ceph-mgr is seeing.
    #INSTANCE_QEMU_MON_RBD_COUNT=$(virsh qemu-monitor-command --hmp "$INSTANCE_NAME" 'info block'|grep -c rbd)
    #echo "DEBUG: $INSTANCE_UUID has this many RBD devices configured: $INSTANCE_QEMU_MON_RBD_COUNT"
  fi
done

