# Copyright 2008-2014 Amazon.com, Inc. or its affiliates.  All Rights
# Reserved.  Licensed under the Amazon Software License (the
# "License").  You may not use this file except in compliance with the
# License. A copy of the License is located at
# http://aws.amazon.com/asl or in the "license" file accompanying this
# file.  This file is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See
# the License for the specific language governing permissions and
# limitations under the License.

require 'ec2/amitools/crypto'
require 'ec2/amitools/format'
require 'ec2/amitools/xmlutil'
require 'pathname'
require 'rexml/document'

# Manifest Version 3.
# Not backwards compatible
class ManifestV3
  VERSION_STRING = '3'
  VERSION = VERSION_STRING.to_i
  
  # AMI part information container.
  class PartInformation
    attr_reader :filename # Part's file basename.
    attr_reader :digest   # Part's digest hex encoded.
    
    # Initialize with part's _filename_ and _digest_ as byte string.
    def initialize(  filename, digest  )
      @filename , @digest = filename, digest
    end
  end

  def initialize( xml = nil )
    if xml == nil
      @doc = REXML::Document.new
    else
      # Convert to string if necessary.
      xml = ( xml.kind_of?( IO ) ? xml.read : xml )
      @doc = REXML::Document.new( xml )
    end
  end

  # for debugging only
  def doc
    @doc
  end
  
  # Initialize the manifest with AMI information.
  # Return +true+ if the initialization was succesful.
  # Raise an exception on error.
  def init(
    name,
    user,                   # The user's account number.
    parts,                  # A list of parts filenames and digest pairs.
    size,                   # The size of the AMI in bytes.
    bundled_size,           # The size of the bunled AMI in bytes.
    user_encrypted_key,     # Hex encoded.
    ec2_encrypted_key,      # Hex encoded.
    cipher_algorithm,       # The cipher algorithm used to encrypted the AMI.
    user_encrypted_iv,      # Hex encoded.
    ec2_encrypted_iv,       # Hex encoded.
    digest,                 # Hex encoded.
    digest_algorithm,       # The digest algorithm.
    privkey_filename,       # The user's private key filename.
    bundler_name = nil,
    bundler_version = nil,
    bundler_release = nil )
    # Check non-String parameter types.
    raise ArgumentError.new( "parts parameter type invalid" ) unless parts.is_a? Array
        
    # XML document.
    @doc = REXML::Document.new
    @doc << REXML::XMLDecl.new

    # manifest - the root element.
    manifest = REXML::Element.new( 'manifest' )

    @doc.add_element( manifest )
    
    # version - indicate the manifest version.
    version = REXML::Element.new( 'version' )
    version.text = VERSION_STRING
    manifest.add_element( version )
    
    # bundler information
    if bundler_name or bundler_version or bundler_release
      bundler_element = REXML::Element.new( 'bundler' )
      manifest.add_element( bundler_element )
      
      [['name', bundler_name ], 
       ['version', bundler_version ],
       ['release', bundler_release ]].each do |element_name, text|
        if element_name
          element = REXML::Element.new( element_name )
          element.text = text
          bundler_element.add_element( element )
        end
      end 
    end
    
    # image - the image element.
    image = REXML::Element.new( 'image' )
    name_element = REXML::Element.new( 'name' )
    name_element.text = name
    image.add_element( name_element )
    manifest.add_element( image )
    
    # user - the user's AWS access key ID.
    user_element = REXML::Element.new( 'user' )
    user_element.text = user
    image.add_element( user_element )
    
    # digest - the digest of the AMI.
    digest_element = REXML::Element.new( 'digest' )
    digest_element.add_attribute( 'algorithm', digest_algorithm )
    digest_element.add_text( digest )
    image.add_element( digest_element )
    
    # size - the size of the uncompressed AMI.
    size_element = REXML::Element.new( 'size' )
    size_element.text = size.to_s
    image.add_element( size_element )
    
    # size - the size of the uncompressed AMI.
    bundled_size_element = REXML::Element.new( 'bundled_size' )
    bundled_size_element.text = bundled_size.to_s
    image.add_element( bundled_size_element )
    
    # ec2 encrypted key element.
    ec2_encrypted_key_element = REXML::Element.new( 'ec2_encrypted_key' )
    ec2_encrypted_key_element.add_attribute( 'algorithm', cipher_algorithm )
    ec2_encrypted_key_element.add_text( ec2_encrypted_key )
    image.add_element( ec2_encrypted_key_element )
    
    # user encrypted key element.
    user_encrypted_key_element = REXML::Element.new( 'user_encrypted_key' )
    user_encrypted_key_element.add_attribute( 'algorithm', cipher_algorithm )
    user_encrypted_key_element.add_text( user_encrypted_key )
    image.add_element( user_encrypted_key_element )
    
    # ec2 encrypted iv element.
    ec2_encrypted_iv_element = REXML::Element.new( 'ec2_encrypted_iv' )
    ec2_encrypted_iv_element.add_text( ec2_encrypted_iv )
    image.add_element( ec2_encrypted_iv_element )
    
    # user encrypted iv element.
    user_encrypted_iv_element = REXML::Element.new( 'user_encrypted_iv' )
    user_encrypted_iv_element.add_text( user_encrypted_iv )
    image.add_element( user_encrypted_iv_element )
    
    # parts - list of the image parts.
    parts_element = REXML::Element.new( 'parts' )
    parts_element.add_attributes( {'count' => parts.size.to_s} )
    index=0
    parts.each do |part|
      # Add image part element for each image part.
      part_element = REXML::Element.new( 'part' )
      part_element.add_attribute( 'index', index.to_s )
      filename = REXML::Element.new( 'filename' )
      filename.add_text( part[0] )
      part_element.add_element( filename )
      digest = REXML::Element.new( 'digest' )
      digest.add_attribute( 'algorithm', digest_algorithm )
      digest.add_text( Format::bin2hex( part[1] ) )
      part_element.add_element( digest )
      parts_element.add_element( part_element )
      index+=1
    end
    image.add_element( parts_element )

    # Sign the manifest.
    sign( privkey_filename )
    
    return true
  end
  
  def ManifestV3::version3?( xml )
    doc = REXML::Document.new( xml )
    version = REXML::XPath.first( doc.root, 'version' )
    return (version and version.text and version.text.to_i == VERSION)
  end
  
  # Return the AMI's digest hex encoded.
  def digest()
    return get_element_text( 'image/digest' )
  end
    
  def name()
    return get_element_text( 'image/name' )
  end

  # The ec2 encrypted key hex encoded.
  def ec2_encrypted_key()
    return get_element_text('image/ec2_encrypted_key' )
  end

  # The user encrypted key hex encoded.
  def user_encrypted_key()
    return get_element_text( 'image/user_encrypted_key' )
  end

  # The ec2 encrypted initialization vector hex encoded.
  def ec2_encrypted_iv()
    return get_element_text( 'image/ec2_encrypted_iv' )
  end

  # The user encrypted initialization vector hex encoded.
  def user_encrypted_iv()
    return get_element_text( 'image/user_encrypted_iv' )
  end

  # Get digest algorithm used.
  def digest_algorithm()
    return REXML::XPath.first(@doc.root, 'image/digest/@algorithm').to_s
  end

  # Get cipher algorithm used.
  def cipher_algorithm()
    return REXML::XPath.first(@doc.root, 'image/ec2_encrypted_key/@algorithm').to_s
  end

  # Retrieve a list of AMI bundle parts info. Each element is a hash
  # with the following elements:
  # * 'digest'
  # * 'filename'
  # * 'index'
  def ami_part_info_list
    parts = Array.new
    REXML::XPath.each( @doc.root,'image/parts/part' ) do |part|
      index = part.attribute( 'index' ).to_s.to_i
      filename = REXML::XPath.first( part, 'filename' ).text
      digest = REXML::XPath.first( part, 'digest' ).text
      parts << { 'digest'=>digest, 'filename'=>filename, 'index'=>index }
    end
    return parts
  end

  # A list of PartInformation instances representing the AMI parts.
  def parts()
    parts = []
    REXML::XPath.each( @doc.root,'image/parts/part' ) do |part|
      index = part.attribute( 'index' ).to_s.to_i
      filename = REXML::XPath.first( part, 'filename' ).text
      digest = Format::hex2bin(  REXML::XPath.first( part, 'digest' ).text  )
      parts[index] = PartInformation.new(  filename, digest  )
    end
    return parts
  end

  # Return the size of the AMI.
  def size()
    return get_element_text( 'image/size' ).to_i()
  end
  
  # Return the bundled size of the AMI.
  def bundled_size()
    return get_element_text( 'image/bundled_size' ).to_i
  end
  
  # Return the bundler name.
  def bundler_name()
    return get_element_text('bundler/name')
  end
  
  # Return the bundler version.
  def bundler_version()
    return get_element_text('bundler/version')
  end
  
  # Return the bundler release.
  def bundler_release()
    return get_element_text('bundler/release')
  end
  
  # Sign the manifest. If it is already signed, the signature and certificate
  # will be replaced
  def sign( privkey_filename )
    unless privkey_filename.kind_of? String and File::exist?( privkey_filename )
      raise ArgumentError.new( "privkey_filename parameter invalid" )
    end
    
    # Get the XML for image element and sign it.
    image_xml = XMLUtil.get_xml( @doc.to_s, 'image' )
    sig = Crypto::sign( image_xml, privkey_filename )
         
    # Create the signature and certificate elements.
    signature = REXML::Element.new( 'signature' )
    signature.add_text( Format::bin2hex( sig ) )
    @doc.root.delete_element( 'signature' )
    @doc.root.add_element( signature )
  end

  # Return the signature
  def signature
    get_element_text('signature')
  end

  # Verify the signature
  def authenticate(cert)
    image_xml = XMLUtil.get_xml( @doc.to_s, 'image' )
    pubkey = Crypto::cert2pubkey(cert)
    Crypto::authenticate(image_xml, Format::hex2bin(signature), pubkey)
  end

  # Return the manifest as an XML string.
  def to_s()
    return @doc.to_s
  end

  def user()
    return get_element_text( 'image/user' )
  end

  def version()
    return get_element_text( 'version' ).to_i
  end
  
  private
  
  def get_element_text( xpath )
    element = REXML::XPath.first( @doc.root, xpath )
    unless element
      raise "invalid AMI manifest, #{xpath} element not present"
    end
    unless element.text
      raise "invalid AMI manifest, #{xpath} element empty"
    end
    return element.text
  end
end
