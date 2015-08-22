#!/bin/sh

. aws.env

#20. Create an EBS volume of the desired size (10G or more) in the desired availability zone.

VOLUME_ID=`$APIBIN/ec2-create-volume -s 10 -z $AVAIL_ZONE | awk '{print $2}'`
echo "VOLUME_ID: $VOLUME_ID"

# Comment by pndiku: The "sleep" parameters put below aren't trustworthy
# A better way to check would be to poll the instance

#21. Attach the volume to the current instance as /dev/sdj.
echo "Waiting for volume to be created..."
sleep 30

$APIBIN/ec2-attach-volume $VOLUME_ID -i $INSTANCE_ID -d /dev/sdj || exit -1

#22. Create a partition and an EXT3 file system on /dev/sdj.
echo "Waiting for volume to be attached..."
sleep 30

# We'll later use a label for mounting
# Comment by pndiku: HVMs use the xvd terminology, not sd
mkfs.ext3 /dev/xvdj -L "root" || exit -1

#22. Mount the EBS volume.

mkdir /mnt/ebs_boot || exit -1
mount /dev/xvdj /mnt/ebs_boot || exit -1

#23. Copy the current AMI to the EBS volume.

rsync -avHx / /mnt/ebs_boot || exit -1

#24. Fix the /etc/fstab file.

cat > /mnt/ebs_boot/etc/fstab << EOF
LABEL=root / ext3 defaults 1 1
EOF

#25. Fix the /etc/inittab file. The cloud AMI's are normally configured for runlevel 4.
cat > /mnt/ebs_boot/etc/inittab <<EOF
id:4:initdefault:
EOF

#26. Un-mount the EBS volume.

sync
umount /mnt/ebs_boot

#27. Detach the volume.

$APIBIN/ec2-detach-volume $VOLUME_ID -i $INSTANCE_ID -d /dev/sdj

echo $VOLUME_ID > var/volume.id
