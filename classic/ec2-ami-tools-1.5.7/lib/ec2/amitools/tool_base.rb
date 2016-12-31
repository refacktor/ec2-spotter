# Copyright 2008-2014 Amazon.com, Inc. or its affiliates.  All Rights
# Reserved.  Licensed under the Amazon Software License (the
# "License").  You may not use this file except in compliance with the
# License. A copy of the License is located at
# http://aws.amazon.com/asl or in the "license" file accompanying this
# file.  This file is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See
# the License for the specific language governing permissions and
# limitations under the License.

module AMIToolExceptions
  # All fatal errors should inherit from this.
  class EC2FatalError < RuntimeError
    attr_accessor :code
    def initialize(code, msg)
      super(msg)
      @code = code
    end
  end

  class FileNotFound < EC2FatalError
    def initialize(path)
      super(2, "File not found: #{path}")
    end
  end

  class S3Error < EC2FatalError
    def initialize(msg)
      super(3, "Error talking to S3: #{msg}")
    end
  end

  class PromptTimeout < EC2FatalError
    def initialize(msg=nil)
      message = "Timed out waiting for user input"
      message += ": #{msg}" unless msg.nil?
      super(5, message)
    end
  end

  # This is more for flow control than anything else.
  # Raising it should terminate execution, but not print an error.
  class EC2StopExecution < RuntimeError
    attr_accessor :code
    def initialize(code=0)
      super()
      @code = code
    end
  end

  class TryFailed < RuntimeError
  end

end

class AMITool

  include AMIToolExceptions

  PROMPT_TIMEOUT = 30
  MAX_TRIES = 5
  BACKOFF_PERIOD = 5

  #------------------------------------------------------------------------------#
  # Methods to override in subclasses
  #------------------------------------------------------------------------------#

  def get_manual()
    # We have to get the manual text into here.
    raise "NotImplemented: get_manual()"
  end

  def get_name()
    # We have to get the tool name into here.
    raise "NotImplemented: get_name()"
  end

  def main(params)
    # Main entry point.
    raise "NotImplemented: main()"
  end

  #------------------------------------------------------------------------------#
  # Utility methods
  #------------------------------------------------------------------------------#

  # Display a message (without appending a newline) and ask for a response.
  # Returns user response or nil if interactivity is not desired.
  # Raises exception on timeout.
  def interactive_prompt(message, name=nil)
    return nil unless interactive?
    begin
      $stdout.print(message)
      $stdout.flush
      Timeout::timeout(PROMPT_TIMEOUT) do
        return gets
      end
    rescue Timeout::Error
      raise PromptTimeout.new(name)
    end
  end

  #------------------------------------------------------------------------------#

  # Display a message on stderr.
  # If interactive, asks for confirmation (yes/no).
  # Returns true if in batch mode or user agrees, false if user disagrees.
  # Raises exception on timeout.
  def warn_confirm(message)
    $stderr.puts(message)
    $stderr.flush
    return true unless interactive?
    response = interactive_prompt("Are you sure you want to continue? [y/N]")
    if response =~ /^[Yy]/
      return true
    end
    return false
  end

  #----------------------------------------------------------------------------#

  def retry_s3(retrying=true)
    tries = 0
    while true
      tries += 1
      begin
        result = yield
        return result
      rescue TryFailed => e
        $stderr.puts e.message
        if retrying and tries < MAX_TRIES
          $stdout.puts "Retrying in #{BACKOFF_PERIOD}s ..."
        else
          raise EC2FatalError.new(3, e.message)
        end
      end
    end
  end

  #------------------------------------------------------------------------------#
  # Standard behaviour
  #------------------------------------------------------------------------------#

  def handle_early_exit_parameters(params)
    if params.version
      puts get_name() + " " + params.version_copyright_string()
      return
    end
    
    if params.show_help
      puts params.help
      return
    end
    
    if params.manual
      puts get_manual()
      return
    end
  end

  #------------------------------------------------------------------------------#

  def interactive?
    @interactive
  end

  #------------------------------------------------------------------------------#

  def get_parameters(params_class)
    # Parse the parameters and die on errors.
    # Assume that if we're parsing parameters, it's safe to exit.
    begin
      params = params_class.new(ARGV)
    rescue StandardError => e
      $stderr.puts e.message
      $stderr.puts "Try '#{get_name} --help'"
      exit 1
    end
    
    # Deal with help, verion, etc.
    if params.early_exit?
      handle_early_exit_parameters(params)
      exit 0
    end
    
    # Some general flags that we want to set
    @debug = params.debug
    @interactive = params.interactive?
    
    # Finally, return the leftovers.
    params
  end

  #------------------------------------------------------------------------------#

  def run(params_class)
    # We want to be able to reuse bits without having to parse
    # parameters, so run() is not called from the constructor.
    begin
      params = get_parameters(params_class)
      main(params)
    rescue AMIToolExceptions::EC2StopExecution => e
      # We've been asked to stop.
      exit e.code
    rescue AMIToolExceptions::PromptTimeout => e
      $stderr.puts e.message
      exit e.code
    rescue AMIToolExceptions::EC2FatalError => e
      $stderr.puts "ERROR: #{e.message}"
      puts e.backtrace if @debug
      exit e.code
    rescue Interrupt => e
      $stderr.puts "\n#{get_name} interrupted."
      puts e.backtrace if @debug
      exit 255
    rescue => e
      $stderr.puts "ERROR: #{e.message}"
      puts e.inspect if @debug
      puts e.backtrace if @debug
      exit 254
    end
  end

end
