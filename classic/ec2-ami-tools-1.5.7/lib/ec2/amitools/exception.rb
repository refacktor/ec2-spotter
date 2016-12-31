# Copyright 2008-2014 Amazon.com, Inc. or its affiliates.  All Rights
# Reserved.  Licensed under the Amazon Software License (the
# "License").  You may not use this file except in compliance with the
# License. A copy of the License is located at
# http://aws.amazon.com/asl or in the "license" file accompanying this
# file.  This file is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See
# the License for the specific language governing permissions and
# limitations under the License.

##
# An exception thrown to indicate an unrecoverable error has been encountered.
# The process should be terminated and the exception's message should be
# displayed to the user.
#
class FatalError < Exception
  ##
  # ((|message|)) The message that should be displayed to the user.
  # ((|cause|))  The exception that caused the fatal error.
  #
  def initialize(message, cause = nil)
    super(message)
    @cause = cause
  end
end

#------------------------------------------------------------------------------#

##
# File access error.
#
class FileError < FatalError
  def initialize(filename, error_description, sys_call_err = nil)
      message = "File Error: #{error_description} \n" +
                "File name: #{filename}\n"
      super(message, sys_call_err)
  end
end

#------------------------------------------------------------------------------#

##
# Directory access exception.
#
class DirectoryError < FatalError
  def initialize(dirname, error_description, sys_call_err = nil)
    message =	"Directory Error: #{error_description} \n" +
                "Directory name: #{dirname} \n"
    super(message, sys_call_error)
  end
end

#----------------------------------------------------------------------------#

class DownloadError < FatalError
  def initialize(resource, addr, port, path, error=nil)
    super("could not download #{resource} from #{addr}/#{path} on #{port}", error)
  end
end

#----------------------------------------------------------------------------#

class UploadError < FatalError
  def initialize(resource, addr, port, path, error=nil)
    super("could not upload #{resource} to #{addr}/#{path} on #{port}", error)
  end
end

#------------------------------------------------------------------------------#

##
# Parameter error.
#
class ParameterError < FatalError
  def initialize(message)
    super(message)
  end
end

#------------------------------------------------------------------------------#

class AMIInvalid < FatalError
  def initialize(message)
    super(message)
  end
end
