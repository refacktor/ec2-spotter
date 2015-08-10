# Copyright 2008-2014 Amazon.com, Inc. or its affiliates.  All Rights
# Reserved.  Licensed under the Amazon Software License (the
# "License").  You may not use this file except in compliance with the
# License. A copy of the License is located at
# http://aws.amazon.com/asl or in the "license" file accompanying this
# file.  This file is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See
# the License for the specific language governing permissions and
# limitations under the License.

module EC2
  module Platform
    module Base
      class Architecture
        I386 = 'i386'
        X86_64 = 'x86_64'
        UNKNOWN = 'unknown'      
        SUPPORTED = [I386, X86_64]
        
        def self.supported? arch
          SUPPORTED.include? arch
        end
      end
    end
  end
end
