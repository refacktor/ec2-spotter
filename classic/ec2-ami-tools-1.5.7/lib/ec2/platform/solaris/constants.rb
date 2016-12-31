# Copyright 2008-2014 Amazon.com, Inc. or its affiliates.  All Rights
# Reserved.  Licensed under the Amazon Software License (the
# "License").  You may not use this file except in compliance with the
# License. A copy of the License is located at
# http://aws.amazon.com/asl or in the "license" file accompanying this
# file.  This file is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See
# the License for the specific language governing permissions and
# limitations under the License.

#------------------------------------------------------------------------
# Solaris overrides for constants go here
#------------------------------------------------------------------------
require 'ec2/platform/base/constants'
module EC2
  module Platform
    module Solaris
      module Constants
        module Bundling
          include EC2::Platform::Base::Constants::Bundling
          DESTINATION = '/mnt'
        end
        module Utility
          OPENSSL = '/usr/sfw/bin/openssl'
          TAR = '/usr/sfw/bin/gtar'
        end
      end
    end
  end
end
