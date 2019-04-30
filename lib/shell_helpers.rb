require 'shell_helpers/version'

require 'fileutils'
#require 'dr/ruby_ext/core_ext'
#load everything in shell_helpers/*.rb
#dir=File.expand_path(File.basename(__FILE__).chomp('.rb'), File.dirname(__FILE__))
#Dir.glob(File.expand_path('*.rb',dir)) do |file|
#	require file
#end
require 'shell_helpers/logger'
require 'shell_helpers/run'
require 'shell_helpers/sh'
require 'shell_helpers/utils'
require 'shell_helpers/sysutils'
require 'shell_helpers/export'
require 'shell_helpers/pathname'

module ShellHelpers
	include Run #run_command, run_output, run_status, run
	include CLILogging #logger.{debug info warn error fatal}, log_and_do
	include ExitNow #exit_now!
	include Sh #sh, sh!
	include Export #export
	include Utils #find, run_pager, rsync...
	include SysUtils #mount, find_devices...

	module LogHelpers
		#activates debug mode
		def debug(level=true)
			#activates logging on Pathname
			Pathname.send(:include, CLILogging)
			logger.cli_level(level, active: Logger::DEBUG)
		end

		def log(*args)
			logger.add(*args)
		end

		# add standard log options to an OptParse instance
		def log_options(opt, recipient)
			opt.on("--[no-]color", "Colorize output", "Default to #{recipient[:color]}") do |v|
				recipient[:color]=v
			end

			opt.on("--debug", "=[level]", "Activate debug informations", "Use `--debug=pry` to launch the pry debugger", "Default to #{recipient[:debug]}") do |v|
				recipient[:debug]=v
			end

			opt.on("--log", "=[level]", "Set log level", "Default to #{recipient[:loglevel]}.") do |v|
				recipient[:loglevel]=v
			end

			opt.on("--[no-]verbose", "-v", "Verbose mode", "Similar to --log=verbose") do |v|
				recipient[:loglevel]=:verbose if v
			end

			opt.on("--vv", "Verbose mode 2", "Similar to --log=verbose2") do |v|
				recipient[:loglevel]=:verbose2 if v
			end

			opt.on("--vvv", "Verbose mode 3", "Similar to --log=verbose3") do |v|
				recipient[:loglevel]=:verbose3 if v
			end

			opt.on("--[no-]quiet", "-q", "Quiet mode", "Similar to --log=warn") do |v|
				recipient[:loglevel]=:warn if v
			end
		end

		def process_log_options(recipient)
			SimpleColor.enabled=recipient[:color] if recipient.key?(:color)
			SH.logger.cli_level(recipient[:loglevel]) if recipient.key?(:loglevel)
			if recipient.key?(:debug)
				debug=recipient[:debug]
				if debug=="pry"
					puts "# Launching pry"
					require 'pry'; binding.pry
				elsif debug
					SH.debug(debug)
				end
			end
		end
	end
	include LogHelpers

	extend self

	#include SH::FU to add FileUtils
	module FU
		include ::FileUtils
		include ::ShellHelpers
		extend self
	end
end

#for the lazy
SH=ShellHelpers
