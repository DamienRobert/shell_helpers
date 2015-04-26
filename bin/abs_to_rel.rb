#!/usr/bin/env ruby

require 'shell_helpers/pathname'
require 'shell_helpers/options'

opts = Slop.parse(ARGV) do |o|
	o.bool "-v", "--verbose", "verbose"
	o.bool "-t", "--test", "test"
	o.symbol "-m", "--mode", "Conversion mode", default: :rel
	o.string "-b", "--base", "Assume symlinks are relative to this base"
	o.symbol "--base-mode", "Base conversion mode", default: :abs_realdir
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
		base=(opts[:base]||l.dirname).convert_path(mode: opts[:'base-mode'])
		oldpath=l.readlink
		newpath=l.rel_path_to(oldpath, base: base, mode: opts[:mode])
		if oldpath != newpath
			puts "#{l}: #{oldpath} -> #{newpath}" if opts[:verbose]
			l.on_ln_sf(newpath, dereference: :none) 
		else
			puts "#{l}: #{newpath}" if opts[:verbose]
		end
	else
		puts "! #{l} is not a symlink" if opts[:verbose]
	end
end
