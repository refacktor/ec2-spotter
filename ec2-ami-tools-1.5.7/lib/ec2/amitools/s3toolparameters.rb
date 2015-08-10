# Copyright 2008-2014 Amazon.com, Inc. or its affiliates.  All Rights
# Reserved.  Licensed under the Amazon Software License (the
# "License").  You may not use this file except in compliance with the
# License. A copy of the License is located at
# http://aws.amazon.com/asl or in the "license" file accompanying this
# file.  This file is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See
# the License for the specific language governing permissions and
# limitations under the License.

require 'ec2/common/constants'
require 'ec2/amitools/parameters_base'
require 'ec2/amitools/region'

#------------------------------------------------------------------------------#

class S3ToolParameters < ParametersBase

  BUCKET_DESCRIPTION = ["The bucket to use. This is an S3 bucket,",
                        "followed by an optional S3 key prefix using '/' as a delimiter."]
  MANIFEST_DESCRIPTION = "The path to the manifest file."
  DELEGATION_TOKEN_DESCRIPTION = "The delegation token pass along to the AWS request."
  URL_DESCRIPTION = "The S3 service URL. Defaults to https://s3.amazonaws.com."
  REGION_DESCRIPTION = "The S3 region. Defaults to us-east-1."
  SIGV2_DESCRIPTION = "Use old signature version 2 signing"
  PROFILE_PATH = '/latest/meta-data/iam/security-credentials/'
  PROFILE_HOST = '169.254.169.254'

  REGION_MAP = {
    'us-east-1' => 'https://s3.amazonaws.com',
    'us-west-2' => 'https://s3-us-west-2.amazonaws.com',
    'us-west-1' => 'https://s3-us-west-1.amazonaws.com',
    'eu-west-1' => 'https://s3-eu-west-1.amazonaws.com',
    'eu-central-1' => 'https://s3.eu-central-1.amazonaws.com',
    'ap-southeast-1' => 'https://s3-ap-southeast-1.amazonaws.com',
    'ap-southeast-2' => 'https://s3-ap-southeast-2.amazonaws.com',
    'ap-northeast-1' => 'https://s3-ap-northeast-1.amazonaws.com',
    'sa-east-1' => 'https://s3-sa-east-1.amazonaws.com',
    'cn-north-1' => 'https://s3.cn-north-1.amazonaws.com.cn',
    'us-gov-west-1' => 'https://s3-us-gov-west-1.amazonaws.com'
  }

  VALID_SIGV = ['2', '4']

  DEFAULT_URL = 'https://s3.amazonaws.com'
  DEFAULT_REGION = 'us-east-1'


  attr_accessor :bucket,
                :keyprefix,
                :user,      # This now contains all the creds.
                :pass,      # pass is just kept for backwards compatibility.
                :url,
                :region,
                :sigv

  #------------------------------------------------------------------------------#

  def split_container(container)
    splitbits = container.sub(%r{^/*},'').sub(%r{/*$},'').split("/")
    bucket = splitbits.shift
    keyprefix = splitbits.join("/")
    keyprefix += "/" unless keyprefix.empty?
    @keyprefix = keyprefix
    @bucket = bucket
  end
  
  #----------------------------------------------------------------------------#

  def mandatory_params()
    on('-b', '--bucket BUCKET', String, *BUCKET_DESCRIPTION) do |container|
      @container = container
      split_container(@container)
    end
    
    on('-a', '--access-key USER', String, USER_DESCRIPTION) do |user|
      @user = {} if @user.nil?
      @user['aws_access_key_id'] = user
    end
    
    on('-s', '--secret-key PASSWORD', String, PASS_DESCRIPTION) do |pass|
      @user = {} if @user.nil?
      @user['aws_secret_access_key'] = pass
      @pass = pass
    end
    
    on('-t', '--delegation-token TOKEN', String, DELEGATION_TOKEN_DESCRIPTION) do |token|
      @user = {} if @user.nil?
      @user['aws_delegation_token'] = token
    end
  end

  #----------------------------------------------------------------------------#

  def optional_params()
    on('--url URL', String, URL_DESCRIPTION) do |url|
      @url = url
    end

    on('--region REGION', REGION_DESCRIPTION) do |region|
      @region = region
    end

    on('--sigv VERSION', SIGV2_DESCRIPTION) do |version_number|
      @sigv = version_number
    end
  end

  #----------------------------------------------------------------------------#

  def get_creds_from_instance_profile
  end

  def get_creds_from_instance_profile
    begin
      require 'json'
      require 'net/http'
      profile_name = Net::HTTP.get(PROFILE_HOST, PROFILE_PATH)
      unless (profile_name.nil? || profile_name.strip.empty?)
        creds_blob = Net::HTTP.get(PROFILE_HOST, PROFILE_PATH + profile_name.strip)
        creds = JSON.parse(creds_blob)
        @user = {
          'aws_access_key_id' => creds['AccessKeyId'],
          'aws_secret_access_key' => creds['SecretAccessKey'],
          'aws_delegation_token' => creds['Token'],
        }
        @pass = creds['SecretAccessKey']
      end
    rescue Exception => e
      @user = nil
    end
  end

  def validate_params()
    unless @user
        get_creds_from_instance_profile
    end
    raise MissingMandatory.new('--access-key') unless @user && @user['aws_access_key_id']
    raise MissingMandatory.new('--secret-key') unless @pass
    raise MissingMandatory.new('--bucket') unless @container
    if @sigv && !VALID_SIGV.include?(@sigv)
      raise InvalidValue.new('--sigv', @sigv, "Please specify one of these values: #{VALID_SIGV.join(', ')}")
    end
  end

  #----------------------------------------------------------------------------#

  def set_defaults()
    # We need three values to be set after this point:
    #   region - which will specify the region of the endpoint used for sigv4
    #   url - the url of the endpoint
    #   location - the S3 bucket location
    #
    # We allow the user to override any of these values. The client only has
    # to specify the region value.
    if @region
      @url ||= REGION_MAP[@region]
    elsif @location
      @region = case @location
        when "EU" then "eu-west-1"
        when "US", :unconstrained then "us-east-1"
        else @location
      end
      @url ||= REGION_MAP[@region]
    elsif @url
      STDERR.puts "Specifying url has been deprecated, please use only --region"
      uri = URI.parse(@url)
      if @region.nil?
        begin
          @region = AwsRegion::determine_region_from_host uri.host
          STDERR.puts "Region determined to be #{@region}"
        rescue => e
          STDERR.puts "No region specified and could not determine region from given url"
          @region = nil
        end
      end
    else
      @url ||= DEFAULT_URL
      @region ||= DEFAULT_REGION
    end
    @sigv ||= EC2::Common::SIGV4
  end
end
