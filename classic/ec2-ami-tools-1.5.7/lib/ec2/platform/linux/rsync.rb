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
module EC2
  module Platform
    module Linux
      class Rsync
        class Command
          EXECUTABLE='rsync'
          def initialize(e = EXECUTABLE)
            @src   = nil
            @dst   = nil
            @options = []
            @executable = e
            @quiet = false
          end
          
          def archive;        @options << '-rlpgoD';     self; end
          def times;          @options << '-t';          self; end
          def recursive;      @options << '-r';          self; end
          def sparse;         @options << '-S';          self; end
          def links;          @options << '-l';          self; end
          def dereference;    @options << '-L';          self; end
          def xattributes;    @options << '-X';          self; end
          def version;        @options << '--version';   self; end
          def src(path)       @src = path;               self; end
          def dst(path)       @dst = path;               self; end
          def quietly;        @quiet = true;             self; end
          
          alias :source :src
          alias :from :src
          alias :destination :dst
          alias :to :dst
          
          def exclude(files)
            if files.is_a? Array
              files.each {|file| exclude file }
            else
              @options << "--exclude '#{files}'" unless files.nil?
            end
            self
          end

          def include(files)
            if files.is_a? Array
              files.each {|file| include file }
            else
              @options << "--include '#{files}'" unless files.nil?
            end
            self
          end
          
          def expand
            "#{@executable} #{@options.join(' ')} #{@src} #{@dst} #{'2>&1 > /dev/null' if @quiet}".strip
          end
        end

        def self.symlinking?
          begin
            src = FileUtil.tempdir('ec2-ami-tools-rsync-test-src')
            dst = FileUtil.tempdir('ec2-ami-tools-rsync-test-dst')
            FileUtils.mkdir(src)
            FileUtils.touch("#{src}/foo")
            FileUtils.symlink("#{src}/foo", "#{src}/bar")
            FileUtils.mkdir("#{src}/baz")
            File.open("#{src}/baz/food", 'w+'){|io| io << IO.read(__FILE__) }
            FileUtils.symlink("#{src}/baz/food", "#{src}/baz/bard")
            FileUtils.mkdir(dst)
            incantation = Command.new.archive.recursive.sparse.links.src("#{src}/").dst("#{dst}")
            `#{incantation.expand} 2>&1`
            rc = $?.exitstatus
            return true if rc == 0
            if rc == 23
              #check that the structure was copied reasonably anyway
              slist = Dir["#{src}/**/**"]
              dlist = Dir["#{dst}/**/**"]
              return false unless dlist == dlist
              slist.each do |sitem|
                ditem = item.gsub(src, dst)
                return false unless dlist.include? ditem 
                if File.file?(sitem) or File.symlink?(sitem)
                  @out.print "comparing #{sitem} to #{ditem}" if @out
                  return false unless IO.read(ditem) == IO.read(sitem)
                end
                if ['food', 'bard'].include? File.basename(ditem)
                  return false unless IO.read(sitem) == IO.read(__FILE__)
                end
              end
              return true
            end
            return false
          rescue Exception
            return false
          ensure
            FileUtils.rm_rf src
            FileUtils.rm_rf dst
          end      
        end
        
        def self.usable?()
          @@usable ||= self.symlinking?
        end
      end
    end
  end
end
