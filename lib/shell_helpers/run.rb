# vim: foldmethod=marker
require 'open3'
require 'shellwords'

module ShellHelpers
	module Run #{{{
		extend(self)

		def sudo_args(sudoarg)
			return "" unless sudoarg
			return sudoarg if sudoarg.is_a?(String)
			"sudo"
		end

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

		#by default capture stdout and status
		def run(*command, output: :capture, error: nil, fail_mode: :error, chomp: false, sudo: false, status_mode: :nil)
			if command.length > 1
				launch=command.shelljoin
			else
				launch=command.first #assume it has already been escaped
			end
			launch+=" 2>/dev/null" if error==:quiet
			launch+=" >/dev/null" if output==:quiet
			launch="#{sudo_args(sudo)} #{launch}" if sudo

			begin
				if error==:capture
					out, error, status=Open3.capture3(launch)
				elsif output==:capture
					out, status=Open3.capture2(launch)
				else
					system(launch)
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
			if status
				yield out, err, status if block_given?
			else # the command failed
				case status_mode
				when :nil
					out=nil
				when :empty
					out=""
				when :error
					raise "error"
				when Proc
					status_mode.call(out, err, status)
				end
			end
			out.chomp! if chomp and out
			return out, error, status if error
			return out, status
		end

		#a simple wrapper for %x//
		def run_simple(*command, **opts, &b)
			out, *_rest = run(*command, **opts, &b)
			return out
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
