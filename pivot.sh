#!/bin/bash
export AWS_CREDENTIAL_FILE=/root/.aws.creds

export AMIBIN=./ec2-ami-tools-*/bin
export APIBIN=./ec2-api-tools-*/bin

export EC2_HOME=$(ls -d ./ec2-api-tools-*)

export JAVA_HOME=/usr/lib/jvm/default-java
export ARCH=`uname -i`

export INSTANCE_ID=`curl -s http://169.254.169.254/latest/meta-data/instance-id`
export AVAIL_ZONE=`curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone`
export DEST_REGION=${AVAIL_ZONE::-1} # Get the region by stripping the last character of the AVAIL_ZONE

SOURCE_REGION=$DEST_REGION # By default, we're in the same region
TAG_KEY="Name"
TAG_VALUE="ubuntu"

# Check S3 to see if we have updated configuration settings
# By default, we expect a bucket called ec2-spotter-config, and a config file to override the above 3 settings
# called ec2-spotter.ini
# NOTE: us-east-1 is the only endpoint for S3 that has no location constraint
# See here: http://docs.aws.amazon.com/general/latest/gr/rande.html#s3_region
if aws s3 --endpoint us-east-1 cp s3://ec2-spotter-config/ec2-spotter.ini  . ; then
    . ec2-spotter.ini
fi

echo "Looking for a volume in $SOURCE_REGION with tags ${TAG_KEY} = ${TAG_VALUE}"
SOURCE_VOLUME=$(${APIBIN}/ec2-describe-tags --region ${SOURCE_REGION} --filter "resource-type=volume" --filter "key=${TAG_KEY}" --filter "value=${TAG_VALUE}" | awk '{print $3}' | head -1)

[[ -z $SOURCE_VOLUME ]] && echo "*** ERROR: No source volume found with tags ${TAG_KEY} = ${TAG_VALUE}" && exit 1

PIVOT_VOLUME=${SOURCE_VOLUME}

# Are we copying the volume from the same region?
if [[ $SOURCE_REGION != $DEST_REGION ]]; then
    # need to copy the volume across
    echo "Volume $SOURCE_VOLUME is in another region"
    echo "Creating a snapshot of the volume"
    SNAPSHOT=$(${APIBIN}/ec2-create-snapshot --region ${SOURCE_REGION} $SOURCE_VOLUME | awk '{print $2}')
    
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
    
    # Copy the snapshot
    NEW_SNAPSHOT=$(${APIBIN}/ec2-copy-snapshot -r ${SOURCE_REGION} -s ${SNAPSHOT} | awk '{print $2}')
    
    echo "Copying snapshot from $SOURCE_REGION to $DEST_REGION with name $NEW_SNAPSHOT. Waiting for completion"
    
    # Keep checking to see that snapshot has been copied
    count=0
    while /bin/true
    do
        sleep 30
        eval count=$((count+30))
        echo "... $count seconds gone. Still waiting..."
        STATUS=$(${APIBIN}/ec2-describe-snapshots ${NEW_SNAPSHOT} | grep completed)

        [[ ! -z $STATUS ]] && break
    done

    echo "Snapshot $NEW_SNAPSHOT created successfully"
    echo "------------------------------------------------"
    echo ""

    # create volume from this new snapshot
    NEW_VOLUME=$(${APIBIN}/ec2-create-volume --snapshot ${NEW_SNAPSHOT} -z ${AVAIL_ZONE} | awk '{print $2}')
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
fi

echo ""
echo "Attaching volume $PIVOT_VOLUME as /dev/sdj"
# Attach volume
${APIBIN}/ec2-attach-volume $PIVOT_VOLUME -d /dev/sdj

DEVICE=/dev/xvdj1
NEWMNT=/new-root
OLDMNT=old-root

echo "Mounting $DEVICE ON $NEWMNT"
mount $DEVICE $NEWMNT

[ ! -d $NEWMNT/$OLDMNT ] && echo "Creating directory $NEWMNT/$OLDMNT." && mkdir -p $NEWMNT/$OLDMNT

echo "Trying to pivot."
cd $NEWMNT
pivot_root . ./$OLDMNT

for dir in /dev /proc /sys /run; do
    echo "Moving mounted file system ${OLDMNT}${dir} to $dir."
    mount --move ./${OLDMNT}${dir} ${dir}
done

echo "Trying to chroot."
exec chroot . /bin/sh -c "umount ./$OLDMNT; cat /proc/mounts > /etc/mtab; exec /sbin/init" < /dev/console > /dev/console 2>&1