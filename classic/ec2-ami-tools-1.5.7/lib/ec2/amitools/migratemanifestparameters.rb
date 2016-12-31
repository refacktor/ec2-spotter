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
require 'ec2/amitools/region'
require 'ec2/platform/current'

#------------------------------------------------------------------------------#

class MigrateManifestParameters < ParametersBase
  include EC2::Platform::Current::Constants

  MANIFEST_DESCRIPTION = "The path to the manifest file."
  DIRECTORY_DESCRIPTION = ["The directory containing the bundled AMI parts to upload.",
                      "Defaults to the directory containing the manifest."]
  EC2_CERT_PATH_DESCRIPTION = ['The path to the EC2 X509 public key certificate bundled into the AMI.',
                               "Defaults to the certificate of the region (usually '#{Bundling::EC2_X509_CERT}')."]
  KERNEL_DESCRIPTION = "Kernel id to bundle into the AMI."
  RAMDISK_DESCRIPTION = "Ramdisk id to bundle into the AMI."
  USER_DESCRIPTION = "The user's AWS access key ID."
  PASS_DESCRIPTION = "The user's AWS secret access key."
  NO_MAPPING_DESCRIPTION = "Do not perform automatic mappings."
  REGION_DESCRIPTION = "Region to look up in the mapping file."
  
  attr_accessor :user_pk_path,
                :user_cert_path,
                :user,
                :pass,
                :ec2_cert_path,
                :manifest_path,
                :kernel_id,
                :ramdisk_id,
                :use_mapping,
                :region
    
  #----------------------------------------------------------------------------#

  def mandatory_params()
    on('-c', '--cert PATH', String, USER_CERT_PATH_DESCRIPTION) do |path|
      assert_file_exists(path, '--cert')
      @user_cert_path = path
    end
    
    on('-k', '--privatekey PATH', String, USER_PK_PATH_DESCRIPTION) do |path|
      assert_file_exists(path, '--privatekey')
      @user_pk_path = path
    end

    on('-m', '--manifest PATH', String, MANIFEST_DESCRIPTION) do |manifest|
      assert_file_exists(manifest, '--manifest')
      @manifest_path = manifest
    end
  end

  #----------------------------------------------------------------------------#

  def optional_params()
    on('-a', '--access-key USER', String, USER_DESCRIPTION) do |user|
      @user = user
    end
    
    on('-s', '--secret-key PASSWORD', String, PASS_DESCRIPTION) do |pass|
      @pass = pass
    end
    
    on('--ec2cert PATH', String, *EC2_CERT_PATH_DESCRIPTION) do |path|
      assert_file_exists(path, '--ec2cert')
      @ec2_cert_path = path
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

  #----------------------------------------------------------------------------#

  def validate_params()
    raise MissingMandatory.new('--manifest') unless @manifest_path
    raise MissingMandatory.new('--cert') unless @user_cert_path
    raise MissingMandatory.new('--privatekey') unless @user_pk_path
    @use_mapping = true if @use_mapping.nil? # False is different.
    if @use_mapping
      raise ParameterExceptions::Error.new('If using automatic mapping, --region must be provided.') unless @region
      raise ParameterExceptions::Error.new('If using automatic mapping, --access-key must be provided.') unless @user
      raise ParameterExceptions::Error.new('If using automatic mapping, --secret-key must be provided.') unless @pass
    end
  end

  #----------------------------------------------------------------------------#

  def set_defaults()
    @ec2_cert_path ||= case
      when (@region=="us-gov-west-1") then Bundling::EC2_X509_GOV_CERT
      when (@region=="cn-north-1") then Bundling::EC2_X509_CN_NORTH_1_CERT
      else Bundling::EC2_X509_CERT
    end
  end
end
