require 'slop'

module Slop
	class SymbolOption < Option
		def call(value)
			value.to_sym
		end
	end

	class PathOption < Option
		def call(value)
			ShellHelpers::Pathname.new(value)
		end
		def finish(opts)
			if cmd[:verbose] and cmd[:test]
				pathname=ShellHelpers::Pathname::DryRun
			elsif cmd[:verbose] and !cmd[:test]
				pathname=ShellHelpers::Pathname::Verbose
			elsif cmd[:test]
				pathname=ShellHelpers::Pathname::NoWrite
			else
				pathname=ShellHelpers::Pathname
			end
			self.value=pathname.new(value)
		end
	end
end
