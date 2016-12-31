# Copyright 2008-2014 Amazon.com, Inc. or its affiliates.  All Rights
# Reserved.  Licensed under the Amazon Software License (the
# "License").  You may not use this file except in compliance with the
# License. A copy of the License is located at
# http://aws.amazon.com/asl or in the "license" file accompanying this
# file.  This file is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See
# the License for the specific language governing permissions and
# limitations under the License.

require 'ec2/amitools/parameters_base'

class UnbundleParameters < ParametersBase
  
  MANIFEST_DESCRIPTION    = "The path to the AMI manifest file."
  SOURCE_DESCRIPTION      = 'The directory containing bundled AMI parts to unbundle. Defaults to ".".'
  DESTINATION_DESCRIPTION = 'The directory to unbundle the AMI into. Defaults to the ".".'
  
  attr_accessor :manifest_path,
                :user_pk_path,
                :source,
                :destination
  
  #----------------------------------------------------------------------------#

  def mandatory_params()
    on('-k', '--privatekey PATH', String, USER_PK_PATH_DESCRIPTION) do |path|
      assert_file_exists(path, '--privatekey')
      @user_pk_path = path
    end

    on('-m', '--manifest PATH', String, MANIFEST_DESCRIPTION) do |manifest|
      assert_file_exists(manifest, '--manifest')
      @manifest_path = manifest
    end
  end

  #----------------------------------------------------------------------------#

  def optional_params()
    on('-s', '--source DIRECTORY', String, SOURCE_DESCRIPTION) do |directory|
      assert_directory_exists(directory, '--source')
      @source = directory
    end  
    
    on('-d', '--destination DIRECTORY', String, DESTINATION_DESCRIPTION) do |directory|
      assert_directory_exists(directory, '--destination')
      @destination = directory
    end
  end    

  #----------------------------------------------------------------------------#

  def validate_params()
    raise MissingMandatory.new('--manifest') unless @manifest_path
    raise MissingMandatory.new('--privatekey') unless @user_pk_path
  end

  #----------------------------------------------------------------------------#

  def set_defaults()
    @source ||= Dir::pwd()
    @destination ||= Dir::pwd()
  end
end
