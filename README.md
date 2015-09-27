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

# How does it work?

The launch script employs user-data to create a boot-time script that attaches the 
specified EBS volume to `/dev/xvdf` and then proceeds to do a `pivot_root` and `chroot` in order to use  it as 
the main system disk in place of `/dev/xvda`. When the instance is first created or restarted following an interruption,
the `/sbin/init` on the AMI-based EBS volume (`/dev/xvda1`) is replaced with a small shell script which performs the magic `pivot_root` and `chroot` and then chain-loads the `/sbin/init` from the specified persistent EBS volume (`/dev/xvdf1`). 
An extra reboot is performed when the instance first comes up, to ensure a clean slate. 
The end-result is a full Linux system running on the persistent volume `dev/xvdf` mounted as `/`.
The ephemeral disk remains mounted under `/old-root` and can be unmounted if needed.

# Caveats

The instance boots using the kernel and initrd from `/dev/xvda1`, which is supplied by the AMI. Nothing is done
to ensure compatibility with the system that's present on the persistent EBS volume. You need to make sure they
are compatible, if not identical.  The AMI ID supplied in the example.conf is Ubuntu 14.04 HVM 64-bit, and should
be changed to an AMI that has the same Kernel version as your target EBS system volume. This hasn't 
been tested with any other AMIs.
