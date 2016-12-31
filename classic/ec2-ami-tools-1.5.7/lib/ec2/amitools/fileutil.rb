# Copyright 2008-2014 Amazon.com, Inc. or its affiliates.  All Rights
# Reserved.  Licensed under the Amazon Software License (the
# "License").  You may not use this file except in compliance with the
# License. A copy of the License is located at
# http://aws.amazon.com/asl or in the "license" file accompanying this
# file.  This file is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See
# the License for the specific language governing permissions and
# limitations under the License.

# Utility class and methods.

require 'ec2/amitools/exception'
require 'tmpdir'
require 'fileutils'
require 'pathname'
require 'tempfile'
require 'zlib'

##
# Module containing file utility methods.
#
module FileUtil
  include Zlib
  BUFFER_SIZE = 1024 * 1024	# Buffer size in bytes.
  PART_SUFFIX = '.part.'

  #----------------------------------------------------------------------------#

  ##
  # Assert the specified file exists.
  # An exception is raised if it does not.
  #
  def FileUtil.assert_exists(filename)
    raise FileError(filename, 'a required file could not be found') unless exists?(filename)
  end

  #----------------------------------------------------------------------------#

  ##
  # Compress the specified file and return the path to the temporary compressed
  # file that will be deleted upon termination of the process.
  #
  def FileUtil.compress(filename)
    outfilename = filename+'.gz'    
    GzipWriter.open(outfilename) do |outfile|
      begin
        File.open(filename, 'r') do |infile|
          while not (infile.eof)
             outfile.write(infile.read(BUFFER_SIZE))
          end
        end
      ensure

      end
    end
    outfilename
  end

  #----------------------------------------------------------------------------#

  ##
  # Expand ((|src_filename|)) to ((|dst_filename|)).
  #
  def FileUtil.expand(src_filename, dst_filename)
    GzipReader.open(src_filename) do |gzfile|
      File.open(dst_filename, 'w') do |file|
        while not (gzfile.eof?)
          file.write(gzfile.read(BUFFER_SIZE))
        end
      end
    end
  end

  #----------------------------------------------------------------------------#

  ##
  # Split the specified file into chunks of the specified size.
  # yields the <file,chunk,chunk size> to a block which writes the actual chunks
  # The chunks are output to the local directory.
  # Typical invocation looks like:
  # FileUtil.split('file',5){|sf,cf,cs| ChunkWriter.write_chunk(sf,cf,cs)}
  #
  # ((|filename|)) The file to split.
  # ((|part_name_prefix|)) The prefix for the parts filenames.
  # ((|cb_size|)) The chunk size in bytes.
  # ((|dst_dir|)) The destination to create the file parts in.
  #
  # Returns a list of the created filenames.
  #
  def FileUtil.split(filename, part_name_prefix, cb_size, dst_dir)
    begin
      # Check file exists and is accessible.
      begin
        file = File.new(filename, File::RDONLY)
      rescue SystemCallError => e
        raise FileError.new(filename, "could not open file to split", e)
      end
      
      # Create the part file upfront to catch any creation/access errors
      # before writing out data.
      nr_parts = (Float(File.size(filename)) / Float(cb_size)).ceil
      part_names = []
      nr_parts.times do |i|
        begin
          nr_parts_digits = nr_parts.to_s.length
          part_name_suffix = PART_SUFFIX + i.to_s.rjust(nr_parts_digits).gsub(' ', '0')
          part_names[i] = part_name = part_name_prefix + part_name_suffix
          FileUtils.touch File.join(dst_dir, part_name)
        rescue SystemCallError => e
          raise FileError.new(filename, "could not create part file", e)
        end
      end
      
      # Write parts to files.
      part_names.each do |part_file_name|
        File.open(File.join(dst_dir, part_file_name), 'w+') do |pf|
          write_chunk(file, pf, cb_size)
        end
      end

      part_names
    ensure
      file.close if not file.nil?
    end
  end

  #----------------------------------------------------------------------------#

  ##
  # Concatenate the specified files into a single file.
  # If the specified output file already exists it will be overwritten.
  # ((|filenames|)) An ordered collection of the names of split files.
  # ((|out_filename|)) The output filename.
  #
  def FileUtil.cat(filenames, out_filename)
    File.open(out_filename, 'w') do |of|
      filenames.each do |filename|
        File.open(filename) do |file|
          while not (file.eof?)
            of.write(file.read(BUFFER_SIZE))
            of.flush
          end
        end
      end
    end
  end 

  #----------------------------------------------------------------------------#
  
  def FileUtil.exists?(fullname)
    FileTest.exists?(fullname)
  end
  
  #----------------------------------------------------------------------------#
  
  def FileUtil.directory?(fullname)
    File::Stat.new(fullname).directory?
  end
  
  #----------------------------------------------------------------------------#
  
  def FileUtil.symlink?(fullname)
    File::Stat.new(fullname).symlink?
  end

  #----------------------------------------------------------------------------#

  def FileUtil.tempdir(basename, tmpdir=Dir::tmpdir, tries=10)
    tmpdir = '/tmp' if $SAFE > 0 and tmpdir.tainted?
    fail = 0
    tmpname = nil
    begin
      begin
        tmpname = File.join(tmpdir, sprintf('%s%d.%s', basename, $$, Time.now.to_f.to_s))
      end until !File.exist? tmpname
    rescue
      fail += 1
      retry if fail < tries
      raise "failed to generate a temporary directory name '%s'" % tmpname
    end
    tmpname
  end


  #----------------------------------------------------------------------------#

  def FileUtil.size(f)
    total =  `du -s #{f}`.split[0].to_i rescue nil
    if total.nil? or $?.exitstatus != 0
      total = 0
      Find.find(f) do |s| 
        total += File.directory?(s) ? 0 : File.size(s)
      end
    end
    total
  end
  
  #----------------------------------------------------------------------------#

  ##
  # Write chunk to file.
  # ((|sf|)) Source file.
  # ((|cf|)) Chunk file.
  # ((|cs|)) Chunk size in bytes.
  # Returns true if eof was encountered.
  #  
  def FileUtil.write_chunk(sf, cf, cs)
    cb_written = 0  # Bytes written.
    cb_left = cs    # Bytes left to write in this chunk.
    while (!sf.eof? && cb_left > 0) do
      buf = sf.read(BUFFER_SIZE < cb_left ? BUFFER_SIZE : cb_left)
      cf.write(buf)
      cb_written += buf.length
      cb_left = cs - cb_written
    end
    sf.eof
  end 
end
