# Copyright 2008-2014 Amazon.com, Inc. or its affiliates.  All Rights
# Reserved.  Licensed under the Amazon Software License (the
# "License").  You may not use this file except in compliance with the
# License. A copy of the License is located at
# http://aws.amazon.com/asl or in the "license" file accompanying this
# file.  This file is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See
# the License for the specific language governing permissions and
# limitations under the License.

require 'ec2/amitools/manifestv20071010'
require 'ec2/amitools/manifestv20070829'
require 'ec2/amitools/manifestv3'
require 'rexml/document'

class ManifestWrapper

  class InvalidManifest < RuntimeError
  end

  # All the manifest fields we support.
  V3_FIELDS = [
               :name,
               :user,
               :parts,
               :size,
               :bundled_size,
               :user_encrypted_key,
               :ec2_encrypted_key,
               :cipher_algorithm,
               :user_encrypted_iv,
               :ec2_encrypted_iv,
               :digest,
               :digest_algorithm,
               :bundler_name,
               :bundler_version,
               :bundler_release,
              ]

  V3_FIELDS.each { |field| attr_reader(field) }

  V20070829_FIELDS = [
                      :arch,
                     ]

  V20070829_FIELDS.each { |field| attr_reader(field) }

  V20071010_FIELDS = [
                      :image_type,
                      :kernel_id,
                      :ramdisk_id,
                      :product_codes,
                      :ancestor_ami_ids,
                      :block_device_mapping,
                      :kernel_name,
                     ]

  V20071010_FIELDS.each { |field| attr_reader(field) }

  # We want to pass some methods through as well.
  METHODS = [
             :authenticate,
            ]

  METHODS.each do |method|
    define_method(method) do |*args|
      @manifest.send(method, *args)
    end
  end

  # Should the caller want the underlying manifest for some reason.
  attr_reader :manifest

  def get_manifest_version(manifest_xml)
    begin
      version_elem = REXML::XPath.first(REXML::Document.new(manifest_xml), '/manifest/version')
      raise InvalidManifest.new("Invalid manifest.") if version_elem.nil?
      return version_elem.text.to_i
    rescue => e
      raise InvalidManifest.new("Invalid manifest.")
    end
  end

  def initialize(manifest_xml)
    version = get_manifest_version(manifest_xml)
    
    if version > 20071010
      raise InvalidManifest.new("Manifest is too new for this tool to handle. Please upgrade.")
    end
    
    if version < 3
      raise InvalidManifest.new("Manifest is too old for this tool to handle.")
    end
    
    # Try figure out what manifest version we have
    @manifest = if ManifestV20071010::version20071010?(manifest_xml)
                  ManifestV20071010.new(manifest_xml)
                elsif ManifestV20070829::version20070829?(manifest_xml)
                  ManifestV20070829.new(manifest_xml)
                elsif ManifestV3::version3?(manifest_xml)
                  ManifestV3.new(manifest_xml)
                else
                  raise InvalidManifest.new("Unrecognised manifest version.")
                end
    
    # Now populate the fields. First, stuff that's in all the
    # manifests we deal with.
    V3_FIELDS.each do |field|
      instance_variable_set("@#{field.to_s}", @manifest.send(field))
    end
    
    # Next, the next version up.
    if @manifest.version > 3
      V20070829_FIELDS.each do |field|
        instance_variable_set("@#{field.to_s}", @manifest.send(field))
      end
    else
      # Some mandatory fields we need in later versions:
      @arch = 'i386'
    end
    
    # Next, the next version up.
    if @manifest.version > 20070829
      V20071010_FIELDS.each do |field|
        instance_variable_set("@#{field.to_s}", @manifest.send(field))
      end
    else
      # Some mandatory fields we need in later versions:
      @image_type = 'machine'
    end
  end
end
