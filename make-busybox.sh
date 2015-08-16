#!/bin/sh
#
# COPYRIGHT (c)2015 ZIGABYTE CORPORATION. COPYING PERMITTED UNDER GPLv3
#

export BUILD=/tmp/busybuild
rm -rfv $BUILD
mkdir $BUILD

# Configure Busybox
cd busybox-*/ || exit -1
make -s defconfig

# Make the build static
sed -i 's/# CONFIG_STATIC is not set/CONFIG_STATIC=y/' .config

# Make and install BusyBox
make -s CONFIG_PREFIX=$BUILD/busyroot install
chmod 4755 $BUILD/busyroot/bin/busybox

# Create required directories
cd $BUILD/busyroot
mkdir dev sys etc proc mnt mnt/new-root

# Create the necessary devices(We will use /dev/sdj for the EBS volume, but this could be any block device not used by the normal AMI
(
	cd $BUILD/busyroot/dev
	MAKEDEV sdj
	MAKEDEV console
	MAKEDEV null
	MAKEDEV zero
)

# Create the init file.
mv $BUILD/busyroot/sbin/init $BUILD/busyroot/sbin/init.orig
cat <<'EOL' > $BUILD/busyroot/sbin/init
#!/bin/busybox sh
PATH=/bin:/usr/bin:/sbin:/usr/sbin
NEWDEV="/dev/sdj"
NEWTYP="ext3"
NEWMNT="/mnt/new-root"
OLDMNT="/mnt/old-root"
OPTIONS="noatime,ro"
SLEEP=10

echo "Remounting writable."
mount -o remount,rw /
[ ! -d $NEWMNT ] && echo "Creating directory $NEWMNT." && mkdir -p $NEWMNT

while true ; do
echo "sleeping..."
sleep $SLEEP
echo "Trying to mount $NEWDEV writable."
mount -t $NEWTYP -o rw $NEWDEV $NEWMNT || continue
echo "Mounted."
break;
done

[ ! -d $NEWMNT/$OLDMNT ] && echo "Creating directory $NEWMNT/$OLDMNT." && mkdir -p $NEWMNT/$OLDMNT

echo “Remounting $NEWMNT $OPTIONS."
mount -o remount,$OPTIONS $NEWMNT

echo "Trying to pivot."
cd $NEWMNT
pivot_root . ./$OLDMNT

for dir in /dev /proc /sys; do
echo "Moving mounted file system ${OLDMNT}${dir} to $dir."
mount -move ./${OLDMNT}${dir} ${dir}
done

echo "Trying to chroot"
exec chroot . /bin/sh -c "unmount ./$OLDMNT; exec /sbin/init $*" < /dev/console > /dev/console 2&1
EOL

chmod 755 $BUILD/busyroot/sbin/init

# Create the fstab file
cat <<'EOL' > $BUILD/busyroot/etc/fstab
/dev/sda1 / ext3 defaults 1 1
none /dev/pts devpts gid=5,mode=620 0 0
none /proc proc defaults 0 0
none /sys sysfs defaults 0 0
EOL

# Create a 4MB loopback file.
cd $BUILD
dd if=/dev/zero of=busybox.fs bs=1M count=4
yes | mkfs.ext3 busybox.fs

#Mount the loopback file
mkdir $BUILD/busyimg
mount -o loop $BUILD/busybox.fs $BUILD/busyimg
#Copy the staged files and directories to the image. (Technically, the BusyBox image could have been built directly in $BUILD/busyimg, but we were not sure how big the image was going to be.)
cp -rp $BUILD/busyroot/* $BUILD/busyimg

#Un-mount the image
sync
umount $BUILD/busyimg

