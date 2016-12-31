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
require 'timeout'
require 'ec2/platform/current'
require 'ec2/amitools/syschecks'

# The Bundle command line parameters.
class BundleParameters < ParametersBase
  include EC2::Platform::Current::Constants

  SUPPORTED_ARCHITECTURES = ['i386', 'x86_64']

  USER_DESCRIPTION = "The user's EC2 user ID (Note: AWS account number, NOT Access Key ID)."
  HELP_DESCRIPTION = "Display this help message and exit."
  MANUAL_DESCRIPTION = "Display the user manual and exit."
  DESTINATION_DESCRIPTION = "The directory to create the bundle in. Defaults to '#{Bundling::DESTINATION}'."
  DEBUG_DESCRIPTION = "Display debug messages."
  EC2_CERT_PATH_DESCRIPTION = ['The path to the EC2 X509 public key certificate bundled into the AMI.',
                               "Defaults to '#{Bundling::EC2_X509_CERT}'."]
  ARCHITECTURE_DESCRIPTION = "Specify target architecture. One of #{SUPPORTED_ARCHITECTURES.inspect}"
  BATCH_DESCRIPTION = "Run in batch mode. No interactive prompts."
  PRODUCT_CODES_DESCRIPTION = ['Default product codes attached to the image at registration time.',
                               'Comma separated list of product codes.']
  SIZE_CHECKS_DESCRIPTION = 'If set, disables size checks on bundled artifacts.'
  VERSION_DESCRIPTION = "Display the version and copyright notice and then exit."

  attr_accessor :user_pk_path,
                :user_cert_path,
                :user,
                :destination,
                :ec2_cert_path,
                :debug,
                :show_help,
                :manual,
                :arch,
                :batch_mode,
                :size_checks,
                :product_codes

  PROMPT_TIMEOUT = 30

  #----------------------------------------------------------------------------#

  def mandatory_params()
    on('-c', '--cert PATH', String, USER_CERT_PATH_DESCRIPTION) do |path|
      assert_file_exists(path, '--cert')
      @user_cert_path = path
    end

    on('-k', '--privatekey PATH', String, USER_PK_PATH_DESCRIPTION) do |path|
      assert_file_exists(path, '--privatekey')
      @user_pk_path = path
    end

    on('-u', '--user USER', String, USER_ACCOUNT_DESCRIPTION) do |user|
      # Remove hyphens from the Account ID as presented in AWS portal.
      @user = user.gsub("-", "")
      # Validate the account ID looks correct (users often provide us with their akid or secret key)
      unless (@user =~ /\d{12}/)
        raise InvalidValue.new('--user', @user,
                               "the user ID should consist of 12 digits (optionally hyphenated); this should not be your Access Key ID")
      end
    end
  end

  #----------------------------------------------------------------------------#

  def optional_params()
    on('-d', '--destination PATH', String, DESTINATION_DESCRIPTION) do |path|
      assert_directory_exists(path, '--destination')
      @destination = path
    end

    on('--ec2cert PATH', String, *BundleParameters::EC2_CERT_PATH_DESCRIPTION) do |path|
      assert_file_exists(path, '--ec2cert')
      @ec2_cert_path = path
    end

    on('-r', '--arch ARCHITECTURE', String, ARCHITECTURE_DESCRIPTION) do |arch|
      @arch = arch
    end

    on('--productcodes PRODUCT_CODES', String, *PRODUCT_CODES_DESCRIPTION) do |pc|
      @product_codes = pc
    end

    on('--no-size-checks', SIZE_CHECKS_DESCRIPTION ) do |o|
      @size_checks = o
    end
  end

  #----------------------------------------------------------------------------#

  def validate_params()
    unless @clone_only
      raise MissingMandatory.new('--cert') unless @user_cert_path
      raise MissingMandatory.new('--privatekey') unless @user_pk_path
      raise MissingMandatory.new('--user') unless @user
    end
  end

  #----------------------------------------------------------------------------#

  def set_defaults()
    @destination ||= Bundling::DESTINATION
    @ec2_cert_path ||= Bundling::EC2_X509_CERT
    @exclude ||= []
    @size_checks = true
  end

end
