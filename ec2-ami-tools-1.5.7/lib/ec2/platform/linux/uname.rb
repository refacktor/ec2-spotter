# Copyright 2008-2014 Amazon.com, Inc. or its affiliates.  All Rights
# Reserved.  Licensed under the Amazon Software License (the
# "License").  You may not use this file except in compliance with the
# License. A copy of the License is located at
# http://aws.amazon.com/asl or in the "license" file accompanying this
# file.  This file is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See
# the License for the specific language governing permissions and
# limitations under the License.

require 'ostruct'
require 'ec2/platform'

module EC2
  module Platform
    module Linux
      class Uname
        @@uname ||= OpenStruct.new
        def self.all
          @@uname.all ||= `uname -a`.strip
        end
        def self.platform
          @@uname.platform ||= `uname -i`.strip
        end
        def self.nodename
          @@uname.nodename ||= `uname -n`.strip
        end
        def self.processor
          @@uname.processor ||= `uname -p`.strip
        end
        def self.release
          @@uname.release ||= `uname -r`.strip
        end
        def self.os
          @@uname.os ||= `uname -s`.strip
        end
        def self.machine
          @@uname.machine ||= `uname -m`.strip
        end
        def self.uname
          @@uname
        end        
      end
    end
  end
end
if __FILE__ == $0
   include EC2::Platform::Linux
   puts "Uname = #{Uname.all.inspect}"
end
