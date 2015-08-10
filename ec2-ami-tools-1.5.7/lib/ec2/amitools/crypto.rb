# Copyright 2008-2014 Amazon.com, Inc. or its affiliates.  All Rights
# Reserved.  Licensed under the Amazon Software License (the
# "License").  You may not use this file except in compliance with the
# License. A copy of the License is located at
# http://aws.amazon.com/asl or in the "license" file accompanying this
# file.  This file is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See
# the License for the specific language governing permissions and
# limitations under the License.

require 'ec2/amitools/format'
require 'digest/sha1'
require 'openssl'
require 'stringio'

###
# Cryptographic utilities module.
#
module Crypto
  BUFFER_SIZE = 1024 * 1024
  ASYM_ALG = 'RSA'
  SYM_ALG = 'AES-128-CBC'
  DIGEST_ALG = 'SHA1'
  PADDING = OpenSSL::PKey::RSA::PKCS1_PADDING
  VERSION1 = 1
  VERSION2 = 2
  SHA1_FINGERPRINT_REGEX = /([a-f0-9]{2}(:[a-f0-9]{2}){15})/i

  #----------------------------------------------------------------------------#

  ##
  # Decrypt the specified cipher text according to the AMI Manifest Encryption
  # Scheme Version 1 or 2.
  #
  # ((|cipher_text|)) The cipher text to decrypt.
  # ((|keyio_or_keyfilename|)) The key data IO stream or the name of the private
  # key file.
  #
  def Crypto.decryptasym(cipher_text, keyfilename)
    raise ArgumentError.new('cipher_text') unless cipher_text
    raise ArgumentError.new('keyfilename') unless keyfilename and FileTest.exists? keyfilename

    # Load key.
    privkey = File.open(keyfilename, 'r') { |f| OpenSSL::PKey::RSA.new(f) }

    # Get version.
    version = cipher_text[0]
    if version == VERSION2
      return Crypto.decryptasym_v2( cipher_text, keyfilename )
    end
    raise ArgumentError.new("invalid encryption scheme versionb: #{version}") unless version == 1

    # Decrypt and extract encrypted symmetric key and initialization vector.
    symkey_cryptogram_len = cipher_text.slice(1, 2).unpack('C')[0]
    symkey_cryptogram = privkey.private_decrypt(
      cipher_text.slice(2, symkey_cryptogram_len),
      PADDING)
    symkey = symkey_cryptogram.slice(0, 16)
    iv = symkey_cryptogram.slice(16, 16)

    # Decrypt data with the symmetric key.
    cryptogram = cipher_text.slice(2 + symkey_cryptogram_len..cipher_text.size)
    decryptsym(cryptogram, symkey, iv)
  end

  #----------------------------------------------------------------------------#

  ##
  # Decrypt the specified cipher text according to the AMI Manifest Encryption
  # Scheme Version 2.
  #
  # ((|cipher_text|)) The cipher text to decrypt.
  # ((|keyio_or_keyfilename|)) The key data IO stream or the name of the private
  # key file.
  #
  def Crypto.decryptasym_v2(cipher_text, keyfilename)
    raise ArgumentError.new('cipher_text') unless cipher_text
    raise ArgumentError.new('keyfilename') unless keyfilename and FileTest.exists? keyfilename

    # Load key.
    privkey = File.open(keyfilename, 'r') { |f| OpenSSL::PKey::RSA.new(f) }

    # Get version.
    version = cipher_text[0]
    raise ArgumentError.new("invalid encryption scheme versionb: #{version}") unless version == VERSION2

    # Decrypt and extract encrypted symmetric key and initialization vector.
    hi_byte, lo_byte = cipher_text.slice(1, 3).unpack('CC')
    symkey_cryptogram_len = ( hi_byte << 8 ) | lo_byte
    symkey_cryptogram = privkey.private_decrypt(
      cipher_text.slice(3, symkey_cryptogram_len),
      PADDING)
    
    symkey = symkey_cryptogram.slice(0, 16)
    iv = symkey_cryptogram.slice(16, 16)

    # Decrypt data with the symmetric key.
    cryptogram = cipher_text.slice( ( 3 + symkey_cryptogram_len )..cipher_text.size)
    decryptsym(cryptogram, symkey, iv)
  end

  #----------------------------------------------------------------------------#

  ##
  # Asymmetrically encrypt the specified data using the AMI Manifest Encryption
  # Scheme Version 2.
  #
  # The data is encrypted with an ephemeral symmetric key and initialization
  # vector. The symmetric key and initialization vector are encrypted with the
  # specified public key and preprended to the data.
  #
  # ((|data|)) The data to encrypt.
  # ((|pubkey|)) The public key.
  #
  def Crypto.encryptasym(data, pubkey)
    raise ArgumentError.new('data') unless data
    raise ArgumentError.new('pubkey') unless pubkey

    symkey = gensymkey
    iv = geniv
    symkey_cryptogram = pubkey.public_encrypt( symkey + iv, PADDING )

    data_cryptogram = encryptsym(data, symkey, iv)

    hi_byte, lo_byte = Format.int2int16(symkey_cryptogram.size)

    Format::int2byte(VERSION2) + hi_byte + lo_byte + symkey_cryptogram + data_cryptogram
  end

  #----------------------------------------------------------------------------#

  ##
  # Verify the authenticity of the data from the IO stream or string ((|data|))
  # using the signature ((|sig|)) and the public key ((|pubkey|)).
  #
  # Return true iff the signature is valid.
  #
  def Crypto.authenticate(data, sig, pubkey)
    raise ArgumentError.new("Invalid parameter data") if data.nil?
    raise ArgumentError.new("Invalid parameter sig") if sig.nil? or sig.length==0
    raise ArgumentError.new("Invalid parameter pubkey") if pubkey.nil?

    # Create IO stream if necessary.
    io = (data.instance_of?(StringIO) ? data : StringIO.new(data))

    sha = OpenSSL::Digest::SHA1.new
    res = false
    while not (io.eof?)
      res = pubkey.verify(sha, sig, io.read(BUFFER_SIZE))
    end
    res
  end

  #----------------------------------------------------------------------------#

  ##
  # Decrypt the specified cipher text file to create the specified plain text
  # file.
  #
  # The symmetric cipher is AES in CBC mode. 128 bit keys are used. If the plain
  # text file already exists it will be overwritten.
  #
  # ((|src|)) The name of the cipher text file to decrypt.
  # ((|dst|)) The name of the plain text file to create.
  # ((|key|)) The 128 bit (16 byte) symmetric key.
  # ((|iv|)) The 128 bit (16 byte) initialization vector.
  #
  def Crypto.decryptfile(src, dst, key, iv)
    raise ArgumentError.new("invalid file name: #{src}") unless FileTest.exists?(src)
    raise ArgumentError.new("invalid key") unless key and key.size == 16
    raise ArgumentError.new("invalid iv") unless iv and iv.size == 16
    pio = IO.popen( "openssl enc -d -aes-128-cbc -in #{src} -out #{dst} -K #{Format::bin2hex(key)} -iv #{Format::bin2hex(iv)} 2>&1" )
    result = pio.read
    pio.close
    raise "error decrypting file #{src}: #{result}" if result.strip != ''
  end

  #----------------------------------------------------------------------------#

  ##
  # Decrypt _ciphertext_ using _key_ and _iv_ using AES-128-CBC.
  #
  def Crypto.decryptsym(plaintext, key, iv)
    raise ArgumentError.new("plaintext must be a String") unless plaintext.is_a? String
    raise ArgumentError.new("invalid key") unless key.is_a? String and key.size == 16
    raise ArgumentError.new("invalid iv") unless iv.is_a? String and iv.size == 16

    cipher = OpenSSL::Cipher::Cipher.new( 'AES-128-CBC' )
    cipher.decrypt( key, iv )
    # NOTE: If the key and iv aren't set this doesn't work correctly.
    cipher.key = key
    cipher.iv = iv
    plaintext = cipher.update( plaintext )
    plaintext + cipher.final
  end

  #----------------------------------------------------------------------------#

  ##
  # Generate and return a message digest for the data from the IO stream
  # ((|io|)), using the algorithm alg
  #
  def Crypto.digest(io, alg = OpenSSL::Digest::SHA1.new)
    raise ArgumentError.new('io') unless io.kind_of?(IO) or io.kind_of?(StringIO)
    while not io.eof?
      alg.update(io.read(BUFFER_SIZE))
    end
    alg.digest
  end

  #----------------------------------------------------------------------------#

  # Return the HMAC SHA1 of _data_ using _key_.
  def Crypto.hmac_sha1( key, data )
    raise ParameterError.new( "key must be a String" ) unless key.is_a? String
    raise ParameterError.new( "data must be a String" ) unless data.is_a? String

    md = OpenSSL::Digest::SHA1.new
    hmac = OpenSSL::HMAC.new( key, md)
    hmac.update( data )
    return hmac.digest
  end

  #----------------------------------------------------------------------------#

  ##
  # Decrypt the specified cipher text file to create the specified plain text
  # file.
  #
  # The symmetric cipher is AES in CBC mode. 128 bit keys are used. If the plain
  # text file already exists it will be overwritten.
  #
  # ((|key|)) The 128 bit (16 byte) symmetric key.
  # ((|src|)) The name of the cipher text file to encrypt.
  # ((|dst|)) The name of the plain text file to create.
  # ((|iv|)) The 128 bit (16 byte) initialization vector.
  #
  def Crypto.encryptfile(src, dst, key, iv)
    raise ArgumentError.new("invalid file name: #{src}") unless FileTest.exists?(src)
    raise ArgumentError.new("invalid key") unless key and key.size == 16
    raise ArgumentError.new("invalid iv") unless iv and iv.size == 16
    cmd = "openssl enc -e -aes-128-cbc -in #{src} -out #{dst} -K #{Format::bin2hex(key)} -iv #{Format::bin2hex(iv)}"
    result = Kernel::system(cmd)
    raise "error encrypting file #{src}" unless result
  end

  #----------------------------------------------------------------------------#

  ##
  # Encrypt _plaintext_ with _key_ and _iv_ using AES-128-CBC.
  #
  def Crypto.encryptsym(plaintext, key, iv)
    raise ArgumentError.new("plaintext must be a String") unless plaintext.kind_of? String
    raise ArgumentError.new("invalid key") unless ( key.is_a? String and key.size == 16 )
    raise ArgumentError.new("invalid iv") unless ( iv.is_a? String and iv.size == 16 )

    cipher = OpenSSL::Cipher::Cipher.new( 'AES-128-CBC' )
    cipher.encrypt( key, iv )
    # NOTE: If the key and iv aren't set this doesn't work correctly.
    cipher.key = key
    cipher.iv = iv
    ciphertext = cipher.update( plaintext )
    ciphertext + cipher.final
  end

  #----------------------------------------------------------------------------#

  ##
  # Generate an initialization vector suitable use with symmetric cipher.
  #
  def Crypto.geniv
    OpenSSL::Cipher::Cipher.new(SYM_ALG).random_iv
  end

  #----------------------------------------------------------------------------#

  ##
  # Generate a key suitable for use with a symmetric cipher.
  #
  def Crypto.gensymkey
    OpenSSL::Cipher::Cipher.new(SYM_ALG).random_key
  end

  #----------------------------------------------------------------------------#

  ##
  # Return the public key from the X509 certificate file ((|filename|)).
  #
  def Crypto.certfile2pubkey(filename)
    begin
      File.open(filename) do |f|
        return cert2pubkey(f)
      end
    rescue Exception => e
      raise "error reading certificate file #{filename}: #{e.message}"
    end
  end

  #----------------------------------------------------------------------------#

  def Crypto.cert2pubkey(data)
    begin
      return OpenSSL::X509::Certificate.new(data).public_key
    rescue Exception => e
      raise "error reading certificate: #{e.message}"
    end
  end

  #----------------------------------------------------------------------------#

  ##
  # Sign the data from IO stream or string ((|data|)) using the key in
  # ((|keyfilename|)).
  #
  # Return the signature.
  #
  def Crypto.sign(data, keyfilename)
    raise ArgumentError.new('data') unless data
    raise ArgumentError.new("invalid file name: #{keyfilename}") unless FileTest.exists?(keyfilename)

    # Create an IO stream from the data if necessary.
    io = (data.instance_of?(StringIO) ? data : StringIO.new(data))

    sha = OpenSSL::Digest::SHA1.new
    pk  = loadprivkey( keyfilename )
    return pk.sign(sha, io.read )
  end

  #------------------------------------------------------------------------------#

  ##
  # Generate the SHA1 fingerprint for a PEM-encoded certificate (NOT private key)
  # Returns the fingerprint in aa:bb:... form
  # Raises ArgumentError if the fingerprint cannot be obtained
  #
  def Crypto.cert_sha1_fingerprint(cert_filename)
    raise ArgumentError.new('cert_filename is nil')  if cert_filename.nil?
    raise ArgumentError.new("invalid cert file name: #{cert_filename}") unless FileTest.exists?(cert_filename)
    fingerprint = nil

    IO.popen("openssl x509 -in #{cert_filename} -noout -sha1 -fingerprint") do |io|
      out = io.read
      md = SHA1_FINGERPRINT_REGEX.match(out)
      if md
        fingerprint = md[1]
      end
    end

    raise ArgumentError.new("could not generate fingerprint for #{cert_filename}")  if fingerprint.nil?

    return fingerprint
  end

  #------------------------------------------------------------------------------#

  def Crypto.loadprivkey filename
    begin
      OpenSSL::PKey::RSA.new( File.open( filename,'r' ) )
    rescue Exception => e
      raise "error reading private key from file #{filename}: #{e.message}"
    end
  end

  #----------------------------------------------------------------------------#

  ##
  # XOR the byte string ((|a|)) with the byte string ((|b|)). The operans must
  # be of the same length.
  #
  def Crypto.xor(a, b)
    raise ArgumentError.new('data lengths differ') unless a.size == b.size
    xored = String.new
    a.size.times do |i|
      xored << (a[i] ^ b[i])
    end

    xored
  end
end
