# Copyright 2008-2014 Amazon.com, Inc. or its affiliates.  All Rights
# Reserved.  Licensed under the Amazon Software License (the
# "License").  You may not use this file except in compliance with the
# License. A copy of the License is located at
# http://aws.amazon.com/asl or in the "license" file accompanying this
# file.  This file is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See
# the License for the specific language governing permissions and
# limitations under the License.

require 'base64'
require 'cgi'
require 'openssl'
require 'digest/sha1'
require 'net/https'
require 'rexml/document'
require 'time'
require 'ec2/amitools/version'

module EC2
  class EC2Client
    attr_accessor :verbose
    attr_accessor :aws_access_key_id
    attr_accessor :aws_secret_access_key
    attr_accessor :http

    def parse_url(url)
      bits = url.split(":")
      secure = {"https"=>true, "http"=>false}[bits[0]]
      port = secure ? 443 : 80
      port = Integer(bits[2]) if bits.size > 2
      server = bits[1][2..-1]
      [server, port, secure]
    end
    
    def initialize(akid, secretkey, url)
      @aws_access_key_id = akid
      @aws_secret_access_key = secretkey
      server, port, is_secure = parse_url(url)
      @http = Net::HTTP.new(server, port)
      @http.use_ssl = is_secure
      @verbose = false
    end

    def pathlist(key, arr)
      params = {}
      arr.each_with_index do |value, i|
        params["#{key}.#{i+1}"] = value
      end
      params
    end
    
    def describe_regions(regionNames=[])
      params = pathlist("regionName", regionNames)
      make_request("DescribeRegions", params)
    end

    def describe_images(imageIds=[], kwargs={})
      params = pathlist("ImageId", imageIds)
      params.merge!(pathlist("Owner", kwargs[:owners])) if kwargs[:owners]
      params.merge!(pathlist("ExecutableBy", kwargs[:executableBy])) if kwargs[:executableBy]
      make_request("DescribeImages", params)
    end

    def make_request(action, params, data='')
      resp = nil
      @http.start do
        params.merge!({ "Action"=>action,
                        "SignatureVersion"=>"1",
                        "AWSAccessKeyId"=>@aws_access_key_id,
                        "Version"=> "2008-12-01",
                        "Timestamp"=>Time.now.getutc.iso8601,
                      })
        p params if @verbose
        
        canonical_string = params.sort_by { |param| param[0].downcase }.map { |param| param.join }.join
        puts canonical_string if @verbose
        sig = encode(@aws_secret_access_key, canonical_string)
        
        path = "?" + params.sort.collect do |param|
          CGI::escape(param[0]) + "=" + CGI::escape(param[1])
        end.join("&") + "&Signature=" + sig
        
        puts path if @verbose
        
        req = Net::HTTP::Get.new("/#{path}")
        
        # ruby will automatically add a random content-type on some verbs, so
        # here we add a dummy one to 'supress' it.  change this logic if having
        # an empty content-type header becomes semantically meaningful for any
        # other verb.
        req['Content-Type'] ||= ''
        req['User-Agent'] = 'ec2-migrate-manifest #{PKG_VERSION}-#{PKG_RELEASE}'

        data = nil unless req.request_body_permitted?
        resp = @http.request(req, data)

      end
      REXML::Document.new(resp.body)
    end

    # Encodes the given string with the aws_secret_access_key, by taking the
    # hmac-sha1 sum, and then base64 encoding it.  Optionally, it will also
    # url encode the result of that to protect the string if it's going to
    # be used as a query string parameter.
    def encode(aws_secret_access_key, str, urlencode=true)
      digest = OpenSSL::Digest::Digest.new('sha1')
      b64_hmac = Base64.encode64(OpenSSL::HMAC.digest(digest, aws_secret_access_key, str)).strip
      if urlencode
        return CGI::escape(b64_hmac)
      else
        return b64_hmac
      end
    end
  end
end
