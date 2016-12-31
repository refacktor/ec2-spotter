# Copyright 2008-2014 Amazon.com, Inc. or its affiliates.  All Rights
# Reserved.  Licensed under the Amazon Software License (the
# "License").  You may not use this file except in compliance with the
# License. A copy of the License is located at
# http://aws.amazon.com/asl or in the "license" file accompanying this
# file.  This file is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See
# the License for the specific language governing permissions and
# limitations under the License.

require 'ec2/amitools/migratemanifestparameters'
require 'ec2/amitools/manifest_wrapper'
require 'fileutils'
require 'csv'
require 'net/http'
require 'ec2/amitools/tool_base'
require 'ec2/amitools/mapids'

MIGRATE_MANIFEST_NAME = "ec2-migrate-manifest"

MIGRATE_MANIFEST_MANUAL =<<TEXT
#{MIGRATE_MANIFEST_NAME} is a command line tool to assist with migrating AMIs to new regions.

#{MIGRATE_MANIFEST_NAME} will:
- automatically replace kernels and ramdisks with replacements suitable for a
  particular target region
- optionally replace kernels and ramdisks with user-specified replacements

TEXT

class BadManifestError < RuntimeError
  def initialize(manifest, msg)
    super("Bad manifest '#{manifest}': #{msg}")
  end
end

class ManifestMigrator < AMITool
  include EC2::Platform::Current::Constants
  
  def get_manifest(manifest_path, user_cert_path)
    unless File::exists?(manifest_path)
      raise BadManifestError.new(manifest_path, "File not found.")
    end
    begin
      manifest = ManifestWrapper.new(File.open(manifest_path).read())
    rescue ManifestWrapper::InvalidManifest => e
      raise BadManifestError.new(manifest_path, e.message)
    end
    unless manifest.authenticate(File.open(user_cert_path))
      raise BadManifestError.new(manifest_path, "Manifest fails authentication.")
    end
    manifest
  end

  #----------------------------------------------------------------------------#

  def get_mappings(*args)
    KernelMappings.new(*args)
  end

  #----------------------------------------------------------------------------#

  def map_identifiers(manifest, user, pass, region, kernel_id=nil, ramdisk_id=nil)
    if region.nil?
      raise EC2FatalError.new(1, "No region provided, cannot map automatically.")
    end
    if manifest.kernel_id.nil? and manifest.ramdisk_id.nil?
      # Exit early if we have nothing to do
      return [kernel_id, ramdisk_id]
    end

    begin
      mappings = get_mappings(user, pass, [manifest.kernel_id, manifest.ramdisk_id].compact, region)
    rescue KernelMappings::MappingError => e
      raise EC2FatalError.new(7, e.message)
    end

    begin
      if manifest.kernel_id
        kernel_id ||= mappings[manifest.kernel_id]
      end
      if manifest.ramdisk_id
        ramdisk_id ||= mappings[manifest.ramdisk_id]
      end
      warn_about_mappings(mappings.find_missing_targets([kernel_id, ramdisk_id].compact))
    rescue KernelMappings::MappingError => e
      raise EC2FatalError.new(6, e.message)
    end
    [kernel_id, ramdisk_id]
  end

  #----------------------------------------------------------------------------#

  def backup_manifest(manifest_path, quiet=false)
    backup_manifest = "#{manifest_path}.bak"
    if File::exists?(backup_manifest)
      raise EC2FatalError.new(2, "Backup file '#{backup_manifest}' already exists. Please delete or rename it and try again.")
    end
    $stdout.puts("Backing up manifest...") unless quiet
    $stdout.puts("Backup manifest at #{backup_manifest}") if @debug
    FileUtils::copy(manifest_path, backup_manifest)
  end

  #----------------------------------------------------------------------------#

  def build_migrated_manifest(manifest, user_pk_path, kernel_id=nil, ramdisk_id=nil)
    new_manifest = ManifestV20071010.new()
    manifest_params = {
      :name => manifest.name,
      :user => manifest.user,
      :image_type => manifest.image_type,
      :arch => manifest.arch,
      :reserved => nil,
      :parts => manifest.parts.map { |part| [part.filename, part.digest] },
      :size => manifest.size,
      :bundled_size => manifest.bundled_size,
      :user_encrypted_key => manifest.user_encrypted_key,
      :ec2_encrypted_key => manifest.ec2_encrypted_key,
      :cipher_algorithm => manifest.cipher_algorithm,
      :user_encrypted_iv => manifest.user_encrypted_iv,
      :ec2_encrypted_iv => manifest.ec2_encrypted_iv,
      :digest => manifest.digest,
      :digest_algorithm => manifest.digest_algorithm,
      :privkey_filename => user_pk_path,
      :kernel_id => kernel_id,
      :ramdisk_id => ramdisk_id,
      :product_codes => manifest.product_codes,
      :ancestor_ami_ids => manifest.ancestor_ami_ids,
      :block_device_mapping => manifest.block_device_mapping,
      :bundler_name => manifest.bundler_name,
      :bundler_version => manifest.bundler_version,
      :bundler_release => manifest.bundler_release,
      :kernel_name => manifest.kernel_name,
    }
    new_manifest.init(manifest_params)
    new_manifest
  end

  #----------------------------------------------------------------------------#

  def check_and_warn(manifest, kernel_id, ramdisk_id)
    if (manifest.kernel_id and kernel_id.nil?) or (manifest.ramdisk_id and ramdisk_id.nil?)
      message = ["This operation will remove the kernel and/or ramdisk associated with",
                 "the AMI. This may cause the AMI to fail to launch unless you specify",
                 "an appropriate kernel and ramdisk at launch time.",
                ].join("\n")
      unless warn_confirm(message)
        raise EC2StopExecution.new()
      end
    end
  end

  #----------------------------------------------------------------------------#

  def warn_about_mappings(problems)
    return if problems.nil?
    message = ["The following identifiers do not exist in the target region:",
               "  " + problems.inspect.gsub(/['"]/, '')
              ].join("\n")
    unless warn_confirm(message)
      raise EC2StopExecution.new()
    end
  end

  #----------------------------------------------------------------------------#

  def migrate_manifest(manifest_path,
                       user_pk_path,
                       user_cert_path,
                       user=nil,
                       pass=nil,
                       use_mapping=true,
                       kernel_id=nil,
                       ramdisk_id=nil,
                       region=nil,
                       quiet=false)
    manifest = get_manifest(manifest_path, user_cert_path)
    backup_manifest(manifest_path, quiet)
    if use_mapping
      kernel_id, ramdisk_id = map_identifiers(manifest,
                                              user,
                                              pass,
                                              region,
                                              kernel_id,
                                              ramdisk_id)
    end
    check_and_warn(manifest, kernel_id, ramdisk_id)
    new_manifest = build_migrated_manifest(manifest, user_pk_path, kernel_id, ramdisk_id)
    File.open(manifest_path, 'w') { |f| f.write(new_manifest.to_s) }
    $stdout.puts("Successfully migrated #{manifest_path}") unless quiet
    $stdout.puts("It is now suitable for use in #{region}.") unless quiet
  end

  #------------------------------------------------------------------------------#
  # Overrides
  #------------------------------------------------------------------------------#

  def get_manual()
    MIGRATE_MANIFEST_MANUAL
  end

  def get_name()
    MIGRATE_MANIFEST_NAME
  end

  def main(p)
    migrate_manifest(p.manifest_path,
                     p.user_pk_path,
                     p.user_cert_path,
                     p.user,
                     p.pass,
                     p.use_mapping,
                     p.kernel_id,
                     p.ramdisk_id,
                     p.region)
  end

end

#------------------------------------------------------------------------------#
# Script entry point. Execute only if this file is being executed.

if __FILE__ == $0
  ManifestMigrator.new().run(MigrateManifestParameters)
end
