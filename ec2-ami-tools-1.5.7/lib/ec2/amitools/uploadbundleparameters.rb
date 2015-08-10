# Copyright 2008-2014 Amazon.com, Inc. or its affiliates.  All Rights
# Reserved.  Licensed under the Amazon Software License (the
# "License").  You may not use this file except in compliance with the
# License. A copy of the License is located at
# http://aws.amazon.com/asl or in the "license" file accompanying this
# file.  This file is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See
# the License for the specific language governing permissions and
# limitations under the License.

require 'ec2/amitools/s3toolparameters'
require 'ec2/amitools/region'

#------------------------------------------------------------------------------#

class UploadBundleParameters < S3ToolParameters

  MANIFEST_DESCRIPTION = "The path to the manifest file."
  ACL_DESCRIPTION = ["The access control list policy [\"public-read\" | \"aws-exec-read\"].",
                         "Defaults to \"aws-exec-read\"."]
  DIRECTORY_DESCRIPTION = ["The directory containing the bundled AMI parts to upload.",
                      "Defaults to the directory containing the manifest."]
  PART_DESCRIPTION = "Upload the specified part and upload all subsequent parts."
  RETRY_DESCRIPTION = "Automatically retry failed uploads."
  SKIP_MANIFEST_DESCRIPTION = "Do not upload the manifest."
  LOCATION_DESCRIPTION = "The location of the bucket to upload to [#{AwsRegion.s3_locations.join(',')}]."
  
  attr_accessor :manifest,
                :acl,
                :directory,
                :part,
                :retry,
                :skipmanifest,
                :location

  #----------------------------------------------------------------------------#

  def mandatory_params()
    super()
    
    on('-m', '--manifest PATH', String, MANIFEST_DESCRIPTION) do |manifest|
      assert_file_exists(manifest, '--manifest')
      @manifest = manifest
    end
  end

  #----------------------------------------------------------------------------#

  def optional_params()
    super()
    
    on('--acl ACL', String, *ACL_DESCRIPTION) do |acl|
      assert_option_in(acl, ['public-read', 'aws-exec-read'], '--acl')
      @acl = acl
    end
    
    on('-d', '--directory DIRECTORY', String, *DIRECTORY_DESCRIPTION) do |directory|
      assert_directory_exists(directory, '--directory')
      @directory = directory
    end
    
    on('--part PART', Integer, PART_DESCRIPTION) do |part|
      @part = part
    end
    
    on('--retry', RETRY_DESCRIPTION) do
      @retry = true
    end
    
    on('--skipmanifest', SKIP_MANIFEST_DESCRIPTION) do
      @skipmanifest = true
    end
    
    on('--location LOCATION', LOCATION_DESCRIPTION) do |location|
      assert_option_in(location, AwsRegion.s3_locations, '--location')
      @location = case location
        when "eu-west-1" then "EU"
        when "US" then :unconstrained
        else location
      end
    end
  end

  #----------------------------------------------------------------------------#

  def validate_params()
    super()
    raise MissingMandatory.new('--manifest') unless @manifest
  end

  #----------------------------------------------------------------------------#

  def set_defaults()
    super()
    @acl ||= 'aws-exec-read'
    @directory ||= File::dirname(@manifest)
    # If no location is given, set it equal to the region.
    # For legacy reasons if no location is given the location is set to US
    # If the region is us-east-1, we must not set the location. By not setting
    # the location S3 will default to the correct US location (which can't be
    # specified).
    if @region && !@location && !(@region == 'us-east-1')
      STDERR.puts "No location specified, setting location to conform with region: #{@region}"
      @location = @region
    end
  end

end
