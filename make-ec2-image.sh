#!/bin/sh

. aws.env

if ! [ -e $BUSYBOX_FS ]; then echo "$BUSYBOX_FS: not found (did you run make-busybox.sh?)"; exit -1; fi

#17. Bundle the image.
$AMIBIN/ec2-bundle-image -i $BUSYBOX_FS -d /tmp -k $EC2_PRIVATE_KEY -c $EC2_CERT -u $AWS_ACCOUNT_NUMBER -r $ARCH  || exit -1

echo "#18. Upload the image."

$AMIBIN/ec2-upload-bundle -b $EC2_BUCKET -m /tmp/busybox.fs.manifest.xml -a $AWS_ACCESS_KEY -s $AWS_SECRET_KEY || exit -1

#19. Register the AMI.

BUSYBOX_AMI=`$APIBIN/ec2-register "$EC2_BUCKET/busybox.fs.manifest.xml"  | awk '{print $2}'`
echo "BUSYBOX_AMI: $BUSYBOX_AMI"

echo $BUSYBOX_AMI > var/busybox-ami.id
