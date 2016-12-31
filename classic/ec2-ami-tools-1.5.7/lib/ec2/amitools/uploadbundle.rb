# Copyright 2008-2014 Amazon.com, Inc. or its affiliates.  All Rights
# Reserved.  Licensed under the Amazon Software License (the
# "License").  You may not use this file except in compliance with the
# License. A copy of the License is located at
# http://aws.amazon.com/asl or in the "license" file accompanying this
# file.  This file is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See
# the License for the specific language governing permissions and
# limitations under the License.

require 'ec2/common/s3support'
require 'ec2/amitools/uploadbundleparameters'
require 'uri'
require 'ec2/amitools/instance-data'
require 'ec2/amitools/manifestv20071010'
require 'rexml/document'
require 'digest/md5'
require 'base64'
require 'ec2/amitools/tool_base'
require 'ec2/amitools/region'

#------------------------------------------------------------------------------#

UPLOAD_BUNDLE_NAME = 'ec2-upload-bundle'

UPLOAD_BUNDLE_MANUAL =<<TEXT
#{UPLOAD_BUNDLE_NAME} is a command line tool to upload a bundled Amazon Image to S3 storage 
for use by EC2. An Amazon Image may be one of the following:
- Amazon Machine Image (AMI)
- Amazon Kernel Image (AKI)
- Amazon Ramdisk Image (ARI)

#{UPLOAD_BUNDLE_NAME} will:
- create an S3 bucket to store the bundled AMI in if it does not already exist
- upload the AMI manifest and parts files to S3, granting specified privileges 
- on them (defaults to EC2 read privileges)

To manually retry an upload that failed, #{UPLOAD_BUNDLE_NAME} can optionally:
- skip uploading the manifest
- only upload bundled AMI parts from a specified part onwards
TEXT

#------------------------------------------------------------------------------#

class BucketLocationError < AMIToolExceptions::EC2FatalError
  def initialize(bucket, location, bucket_location)
    location = "US" if location == :unconstrained
    bucket_location = "US" if bucket_location == :unconstrained
    super(10, "Bucket \"#{bucket}\" already exists in \"#{bucket_location}\" and \"#{location}\" was specified.")
  end
end

#----------------------------------------------------------------------------#

# Upload the specified file.

class BundleUploader < AMITool

  def upload(s3_conn, bucket, key, file, acl, retry_upload)
    retry_s3(retry_upload) do
      begin
        md5 = get_md5(file)
        s3_conn.put(bucket, key, file, {"x-amz-acl"=>acl, "content-md5"=>md5})
        return
      rescue EC2::Common::HTTP::Error::PathInvalid => e
        raise FileNotFound(file)
      rescue => e
        raise TryFailed.new("Failed to upload \"#{file}\": #{e.message}")
      end
    end
  end

  #----------------------------------------------------------------------------#

  def get_md5(file)
    Base64::encode64(Digest::MD5::digest(File.open(file) { |f| f.read })).strip
  end

  #----------------------------------------------------------------------------#

  # 
  # Availability zone names are generally in the format => ${REGION}${ZONENUMBER}.
  # Examples being us-east-1b, us-east-1c, etc.
  #
  def get_availability_zone()
    instance_data = EC2::InstanceData.new
    instance_data.availability_zone
  end

  #----------------------------------------------------------------------------#

  # Return a list of bundle part filename and part number tuples from the manifest.
  def get_part_info(manifest)
    parts = manifest.ami_part_info_list.map do |part|
      [part['filename'], part['index']]
    end
    parts.sort
  end

  #------------------------------------------------------------------------------#

  def uri2string(uri)
    s = "#{uri.scheme}://#{uri.host}:#{uri.port}#{uri.path}"
    # Remove the trailing '/'.
    return (s[-1..-1] == "/" ? s[0..-2] : s)
  end

  #------------------------------------------------------------------------------#

  # Get the bucket's location.
  def get_bucket_location(s3_conn, bucket)
    begin
      response = s3_conn.get_bucket_location(bucket)
    rescue EC2::Common::HTTP::Error::Retrieve => e
      if e.code == 404
        # We have a "Not found" S3 response, which probably means the bucket doesn't exist.
        return nil
      end
      raise e
    end
    $stdout.puts "check_bucket_location response: #{response.body}" if @debug and response.text?
    docroot = REXML::Document.new(response.body).root
    bucket_location = REXML::XPath.first(docroot, '/LocationConstraint').text
    bucket_location ||= :unconstrained
  end

  #------------------------------------------------------------------------------#

  # Check if the bucket exists and is in an appropriate location.
  def check_bucket_location(bucket, bucket_location, location)
    if bucket_location.nil?
      # The bucket does not exist. Safe, but we need to create it.
      return false
    end
    if location.nil?
      # The bucket exists and we don't care where it is.
      return true
    end
    unless [bucket_location, AwsRegion.guess_region_from_s3_bucket(bucket_location)].include?(location)
      # The bucket isn't where we want it. This is a problem.
      raise BucketLocationError.new(bucket, location, bucket_location)
    end
    # The bucket exists and is in the right place.
    return true
  end

  #------------------------------------------------------------------------------#

  # Create the specified bucket if it does not exist.
  def create_bucket(s3_conn, bucket, bucket_location, location, retry_create)
    begin
      if check_bucket_location(bucket, bucket_location, location)
        return true
      end
      $stdout.puts "Creating bucket..."
      
      retry_s3(retry_create) do
        error = "Could not create or access bucket #{bucket}"
        begin
          rsp = s3_conn.create_bucket(bucket, location == :unconstrained ? nil : location)
        rescue EC2::Common::HTTP::Error::Retrieve => e
          error += ": server response #{e.message} #{e.code}" 
          raise TryFailed.new(e.message)
        rescue RuntimeError => e
          error += ": error message #{e.message}"
          raise e
        end
      end
    end
  end

  #------------------------------------------------------------------------------#

  # If we return true, we have a v2-compliant name.
  # If we return false, we wish to use a bad name.
  # Otherwise we quietly wander off to die in peace.
  def check_bucket_name(bucket)
    if EC2::Common::S3Support::bucket_name_s3_v2_safe?(bucket)
      return true
    end
    message = "The specified bucket is not S3 v2 safe (see S3 documentation for details):\n#{bucket}"
    if warn_confirm(message)
      # Assume the customer knows what he's doing.
      return false
    else
      # We've been asked to stop, so quietly wander off to die in peace.
      raise EC2StopExecution.new()
    end
  end

  # force v1 S3 addressing when using govcloud endpoint
  def check_govcloud_override(s3_url)
    if s3_url =~ /s3-us-gov-west-1/
      false
    else
      true
    end
  end

  #------------------------------------------------------------------------------#

  def get_region()
    zone = get_availability_zone()
    if zone.nil?
      return nil
    end
    # assume region names do not have a common naming scheme. Therefore we manually go through all known region names
    AwsRegion.regions.each do |region| 
      match = zone.match(region)
      if not match.nil?
        return region
      end
    end
    nil
  end

  # This is very much a best effort attempt. If in doubt, we don't warn.
  def cross_region?(location, bucket_location)

    # If the bucket exists, its S3 location is canonical.
    s3_region = bucket_location
    s3_region ||= location
    s3_region ||= :unconstrained

    region = get_region()

    if region.nil?
      # If we can't get the region, assume we're fine since there's
      # nothing more we can do.
      return false
    end

    return s3_region != AwsRegion.get_s3_location(region)
  end

  #------------------------------------------------------------------------------#

  def warn_about_migrating()
    message = ["You are bundling in one region, but uploading to another. If the kernel",
               "or ramdisk associated with this AMI are not in the target region, AMI",
               "registration will fail.",
               "You can use the ec2-migrate-manifest tool to update your manifest file",
               "with a kernel and ramdisk that exist in the target region.",
              ].join("\n")
    unless warn_confirm(message)
      raise EC2StopExecution.new()
    end
  end

  #------------------------------------------------------------------------------#

  def get_s3_conn(s3_url, user, pass, method, sigv, region=nil)
    EC2::Common::S3Support.new(s3_url, user, pass, method, @debug, sigv, region)
  end

  #------------------------------------------------------------------------------#
  
  #
  # Get parameters and display help or manual if necessary.
  #
  def upload_bundle(url,
                    bucket,
                    keyprefix,
                    user,
                    pass,
                    location,
                    manifest_file,
                    retry_stuff,
                    part,
                    directory,
                    acl,
                    skipmanifest,
                    sigv,
                    region)
    begin
      # Get the S3 URL.
      s3_uri = URI.parse(url)
      s3_url = uri2string(s3_uri)
      v2_bucket = check_bucket_name(bucket) and check_govcloud_override(s3_url)
      s3_conn = get_s3_conn(s3_url, user, pass, (v2_bucket ? nil : :path), sigv, region)

      # Get current location and bucket location.
      bucket_location = get_bucket_location(s3_conn, bucket)

      # Load manifest.
      xml = File.open(manifest_file) { |f| f.read }
      manifest = ManifestV20071010.new(xml)
      
      # If in interactive mode, warn when bundling a kernel into our AMI and we are uploading cross-region
      if interactive? and manifest.kernel_id and cross_region?(location, bucket_location)
        warn_about_migrating()
      end

      # Create storage bucket if required.
      create_bucket(s3_conn, bucket, bucket_location, location, retry_stuff)
      
      # Upload AMI bundle parts.
      $stdout.puts "Uploading bundled image parts to the S3 bucket #{bucket} ..."
      get_part_info(manifest).each do |part_info|
        if part.nil? or (part_info[1] >= part)
          path = File.join(directory, part_info[0])
          upload(s3_conn, bucket, keyprefix + part_info[0], path, acl, retry_stuff)
          $stdout.puts "Uploaded #{part_info[0]}"
        else
          $stdout.puts "Skipping #{part_info[0]}"
        end
      end
      
      # Encrypt and upload manifest.
      unless skipmanifest
        $stdout.puts "Uploading manifest ..."
        upload(s3_conn, bucket, keyprefix + File::basename(manifest_file), manifest_file, acl, retry_stuff)
        $stdout.puts "Uploaded manifest."
        $stdout.puts 'Manifest uploaded to: %s/%s' % [bucket, keyprefix + File::basename(manifest_file)]
      else
        $stdout.puts "Skipping manifest."
      end

      $stdout.puts 'Bundle upload completed.'
    rescue EC2::Common::HTTP::Error => e
      $stderr.puts e.backtrace if @debug
      raise S3Error.new(e.message)
    end
  end

  #------------------------------------------------------------------------------#
  # Overrides
  #------------------------------------------------------------------------------#

  def get_manual()
    UPLOAD_BUNDLE_MANUAL
  end

  def get_name()
    UPLOAD_BUNDLE_NAME
  end

  def main(p)
    upload_bundle(p.url,
                  p.bucket,
                  p.keyprefix,
                  p.user,
                  p.pass,
                  p.location,
                  p.manifest,
                  p.retry,
                  p.part,
                  p.directory,
                  p.acl,
                  p.skipmanifest,
                  p.sigv,
                  p.region)
  end

end

#------------------------------------------------------------------------------#
# Script entry point. Execute only if this file is being executed.
if __FILE__ == $0
  BundleUploader.new().run(UploadBundleParameters)
end
