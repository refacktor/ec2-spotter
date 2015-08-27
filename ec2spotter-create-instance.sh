#!/bin/bash

ROOT_VOL=$1

export AWS_CREDENTIAL_FILE=/root/.aws.creds



aws ec2 request-spot-instances --spot-price 0.015 --type persistent --launch-specification file://spot-spec.json --region us-east-1
