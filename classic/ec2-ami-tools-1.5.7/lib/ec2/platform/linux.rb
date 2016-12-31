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
require 'ec2/platform/base'
require 'ec2/platform/linux/identity'
require 'ec2/platform/linux/architecture'
require 'ec2/platform/linux/fstab'
require 'ec2/platform/linux/mtab'
require 'ec2/platform/linux/image'
require 'ec2/platform/linux/rsync'
require 'ec2/platform/linux/tar'
require 'ec2/platform/linux/uname'
require 'ec2/platform/linux/pipeline'
require 'ec2/platform/linux/constants'

module EC2
  module Platform    
    module Linux
      module Distribution
        include EC2::Platform::Base::Distribution
        AMAZON    = 'Amazon Linux'
        REDHAT    = 'Red Hat Linux'
        GENTOO    = 'Gentoo'
        DEBIAN    = 'Debian'
        UBUNTU    = 'Ubuntu'
        FEDORA    = 'Fedora'
        SLACKWARE = 'Slackware'
        SUSE      = 'SuSE Linux'
        MANDRAKE  = 'Mandrake'
        CAOS      = 'Caos Linux'
        
        IDENTITIES= [
          # file                     distro                    regex
          ['/etc/system-release-cpe', Distribution::AMAZON, /amazon/],
          ['/etc/caos-release',       Distribution::CAOS,        nil],
          ['/etc/debian-release',     Distribution::DEBIAN,      nil],
          ['/etc/debian_version',     Distribution::DEBIAN,      nil],
          ['/etc/fedora-release',     Distribution::FEDORA,      nil],
          ['/etc/gentoo-release',     Distribution::GENTOO,      nil],
          ['/etc/redhat-release',     Distribution::REDHAT,      nil],
          ['/etc/slackware-version',  Distribution::SLACKWARE,   nil],
          ['/etc/slackware-release',  Distribution::SLACKWARE,   nil],
          ['/etc/SuSE-release',       Distribution::SUSE,        nil],
          ['/etc/ubuntu-release',     Distribution::UBUNTU,      nil],
          ['/etc/ubuntu-version',     Distribution::UBUNTU,      nil],
          ['/etc/mandrake-release',   Distribution::MANDRAKE,    nil],
        ]
      end
      
      class System < EC2::Platform::Base::System
        
        BUNDLING_ARCHITECTURE = EC2::Platform::Linux::Architecture.bundling    
        
        #---------------------------------------------------------------------#
        def self.distribution
          Distribution::IDENTITIES.each do |file, distro, regex|
            if File.exists? file 
              if regex.is_a? Regexp
                return distro if regex.match((IO.read file rescue nil))
              else              
                return distro
              end
            end
          end
          return Distribution::UNKNOWN
        end
        
        #---------------------------------------------------------------------#              
        def self.superuser?()
          return `id -u`.strip == '0'
        end
      end
    end
  end
end
