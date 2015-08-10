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
require 'ec2/common/s3support'
require 'ec2/amitools/downloadbundleparameters'
require 'ec2/amitools/exception'
require 'ec2/amitools/manifestv20071010'
require 'getoptlong'
require 'net/http'
require 'rexml/document'
require 'ec2/amitools/tool_base'

# Download AMI downloads the specified AMI from S3.

#------------------------------------------------------------------------------#

DOWNLOAD_BUNDLE_NAME = 'ec2-download-bundle'
DOWNLOAD_BUNDLE_MANUAL =<<TEXT
#{DOWNLOAD_BUNDLE_NAME} is a command line tool to download a bundled Amazon Image from
S3 storage. An Amazon Image may be one of the following:
- Amazon Machine Image (AMI)
- Amazon Kernel Image (AKI)
- Amazon Ramdisk Image (ARI)

#{DOWNLOAD_BUNDLE_NAME} downloads and decrypts the manifest, then fetches all
the parts referenced in the manifest.
TEXT

class BundleDownloader < AMITool

  def download_manifest(s3_conn, bucket, manifest_name, manifest_path, privatekey, retry_download=false)
    $stdout.puts "Downloading manifest #{manifest_name} from #{bucket} to #{manifest_path} ..."
    download_file(s3_conn, bucket, manifest_name, manifest_path, retry_download)
    encrypted_manifest = File::open(manifest_path) { |f| f.read() }
    plaintext_manifest = nil
    if (encrypted_manifest !~ /^\s*<\?/)
      $stdout.puts "Decrypting manifest ..."
      plaintext_manifest = Crypto::decryptasym(encrypted_manifest, privatekey)
      File::open(manifest_path+'.plaintext', 'w') { |f| f.write(plaintext_manifest) }
    else
      plaintext_manifest = encrypted_manifest
    end
    plaintext_manifest
  end
  
  #----------------------------------------------------------------------------#
  
  def download_part(s3_conn, bucket, part, part_path, retry_download=false)
    $stdout.puts "Downloading part #{part} to #{part_path} ..."
    download_file(s3_conn, bucket, part, part_path, retry_download)
  end
  
  #----------------------------------------------------------------------------#
  
  def download_file(s3_conn, bucket, file, file_path, retry_download=false)
    retry_s3(retry_download) do
      begin
        s3_conn.get(bucket, file, file_path)
        return
      rescue => e
        raise TryFailed.new("Failed to download \"#{file}\": #{e.message}")
      end
    end
  end
  
  #----------------------------------------------------------------------------#
  
  def get_part_filenames(manifest_xml)
    manifest = ManifestV20071010.new(manifest_xml)
    manifest.parts.collect { |part| part.filename }.sort
  end

  #----------------------------------------------------------------------------#

  def uri2string( uri )
    s = "#{uri.scheme}://#{uri.host}:#{uri.port}#{uri.path}"
    # Remove the trailing '/'.
    return ( s[-1..-1] == "/" ? s[0..-2] : s )
  end

  #----------------------------------------------------------------------------#

  def make_s3_connection(s3_url, user, pass, bucket, sigv, region)
    s3_uri = URI.parse(s3_url)
    s3_url = uri2string(s3_uri)
    v2_bucket = EC2::Common::S3Support::bucket_name_s3_v2_safe?(bucket)
    EC2::Common::S3Support.new(s3_url, user, pass, (v2_bucket ? nil : :path), @debug, sigv, region)
  end

  #----------------------------------------------------------------------------#

  # Main method.
  def download_bundle(url,
                      user,
                      pass,
                      bucket,
                      keyprefix,
                      directory,
                      manifest,
                      privatekey,
                      retry_stuff,
                      sigv,
                      region)
    begin
      s3_conn = make_s3_connection(url, user, pass, bucket, sigv, region)
      # Download and decrypt manifest.
      manifest_path = File.join(directory, manifest)
      manifest_xml = download_manifest(s3_conn, bucket, keyprefix+manifest, manifest_path, privatekey, retry_stuff)
      
      # Download AMI parts.
      get_part_filenames(manifest_xml).each do |filename|
        download_part(s3_conn, bucket, keyprefix+filename, File::join(directory, filename), retry_stuff)
        $stdout.puts "Downloaded #{filename} from #{bucket}"
      end
    rescue EC2::Common::HTTP::Error => e
      $stderr.puts e.backtrace if @debug
      raise S3Error.new(e.message)
    end
  end

  #------------------------------------------------------------------------------#
  # Overrides
  #------------------------------------------------------------------------------#

  def get_manual()
    DOWNLOAD_BUNDLE_MANUAL
  end

  def get_name()
    DOWNLOAD_BUNDLE_NAME
  end

  def main(p)
    download_bundle(p.url,
                    p.user,
                    p.pass,
                    p.bucket,
                    p.keyprefix,
                    p.directory,
                    p.manifest,
                    p.privatekey,
                    p.retry,
                    p.sigv,
                    p.region)
  end

end

#------------------------------------------------------------------------------#
# Script entry point. Execute only if this file is being executed.
if __FILE__ == $0
  BundleDownloader.new().run(DownloadBundleParameters)
end
