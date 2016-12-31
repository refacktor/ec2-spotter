# Copyright 2008-2014 Amazon.com, Inc. or its affiliates.  All Rights
# Reserved.  Licensed under the Amazon Software License (the
# "License").  You may not use this file except in compliance with the
# License. A copy of the License is located at
# http://aws.amazon.com/asl or in the "license" file accompanying this
# file.  This file is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See
# the License for the specific language governing permissions and
# limitations under the License.

# ---------------------------------------------------------------------------
# Module that provides higher-level S3 functionality
# ---------------------------------------------------------------------------
require 'uri'
require 'cgi'
require 'ec2/common/constants'
require 'ec2/common/http'

module EC2
  module Common
    class S3Support

      attr_accessor :s3_url,
                    :user,
                    :pass

      DEFAULT_SIGV = EC2::Common::SIGV4
      DEFAULT_REGION = 'us-east-1'

      # Return true if the bucket name is S3 safe.
      #
      # Per the S3 dev guide @ http://docs.amazonwebservices.com/AmazonS3/2006-03-01/index.html?BucketRestrictions.html
      # - Be between 3 and 255 characters long
      # - Start with a number or letter
      # - Contain lowercase letters, numbers, periods (.), underscores (_), and dashes (-)
      # - Not be in an IP address style (e.g., "192.168.5.4")
      #
      # * Notes:
      # - !!(....) silliness to force a boolean to be returned
      def self.bucket_name_s3_safe?(bucket_name)
        # Can most probably fold this all into 1 grand regexp but 
        # for now opt for semi-clarity.
        !!((3..255).include?(bucket_name.length) and
           (/^[a-z0-9][a-z0-9\._-]+$/ =~ bucket_name) and
           (/^(\d{1,3}\.){3}\d{1,3}$/ !~ bucket_name))
      end


      # Return true if the bucket name is S3 (v2) safe.
      #
      # Per the S3 dev guide @ http://docs.amazonwebservices.com/AmazonS3/2006-03-01/index.html?BucketRestrictions.html
      # - Bucket names should not contain underscores (_)
      # - Bucket names should be between 3 and 63 characters long
      # - Bucket names should not end with a dash
      # - Bucket names cannot contain dashes next to periods (e.g., "my-.bucket.com" and "my.-bucket" are invalid)
      # - Bucket names must only contain lower case letters
      #
      # and naturally also fulfills bucket_name_s3_safe?() requirements
      #
      # * Notes:
      # - !!(....) silliness to force a boolean to be returned
      def self.bucket_name_s3_v2_safe?(bucket_name)
        # Can most probably fold this all into 1 grand regexp but 
        # for now opt for semi-clarity.
        !!(self.bucket_name_s3_safe?(bucket_name) and
           bucket_name.length <= 63 and
           not bucket_name.include?('_') and
           bucket_name[-1] != ?- and
           /(-\.)|(\.-)/ !~ bucket_name)
      end

      def initialize(s3_url, user, pass, format=nil, debug=nil, sigv=DEFAULT_SIGV, region=DEFAULT_REGION)
        @user = user
        @pass = pass
        @s3_url = fix_s3_url(s3_url)
        @format = format
        @debug = debug
        @sigv = sigv
        @region = region
      end

      def fix_s3_url(s3_url)
        if s3_url !~ %r{://}
          s3_url = "https://#{s3_url}"
        end
        if s3_url[-1..-1] != "/"
          s3_url << "/"
        end
        s3_url
      end

      def get_bucket_url(bucket)
        # The returned variable should not end with '/', makes constructing the path for sigv4 easier
        if not @format
          if bucket.include? "."
            @format = :path
          else
            @format = :subdomain
          end
        end

        case @format
        when :subdomain
          uri = URI.parse(@s3_url)
          return ["#{uri.scheme}://#{bucket}.#{uri.host}", bucket]
        when :path
          return ["#{@s3_url}#{bucket}", bucket]
        end
      end

      def get_acl(bucket, key, options={})
        begin
          url, bkt = get_bucket_url(bucket)
          url << "/#{CGI::escape(key)}?acl"
          http_fallback(url, @sigv) do |url, signature|
            EC2::Common::HTTP::get(url, bkt, nil, options, @user, @pass, nil, nil, @debug, signature, @region)
          end
        end
      end

      def check_bucket_exists(bucket, options={})
        url, bkt = get_bucket_url(bucket)
        http_fallback(url, @sigv) do |url, signature|
          EC2::Common::HTTP::head(url, bkt, options, @user, @pass, @debug, signature, @region)
        end
      end

      def get_bucket_location(bucket, options={})
        url, bkt = get_bucket_url(bucket)
        url << "?location"
        http_fallback(url, @sigv) do |url, signature|
          EC2::Common::HTTP::get(url, bkt, nil, options, @user, @pass, nil, nil, @debug, signature, @region)
        end
      end

      def create_bucket(bucket, location, options={})
        url, bkt = get_bucket_url(bucket)
        binary_data = ""
        if (location != nil)
          binary_data = "<CreateBucketConstraint><LocationConstraint>#{location}</LocationConstraint></CreateBucketConstraint>"
        end
        http_fallback(url, @sigv) do |url, signature|
          EC2::Common::HTTP::putdir(url, bkt, binary_data, options, @user, @pass, @debug, signature, @region)
        end
      end

      def list_bucket(bucket, prefix=nil, max_keys=nil, path=nil, options={})
        url, bkt = get_bucket_url(bucket)
        params = []
        params << "prefix=#{CGI::escape(prefix)}" if prefix
        params << "max-keys=#{CGI::escape(max_keys)}" if max_keys
        url << "?" + params.join("&") unless params.empty?
        http_fallback(url, @sigv) do |url, signature|
          EC2::Common::HTTP::get(url, bkt, path, options, @user, @pass, nil, nil, @debug, signature, @region)
        end
      end

      def get(bucket, key, path=nil, options={})
        url, bkt = get_bucket_url(bucket)
        url << "/#{CGI::escape(key)}"
        http_fallback(url, @sigv) do |url, signature|
          EC2::Common::HTTP::get(url, bkt, path, options, @user, @pass, nil, nil, @debug, signature, @region)
        end
      end

      def put(bucket, key, file, options={})
        url, bkt = get_bucket_url(bucket)
        url << "/#{CGI::escape(key)}"
        http_fallback(url, @sigv) do |url, signature|
          EC2::Common::HTTP::put(url, bkt, file, options, @user, @pass, @debug, signature, @region)
        end
      end

      def copy(bucket, key, source, options={})
        url, bkt = get_bucket_url(bucket)
        url << "/#{CGI::escape(key)}"
        options['x-amz-copy-source'] = CGI::escape(source)
        http_fallback(url, @sigv) do |url, signature|
          EC2::Common::HTTP::put(url, bkt, nil, options, @user, @pass, @debug, signature, @region)
        end
      end

      def delete(bucket, key="", options={})
        url, bkt = get_bucket_url(bucket)
        url << "/#{CGI::escape(key)}"
        http_fallback(url, @sigv) do |url, signature|
          EC2::Common::HTTP::delete(url, bkt, options, @user, @pass, @debug, signature, @region)
        end
      end

      private
      # This method will cycle through all possible signatures versions, starting
      # with the given the one as first choice
      def http_fallback url, sigv, &block
        all_sigv = [EC2::Common::SIGV2, EC2::Common::SIGV4]
        all_sigv.delete(sigv)
        ordered_sigv = [sigv].concat all_sigv
       
        resp = nil
        access_denied = false
        ordered_sigv.each do |o_sigv|
          redirected = true
          while redirected
            redirected = false
            begin
              resp = block.call(url, o_sigv)
            rescue EC2::Common::HTTP::Error::Redirect => e
              redirected = true
              url = e.endpoint
              STDERR.puts "Redirecting to #{url}, resigning request"
            rescue EC2::Common::HTTP::Error => e
              if e.code == 403
                access_denied = true 
              else
                raise e
              end
            end
          end
          # If the response was 403, try other sigv
          if access_denied == true
            access_denied = false
            STDERR.puts "Signature version #{o_sigv} authentication failed, trying different signature version"
          else
            break
          end
        end
        resp
      end
    end
  end
end
