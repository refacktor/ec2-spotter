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
# Module that provides http functionality.
# ---------------------------------------------------------------------------
require 'uri'
require 'set'
require 'time'
require 'base64'
require 'tmpdir'
require 'tempfile'
require 'fileutils'

require 'ec2/common/constants'
require 'ec2/common/curl'
require 'ec2/common/signature'
require 'ec2/common/headers'
require 'ec2/amitools/crypto'

module EC2
  module Common
    module HTTP
      DEFAULT_SIGV = EC2::Common::SIGV4
      DEFAULT_REGION = 'us-east-1'

      class Response < EC2::Common::Curl::Response
        attr_reader :body
        def initialize(code, type, body=nil)
          super code, type
          @body = body
        end
      end
    
      #-----------------------------------------------------------------------      
      # Errors.
      class Error < RuntimeError
        attr_reader :code
        def initialize(msg, code = nil)          
          super(msg)
          @code = code || 1
        end
        class PathInvalid < Error; end
        class Write < Error;       end
        class BadDigest < Error
          def initialize(file, expected, obtained)
            super("Digest for file '#{file}' #{obtained} differs from expected digest #{digest}")
          end
        end
        class Transfer < Error;    end
        class Retrieve < Transfer; end
        class Redirect < Error
          attr_accessor :code, :endpoint
          def initialize(code, endpoint)
            super("Redirected (#{code}) to new endpoint: #{endpoint}")
            @code = code
            @endpoint = endpoint
          end
        end
      end
      
      
      #-----------------------------------------------------------------------      
      # Invoke curl with arguments given and process results of output file
      def HTTP::invoke(url, arguments, outfile, debug=false)
        begin
          raise ArgumentError.new(outfile) unless File.exists? outfile
          result = EC2::Common::Curl.execute("#{arguments.join(' ')} '#{url}'", debug)
          if result.success?
            if result.response.success?
              return result.response
            else
              synopsis= 'Server.Error(' + result.response.code.to_s + '): '
              message = result.stderr + ' '
              if result.response.type == 'application/xml'                
                require 'rexml/document'
                doc = REXML::Document.new(IO.read(outfile))
                if doc.root
                  if result.response.redirect?
                    endpoint = REXML::XPath.first(doc, '/Error/Endpoint').text
                    raise Error::Redirect.new(result.response.code, endpoint)
                  end
                  content = REXML::XPath.first(doc, '/Error/Code')
                  unless content.nil? or content.text.empty?
                    synopsis= 'Server.'+ content.text + '(' + 
                      result.response.code.to_s + '): '
                  end
                  content = REXML::XPath.first(doc, '/Error/Message')
                  message = content.text unless content.nil?
                end
              else
                if result.response.type =~ /text/
                  message << IO.read(outfile)
                end
              end
              raise Error::Transfer.new(synopsis + message, result.response.code)
            end
          else
            synopsis= 'Curl.Error(' + result.status.to_s + '): '
            message = result.stderr.split("\n").map { |line|            
              if (m = /^curl:\s+(?:\(\d{1,2}\)\s+)*(.*)$/.match(line))
                (m.captures[0] == "try 'curl --help' for more information") ? 
                  '' : m.captures[0]
              else
                line.strip
              end
            }.join("\n")
            output = result.stdout.chomp
            if debug and not output.empty?
              message << "\nCurl.Output: " + output.gsub("\n", "\nCurl.Output: ")
            end
            raise Error::Transfer.new(synopsis + message.strip + '.', result.status)
          end
        rescue EC2::Common::Curl::Error => e
          raise Error::Transfer.new(e.message, e.code)
        end
      end
      
      #-----------------------------------------------------------------------      
      # Delete the file at the specified url.
      def HTTP::delete(url, bucket, options={}, user=nil, pass=nil, debug=false, sigv=DEFAULT_SIGV, region=DEFAULT_REGION)
        raise ArgumentError.new('Bad options in HTTP::delete') unless options.is_a? Hash
        begin
          output = Tempfile.new('ec2-delete-response')
          output.close
          
          arguments = ['-X DELETE']
          arguments << get_arguments(url, bucket, 'DELETE', options, user, pass, sigv, region)
          arguments << '-o ' + output.path
          
          response = HTTP::invoke(url, arguments, output.path, debug)
          return EC2::Common::HTTP::Response.new(response.code, response.type)
        ensure
          output.close(true)
          GC.start
        end
      end


      #-----------------------------------------------------------------------      
      # Put the file at the specified path to the specified url. The content of
      # the options hash will be passed as HTTP headers. If the username and
      # password options are specified, then the headers will be signed.
      def HTTP::put(url, bucket, path, options={}, user=nil, pass=nil, debug=false, sigv=DEFAULT_SIGV, region=DEFAULT_REGION)
        path ||= "/dev/null"
        raise Error::PathInvalid.new(path) unless path and File::exist?(path)
        raise ArgumentError.new('Bad options in HTTP::put') unless options.is_a? Hash
        
        begin
          output = Tempfile.new('ec2-put-response')
          output.close

          arguments = [get_arguments(url, bucket, 'PUT', options, user, pass, sigv, region, open(path))]
          arguments << '-T ' + path
          arguments << '-o ' + output.path

          response = HTTP::invoke(url, arguments, output.path, debug)
          return EC2::Common::HTTP::Response.new(response.code, response.type)
        ensure
          output.close(true)
          GC.start
        end
      end
  
      #-----------------------------------------------------------------------      
      # Create a bucket using the specified url and constraints (either a file 
      # with location string, or the string itself). The content of the 
      # options hash will be passed as HTTP headers. If the username and 
      # password options are specified, then the headers will be signed.
      def HTTP::putdir(url, bucket, constraint, options={}, user=nil, pass=nil, debug=false, sigv=DEFAULT_SIGV, region=DEFAULT_REGION)
        if constraint and File::exists?(constraint)
          putdir_file(url, bucket, constraint, options, user, pass, debug)
        else
          putdir_binary_data(url, bucket, constraint, options, user, pass, debug, sigv, region)
        end
      end

      def HTTP::putdir_file(url, bucket, path, options={}, user=nil, pass=nil, debug=false)
        raise Error::PathInvalid.new(path) unless path and File::exist?(path)
        raise ArgumentError.new('Bad options in HTTP::putdir_file') unless options.is_a? Hash

        begin
          output = Tempfile.new('ec2-put-response')
          output.close
          arguments = []

          headers = EC2::Common::Headers.new('PUT')
          options.each do |name, value| headers.add(name, value) end
          headers.sign(user, pass, url, bucket) if user and pass
          
          arguments << headers.get.map { |name, value| "-H \"#{name}:#{value}\""}.join(' ')
          arguments << '-T - '
          arguments << '-o ' + output.path
          arguments << " < #{path}"

          response = HTTP::invoke(url, arguments, output.path, debug)
          return EC2::Common::HTTP::Response.new(response.code, response.type)
        ensure
          output.close(true)
          GC.start
        end
      end

      def HTTP::putdir_binary_data(url, bucket, binary_data, options={}, user=nil, pass=nil, debug=false, sigv=DEFAULT_SIGV, region=DEFAULT_REGION)
        raise ArgumentError.new('Bad options in HTTP::putdir_binary_data') unless options.is_a? Hash
        
        begin
          output = Tempfile.new('ec2-put-response')
          output.close
          
          arguments = ["-X PUT"]
          arguments << "--data-binary \"#{binary_data}\""
          arguments << get_arguments(url, bucket, 'PUT', options, user, pass, sigv, region, binary_data)
          arguments << '-o ' + output.path

          response = HTTP::invoke(url, arguments, output.path, debug)
          return EC2::Common::HTTP::Response.new(response.code, response.type)          
        ensure
          output.close(true)
          GC.start
        end
      end
  
      #-----------------------------------------------------------------------      
      # Save the file at specified url, to the local file at specified path.
      # The local file will be created if necessary, or overwritten already
      # existing. If specified, the expected digest is compare to that of the
      # retrieved file which gets deleted if the calculated digest does not meet
      # expectations. If no path is specified, and the response is a 200 OK, the
      # content of the response will be returned as a String
      def HTTP::get(url, bucket, path=nil, options={}, user=nil, pass=nil, 
                    size=nil, digest=nil, debug=false, sigv=DEFAULT_SIGV, region=DEFAULT_REGION)
        raise ArgumentError.new('Bad options in HTTP::get') unless options.is_a? Hash
        buffer = nil
        if path.nil?
          buffer = Tempfile.new('ec2-get-response')
          buffer.close
          path = buffer.path
        else
          directory = File.dirname(path)
          FileUtils.mkdir_p(directory) unless File.exist?(directory)
        end
       
        arguments = [get_arguments(url, bucket, 'GET', options, user, pass, sigv, region)]
        arguments << "--max-filesize #{size}" if size
        arguments << '-o ' + path
        
        begin
          FileUtils.touch path
          response = HTTP::invoke(url, arguments, path, debug)
          body = nil
          if response.success?
            if digest
              obtained = IO.popen("openssl sha1 #{path}") { |io| io.readline.split(/\s+/).last.strip }
              unless digest == obtained                
                File.delete(path) if File.exists?(path) and not buffer.is_a? Tempfile
                raise Error::BadDigest.new(path, digest, obtained)
              end
            end
            if buffer.is_a? Tempfile
              buffer.open; 
              body = buffer.read
            end
          else
            File.delete(path) if File.exist?(path) and not buffer.is_a? Tempfile
          end
          return EC2::Common::HTTP::Response.new(response.code, response.type, body)
        rescue Error::Transfer => e
          File::delete(path) if File::exist?(path) and not buffer.is_a? Tempfile
          raise Error::Retrieve.new(e.message, e.code)
        ensure
          if buffer.is_a? Tempfile
            buffer.close
            buffer.unlink if File.exists? path
            GC.start
          end
        end
      end
      
  
      #-----------------------------------------------------------------------      
      # Get the HEAD response for the specified url.
      def HTTP::head(url, bucket, options={}, user=nil, pass=nil, debug=false, sigv=DEFAULT_SIGV, region=DEFAULT_REGION)
        raise ArgumentError.new('Bad options in HTTP::head') unless options.is_a? Hash
        begin
          output = Tempfile.new('ec2-head-response')
          output.close
          
          arguments = ['--head']
          arguments << get_arguments(url, bucket, 'HEAD', options, user, pass, sigv, region)
          arguments << '-o ' + output.path
          
          response = HTTP::invoke(url, arguments, output.path, debug)
          return EC2::Common::HTTP::Response.new(response.code, response.type)
          
        rescue Error::Transfer => e
          raise Error::Retrieve.new(e.message, e.code)
        ensure
          output.close(true)
          GC.start
        end
      end

      private
      def HTTP::get_arguments(url, bucket, http_method, options, user, pass, sigv, region, file_path=nil)
        headers = if user and pass
          if sigv == EC2::Common::SIGV2
            EC2::Common::Signature::curl_args_sigv2(url, bucket,
                                                    http_method,
                                                    options,
                                                    user, pass)
          elsif sigv == EC2::Common::SIGV4
            EC2::Common::Signature::curl_args_sigv4(url, region, bucket,
                                                    http_method,
                                                    options,
                                                    user, pass,
                                                    file_path)
          end
        else
          options
        end
        headers.map { |name, value| "-H \"#{name}:#{value}\""}.join(' ')
      end
    end
  end
end
