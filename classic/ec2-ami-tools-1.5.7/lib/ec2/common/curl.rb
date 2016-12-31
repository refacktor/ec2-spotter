# Copyright 2008-2014 Amazon.com, Inc. or its affiliates.  All Rights
# Reserved.  Licensed under the Amazon Software License (the
# "License").  You may not use this file except in compliance with the
# License. A copy of the License is located at
# http://aws.amazon.com/asl or in the "license" file accompanying this
# file.  This file is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See
# the License for the specific language governing permissions and
# limitations under the License.

# -----------------------------------------------------------------------------
# This is a light ruby wrapper around the curl command-line utility.
# Unless the run with the -f/--fail flag, the curl utility returns an exit-code 
# of value 0 for requests that produce responses with HTTP errors codes greater 
# than or equal to 400; it returns 22 and swallows the response. This wrapper 
# attempts to emulate the -f/--fail flag while making available response codes
# with minimal verbosity.
# -----------------------------------------------------------------------------
require 'ec2/oem/open4'
require 'tmpdir'

module EC2
  module Common
    module Curl
      class Error < RuntimeError
        attr_reader :code
        def initialize(message, code=22)
          super message
          @code = code
        end
      end
      class Response
        attr_reader :code, :type
        def initialize(code, type)
          @code = code.to_i
          @type = type
        end
        def success?
          (200..299).include? @code
        end
        def redirect?
          (300..399).include? @code
        end
        def text?
          @type =~ /(text|xml)/
        end
      end
      
      class Result
        attr_reader :stdout, :stderr, :status, :response
        def initialize(stdout, stderr, status, response = nil)
          unless response.nil? or response.is_a? EC2::Common::Curl::Response
            raise ArgumentError.new('invalid response argument')
          end
          @stdout  = stdout
          @stderr  = stderr
          @status  = status
          @response= response
        end
        def success?
          @status == 0
        end
      end
      
      def self.invoke(command, debug=false)
        invocation =  "curl -sSL #{command}"
#         invocation =  "curl -vsSL #{command}" if debug
        invocation << ' -w "Response-Code: %{http_code}\nContent-Type: %{content_type}"'
        STDERR.puts invocation if debug
        pid, stdin, stdout, stderr = Open4::popen4(invocation)
        pid, status = Process::waitpid2 pid
        [status, stdout, stderr]
      end

      def self.print_error(command, status, out, err)
        puts "----COMMAND------------------"
        puts command
        puts "----EXIT-CODE----------------"
        puts status.exitstatus.inspect
        puts "----STDOUT-------------------"
        puts out
        puts "----STDERR-------------------"
        puts err
        puts "-----------------------------"
      end

      def self.execute(command, debug = false)
        status, stdout, stderr = self.invoke(command, debug)
        out = stdout.read
        err = stderr.read
        if status.exitstatus == 0
          code, type = out.chomp.split("\n").zip(['Response-Code', 'Content-Type']).map do |line, name|
            (m = Regexp.new("^#{name}: (\\S+)$").match(line.chomp)) ? m.captures[0] : nil
          end
          if code.nil?
            self.print_error(command, status, out, err) if debug
            raise EC2::Common::Curl::Error.new(
              'Invalid curl output for response-code. Is the server up and reachable?'
            )
          end
          response = EC2::Common::Curl::Response.new(code, type)
          return EC2::Common::Curl::Result.new(out, err, status.exitstatus, response)
        else
          self.print_error(command, status, out, err) if debug
          return EC2::Common::Curl::Result.new(out, err, status.exitstatus)
        end
      end
    end    
  end
end
