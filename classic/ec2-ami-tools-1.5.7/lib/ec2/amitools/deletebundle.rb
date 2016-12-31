# Copyright 2008-2014 Amazon.com, Inc. or its affiliates.  All Rights
# Reserved.  Licensed under the Amazon Software License (the
# "License").  You may not use this file except in compliance with the
# License. A copy of the License is located at
# http://aws.amazon.com/asl or in the "license" file accompanying this
# file.  This file is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See
# the License for the specific language governing permissions and
# limitations under the License.

require 'ec2/amitools/crypto'
require 'ec2/amitools/exception'
require 'ec2/amitools/deletebundleparameters'
require 'net/https'
require 'rexml/document'
require 'tempfile'
require 'uri'
require 'ec2/common/s3support'
require 'ec2/amitools/tool_base'

DELETE_BUNDLE_NAME = 'ec2-delete-bundle'

#------------------------------------------------------------------------------#

DELETE_BUNDLE_MANUAL=<<TEXT
#{DELETE_BUNDLE_NAME} is a command line tool to delete a bundled Amazon Image from S3 storage.
An Amazon Image may be one of the following:
- Amazon Machine Image (AMI)
- Amazon Kernel Image (AKI)
- Amazon Ramdisk Image (ARI)

#{DELETE_BUNDLE_NAME} will delete a bundled AMI specified by either its manifest file or the
prefix of the bundled AMI filenames.

#{DELETE_BUNDLE_NAME} will:
- delete the manifest and parts from the s3 bucket
- remove the bucket if and only if it is empty and you request its deletion
TEXT

#------------------------------------------------------------------------------#

RETRY_WAIT_PERIOD = 5

#------------------------------------------------------------------------------#

class DeleteFileError < AMIToolExceptions::EC2FatalError
  def initialize(file, reason)
    super(5,"Could not delete file '#{file}': #{reason}")
  end
end

class BundleDeleter < AMITool
  #----------------------------------------------------------------------------#

  # Delete the specified file.
  def delete(bucket, key, retry_delete)
    retry_s3(retry_delete) do
      begin
        response = @s3_conn.delete(bucket, key)
        return if response.success?
        raise "HTTP DELETE returned #{response.code}"
      rescue => e
        raise TryFailed.new("Failed to delete \"#{key}\": #{e.message}")
      end
    end
  end

  #----------------------------------------------------------------------------#

  # Return a list of bundle part filenames from the manifest.
  def get_part_filenames(manifest)
    parts = []
    manifest_doc = REXML::Document.new(manifest).root
    REXML::XPath.each(manifest_doc, 'image/parts/part/filename/text()') do |part|
      parts << part.to_s
    end
    return parts
  end

  #------------------------------------------------------------------------------#

  def uri2string(uri)
    s = "#{uri.scheme}://#{uri.host}:#{uri.port}#{uri.path}"
    # Remove the trailing '/'.
    return (s[-1..-1] == "/" ? s[0..-2] : s)
  end

  #------------------------------------------------------------------------------#

  def get_file_list_from_s3(bucket, keyprefix, prefix)
    s3prefix = keyprefix+prefix
    files_to_delete = []
    response = @s3_conn.list_bucket(bucket, s3prefix)
    unless response.success?
      raise "unable to list contents of bucket #{bucket}: HTTP #{response.code} response: #{response.body}"
    end
    REXML::XPath.each(REXML::Document.new(response.body), "//Key/text()") do |entry|
      entry = entry.to_s
      if entry[0,s3prefix.length] == s3prefix
        test_str = entry[(s3prefix.length)..-1]
        if (test_str =~ /^\.part\.[0-9]+$/ or
            test_str =~ /^\.manifest(\.xml)?$/)
          files_to_delete << entry[(keyprefix.length)..-1]
        end
      end
    end
    files_to_delete
  end

  #------------------------------------------------------------------------------#
  
  def make_s3_connection(s3_url, user, pass, method, sigv, region)
    EC2::Common::S3Support.new(s3_url, user, pass, method, @debug, sigv, region)
  end

  #------------------------------------------------------------------------------#
  
  def delete_bundle(url, bucket, keyprefix, user, pass, manifest, prefix, yes, clear, retry_stuff, sigv, region)
    begin
      # Get the S3 URL.
      s3_uri = URI.parse(url)
      s3_url = uri2string(s3_uri)
      retry_delete = retry_stuff
      v2_bucket = EC2::Common::S3Support::bucket_name_s3_v2_safe?(bucket)
      @s3_conn = make_s3_connection(s3_url, user, pass, (v2_bucket ? nil : :path), sigv, region)
      
      files_to_delete = []
      
      if manifest
        # Get list of files to delete from the AMI manifest.
        xml = String.new
        manifest_path = manifest
        File.open(manifest_path) { |f| xml << f.read }
        files_to_delete << File::basename(manifest)
        get_part_filenames( xml ).each do |part_info|
          files_to_delete << part_info
        end
      else
        files_to_delete = get_file_list_from_s3(bucket, keyprefix, prefix)
      end
      
      if files_to_delete.empty?
        $stdout.puts "No files to delete."
      else
        $stdout.puts "Deleting files:"
        files_to_delete.each { |file| $stdout.puts("   - #{file}") }
        continue = yes
        unless continue
          begin
            $stdout.print "Continue [y/N]: "
            $stdout.flush
            Timeout::timeout(PROMPT_TIMEOUT) do
              continue = gets.strip =~ /^y/i
            end
          rescue Timeout::Error
            $stdout.puts "\nNo response given, skipping the files."
            continue = false
          end
        end
        if continue
          files_to_delete.each do |file|
            delete(bucket, keyprefix+file, retry_delete)
            $stdout.puts "Deleted #{file}"
          end
        end
      end
      
      if clear
        $stdout.puts "Attempting to delete bucket #{bucket}..."
        @s3_conn.delete(bucket)
      end
    rescue EC2::Common::HTTP::Error => e
      $stderr.puts e.backtrace if @debug
      raise S3Error.new(e.message)
    end  
    $stdout.puts "#{DELETE_BUNDLE_NAME} complete."
  end

  #------------------------------------------------------------------------------#
  # Overrides
  #------------------------------------------------------------------------------#

  def get_manual()
    DELETE_BUNDLE_MANUAL
  end

  def get_name()
    DELETE_BUNDLE_NAME
  end

  def main(p)
    delete_bundle(p.url,
                  p.bucket,
                  p.keyprefix,
                  p.user,
                  p.pass,
                  p.manifest,
                  p.prefix,
                  p.yes,
                  p.clear,
                  p.retry,
                  p.sigv,
                  p.region)
  end

end

#------------------------------------------------------------------------------#
# Script entry point. Execute only if this file is being executed.
if __FILE__ == $0
  BundleDeleter.new().run(DeleteBundleParameters)
end
