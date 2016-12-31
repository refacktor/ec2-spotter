# Copyright 2008-2014 Amazon.com, Inc. or its affiliates.  All Rights
# Reserved.  Licensed under the Amazon Software License (the
# "License").  You may not use this file except in compliance with the
# License. A copy of the License is located at
# http://aws.amazon.com/asl or in the "license" file accompanying this
# file.  This file is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See
# the License for the specific language governing permissions and
# limitations under the License.

require 'ec2/platform/linux/fstab'

module EC2
  module Platform
    module Solaris
      class Fstab < EC2::Platform::Linux::Fstab
        LOCATION = '/etc/vfstab'
        def initialize(filename = LOCATION)
          super filename          
        end
        
        DEFAULT = IO.read(File.join('/etc', 'vfstab')) rescue <<TEXT
# Default /etc/vfstab
# Supplied by: #{PKG_NAME}-#{PKG_VERSION}-#{PKG_RELEASE}
#device         device          mount           FS      fsck    mount   mount
#to mount       to fsck         point           type    pass    at boot options
#
fd      -       /dev/fd fd      -       no      -
/proc   -       /proc   proc    -       no      -
/dev/dsk/c0d0s1 -       -       swap    -       no      -
/dev/dsk/c0d0s0 /dev/rdsk/c0d0s0        /       ufs     1       no      -
/dev/dsk/c0d1s0 /dev/rdsk/c0d1s0        /mnt    ufs     2       no      -
/devices        -       /devices        devfs   -       no      -
sharefs -       /etc/dfs/sharetab       sharefs -       no      -
ctfs    -       /system/contract        ctfs    -       no      -
objfs   -       /system/object  objfs   -       no      -
swap    -       /tmp    tmpfs   -       yes     -
TEXT
        LEGACY = :legacy # here for compatibility reasons
      end
    end
  end
end
