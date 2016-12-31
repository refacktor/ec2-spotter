# ec2-spotter 'classic'

The 'classic' ec2-spotter was the first attempt at solving the problem of the "permanent spot instance".
It worked okay but is a little clunky and high maintenance (see Caveats section below).
The one advantage this solution has over the later ones, is that it doesn't require an external "watcher".
It relies on the builtin relaunch mechanism. 

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
