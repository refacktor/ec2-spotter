#!/usr/bin/python

# a stand-alone Python script to find the cheapest AWS EC2 Spot Instance types in a region
#
# usage: find-cheapest.py [region]

import sys
import boto3
import json
import pandas as pd

region = sys.argv[1]
client = boto3.client('ec2', region)
response = client.describe_spot_price_history()

#print(response)

df = pd.DataFrame(response['SpotPriceHistory'])
df = df.sort_values(by = 'SpotPrice')
df = df.head(50)
df['Monthly'] = df['SpotPrice'].astype(float) * 744
print(df)
