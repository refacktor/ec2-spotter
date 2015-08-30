# About AWS EC2 Spot Instances

EC2 Spot Instances are cheaper than On Demand instances and even Reserved Instances.

BUT there are several challenges in trying to run a Spot Instance without completely rearchitecting
the underlying platform and applications: 
1) EC2 does not allow specifying an EBS volume as root of a Spot Instance, only an AMI image, which leads to the
creation of an EPHEMERAL (temporary) EBS volume, 2) Spot Instances cannot be Stopped, they can only be
Rebooted or Terminated, that exacerbates issue#1 as it means it's impossible to detach /dev/xvda1 and attach another
disk as the root device after the instance has launched, 3) Every time the instance is re-launched, a brand new EBS
volume is created from the AMI (see point#1 about the EBS being ephemeral), that breaks continuity from the previous EBS volume so things
like /var/log, crontab, apt-get updates, etc, are lost and basically they expect you to run a fully re-designed system that saves 
everything important somewhere else.


# ec2-spotter

EC2-Spotter is a utility that brings together the best of both worlds -- Spot Instance pricing with
the simplicity of On Demand & Reserved Instances. This sounds like cheating, but apparently is not
forbidden by the Amazon Terms Of Service.

# Running ec2-spotter

1. cd /root; git clone https://github.com/atramos/ec2-spotter.git
2. create /root/.aws.creds with your actual IAM credentials with EBS/EC2 privilege in this format:
AWSAccessKeyId=XXXXXXXXXXXXXXXXXXXX
AWSSecretKey=XXXXXXXXXXXXXXXXXXXXXXXXXX
3. create a bootable EBS volume (or borrow one from an On Demand instance)
4. launch the spot instance:
./ec2spotter-launch vol-XXXXXXXX

# How does it work?

It's quite simple, really. The scripts attach a specified EBS volume to /dev/xvdf as a 2nd disk, to be used as 
the system root filesystem. When the instance is first created or restarted following an interruption,
the /sbin/init on the AMI-based EBS volume (/dev/xvda1) is replaced with a small shell script which chain-loads the
/sbin/init from the specified persistent EBS volume (/dev/xvdf1). An extra reboot is performed when the
instance first comes up. The end-result is a full Linux system booted from and running on the 2nd, persitent disk,
instead of the 1st, ephemeral disk.

# Caveats

The instance boots using the kernel and initrd from /dev/xvda1, which is supplied by the AMI. Nothing is done
to ensure compatibility with the system that's present on the persistent EBS volume. You need to make sure they
are compatible, if not identical.  Currently the AMI ID is hard-coded in ec2spotter-launch and it is set to
Ubuntu 14.04 HVM 64-bit. This hasn't been tested with any other AMIs.
