DEVICE=/dev/xvdf1
NEWMNT=/permaroot
OLDMNT=old-root

mkdir $NEWMNT
mount $DEVICE $NEWMNT || exit -1

[ ! -d $NEWMNT/$OLDMNT ] && mkdir -p $NEWMNT/$OLDMNT

cd $NEWMNT
pivot_root . ./$OLDMNT

for dir in /dev /proc /sys /run; do
    echo "Moving mounted file system ${OLDMNT}${dir} to $dir."
    mount --move ./${OLDMNT}${dir} ${dir}
done

echo "Trying to chroot."
exec chroot . /bin/bash -i

