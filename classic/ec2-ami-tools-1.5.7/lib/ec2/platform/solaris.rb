# Copyright 2008-2014 Amazon.com, Inc. or its affiliates.  All Rights
# Reserved.  Licensed under the Amazon Software License (the
# "License").  You may not use this file except in compliance with the
# License. A copy of the License is located at
# http://aws.amazon.com/asl or in the "license" file accompanying this
# file.  This file is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See
# the License for the specific language governing permissions and
# limitations under the License.

#------------------------------------------------------------------------------
require 'ec2/platform/base'
require 'ec2/platform/solaris/identity'
require 'ec2/platform/solaris/architecture'
require 'ec2/platform/solaris/fstab'
require 'ec2/platform/solaris/mtab'
require 'ec2/platform/solaris/image'
require 'ec2/platform/solaris/rsync'
require 'ec2/platform/solaris/tar'
require 'ec2/platform/solaris/uname'
require 'ec2/platform/solaris/pipeline'
require 'ec2/platform/solaris/constants'

module EC2
  module Platform
    module Solaris
      class System < EC2::Platform::Base::System
        
        BUNDLING_ARCHITECTURE = EC2::Platform::Solaris::Architecture.bundling        
        
        #---------------------------------------------------------------------#
        def self.superuser?
          return `id -u`.strip == '0'
        end
      end
    end
  end
end
