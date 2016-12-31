# Copyright 2008-2014 Amazon.com, Inc. or its affiliates.  All Rights
# Reserved.  Licensed under the Amazon Software License (the
# "License").  You may not use this file except in compliance with the
# License. A copy of the License is located at
# http://aws.amazon.com/asl or in the "license" file accompanying this
# file.  This file is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See
# the License for the specific language governing permissions and
# limitations under the License.

#--------------------------------------------------------------------------
# Definition of constant values used by the AMI tools
#------------------------------------------------------------------------
module EC2
  module Platform
    module Base
      module Constants
        module Bundling
          EC2_HOME = ENV["EC2_AMITOOL_HOME"] || ENV["EC2_HOME"]
          EC2_X509_CERT = File.join(EC2_HOME.to_s, '/etc/ec2/amitools/cert-ec2.pem')
          EC2_X509_GOV_CERT = File.join(EC2_HOME.to_s, '/etc/ec2/amitools/cert-ec2-gov.pem')
          EC2_X509_CN_NORTH_1_CERT = File.join(EC2_HOME.to_s, '/etc/ec2/amitools/cert-ec2-cn-north-1.pem')
          EC2_MAPPING_FILE = File.join(EC2_HOME.to_s, '/etc/ec2/amitools/mappings.csv')
          EC2_MAPPING_URL = 'https://ec2-downloads.s3.amazonaws.com/mappings.csv'
          DESTINATION = '/tmp'
        end
        module Utility
          OPENSSL = 'openssl'
          RSYNC = 'rsync'
          TAR = 'tar'
          TEE = 'tee'
          GZIP = 'gzip'
        end
        module Security
          FILE_FILTER = [
              '*/#*#',
              '*/.#*',
              '*.sw',
              '*.swo',
              '*.swp',
              '*~',
              '*.pem',
              '*.priv',
              '*id_rsa*',
              '*id_dsa*',
              '*.gpg',
              '*.jks',
              '*/.ssh/authorized_keys',
              '*/.bash_history']
        end
      end
    end
  end
end
