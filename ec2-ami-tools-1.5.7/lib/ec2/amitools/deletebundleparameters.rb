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

#------------------------------------------------------------------------------#

class DeleteBundleParameters < S3ToolParameters
    
  MANIFEST_DESCRIPTION = "The path to the unencrypted manifest file."  
  PREFIX_DESCRIPTION = "The bundled AMI part filename prefix."  
  RETRY_DESCRIPTION = "Automatically retry failed deletes. Use with caution."  
  YES_DESCRIPTION = "Automatically answer 'y' without asking."
  CLEAR_DESCRIPTION = "Delete the bucket if empty. Not done by default."
  
  attr_accessor :manifest,
                :prefix,
                :retry,
                :yes,
                :clear
    
  #----------------------------------------------------------------------------#

  def mandatory_params()
    super()
  end
  
  #----------------------------------------------------------------------------#

  def optional_params()
    super()
    
    on('-m', '--manifest PATH', String, MANIFEST_DESCRIPTION) do |manifest|
      assert_file_exists(manifest, '--manifest')
      @manifest = manifest
    end
    
    on('-p', '--prefix PREFIX', String, PREFIX_DESCRIPTION) do |prefix|
      assert_good_key(prefix, '--prefix')
      @prefix = prefix
    end
    
    on('--clear', CLEAR_DESCRIPTION) do
      @clear = true
    end
    
    on('--retry', RETRY_DESCRIPTION) do
      @retry = true
    end
    
    on('-y', '--yes', YES_DESCRIPTION) do
      @yes = true
    end
  end

  #----------------------------------------------------------------------------#

  def validate_params()
    super()
    raise MissingMandatory.new('--manifest or --prefix') unless @manifest or @prefix
    raise InvalidCombination.new('--prefix', '--manifest') if (@prefix and @manifest)
  end

  #----------------------------------------------------------------------------#

  def set_defaults()
    super()
    @clear ||= false
  end

end
