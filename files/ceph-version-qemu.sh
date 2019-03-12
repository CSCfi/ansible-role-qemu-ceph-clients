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

YUM_HISTORY_EVENTS=$(yum history|grep -E '^  '|awk '{print $1}')

for YUM_HISTORY_EVENT in $YUM_HISTORY_EVENTS; do
  CEPH_MAJORVER_OLD=$(yum history info $YUM_HISTORY_EVENT|grep -A1 ceph-common|head -1|awk -F':' '{print $2}'|awk -F'.' '{print $1}')
  CEPH_MAJORVER_NEW=$(yum history info $YUM_HISTORY_EVENT|grep -A1 ceph-common|tail -1|awk -F':' '{print $2}'|awk -F'.' '{print $1}')
  if [[ "$CEPH_MAJORVER_OLD" == "$CEPH_MAJORVER_EXPECTED_OLD" ]] && [[ "$CEPH_MAJORVER_NEW" == "$CEPH_MAJORVER_EXPECTED_NEW" ]]
  then
    CEPH_UPGRADE_DATE=$(yum history info $YUM_HISTORY_EVENT|grep '^Begin time'|awk -F' : ' '{print $2}')
    CEPH_UPGRADE_TIMESTAMP=$(date -d "$CEPH_UPGRADE_DATE" +%s)
    break
  fi
done

PIDS=$(pidof /usr/libexec/qemu-kvm)

for PID in $PIDS; do
  QEMU_TIMESTAMP=$(date -d "$(stat -c %x /proc/$PID/stat)" +%s)
  if [[ "$QEMU_TIMESTAMP" -lt "$CEPH_UPGRADE_TIMESTAMP" ]]
  then
    INSTANCE_NAME=$(ps -ef -q $PID|grep -Po "(instance-\w+)"|uniq)
    INSTANCE_UUID=$(virsh dumpxml $INSTANCE_NAME|grep \/uuid|awk -F'>' "{print \$2}"|awk -F'<' "{print \$1}")
    echo $INSTANCE_UUID
  fi
done

