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
require 'ec2/amitools/bundleimageparameters'
require 'ec2/amitools/bundle_base'

MAX_SIZE = 10 * 1024 * 1024 * 1024 # 10 GB in bytes.
BUNDLE_IMAGE_NAME = 'ec2-bundle-image'

# The manual.
BUNDLE_IMAGE_MANUAL=<<TEXT
#{BUNDLE_IMAGE_NAME} is a command line tool that creates a bundled Amazon Machine \
Image (AMI) from a specified loopback filesystem image.

#{BUNDLE_IMAGE_NAME} will:
- tar -S the AMI to preserve sparseness of the image file
- gzip the result
- encrypt it
- split it into parts
- generate a manifest file describing the bundled AMI

#{BUNDLE_IMAGE_NAME} will bundle AMIs of up to 10GB.
TEXT

class ImageBundler < BundleTool

  def bundle_image(p)
    if p.size_checks
      file_size = File.size(p.image_path)
      if file_size <= 0
        raise "the specified image #{p.image_path} is zero sized"
      elsif file_size > MAX_SIZE
        raise "the specified image #{p.image_path} is too large"
      end
    else
      $stderr.puts 'Warning: disabling size-checks can result in unbootable image'
    end
    
    optional_args = {
      :kernel_id => p.kernel_id,
      :ramdisk_id => p.ramdisk_id,
      :product_codes => p.product_codes,
      :ancestor_ami_ids => p.ancestor_ami_ids,
      :block_device_mapping => p.block_device_mapping,
    }
    $stdout.puts 'Bundling image file...'
    
    Bundle.bundle_image(File::expand_path(p.image_path),
                        p.user,
                        p.arch,
                        Bundle::ImageType::MACHINE,
                        p.destination,
                        p.user_pk_path,
                        p.user_cert_path,
                        p.ec2_cert_path,
                        p.prefix,
                        optional_args,
                        @debug,
                        false)
    
    $stdout.puts( "#{BUNDLE_IMAGE_NAME} complete." )
  end

  #------------------------------------------------------------------------------#
  # Overrides
  #------------------------------------------------------------------------------#

  def get_manual()
    BUNDLE_IMAGE_MANUAL
  end

  def get_name()
    BUNDLE_IMAGE_NAME
  end

  def main(p)
    bundle_image(p)
  end

end

#------------------------------------------------------------------------------#
# Script entry point. Execute only if this file is being executed.
if __FILE__ == $0
  ImageBundler.new().run(BundleImageParameters)
end
