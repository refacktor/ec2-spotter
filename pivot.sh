#!/bin/sh -x


NEWMNT=/new-root
OLDMNT=old-root
DEVICE=/dev/xvdj1

echo "Mounting $DEVICE ON $NEWMNT"
mkdir $NEWMNT
mount $DEVICE $NEWMNT

[ ! -d $NEWMNT/$OLDMNT ] && echo "Creating directory $NEWMNT/$OLDMNT." && mkdir -p $NEWMNT/$OLDMNT

echo "Trying to pivot."
cd $NEWMNT
pivot_root . ./$OLDMNT

for dir in /dev /proc /sys; do
echo "Moving mounted file system ${OLDMNT}${dir} to $dir."
mount --move ./${OLDMNT}${dir} ${dir}
done

echo "Trying to chroot."
exec chroot . /bin/sh -c "umount ./$OLDMNT; exec /sbin/init $*" < /dev/console > /dev/console 2>&1
