# About AWS EC2 Spot Instances

EC2 Spot Instances are cheaper than On Demand instances and even Reserved Instances.

BUT there are several challenges in trying to run a Spot Instance for "normal" Linux-based workloads: 

1. EC2 does not allow specifying an EBS volume as root of a Spot Instance, only an AMI image. 
2. Every time a Spot Instance is re-launched, a brand new EBS volume is created from the AMI (see point#1), which leads to the creation of a fresh new EBS volume wiped and restored from the AMI. 
3. Spot Instances cannot be Stopped, they can only be Rebooted or Terminated, that exacerbates issue#1 as it means it's impossible to simply reattach your original EBS volume to /dev/xvda. 
4. Important system information stored in /var/log, crontab, apt-get system files, etc, not to mention actual application config and data files, are LOST every time you restart a Spot Instance (directly caused by points #1 and #2 above).
5. Essentially, the Spot Instance architecture requires a full redesign of your system to save everything of importance somewhere else (outside of the filesystem), but no Linux distribution exists which does this out of the box.

# Introducing ec2-spotter

EC2-Spotter is a utility that brings together the best of both worlds -- Spot Instance pricing with
the simplicity (persistent EBS filesystem) of On Demand & Reserved Instances. This sounds like cheating, but apparently is not forbidden by the Amazon Terms Of Service.

# Running ec2-spotter

The 24x7 version works differently from the 'classic' version, so check the respective sub-directory.

# How does it work?

See above.