# ec2-spotter 24x7

This folder contains the "24x7" High Availability version of ec2-spotter.

It provides mostly uninterrupted availability by automatically failing over between a (cheap) reserved instance and a (powerful) spot instance. This is ideal for web or other servers which need to be up 24x7 but can tolerate a performance hit during a spot instance rollover. It's not good for databases. 

This code was in production use for a while at CTC.

# Running ec2-spotter 24x7

1. Copy example.conf to $(hostname).conf and modify to your environment.

2. Install prereqs: AWS CLI and jq

3. Setup two crontab entries on the base machine:
* * * * * [ -f /etc/ec2spotter ] || spot /root/ec2-spotter/example.conf  
* * * * * [ -f /etc/ec2spotter ] && self-spot /root/ec2-spotter/example.conf  

The reason you need two crontab entries is that they will run on both the base (reserved) and the cloned (spot) machines, but need to do something different in each (spot the other instance, or spot itself).

# How does it work?

A crontab task is setup to run once every minute on the base instance and runs /root/ec2-spotter/spot. This "spot" script watches to ensure the spot instance is always running. 

If a spot instance is not running, 'spot' starts by cloning the base instance (on-demand or reserved) into a Spot Instance. The spot instance takes over the Elastic IP address on successful launch.

When the Spot Instance is terminated, the Elastic IP address is reclaimed by the original base instance (again, "spot" script kicks in).



