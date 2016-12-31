# Copyright 2008-2014 Amazon.com, Inc. or its affiliates.  All Rights
# Reserved.  Licensed under the Amazon Software License (the
# "License").  You may not use this file except in compliance with the
# License. A copy of the License is located at
# http://aws.amazon.com/asl or in the "license" file accompanying this
# file.  This file is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See
# the License for the specific language governing permissions and
# limitations under the License.

require 'open-uri'

module EC2
  class InstanceData

    META_DATA_URL = "http://169.254.169.254/latest/meta-data/"

    attr_reader :instance_data_accessible

    def initialize(meta_data_url = META_DATA_URL)
      @meta_data_url = meta_data_url
      # see if we can access the meta data. Be unforgiving - if anything goes wrong 
      # just mark instance data as unaccessible.
      begin
        open(@meta_data_url)
        @instance_data_accessible = true
      rescue StandardError => e
        @instance_data_accessible = false
      end
    end

    def kernel_id
      read_meta_data('kernel-id')
    end
    
    def ramdisk_id
      read_meta_data('ramdisk-id')
    end

    def ami_id
      read_meta_data('ami-id')
    end

    def ancestor_ami_ids
      read_meta_data_list('ancestor-ami-ids')
    end

    def product_codes
      read_meta_data_list('product-codes')
    end

    def block_device_mapping
      read_meta_data_hash('block-device-mapping')
    end

    def availability_zone
      read_meta_data('placement/availability-zone')
    end

    def read_meta_data_hash(path)
      keys = list_meta_data_index(path)
      return nil if keys.nil?
      hash = {}
      keys.each do |key|
        value = read_meta_data(File.join(path, key))
        hash[key] = value if value
      end
      hash
    end
    private :read_meta_data_hash

    def read_meta_data_list(path)
      list = read_meta_data(path)
      list.nil? ? nil : list.split("\n")
    end
    private :read_meta_data_list

    def list_meta_data_index(path)
      read_meta_data_list(File.join(path, ''))
    end
    private :list_meta_data_index

    def read_meta_data(path)
      nil if !@instance_data_accessible
      begin
        open(File.join(@meta_data_url, path)) do |cio|
          return cio.read.to_s.strip
        end
      rescue
        return nil
      end
    end
    private :read_meta_data

  end
end

