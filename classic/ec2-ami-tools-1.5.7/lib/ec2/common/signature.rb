# Copyright 2008-2014 Amazon.com, Inc. or its affiliates.  All Rights
# Reserved.  Licensed under the Amazon Software License (the
# "License").  You may not use this file except in compliance with the
# License. A copy of the License is located at
# http://aws.amazon.com/asl or in the "license" file accompanying this
# file.  This file is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See
# the License for the specific language governing permissions and
# limitations under the License.

require 'uri'

require 'ec2/common/headers'
require 'ec2/common/headersv4'

module EC2
  module Common
    module Signature
      def self.curl_args_sigv2(url, bucket, http_method, options, user, pass)
          headers = EC2::Common::Headers.new(http_method)
          options.each do |name, value| headers.add(name, value) end
          headers.sign(user, pass, url, bucket) if user and pass
          headers.get
      end
 
      def self.curl_args_sigv4(url, region, bucket, http_method, optional_headers, user, pass, data=nil)
        aws_secret_access_key = pass
        aws_access_key_id = user
        if (user.is_a?(Hash))
            aws_access_key_id = user['aws_access_key_id']
            aws_secret_access_key = user['aws_secret_access_key']
            delegation_token = user['aws_delegation_token']
        end
        host, path, query = parseURL(url, bucket)
        hexdigest = if data
          HeadersV4::hexdigest data
        else
          HeadersV4::hexdigest ""
        end
        optional_headers ||= {}
        unless delegation_token.nil?
            optional_headers[EC2::Common::Headers::X_AMZ_SECURITY_TOKEN] = delegation_token
        end
        headers_obj = HeadersV4.new({:host => host,
                               :hexdigest_body => hexdigest,
                               :region => region,
                               :service => "s3",
                               :http_method => http_method,
                               :path => path,
                               :querystring => query,
                               :access_key_id => aws_access_key_id,
                               :secret_access_key => aws_secret_access_key},
                               optional_headers)
        headers = headers_obj.add_authorization!
        headers
      end

      def self.parseURL(url, bucket)
        uri = URI.parse(url)
        host = uri.host
        path = uri.path
        path = "/" if path == ""

        [host, path, "#{uri.query}"]
      end
    end
  end
end
