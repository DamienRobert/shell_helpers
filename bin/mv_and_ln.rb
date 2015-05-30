#!/usr/bin/env ruby

require 'shell_helpers/pathname'
require 'shell_helpers/options'

opts = Slop.parse(ARGV) do |o|
	o.bool "-v", "--verbose", "verbose"
	o.int "--verbose-level", "verbose level"
	o.bool "-t", "--test", "test"
	o.symbol "-m", "--mode", "Conversion mode", default: :rel
	o.symbol "--rm", "rm options", default: :noclobber
	o.symbol "--dereference-mode", "dereference mode for dest"
	o.bool "-L", "--dereference", "dereference dest"
	o.bool "-f", "--force", "force remove"
	o.on '--help' do
		puts o
		exit
	end
end

if opts[:force]
	opts[:rm] ||= :all
else
	opts[:rm] ||= :noclobber
end
#dereference-mode can also take the values 'simple' and 'none'
opts[:"dereference-mode"] ||= opts[:dereference]

pathname=ShellHelpers::Pathname
if opts[:verbose] and opts[:test]
	pathname=ShellHelpers::Pathname::DryRun
elsif opts[:verbose] and !opts[:test]
	pathname=ShellHelpers::Pathname::Verbose
elsif opts[:test]
	pathname=ShellHelpers::Pathname::NoWrite
end

*args,dest=opts.args
dest=pathname.new(dest)
if args.empty?
	warn "You should specify at least two arguments"
	exit 1
end
if args.length > 1 and !dest.directory?
	warn "When specifying more than one target, dest should be a directory"
	exit 1
end
args.each do |f|
	f=pathname.new(f)
	t=dest.directory? ? dest+f.basename : dest
	t=f.rel_path_to(t, mode: opts[:mode])
	puts "#{f} -> #{t}" if opts[:verbose]
	dest.on_mv(f, mode: opts[:rm], verbose: opts[:verbose], dereference: opts[:"dereference-mode"]) and f.on_ln_s(t, verbose: opts[:verbose])
end
