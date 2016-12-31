# ec2-spotter 24x7

This folder contains the "24x7" High Availability version of ec2-spotter.

It works by cloning a base instance (on-demand or reserved) into a Spot Instance, and taking over its Elastic IP address.

When the Spot Instance is terminated, the Elastic IP address is reclaimed by the original base instance.

This is ideal for web or other servers which need to be up 24x7. It's not good for databases.

This code was in production use for a while at CTC.