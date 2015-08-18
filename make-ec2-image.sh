#!/bin/sh

BUSYBOX_FS=/tmp/busybuild/busybox.fs

if ! [ -e $BUSYBOX_FS ]; then echo "$BUSYBOX_FS: not found (did you run make-busybox.sh?)"; exit -1; fi

# default values to be overridden by local configuration
export EC2_CERT=/path/to/your/cert.pem
export EC2_PRIVATE_KEY=/path/to/your/pk.pem
export EC2_BUCKET="your_bucket"
export AWS_ACCOUNT_NUMBER="NNNN-NNNN-NNNN"
export AWS_ACCESS_KEY=your_key
export AWS_SECRET_KEY=your_secret_key
# override defaults with secret values
. /root/.aws-secrets

export AMIBIN=./ec2-ami-tools-*/bin
export APIBIN=./ec2-api-tools-*/bin

export EC2_HOME=$(ls -d ./ec2-api-tools-*)

export JAVA_HOME=/usr/lib/jvm/default-java
export ARCH=`uname -i`
# Comment by pndiku: AKI's don't exist for HVM instances
# export ARI=`curl -s http://169.254.169.254/latest/meta-data/ramdisk-id`
export INSTANCE_ID=`curl -s http://169.254.169.254/latest/meta-data/instance-id`
export AVAIL_ZONE=`curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone`
export SEC_GROUP=`curl -s http://169.254.169.254/latest/meta-data/security-groups`
export PUB_KEY=`wget -q -O - "http://169.254.169.254/latest/meta-data/public-keys" | awk -F= '{print $2}'`

#17. Bundle the image.
$AMIBIN/ec2-bundle-image -i $BUSYBOX_FS -d /tmp -k $EC2_PRIVATE_KEY -c $EC2_CERT -u $AWS_ACCOUNT_NUMBER -r $ARCH  || exit -1

echo "#18. Upload the image."

$AMIBIN/ec2-upload-bundle -b $EC2_BUCKET -m /tmp/busybox.fs.manifest.xml -a $AWS_ACCESS_KEY -s $AWS_SECRET_KEY || exit -1

#19. Register the AMI.

BUSYBOX_AMI=`$APIBIN/ec2-register "$EC2_BUCKET/busybox.fs.manifest.xml"  | awk '{print $2}'`
echo "BUSYBOX_AMI: $BUSYBOX_AMI"

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

#28. Create a new instance running the BusyBox AMI.

BUSYBOX_ID=`$APIBIN/ec2-run-instances $BUSYBOX_AMI -z $AVAIL_ZONE -k $PUB_KEY -g $SEC_GROUP | grep INSTANCE | awk '{print $2}'`

echo "Please wait while launching instance"
sleep 30
#29. Wait until the instance is running...

$APIBIN/ec2-describe-instances $BUSYBOX_ID 

#30. Attach the EBS volume to the BusyBox instance as /dev/sdj.

$APIBIN/ec2-attach-volume $VOLUME_ID -i $BUSYBOX_ID -d /dev/sdj

#31. Reboot the BusyBox instance to make sure it picks up the new device.

$APIBIN/ec2-reboot-instances $BUSYBOX_ID

#32. Check the BusyBox instance's console output to make sure it came up as expected.

$APIBIN/ec2-get-console-output $BUSYBOX_ID

#33. Log into the new EBS backed instance.

#That should be it. You now have a persistent instance that is backed by EBS storage!

