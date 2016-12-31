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
require 'ec2/amitools/xmlbuilder'

# Manifest Version 2007-10-10.
# Not backwards compatible
class ManifestV20071010
  VERSION_STRING = '2007-10-10'
  VERSION = VERSION_STRING.gsub('-','').to_i

  # Expose the version
  def self.version
    VERSION
  end
  
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
  
  def mandatory_argument(arg, args)
    raise "Missing mandatory argument #{arg} for manifest #{VERSION_STRING}" if !args.key?(arg)
    args[arg]
  end

  def optional_argument(arg, args)
    args[arg]
  end

  IMAGE_TYPE_KERNEL = "kernel"

  # Initialize the manifest with AMI information.
  # Return +true+ if the initialization was succesful.
  # Raise an exception on error.
  def init(args)
    name = mandatory_argument(:name, args)
    user = mandatory_argument(:user, args)                               # The user's account number.
    arch = mandatory_argument(:arch, args)                               # Target architecture for AMI.
    image_type = mandatory_argument(:image_type, args)                   # Type of image
    reserved = mandatory_argument(:reserved, args)                       # Reserved for future use; pass nil.
    parts = mandatory_argument(:parts, args)                             # A list of parts filenames and digest pairs.
    size = mandatory_argument(:size, args)                               # The size of the AMI in bytes.
    bundled_size = mandatory_argument(:bundled_size, args)               # The size of the bunled AMI in bytes.
    user_encrypted_key = mandatory_argument(:user_encrypted_key, args)   # Hex encoded.
    ec2_encrypted_key = mandatory_argument(:ec2_encrypted_key, args)     # Hex encoded.
    cipher_algorithm = mandatory_argument(:cipher_algorithm, args)       # The cipher algorithm used to encrypted the AMI.
    user_encrypted_iv = mandatory_argument(:user_encrypted_iv, args)     # Hex encoded.
    ec2_encrypted_iv = mandatory_argument(:ec2_encrypted_iv, args)       # Hex encoded.
    digest = mandatory_argument(:digest, args)                           # Hex encoded.
    digest_algorithm = mandatory_argument(:digest_algorithm, args)       # The digest algorithm.
    privkey_filename = mandatory_argument(:privkey_filename, args)       # The user's private key filename.
    # Optional parameters
    kernel_id = optional_argument(:kernel_id, args)                      # Optional default kernel image id
    ramdisk_id = optional_argument(:ramdisk_id, args)                    # Optional default ramdisk image id
    product_codes = optional_argument(:product_codes, args)              # Optional array of product codes (strings)
    ancestor_ami_ids = optional_argument(:ancestor_ami_ids, args)        # Optional array of ancestor ami ids (strings)
    bdm = optional_argument(:block_device_mapping, args) ||{}            # Optional hash of block device mappings(strings)
    bundler_name = optional_argument(:bundler_name, args)
    bundler_version = optional_argument(:bundler_version, args)
    bundler_release = optional_argument(:bundler_release, args)

    # Conditional parameters
    kernel_name = (image_type == IMAGE_TYPE_KERNEL ? mandatory_argument(:kernel_name, args) : nil) # Name of the kernel in the image
    
    # Check reserved parameters are nil
    raise ArgumentError.new( "reserved parameters not nil" ) unless reserved.nil?

    # Check non-String parameter types.
    raise ArgumentError.new( "parts parameter type invalid" ) unless parts.is_a? Array
        
    # XML document.
    @doc = REXML::Document.new
    @doc << REXML::XMLDecl.new

    # Yeah... the way we used to do this really sucked - manually building up REXML::Element and inserting them into
    # parent nodes. So I've reinvented the wheel and done a baby xpath xml builder kinda thing
    # Makes it much easier (from a code point of view) to build up xml docs. Probably less efficient in machine terms but c'mon
    # if we cared about that we wouldn't be using ruby.
    builder = XMLBuilder.new(@doc)

    # version - indicate the manifest version.
    builder['/manifest/version'] = VERSION_STRING
    
    # bundler information
    builder['/manifest/bundler/name'] = bundler_name
    builder['/manifest/bundler/version'] = bundler_version
    builder['/manifest/bundler/release'] = bundler_release
    
    # machine_configuration - the target hardware description of the AMI.
    builder['/manifest/machine_configuration/architecture'] = arch
    bdm.keys.sort.each_with_index do |key, index|
      builder["/manifest/machine_configuration/block_device_mapping/mapping[#{index}]/virtual"] = key
      builder["/manifest/machine_configuration/block_device_mapping/mapping[#{index}]/device"] = bdm[key]
    end
    builder['/manifest/machine_configuration/kernel_id'] = kernel_id
    builder['/manifest/machine_configuration/ramdisk_id'] = ramdisk_id
    Array(product_codes).each_with_index do |product_code, index|
      builder["/manifest/machine_configuration/product_codes/product_code[#{index}]"] = product_code
    end

    # image - the image element.
    builder['manifest/image/name'] = name
    
    # user - the user's AWS access key ID.
    builder['/manifest/image/user'] = user
    builder['/manifest/image/type'] = image_type

    # The name of the kernel in the image. Only applicable to kernel images.
    builder['/manifest/image/kernel_name'] = kernel_name
    
    # ancestry - the parent ami ids
    (ancestor_ami_ids || []).each_with_index do |ancestor_ami_id, index|
      builder["/manifest/image/ancestry/ancestor_ami_id[#{index}]"] = ancestor_ami_id
    end

    # digest - the digest of the AMI.
    builder['/manifest/image/digest'] = digest
    builder['/manifest/image/digest/@algorithm'] = digest_algorithm

    # size - the size of the uncompressed AMI.
    builder['/manifest/image/size'] = size.to_s
    
    # bundled size - the size of the bundled AMI.
    builder['/manifest/image/bundled_size'] = bundled_size.to_s
    
    # ec2 encrypted key element.
    builder['/manifest/image/ec2_encrypted_key'] = ec2_encrypted_key
    builder['/manifest/image/ec2_encrypted_key/@algorithm'] = cipher_algorithm
    
    # user encrypted key element.
    builder['/manifest/image/user_encrypted_key'] = user_encrypted_key
    builder['/manifest/image/user_encrypted_key/@algorithm'] = cipher_algorithm
    
    # ec2 encrypted iv element.
    builder['/manifest/image/ec2_encrypted_iv'] = ec2_encrypted_iv
    
    # user encrypted iv element.
    builder['/manifest/image/user_encrypted_iv'] = user_encrypted_iv
    
    # parts - list of the image parts.
    builder['/manifest/image/parts/@count'] = parts.size
    
    parts.each_with_index do |part, index|
      # Add image part element for each image part.
      builder["/manifest/image/parts/part[#{index}]/@index"] = index
      builder["/manifest/image/parts/part[#{index}]/filename"] = part[0]
      builder["/manifest/image/parts/part[#{index}]/digest"] = Format::bin2hex(part[1])
      builder["/manifest/image/parts/part[#{index}]/digest/@algorithm"] = digest_algorithm
      builder["/manifest/image/parts/part[#{index}]/@index"] = index
    end

    # Sign the manifest.
    sign(privkey_filename)
    
    return true
  end
  
  def self::version20071010?(xml)
    doc = REXML::Document.new(xml)
    version = REXML::XPath.first(doc.root, 'version')
    return (version and version.text and version.text == VERSION_STRING)
  end
  
  # Get the kernel_name
  def kernel_name()
    return get_element_text_or_nil('image/kernel_name')
  end
  
  # Get the default kernel_id
  def kernel_id()
    return get_element_text_or_nil('machine_configuration/kernel_id')
  end

  # Get the default ramdisk id
  def ramdisk_id()
    return get_element_text_or_nil('machine_configuration/ramdisk_id')
  end

  # Get the default product codes
  def product_codes()
    product_codes = []
    REXML::XPath.each(@doc, '/manifest/machine_configuration/product_codes/product_code') do |product_code|
      product_codes << product_code.text
    end
    product_codes
  end

  # Get the manifest's ancestry
  def ancestor_ami_ids()
    ancestor_ami_ids = []
    REXML::XPath.each(@doc, '/manifest/image/ancestry/ancestor_ami_id') do |node|
      ancestor_ami_ids << node.text unless (node.text.nil? or node.text.empty?)
    end
    ancestor_ami_ids
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

  # Get the block device mapping as a map.
  def block_device_mapping()
    bdm = {}
    REXML::XPath.each(@doc.root,'machine_configuration/block_device_mapping/mapping/') do |mapping|
      virtual = REXML::XPath.first(mapping, 'virtual').text
      device = REXML::XPath.first(mapping, 'device').text
      bdm[virtual] = device
    end
    bdm
  end

  # Return the size of the AMI.
  def size()
    return get_element_text( 'image/size' ).to_i()
  end
  
  # Return the (optional) architecture of the AMI.
  def arch()
    return get_element_text_or_nil('machine_configuration/architecture')
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
    
    # Get the XML for <machine_configuration> and <image> elements and sign them.
    machine_configuration_xml = XMLUtil.get_xml( @doc.to_s, 'machine_configuration' ) || ""
    image_xml = XMLUtil.get_xml( @doc.to_s, 'image' )
    sig = Crypto::sign( machine_configuration_xml + image_xml, privkey_filename )
         
    # Create the signature and certificate elements.
    XMLBuilder.new(@doc)['/manifest/signature'] = Format::bin2hex(sig)
  end

  # Return the signature
  def signature
    get_element_text('signature')
  end

  # Verify the signature
  def authenticate(cert)
    machine_configuration_xml = XMLUtil.get_xml( @doc.to_s, 'machine_configuration' ) || ""
    image_xml = XMLUtil.get_xml( @doc.to_s, 'image' )
    pubkey = Crypto::cert2pubkey(cert)
    Crypto::authenticate(machine_configuration_xml + image_xml, Format::hex2bin(signature), pubkey)
  end

  # Return the manifest as an XML string.
  def to_s()
    return @doc.to_s
  end

  def user()
    return get_element_text('image/user')
  end

  def image_type()
    return get_element_text('image/type')
  end

  def version()
    return get_element_text('version').gsub('-','').to_i
  end
  
  private
  
  def get_element_text_or_nil(xpath)
    element = REXML::XPath.first(@doc.root, xpath)
    return element.text if element
    return nil
  end
  
  def get_element_text(xpath)
    element = REXML::XPath.first(@doc.root, xpath)
    unless element
      raise "invalid AMI manifest, #{xpath} element not present"
    end
    unless element.text
      raise "invalid AMI manifest, #{xpath} element empty"
    end
    return element.text
  end
end
