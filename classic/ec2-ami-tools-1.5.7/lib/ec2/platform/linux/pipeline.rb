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
require 'ec2/platform/base/pipeline'

#------------------------------------------------------------------------------
module EC2    
  #----------------------------------------------------------------------------
  module Platform
    #--------------------------------------------------------------------------
    module Linux
      #------------------------------------------------------------------------    
      class Pipeline < EC2::Platform::Base::Pipeline
        
        #----------------------------------------------------------------------
        # Given a pipeline of commands, modify it so that we can obtain
        # the exit status of each pipeline stage by reading the tempfile
        # associated with that stage. 
        def pipestatus(cmd)
          command = cmd
          command << ';' unless cmd.rstrip[-1,1] == ';'
          command << ' ' unless cmd[-1,1] == ' '
          list = []
          @tempfiles.each_with_index do |file, index| 
            list << "echo ${PIPESTATUS[#{index}]} > #{file.path}"
          end
          command + list.join(' & ')
        end
      end
    end
  end
end
