# vim: foldmethod=marker
#from methadone (error.rb, exit_now.rb, process_status.rb, run.rb;
#last import 4626a2bca9b6e54077a06a0f8e11a04fadc6e7ae, 2017-01-19
require 'shell_helpers/logger'
require 'shell_helpers/run'
require 'forwardable'

begin
	require 'simplecolor'
rescue LoadError
	#fallback, don't colorize
	module SimpleColor
		def self.color(s,**opts)
			puts s
		end
	end
end

module ShellHelpers
	# ExitNow {{{
	# Standard exception you can throw to exit with a given status code.
	# Generally, you should prefer SH::ExitNow.exit_now! over using this
	# directly, however you may wish to create a rich hierarchy of exceptions
	# that extend from this in your app, so this is provided if you wish to
	# do so.
	class ExitError < StandardError
		attr_reader :exit_code
		# Create an Error with the given status code and message
		def initialize(exit_code,message=nil)
			super(message)
			@exit_code = exit_code
		end
	end

	# Provides #exit_now! You might mix this into your business logic classes
	# if they will need to exit the program with a human-readable error
	# message.
	module ExitNow
		# Call this to exit the program immediately
		# with the given error code and message.
		# +exit_code+:: exit status you'd like to exit with
		# +message+:: message to display to the user explaining the problem
		# If +exit_code+ is a String and +message+ is omitted, +exit_code+ will
		# === Examples
		#			exit_now!(4,"Oh noes!")
		#				# => exit app with status 4 and show the user "Oh noes!" on stderr
		#			exit_now!("Oh noes!")
		#				# => exit app with status 1 and show the user "Oh noes!" on stderr
		#			exit_now!(4)
		#				# => exit app with status 4 and dont' give the user a message (how rude of you)
		def exit_now!(exit_code,message=nil)
			if exit_code.kind_of?(String) && message.nil?
				raise ExitError.new(1,exit_code)
			else
				raise ExitError.new(exit_code,message)
			end
		end
	end
	# }}}
	
	# SudoLoop {{{
	# extend SudoLoop.configure to run a sudo loop
	# SH.sh("ls /", sudo: "sudo".extend(SH::SudoLoop.configure(**opts))
	module SudoLoop
		extend self
		def configure(**opts)
			return Module.new do |m|
				m.define_method(:sudo_loop) do
					SudoLoop.instance_method(:run_sudo_loop).bind(self).call(**opts)
				end
				m.define_method(:stop_sudo_loop) do
					SudoLoop.instance_method(:stop_sudo_loop).bind(self).call
				end
			end
		end

		def run_sudo_loop(command: "sudo -v", interval: 30, init_command: command)
			if @sudo_loop_thread.nil? or !@sudo_loop_thread.alive?
				Sh.sh_or_proc(init_command, log: false)
				#require 'pry'; binding.pry
				@sudo_loop_thread = Thread.new do
					loop do
						Sh.sh_or_proc(command, log: false)
						sleep(interval)
					end
				end
				@sudo_loop_thread.run
			end
		end

		def stop_sudo_loop
			@sudo_loop_thread&.kill
		end
	end #}}}

	# Sh {{{
	# Module with various helper methods for executing external commands.
	# In most cases, you can use #sh to run commands and have decent logging
	# done.
	# == Examples
	#
	#		 extend SH::Sh
	#
	#		 sh 'cp foo.txt /tmp'
	#		 # => logs the command to DEBUG, executes the command, logs its output to DEBUG and its error output to WARN, returns 0
	#
	#		 sh 'cp non_existent_file.txt /nowhere_good'
	#		 # => logs the command to DEBUG, executes the command, logs its output to INFO and its error output to WARN, returns the nonzero exit status of the underlying command
	#
	#		 sh! 'cp non_existent_file.txt /nowhere_good'
	#		 # => same as above, EXCEPT, raises a Methadone::FailedCommandError
	#
	#		 sh 'cp foo.txt /tmp' do
	#			 # Behaves exactly as before, but this block is called after
	#		 end
	#
	#		 sh 'cp non_existent_file.txt /nowhere_good' do
	#			 # This block isn't called, since the command failed
	#		 end
	#
	#		 sh 'ls -l /tmp/', capture: true do |status, stdout|
	#			 # stdout contains the output of the command
	#		 end
	#		 sh 'ls -l /tmp/ /non_existent_dir', capture: true do |status, stdout,stderr|
	#			 # stdout contains the output of the command,
	#			 # stderr contains the standard error output.
	#			end

	# FailedCommandError {{{
	# Thrown by certain methods when an externally-called command exits nonzero
	class FailedCommandError < StandardError
		# The command that caused the failure
		attr_reader :command
		# exit_code:: exit code of the command that caused this
		# command:: the entire command-line that caused this
		# custom_error_message:: an error message to show the user instead of
		# the boilerplate one.	Useful for allowing this exception to bubble up
		# and exit the program, but to give the user something actionable.
		def initialize(exit_code,command,failure_msg: nil)
			error_message = String(failure_msg).empty? ?	"Command '#{command}' exited #{exit_code}" : failure_msg
			super(error_message)
			@command = command
		end
	end
	# }}}

	ShError=Class.new(StandardError)
	module Sh
		include CLILogging
		extend self
		attr_writer :default_sh_options
		def default_sh_options
			@default_sh_options||={log: true, capture: false, on_success: nil, on_error: nil, expected:0, dryrun: false, escape: false,
			log_level_execute_debug: :debug,
			log_level_execute: :info, log_level_error: :error,
			log_level_stderr: :error, log_level_stdout_success: :info,
			log_level_stdout_fail: :warn, detach: false,
			mode: :system}
		end

		attr_writer :spawned
		def spawned
			@spawned||=[]
		end
		def wait_spawned
			spawned.each {|c| Process.waitpid(c)}
		end

		# callback called by sh to select the exec mode
		# mode: :system,:spawn,:exec,:capture
		# opts: sudo, env
		def shrun(*args,mode: :system, block: nil, **opts)
			env, args, spawn_opts=Run.process_command(*args, **opts)
			# p env, args, spawn_opts
			case mode
			when :system
				system(env,*args,spawn_opts)
			when :spawn, :detach
				pid=spawn(env,*args,spawn_opts, &block)
				if mode==:detach
					Process.detach(pid) 
				else
					spawned << pid
					if block_given?
						yield pid
						Process.wait(pid)
					else
						pid
					end
				end
			when :exec
				exec(env,*args,spawn_opts, &block)
			when :capture
				Run.run_command(env,*args,spawn_opts, &block)
			when :run
				Run.run(env,*args,spawn_opts, &block)
			else
				raise ShError.new("In shrun, mode #{mode} not understood")
			end
		end

		# Run a shell command, capturing and logging its output.
		# keywords:: log+capture
		# If the command completed successfully, it's output is logged at DEBUG.
		# If not, its output is logged at INFO.  In either case, its
		# error output is logged at WARN.
		#						+:expected+:: an Int or Array of Int representing error codes, <b>in addition to 0</b>, that are expected and therefore constitute success.  Useful for commands that don't use exit codes the way you'd like
		#			name: pretty name of command
		#			on_success,on_error: blocks to call on success/failure
		# block:: if provided, will be called if the command exited nonzero.	The block may take 0, 1, 2, or 3 arguments.
		#					The arguments provided are the standard output as a string, standard error as a string, and the processstatus as SH::ProcessStatus
		#					You should be safe to pass in a lambda instead of a block, as long as your lambda doesn't take more than three arguments
		#
		# Example
		#			sh "cp foo /tmp"
		#			sh "ls /tmp" do |stdout|
		#				# stdout contains the output of ls /tmp
		#			end
		#			sh "ls -l /tmp foobar" do |stdout,stderr|
		#				# ...
		#			end
		#
		# Returns the exit status of the command (Note that if the command doesn't exist, this returns 127.), stdout, stderr and the full status of the command

		# callbacks: on_success, on_error
		# yield process_status.success?,stdout,stderr,process_status if block_given?
		# returns success; except in capture mode where it returns success,
		# stdout, stderr, process_status
		def sh(*command, argv0: nil, **opts)
			defaults=default_sh_options
			curopts=defaults.dup
			defaults.keys.each do |k|
				v=opts.delete(k)
				curopts[k]=v unless v.nil?
			end

			log=curopts[:log]
			command=[[command.first, argv0], *command[1..-1]] if argv0 and command.length > 1 and !curopts[:escape]

			if command.length==1 and command.first.kind_of?(Array) #so that sh(["ls", "-a"]) works
				command=command.first
				command=[[command.first, argv0], *command[1..-1]] if argv0 and !curopts[:escape]
			end
			command_name = curopts[:name] || command_name(command) #this keep the options
			# this should not be needed
			command=command.shelljoin if curopts[:escape]

			if log
				sh_logger.send(curopts[:log_level_execute], SimpleColor.color("Executing '#{command_name}'",:bold))
				p_env, p_args, p_opts= Run.process_command(*command, **opts)
				sh_logger.send(curopts[:log_level_execute_debug], SimpleColor.color("Debug execute: #{[p_env, *p_args, p_opts]}", :bold))
			end

			if !curopts[:dryrun]
				if curopts[:capture] || curopts[:mode]==:capture
					stdout,stderr,status = shrun(*command,**opts,mode: :capture)
				elsif curopts[:detach] || curopts[:mode]==:spawn || curopts[:mode]==:detach
					mode = curopts[:detach] ? :detach : curops[:mode]
					_pid = shrun(*command,**opts, mode: mode)
					status=0; stdout=nil; stderr=nil
				elsif curopts[:mode]==:run
					status, stdout, stderr=shrun(*command,mode: curopts[:mode], **opts)
				else
					mode = curopts[:mode] || :system
					shrun(*command,mode: mode, **opts)
					status=$?; stdout=nil; stderr=nil
				end
			else
				sh_logger.info command.to_s
				status=0; stdout=nil; stderr=nil
			end
			process_status = ProcessStatus.new(status,curopts[:expected])

			sh_logger.send(curopts[:log_level_stderr], SimpleColor.color("stderr output of '#{command_name}':\n",:bold,:red)+stderr) unless stderr.nil? or stderr.strip.length == 0 or !log
			if process_status.success?
				sh_logger.send(curopts[:log_level_stdout_success], SimpleColor.color("stdout output of '#{command_name}':\n",:bold,:green)+stdout) unless stdout.nil? or stdout.strip.length == 0 or !log
				curopts[:on_success].call(stdout,stderr,process_status) unless curopts[:on_success].nil?
				# block.call(stdout,stderr,process_status) unless block.nil?
			else
				sh_logger.send(curopts[:log_level_stdout_fail], SimpleColor.color("stdout output of '#{command_name}':\n",:bold,:yellow)+stdout) unless stdout.nil? or stdout.strip.length == 0 or !log
				sh_logger.send(curopts[:log_level_error], SimpleColor.color("Error running '#{command_name}': #{process_status.status}",:red,:bold)) if log
				curopts[:on_error].call(stdout,stderr,process_status) unless curopts[:on_error].nil?
			end
			yield process_status.success?,stdout,stderr,process_status if block_given?
			if curopts[:capture] || curopts[:mode]==:capture || curopts[:mode]==:run
				return process_status.success?,stdout,stderr,process_status
			else
				return process_status.success?
			end

		rescue SystemCallError => ex
			sh_logger.send(curopts[:log_level_error], SimpleColor.color("Error running '#{command_name}': #{ex.message}",:red,:bold)) if log
			if block_given?
				yield 127, nil, nil, nil
			else
				return 127, nil, nil, nil
			end
		end

		# Run a command, throwing an exception if the command exited nonzero.
		# Otherwise, behaves exactly like #sh.
		# Raises SH::FailedCommandError if the command exited nonzero.
		# Examples:
		#
		#			sh!("rsync foo bar")
		#			# => if command fails, app exits and user sees: "error: Command 'rsync foo bar' exited 12"
		#			sh!("rsync foo bar", :failure_msg => "Couldn't rsync, check log for details")
		#			# => if command fails, app exits and user sees: "error: Couldn't rsync, check log for details
		def sh!(*args,failure_msg: nil,**opts, &block)
			on_error=Proc.new do |*blockargs|
				process_status=blockargs.last
				raise FailedCommandError.new(process_status.exitstatus,command_name(args),failure_msg: failure_msg)
			end
			sh(*args,**opts,on_error: on_error,&block)
		end

		# Override the default logger (which is the one provided by CLILogging).
		# You would do this if you want a custom logger or you aren't mixing-in
		# CLILogging.
		#
		# Note that this method is *not* called <tt>sh_logger=</tt> to avoid annoying situations
		# where Ruby thinks you are setting a local variable
		def change_sh_logger(logger)
			@sh_logger = logger
		end

		#split commands on newlines and run sh on each line
		def sh_commands(com, **opts)
			com.each_line do |line|
				sh(line.chomp,**opts)
			end
		end

		# returns only the success or failure
		def sh_or_proc(cmd, *args, **opts, &b)
			case cmd
			when Proc
				cmd.call(*args, **opts, &b)
			when Array
				suc, _r=SH.sh(*cmd, *args, **opts, &b)
				suc
			when String
				suc, _r=SH.sh(cmd + " #{args.shelljoin}", **opts, &b)
				suc
			end
		end

	private
		def command_name(command)
			if command.size == 1
				command.first.to_s
			else
				#command.to_s
				#command.map {|i| i.to_s}.to_s
				command.shelljoin
			end
		end

		def sh_logger
			@sh_logger ||= begin
				raise StandardError, "No logger set! Please include SH::CLILogging
ng or provide your own via #change_sh_logger." unless self.respond_to?(:logger)
				self.logger
			end
		end

	end

	#SH::ShLog.sh is by default like SH::Sh.sh.
	# It is easy to change it to be more verbose though
	module ShLog
		include Sh
		extend self
		@default_sh_options=default_sh_options
		@default_sh_options[:log]=true
		@default_sh_options[:log_level_execute]=:info
	end

	# Do not log execution
	module ShQuiet
		include Sh
		extend self
		@default_sh_options=default_sh_options
		@default_sh_options[:log]=true
		@default_sh_options[:log_level_execute]=:debug
	end

	# Completely silent
	module ShSilent
		include Sh
		extend self
		@default_sh_options=default_sh_options
		@default_sh_options[:log]=false
	end

	module ShDryRun
		include Sh
		extend self
		@default_sh_options=default_sh_options
		@default_sh_options[:log]=true
		@default_sh_options[:log_level_execute]=:info
		@default_sh_options[:dryrun]=true
	end

	# this modules deal with default options, paths and arg handling for
	# different programs, while letting the user control
	# Exemples:
	# ShConfig.launch(:ls, "/", config: {ls: {default_opts: ["-l"]}})
	# => ["ls", "-l", "/", {}]
	# ShConfig.launch(:ls, "/", config: {ls: {default_opts: ["-l"]}}, method: :sh)
	# ShConfig.launch(:ls, "/", config: {ls: {default_opts: ["-l"]}}) { |*args| SH.sh(*args) }
	# ShConfig.launch(:ls, "/", config: {ls: {wrap: ->(cmd,*args, &b) { b.call(cmd, '-l', *args) } }}, method: :sh)

	module ShConfig
		extend self
		def launch(*args, opts: [], cmd_prepend: [], cmd_postpone: [], config: self.sh_config, default_opts: true, method: nil, **keywords, &b)
			if args.length == 1 and (arg=args.first).is_a?(String)
				args=arg.shellsplit
				args[0]=args[0][1..-1].to_sym if args[0][0]==':'
			end
			opts=opts.shellsplit if opts.is_a?(String)
			default_opts=default_opts.shellsplit if default_opts.is_a?(String)
			cmd_prepend=cmd_prepend.shellsplit if cmd_prepend.is_a?(String)
			cmd_postpone=cmd_postpone.shellsplit if cmd_postpone.is_a?(String)
			dopts = default_opts.is_a?(Array) ? default_opts : []
			cmd, *args=args
			if cmd.is_a?(Symbol)
				if config.key?(cmd)
					c=config[cmd]
					cmd=c[:bin] || cmd.to_s
					dopts += (Array(c[:default_opts])||[]) if default_opts
					wrap=c[:wrap]
				else
					cmd=cmd.to_s
				end
			end
			cargs=Array(cmd_prepend) + [cmd] + dopts + Array(opts) + args + Array(cmd_postpone)
			if !b
				if method
					b=lambda do |*args, **kw|
						SH.public_send(method, *args, **kw)
					end
				else
					b=lambda do |*args|
						return *args
					end
				end
			end
			if wrap
				wrap.call(*cargs, **keywords, &b)
			else
				b.call(*cargs, **keywords)
			end
		end

		def sh_config
			{}
		end
	end
	# }}}
end
