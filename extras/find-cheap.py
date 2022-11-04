#!/usr/bin/python

# a stand-alone Python script to find the cheapest AWS EC2 Spot Instance types in a region,
# for a given minimum RAM and CPU
#
# usage: find-cheap.py [ram] [cpu] [regions...]

import sys
import boto3
import json
import pandas as pd
import math
import datetime

minMem = float(sys.argv[1])
minCpu = float(sys.argv[2])
regions = sys.argv[3:] or ['us-west-1', 'us-west-2', 'us-east-1', 'us-east-2']

history = []

for region in regions:
    print('Retrieving price history for %s' % region)
    client = boto3.client('ec2', region)
    response = {}

    while response == {} or response['NextToken']:
        response = client.describe_spot_price_history(
            **response,
            StartTime=datetime.datetime.now() - datetime.timedelta(hours=1)
        )
        history.extend(response['SpotPriceHistory'])
        response = {'NextToken': response['NextToken']}

sz = pd.read_csv('instance-types.csv')

df = pd.DataFrame(history)

df = df[df.apply(lambda x: not(math.isnan(float(x['SpotPrice']))), axis=1)]
df['Monthly'] = df['SpotPrice'].astype(float) * 744
df.drop(['AvailabilityZone'], axis=1)

df = df.merge(sz, how='outer', on='InstanceType')
df = df[df.apply(lambda x: x['memory_gb'] >= minMem, axis=1)]
df = df[df.apply(lambda x: x['vcpu'] >= minCpu, axis=1)]
df = df.sort_values(by = 'SpotPrice')
df = df.head(100)

with pd.option_context('display.max_rows', None):
    print(df)
