# This is the 'classic' implementation of ec2-spotter

This version has been rendered obsolete by AWS service enhancements made in 2017 and 2019.
The newer implementation which is in the project's main folder also has a different objective.

# Important News - 9/18/2017

Amazon EC2 Spot Can Now Stop and Start Your Spot Instances!

https://aws.amazon.com/about-aws/whats-new/2017/09/amazon-ec2-spot-can-now-stop-and-start-your-spot-instances/

The change is welcome but does not render ec2-spotter completely obsolete: use this project if you want more control over the starts and stops.

# About AWS EC2 Spot Instances (prior to 2017)

EC2 Spot Instances are cheaper than On Demand instances and even Reserved Instances.

BUT there are several challenges in trying to run a Spot Instance for "normal" Linux-based workloads: 

1. EC2 does not allow specifying an EBS volume as root of a Spot Instance, only an AMI image. 
2. Every time a Spot Instance is re-launched, a brand new EBS volume is created from the AMI (see point#1), which leads to the creation of a fresh new EBS volume wiped and restored from the AMI. [no longer true as of 9/18/2017]
3. Spot Instances cannot be Stopped, they can only be Rebooted or Terminated, that exacerbates issue#1 as it means it's impossible to simply reattach your original EBS volume to /dev/xvda. [as of 9/18/2017, Spot Instances can be stopped by AWS, but not the customer]
4. Important system information stored in /var/log, crontab, apt-get system files, etc, not to mention actual application config and data files, are LOST every time you restart a Spot Instance (directly caused by points #1 and #2 above).
5. A Spot Instance may be Terminated by AWS at any time, with only a 2-minute warning, whenever the dynamic pricing exceeds your hourly budget.
6. Essentially, the Spot Instance architecture requires a full redesign of your system to save everything of importance somewhere else (outside of the filesystem), but no Linux distribution exists which does this out of the box. [as of 9/18/2017 this is true only if you need the ability to stop spot instances outside of the AWS-controlled stop event]

# Introducing ec2-spotter

EC2-Spotter is a utility that brings together the best of both worlds -- Spot Instance pricing with
the simplicity (persistent EBS filesystem) of On Demand & Reserved Instances. This sounds like cheating, but apparently is not forbidden by the Amazon Terms Of Service.

# Notable Forks

If you have any issues with the 'classic' implementation, check out Slav Ivanov's fork at https://github.com/slavivanov/ec2-spotter - it is fully productionalized, including more exhaustive documentation and active discussion at his blog, while removing support for the '24x7' concept. 

# Commercial Alternatives

ElastiGroup (https://spotinst.com/products/elastigroup/) appears to cover a lot of the same ground as ec2spotter, and more, in a commercial offering. We have no relationship with the company offering ElastiGroup, and have not evaluated their product.

## ec2-spotter 'classic'

The 'classic' ec2-spotter was the first attempt at solving the problem of the "permanent spot instance".
It worked okay but is a little clunky and high maintenance (see Caveats section below).
The one advantage this solution has over the later ones, is that it doesn't require an external "watcher".
It relies on the builtin relaunch mechanism. 

## Running ec2-spotter

1) Get the scripts onto your "management workstation" (e.g. a throw-away On Demand t2.micro instance) and install the pre-requisites:

```
sudo su -
cd /root
git clone https://github.com/atramos/ec2-spotter.git
cd ec2-spotter
./ec2spotter-setup
```

2) Create `/root/.aws.creds` with your actual IAM credentials with EC2 privileges in this format:

```
AWSAccessKeyId=XXXXXXXXXXXXXXXXXXXX
AWSSecretKey=XXXXXXXXXXXXXXXXXXXXXXXXXX
```

3) Create a bootable EBS volume (or grab one from a stopped On Demand instance that you want to replace with a Spot Instance) and give it a unique Name (you can change the Name under the main 'Volumes' tab in the AWS Console or under Tags)

4) Edit the `example.conf` file, change the Volume Name to the value assigned in Step 3.

5) Launch the spot instance: 

```
./ec2spotter-launch example.conf
```

6) If you were using a throw-away On Demand instance as suggested in Step 1 to run the scripts, you may terminate or stop it now. It's no longer needed unless you want to maintain it as a central place for configuration.

## How does it work?

The launch script employs user-data to create a boot-time script that attaches the 
specified EBS volume to `/dev/xvdf` and then proceeds to do a `pivot_root` and `chroot` in order to use  it as 
the main system disk in place of `/dev/xvda`. When the instance is first created or restarted following an interruption,
the `/sbin/init` on the AMI-based EBS volume (`/dev/xvda1`) is replaced with a small shell script which performs the magic `pivot_root` and `chroot` and then chain-loads the `/sbin/init` from the specified persistent EBS volume (`/dev/xvdf1`). 
An extra reboot is performed when the instance first comes up, to ensure a clean slate. 
The end-result is a full Linux system running on the persistent volume `dev/xvdf` mounted as `/`.
The ephemeral disk remains mounted under `/old-root` and can be unmounted if needed.

## Caveats

The instance boots using the kernel and initrd from `/dev/xvda1`, which is supplied by the AMI. Nothing is done
to ensure compatibility with the system that's present on the persistent EBS volume. You need to make sure they
are compatible, if not identical.  The AMI ID supplied in the example.conf is Ubuntu 14.04 HVM 64-bit, and should
be changed to an AMI that has the same Kernel version as your target EBS system volume. This hasn't 
been tested with any other AMIs.
