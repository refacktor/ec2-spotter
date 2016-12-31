# Copyright 2008-2014 Amazon.com, Inc. or its affiliates.  All Rights
# Reserved.  Licensed under the Amazon Software License (the
# "License").  You may not use this file except in compliance with the
# License. A copy of the License is located at
# http://aws.amazon.com/asl or in the "license" file accompanying this
# file.  This file is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See
# the License for the specific language governing permissions and
# limitations under the License.

module ParameterExceptions
  class Error < RuntimeError
  end

  class MissingMandatory < Error
    def initialize(name)
      super("missing mandatory parameter: #{name}")
    end
  end

  class InvalidCombination < Error
    def initialize(name1, name2)
      super("#{name1} and #{name2} may not both be provided")
    end
  end

  class InvalidValue < Error
    def initialize(name, value, msg=nil)
      message = "#{name} has invalid value '#{value.to_s}'"
      message += ": #{msg}" unless msg.nil?
      super(message)
    end
  end
end
