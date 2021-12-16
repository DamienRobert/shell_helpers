# vim: foldmethod=marker
require 'open3'
require 'shellwords'

module ShellHelpers
	module Run #{{{
		extend(self)
		RunError=Class.new(StandardError)

		## Trivial wrappers around Open3

		#the run_* commands here capture all the output
		def run_command(*command)
			#stdout, stderr, status
			return Open3.capture3(*command)
		end

		#Only capture output
		def output_of(*command)
			stdout,status = Open3.capture2(*command)
			yield stdout, status if block_given?
			return stdout
		end

		def status_of(*command)
			stdout,stderr,status = run_command(*command)
			yield stdout, stderr, status if block_given?
			return status.success?
			#system(*command)
			#return $?.dup
		end

		#wrap the output of the command in an enumerator
		#allows to lazily parse the result
		def run_lazy(*command)
			r=nil
			IO.popen(command) do |f|
				r=f.each_line.lazy
			end
			r
		end

		## Launching a command
		#handle sudo arguments

		def sudo_args(sudoarg)
			if sudoarg.respond_to?(:sudo_loop)
				sudoarg.sudo_loop
			end
			return [] unless sudoarg
			return sudoarg.shellsplit if sudoarg.is_a?(String)
			["sudo"]
		end

		# get the args, environment and spawning options
		def process_command(*args, pre: nil, post: nil, wrap: nil, **opts)
			spawn_opts={}
			if args.last.kind_of?(Hash)
				#we may have no symbol keywords
				*args,spawn_opts=*args
			end
			sudo=opts.delete(:sudo)
			env={}
			if args.first.kind_of?(Hash)
				env,*args=*args
			end
			env.merge!(opts.delete(:env)||{})
			args=args.map.with_index {|arg, i| i == 0 && arg.is_a?(Array) ? arg : arg.to_s} if args.length > 1
			spawn_opts.merge!(opts)
			if pre
				if args.length > 1
					args=args.unshift(*pre)
				else
				  args=["#{pre.is_a?(Enumerable) ? pre.shelljoin : pre} #{args.first}"]
				end
			end
			if post
				if args.length > 1
					args=args.push(*post)
				else
				  args=["#{args.first} #{post.is_a?(Enumerable) ? post.shelljoin : post}"]
				end
			end
			if wrap
			  args=wrap.call(*args)
			end
			if sudo
				if args.length > 1
					args.unshift(*Run.sudo_args(sudo))
				else
					args=["#{Run.sudo_args(sudo).shelljoin} #{args.first}"]
				end
			end
			return env, args, spawn_opts
		end

		## Run a command
		#by default capture stdout and status
		# callbacks: yield status.success?, out, err, status if block_given?
		#   if status.success? => on_success.call(status, out, err)
		#		else error_mode.call(status, out, error)
		#   rescue ... => fail_mode.call(e)
		# return status, out, error
		def run(*args, output: :capture, error: nil, fail_mode: :error, chomp: false, sudo: false, error_mode: nil, expected: nil, on_success: nil, quiet: nil, **opts)
			env, args, spawn_opts=Run.process_command(*args, sudo: sudo, **opts)

			if args.is_a?(Array)
				if args.length > 1
					launch=args.shelljoin
				else
					launch=args.first #assume it has already been escaped
				end
			else
				launch=args.to_s
			end
			launch+=" 2>/dev/null" if error==:quiet or quiet
			launch+=" >/dev/null" if output==:quiet
			out=err=nil

			begin
				if error==:capture
					out, err, status=Open3.capture3(env, launch, spawn_opts)
				elsif output==:capture
					out, status=Open3.capture2(env, launch, spawn_opts)
				else
					system(env, launch, spawn_opts)
					status=$?
				end
			rescue => e
				status=false
				case fail_mode
				when :error
					raise e
				when :empty
					out=""
				when :nil
					out=nil
				when Proc
					fail_mode.call(e)
				end
			end
			status=ProcessStatus.new(status, expected) if expected
			status_success=status.success? if status.respond_to? :success?
			yield status_success, out, err, status if block_given?
			if status_success
				# this block is called in case of success
				on_success.call(status, out, err) if on_success.is_a?(Proc)
			else # the command failed
				case error_mode
				when :nil
					out=nil
				when :empty
					out=""
				when :error
					raise RunError.new("Error running command '#{launch}': #{status}")
				when Proc
					error_mode.call(status, out, err)
				end
			end
			if chomp and out
				case chomp
				when :line, :lines
					#out is now an array
					out=out.each_line.map {|l| l.chomp}
				else
					out.chomp! 
				end
			end

			# return out, error, status if error
			return status, out, err
		end

		#a simple wrapper for %x//
		#return the output; the block is called in case of an error
		#eg SH.run_simple("echo foo; false") do p "error" end
		#=> returns "foo\n" and prints error
		def run_simple(*command, **opts, &b)
			# here the block is called in case of error
			opts[:error_mode]=b if b
			_status, out, _error = run(*command, **opts)
			return out
		end

		# like run, but only returns status.success?
		def run_success(*command, **opts, &b)
			status, _out, _error = run(*command, **opts, &b)
			status.success?
		end

		#same as Run, but if we get interrupted once, we don't want to launch any more commands
		module Interrupt #{{{
			extend(self)
			@interrupted=false
			def run_command(*args)
				if !@interrupted
					begin
						Run.run_command(*args)
					rescue Interrupt #interruption
						@interrupted=true
						return "", "", false
					end
				else
					return "", "", false
				end
			end

			#TODO: handle non default options, 'error: :capture' would imply we
			#need to return "", "", false
			def run(*command)
				if !@interrupted
					begin
						return Run.run(*command)
					rescue Interrupt #interruption
						@interrupted=true
						return "", false
					end
				else
					return "", false
				end
			end
		end #}}}
	end #}}}

	# ProcessStatus {{{
	# from methadone (process_status.rb; last import v1.3.1-2-g9be3b5a)
	#
	# A wrapper/enhancement of Process::Status that handles coercion and expected
	# nonzero statuses
	class ProcessStatus

		# The exit status, either directly from a Process::Status, from the exit code, or derived from a non-Int value.
		attr_reader :exitstatus, :status

		# Create the ProcessStatus with the given status.
		# respond to success?,exitstatus,status
		#
		# status:: if this responds to #exitstatus, that method is used to extract the exit code.  If it's an Int, that is used as the exit code.  Otherwise, it's truthiness is used: 0 for truthy, 1 for falsey.
		# expected:: an Int or Array of Int representing the expected exit status, other than zero, that represent "success".
		#Ex usage: stdout,stderr,status = DR::Run.run_command(*command,**opts)
		#process_status = DR::ProcessStatus.new(status,expected)
		def initialize(status,expected=nil)
			@status=status
			@exitstatus = derive_exitstatus(status)
			@success = ([0] + Array(expected)).include?(@exitstatus)
		end

		# True if the exit status was a successul (i.e. expected) one.
		def success?
			@success
		end

		private

		def derive_exitstatus(status)
			status = if status.respond_to? :exitstatus
								 status.exitstatus
							 else
								 status
							 end
			if status.kind_of? Integer
				status
			elsif status
				0
			else
				1
			end
		end
	end
	# }}}
end
