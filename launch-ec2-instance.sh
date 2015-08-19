#!/bin/sh

. aws.env

if ! [ -e var/volume.id ]; then echo "var/volume.id: not found (did you run make-ebs-volume?)"; exit -1; fi

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

