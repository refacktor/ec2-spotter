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
    module Linux
      LOCAL_FS_TYPES = ['ext2', 'ext3', 'ext4', 'xfs', 'jfs', 'reiserfs', 'tmpfs']
      class Mtab
        class Entry
          REGEX = /^(\S+)\s+(\S+)\s+(\S+)\s+(\S+).*$/
          attr_reader :device   # mounted device.
          attr_reader :mpoint   # mount point.
          attr_reader :fstype   # file system type.
          attr_reader :options  # options
          attr_reader :value    # entire line
          
          
          def initialize(dev, mnt_point, fs_type, opts, line)
            @device = dev
            @mpoint = mnt_point
            @fstype = fs_type
            @options= opts
            @value  = line
          end
          
          def self.parse(line)
            return nil if line[0,1] == '#'
            if (m = REGEX.match(line))
              parts = m.captures
              return Entry.new(parts[0], parts[1], parts[2], parts[3], line.strip)
            else
              return nil
            end
          end
          
          def to_s
            value
          end
          
          def print
            puts(to_s)
          end
        end
        
        attr_reader :entries
        LOCATION = '/etc/mtab'
        
        def initialize(filename = LOCATION)
          begin
            f = File.new(filename, File::RDONLY)
          rescue SystemCallError => e
            raise FileError(filename, "could not open #{filename} to read mount table", e)
          end
          @entries = Hash.new
          f.readlines.each do |line|
            entry = Entry.parse(line)
            @entries[entry.mpoint] = entry unless entry.nil?
          end          
        end
        
        def self.load
          self.new()
        end
      end
    end
  end
end
