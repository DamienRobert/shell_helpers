gem 'slop', '~> 4'
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
			if opts[:verbose] and opts[:test]
				pathname=ShellHelpers::Pathname::DryRun
			elsif opts[:verbose] and !opts[:test]
				pathname=ShellHelpers::Pathname::Verbose
			elsif opts[:test]
				pathname=ShellHelpers::Pathname::NoWrite
			else
				pathname=ShellHelpers::Pathname
			end
			self.value=pathname.new(value)
		end
	end
end
