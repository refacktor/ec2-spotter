# Copyright 2008-2014 Amazon.com, Inc. or its affiliates.  All Rights
# Reserved.  Licensed under the Amazon Software License (the
# "License").  You may not use this file except in compliance with the
# License. A copy of the License is located at
# http://aws.amazon.com/asl or in the "license" file accompanying this
# file.  This file is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See
# the License for the specific language governing permissions and
# limitations under the License.

require 'ec2/amitools/tool_base'
require 'ec2/amitools/bundleparameters'

class BundleTool < AMITool

  def user_override(name, value)
    if interactive?
      instr = interactive_prompt("Please specify a value for #{name} [#{value}]: ", name)
      return instr.strip unless instr.nil? or instr.strip.empty?
    end
    value
  end

  def notify(msg)
    $stdout.puts msg
    if interactive?
      print "Hit enter to continue anyway or Control-C to quit."
      gets
    end
  end

  def get_parameters(params_class)
    params = super(params_class)
    
    if params.arch.nil?
      params.arch = SysChecks::get_system_arch()
      raise "missing or bad uname" if params.arch.nil?
      params.arch = user_override("arch", params.arch)
    end
    
    unless BundleParameters::SUPPORTED_ARCHITECTURES.include?(params.arch)
      unless warn_confirm("Unsupported architecture [#{params.arch}].")
        raise EC2StopExecution.new()
      end
    end
    
    tarcheck = SysChecks::good_tar_version?
    raise "missing or bad tar" if tarcheck.nil?
    unless tarcheck
      unless warn_confirm("Possibly broken tar version found. Please use tar version 1.15 or later.")
        raise EC2StopExecution.new()
      end
    end
    
    params
  end

end
