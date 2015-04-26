#!/usr/bin/env ruby

require 'shell_helpers/pathname'
require 'shell_helpers/options'

opts = Slop.parse(ARGV) do |o|
	o.bool "-v", "--verbose", "verbose"
	o.bool "-t", "--test", "test"
	o.string "-b", "--base", "Assume symlinks are relative to this base"
	o.symbol "-m", "--mode", "Conversion mode", default: :rel
	o.on '--help' do
		puts o
		exit
	end
end

pathname=ShellHelpers::Pathname
if opts[:verbose] and opts[:test]
	pathname=ShellHelpers::Pathname::DryRun
elsif opts[:verbose] and !opts[:test]
	pathname=ShellHelpers::Pathname::Verbose
elsif opts[:test]
	pathname=ShellHelpers::Pathname::NoWrite
end

opts.args.each do |l|
	l=pathname.new(l)
	if l.symlink?
		p l
		oldpath=l.readlink
		p oldpath
		newpath=oldpath.convert_path(base: pathname.new(opts[:base]||l.dirname), mode: opts[:mode])
		p newpath
		puts "#{l}: #{oldpath} -> #{newpath}" if opts[:verbose]
		l.on_ln_s(newpath)
	else
		puts "! #{l} is not a symlink" if opts[:verbose]
	end
end
