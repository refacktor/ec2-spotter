# Copyright 2008-2014 Amazon.com, Inc. or its affiliates.  All Rights
# Reserved.  Licensed under the Amazon Software License (the
# "License").  You may not use this file except in compliance with the
# License. A copy of the License is located at
# http://aws.amazon.com/asl or in the "license" file accompanying this
# file.  This file is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See
# the License for the specific language governing permissions and
# limitations under the License.

require 'fileutils'
require 'pathname'
require 'ec2/oem/open4'
require 'ec2/amitools/fileutil'
require 'ec2/amitools/syschecks'
require 'ec2/amitools/exception'
require 'ec2/platform/linux/mtab'
require 'ec2/platform/linux/fstab'
require 'ec2/platform/linux/constants'

module EC2
  module Platform
    module Linux

      # This class encapsulate functionality to create an file loopback image
      # from a volume. The image is created using dd. Sub-directories of the
      # volume, including mounts of local filesystems, are copied to the image.
      # Symbolic links are preserved.
      class Image
        IMG_MNT = '/mnt/img-mnt'
        EXCLUDES= ['/dev', '/media', '/mnt', '/proc', '/sys']
        DEFAULT_FSTAB = EC2::Platform::Linux::Fstab::DEFAULT
        LEGACY_FSTAB  = EC2::Platform::Linux::Fstab::LEGACY
        BASE_UTILS = [ 'modprobe', 'mount', 'umount', 'dd' ]
        PART_UTILS = [ 'dmsetup', 'kpartx', 'losetup' ]
        CHROOT_UTILS = [ 'grub' ]

        #---------------------------------------------------------------------#

        # Initialize the instance with the required parameters.
        # * _volume_ The path to the volume to create the image file from.
        # * _image_filename_ The name of the image file to create.
        # * _mb_image_size_ The image file size in MB.
        # * _exclude_ List of directories to exclude.
        # * _debug_ Make extra noise.
        def initialize( volume,
                        image_filename,
                        mb_image_size,
                        exclude,
                        includes,
                        filter = true,
                        fstab = nil,
                        part_type = nil,
                        arch = nil,
                        script = nil,
                        debug = false,
                        grub_config = nil )
          @volume = volume
          @image_filename = image_filename
          @mb_image_size = mb_image_size
          @exclude = exclude
          @includes = includes
          @filter = filter
          @arch = arch || EC2::Platform::Linux::Uname.platform
          @script = script
          @fstab = nil
          @conf = grub_config
          @warnings = Array.new

          self.verify_runtime(BASE_UTILS)
          self.set_partition_type(part_type)

          # Cunning plan or horrible hack?
          # If :legacy is passed in as the fstab, we use the old v3 manifest's
          # device naming and fstab.
          if [:legacy, :default].include? fstab
            @fstab = fstab
          elsif not fstab.nil?
            @fstab = File.open(fstab).read()
          end
          @debug = debug

          # Exclude the temporary image mount point if it is under the volume
          # being bundled.
          if IMG_MNT.index( volume ) == 0
            @exclude << IMG_MNT
          end
        end

        #--------------------------------------------------------------------#

        def make_hash(array)
          hash = Hash.new
          array.each do |entry|
            # Split on the first '='
            key, value = entry.split('=', 2)
            hash[key] = value || ''
          end
          hash
        end

        def compare_hashes(a, b)
          a.each do |key,value|
            if not b.has_key?(key)
              @warnings.push "\t* Missing key '#{key}' with value '#{value}'"
            elsif b[key] != value
              @warnings.push "\t* Key '#{key}' value '#{b[key]}' differs from /proc/cmdline value '#{value}'"
            end
          end
        end

        def remove_kernel(tokens)
          if tokens.include?('kernel')
            tokens.delete('kernel')
            # The kernel can receive optional arguments, drop those along with the kernel
            kernel_index = tokens.index{ |token| !token.include?('--') }
            tokens = tokens.drop(kernel_index + 1)
          end
          tokens
        end

        def tokenize(string)
          string.strip.split(/\s+/)
        end

        def check_kernel_parameters(conf)
          cmdline = File.read('/proc/cmdline')
          cmdline_hash = make_hash(tokenize(cmdline))

          default = nil
          File.readlines(conf).each do |line|
            match = line.match(/^default.*([\d+])/)
            if match
              default = match.captures[0]
            end
          end
          if not default
            STDERR.puts "Couldn't find default kernel designation in grub config. The resulting image may not boot."
            return
          end
          default = default.to_i

          kernels = File.readlines(conf).grep(/^\s*kernel/)
          kernel_line = kernels[default]

          kernel_line = remove_kernel(tokenize(kernel_line))
          kernel_hash = make_hash(kernel_line)

          compare_hashes(cmdline_hash, kernel_hash)

          if not @warnings.empty?
            $stdout.puts "Found the following differences between your kernel " +
                         "commandline and the grub configuration on the volume:"

            @warnings.each do |warning|
              $stdout.puts warning
            end

            $stdout.puts "Please verify that the kernel command line in " +
                         "#{File.expand_path(conf)} is correct for your new AMI."
          end
        end

        # Create the loopback image file and copy volume to it.
        def make
          begin
            puts( "Copying #{@volume} into the image file #{@image_filename}...")
            puts( 'Excluding: ' )
            @exclude.each { |x| puts( "\t #{x}" ) }

            create_image_file
            format_image
            execute( 'sync' )  # Flush so newly formatted filesystem is ready to mount.
            mount_image
            copy_rec( @volume, IMG_MNT)
            update_fstab
            customize_image
            finalize_image
          ensure
            cleanup
          end
        end

        #---------------------------------------------------------------------#
        # Ensure we have the specified commonly-needed utils in the PATH.
        def verify_runtime(utils, chroot = nil)
          unless ENV['PATH']
            raise FatalError.new('PATH not set, cannot find needed utilities')
          end

          paths = ENV['PATH'].split(File::PATH_SEPARATOR)
          paths.map! { |path| File.join(chroot, path) } if chroot

          utils.each do |util|
            unless paths.any? { |dir| File.executable?(File.join(dir, util)) }
              raise FatalError.new("Required utility '%s' not found in PATH - is it installed?" % util)
            end
          end
        end

        def check_deps(part_type)
            if part_type == EC2::Platform::PartitionType::MBR
              self.verify_runtime([ 'parted' ])
              self.verify_runtime(CHROOT_UTILS, @volume)
            elsif part_type == EC2::Platform::PartitionType::GPT
              self.verify_runtime([ 'sgdisk' ])
              self.verify_runtime(CHROOT_UTILS, @volume)
            end
        end

        #---------------------------------------------------------------------#
        # Assign an appropriate partition type. The current implementation will
        # fail to bundle volumes that reside on devices whose partition schemes
        # deviate from what is commonly available in EC2, namely a partitioned
        # disk with the root file system residing on the first partition.
        ROOT_DEVICE_REGEX = /^(\/dev\/(?:xvd|sd)(?:[a-z]|[a-c][a-z]|d[a-x]))[1]?$/

        def set_partition_type(input)
          input ||= EC2::Platform::PartitionType::NONE
          if input == EC2::Platform::PartitionType::NONE
            # We are not doing anything interesting. Return early.
            puts('Not partitioning boot device.')
            @part_type = EC2::Platform::PartitionType::NONE
            return
          end

          # Verify that general partitioning utilities are present
          self.verify_runtime(PART_UTILS)

          value = input
          puts('Setting partition type to bundle "%s" with...' % [@volume])
          if File.directory?(@volume)
            mtab = EC2::Platform::Linux::Mtab.load
            entry = mtab.entries[@volume]
            if entry
              # Volume is a mounted file system:
              # * Determine the mounted device
              # * Ensure device partition scheme is one that we understand
              # * Ensure device and it's container(if applicable) are block devices
              # * Determine the current partition type using parted if appropriate.
              device = entry.device
              root = nil
              if (match = ROOT_DEVICE_REGEX.match(device))
                root = match[1]
                root = device unless File.exists?(root) # classic AMI with no partition table
                # Be paranoid. Bail unless the device and parent are block devices
                [device, root].each do |dev|
                  unless File.blockdev?(dev)
                    raise FatalError.new('Not a block device: %s' % [dev])
                  end
                end
              else
                raise FatalError.new('Non-standard volume device "%s"' % [device])
              end
              if input == :auto
                self.verify_runtime([ 'parted' ])
                puts('Auto-detecting partition type for "%s"' % [@volume])
                cmd = "parted -s %s print|awk -F: '/^Partition Table/{print $2}'" % [root]
                value = evaluate(cmd).strip
                raise FatalError.new('Cannot determine partition type') if value.empty?
                puts('Partition label detected using parted: "%s"' % value)
              end
            else
              # Volume specified is possibly a file system root:
              #   * Proceed cautiously using sane defaults if no partition type
              #     has been provided.
              puts('Volume "%s" is not a mount point.'  % [@volume])
              value = EC2::Platform::PartitionType::GPT if input == :auto
              puts('Treating it as a file system root and using "%s"...' % [value])
            end
          elsif File.blockdev?(@volume)
            # Volume specified is a block device:
            #   * Not sure how we got here.
            #   * We only support bundling of file system roots and not block
            #     devices, so throw an exception.
            raise FatalError('Volume cannot be a block device "%s".' % [@volume])
          else
            # Volume specified is not a file system (mounted or otherwise):
            #   * Bail!
            raise FatalError.new('Cannot determine partition type of "%s"' % [@volume])
          end

          if EC2::Platform::PartitionType.valid?(value)
            @part_type = value
          elsif value == 'msdos'
            # This is the parted label value reported for MBR partition tables.
            @part_type = EC2::Platform::PartitionType::MBR
          elsif value == 'loop'
            # This typically indicates that we have a bare partition that is not
            # part of a partition table. This is typically the case for pv amis.
            @part_type = EC2::Platform::PartitionType::NONE
          elsif value == 'gpt'
            @part_type = EC2::Platform::PartitionType::GPT
          elsif value
            if input == :auto
              # Somehow we failed to determine a partition type that we support
              raise FatalError.new('Could not determine a suitable partition type')
            else
              # User specified a format we currently do not support. Bail.
              raise FatalError.new('Unsupported partition table type %s' % input)
            end
          else
            raise FatalError.ne('Cannot determine partition type for %s' % [@volume])
          end
          puts('Using partition type "%s"' % @part_type)

          self.check_deps(@part_type)
        end

        #---------------------------------------------------------------------#

        def settle
          # Run sync and udevadm settle to quiet device.
          execute('sync||:')
          if File.executable?('/usr/sbin/udevsettle')
            execute('/usr/sbin/udevsettle||:')
          elsif File.executable?('/sbin/udevadm')
            execute('/sbin/udevadm settle||:')
          end
        end

        #---------------------------------------------------------------------#
        # Returns true if we are trying to build a valid disk image
        def is_disk_image?
          EC2::Platform::PartitionType.valid?(@part_type)
        end

        private

        #---------------------------------------------------------------------#

        def unmount(mpoint)
          if mounted?(mpoint) then
              execute('umount -d ' + mpoint)
          end
        end

        #---------------------------------------------------------------------#

        def mounted?(mpoint)
          EC2::Platform::Linux::Mtab.load.entries.keys.include? mpoint
        end

        #---------------------------------------------------------------------#

        # Unmount devices. Delete temporary files.
        def cleanup
          # Unmount image file.
          if self.is_disk_image?
            unmount('%s/sys' % IMG_MNT)
            unmount('%s/proc' % IMG_MNT)
            unmount('%s/dev' % IMG_MNT)
          end

          unmount(IMG_MNT)
          if self.is_disk_image? and @diskdev
            diskname = File.basename(@diskdev)
            execute('kpartx -d %s' % @diskdev)
            execute('dmsetup remove %s' % diskname)
            execute('losetup -d %s' % @diskloop)
          end
        end

        #---------------------------------------------------------------------#

        # Call dd to create the image file.
        def create_image_file
          cmd = "dd if=/dev/zero status=noxfer of=" + @image_filename +
                " bs=1M count=1 seek=" + (@mb_image_size-1).to_s
          execute( cmd )
        end

        #---------------------------------------------------------------------#

        # Format the image file, tune filesystem not to fsck based on interval.
        # Where available and possible, retain the original root volume label
        # uuid and file-system type falling back to using ext3 if not sure of
        # what to do.
        def format_image
          mtab = EC2::Platform::Linux::Mtab.load
          root = mtab.entries[Pathname(@volume).realpath.to_s].device rescue nil
          info = fsinfo( root )
          label= info[:label]
          uuid = info[:uuid]
          type = info[:type] || 'ext3'
          execute('modprobe loop') unless File.blockdev?('/dev/loop0')

          target = nil
          if self.is_disk_image?
            cmd = []
            img = @image_filename
            size = (@mb_image_size * 1024 * 1024 / 512)
            case @part_type
            when EC2::Platform::PartitionType::MBR
              # Add a partition table and leave space to install a boot-loader.
              # The boot partition fills up the disk. Note that '-1s' indicates
              # the end of disk (and not 1 sector in from the end.
              head = 63
              cmd << ['unit s']
              cmd << ['mklabel msdos']
              cmd << ['mkpart primary %s -1s' % head]
              cmd << ['set 1 boot on print quit']
              cmd = "parted --script %s -- '%s'" % [img, cmd.join(' ')]
              execute(cmd)
              self.settle
            when EC2::Platform::PartitionType::GPT
              # Add a 1M (2048 sector) BIOS Boot Partition (BPP) to hold the
              # GRUB bootloader and then fill the rest of the disk with the
              # boot partition.
              #
              # * GRUB2 is BBP-aware and will automatically use this partition for
              #   stage2.
              #
              # * Legacy GRUB is not smart enough to use the BBP for stage 1.5.
              #   We deal with that during GRUB setup in #finalize_image.
              #
              # * Legacy GRUB knows enough about GPT partitions to reference
              #   them by number (avoiding the need for the hybrid MBR hack), so
              #   we set this partition to the maximum partition available to
              #   avoid incrementing the root partition number.
              last = evaluate('sgdisk --print %s |grep "^Partition table holds up to"|cut -d" " -f6 ||:' % img).strip
              last = 4 if last.empty? # fallback to 4.
              execute('sgdisk --new %s:1M:+1M --change-name %s:"BIOS Boot Partition" --typecode %s:ef02 %s' % [last,last,last, img])
              self.settle
              execute('sgdisk --largest-new=1 --change-name 1:"Linux" --typecode 1:8300 %s' % img)
              self.settle
              execute('sgdisk --print  %s' % img)
              self.settle
            else
              raise NotImplementedError, "Partition table type %s not supported" % @part_type
            end
            self.settle

            # The series of activities below are to ensure we can workaround
            # the vagaries of various versions of GRUB. After we have created
            # partition table above, we fake an hda-named device by leveraging
            # device mapper to create a linear device named "/dev/mapper/hda".
            # We then set @target to its first partition. This makes @target
            # easy to manipulate pretty much in the same way that we handle
            # non-partitioned images. All cleanup happens during #cleanup.
            @diskloop = evaluate('losetup -f').strip
            execute('losetup %s %s' % [@diskloop, @image_filename])
            @diskdev = '/dev/mapper/hda'
            @partdev = '%s1' % [ @diskdev]
            diskname = File.basename(@diskdev)
            loopname = File.basename(@diskloop)
            majmin = IO.read('/sys/block/%s/dev' % loopname).strip
            execute( 'echo 0 %s linear %s 0|dmsetup create %s' % [size, majmin, diskname] )
            execute( 'kpartx -a %s' % [ @diskdev ] )
            self.settle
            @target = @partdev
            @fstype = type
          else
            # Not creating a disk image.
            @target = @image_filename
          end

          tune = nil
          mkfs = [ '/sbin/mkfs.' + type ]
          case type
          when 'btrfs'
            mkfs << [ '-L', label] unless label.to_s.empty?
            mkfs << [ @target ]
          when 'xfs'
            mkfs << [ '-L', label] unless label.to_s.empty?
            mkfs << [ @target ]
            tune =  [ '/usr/sbin/xfs_admin' ]
            tune << [ '-U', uuid ] unless uuid.to_s.empty?
            tune << [ @target ]
          else
            # Type unknown or ext2 or ext3 or ext4
            # New e2fsprogs changed the default inode size to 256 which is
            # incompatible with some older kernels, and older versions of
            # grub. The options below change the behavior back to the
            # expected RHEL5 behavior if we are bundling disk images. This
            # is not ideal, but oh well.
            if ['ext2', 'ext3', 'ext4'].include?(type)
              # Clear all the defaults specified in /etc/mke2fs.conf
              features = ['none']

              # Get Filesytem Features as reported by dumpe2fs
              output = evaluate("dumpe2fs -h %s | grep 'Filesystem features'" % root)
              parts = output.split(':')[1].lstrip.split(' ')
              features.concat(parts)
              features.delete('needs_recovery')
              if features.include?('64bit')
                puts "WARNING: 64bit filesystem flag detected on root device (#{root}), resulting image may not boot"
              end

              if self.is_disk_image?
                mkfs = [ '/sbin/mke2fs -t %s -v -m 1' % type ]
                mkfs << ['-O', features.join(',')]
                if ['ext2', 'ext3',].include?(type)
                  mkfs << [ '-I 128 -i 8192' ]
                end
              else
                mkfs << ['-F']
                mkfs << ['-O', features.join(',')]
              end
            else
              # Unknown case
              mkfs << ['-F']
            end
            mkfs << [ '-L', label] unless label.to_s.empty?
            mkfs << [ @target ]
            tune =  [ '/sbin/tune2fs -i 0' ]
            tune << [ '-U', uuid ] unless uuid.to_s.empty?
            tune << [ @target ]
          end
          execute( mkfs.join( ' ' ) )
          execute( tune.join( ' ' ) ) if tune
        end

        def customize_image
          return unless @script and File.executable?(@script)
          puts('Customizing cloned volume mounted at %s with script %s' % [IMG_MNT, @script])
          output = evaluate('%s "%s"' % [@script, IMG_MNT])
          STDERR.puts output if @debug
        end

        def finalize_image
          return unless self.is_disk_image?
          begin
            # GRUB needs to reference the device.map file to know about our
            # disk layout. So let's write out a simple one.
            devmapfile = '%s/boot/grub/device.map' % IMG_MNT
            FileUtils.mkdir_p(File.dirname(devmapfile))
            File.open(devmapfile, 'w') do|io|
              io << "(hd0) %s\n" % @diskdev
            end

            # Provide a suitable /etc/mtab if it doesn't already exist
            fixmtab = false
            mtabfile = '%s/etc/mtab' % IMG_MNT
            execute('ln -s /proc/mounts %s' % mtabfile) unless File.exists?(mtabfile)

            puts('Installing GRUB on root device with %s boot scheme' % @part_type)
            # Newish versions of old GRUB expect the first partition
            # of /dev/mapper/hda to be /dev/mapper/hda1. Lie to GRUB
            # by adding a symlink to /dev/mapper/hda1.
            hdap1 = '%s/dev/mapper/hdap1' % IMG_MNT
            execute('ln -s ./hda1 %s' % hdap1) unless File.exists?(hdap1)

            # Try to find the grub stages. There isn't a good way to know where
            # exactly these will be on a given system, so this glob is a little
            # excessive, but it should usually result in finding the path to
            # the grub stages. It's also possible that it will exist outside
            # /usr, but unlikely enough to not merit another glob there.
            stage1 = Dir.glob("#{IMG_MNT}/usr/**/grub*/**/stage1")
            if stage1.empty?
              raise RuntimeError, "Couldn't find grub stages under #{IMG_MNT}"
            end
            stagesdir = File.dirname(stage1[0])

            # Copy the stages into the grub dir on /boot
            # Normally you'd let grub-install do this, but it can be very picky
            # and doing the setup manually seems to be more reliable.
            Dir.glob(["#{stagesdir}/stage{1,2}", "#{stagesdir}/*_stage1_5"]).each do |stage|
              dest = "#{IMG_MNT}/boot/grub/%s" % File.basename(stage)
              FileUtils.rm_f(dest)
              FileUtils.cp(stage, dest)
            end

            # We're now ready to install GRUB.
            case @part_type
            when EC2::Platform::PartitionType::MBR
              cmd = 'device (hd0) %s\nroot (hd0,0)\nsetup (hd0)' % @diskdev
              execute('echo -e "%s" | grub --device-map=/dev/null --batch' % cmd, IMG_MNT)
            when EC2::Platform::PartitionType::GPT
              case @fstype
              when /ext[234]/
                file = '/boot/grub/e2fs_stage1_5'
              when 'xfs'
                file = '/boot/grub/xfs_stage1_5'
              else
                raise RuntimeError, 'File system type %s unsupported' % [@fstype]
              end

              file = File.join(IMG_MNT, file)
              size = (File.size(file) + 511)/512
              head = 2048 # start of the BIOS Boot Partition
              cmd = 'dd if=%s of=%s seek=%s conv=fsync status=noxfer' % [file, @diskdev, head]
              execute(cmd)
              cmd =  'device (hd0) %s\n' % @diskdev
              cmd += 'root (hd0,0)\n'
              cmd += 'install /boot/grub/stage1 (hd0) (hd0)%s+%s ' % [head, size]
              cmd += 'p (hd0,0)/boot/grub/stage2 /boot/grub/grub.conf'
              execute('echo -e "%s" | grub --device-map=/dev/null --batch' % cmd, IMG_MNT)
            else
              raise RuntimeError, 'Unknown partition table type %s' % @part_type
            end

            # Check for reasonable kernel parameters
            if @conf # user-supplied
              src = Pathname(@conf).realpath.to_s
              puts "Using user supplied grub config #{src}"
              check_kernel_parameters(@conf)

              dst_dir = File.join(IMG_MNT, '/boot/grub')
              FileUtils.mkdir_p(dst_dir) unless File.exists?(dst_dir)

              menulst = File.join(dst_dir, '/menu.lst')
              # Copy the user supplied grub-config over any default ones
              FileUtils.copy_entry(src, menulst, remove_destination=true)

              grubconf = File.join(dst_dir, '/grub.conf')
              File.delete(grubconf) unless not File.exists?(grubconf)
              File.symlink('menu.lst', grubconf)
              @conf = menulst
            else
              default_confs = [File.join(IMG_MNT, '/boot/grub/grub.conf'),
                               File.join(IMG_MNT, '/boot/grub/menu.lst')]
              @conf = default_confs.find { |file| File.file?(file) }
              if @conf
                puts "Using default grub config"
                check_kernel_parameters(@conf)
              else
                STDERR.puts('WARNING: No GRUB config found. The resulting image may not boot')
              end
            end

            # Finally, tweak grub.conf to ensure we can boot.
            adjustconf(@conf)
          ensure
            FileUtils.rm_f(hdap1)
            FileUtils.rm_f(mtabfile) if fixmtab
          end
        end

        def adjustconf(conf)
          if conf
            puts("Adjusting #{File.expand_path(conf)}")
            conf = File.expand_path(conf)
            data = IO.read(conf).split(/\n/).map do |line|
              line.gsub(/root\s+\(hd0\)/, 'root (hd0,0)')
            end
            File.open(conf, 'w'){|io| io << data.join("\n")}
            puts(evaluate('cat %s' % conf))
          end
        end

        def fsinfo( fs )
          result = {}
          if fs and File.exists?( fs )
            ['LABEL', 'UUID', 'TYPE' ].each do |tag|
              begin
                property = tag.downcase.to_sym
                value = evaluate( '/sbin/blkid -o value -s %s %s' % [tag, fs] ).strip
                result[property] = value if value and not value.empty?
              rescue FatalError => e
                if @debug
                  STDERR.puts e.message
                  STDERR.puts "Could not replicate file system #{property}. Proceeding..."
                end
              end
            end
          end
          result
        end

        #---------------------------------------------------------------------#

        # Mount the image file as a loopback device. The mount point is created
        # if necessary.
        def mount_image
          Dir.mkdir(IMG_MNT) if not FileUtil::exists?(IMG_MNT)
          raise FatalError.new("image already mounted") if mounted?(IMG_MNT)
          dirs = ['mnt', 'proc', 'sys', 'dev']
          if self.is_disk_image?
            execute( 'mount -t %s %s %s' % [@fstype, @target, IMG_MNT] )
            dirs.each{|dir| FileUtils.mkdir_p( '%s/%s' % [IMG_MNT, dir])}
            make_special_devices
            execute( 'mount -o bind /proc %s/proc' % IMG_MNT )
            execute( 'mount -o bind /sys %s/sys' % IMG_MNT )
            execute( 'mount -o bind /dev %s/dev' % IMG_MNT )
          else
            execute( 'mount -o loop ' + @target + ' ' + IMG_MNT )
            dirs.each{ |dir| FileUtils.mkdir_p( '%s/%s' % [IMG_MNT, dir]) }
            make_special_devices
          end
        end

        #---------------------------------------------------------------------#
        # Copy the contents of the specified source directory to the specified
        # target directory, recursing sub-directories. Directories within the
        # exclusion list are not copied. Symlinks are retained but not traversed.
        #
        # src: The source directory name.
        # dst: The destination directory name.
        # options: A set of options to try.
        def copy_rec( src, dst, options={:xattributes => true} )
          begin
            rsync = EC2::Platform::Linux::Rsync::Command.new
            rsync.archive.times.recursive.sparse.links.quietly.include(@includes).exclude(@exclude)
            if @filter
              rsync.exclude(EC2::Platform::Linux::Constants::Security::FILE_FILTER)
            end
            rsync.xattributes if options[ :xattributes ]
            rsync.src(File::join( src, '*' )).dst(dst)
            execute(rsync.expand)
            return true
          rescue Exception => e
            rc = $?.exitstatus
            return true if rc == 0
            if rc == 23 and SysChecks::rsync_usable?
              STDERR.puts [
               'NOTE: rsync seemed successful but exited with error code 23. This probably means',
               'that your version of rsync was built against a kernel with HAVE_LUTIMES defined,',
               'although the current kernel was not built with this option enabled. The bundling',
               'process will thus ignore the error and continue bundling.  If bundling completes',
               'successfully, your image should be perfectly usable. We, however, recommend that',
               'you install a version of rsync that handles this situation more elegantly.'
              ].join("\n")
              return true
            elsif rc == 1 and options[ :xattributes ]
              STDERR.puts [
               'NOTE: rsync with preservation of extended file attributes failed. Retrying rsync',
               'without attempting to preserve extended file attributes...'
              ].join("\n")
              o = options.clone
              o[ :xattributes ] = false
              return copy_rec( src, dst, o)
            end
            raise e
          end
        end

        #----------------------------------------------------------------------------#

        def make_special_devices
          execute("mknod %s/dev/null    c 1 3" % IMG_MNT)
          execute("mknod %s/dev/zero    c 1 5" % IMG_MNT)
          execute("mknod %s/dev/tty     c 5 0" % IMG_MNT)
          execute("mknod %s/dev/console c 5 1" % IMG_MNT)
          execute("ln -s null %s/dev/X0R" % IMG_MNT)
        end

        #----------------------------------------------------------------------------#

        def make_fstab
          case @fstab
          when :legacy
            return LEGACY_FSTAB
          when :default
            return DEFAULT_FSTAB
          else
            return @fstab
          end
        end

        #----------------------------------------------------------------------------#

        def update_fstab
          if @fstab
            etc = File::join( IMG_MNT, 'etc')
            fstab = File::join( etc, 'fstab' )

            FileUtils::mkdir_p( etc ) unless File::exist?( etc)
            execute( "cp #{fstab} #{fstab}.old" ) if File.exist?( fstab )
            fstab_content = make_fstab
            File.open( fstab, 'w' ) { |f| f.write( fstab_content ) }
            puts "/etc/fstab:"
            fstab_content.each_line do |s|
              puts "\t #{s}"
            end
          end
        end

        #----------------------------------------------------------------------------#

        # Execute the command line _cmd_.
        def execute( cmd, chroot = nil, nullenv = true )
          command = cmd
          if chroot and not File.directory?(chroot)
            raise FatalError.new('Cannot chroot into %s. Not a directory' % [chroot])
          end
          if chroot
            env = nullenv ? 'env -i' : ''
            command = 'setarch %s chroot %s %s %s' % [@arch, chroot, env, cmd]
          else
            command = cmd
          end

          if @debug
            if chroot
              STDERR.puts( 'Executing(chroot=%s): %s' % [chroot, command ] )
            else
              STDERR.puts( 'Executing: %s' % command )
            end
          else
            command += ' >/dev/null 2>&1'
          end
          raise FatalError.new("Failed to execute: '#{cmd}'") unless system( command )
        end

        #---------------------------------------------------------------------------#
        # Execute command line passed in and return STDOUT output if successful.
        def evaluate( cmd, success = 0, verbattim = nil )
          verbattim = @debug if verbattim.nil?
          STDERR.puts( "Evaluating: %s" % cmd ) if verbattim
          pid, stdin, stdout, stderr = Open4::popen4( cmd )
          pid, status = Process::waitpid2 pid
          unless status.exitstatus == success
            raise FatalError.new( "Failed to evaluate '#{cmd }'. Reason: #{stderr.read}." )
          end
          stdout.read
        end
      end
    end
  end
end
