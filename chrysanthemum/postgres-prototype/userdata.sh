#!/bin/bash

set -e
set -x

# template()
#
# stone-stupid templating with only perl
# replaces ${VARIABLE} with an environment variable value where available
#
function template() {
  perl -p -e 's/\$\{([^}]+)\}/defined $ENV{$1} ? $ENV{$1} : $&/eg' $1
}

function configure_drives() {
echo "--- CONFIGURE DRIVES"

apt-get install -y mdadm xfsprogs

echo "--- configuring write ahead log drive"
echo deadline > /sys/block/sde1/queue/scheduler
mkfs.ext3 -q -L /wal /dev/sde1
mkdir -p /wal && mount -o noatime -t ext3 /dev/sde1 /wal
echo "/dev/sde1         /wal        ext3   nodev,nosuid,noatime" >> /etc/fstab

echo "--- creating raid for database cluster" 
for i in /sys/block/sdf{1..8}/queue/scheduler; do
  echo "deadline" > $i
done
# a bug with udev conflicts with mdadm
service udev stop
mdadm --create /dev/md0 -n 8 -l 0 -c 256 /dev/sdf{1..8}
mdadm -Es >>/etc/mdadm/mdadm.conf
service udev start
blockdev --setra 65535 /dev/md0
mkfs.xfs -q -L /database /dev/md0
mkdir -p /database && mount -o noatime -t xfs /dev/md0 /database
echo "/dev/md0          /database   xfs" >> /etc/fstab

}


function userdata() {
exec 2>&1

echo "--- BEGIN"
export DEBIAN_FRONTEND="noninteractive"
export DEBIAN_PRIORITY="critical"

configure_drives

echo "--- POSTGRESQL INSTALL"
apt-get -y install thin postgresql-8.4 postgresql-server-dev-8.4 libpq-dev libgeos-dev proj
service postgresql-8.4 stop

echo "--- POSTGRESQL VARS"
export DATA_DIR="/database"
export WAL_DIR="/wal"
export SYSTEM_MEMORY_KB=$(cat /proc/meminfo | awk '/MemTotal/ { print $2 }')
export PG_EFFECTIVE_CACHE_SIZE=$(($SYSTEM_MEMORY_KB * 9 / 10 / 1024))MB
export PG_SHARED_BUFFERS=$(($SYSTEM_MEMORY_KB / 4 / 1024))MB
#export PG_ARCHIVE_COMMAND=XXX TODO

echo "--- POSTGRESQL CONFIGURE"

echo "--- templating and placing config files."
# TODO: maybe there ought to be a more built in way to get data to here
wget https://stem.s3.amazonaws.com/packet.tar.gz
tar xzpvf packet.tar.gz

cp packet/pg_hba.conf /etc/postgresql/8.4/main/
template packet/postgresql.conf-8.4.template > /etc/postgresql/8.4/main/postgresql.conf

# shmmax -> one third of system RAM in bytes
echo "kernel.shmmax=$((SYSTEM_MEMORY_KB * 1024 / 3))" >> /etc/sysctl.conf
sysctl -p /etc/sysctl.conf

template packet/s3cfg.template > /etc/s3cfg
chown postgres:postgres /etc/s3cfg

echo "--- creating database cluster"
mkdir -p $DATA_DIR
mkdir -p $WAL_DIR
chown postgres:postgres $DATA_DIR $WAL_DIR
chmod 700 $DATA_DIR $WAL_DIR
su - postgres -c "/usr/lib/postgresql/8.4/bin/initdb -D $DATA_DIR"
mv $DATA_DIR/pg_xlog/ $WAL_DIR
ln -s $WAL_DIR/pg_xlog $DATA_DIR/pg_xlog
ln -s /etc/ssl/certs/ssl-cert-snakeoil.pem $DATA_DIR/server.crt
ln -s /etc/ssl/private/ssl-cert-snakeoil.key $DATA_DIR/server.key

echo "--- starting postgres service"
service postgresql-8.4 start

echo "--- FINISHED, SHUTTING DOWN"
shutdown -h now

}

userdata > /var/log/kuzushi.log

