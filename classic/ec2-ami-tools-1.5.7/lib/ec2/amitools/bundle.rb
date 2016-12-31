# Copyright 2008-2014 Amazon.com, Inc. or its affiliates.  All Rights
# Reserved.  Licensed under the Amazon Software License (the
# "License").  You may not use this file except in compliance with the
# License. A copy of the License is located at
# http://aws.amazon.com/asl or in the "license" file accompanying this
# file.  This file is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See
# the License for the specific language governing permissions and
# limitations under the License.

require 'open-uri'
require 'ec2/amitools/fileutil'
require 'ec2/amitools/manifestv20071010'
require 'ec2/amitools/instance-data'
require 'ec2/amitools/version'
require 'ec2/platform/current'

# Module containing utility methods for bundling an AMI.
module Bundle
  class ImageType < String
    MACHINE = new 'machine'
    KERNEL  = new 'kernel'
    RAMDISK = new 'ramdisk'
    VOLUME  = new 'machine'
    def ==(o)
      self.object_id == o.object_id
    end
  end

  
  CHUNK_SIZE = 10 * 1024 * 1024 # 10 MB in bytes.

  def self.bundle_image( image_file,
                         user,
                         arch,
                         image_type,
                         destination,
                         user_private_key_path,
                         user_cert_path,
                         ec2_cert_path,
                         prefix,
                         optional_args,
                         debug = false,
                         inherit = true
                       )
    begin
      raise "invalid image-type #{image_type}" unless image_type.is_a? Bundle::ImageType
      # Create named pipes.
      digest_pipe = File::join('/tmp', "ec2-bundle-image-digest-pipe-#{$$}")
      File::delete(digest_pipe) if File::exist?(digest_pipe)
      unless system( "mkfifo #{digest_pipe}" )
        raise "Error creating named pipe #{digest_pipe}"
      end
      
      # If the prefix differs from the file name create a symlink
      # so that the file is tarred with the prefix name.
      if prefix and File::basename( image_file ) != prefix
        image_file_link = File::join( destination, prefix )
        begin
          FileUtils.ln_s(image_file, image_file_link)
        rescue Exception => e
          raise "Error creating symlink to image file, #{e.message}."
        end
        image_file = image_file_link
      end
      
      # Load and generate necessary keys.
      name = prefix || File::basename( image_file )
      manifest_file = File.join( destination, name + '.manifest.xml')
      bundled_file_path = File::join( destination, name + '.tar.gz.enc' )
      user_public_key = Crypto::certfile2pubkey( user_cert_path )
      ec2_public_key = Crypto::certfile2pubkey( ec2_cert_path )
      key = Format::bin2hex( Crypto::gensymkey )
      iv = Format::bin2hex( Crypto::gensymkey )
      
      # Bundle the AMI.
      # The image file is tarred - to maintain sparseness, gzipped for
      # compression and then encrypted with AES in CBC mode for
      # confidentiality.
      # To minimize disk I/O the file is read from disk once and
      # piped via several processes. The tee is used to allow a
      # digest of the file to be calculated without having to re-read
      # it from disk.
      tar = EC2::Platform::Current::Tar::Command.new.create.dereference.sparse
      tar.owner(0).group(0)
      tar.add(File::basename( image_file ), File::dirname( image_file ))
      openssl = EC2::Platform::Current::Constants::Utility::OPENSSL
      pipeline = EC2::Platform::Current::Pipeline.new('image-bundle-pipeline', debug)
      pipeline.concat([
        ['tar', "#{openssl} sha1 < #{digest_pipe} & " + tar.expand],
        ['tee', "tee #{digest_pipe}"],
        ['gzip', 'gzip -9'],
        ['encrypt', "#{openssl} enc -e -aes-128-cbc -K #{key} -iv #{iv} > #{bundled_file_path}"]
        ])
      digest = nil
      begin
        digest = pipeline.execute.split(/\s+/).last.strip
      rescue EC2::Platform::Current::Pipeline::ExecutionError => e
        $stderr.puts e.message
        exit 1
      end

      # Split the bundled AMI. 
      # Splitting is not done as part of the compress, encrypt digest
      # stream, so that the filenames of the parts can be easily
      # tracked. The alternative is to create a dedicated output
      # directory, but this leaves the user less choice.
      parts = Bundle::split( bundled_file_path, name, destination )
      
      # Sum the parts file sizes to get the encrypted file size.
      bundled_size = 0
      parts.each do |part|
        bundled_size += File.size( File.join( destination, part ) )
      end
      
      # Encrypt key and iv.
      padding = OpenSSL::PKey::RSA::PKCS1_PADDING
      user_encrypted_key = user_public_key.public_encrypt( key, padding )
      ec2_encrypted_key = ec2_public_key.public_encrypt( key, padding )
      user_encrypted_iv = user_public_key.public_encrypt( iv, padding )
      ec2_encrypted_iv = ec2_public_key.public_encrypt( iv, padding )

      # Digest parts.
      part_digest_list = Bundle::digest_parts( parts, destination )
      
      # Launch-customization data
      patch_in_instance_meta_data(image_type, optional_args) if inherit

      # Sanity-check block-device-mappings
      bdm = optional_args[:block_device_mapping]
      if bdm.is_a? Hash
        [ 'root', 'ami' ].each do |item|
          if bdm[item].to_s.strip.empty?
            $stdout.puts "Block-device-mapping has no '#{item}' entry. A launch-time default will be used."
          end
        end
      end
 
 
      # Create bundle manifest.
      $stdout.puts 'Creating bundle manifest...'
      manifest = ManifestV20071010.new()
      manifest.init(optional_args.merge({:name => name,
                     :user => user,
                     :image_type => image_type.to_s,
                     :arch => arch,
                     :reserved => nil,
                     :parts => part_digest_list,
                     :size => File::size( image_file ),
                     :bundled_size => bundled_size,
                     :user_encrypted_key => Format::bin2hex( user_encrypted_key ),
                     :ec2_encrypted_key => Format::bin2hex( ec2_encrypted_key ),
                     :cipher_algorithm => Crypto::SYM_ALG,
                     :user_encrypted_iv => Format::bin2hex( user_encrypted_iv ),
                     :ec2_encrypted_iv => Format::bin2hex( ec2_encrypted_iv ),
                     :digest => digest,
                     :digest_algorithm => Crypto::DIGEST_ALG,
                     :privkey_filename => user_private_key_path,
                     :kernel_id => optional_args[:kernel_id],
                     :ramdisk_id => optional_args[:ramdisk_id],
                     :product_codes => optional_args[:product_codes],
                     :ancestor_ami_ids => optional_args[:ancestor_ami_ids],
                     :block_device_mapping => optional_args[:block_device_mapping],
                     :bundler_name => EC2Version::PKG_NAME,
                     :bundler_version => EC2Version::PKG_VERSION,
                     :bundler_release  => EC2Version::PKG_RELEASE}))
      
      # Write out the manifest file.
      File.open( manifest_file, 'w' ) { |f| f.write( manifest.to_s ) }
      $stdout.puts 'Bundle manifest is %s' % manifest_file
    ensure
      # Clean up.
      if bundled_file_path and File.exist?( bundled_file_path )
        File.delete( bundled_file_path )
      end
      File::delete( digest_pipe ) if digest_pipe and File::exist?(digest_pipe)
      if image_file_link and File::exist?( image_file_link )
        File::delete( image_file_link )
      end
    end
  end

  def self.patch_in_instance_meta_data(image_type, optional_args)
    if (image_type == ImageType::VOLUME || image_type == ImageType::MACHINE )
      instance_data = EC2::InstanceData.new
      if !instance_data.instance_data_accessible
        raise "Error accessing instance data. If you are not bundling on an EC2 instance use --no-inherit." 
      else
        [
          [:ancestor_ami_ids,     instance_data.ancestor_ami_ids, Proc.new do |key, value|
            if (optional_args[key].nil?)
              ancestry = nil
              if value.nil? or value.to_s.empty?
                ancestry = []
              elsif value.is_a? Array
                ancestry = value
              else
                ancestry = [value]
              end
              ami_id = instance_data.ami_id
              $stdout.puts "Unable to read instance meta-data for ami-id" if ami_id.nil?
              ancestry << ami_id unless(ami_id.nil? or ancestry.include?(ami_id))
              optional_args[key] = ancestry if ancestry && ancestry.length > 0
            end
          end],
          [:kernel_id,            instance_data.kernel_id, nil],
          [:ramdisk_id,           instance_data.ramdisk_id, nil],
          [:product_codes,        instance_data.product_codes, nil],
          [:block_device_mapping, instance_data.block_device_mapping, nil],
        ].each do |key, value, block|
          begin
            if value.nil?
              $stdout.puts "Unable to read instance meta-data for #{key.to_s.gsub('_','-')}"
              block.call(key, value) if block
            else
              if block
                block.call(key, value)
              else
                optional_args[key] ||= value
              end
            end
          rescue
            $stdout.puts "Unable to set #{key.to_s.gsub('_','-')} from instance meta-data"
          end
        end
      end
    end
  end

  def self.split( filename, prefix, destination )
    $stdout.puts "Splitting #{filename}..."
    part_filenames = FileUtil::split(filename,
                                     prefix,
                                     CHUNK_SIZE,
                                     destination)
    part_filenames.each { |name| puts "Created #{name}" }
    part_filenames
  end
  
  def self.digest_parts( basenames, dir )
    $stdout.puts 'Generating digests for each part...'
    parts_digests = Array.new
    basenames.each do |basename|
      File.open(File.join(dir, basename)) do |f|
        parts_digests << [basename, Crypto.digest( f )]
      end
    end
    $stdout.puts 'Digests generated.'
    parts_digests
  end
end
