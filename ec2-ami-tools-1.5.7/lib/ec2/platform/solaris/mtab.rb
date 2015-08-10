# Copyright 2008-2014 Amazon.com, Inc. or its affiliates.  All Rights
# Reserved.  Licensed under the Amazon Software License (the
# "License").  You may not use this file except in compliance with the
# License. A copy of the License is located at
# http://aws.amazon.com/asl or in the "license" file accompanying this
# file.  This file is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See
# the License for the specific language governing permissions and
# limitations under the License.

require 'ec2/platform/linux/mtab'

module EC2
  module Platform
    module Solaris
      LOCAL_FS_TYPES = [
        'ext2', 'ext3', 'xfs', 'jfs', 'reiserfs', 'tmpfs', 
        'ufs', 'sharefs', 'dev', 'devfs', 'ctfs', 'mntfs',
        'proc', 'lofs',   'objfs', 'fd', 'autofs'
      ]
      class Mtab < EC2::Platform::Linux::Mtab
        LOCATION = '/etc/mnttab'
        def initialize(filename = LOCATION)
          super filename
        end
      end
    end
  end
end
