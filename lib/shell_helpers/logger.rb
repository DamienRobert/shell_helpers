# vim: foldmethod=marker
#From methadone (cli_logger.rb, cli_logging.rb, last import: 4626a2bca9b6e54077a06a0f8e11a04fadc6e7ae; 2017-01-19)
require 'logger'
require 'simplecolor'

module ShellHelpers
	class ColorFormatter < Logger::Formatter #{{{1
		CLI_COLORS={
			mark: [:bold],
			success: [:green, :bold],
			important: [:blue, :bold],
			warn: [:yellow, :bold],
			error: [:red, :bold],
			fatal: [:red, :bold]
		}

		def self.create(type=:default)
			return type if type.respond_to?(:call)
			logger=self.new
			case type
			when :blank
				logger.format=BLANK_FORMAT
			when :color
				logger.cli_colors=CLI_COLORS
				logger.format=BLANK_FORMAT
			when :color_info
				logger.cli_colors=CLI_COLORS
			when :none
				logger.format=""
			end
			logger
		end

		def format_severity(severity)
			# sev_name = Logger::SEV_LABEL[severity] || 'ANY'
			sev_name=severity.to_s.upcase
			sev_short=sev_name[0..0]
			[sev_name, sev_short]
		end

		attr_accessor :cli_colors

		BLANK_FORMAT = "%{msg}\n"
		# "%s, [%s#%d] %5s -- %s: %s\n"
		DEFAULT_FORMAT = "%{severity_short}, [%{date}#%<pid>d] %<severity>s9 -- %{progname}: %{msg}\n"
		attr_writer :format
		def format
			@format ||= DEFAULT_FORMAT
		end

		private def get_colors(severity, color: [], **_kwds)
			if cli_colors.nil? #no colors at all
				return []
			end
			colors=[*color]
			unless severity.is_a?(Numeric)
				colors=[*cli_colors[severity.to_sym]]+colors
			end
			colors
		end

		def format_msg(msg_infos, colors: [])
			msg_infos[:msg]=SimpleColor[msg_infos[:msg], *colors]
			format % msg_infos
		end

		def call(severity, time, progname, msg, **kwds)
			colors=get_colors(severity, **kwds)
			severity_short, severity_name=format_severity(severity)
			format_msg( {severity_short: severity_short,
				date: format_datetime(time),
				pid: $$,
				severity: severity_name,
				progname: progname,
				msg: msg2str(msg)}, colors: colors)
		end
	end

	# like Logger but with more levels
	class ColorLogger < ::Logger #{{{1
		ColorLoggerError=Class.new(StandardError)
		WrongLevel=Class.new(ColorLoggerError)
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
				quiet: Levels::QUIET,
				debug3: Levels::DEBUG3,
				debug2: Levels::DEBUG2,
				debug1: Levels::DEBUG1,
				debug: Levels::DEBUG, #0
				verbose: Levels::VERBOSE,
				verbose1: Levels::VERBOSE1,
				verbose2: Levels::VERBOSE2,
				verbose3: Levels::VERBOSE3,
				info: Levels::INFO, #1
				mark: :info,
				success: Levels::SUCCESS,
				important: Levels::IMPORTANT,
				warn: Levels::WARN, #2
				error: Levels::ERROR, #3
				fatal: Levels::FATAL, #4
				unknown: Levels::UNKNOWN, #5
			}

		def log_levels
			@levels ||= LOG_LEVELS.dup
			@levels
		end

		def severity(severity, default_lvl: @default_lvl, quiet_lvl: @quiet_lvl, **_opts)
			severity ||= :unknown
			severity=default_lvl if severity == true
			severity=quiet_lvl if severity == false
			severity
		end

		def severity_lvl(severity, **opts)
			severity=severity(severity, **opts)
			if severity.is_a?(Numeric)
				return severity
			else
				sev=severity.to_s.downcase.to_sym
				if log_levels.key?(sev)
					return severity_lvl(log_levels[sev])
				else
					raise WrongLevel.new(severity)
				end
			end
		end

		attr_accessor :default_lvl, :verbose_lvl, :quiet_lvl, :default_formatter

		def initialize(*args, levels: {}, default_lvl: :info, level: default_lvl, verbose_lvl: :verbose, quiet_lvl: :unknown, default_formatter: :color, **kwds)
			@default_lvl=default_lvl
			@verbose_lvl=verbose_lvl
			@quiet_lvl=quiet_lvl
			super(*args, level: severity_lvl(level), **kwds)
			@default_formatter = ColorFormatter.create(default_formatter)
			@level=severity_lvl(@default_lvl)
			klass=self.singleton_class
			levels=log_levels.merge!(levels)
			levels.keys.each do |lvl|
				klass.define_method(lvl.to_sym) do |msg=nil, **opts, &block|
					add(lvl.to_sym, msg, **opts, &block)
				end
				klass.define_method("#{lvl}?".to_sym) do
					@level <= severity_lvl(lvl)
				end
			end
			yield self, @default_formatter if block_given?
		end

		def datetime_format=(datetime_format)
			@default_formatter.datetime_format = datetime_format if @default_formatter.respond_to?(:datetime_format)
			@formatter.datetime_format = datetime_format if defined? @formatter and @formatter.respond_to?(:datetime_format)
		end

		def datetime_format
			@default_formatter.datetime_format if @default_formatter.respond_to?(:datetime_format)
		end

		def formatter=(form)
			if form.nil?
				super
			else
				@formatter=get_formatter(form) 
			end
		end

		def get_formatter(form=nil)
			if form.nil?
				@formatter || @default_formatter
			else
				formatter=ColorFormatter.create(form)
				formatter.datetime_format = @default_formatter.datetime_format if formatter.respond_to?(:datetime_format) and @default_formatter.respond_to?(:datetime_format)
				formatter
			end
		end

		def format_message(severity, datetime, progname, msg, formatter: nil, **opts)
			get_formatter(formatter).call(severity, datetime, progname, msg, **opts)
		end

		# log with given security. Also accepts 'true'
		def add(severity, message = nil, progname: @progname, callback: nil, format: nil, **opts)
			severity=severity(severity, **opts)
			severity_lvl=severity_lvl(severity)
			if @logdev.nil? or severity_lvl < @level
				return true
			end
			if message.nil?
				message = yield if block_given?
			end
			callback.call(message, progname, severity) if callback
			@logdev.write(
				format_message(severity, Time.now, progname, message, formatter: format, caller: self, **opts))
			true
		end

		def level=(severity)
			@level = severity_lvl(severity)
		end

		# like level= but for clis, so we can pass a default if level=true
		def cli_level(level, active: @verbose_lvl, disactive: @quiet_lvl)
			level=active if level==true #for cli
			level=disactive if level==false #for cli
			self.level=level
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

		def add(severity, message = nil, **opts, &block) #:nodoc:
			severity_lvl = severity_lvl(severity)
			if @split_logs
				unless severity_lvl >= @stderr_logger.level
					super(severity,message, **opts, &block)
				end
			else
				super(severity,message,**opts, &block)
			end
			severity = severity_lvl if severity == true
			@stderr_logger.add(severity,message,**opts, &block)
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
				 split_log: :auto, default_error_lvl: DEFAULT_ERROR_LEVEL, **kwds)
			@stderr_logger = ColorLogger.new(error_device, default_lvl: default_error_lvl, **kwds)

			super(log_device, **kwds)

			log_device_tty	 = tty?(log_device)
			error_device_tty = tty?(error_device)

			@split_logs = log_device_tty && error_device_tty if split_log==:auto

			self.default_formatter = ColorFormatter.create(:color) if log_device_tty
			@stderr_logger.default_formatter = ColorFormatter.create(:color) if error_device_tty

			yield self, @stderr_logger if block_given?
		end

		private def adjust_stderr_level
			#current_error_level = @stderr_logger.level
			if @split_logs
				if (self.level > @stderr_logger.level)
					@stderr_logger.level = self.level
				end
				if (self.level < @stderr_logger.level)
					@stderr_logger.level = [self.level, @stderr_logger.severity_lvl(@stderr_logger.default_lvl)].min
				end
			end
		end

		def level=(level)
			super
			adjust_stderr_level
		end

		def cli_level(*args)
			super
			adjust_stderr_level
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
			include CLILogging
			extend self
			logger.log_levels.each_key do |lvl|
				define_method(lvl.to_sym) do |*args, &block|
					logger.send(lvl.to_sym, *args, &block)
				end
			end
		end
		#}}}
	end #}}}
end
