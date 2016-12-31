# Copyright 2008-2014 Amazon.com, Inc. or its affiliates.  All Rights
# Reserved.  Licensed under the Amazon Software License (the
# "License").  You may not use this file except in compliance with the
# License. A copy of the License is located at
# http://aws.amazon.com/asl or in the "license" file accompanying this
# file.  This file is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See
# the License for the specific language governing permissions and
# limitations under the License.

require 'optparse'
require 'ec2/amitools/parameter_exceptions'
require 'ec2/amitools/version'
require 'ec2/common/s3support'

class ParametersBase < OptionParser
  include ParameterExceptions

  # Descriptions for common parameters:
  USER_CERT_PATH_DESCRIPTION = "The path to the user's PEM encoded RSA public key certificate file."
  USER_PK_PATH_DESCRIPTION = "The path to the user's PEM encoded RSA private key file."
  USER_DESCRIPTION = "The user's AWS access key ID."
  PASS_DESCRIPTION = "The user's AWS secret access key."
  USER_ACCOUNT_DESCRIPTION = "The user's EC2 user ID (Note: AWS account number, NOT Access Key ID)."
  HELP_DESCRIPTION = "Display this help message and exit."
  MANUAL_DESCRIPTION = "Display the user manual and exit."
  DEBUG_DESCRIPTION = "Display debug messages."
  VERSION_DESCRIPTION = "Display the version and copyright notice and then exit."
  BATCH_DESCRIPTION = "Run in batch mode. No interactive prompts."

  attr_accessor(:show_help,
                :manual,
                :version,
                :batch_mode,
                :debug)

  #------------------------------------------------------------------------------#
  # Methods to override in subclasses
  #------------------------------------------------------------------------------#

  def mandatory_params()
    # Override this for mandatory parameters
  end

  def optional_params()
    # Override this for optional parameters
  end

  def validate_params()
    # Override this for parameter validation
  end

  def set_defaults()
    # Override this for parameter validation
  end

  #------------------------------------------------------------------------------#
  # Useful utility methods
  #------------------------------------------------------------------------------#
  
  def early_exit?()
    @show_help or @manual or @version
  end

  def interactive?()
    not (early_exit? or @batch_mode)
  end

  def version_copyright_string()
    EC2Version::version_copyright_string()
  end

  #------------------------------------------------------------------------------#
  # Validation utility methods
  #------------------------------------------------------------------------------#

  def assert_exists(path, param)
    unless File::exist?(path)
      raise InvalidValue.new(param, path, "File or directory does not exist.")
    end
  end

  def assert_glob_expands(path, param)
    if Dir::glob(path).empty?
      raise InvalidValue.new(param, path, "File or directory does not exist.")
    end
  end

  def assert_file_exists(path, param)
    unless (File::exist?(path) and File::file?(path))
      raise InvalidValue.new(param, path, "File does not exist or is not a file.")
    end
  end

  def assert_file_executable(path, param)
    unless (File::executable?(path) and File::file?(path))
      raise InvalidValue.new(param, path, "File not executable.")
    end
  end

  def assert_directory_exists(path, param)
    unless (File::exist?(path) and File::directory?(path))
      raise InvalidValue.new(param, path, "Directory does not exist or is not a directory.")
    end
  end

  def assert_option_in(option, choices, param)
    unless choices.include?(option)
      raise InvalidValue.new(param, option)
    end
  end

  def assert_good_key(key, param)
    if key.include?("/")
      raise InvalidValue.new(param, key, "'/' character not allowed.")
    end
  end

  #------------------------------------------------------------------------------#
  # Parameters common to all tools
  #------------------------------------------------------------------------------#

  def common_params()
    on('-h', '--help', HELP_DESCRIPTION) do
      @show_help = true
    end
    
    on('--version', VERSION_DESCRIPTION) do
      @version = true
    end
    
    on('--manual', MANUAL_DESCRIPTION) do
      @manual = true
    end
    
    on('--batch', BATCH_DESCRIPTION) do
      @batch_mode = true
    end
    
    on('--debug', DEBUG_DESCRIPTION) do
      @debug = true
    end    
  end


  def initialize(argv, name=nil)
    super(argv)

    # Mandatory parameters.
    separator("")
    separator("MANDATORY PARAMETERS")
    mandatory_params()
    
    # Optional parameters.
    separator("")
    separator("OPTIONAL PARAMETERS")
    common_params()
    optional_params()

    # Parse the command line parameters.
    parse!(argv)

    unless early_exit?
      validate_params()
      set_defaults()
    end
  end
end
