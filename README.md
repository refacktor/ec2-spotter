# ec2-spotter 24x7

This folder contains the "24x7" High Availability version of ec2-spotter, which differs in both goals and implementation from the obsolete "classic" version.

This setup provides mostly uninterrupted availability by automatically failing over between a (cheap) reserved instance and a (powerful) spot instance, automatically managing Elastic IP Address reassignment as well as re-cloning the primary node every time a new spot instance is launched (to cut down on maintenance chores on applications that are not fully CI/CD'd). 

This configuration is good for web or other servers which need to be up 24x7 but can tolerate a performance hit during a spot instance roll-over and do not keep critical dynamic information on the local filesystem. It's not good for databases. 

This code was in production use for a while at CTC, until we migrated to Elastic Beanstalk. If EB is not a viable choice for your specific application, you may find `ec2-spotter` to be useful. 

## Basic Architecture

It's very simple. You have an application server running as a single-node, On-Demand or Reserved EC2 instance. Once you configure `ec2-spotter`, the base instance will clone itself onto a freshly launched Spot Instance, and will give its Elastic IP Address to the clone. The base instance will then watch the clone. When the clone dies, the base instance will reclaim the Elastic IP Address, then launch a new Spot Instance clone, rinse, repeat.

## What's the point of all this?

The idea is that you size your base instance a t3.nano Reserved Instance (costs around ~$3/month) and size the Spot Instance to something like a t3.xlarge (normally ~$120/month comes down to $20-$30/month with spot savings). The t3.xlarge becomes your primary server and the t3.nano will step in when the spot price spikes, which is an extremely rare occurrence.   

## Really? Is that how you run your cloud workloads?

Actually no, I recommend AWS Lambda, ECS, and Elastic Beanstalk for newly developed applications. `ec2-spotter` is more of a niche solution for applications that can't be ported to those modern platforms.

## Running ec2-spotter 24x7

1. Copy `example.conf` to `$(hostname).conf` and modify to your environment.

2. Install prereqs: AWS CLI and jq

3. Setup two crontab entries on the base machine:
	
	`* * * * * [ -f /etc/ec2spotter ] || spot /root/ec2-spotter/example.conf`  
	
	`* * * * * [ -f /etc/ec2spotter ] && self-spot /root/ec2-spotter/example.conf`  

The reason you need two crontab entries is that they will run on both the base (reserved) and the cloned (spot) machines, but need to do something different in each (spot the other instance, or spot itself).

## How does it work?

A crontab task is setup to run once every minute on the base instance and runs /root/ec2-spotter/spot. This "spot" script watches to ensure the spot instance is always running. 

If a spot instance is not running, 'spot' starts by cloning the base instance (on-demand or reserved) into a Spot Instance. The spot instance takes over the Elastic IP address on successful launch.

When the Spot Instance is terminated, the Elastic IP address is reclaimed by the original base instance (again, "spot" script kicks in).



