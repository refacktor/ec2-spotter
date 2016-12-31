# Copyright 2008-2014 Amazon.com, Inc. or its affiliates.  All Rights
# Reserved.  Licensed under the Amazon Software License (the
# "License").  You may not use this file except in compliance with the
# License. A copy of the License is located at
# http://aws.amazon.com/asl or in the "license" file accompanying this
# file.  This file is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See
# the License for the specific language governing permissions and
# limitations under the License.

require 'monitor'
require 'thread'
require 'syslog'

##
# generate a unique identifier used for filenames
#
def gen_ident()
  (0..19).inject("") {|ident, n| ident+(?A + Kernel.rand(26)).chr}
end

#------------------------------------------------------------------------------#

# A thread local buffer manager. Provide's each thread with a single
# pre-allocated IO buffer. IMPORTANT: as these buffers are indexed in a 
# hashtable they will not be freed until the application closes. If a thread
# needs to free the memory its buffer is using, it must call
# <code>delete_buffer</code> and ensure it has no references to the buffer.
class ThreadLocalBuffer
  POWER = 12      # Log SIZE base 2
  SIZE = 2**POWER # Size of the buffer.
  @@buffers = {}
  @@buffers.extend( MonitorMixin )
  
  #----------------------------------------------------------------------------#
  
  # Return the thread's buffer.
  def ThreadLocalBuffer.get_buffer
    @@buffers.synchronize do
      @@buffers[Thread.current] = new_buffer unless @@buffers.has_key?( Thread.current )
      @@buffers[Thread.current]
    end
  end
  
  #----------------------------------------------------------------------------#
  
  # Delete the threads buffer.
  def delete_buffer buffer
    @@buffers.delete buffer
  end
  
  #----------------------------------------------------------------------------#
  
  def ThreadLocalBuffer.new_buffer
    buffer = String.new
    buffer = Format::hex2bin( '00' )
    POWER.times { buffer << buffer }
    buffer
  end
  
  private_class_method :new_buffer
end

#------------------------------------------------------------------------------#

##
# Base class for XML-RPC structures. Stores key and values pairs. Key names are
# mapped to method names by converting '-' to '_' characters.
#
class XMLRPCStruct < Hash
  # _members_ A list of the structure's key names or nil if any key names
  # are allowed.
  def initialize members
    unless members.kind_of? Array or members.nil?
      raise ArgumentError.new( "invalid members argument" )
    end
    @members = members
  end
  
  # Provide direct access to individual instance elements by methods named after
  # the element's key.
  def method_missing( method_symbol, argument=nil )
    # Here kid, play with this loaded gun...
    method = method_symbol.to_s
    
    # Determine if setter or getter call and remove '=' if setter.
    setter = /[\S]+=/.match(method)
    member = (setter ? method.slice(0, method.size - 1) : method)
    
    # Map method name to member name.
    member = member.gsub('_', '-')
   
    # If valid attribute set or get accordingly. If the member list is nil then
    # any members are allowed.
    if @members.nil? or @members.include?( member )
      if setter
        raise ArgumentError, "value for key #{member} may not be nil" if argument.nil?
        self[member] = argument
      else
        self[member]
      end
    else
      raise NoMethodError.new( method )
    end
  end
end

#------------------------------------------------------------------------------#

##
# Note to self - use log4r next time ;)
#
class Log
  #----------------------------------------------------------------------------#

  # @deprecated use Priority instead
  class Verbosity
    private_class_method :new
    @@levels = Hash.new
    
    def initialize value
      @value = value
      @@levels[value] = self
    end

    V0 = new 0  # Unhandled exceptions only.
    V1 = new 1  # As for 0 but with error messages.
    V2 = new 2  # As for 1 but with informational messages.
    V3 = new 3  # As for 2 but with XML-RPC logging.
    V4 = new 4  # As for 3 but with Xen logging.
    V5 = new 5  # As for 4 but with debugging messages.
    
    attr_accessor :value
        
    def >= operand
      @value >= operand.value
    end
    
    def Verbosity.from_string s
      level = s.to_i
      if not @@levels[level]
        raise ArgumentError.new("invalid logging verbosity level #{level}")
      else
        @@levels[level]
      end
    end
    
    def to_priority
      case self
      when V0
        return Priority::ALERT
      when V1
        return Priority::ERR
      when V2
        return Priority::WARNING
      when V3
        return Priority::NOTICE
      when V4
        return Priority::INFO
      else
        return Priority::DEBUG
      end
    end
  end

  #----------------------------------------------------------------------------#

  class Facility
    private_class_method :new

    def initialize(name)
      @name = name
      @value = (name == "AES")?(12<<3):eval("Syslog::LOG_#{name}")
    end

    AUTHPRIV  = new "AUTHPRIV"
    CRON      = new "CRON"
    DAEMON    = new "DAEMON"
    FTP       = new "FTP"
    KERN      = new "KERN"
    LOCAL0    = new "LOCAL0"
    LOCAL1    = new "LOCAL1"
    LOCAL2    = new "LOCAL2"
    LOCAL3    = new "LOCAL3"
    LOCAL4    = new "LOCAL4"
    LOCAL5    = new "LOCAL5"
    LOCAL6    = new "LOCAL6"
    LOCAL7    = new "LOCAL7"
    LPR       = new "LPR"
    MAIL      = new "MAIL"
    NEWS      = new "NEWS"
    SYSLOG    = new "SYSLOG"
    USER      = new "USER"
    UUCP      = new "UUCP"
    AES       = new "AES"

    attr_accessor :value
    attr_accessor :name
    
    def to_s
      "Facility[LOG_#{@name}]"
    end
  end

  #----------------------------------------------------------------------------#

  class Priority
    include Comparable
    
    private_class_method :new

    def initialize(name)
      @name = name
      @value = eval("Syslog::LOG_#{name}")
    end
    
    EMERG   = new "EMERG"     # 0
    ALERT   = new "ALERT"     # 1
    CRIT    = new "CRIT"      # 2
    ERR     = new "ERR"       # 3
    WARNING = new "WARNING"   # 4
    NOTICE  = new "NOTICE"    # 5
    INFO    = new "INFO"      # 6
    DEBUG   = new "DEBUG"     # 7

    attr_accessor :value
    attr_accessor :name

    def <=>(priority)
      @value <=> priority.value
    end
    
    def to_s
      "Priority[LOG_#{@name}]"
    end
  end

  #----------------------------------------------------------------------------#

  @@facility = Facility::AES
  @@priority = Priority::INFO
  @@identity = nil
  @@streams_mutex = Mutex.new
  @@streams = []

  #----------------------------------------------------------------------------#

  ##
  # Set the verbosity of the logging.
  # @deprecated use set_priority
  def Log.set_verbosity(verbosity)
    set_priority(verbosity.to_priority)
  end
  
  #----------------------------------------------------------------------------#

  ##
  # Set the IO instance to log to.
  # @deprecated use add_stream
  def Log.set_io(io)
    add_stream(io)
  end

  #----------------------------------------------------------------------------#

  ##
  # Log a debug message.
  def Log.debug(msg=nil)
    if block_given?
      write(Priority::DEBUG) {yield}
    else
      write(Priority::DEBUG) {msg}
    end
  end

  #----------------------------------------------------------------------------#

  ##
  # Log a warning message.
  def Log.warn(msg=nil)
    if block_given?
      write(Priority::WARNING) {yield}
    else
      write(Priority::WARNING) {msg}
    end
  end

  #----------------------------------------------------------------------------#

  ##
  # Log an informational message.
  def Log.info(msg=nil)
    if block_given?
      write(Priority::INFO) {yield}
    else
      write(Priority::INFO) {msg}
    end
  end

  #----------------------------------------------------------------------------#

  ##
  # Log an error message.
  def Log.err(msg=nil)
    if block_given?
      write(Priority::ERR) {yield}
    else
      write(Priority::ERR) {msg}
    end
  end

  #----------------------------------------------------------------------------#

  ##
  # Log a warning message.
  def Log.warn(msg=nil)
    if block_given?
      write(Priority::WARNING) {yield}
    else
      write(Priority::WARNING) {msg}
    end
  end

  #----------------------------------------------------------------------------#

  ##
  # Log an unhandled exception.
  # @deprecated use write
  def Log.exception(e)
    if block_given?
      write(Priority::ALERT) {yield}
    else
      write(Priority::ALERT) {Log.exception_str(e)}
    end
  end

  #----------------------------------------------------------------------------#

  ##
  # Log an informational message.
  # @deprecated use write
  def Log.msg(msg)
    write(Verbosity::V2.to_priority) {msg}
  end

  #----------------------------------------------------------------------------#

  # @deprecated use write
  def Log.xen_msg(msg)
    write(Verbosity::V4.to_priority) {msg}
  end

  #----------------------------------------------------------------------------#

  # @deprecated use write
  def Log.xmlrpcmethod_call(name, *paramstructs)
    write(Verbosity::V3.to_priority) {Log.xmlrpcmethod_call_str(name, paramstructs)}
  end

  #----------------------------------------------------------------------------#

  # @deprecated use write
  def Log.xmlrpcmethod_return(name, value)
    write(Verbosity::V3.to_priority) {Log.xmlrpcmethod_return_str(name, value)}
  end
  
  #----------------------------------------------------------------------------#

  # @deprecated use write
  def Log.xmlrpcfault(xmlrpc_method, fault)
    write(Verbosity::V3.to_priority) {Log.xmlrpcfault_str(xmlrpc_method, fault)}
  end
  
  #----------------------------------------------------------------------------#

  ##
  # Add an additional stream (like a file, or $stdout) to send
  # log output to.
  #
  def Log.add_stream(stream)
    @@streams_mutex.synchronize do
      @@streams.push(stream)
      @@streams.delete_if { |io| io.closed? }
    end
  end

  #----------------------------------------------------------------------------#

  def Log.exception_str(e)
    e.message + "\n" + e.backtrace.to_s
  end

  #----------------------------------------------------------------------------#

  def Log.xmlrpcfault_str(xmlrpc_method, fault)
    "XML-RPC method fault\nmethod: #{xmlrpc_method}\nfault code: #{fault.faultCode}\nfault string: #{fault.faultString}"
  end
  
  #----------------------------------------------------------------------------#

  def Log.xmlrpcmethod_call_str(name, *paramstructs)
    msg = "name: #{name}\n"
    paramstructs.each_index { |i| msg += "parameter #{i + 1}: #{paramstructs[i].inspect}\n" }
    "XML-RPC method call\n#{msg}"
  end

  #----------------------------------------------------------------------------#

  def Log.xmlrpcmethod_return_str(name, value)
    msg = "name: #{name}\nvalue: #{value.inspect}"
    "XML-RPC method return\n#{msg}"
  end
  
  #----------------------------------------------------------------------------#

  ##
  # Set the minimum priority of the logging. Messages logged with a
  # lower (less urgent) priority will be ignored.
  #
  def Log.set_priority(priority)
    @@priority = priority
  end

  #----------------------------------------------------------------------------#

  ##
  # Set the facility to log messages against when no explicit facility is
  # provided.
  #
  def Log.set_facility(facility)
    @@facility = facility
  end

  #----------------------------------------------------------------------------#

  ##
  # Set the identity to log messages against when no explicit identity is
  # provided. If no identity is provided (either using this method or explicitly
  # when logging) the system will use the application name as the identity.
  #
  def Log.set_identity(identity)
    @@identity = identity
  end

  #----------------------------------------------------------------------------#

  SYSLOG_OPTS = (Syslog::LOG_PID | Syslog::LOG_CONS)

  #----------------------------------------------------------------------------#
  
  def Log.time
    Time.new.to_s
  end
  
  private_class_method :time

  #----------------------------------------------------------------------------#
  
  def Log.write(priority=Priority::DEBUG, facility=nil, identity=nil)
    # If the priority of this message is below the defined priority
    # for logging then we don't want to do this at all. NOTE: Priorities
    # for syslog are defined in ascending order (so lower priorities
    # are more urgent).
    return unless priority <= @@priority
    return unless block_given?
    
    begin
      facility = (facility == nil)?(@@facility):(facility)
      fac_int = facility.value
      ident = (identity == nil)?(@@identity):(identity)
      msg = yield
      Syslog.open(ident, SYSLOG_OPTS, fac_int) do |log|
        log.log(priority.value, '%s', msg)
      end

      # Now pass the message onto each registered stream
      # Access to our list of streams is synchronized so that it can be changed
      # at runtime.
      @@streams_mutex.synchronize do
        @@streams.each do |stream|
          begin
            stream.puts "#{time}: #{ident}: #{priority.value}: #{msg}"
            stream.flush
          rescue Exception => e
            $stderr.puts 'error writing to stream [#{stream}], logging to stdout'
          end
        end
      end
    rescue Exception => e
      $stderr.puts "error loggin to syslog, logging to stdout: #{e}"
      if block_given?
        begin
          $stdout.puts "Msg: #{msg}"
        rescue Exception => e
          $stderr.puts "Block raised error: #{e}"
        end
	  end
    end
  end
end

#------------------------------------------------------------------------------#

##
# Utilities used for logging (in order for compatability between AESLogger and the previous Log class)

class LogUtils

##
# Prevent instantiation
private_class_method :new

 def LogUtils.exception_str(e)
   e.message + "\n" + e.backtrace.to_s
 end

 def LogUtils.xmlrpcfault_str(xmlrpc_method, fault)
   "XML-RPC method fault : method: #{xmlrpc_method} : fault code: #{fault.faultCode} : fault string: #{fault.faultString}"
 end
  
 def LogUtils.xmlrpcmethod_call_str(name, *paramstructs)
   msg = "name: #{name} : "
   paramstructs.each_index { |i| msg += "parameter #{i + 1}: #{paramstructs[i].inspect} : " }
   "XML-RPC method call\n#{msg}"
 end

 def LogUtils.xmlrpcmethod_return_str(name, value)
   msg = "name: #{name} : value: #{value.inspect}"
    "XML-RPC method return : #{msg}"
 end 
end

