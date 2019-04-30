# vim: foldmethod=marker
#From methadone (cli_logger.rb, cli_logging.rb, last import: 4626a2bca9b6e54077a06a0f8e11a04fadc6e7ae; 2017-01-19)
require 'logger'
require 'simplecolor'

module ShellHelpers
	# like Logger but with more levels
	class MoreLogger < Logger #{{{1
		class Formatter < Logger::Formatter
			def self.format_severity(severity)
				Logger::SEV_LABEL[severity] || 'ANY'
			end

			def call(severity, time, progname, msg)
				severity=self.class.format_severity(severity)
				Format % [severity[0..0], format_datetime(time), $$, severity, progname,
					msg2str(msg)]
			end
		end

		WrongLevel=Class.new(StandardError)

		module Levels
			#note Logger::Severity is included into Logger, so we can access the severity levels directly
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
			DEBUG		= Logger::DEBUG # 0
			INFO		= Logger::INFO # 1
			WARN		= Logger::WARN # 2
			ERROR		= Logger::ERROR # 3
			FATAL		= Logger::FATAL # 4
			UNKNOWN = Logger::UNKNOWN # 5
		end

		LOG_LEVELS=
			{
				'quiet' => Levels::QUIET,
				'debug3' => Levels::DEBUG3,
				'debug2' => Levels::DEBUG2,
				'debug1' => Levels::DEBUG1,
				'debug' => Levels::DEBUG, #0
				'verbose' => Levels::VERBOSE,
				'verbose1' => Levels::VERBOSE1,
				'verbose2' => Levels::VERBOSE2,
				'verbose3' => Levels::VERBOSE3,
				'info' => Levels::INFO, #1
				'success' => Levels::SUCCESS,
				'important' => Levels::IMPORTANT,
				'warn' => Levels::WARN, #2
				'error' => Levels::ERROR, #3
				'fatal' => Levels::FATAL, #4
				'unknown' => Levels::UNKNOWN, #5
			}

		def log_levels
			@levels ||= LOG_LEVELS.dup
			@levels
		end

		attr_accessor :default, :active, :quiet

		def initialize(*args, levels: {}, default: :info, active: :verbose, quiet: :warn, **kwds)
			@default=default
			@active=active
			@quiet=quiet
			super(*args, **kwds)
			@default_formatter = Formatter.new
			@level=severity_lvl(@default)
			klass=self.singleton_class
			levels=log_levels.merge!(levels)
			levels.keys.each do |lvl, cst|
				klass.define_method(lvl.to_sym) do |progname=nil, **opts, &block|
					add(lvl.to_sym, nil, progname, **opts, &block)
				end
				klass.define_method("#{lvl}?".to_sym) do
					@level <= cst
				end
			end
		end

		# log with given security. Also accepts 'true'
		def add(severity, message = nil, progname = nil, default: @default, quiet: @quiet, callback: nil)
			severity=severity(severity, default: default, quiet: quiet)
			severity_lvl=severity_lvl(severity)
			if @logdev.nil? or severity_lvl < @level
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
			callback.call(message, progname, severity) if callback
			@logdev.write(
				format_message(format_severity(severity), Time.now, progname, message))
			true
		end

		def severity(severity, default: @default, quiet: @quiet)
			severity ||= UNKNOWN
			severity=default if severity == true
			severity=quiet if severity == false
			severity
		end

		def severity_lvl(severity, **opts)
			severity=severity(severity, **opts)
			if severity.is_a?(Numeric)
				return severity
			else
				sev=severity.to_s.downcase
				if log_levels.key?(sev)
					return log_levels[sev]
				else
					raise WrongLevel.new(severity)
				end
			end
		end

		def level=(severity)
			@level = severity_lvl(severity)
		end

		# like level= but for clis, so we can pass a default if level=true
		def cli_level(level, active: @active, quiet: @quiet)
			level=active if level==true #for cli
			level=quiet if level==false #for cli
			self.level=level
		end
	end

	class ColorLogger < MoreLogger #{{{1
		CLI_COLORS_BASE={
			# info: [:bold],
			success: [:green, :bold],
			important: [:blue, :bold],
			warn: [:yellow, :bold],
			error: [:red, :bold],
			fatal: [:red, :bold]
		}

		CLI_COLORS={
			mark: {lvl: :info, colors: :bold}
		}

		def cli_colors
			return @cli_colors if defined?(@cli_colors)
			@cli_colors={}
			base_colors=CLI_COLORS_BASE
			base_colors.each do |k,v|
				r={colors: v}
				@cli_colors[k.to_sym]=r
			end
			@cli_colors.merge!(CLI_COLORS)
			@cli_colors
			#mode => {lvl: lvl, colors: colors }
		end

		def add(severity, message = nil, progname = nil, color: [], raw: @raw, **args)
			severity ||= UNKNOWN
			severity=severity(severity)
			color=[*color]
			unless severity.is_a?(Numeric)
				cli=cli_colors[severity.to_sym]
				if cli
					severity=cli[:lvl] if cli.key?(:lvl)
					if !raw
						color=[*cli[:colors]] + color
					end
				end
			end
			severity_lvl=severity_lvl(severity)

			if @logdev.nil? or severity_lvl < @level
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
			message = SimpleColor.color(message.to_s, *color)
			super(severity_lvl, message, progname)
		end

		attr_accessor :raw

		def initialize(*args, cli: {}, **kwds)
			@raw=false
			super(*args, **kwds)
			klass=self.singleton_class
			cli=cli_colors.merge!(cli)
			(cli.keys - CLI_COLORS_BASE.keys).each do |lvl|
				klass.define_method(lvl.to_sym) do |progname=nil, **opts, &block|
					add(lvl, nil, progname, **opts, &block)
				end
			end
			yield self if block_given?
		end
	end

	# CLILogger {{{1
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
	class CLILogger < ColorLogger
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

		def add(severity, message = nil, progname = nil, **opts, &block) #:nodoc:
			severity_lvl = severity_lvl(severity)
			if @split_logs
				unless severity_lvl >= @stderr_logger.level
					super(severity,message,progname, **opts, &block)
				end
			else
				super(severity,message,progname,**opts, &block)
			end
			@stderr_logger.add(severity,message,progname,**opts, &block)
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
									 split_log: :auto, default_error: DEFAULT_ERROR_LEVEL, **kwds)
			@stderr_logger = MoreLogger.new(error_device, default: default_error, **kwds)

			super(log_device, **kwds)

			log_device_tty	 = tty?(log_device)
			error_device_tty = tty?(error_device)

			@split_logs = log_device_tty && error_device_tty if split_log==:auto

			self.level = Logger::Severity::INFO
			@stderr_logger.level = @stderr_logger.default

			self.formatter = BLANK_FORMAT if log_device_tty
			@stderr_logger.formatter = BLANK_FORMAT if error_device_tty
			yield self, @stderr_logger if block_given?
		end

		def level=(level)
			super
			#current_error_level = @stderr_logger.level
			if (self.level > @stderr_logger.default) && @split_logs
				@stderr_logger.level = self.level
			end
		end

		def cli_level(*args)
			super
			if (self.level > @stderr_logger.default) && @split_logs
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

	# CLILogging {{{1
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
