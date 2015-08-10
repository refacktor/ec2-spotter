# Copyright 2008-2014 Amazon.com, Inc. or its affiliates.  All Rights
# Reserved.  Licensed under the Amazon Software License (the
# "License").  You may not use this file except in compliance with the
# License. A copy of the License is located at
# http://aws.amazon.com/asl or in the "license" file accompanying this
# file.  This file is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See
# the License for the specific language governing permissions and
# limitations under the License.

require 'stringio'

module Format

  #----------------------------------------------------------------------------#

  ##
  # Convert the binary data ((|data|)) to an ASCII string of hexadecimal digits
  # that represents it.
  #
  # E.g. if ((|data|)) is the string of bytes 0x1, 0x1A, 0xFF, it is converted
  # to the string "011AFF".
  #
  def Format.bin2hex(data)
    hex = StringIO.new
    data.unpack('H*').each {|digit| hex.write(digit)}
    hex.string
  end

  #----------------------------------------------------------------------------#
  
  ##
  # Breaks ((|data|)) into blocks of size ((|blocksize|)). The last block maybe
  # less than ((|blocksize||).
  #
  def Format.block(data, blocksize)
    blocks = Array.new
    read = 0
    while read < data.size
      left = data.size - read
      blocks << data[read, (left < blocksize) ? left : blocksize]
      read += (left < blocksize ? left : blocksize)
    end
    
    blocks
  end

  #----------------------------------------------------------------------------#
  
  ##
  # Convert ASCII string of hexadecimal digits ((|hex|)) into the binary data it
  # represents. If there are an odd number of hexedecimal digits in ((|hex|)) it
  # is left padded with a leading '0' character.
  #
  # E.g. if ((|hex|)) is "11AFF", it is converted to the string of bytes 0x1,
  # 0x1A, 0xFF.
  #
  def Format.hex2bin(hex)
    hex = '0' + hex unless (hex.size % 2) == 0
    data = StringIO.new
    [[hex].pack('H*')].each {|digit| data.write(digit)}
    data.string
  end

  #----------------------------------------------------------------------------#

  ##
  # Return a single character string containing ((|int|)) converted to a single
  # byte unsigned integer. The operand must be less than 256.
  #
  def Format.int2byte int
    raise ArgumentError.new('argument greater than 255') unless int < 256
    int.chr
  end

  #----------------------------------------------------------------------------#

  # Convert integer _i_ to an unsigned 16 bit int packed into two bytes in big
  # endian order.
  def Format::int2int16( i )
    raise ArgumentError.new( 'argument greater than 65535' ) unless i < 65536
    hi_byte = ( i >> 8 ).chr
    lo_byte = ( i & 0xFF).chr
    return [ hi_byte, lo_byte ]
  end

  #----------------------------------------------------------------------------#
  
  ##
  # Pad data string ((|data|)) according to the PKCS #7 padding scheme.
  #
  def Format.pad_pkcs7(data, blocksize)
    raise ArgumentError.new("invalid data: #{data.to_s}") unless data and data.kind_of? String
    raise ArgumentError.new("illegal blocksize: #{blocksize}") unless blocksize > 0x0 and blocksize < 0xFF
    
    # Determine the number of padding characters required. If the data size is
    # divisible by the blocksize, a block of padding is required.
    nr_padchars = blocksize - (data.size % blocksize)
    nr_padchars = blocksize unless nr_padchars != 0
    
    # Create padding, where the padding byte is the number of padding bytes.
    padchar = nr_padchars.chr
    padding = padchar * nr_padchars
    
    data + padding
  end
  
  #----------------------------------------------------------------------------#
  
  ##
  # Pad ((|data|)) according to the PKCS #7 padding scheme.
  #
  def Format.unpad_pkcs7(data, blocksize)
    raise ArgumentError.new("illegal blocksize: #{blocksize}") unless blocksize > 0x0 and blocksize < 0xFF
    raise ArgumentError.new("invalid data: #{data.to_s}") unless data and data.kind_of? String 
    raise ArgumentError.new("invalid data size: #{data.size}") unless data.size > 0 and (data.size % blocksize) == 0
    
    nr_padchars = data[data.size - 1]
    raise ArgumentError.new("data padding character invalid: #{nr_padchars}") unless (nr_padchars > 0 and nr_padchars <= blocksize)
    
    data[0, data.size - nr_padchars]
  end
  
  
  
  
end
