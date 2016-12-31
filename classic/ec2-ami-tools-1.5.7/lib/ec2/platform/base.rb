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
module EC2
  module Platform
    class PartitionType < String
      MBR  = new 'mbr'
      GPT  = new 'gpt'
      NONE = new 'none'

      def self.list()
        [MBR, GPT, NONE]
      end

      def self.valid?(input)
        return false if input == NONE
        self.list.include?(input)
      end
    end

    module Base
      module Distribution
        UNKNOWN   = 'Unknown'
        GENERIC   = 'Generic'
      end

      class System
        MOUNT_POINT = '/mnt/img-mnt'
        def self.distribution
          Distribution::UNKNOWN
        end
        
        def self.superuser?
          false
        end
        
        def self.exec(cmd, debug)
          if debug
            puts( "Executing: #{cmd} " )
            suffix = ''
          else
            suffix = ' 2>&1 > /dev/null'
          end
          raise "execution failed: \"#{cmd}\"" unless system( cmd + suffix )
        end
      end
    end
  end
end
