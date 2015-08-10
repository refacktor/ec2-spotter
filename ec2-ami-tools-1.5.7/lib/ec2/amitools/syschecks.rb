# Copyright 2008-2014 Amazon.com, Inc. or its affiliates.  All Rights
# Reserved.  Licensed under the Amazon Software License (the
# "License").  You may not use this file except in compliance with the
# License. A copy of the License is located at
# http://aws.amazon.com/asl or in the "license" file accompanying this
# file.  This file is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See
# the License for the specific language governing permissions and
# limitations under the License.

require 'ec2/amitools/fileutil'
require 'ec2/platform/current'

module SysChecks
  def self.rsync_usable?()
    EC2::Platform::Current::Rsync.usable?
  end
  def self.good_tar_version?()
    EC2::Platform::Current::Tar::Version.current.usable?
  end
  def self.get_system_arch()
    EC2::Platform::Current::System::BUNDLING_ARCHITECTURE
  end
  def self.root_user?()
    EC2::Platform::Current::System.superuser?
  end
end
