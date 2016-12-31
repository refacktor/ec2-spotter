# Copyright 2008-2014 Amazon.com, Inc. or its affiliates.  All Rights
# Reserved.  Licensed under the Amazon Software License (the
# "License").  You may not use this file except in compliance with the
# License. A copy of the License is located at
# http://aws.amazon.com/asl or in the "license" file accompanying this
# file.  This file is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See
# the License for the specific language governing permissions and
# limitations under the License.

# Module to hold region informations
#

module AwsRegion

  AWS_REGIONS = [
    'eu-west-1',
    'eu-central-1',
    'us-east-1',
    'us-gov-west-1',
    'cn-north-1',
    'us-west-1',
    'us-west-2',
    'ap-southeast-1',
    'ap-southeast-2',
    'ap-northeast-1',
    'sa-east-1',
  ]

  S3_LOCATIONS = [
    'EU', 'eu-west-1',
    'eu-central-1',
    'US',
    'us-gov-west-1',
    'cn-north-1',
    'us-west-1',
    'us-west-2',
    'ap-southeast-1',
    'ap-southeast-2',
    'ap-northeast-1',
    'sa-east-1',
  ]

  module_function

  def determine_region_from_host host
    # http://docs.aws.amazon.com/general/latest/gr/rande.html#s3_region
    if host == "s3.amazonaws.com" || host == "s3-external-1.amazonaws.com"
      "us-east-1"
    elsif
      domains = host.split(".")
      # handle s3-$REGION.amazonaws.something
      if domains.length >= 3 && domains[0].start_with?("s3-")
        domains[0].sub("s3-", "")
      # handle s3.$REGION.amazonaws.something, this is specific to the cn-north-1 endpoint
      elsif domains.length >= 3 && domains[0] == "s3"
        domains[1]
      else
        "us-east-1"
      end
    end
  end

  def guess_region_from_s3_bucket(location)
    if (location == "EU")
      return "eu-west-1"
    elsif ((location == "US") || (location == "") || (location.nil?))
      return "us-east-1"
    else 
      return location
    end
  end

  def get_s3_location(region)
    if (region == "eu-west-1")
      return 'EU'
    elsif (region == "us-east-1")
      return :unconstrained
    else
      return region
    end
  end

  def regions
    AWS_REGIONS
  end

  def s3_locations
    S3_LOCATIONS
  end

end

