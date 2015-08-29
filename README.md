# About AWS EC2 Spot Instances

EC2 Spot Instances are cheaper than On Demand instances and even Reserved Instances.

BUT there are several challenges in trying to run a Spot Instance without completely rearchitecting
the underlying platform and applications: 
1) the API does not allow specifying an EBS volume as root, only an AMI image, 2) Spot Instances cannot be stopped, they can only be
Rebooted or Terminated, that means it's impossible to detach /dev/xvda1 and attach another
disk after the machine is launched, 3) Every time the instance is relaunched, a brand new EBS
volume is created from the AMI, that breaks continuity from the previous EBS volume so things
like /var/log, crontab, etc, are lost. 4) An alternative would be to redesign Linux and make sure no important files are updated in the root
filesystem... that way they would not be lost... Meanwhile, there is this project.


# ec2-spotter

EC2-Spotter is a utility for running Spot Instances on persistent EBS root volumes, something which Amazon
does not enable by default, but is not forbidden by the Terms Of Service.

Currently this is Work In Progress.

There is a surprising challenge in trying to get GRUB to boot off the 2nd disk (/dev/xvdf1)

# Running ec2-spotter

1. cd /root; git clone https://github.com/atramos/ec2-spotter.git
2. create /root/.aws.creds with your actual IAM credentials with EBS/EC2 privilege in this format:
AWSAccessKeyId=XXXXXXXXXXXXXXXXXXXX
AWSSecretKey=XXXXXXXXXXXXXXXXXXXXXXXXXX
3. create a bootable EBS volume (or borrow one from an On Demand instance)
4. launch the spot instance:
./ec2spotter-launch vol-XXXXXXXX

# BUGS

Right now, it's not working. The instance hangs after reboot. Please help!
