#!/usr/bin/python

# a stand-alone Python script to find the cheapest AWS EC2 Spot Instance types in a region,
# for a given minimum RAM and CPU
#
# usage: find-cheap.py [region] [ram] [cpu]

import sys
import boto3
import json
import pandas as pd
import math

region = sys.argv[1]
minMem = float(sys.argv[2])
minCpu = float(sys.argv[3])

client = boto3.client('ec2', region)
response = client.describe_spot_price_history()

sz = pd.read_csv('instance-sizes.csv')

df = pd.DataFrame(response['SpotPriceHistory'])
df = df[df.apply(lambda x: not(math.isnan(float(x['SpotPrice']))), axis=1)]
df['Monthly'] = df['SpotPrice'].astype(float) * 744
df.drop(['AvailabilityZone'], axis=1)

df = df.merge(sz, how='outer', on='InstanceType')
df = df[df.apply(lambda x: x['memory_gb'] >= minMem, axis=1)]
df = df[df.apply(lambda x: x['vcpu'] >= minCpu, axis=1)]
df = df.sort_values(by = 'SpotPrice')
df = df.head(20)

with pd.option_context('display.max_rows', None):
    print(df)