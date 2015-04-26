#!/usr/bin/env ruby

require 'shell_helpers/pathname'
require 'shell_helpers/options'


optparser=ShellHelpers::Slop
opts = optparser::Options.new
opts.banner = "#{$0} [options]: convert symlink path"
opts.bool "-v", "--verbose", "verbose"
opts.bool "-t", "--test", "test"
opts.string "-b", "--base", "Assume symlinks are relative to this base"
opts.symbol "-m", "--mode", "Conversion mode", default: :rel
cmd = optparser::Parser.new(opts).parse([ARGV])

pathname=ShellHelpers::Pathname
if cmd[:verbose] and cmd[:test]
	pathname=ShellHelpers::Pathname::DryRun
elsif cmd[:verbose] and !cmd[:test]
	pathname=ShellHelpers::Pathname::Verbose
elsif cmd[:test]
	pathname=ShellHelpers::Pathname::NoWrite
end
cmd.args do |l|
	l=ShellHelpers::Pathname.new(l)
	if l.symlink?
		oldpath=l.readlink
		newpath=oldpath.convert_path(base: pathname.new(cmd[:base]), mode: cmd[:mode])
		puts "#{l}: #{oldpath} -> #{newpath}" if cmd[:verbose]
		l.on_ln_s(newpath)
	end
end

