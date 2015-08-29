# ec2-spotter

EC2-Spotter is a utility for running Spot Instances on persistent EBS root volumes.

Currently this is Work In Progress.

There is a surprising challenge in trying to get GRUB to boot off the 2nd disk (/dev/xvdf1)

# Running it

1. cd /root; git clone https://github.com/atramos/ec2-spotter.git
2. create /root/.aws.creds with your actual IAM credentials with EBS/EC2 privilege in this format:
AWSAccessKeyId=XXXXXXXXXXXXXXXXXXXX
AWSSecretKey=XXXXXXXXXXXXXXXXXXXXXXXXXX
3. create a bootable EBS volume (or borrow one from an On Demand instance)
4. launch the spot instance:
./ec2spotter-launch vol-XXXXXXXX
