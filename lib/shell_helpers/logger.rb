# vim: foldmethod=marker
#From methadone (cli_logger.rb, cli_logging.rb, last import: 4626a2bca9b6e54077a06a0f8e11a04fadc6e7ae; 2017-01-19)
require 'logger'

module ShellHelpers
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
	class CLILogger < Logger
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
			severity = INFO if severity == true
			unless severity.is_a?(Integer)
				severity=log_levels[severity.to_s.downcase]|| UNKNOWN
			end
			return true if severity == QUIET
			if @split_logs
				unless severity >= @stderr_logger.level
					super(severity,message,progname,&block)
				end
			else
				super(severity,message,progname,&block)
			end
			@stderr_logger.add(severity,message,progname,&block)
		end

		def quiet(progname = nil, &block)
			add(QUIET, nil, progname, &block)
		end
		def debug1(progname = nil, &block)
			add(DEBUG1, nil, progname, &block)
		end
		def debug2(progname = nil, &block)
			add(DEBUG2, nil, progname, &block)
		end
		def debug3(progname = nil, &block)
			add(DEBUG3, nil, progname, &block)
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
			@stderr_logger = Logger.new(error_device)

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
			super(level)
			#current_error_level = @stderr_logger.level
			if (level > DEFAULT_ERROR_LEVEL) && @split_logs
				@stderr_logger.level = level
			end
		end

		# like level= but for clis, so can pass a string
		def cli_level(level, default: Logger::INFO)
			level=default if level==true #for cli
			if level.is_a?(Integer)
				self.level=level
			else
				level=level.to_s
				self.level=log_levels.fetch(level)
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
		def log_and_do(*args, severity: Logger::INFO, definee: self, **opts, &block)
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

		DEBUG1=-1
		DEBUG2=-2
		DEBUG3=-3
		QUIET=-9
		#note Logger::Severity is included into Logger, so we can access the severity levels directly
		LOG_LEVELS=
			{
				'quiet' => QUIET,
				'debug1' => DEBUG1,
				'debug2' => DEBUG2,
				'debug3' => DEBUG3,
				'debug' => Logger::DEBUG,
				'info' => Logger::INFO,
				'warn' => Logger::WARN,
				'error' => Logger::ERROR,
				'fatal' => Logger::FATAL,
			}

		def log_levels
			LOG_LEVELS
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

			def quiet(progname = nil, &block); logger.quiet(progname,&block); end
			def debug(progname = nil, &block); logger.debug(progname,&block); end
			def info(progname = nil, &block); logger.info(progname,&block); end
			def warns(progname = nil, &block); logger.warn(progname,&block); end
			def error(progname = nil, &block); logger.error(progname,&block); end
			def fatal(progname = nil, &block); logger.fatal(progname,&block); end
		end
		#}}}
	end #}}}
end
