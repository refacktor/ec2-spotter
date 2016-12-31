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
require 'English'
require 'fileutils'
require 'tempfile'

#------------------------------------------------------------------------------
module EC2    
  #----------------------------------------------------------------------------
  module Platform
    #--------------------------------------------------------------------------
    module Base
      #------------------------------------------------------------------------    
      class Pipeline
        #----------------------------------------------------------------------
        class ExecutionError < RuntimeError
          def initialize(pipeline=nil, stage=nil, message=nil)
            word = 'Execution failed'
            word << ", pipeline: #{pipeline}" unless pipeline.nil?
            word << ", stage: #{stage}" unless stage.nil?
            word << ', mesage:' + message.to_s unless message.nil?
            word << '.'
            super word
          end
        end
        #----------------------------------------------------------------------
        class Stage
          class Result
            attr :name
            attr :rc
            attr :successful
            def initialize(name, rc, successful)
              @name = name
              @rc = rc
              @successful = successful
            end
            def successful?
              @successful
            end
            def to_s
              "Result(name=#{@name}, rc=#{@rc}, successful=#{@successful})"
            end
          end
          
          attr :name
          attr :command
          attr :success
    
          def initialize(name, command, success=0)
            @name = name
            @command = command
            @success = success
          end
          def to_s()
            "Stage(name=#{@name}, command=#{@command}, success=#{@success})"
          end
        end
        attr_accessor :verbose
        attr_reader :basename
        
        #----------------------------------------------------------------------
        def initialize(basename='pipeline', is_verbose=false)
          @stages = []
          @results = []
          @tempfiles = []
          @basename = basename
          @verbose = is_verbose
        end
    
        #----------------------------------------------------------------------
        def add(name, command, success=0)
          @stages << Stage.new(name, command, success)
          self
        end
  
        #----------------------------------------------------------------------
        def concat(arr)
          if arr.is_a? Array
            arr.each do |e|
              self.add(e[0], e[1], e[2] || 0)
            end
          end
          self
        end
        
        #----------------------------------------------------------------------
        # Given a pipeline of commands, modify it so that we can obtain
        # the exit status of each pipeline stage by reading the tempfile
        # associated with that stage. Must be implemented by subclasses
        def pipestatus(cmd)
          raise 'unimplemented method'
        end
        
        #----------------------------------------------------------------------
        def command
          # Create the pipeline incantation
          pipeline = @stages.map { |s| s.command }.join(' | ') + '; '
          
          # Fudge pipeline incantation to make return codes for each
          # stage accessible from the associated pipeline stage
          pipestatus(pipeline)
        end
        
        #----------------------------------------------------------------------
        def execute()
          @results = []
          create_tempfiles
          escaped_command = command.gsub("'","'\"'\"'")
          invocation = "/bin/bash -c '#{escaped_command}'"
          
          # Execute the pipeline invocation
          STDERR.puts("Pipeline.execute: command = [#{invocation}]") if verbose
          output = `#{invocation}`
          STDERR.puts("Pipeline.execute: output = [#{output.strip}]") if verbose
    
          unless $CHILD_STATUS.success?
            raise ExecutionError.new(@basename)
          end
    
          # Collect the pipeline's exit codes and see if they're good
          successful = true
          offender = nil
          @results = @tempfiles.zip(@stages).map do |file, stage|
            file.open()
            status = file.read().strip.to_i
            file.close(false)
            success = (stage.success == status)
            successful &&= success
            offender = stage.name unless successful
            Stage::Result.new(stage.name, status, success)
          end
          unless successful
            raise ExecutionError.new(@basename, offender)
          end
          output
        end
    
        #----------------------------------------------------------------------
        def cleanup
          @tempfiles.each do |file| 
            file.close(true) if file.is_a? Tempfile
            FileUtils.rm_f(file.path) if File.exist?(file.path)
          end
        end
        
        #----------------------------------------------------------------------
        def errors
          @results.reject { |r| r.success }
        end
    
        #----------------------------------------------------------------------
        def create_tempfiles
          @tempfiles = (0...@stages.length).map do |index|
            file = Tempfile.new("#{@basename}-pipestatus-#{index}")
            file.close(false)
            file
          end
          unless @tempfiles.length == @stages.length
            raise ExecutionError.new(
              @basename, nil,
              "Temp files count(#{@tempfiles.length}) != stages count(#{@stages.length})")
          end
        end
        
        #----------------------------------------------------------------------
        def to_s
          "Pipeline(stages=[#{@stages.join(', ')}], results=[#{@results.join(', ')}])"
        end
      end
    end
  end
end
