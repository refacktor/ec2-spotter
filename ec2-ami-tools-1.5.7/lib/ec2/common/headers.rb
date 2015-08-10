# Copyright 2008-2014 Amazon.com, Inc. or its affiliates.  All Rights
# Reserved.  Licensed under the Amazon Software License (the
# "License").  You may not use this file except in compliance with the
# License. A copy of the License is located at
# http://aws.amazon.com/asl or in the "license" file accompanying this
# file.  This file is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See
# the License for the specific language governing permissions and
# limitations under the License.

module EC2
  module Common
    class Headers
      MANDATORY = ['content-md5', 'content-type', 'date'] # Order matters.
      X_AMZ_PREFIX = 'x-amz'
      X_AMZ_SECURITY_TOKEN = 'x-amz-security-token'
      
      def initialize(verb)
        raise ArgumentError.new('invalid verb') if verb.to_s.empty?
        @headers = {}
        @verb = verb
      end
      
      #---------------------------------------------------------------------
      # Add a Header key-value pair.
      def add(name, value)
        raise ArgumentError.new("name '#{name.inspect}' must be a String") unless name.is_a? String
        raise ArgumentError.new("value '#{value.inspect}' (#{name}) must be a String") unless value.is_a? String
        @headers[name.downcase.strip] = value.strip
      end

      #-----------------------------------------------------------------------
      # Sign the headers using HMAC SHA1.
      def sign(creds, aws_secret_access_key, url, bucket)
        aws_access_key_id = creds
        delegation_token = nil
        if (creds.is_a?(Hash))
            aws_access_key_id = creds['aws_access_key_id']
            aws_secret_access_key = creds['aws_secret_access_key']
            delegation_token = creds['aws_delegation_token']
        end

        @headers['date'] = Time.now.httpdate          # add HTTP Date header
        @headers['content-type'] ||= 'application/x-www-form-urlencoded'

        # Build the data to sign.
        data = @verb + "\n"

        # Deal with mandatory headers first:
        MANDATORY.each do |name|
          data += @headers.fetch(name, "") + "\n"
        end
 
        unless delegation_token.nil?
            @headers[X_AMZ_SECURITY_TOKEN] = delegation_token
        end
        # Add mandatory headers and those that start with the x-amz prefix.
        @headers.sort.each do |name, value|
          # Headers that start with x-amz must have both their name and value 
          # added.
          if name =~ /^#{X_AMZ_PREFIX}/
            data += name + ":" + value +"\n"
          end
        end
 
        uri = URI.parse(url)
        # Ignore everything in the URL after the question mark unless, by the
        # S3 protocol, it signifies an acl, torrent, logging or location parameter
        if uri.host.start_with? bucket
          data << "/#{bucket}"
        end
        data << if uri.path.empty?
          "/"
        else
          uri.path
        end
        ['acl', 'logging', 'torrent', 'location'].each do |item|
          regex = Regexp.new("[&?]#{item}($|&|=)")
          data << '?' + item if regex.match(url)
        end

        # Sign headers and then put signature back into headers.
        signature = Base64.encode64(Crypto::hmac_sha1(aws_secret_access_key, data))
        signature.chomp!
        @headers['Authorization'] = "AWS #{aws_access_key_id}:#{signature}"
      end

      #-----------------------------------------------------------------------
      # Return the headers as a map from header name to header value.
      def get
        return @headers.clone
      end
    end
  end
end
