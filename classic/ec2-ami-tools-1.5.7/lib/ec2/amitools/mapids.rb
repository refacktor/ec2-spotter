# Copyright 2008-2014 Amazon.com, Inc. or its affiliates.  All Rights
# Reserved.  Licensed under the Amazon Software License (the
# "License").  You may not use this file except in compliance with the
# License. A copy of the License is located at
# http://aws.amazon.com/asl or in the "license" file accompanying this
# file.  This file is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See
# the License for the specific language governing permissions and
# limitations under the License.

require 'ec2/amitools/minimalec2'

class KernelMappings
  ENDPOINT = "http://ec2.amazonaws.com"

  class MappingError < StandardError; end

  attr_reader :source_image_info
  attr_reader :target_image_info

  #----------------------------------------------------------------------------#

  def get_ec2_client(akid, secretkey, endpoint=nil)
    EC2::EC2Client.new(akid, secretkey, endpoint)
  end

  #----------------------------------------------------------------------------#

  def add_endpoint_from_env(endpoints)
    str = ENV['AMITOOLS_EC2_REGION_ENDPOINT']
    if not str
      return
    end

    components = str.split('@').collect{|s| s.strip()}
    if components.size != 2
      return
    end
    
    endpoints[components[0]] = components[1]
  end

  def get_endpoints(akid, secretkey, endpoint=nil)
    endpoint ||= ENDPOINT
    endpoints = {}
    ec2conn = get_ec2_client(akid, secretkey, endpoint)
    resp_doc = ec2conn.describe_regions()
    REXML::XPath.each(resp_doc.root, '/DescribeRegionsResponse/regionInfo/item') do |region|
      region_name = REXML::XPath.first(region, 'regionName').text
      region_url = REXML::XPath.first(region, 'regionEndpoint').text
      region_url = 'https://'+region_url unless region_url =~ %r{^https?://}
      endpoints[region_name] = region_url
    end
    add_endpoint_from_env(endpoints)
    endpoints
  end

  #----------------------------------------------------------------------------#

  def create_ec2_connections(akid, secretkey, endpoint=nil)
    @ec2conn = {}
    @endpoints = get_endpoints(akid, secretkey, endpoint)
    @endpoints.each do |region, endpoint|
      @ec2conn[region] = get_ec2_client(akid, secretkey, endpoint)
    end
  end

  #----------------------------------------------------------------------------#

  def get_source_images_info()
    @ec2conn.each do |region, connection|
      $stderr.puts "Getting source data from #{region} #{@source_images.inspect}..." if @verbose
      resp_doc = connection.describe_images(@source_images)
      @source_images_info = parse_imageset(resp_doc)
      $stderr.puts "Found #{@source_images_info.size} images in #{region}." if @verbose
      # We assume all the images we're trying to map are in the same region.
      return if @source_images_info.size > 0
    end
  end

  #----------------------------------------------------------------------------#

  def get_target_candidates()
    owners = @source_images_info.map { |ii| ii['imageOwnerId'] }
    $stderr.puts "Getting target data from #{region} #{owners.inspect}..." if @verbose
    resp_doc = @ec2conn[@target_region].describe_images([], :ownerIds => owners)
    @target_images_info = parse_imageset(resp_doc)
    $stderr.puts "Found #{@target_images_info.size} images in #{region}." if @verbose
  end

  #----------------------------------------------------------------------------#

  def parse_imageset(resp_doc)
    images_info = []
    resp_doc.each_element('DescribeImagesResponse/imagesSet/item') do |image|
      image_data = {}
      image.each_element() { |elem| image_data[elem.name] = elem.text }
      images_info << image_data
    end
    images_info
  end

  #----------------------------------------------------------------------------#

  def initialize(akid, secretkey, source_images, target_region, endpoint=nil)
    @target_region = target_region
    @source_images = source_images
    create_ec2_connections(akid, secretkey, endpoint)
    unless @ec2conn.has_key?(target_region)
      raise MappingError.new("Invalid region: #{target_region}")
    end
  end

  #----------------------------------------------------------------------------#

  def matchable_image(image)
    summary = {}
    ['imageOwnerId', 'imageType'].each { |key| summary[key] = image[key] }
    summary[:s3key] = image['imageLocation'].sub(%r{^/*[^/]+/},'')
    summary
  end

  #----------------------------------------------------------------------------#

  def find_missing_targets(targets)
    @target_images_info.each { |ii| targets.delete(ii['imageId']) } unless @target_images_info.nil?
    return nil if targets.empty?
    lookups = parse_imageset(@ec2conn[@target_region].describe_images(targets))
    lookups.each { |ii| targets.delete(ii['imageId']) }
    return nil if targets.empty?
    targets
  end

  #----------------------------------------------------------------------------#

  def [](identifier)
    if @target_images_info.nil?
      get_source_images_info()
      get_target_candidates()
    end
    source_info = @source_images_info.find { |ii| ii['imageId'] == identifier }
    raise MappingError.new("'#{identifier}' not found.") if source_info.nil?
    source_match = matchable_image(source_info)
    target_info = @target_images_info.find { |ii| source_match == matchable_image(ii) }
    raise MappingError.new("Mapping for '#{identifier}' not found.") if target_info.nil?
    target_info['imageId']
  end
end
