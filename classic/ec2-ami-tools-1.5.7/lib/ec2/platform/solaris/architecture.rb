# Copyright 2008-2014 Amazon.com, Inc. or its affiliates.  All Rights
# Reserved.  Licensed under the Amazon Software License (the
# "License").  You may not use this file except in compliance with the
# License. A copy of the License is located at
# http://aws.amazon.com/asl or in the "license" file accompanying this
# file.  This file is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See
# the License for the specific language governing permissions and
# limitations under the License.

#-------------------------------------------------------------------------------
# Solaris machine architectures as seen in EC2
require 'ec2/platform/base/architecture'
require 'ec2/platform/solaris/uname'
module EC2
  module Platform
    module Solaris
      class Architecture < EC2::Platform::Base::Architecture
        def self.bundling
          processor = Uname.processor
          return Architecture::I386 if processor =~ /^i\d86$/
          return Architecture::X86_64 if processor =~ /^x86_64$/
          return Architecture::UNKNOWN
        end
      end
    end
  end
end
