#!/bin/bash
export AWS_CREDENTIAL_FILE=/root/.aws.creds
. /root/.aws.creds
export AWS_ACCESS_KEY=$AWSAccessKeyId
export AWS_SECRET_KEY=$AWSSecretKey

export AMIBIN=./ec2-ami-tools-*/bin
export APIBIN=./ec2-api-tools-*/bin

export EC2_HOME=$(ls -d ./ec2-api-tools-*)

export JAVA_HOME=$(echo /usr/lib/jvm/*)
export ARCH=`uname -i`

export INSTANCE_ID=`curl -s http://169.254.169.254/latest/meta-data/instance-id`
export DEST_ZONE=`curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone`
export DEST_REGION=${DEST_ZONE::-1} # Get the region by stripping the last character of the SOURCE_ZONE

SOURCE_REGION=$DEST_REGION # By default, we're in the same region
#SOURCE_ZONE=$DEST_ZONE

TAG_KEY="Name"
TAG_VALUE="ctcdev"

# Check S3 to see if we have updated configuration settings
# By default, we expect a bucket called ec2-spotter-config, and a config file to override the above 3 settings
# called ec2-spotter.ini
# NOTE: us-east-1 is the only endpoint for S3 that has no location constraint
# See here: http://docs.aws.amazon.com/general/latest/gr/rande.html#s3_region
#if aws s3 --endpoint us-east-1 cp s3://ec2-spotter-config/ec2-spotter.ini  . ; then
#    . ec2-spotter.ini
#fi

echo "Looking for a volume in $SOURCE_REGION with tags ${TAG_KEY} = ${TAG_VALUE}"
volInfo=$(${APIBIN}/ec2-describe-tags --region ${SOURCE_REGION} --filter "resource-type=volume" --filter "key=${TAG_KEY}" --filter "value=${TAG_VALUE}")
echo $volInfo
SOURCE_VOLUME=$(echo $volInfo | awk '{print $3}' | head -1)
SOURCE_ZONE=$(${APIBIN}/ec2-describe-volumes $SOURCE_VOLUME | head -1 | awk '{print $5}')

[[ -z $SOURCE_VOLUME ]] && echo "*** ERROR: No source volume found with tags ${TAG_KEY} = ${TAG_VALUE}" && exit 1

# Are we copying the volume from the same region?
if [[ $SOURCE_ZONE != $DEST_ZONE ]]; then
    # need to copy the volume across
    echo "Volume $SOURCE_VOLUME is in another region"
    echo "Creating a snapshot of the volume"
    SNAPSHOT=$(${APIBIN}/ec2-create-snapshot --region ${SOURCE_REGION} $SOURCE_VOLUME --description 'ec2-spotter temporary snapshot ok to delete' | awk '{print $2}')
    
    echo "Snapshot $SNAPSHOT created. Waiting for completion"
    # Keep checking to see that snapshot has been created
    count=0
    while /bin/true
    do
        sleep 30
        eval count=$((count+30))
        echo "... $count seconds gone. Still waiting..."
        STATUS=$(${APIBIN}/ec2-describe-snapshots --region ${SOURCE_REGION} ${SNAPSHOT} | grep completed)

        [[ ! -z $STATUS ]] && break
    done
    echo "Snapshot $SNAPSHOT created successfully"
    echo "------------------------------------------------"
    echo ""
    
    # Copying the snapshot would be needed if the REGION was different. Old code available in git
    NEW_SNAPSHOT=$SNAPSHOT

    # create volume from this new snapshot
    NEW_VOLUME=$(${APIBIN}/ec2-create-volume --snapshot ${NEW_SNAPSHOT} -z ${DEST_ZONE} | awk '{print $2}')
    echo "Creating volume $NEW_VOLUME from $NEW_SNAPSHOT. Waiting for completion"
    
    # Keep checking to see that volume has been created
    count=0
    while /bin/true
    do
        sleep 30
        eval count=$((count+30))
        echo "... $count seconds gone. Still waiting..."
        STATUS=$(${APIBIN}/ec2-describe-volumes ${NEW_VOLUME} | grep available)

        [[ ! -z $STATUS ]] && break
    done
    
    echo "Volume $NEW_VOLUME created successfully"
    echo "------------------------------------------------"


    PIVOT_VOLUME=${NEW_VOLUME}
else
    PIVOT_VOLUME=${SOURCE_VOLUME}
fi

echo ""
echo "Attaching volume $PIVOT_VOLUME as /dev/sdj"
# Attach volume
${APIBIN}/ec2-attach-volume $PIVOT_VOLUME -d /dev/sdj --instance $INSTANCE_ID || exit -1

while ! lsblk /dev/xvdj1
do
  echo "waiting for device to attach"
  sleep 10
done

# all this stuff not working
#
#DEVICE=/dev/xvdj1
#NEWMNT=/new-root
#OLDMNT=old-root
#
#echo "Mounting $DEVICE ON $NEWMNT"
#mount $DEVICE $NEWMNT || exit -1
#
#[ ! -d $NEWMNT/$OLDMNT ] && echo "Creating directory $NEWMNT/$OLDMNT." && mkdir -p $NEWMNT/$OLDMNT
#
#echo "Trying to pivot."
#cd $NEWMNT
#pivot_root . ./$OLDMNT
#
#for dir in /dev /proc /sys /run; do
#    echo "Moving mounted file system ${OLDMNT}${dir} to $dir."
#    mount --move ./${OLDMNT}${dir} ${dir}
#done
#
#echo "Trying to chroot."
#exec chroot . /bin/sh -c "umount ./$OLDMNT; cat /proc/mounts > /etc/mtab; exec /sbin/init" < /dev/console > /dev/console 2>&1
