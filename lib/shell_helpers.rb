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
	extend self
	#activates debug mode
	def self.debug(level=Logger::DEBUG)
		#activates logging on Pathname
		Pathname.send(:include, CLILogging)
		logger.level=(level)
	end
	#include SH::FU to add FileUtils
	module FU
		include ::FileUtils
		include ::ShellHelpers
		extend self
	end
	def log(*args)
		logger.add(*args)
	end

	# #include LogHelper to set up CLILogging with some convenience facilities
	# module LogHelper
	# 	include CLILogging
	# 	CLILogging.logger.progname||=$0
	# 	# #Activates Sh.sh in klass
	# 	# def self.included(klass)
	# 	# 	klass.const_set(:Sh,ShellHelpers::Sh)
	# 	# end
	# end
end

#for the lazy
SH=ShellHelpers

## # SHLog.sh to get logging
## module SHLog
## 	include ShellHelpers
## 	include ShellHelpers::ShLog
## end

