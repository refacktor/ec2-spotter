# default values
export EC2_CERT=/path/to/your/cert.pem
export EC2_PRIVATE_KEY=/path/to/your/pk.pem
export EC2_BUCKET=”your_bucket”
export AWS_ACCOUNT_NUMBER=”NNNN-NNNN-NNNN”
export AWS_ACCESS_KEY_ID=your_key
export AWS_SECRET_ACCESS_KEY=your_secret_key
# override defaults with secret values
source /root/.aws-secrets

export EC2_HOME=./ec2-api-tools-1.7.5.0
#export JAVA_HOME=/usr/java/default
export ARCH=`uname -i`
export AKI=`curl -s http://169.254.169.254/latest/meta-data/kernel-id`
export ARI=`curl -s http://169.254.169.254/latest/meta-data/ramdisk-id`
export INSTANCE_ID=`curl -s http://169.254.169.254/latest/meta-data/instance-id`
export AVAIL_ZONE=`curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone`
export SEC_GROUP=`curl -s http://169.254.169.254/latest/meta-data/security-groups`
export PUB_KEY=`wget -q -O – “http://169.254.169.254/latest/meta-data/public-keys” | awk -F= ‘{print $2}’`

#17. Bundle the image.

ec2-bundle-image -i $HOME/busybox.fs -d /tmp -k $EC2_PRIVATE_KEY -c $EC2_CERT -u $AWS_ACCOUNT_NUMBER -r $ARCH –kernel $AKI –ramdisk $ARI

#18. Upload the image.

ec2-upload-bundle -b $EC2_BUCKET -m /tmp/busybox.fs.manifest.xml -a $AWS_ACCESS_KEY_ID -s $AWS_SECRET_ACCESS_KEY

#19. Register the AMI.

BUSYBOX_AMI=`ec2-register “$EC2_BUCKET/busybox.fs.manifest.xml” | awk ‘{print $2}’`
echo “BUSYBOX_AMI: $BUSYBOX_AMI”

#20. Create an EBS volume of the desired size (10G or more) in the desired availability zone.

VOLUME_ID=`ec2-create-volume -s 10 -z $AVAIL_ZONE | awk ‘{print $2}’`
echo “VOLUME_ID: $VOLUME_ID”

#21. Attach the volume to the current instance as /dev/sdj.

ec2-attach-volume $VOLUME_ID -i $INSTANCE_ID -d /dev/sdj

#22. Create an EXT3 file system on /dev/sdj.

mkfs.ext3 /dev/sdj

#22. Mount the EBS volume.

mkdir /mnt/ebs_boot
mount /dev/sdj /mnt/ebs_boot

#23. Copy the current AMI to the EBS volume.

rsync -avHx / /mnt/ebs_boot

#24. Fix the /etc/fstab file.

vi /mnt/ebs_boot/etc/fstab
Remove the local file systems.
/dev/sda1 / ext3 defaults 1 1
/dev/sdb /mnt ext3 defaults 1 2
/dev/sda3 swap swap defaults 0 0
Add the /dev/sdj file system.
/dev/sdj / ext3 defaults 1 1

#25. Fix the /etc/inittab file. The cloud AMI’s are normally configured for runlevel 4.

vi /mnt/ebs_boot/etc/inittab
Edit the following line if necessary:
id:4:initdefault:

#26. Un-mount the EBS volume.

sync
umount /mnt/ebs_boot

#27. Detach the volume.

ec2-detach-volume $VOLUME_ID -i $INSTANCE_ID -d /dev/sdj

#28. Create a new instance running the BusyBox AMI.

BUSYBOX_ID=`ec2-run-instances $BUSYBOX_AMI -z $AVAIL_ZONE -k $PUB_KEY -g $SEC_GROUP | awk ‘{print $6}’`

#29. Wait until the instance is running…

ec2-describe-instances $BUSYBOX_ID

#30. Attach the EBS volume to the BusyBox instance as /dev/sdj.

ec2-attach-volume $VOLUME_ID -i $BUSYBOX_ID -d /dev/sdj

#31. Reboot the BusyBox instance to make sure it picks up the new device.

ec2-reboot-instances $BUSYBOX_ID

#32. Check the BusyBox instance’s console output to make sure it came up as expected.

ec2-get-console-output $BUSYBOX_ID

#33. Log into the new EBS backed instance.

#That should be it. You now have a persistent instance that is backed by EBS storage!

