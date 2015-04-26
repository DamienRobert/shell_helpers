require 'slop'

module ShellHelpers
	module Slop
		include ::Slop
		Options=::Slop::Options
		Parser=::Slop::Parser
		class SymbolOption < Option
			def call(value)
				value.to_sym
			end
		end
		class PathOption < Option
			def call(value)
				DR::Pathname.new(value)
			end
		end
	end
end
