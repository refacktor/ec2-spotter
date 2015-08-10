#!/bin/sh

# from http://docs.aws.amazon.com/AWSEC2/latest/CommandLineReference/set-up-ami-tools.html

apt-get update -y && sudo apt-get install -y ruby unzip
wget http://s3.amazonaws.com/ec2-downloads/ec2-ami-tools.zip

mkdir -p /usr/local/ec2
unzip ec2-ami-tools.zip


