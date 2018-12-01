#!/usr/bin/env python
# List EC2 Instance Types
# see: https://aws.amazon.com/blogs/aws/new-aws-price-list-api/
# Inspired by https://stackoverflow.com/questions/33120348/boto3-aws-api-listing-available-instance-types

import requests
import pandas as pd
import os.path
import json

if os.path.exists('ec2.json') == False:
    print("Downloading json file (this will take a very long time)")
    offers = requests.get(
        'https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/index.json'
    )
    ec2_offer_path = offers.json()['offers']['AmazonEC2']['currentVersionUrl']
    print(ec2_offer_path)
    ec2offer = requests.get(    
        'https://pricing.us-east-1.amazonaws.com%s' % ec2_offer_path
    ).text()
    
    with open('ec2.json', "w") as text_file:
        text_file.write(ec2offer)

else:
    
    with open('ec2.json', 'r') as text_file:
        ec2offer = text_file.read()

#for sku, data in json.loads(ec2offer)['products'].items():
#    if data['productFamily'] == 'Compute Instance':
#        new_df = pd.DataFrame.from_dict(data['attributes'], index=[0])
#        df.append(new_df, ignore_index=True)

data = json.loads(ec2offer)

d={}
for product in data['products'].keys():
    attr = data['products'][product]['attributes']
    if(data['products'][product]['productFamily'] == 'Compute Instance'):
        d[product]={}
        d[product]['InstanceType']=attr['instanceType']
        d[product]['memory_gb']=float(attr['memory'].split()[0].replace(',',''))
        d[product]['vcpu']=attr['vcpu']
        d[product]['network']=attr['networkPerformance']

df=pd.DataFrame(d).T.reset_index().drop('index',1)
df.drop_duplicates(inplace=True)

df.to_csv('instance-sizes.csv', index=False)
