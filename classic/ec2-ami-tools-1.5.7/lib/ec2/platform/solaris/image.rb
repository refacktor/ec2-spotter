# Copyright 2008-2014 Amazon.com, Inc. or its affiliates.  All Rights
# Reserved.  Licensed under the Amazon Software License (the
# "License").  You may not use this file except in compliance with the
# License. A copy of the License is located at
# http://aws.amazon.com/asl or in the "license" file accompanying this
# file.  This file is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See
# the License for the specific language governing permissions and
# limitations under the License.

#---------------------------------------------------------------------#
# Create a Solaris EC2 Image as follows:
#  - create a bootable file-system archive in the SUN flash format
#  - create, format and mount a blank file-system image
#  - replicate the archive section of the flash archive into the image
#  - customize the image
#
# Fasten your seat-belts and grab a pillow; this is painfully slow.
# Initial tests show an average bundling time of a virgin OpenSolaris
# system using this algorithm to be about 85-90 minutes. Optimization
# involves rewriting flar to combine the "flar create" and "flar split"
# steps into a "flar replicate" step
#---------------------------------------------------------------------#

require 'fileutils'
require 'ec2/oem/open4'
require 'ec2/amitools/fileutil'
require 'ec2/amitools/syschecks'
require 'ec2/amitools/exception'
require 'ec2/platform/solaris/mtab'
require 'ec2/platform/solaris/fstab'
require 'ec2/platform/solaris/constants'

module EC2
  module Platform
    module Solaris

    class ExecutionError < RuntimeError
    end

      # This class encapsulate functionality to create an file loopback image
      # from a volume. The image is created using mkfile. Sub-directories of the
      # volume, including mounts of local filesystems, are copied to the image.
      # Symbolic links are preserved wherever possible.
      class Image
        EXCLUDES  = [ '/mnt' ]
        WORKSPACE = '/mnt/ec2-bundle-workspace'
        MOUNT     = File.join( WORKSPACE, 'mnt' )
        ARCHIVE   = File.join( WORKSPACE, 'archive' )
        PROFILING = true
        RETRIES   = 5
        DELAY     = 10
        #---------------------------------------------------------------------#
        def initialize( volume,             # path to volume to be bundled
                        filename,           # name of image file to create
                        size,               # size of image file in MB
                        exclude,            # list of directories to exclude
                        includes,           # This does absolutely nothing on solaris - warrenr
                        filter,             # Same as above - warrenr
                        vfstab=nil,         # file system table to use
                        part_type=nil,      # Disk partition type: MBR/GPT etc
                        arch=nil,           # Architecture of the bundled volume
                        script=nil,         # Post-cloning customization script
                        debug = false )
          @volume = volume
          @filename = filename
          @size = size
          @exclude = exclude
          @debug = debug
          @arch = arch
          @script = script
          self.set_partition_type( part_type )
          if vfstab.nil? or vfstab == :legacy
            @vfstab = EC2::Platform::Solaris::Fstab::DEFAULT
          elsif File.exists? vfstab
            @vfstab = IO.read(vfstab)
          else
            @vfstab = vfstab
          end

          # Exclude the workspace if it is in the volume being bundled.
          @exclude << WORKSPACE if( WORKSPACE.index(volume) == 0 )
        end

        #---------------------------------------------------------------------#
        def set_partition_type( input )
          input ||= EC2::Platform::PartitionType::NONE
          if input == EC2::Platform::PartitionType::NONE
            @part_type = EC2::Platform::PartitionType::NONE
          else
            raise NotImplementedError, "Disk images not supported for Solaris"
          end
        end

        #---------------------------------------------------------------------#
        # Clone a running volume into a bootable Amazon Machine Image.
        def make
          begin
            announce( "Cloning #{@volume} into image file #{@filename}...", true)
            announce( 'Excluding: ', true )
            @exclude.each { |x| announce( "\t #{x}", true ) }
            archive
            prepare
            replicate
          ensure
            cleanup
          end
        end

        private


        #---------------------------------------------------------------------#
        # Create, format and mount the blank machine image file.
        # TODO: investigate parallelizing prepare() with archive()
        def prepare
          FileUtils.mkdir_p( MOUNT )
          announce( 'Creating and formatting file-system image...', true )
          evaluate( "/usr/sbin/mkfile #{@size*1024*1024} #{@filename}" )

          announce( 'Formatting file-system image...' )
          execute( 'sync && devfsadm -C' )
          @device = evaluate('/usr/sbin/lofiadm -a ' + @filename).strip
          number = @device.split(/\//).last rescue nil
          raise FatalError.new('Failed to attach image to a device' ) unless number
          execute( "echo y | newfs /dev/rlofi/#{number} < /dev/null > /dev/null 2>&1", true )

          execute( 'sync' )
          mount( @device, MOUNT )
        end

        #---------------------------------------------------------------------#
        # Create a flash archive of the system at the desired volume root.
        def archive
          FileUtils.mkdir_p( WORKSPACE )
          announce( 'Creating flash archive of file system...', true )
          exempt = []
          @exclude.each do |item|
            item = File.expand_path(item)
            # Since flarcreate does not allow you to exclude a mount-point from
            # a flash archive, we work around this by listing the files in that
            # directory and excluding them individually.
            if mounted? item
              exempt.concat( evaluate( 'ls -A ' + item).split(/\s/).map{|i| File.join( item, i ) } )
            else
              exempt << item
            end
          end
          exempt = exempt.join( ' -x ')

          invocation = ['flar create -n ec2.archive -S -R ' + @volume ]
          invocation << ( '-x ' + exempt ) unless exempt.empty?
          invocation << ARCHIVE
          evaluate( invocation.join( ' ' ) )
          raise FatalError.new( "Archive creation failed" ) unless File.exist?( ARCHIVE )

          asize = FileUtil.size( ARCHIVE ) / ( 1024 * 1024 )
          raise FatalError.new( "Archive too small" ) unless asize > 0
          raise FatalError.new( 'Archive exceeds target size' ) if asize > @size
        end

        #---------------------------------------------------------------------#
        # Extract the archive into the file-system image.
        def replicate
          announce( 'Replicating archive to image (this will take a while)...', true )
          # Extract flash archive into mounted image. The flar utility places
          # the output in a folder called 'archive'. Since we cannot override
          # this, we need to extract the content, move it to the image root
          # and delete remove the cruft
          extract = File.join( MOUNT, 'archive')
          execute( "flar split -S archive -d #{MOUNT} -f #{ARCHIVE}" )
          execute( "ls -A #{extract} | xargs -i mv #{extract}/'{}' #{MOUNT}" )
          FileUtils.rm_rf( File.join(MOUNT, 'archive') )
          FileUtils.rm_rf( File.join(MOUNT, 'identification') )

          announce 'Saving system configuration...'
          ['/boot/solaris/bootenv.rc', '/etc/vfstab', '/etc/path_to_inst'].each do |path|
            file = File.join( MOUNT, path )
            FileUtils.cp( file, file + '.phys' )
          end

          announce 'Fine-tuning system configuration...'
          execute( '/usr/sbin/sys-unconfig -R ' + MOUNT )
          bootenv = File.join( MOUNT, '/boot/solaris/bootenv.rc' )
          execute( "sed '/setprop bootpath/,/setprop console/d' < #{bootenv}.phys > #{bootenv}" )
          execute( "sed '/dsk/d' < #{MOUNT}/etc/vfstab.phys > #{MOUNT}/etc/vfstab" )

          FileUtils.rm_f( File.join(MOUNT, '/etc/rc2.d/S99dtlogin') )

          announce 'Creating missing image directories...'
          [ '/dev/dsk', '/dev/rdsk', '/dev/fd', '/etc/mnttab', ].each do |item|
            FileUtils.mkdir_p( File.join( MOUNT, item ) )
          end

          FileUtils.ln_s( '../../devices/xpvd/xdf@0:a', File.join( MOUNT, '/dev/dsk/c0d0s0' ) )
          FileUtils.ln_s( '../../devices/xpvd/xdf@0:a,raw', File.join( MOUNT, '/dev/rdsk/c0d0s0' ) )

          FileUtils.touch( File.join( MOUNT, Mtab::LOCATION ) )
          fstab = File.join( MOUNT, Fstab::LOCATION )
          File.open(fstab, 'w+') {|io| io << @vfstab }
          announce( "--->/etc/vfstab<---:\n" + @vfstab , true )

          execute( "bootadm update-archive -R #{MOUNT} > /dev/null 2>&1", true )

          announce( 'Disable xen services' )
          file = File.join( MOUNT, '/var/svc/profile/upgrade' )
          execute( 'echo "/usr/sbin/svcadm disable svc:/system/xctl/xend:default" >> ' + file )

          announce 'Setting up DHCP boot'
          FileUtils.touch( File.join( MOUNT, '/etc/hostname.xnf0' ) )
          FileUtils.touch( File.join( MOUNT, '/etc/dhcp.xnf0' ) )

          announce 'Setting keyboard layout'
          kbd = File.join( MOUNT, '/etc/default/kbd' )
          execute( "egrep '^LAYOUT' #{kbd} || echo 'LAYOUT=US-English' >> #{kbd}" )

          customize
        end

        def customize
          return unless @script and File.executable?(@script)
          announce 'Customizing replicated volume mounted at %s with script %s' % [MOUNT, @script]
          output = evaluate('%s "%s"' % [@script, MOUNT])
          STDERR.puts output if @debug
        end

        #---------------------------------------------------------------------#
        # Mount the specified device. The mount point is created if necessary.
        # We let mount guess the appropriate file system type.
        def mount(device, mpoint)
          FileUtils.mkdir_p(mpoint) if not FileUtil::exists?(mpoint)
          raise FatalError.new("image already mounted") if mounted?(mpoint)
          execute( 'sync' )
          execute( 'mount ' + device + ' ' + mpoint )
        end

        #---------------------------------------------------------------------#

        def unmount(mpoint, force=false)
          GC.start
          execute( 'sync && sync && sync' )
          if mounted?( mpoint ) then
            execute( 'umount ' + (force ? '-f ' : '') + mpoint )
          end
        end

        #---------------------------------------------------------------------#

        def mounted?(mpoint)
          EC2::Platform::Solaris::Mtab.load.entries.keys.include? mpoint
        end

        #---------------------------------------------------------------------#
        # Cleanup after self:
        # - unmount relevant mount points.
        # - release any device and resources attached to the image and mount-point
        # - delete any intermediate files and directories.
        def cleanup
          attempts = 0
          begin
            unmount( MOUNT )
          rescue ExecutionError
            announce "Unable to unmount image. Retrying after a short sleep."
            attempts += 1
            if attempts < RETRIES
              sleep DELAY
              retry
            else
              announce( "Unable to unmount image after #{RETRIES} attempts. Baling out...", true )
              unmount( MOUNT, true )
              if File.exist?( @filename )
                announce( "Deleting image file #{@filename}..." )
                FileUtils.rm_f( @filename )
              end
            end
          end
          unless @device.nil?
            devices = evaluate( 'lofiadm' ).split( /\n/ )
            devices.each do |item|
              execute( 'lofiadm -d' + @device ) if item.index( @device ) == 0
            end
          end
          execute( 'devfsadm -C' )
          FileUtils.rm_rf( WORKSPACE ) if File.directory?( WORKSPACE )
        end

        #---------------------------------------------------------------------#
        # Output a message if running in debug mode
        def announce(something, force=false)
          STDOUT.puts( something ) if @debug or force
        end

        #---------------------------------------------------------------------#
        # Execute the command line passed in.
        def execute( cmd, verbattim = false )
          verbattim ||= @debug
          invocation = [ cmd ]
          invocation << ' 2>&1 > /dev/null' unless verbattim
          announce( "Executing: '#{cmd}' " )
          time = Time.now
          raise ExecutionError.new( "Failed to execute '#{cmd}'.") unless system( invocation.join )
          announce( "Time: #{Time.now - time}s", PROFILING )
        end

        #---------------------------------------------------------------------#
        # Execute command line passed in and return STDOUT output if successful.
        def evaluate( cmd, success = 0, verbattim = false )
          verbattim ||= @debug
          cmd << ' 2> /dev/null' unless verbattim
          announce( "Evaluating: '#{cmd}' " )
          time = Time.now
          pid, stdin, stdout, stderr = Open4::popen4( cmd )
          ignore stdin
          pid, status = Process::waitpid2 pid
          unless status.exitstatus == success
            raise ExecutionError.new( "Failed to evaluate '#{cmd }'. Reason: #{stderr.read}." )
          end
          announce( "Time: #{Time.now - time}s", PROFILING )
          stdout.read
        end

        def ignore(stuff) stuff end

      end
    end
  end
end
