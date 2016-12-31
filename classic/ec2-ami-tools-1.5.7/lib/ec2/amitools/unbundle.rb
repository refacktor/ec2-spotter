# Copyright 2008-2014 Amazon.com, Inc. or its affiliates.  All Rights
# Reserved.  Licensed under the Amazon Software License (the
# "License").  You may not use this file except in compliance with the
# License. A copy of the License is located at
# http://aws.amazon.com/asl or in the "license" file accompanying this
# file.  This file is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See
# the License for the specific language governing permissions and
# limitations under the License.

require 'ec2/amitools/format'
require 'ec2/amitools/manifestv3'
require 'ec2/amitools/unbundleparameters'
require 'ec2/platform/current'
require 'ec2/amitools/tool_base'

UNBUNDLE_NAME = 'ec2-unbundle'

UNBUNDLE_MANUAL =<<TEXT
#{UNBUNDLE_NAME} extracts a filesystem image from a bundle AMI.

#{UNBUNDLE_NAME} will:
- read relevant information from the manifest file
- concatenate all the parts
- decrypt and uncompress the image
TEXT

class Unbundler < AMITool

  def unbundle(p)
    begin
      manifest_path = p.manifest_path
      src_dir = p.source
      dst_dir = p.destination
      
      digest_pipe = File::join( '/tmp', "ec2-unbundle-image-digest-pipe" )
      File::delete( digest_pipe ) if File::exist?( digest_pipe )
      unless system( "mkfifo #{digest_pipe}" )
        raise "error creating named pipe #{digest_pipe}"
      end
      
      # Load manifest and the user's private key.
      manifest = ManifestV3.new(File.open( manifest_path ) { |f| f.read() })
      pk = Crypto::loadprivkey( p.user_pk_path )
      
      # Extract key and IV from XML manifest.
      key = pk.private_decrypt(Format::hex2bin( manifest.user_encrypted_key))
      iv = pk.private_decrypt(Format::hex2bin( manifest.user_encrypted_iv))
      
      # Create a string of space separated part paths.
      part_files = manifest.parts.collect do |part| 
        File::join( src_dir, part.filename ) 
      end.join( ' ' )
      
      # Join, decrypt, decompress and untar.
      untar = EC2::Platform::Current::Tar::Command.new.extract.chdir(dst_dir)
      pipeline = EC2::Platform::Current::Pipeline.new('image-unbundle-pipeline', @debug)
      pipeline.concat([
                       ['cat', "openssl sha1 < #{digest_pipe} & cat #{part_files}"],
                       ['decrypt', "openssl enc -d -aes-128-cbc -K #{key} -iv #{iv}"],
                       ['gunzip', "gunzip"],
                       ['tee', "tee #{digest_pipe}"],
                       ['untar', untar.expand]
                      ])
      digest = nil
      begin
        digest = pipeline.execute.split(/\s+/).last.strip
      rescue EC2::Platform::Current::Pipeline::ExecutionError => e
        $stderr.puts e.message
      end
      
      # Verify digest.
      unless manifest.digest == digest
        raise "invalid digest, expected #{manifest.digest} received #{digest}"
      end
      
      puts "Unbundle complete."
      return 0
    ensure
      File::delete( digest_pipe ) if (digest_pipe && File::exist?( digest_pipe ))
    end
  end

  #------------------------------------------------------------------------------#
  # Overrides
  #------------------------------------------------------------------------------#

  def get_manual()
    UNBUNDLE_MANUAL
  end

  def get_name()
    UNBUNDLE_NAME
  end

  def main(p)
    unbundle(p)
  end

end

#------------------------------------------------------------------------------#
# Script entry point. Execute only if this file is being executed.

if __FILE__ == $0
  Unbundler.new().run(UnbundleParameters)
end
