# Copyright 2008-2014 Amazon.com, Inc. or its affiliates.  All Rights
# Reserved.  Licensed under the Amazon Software License (the
# "License").  You may not use this file except in compliance with the
# License. A copy of the License is located at
# http://aws.amazon.com/asl or in the "license" file accompanying this
# file.  This file is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See
# the License for the specific language governing permissions and
# limitations under the License.

require 'ec2/amitools/bundlemachineparameters'

# The Bundle Image command line parameters.
class BundleImageParameters < BundleMachineParameters

  IMAGE_PATH_DESCRIPTION = "The path to the file system image to bundle."
  PREFIX_DESCRIPTION = "The filename prefix for bundled AMI files. Defaults to image name."

  attr_reader :image_path,
              :prefix
                
  def mandatory_params()
    super()
    on('-i', '--image PATH', String, IMAGE_PATH_DESCRIPTION) do |path|
      assert_file_exists(path, '--image')
      @image_path = path
    end
  end

  def optional_params()
    super()
    on('-p', '--prefix PREFIX', String, PREFIX_DESCRIPTION) do |prefix|
      assert_good_key(prefix, '--prefix')
      @prefix = prefix
    end
  end

  def validate_params()
    raise MissingMandatory.new('--image') unless @image_path
    super()
  end
end
