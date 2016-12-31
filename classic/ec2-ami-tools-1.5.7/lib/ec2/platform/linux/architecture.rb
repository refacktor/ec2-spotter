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
# Machine architectures as seen by EC2 in Linux

require 'ec2/platform/base/architecture'
require 'ec2/platform/linux/uname'

module EC2
  module Platform
    module Linux
      class Architecture < EC2::Platform::Base::Architecture
      
        #----------------------------------------------------------------------
        # Returns the EC2-equivalent of the architecture of the platform this is
        # running on.        
        def self.bundling
          processor = Uname.platform
          processor = Uname.machine if processor =~ /unknown/i
          return Architecture::I386 if processor =~ /^i\d86$/
          return Architecture::X86_64 if processor =~ /^x86_64$/
          return Architecture::UNKNOWN
        end
      end
    end
  end
end
