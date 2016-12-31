# Copyright 2008-2014 Amazon.com, Inc. or its affiliates.  All Rights
# Reserved.  Licensed under the Amazon Software License (the
# "License").  You may not use this file except in compliance with the
# License. A copy of the License is located at
# http://aws.amazon.com/asl or in the "license" file accompanying this
# file.  This file is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See
# the License for the specific language governing permissions and
# limitations under the License.

#------------------------------------------------------------------------------
require 'pathname'
require 'ec2/platform'

module EC2
  module Platform
    class Unknown < RuntimeError
      def initialize(name)
        super("Unknown platform: #{name}")
        @name = name
      end
      attr_reader :name
    end
    
    class Unsupported < RuntimeError
      def initialize(name)
        super("Unsupported or unimplemented platform: #{name}")
        @name = name
      end
      attr_reader :name
    end
    
    def self.initialize
      return EC2::Platform::PEER if defined? EC2::Platform::PEER
      impl = Platform::IMPL
      base = impl.to_s
      
      # must be a known architecture
      raise Unknown.new(base), caller if base.nil? or impl == :unknown      
      
      # base file must exist in same directory as this one
      file = Pathname.new(__FILE__).dirname + base
      raise Unsupported.new(base), caller unless File.exists? file
      
      # a require statement must succeed
      implemented = require "ec2/platform/#{base}" rescue false
      raise Unsupported.new(impl), caller unless implemented
      
      # cross fingers and hope the 'required' peer set the PEER constant
      raise Unsupported.new(impl), caller unless defined? EC2::Platform::PEER
      EC2::Platform::PEER
    end    
    Current = initialize
  end
end
