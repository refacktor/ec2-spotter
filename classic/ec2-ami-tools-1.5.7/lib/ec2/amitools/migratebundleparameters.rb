# Copyright 2008-2014 Amazon.com, Inc. or its affiliates.  All Rights
# Reserved.  Licensed under the Amazon Software License (the
# "License").  You may not use this file except in compliance with the
# License. A copy of the License is located at
# http://aws.amazon.com/asl or in the "license" file accompanying this
# file.  This file is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See
# the License for the specific language governing permissions and
# limitations under the License.

require 'ec2/amitools/parameters_base'
require 'ec2/platform/current'
require 'ec2/amitools/region'

#------------------------------------------------------------------------------#

class MigrateBundleParameters < ParametersBase
  include EC2::Platform::Current::Constants

  MANIFEST_DESCRIPTION = "The name the manifest file."
  DIRECTORY_DESCRIPTION = ["The directory containing the bundled AMI parts to upload.",
                           "Defaults to the directory containing the manifest."]
  USER_CERT_PATH_DESCRIPTION = "The path to the user's PEM encoded RSA public key certificate file."
  USER_PK_PATH_DESCRIPTION = "The path to the user's PEM encoded RSA private key file."
  EC2_CERT_PATH_DESCRIPTION = ['The path to the EC2 X509 public key certificate bundled into the AMI.',
                               "Defaults to '#{Bundling::EC2_X509_CERT}'."]
  KERNEL_DESCRIPTION = "Kernel id to bundle into the AMI."
  RAMDISK_DESCRIPTION = "Ramdisk id to bundle into the AMI."
  DEST_BUCKET_DESCRIPTION = "The bucket to copy bundle to. Created if nonexistent."
  BUCKET_DESCRIPTION = "The bucket containing the AMI to be migrated."
  USER_DESCRIPTION = "The user's AWS access key ID."
  PASS_DESCRIPTION = "The user's AWS secret access key."
  ACL_DESCRIPTION = ["The access control list policy [\"public-read\" | \"aws-exec-read\"].",
                     "Defaults to \"aws-exec-read\"."]
  URL_DESCRIPTION = "The S3 service URL. Defaults to https://s3.amazonaws.com."
  RETRY_DESCRIPTION = "Automatically retry failed uploads. Use with caution."
  LOCATION_DESCRIPTION = "The location of the bucket to upload to [#{AwsRegion.regions.join(',')}]."
  NO_MAPPING_DESCRIPTION = "Do not perform automatic mappings."
  REGION_DESCRIPTION = "Region to look up in the mapping file."

  attr_accessor :user_pk_path,
                :user_cert_path,
                :ec2_cert_path,
                :user,
                :pass,
                :kernel_id,
                :ramdisk_id,
                :s3_url,
                :bucket,
                :keyprefix,
                :dest_bucket,
                :dest_keyprefix,
                :manifest_name,
                :location,
                :acl,
                :retry,
                :use_mapping,
                :region
  
  def split_container(container)
    splitbits = container.sub(%r{^/*},'').sub(%r{/*$},'').split("/")
    bucket = splitbits.shift
    keyprefix = splitbits.join("/")
    keyprefix += "/" unless keyprefix.empty?
    [bucket, keyprefix]
  end

  def mandatory_params()
    on('-c', '--cert PATH', String, USER_CERT_PATH_DESCRIPTION) do |path|
      assert_file_exists(path, '--cert')
      @user_cert_path = path
    end
    
    on('-k', '--privatekey PATH', String, USER_PK_PATH_DESCRIPTION) do |path|
      assert_file_exists(path, '--privatekey')
      @user_pk_path = path
    end
    
    on('-m', '--manifest NAME', String, MANIFEST_DESCRIPTION) do |manifest|
      raise InvalidValue.new("--manifest", manifest) unless manifest =~ /\.manifest\.xml$/
      assert_good_key(manifest, '--manifest')
      @manifest_name = manifest
    end
    
    on('-b', '--bucket BUCKET', String, BUCKET_DESCRIPTION) do |container|
      @container = container
      @bucket, @keyprefix = split_container(@container)
    end
    
    on('-d', '--destination-bucket BUCKET', String, DEST_BUCKET_DESCRIPTION) do |dest_container|
      @dest_container = dest_container
      @dest_bucket, @dest_keyprefix = split_container(@dest_container)
    end
    
    on('-a', '--access-key USER', String, USER_DESCRIPTION) do |user|
      @user = user
    end
    
    on('-s', '--secret-key PASSWORD', String, PASS_DESCRIPTION) do |pass|
      @pass = pass
    end
  end
  
  def optional_params()
    on('--ec2cert PATH', String, *EC2_CERT_PATH_DESCRIPTION) do |path|
      assert_file_exists(path, '--ec2cert')
      @ec2_cert_path = path
    end
    
    on('--acl ACL', String, *ACL_DESCRIPTION) do |acl|
      raise InvalidValue.new('--acl', acl) unless ['public-read', 'aws-exec-read'].include?(acl)
      @acl = acl
    end

    on('--url URL', String, URL_DESCRIPTION) do |url|
      @s3_url = url
    end

    on('--retry', RETRY_DESCRIPTION) do
      @retry = true
    end
    
    on('--location LOCATION', LOCATION_DESCRIPTION) do |location|
      assert_option_in(location, AwsRegion.s3_locations, '--location')
      @location = case location
        when "eu-west-1" then "EU"
        when "US" then :unconstrained
        else location
      end
    end
    
    on('--kernel KERNEL_ID', String, KERNEL_DESCRIPTION) do |kernel_id|
      @kernel_id = kernel_id
    end
    
    on('--ramdisk RAMDISK_ID', String, RAMDISK_DESCRIPTION) do |ramdisk_id|
      @ramdisk_id = ramdisk_id
    end
    
    on('--no-mapping', String, NO_MAPPING_DESCRIPTION) do
      @use_mapping = false
    end

    on('--region REGION', String, REGION_DESCRIPTION) do |region|
      @region = region
    end
  end

  def validate_params()
    raise MissingMandatory.new('--manifest') unless @manifest_name
    raise MissingMandatory.new('--cert') unless @user_cert_path
    raise MissingMandatory.new('--privatekey') unless @user_pk_path
    raise MissingMandatory.new('--bucket') unless @container
    raise MissingMandatory.new('--destination-bucket') unless @dest_container
    raise MissingMandatory.new('--access-key') unless @user
    raise MissingMandatory.new('--secret-key') unless @pass
  end

  def set_defaults()
    @acl ||= 'aws-exec-read'
    @s3_url ||= 'https://s3.amazonaws.com'
    @ec2_cert_path ||= Bundling::EC2_X509_CERT
    @use_mapping = true if @use_mapping.nil? # False is different.
  end

  def help()
    s = "*** This tool is deprecated. ***\n"
    s += "Please consider using ec2-migrate-image from the EC2 API tools.\n"
    s += "You can download the EC2 API tools here:\n"
    s += "http://aws.amazon.com/developertools/351\n"
    s += super()
  end
end
