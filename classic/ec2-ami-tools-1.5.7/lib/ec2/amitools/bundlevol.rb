# Copyright 2008-2014 Amazon.com, Inc. or its affiliates.  All Rights
# Reserved.  Licensed under the Amazon Software License (the
# "License").  You may not use this file except in compliance with the
# License. A copy of the License is located at
# http://aws.amazon.com/asl or in the "license" file accompanying this
# file.  This file is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See
# the License for the specific language governing permissions and
# limitations under the License.

require 'ec2/amitools/bundle'
require 'ec2/amitools/bundlevolparameters'
require 'ec2/platform/current'
require 'ec2/amitools/syschecks'
require 'ec2/amitools/bundle_base'

BUNDLE_VOL_NAME = 'ec2-bundle-vol'

BUNDLE_VOL_MANUAL=<<TEXT
#{BUNDLE_VOL_NAME} is a command line tool that creates an Amazon Machine Image (AMI)
from an existing Fedora Core installation and bundles it. Its output is a
bundled AMI consisting of AMI parts and a manifest. Use the '--help'
option to display help on Bundle Volume parameters.

#{BUNDLE_VOL_NAME} can be run from within an installation, provided there is sufficient space
for the AMI in the destination directory. Note that running Bundle Volume from
within a running installation may be problematic because partially written files
may get copied into the AMI. To minimize this risk it is recommended that the
system is brought down to runlevel 1. Note that this will stop networking, so
only do this if you have access to the console.

If #{BUNDLE_VOL_NAME} is not run from within the installation, the volume belonging to the
installation must be mounted so that it is accessible to #{BUNDLE_VOL_NAME}.

#{BUNDLE_VOL_NAME} will:
- create a sparse filesystem image
- recursively copy the specified volume into the image
- tar -S the image to preserve the sparseness of the image file
- compress the image
- encrypt it
- split it into parts
- generate a manifest file describing the bundled AMI

Recursive Copying

The recursive copying process copies directories from the volume into the image.
The special directories:

- '/dev'
- '/media'
- '/mnt'
- '/proc'
- '/sys'

are always excluded.

Files matching the following regular expressions:

- '*/#*#'
- '*/.#*'
- '*.sw'
- '*.swo'
- '*.swp'
- '*~'
- '*.pem'
- '*.priv'
- '*id_rsa*'
- '*id_dsa*'
- '*.gpg'
- '*.jks'
- '*/.ssh/authorized_keys'
- '*/.bash_history'

are excluded by default on Linux. Individual files that match these patterns may be
included by specifying the '--include' option.

Local directories, which are copied by default, are defined to be those on
filesystems of the following types:

- ext2
- ext3
- xfs
- jfs
- reiserfs

Directories on filesystems that are not of one of the types listed above, such as
remotely mounted NFS filesystems, are excluded by default, but can be copied
by using the '--all' option.

Symbolic links are preserved by the copying process, provided the link target is
copied.

Mounted File Systems

#{BUNDLE_VOL_NAME} will default to bundling the existing /etc/fstab file.

#{BUNDLE_VOL_NAME} will create and bundle AMIs of up to 10GB.

Note:
  Creating the filesystem on the image may fail in the presence of selinux.
  If you are using selinux, you should disable it before using #{BUNDLE_VOL_NAME}.
TEXT

MAX_SIZE_MB = 10 * 1024  # 10 GB in MB

class VolBundler < BundleTool

  def bundle_vol(p)
    name = p.prefix
    image_file = File::join( p.destination, name )
    volume = File::join( p.volume, "" ) # Add a trailing "/" if not present.

    #
    # We can't bundle unless we're root.
    #
    raise "You need to be root to run #{$0}" unless SysChecks::root_user?

    #
    # Extra parameter verification.
    #
    raise "the specified size #{p.size}MB is too large" unless p.size <= MAX_SIZE_MB
    raise "the specified image file #{image_file} already exists" if File::exist?( image_file )

    #
    # Create a list of files to be included in the image. This list will override any
    # files that are excluded by the security filtered files list. Files are only added if
    # they are under the volume root.
    #
    includes = []
    p.includes.each do |file|
      includes << file
    end
    #
    # Create list of directories to exclude from the image. Always exclude special
    # directories, directories specified by the user and the image file itself.
    #
    exclude = []
    unless p.all
      #
      # Exclude mounted non-local filesystems if they are under the volume root.
      #
      EC2::Platform::Current::Mtab.load.entries.values.each do |entry|
        unless EC2::Platform::Current::LOCAL_FS_TYPES.include? entry.fstype
          exclude << entry.mpoint if entry.mpoint.index(volume) == 0
        end
      end
    end
    EC2::Platform::Current::Image::EXCLUDES.each { |dir| exclude << dir }

    #
    # Exclude user specified excluded directories if they are under the volume root.
    #
    p.exclude.each do |dir|
      exclude << dir
    end

    #
    # Exclude the image file if it is under the volume root.
    #
    if image_file.index( volume ) == 0
      exclude << image_file
    end

    # If we are inheriting instance data but can't access it we want to fail early
    if p.inherit && !EC2::InstanceData.new.instance_data_accessible
      raise EC2FatalError.new(12, "Can't access instance metadata. If you are not bundling on an EC2 instance use --no-inherit.")
    end

    #
    # Create image from volume.
    #
    image = EC2::Platform::Current::Image.new(volume,
                                              image_file,
                                              p.size,
                                              exclude,
                                              includes,
                                              p.filter,
                                              p.fstab,
                                              p.part_type,
                                              p.arch,
                                              p.script,
                                              @debug,
                                              p.grub_config)
    image.make

    $stdout.puts 'Image file created: %s' % [image_file]
    $stdout.puts 'Volume cloning done.'
    if p.clone_only
      $stdout.puts 'Not bundling image file since "--clone-only" flag was specified.'
    else
      #
      # Bundle the created image file.
      #
      $stdout.puts 'Bundling image file...'
      optional_args = {
        :kernel_id => p.kernel_id,
        :ramdisk_id => p.ramdisk_id,
        :product_codes => p.product_codes,
        :ancestor_ami_ids => p.ancestor_ami_ids,
        :block_device_mapping => p.block_device_mapping
      }
      Bundle.bundle_image(image_file,
                          p.user,
                          p.arch,
                          Bundle::ImageType::VOLUME,
                          p.destination,
                          p.user_pk_path,
                          p.user_cert_path,
                          p.ec2_cert_path,
                          nil, # prefix
                          optional_args,
                          @debug,
                          p.inherit)
    end
    $stdout.puts("#{BUNDLE_VOL_NAME} complete.")
  end

  #------------------------------------------------------------------------------#
  # Overrides
  #------------------------------------------------------------------------------#

  def get_manual()
    BUNDLE_VOL_MANUAL
  end

  def get_name()
    BUNDLE_VOL_NAME
  end

  def main(p)
    bundle_vol(p)
  end

end

#------------------------------------------------------------------------------#
# Script entry point. Execute only if this file is being executed.
if __FILE__ == $0
  VolBundler.new().run(BundleVolParameters)
end
