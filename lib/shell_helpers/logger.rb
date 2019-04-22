# vim: foldmethod=marker
#From methadone (cli_logger.rb, cli_logging.rb, last import: 4626a2bca9b6e54077a06a0f8e11a04fadc6e7ae; 2017-01-19)
require 'logger'
require 'simplecolor'

module ShellHelpers
	# like Logger but with more levels
	class MoreLogger < Logger

		DEBUG1=0 #=DEBUG
		DEBUG2=-0.1
		DEBUG3=-0.2
		IMPORTANT=1.5 #between warning and info
		SUCCESS=1.3 #between warning and info
		VERBOSE=0.9
		VERBOSE1=0.9
		VERBOSE2=0.8
		VERBOSE3=0.7
		QUIET=-9
		#note Logger::Severity is included into Logger, so we can access the severity levels directly
		LOG_LEVELS=
			{
				'quiet' => QUIET,
				'debug3' => DEBUG3,
				'debug2' => DEBUG2,
				'debug1' => DEBUG1,
				'debug' => Logger::DEBUG, #0
				'verbose' => VERBOSE,
				'verbose1' => VERBOSE1,
				'verbose2' => VERBOSE2,
				'verbose3' => VERBOSE3,
				'info' => Logger::INFO, #1
				'success' => SUCCESS,
				'important' => IMPORTANT,
				'warn' => Logger::WARN, #2
				'error' => Logger::ERROR, #3
				'fatal' => Logger::FATAL, #4
				'unknown' => Logger::UNKNOWN, #5
			}

		def log_levels
			LOG_LEVELS
		end

		LOG_LEVELS.each do |lvl, cst|
			unless ['debug', 'info', 'warn', 'fatal'].include?(lvl)
				define_method(lvl.to_sym) do |progname=nil, &block|
					add(cst, nil, progname, &block)
				end
				define_method("#{lvl}?".to_sym) do
					@level <= cst
				end
			end
		end

		def color_add(severity, message = nil, progname = nil, color: black)
			severity ||= UNKNOWN
			if @logdev.nil? or severity < @level
				return true
			end
			if progname.nil?
				progname = @progname
			end
			if message.nil?
				if block_given?
					message = yield
				else
					message = progname
					progname = @progname
				end
			end
			message=message.to_s
			message = SimpleColor.color(message, *color) unless SimpleColor.color?(message)
			add(severity, message, progname)
		end
		{success: :green, important: :blue, warn: :yellow,
	 error: :red, fatal: :red}.each do |lvl, base_color|
			define_method("color_#{lvl}".to_sym) do |progname=nil, color: [], &block|
				color_add(LOG_LEVELS[lvl.to_s], nil, progname, color: [*base_color, *color], &block)
			end
		end

		private def severity_to_level(severity, default: INFO)
			severity = default if severity == true
			if severity.is_a?(Integer) or severity.is_a?(Float)
				return severity
			else
				return LOG_LEVELS[severity.to_s.downcase]
			end
		end

		def level=(severity)
			lvl = severity_to_level(severity)
			if lvl
				@level = lvl
			else
				raise ArgumentError, "invalid log level: #{severity}"
			end
		end

		# like level= but for clis, so we can pass a default if level=true
		def cli_level(level, default: Logger::INFO)
			level=default if level==true #for cli
			self.level=level
		end

		# log with given security. Also accepts 'true'
		def add(severity, message = nil, progname = nil, &block)
			super(severity_to_level(severity),message,progname,&block)
		end

	end
	# CLILogger {{{
	# A Logger instance that gives better control of messaging the user and
	# logging app activity.  At it's most basic, you would use <tt>info</tt>
	# as a replacement for +puts+ and <tt>error</tt> as a replacement for
	# <tt>STDERR.puts</tt>.  Since this is a logger, however, you can also
	# use #debug, #warn, and #fatal, and you can control the format and
	# "logging level" as such.
	#
	# So, by default:
	# * debug messages do not appear anywhere
	# * info messages appear on the standard output
	# * warn, error, and fatal message appear on the standard error
	# * The default format of messages is simply the message, no logging
	# cruft, however if your output is redirected to a file, a better
	# timestamped logging format is used
	#
	# You can customize this in several ways:
	# * You can override the devices used by passing different devices to the constructor
	# * You can adjust the level of message that goes to the error logger via error_level=
	# * You can adjust the format for messages to the error logger separately via error_formatter=
	#
	# === Example
	#
	#			logger = CLILogger.new
	#			logger.debug("Starting up") # => only the standard output gets this
	#			logger.warn("careful!") # => only the standard error gets this
	#			logger.error("Something went wrong!") # => only the standard error gets this
	#
	#			logger = CLILogger.new
	#			logger.error_level = Logger::ERROR
	#			logger.debug("Starting up") # => only the standard output gets this
	#			logger.warn("careful!") # => only the standard OUTPUT gets this
	#			logger.error("Something went wrong!") # => only the standard error gets this
	#
	#			logger = CLILogger.new('logfile.txt')
	#			logger.debug("Starting up") #=> logfile.txt gets this
	#			logger.error("Something went wrong!") # => BOTH logfile.txt AND the standard error get this
	class CLILogger < MoreLogger
		BLANK_FORMAT = lambda { |severity,datetime,progname,msg|
			msg + "\n"
		}

		# Helper to proxy methods to the super class AND to the internal error logger
		# +symbol+:: Symbol for name of the method to proxy
		def self.proxy_method(symbol) #:nodoc:
			old_name = "old_#{symbol}".to_sym
			alias_method old_name,symbol
			define_method symbol do |*args,&block|
				send(old_name,*args,&block)
				@stderr_logger.send(symbol,*args,&block)
			end
		end

		proxy_method :'formatter='
		proxy_method :'progname='
		proxy_method :'datetime_format='

		def add(severity, message = nil, progname = nil, &block) #:nodoc:
			severity = severity_to_level(severity)
			if @split_logs
				unless severity >= @stderr_logger.level
					super(severity,message,progname,&block)
				end
			else
				super(severity,message,progname,&block)
			end
			@stderr_logger.add(severity,message,progname,&block)
		end

		DEFAULT_ERROR_LEVEL = Logger::Severity::WARN

		# A logger that logs error-type messages to a second device; useful for
		# ensuring that error messages go to standard error.	This should be
		# pretty smart about doing the right thing.  If both log devices are
		# ttys, e.g. one is going to standard error and the other to the
		# standard output, messages only appear once in the overall output
		# stream.  In other words, an ERROR logged will show up *only* in the
		# standard error.  If either log device is NOT a tty, then all messages
		# go to +log_device+ and only errors go to +error_device+
		#
		# +log_device+:: device where all log messages should go, based on level
		# By default, this is Logger::Severity::WARN
		# +error_device+:: device where all error messages should go.
		def initialize(log_device=$stdout,error_device=$stderr,
									 split_log: :auto)
			@stderr_logger = MoreLogger.new(error_device)

			super(log_device)

			log_device_tty	 = tty?(log_device)
			error_device_tty = tty?(error_device)

			@split_logs = log_device_tty && error_device_tty if split_log==:auto

			self.level = Logger::Severity::INFO
			@stderr_logger.level = DEFAULT_ERROR_LEVEL

			self.formatter = BLANK_FORMAT if log_device_tty
			@stderr_logger.formatter = BLANK_FORMAT if error_device_tty
		end

		def level=(level)
			super
			#current_error_level = @stderr_logger.level
			if (self.level > DEFAULT_ERROR_LEVEL) && @split_logs
				@stderr_logger.level = self.level
			end
		end

		def cli_level(level, default: Logger::INFO)
			super
			if (self.level > DEFAULT_ERROR_LEVEL) && @split_logs
				@stderr_logger.level = self.level
			end
		end

		# Set the threshold for what messages go to the error device.  Note
		# that calling #level= will *not* affect the error logger *unless* both
		# devices are TTYs.
		# +level+:: a constant from Logger::Severity for the level of messages that should go to the error logger
		def error_level=(level)
			@stderr_logger.level = level
		end

		# Overrides the formatter for the error logger.  A future call to
		# #formatter= will affect both, so the order of the calls matters.
		# +formatter+:: Proc that handles the formatting, the same as for #formatter=
		def error_formatter=(formatter)
			@stderr_logger.formatter=formatter
		end

		private def tty?(device_or_string)
			return device_or_string.tty? if device_or_string.respond_to? :tty?
			false
		end

		#log the action and execute it
		#Severity is Logger:: DEBUG < INFO < WARN < ERROR < FATAL < UNKNOWN
		def log_and_do(*args, severity: INFO, definee: self, **opts, &block)
			msg="log_and_do #{args} on #{self}"
			msg+=" with options #{opts}" unless opts.empty?
			msg+=" with block #{block}" if block
			add(severity,msg)
			if opts.empty?
				definee.send(*args, &block)
			else
				definee.send(*args, **opts, &block)
			end
		end

		private def toggle_log_level(toggle='debug')
			@log_level_original = self.level unless @log_level_toggled
			logger.level = if @log_level_toggled
											 @log_level_original
										 else
											 log_levels.fetch(toggle)
										 end
			@log_level_toggled = !@log_level_toggled
			@log_level = logger.level
		end

		#call logger.setup_toggle_trap('USR1') to change the log level to
		#:debug when USR1 is received
		def setup_toggle_trap(signal)
			if signal
				Signal.trap(signal) do
					toggle_log_level
				end
			end
		end

	end
	#}}}
	# CLILogging {{{
	# Provides easier access to a shared DR::CLILogger instance.
	# Include this module into your class, and #logger provides access to a
	# shared logger. This is handy if you want all of your clases to have
	# access to the same logger, but don't want to (or aren't able to) pass
	# it around to each class.
	# This also provides methods for direct logging without going through the
	# #logger
	#
	# === Example
	#
	#			class MyClass
	#				include DR::CLILogging
	#
	#				def doit
	#					debug("About to doit!")
	#					if results
	#						info("We did it!")
	#					else
	#						error("Something went wrong")
	#					end
	#					debug("Done doing it")
	#				end
	#			end
	#
	# Note that every class that mixes this in shares the *same logger
	# instance*, so if you call #change_logger, this will change the logger
	# for all classes that mix this in.  This is likely what you want.
	module CLILogging
		extend self

		# Access the shared logger.  All classes that include this module
		# will get the same logger via this method.
		def logger
			unless CLILogging.class_variable_defined?(:@@logger)
				@@logger = CLILogger.new
				@@logger.progname=$0
			end
			@@logger
		end

		self.logger.progname||=$0

		# Change the global logger that includers will use.  Useful if you
		# don't want the default configured logger.  Note that the
		# +change_logger+ version is preferred because Ruby will often parse
		# <tt>logger = Logger.new</tt> as the declaration of, and assignment
		# to, of a local variable.	You'd need to do
		# <tt>self.logger=Logger.new</tt> to be sure.  This method is a bit
		# easier.
		#
		# +new_logger+:: the new logger.	May not be nil and should be a logger of some kind
		def change_logger(new_logger)
			raise ArgumentError,"Logger may not be nil" if new_logger.nil?
			@@logger = new_logger
			@@logger.level = @log_level if defined?(@log_level) && @log_level
		end

		alias logger= change_logger

		#call CLILogging.setup_toggle_trap('USR1') to change the log level to
		#:debug when USR1 is received
		def self.setup_toggle_trap(signal)
			logger.setup_toggle_trap(signal)
		end

		def log_and_do(*args)
			logger.log_and_do(*args)
		end

		LOG_LEVELS=logger.log_levels

		#Include this in place of CLILogging if you prefer to use
		#info directly rather than logger.info
		module Shortcuts #{{{
			extend self
			include CLILogging
			LOG_LEVELS.each do |lvl, _cst|
				define_method(lvl.to_sym) do |progname=nil, &block|
					logger.send(lvl.to_sym, progname, &block)
				end
			end
		end
		#}}}
	end #}}}
end
