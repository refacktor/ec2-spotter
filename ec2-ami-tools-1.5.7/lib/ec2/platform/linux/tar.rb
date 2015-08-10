# Copyright 2008-2014 Amazon.com, Inc. or its affiliates.  All Rights
# Reserved.  Licensed under the Amazon Software License (the
# "License").  You may not use this file except in compliance with the
# License. A copy of the License is located at
# http://aws.amazon.com/asl or in the "license" file accompanying this
# file.  This file is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See
# the License for the specific language governing permissions and
# limitations under the License.

require 'ec2/platform/linux/constants'
module EC2
  module Platform
    module Linux
      class Tar
        class Command
          EXECUTABLE=EC2::Platform::Linux::Constants::Utility::TAR
          def initialize(e = EXECUTABLE)
            @files   = []
            @options = []
            @executable = e
          end
          
          def version;        @options << '--version';   self; end
          def verbose;        @options << '-v';          self; end
          def create;         @options << '-c';          self; end
          def bzip2;          @options << '-j';          self; end
          def diff;           @options << '-d';          self; end
          def gzip;           @options << '-z';          self; end
          def extract;        @options << '-x';          self; end
          def update;         @options << '-u';          self; end
          def sparse;         @options << '-S';          self; end
          def dereference;    @options << '-h';          self; end
          
          def archive(filename)
            filename = '-' if filename.nil? 
            @options << "-f #{filename}"
            self
          end

          def owner(user)
            @options << "--owner #{user}"
            self
          end

          def group(grp)
            @options << "--group #{grp}"
            self
          end
          
          def chdir(dir)
            @options << "-C #{dir}" unless dir.nil?
            self
          end
          
          def add(filename, dir = nil)
            item = dir.nil? ? filename : "-C #{dir} #{filename}"
            @files << item
            self
          end
          def expand
            "#{@executable} #{@options.join(' ')} #{@files.join(' ')}".strip            
          end
        end
        class Version
          RECOMMENDED  = 'tar 1.15'
          REGEX = /(?:tar).*?(\d+)\.(\d+)\.?(\d*)/
          attr_reader :values
          attr_reader :string
          
          def initialize(str=nil)
            @string = str
            @string = default if str.nil? or str.empty?
            @values = Version.parse @string
          end
          def default
            s = `#{Command.new.version.expand}`.strip
            s = nil unless $? == 0
            s
          end
          def string= (str)
            @string = str
            @values = Version.parse @string
          end
          def >= (other)
            return nil if @values.nil?
            if other.nil? or not other.is_a? Version
              raise ArgumentError, "Cannot compare with invalid version #{other}"
            end
            @values.zip(other.values).each do |mine, others|
              return false if mine < others
              return true if mine > others
            end
            return true
          end          
          def usable?
             self >= Version.new(Version::RECOMMENDED)
          end
          def self.parse(str)
            match = REGEX.match(str)
            return nil if match.nil?
            begin
              items = match.captures.collect do |cap|
                cap.sub!(/^0*/, "")
                case cap
                when ""
                  num = 0
                else
                  num = Integer(cap)
                end
              end
            rescue ArgumentError
              return nil
            end
            items
          end          
          def self.current
            Version.new
          end
        end
      end
    end
  end
end
