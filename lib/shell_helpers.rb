require 'shell_helpers/version'

require 'shellwords'; require 'pathname'; require 'fileutils'
require 'dr/ruby_ext/core_ext'; require 'dr/ruby_ext/pathname_ext'
#load everything in shell_helpers/*.rb
dir=File.expand_path(File.basename(__FILE__).chomp('.rb'), File.dirname(__FILE__))
Dir.glob(File.expand_path('*.rb',dir)) do |file|
	require file
end

module SH
	include Run #run_command, run_output, run_status, run
	include CLILogging #logger.{debug info warn error fatal}, log_and_do
	include ExitNow #exit_now!
	include Sh #sh, sh!
	include ShellExport #export
	include ShellUtils #find, run_pager
	extend self
	#activates debug mode
	def self.debug(level=Logger::DEBUG)
		#activates logging on Pathname
		Pathname.send(:include, CLILogging)
		logger.level=(level)
	end
	#including SH::FU to add FileUtils
	module FU
		include ::FileUtils
		include ::SH
		extend self
	end
end

