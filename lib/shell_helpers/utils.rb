require 'shellwords'
require 'dr/ruby_ext/core_ext'
require 'dr/parse/simple_parser'
require 'shell_helpers/pathname'

module ShellHelpers
	module ShellExport
		extend self

		#export a value for SHELL consumption
		def export_value(v)
			case v
				when String
					return v.shellescape
				when Array
					return "(#{v.map {|i| i.to_s.shellescape}.join(' ')})"
				when Hash
					return "(#{v.map {|k,v| k.to_s.shellescape+" "+v.to_s.shellescape}.join(' ')})"
				when nil
					return ""
				when ->(x){x.respond_to?(:to_a)}
					return export_value(v.to_a)
				when ->(x){x.respond_to?(:to_h)}
					return export_value(v.to_h)
				else
					return v.to_s.shellescape
			end
		end
		def import_value(v, type: String)
			#String === String => false
			case type.to_s
			when "String"
				v.to_s
			when "Integer"
				v.to_i
			when "Symbol"
				v.to_sym
			when "Array"
				#v is of the form (ploum plam)
				eval "%w#{v}"
			when "Hash"
				import_value(v, type: Array).each_slice(2).to_h
			end
		end

		def escape_name(name, prefix:"", upcase: true)
			name=name.to_s
			name=name.upcase if upcase
			(prefix+name).gsub('/','_')
		end

		#export_variable("ploum","plam") yields ploum="plam"
		def export_variable(name, value, local: false, export: false, prefix:"",upcase:true)
			r=""
			name=escape_name(name,prefix:prefix,upcase:upcase)
			r+="local #{name}\n" if local
			r+="typeset -A #{name}\n" if Hash === value
			r+="#{name}=#{export_value(value)}\n"
			r+="export #{name}\n" if export
			return r
		end

		def import_variable(namevalue, downcase:true, type: :auto)
			#TODO: handle quotes
			namevalue.match(/(local|export)?\s*(\S*)=(.*)$/) do |m|
				_match,_type,name,value=m.to_a
				name=name.downcase if downcase
				if type == :auto
					if value=~/^\(.*\)$/
						value=import_value(value, type: Array)
					else
						value=import_value(value)
					end
				else
					value=import_value(value, type: type)
				end
				return name, value
			end
		end

		#from {ploum: plim} return something like
		#PLOUM=plim
		#that can be evaluated by the shell
		def export_variables(hash, local: false, export: false, prefix:"",upcase:true)
			names=hash.keys.map {|s| escape_name(s,prefix:prefix,upcase:upcase)}
			r=""
			r+="local #{names.join(" ")}\n" if local
			hash.each do |k,v|
				r+=export_variable(k,v,prefix:prefix,upcase:upcase)
			end
			r+="export #{names.join(" ")}\n" if export
			return r
		end

		#export_parse(hash,"name:value")
		#will output name=$(hash[value])
		#special cases: when value = '/' we return the full hash
		#		when value ends by /, we return the splitted hash (and name serves
		#		as a prefix)
		#Ex: Numenor ~ $ ./mine/00COMPUTERS.rb --export=//
		#		 HOSTNAME=Numenor;
		#		 HOSTTYPE=perso;
		#		 HOMEPATH=/home/dams;...
		#		 Numenor ~ $ ./mine/00COMPUTERS.rb --export=syst/
		#		 LAPTOP=true;
		#		 ARCH=i686;...
		#Remark: in name:value, we don't put name in uppercase
		#But in split hash mode, we put the keys in uppercase (to prevent collisions)
		def export_parse(hash,s)
			r=""
			args=DR::SimpleParser.parse_string(s.to_s)
			args[:values].each do |k,v|
				if v
					name=k.to_s
				else
					#no name given
					v=k.to_s
					if v !='/' && v[-1]=='/'
						#in split mode we don't need the name
						name="" 
					else
						#else since no name was given we reuse the variable
						name=v
						name="all" if v=="/"
					end
				end
				if v != '/' && v[-1]=='/'
					all=true
					v=v[0...-1]
				end
				value=hash.keyed_value(v)
				opts=args[:opts][k]
				if all
					r+=export_variables(value, prefix: name, **opts)
				else
					r+=export_variable(name,value, **opts)
				end
			end
			return r
		end

		def import_parse(s, split_on: :auto, var_separator:'/')
			r={}
			if split_on == :auto
				split_on=","
				split_on="\n" if s =~ /\n/
			end
			instructions=s.split(split_on)
			instructions.each do |namevalue|
				name,value=import_variable(namevalue)
				r.set_keyed_value(name,value, sep: var_separator)
			end
			r
		end
	end

	module ShellUtils
		extend self

		class << self
			attr_accessor :orig_stdin, :orig_stdout, :orig_stderr
		end
		@orig_stdin=$stdin
		@orig_stdout=$stdout
		@orig_stderr=$stderr

		#An improved find from Find::find that takes in the block the absolute and relative name of the files (+the directory where the relative file is from), and has filter options
		#Returns ::Pathname, except when the value is SH::Pathname where it
		#returns a SH::Pathname
		def find(*bases, filter: nil, prune: nil, follow_symlink: false, depth: false, max_depth: nil, chdir: false)
			block_given? or return enum_for(__method__, *bases, filter: filter, follow_symlink: follow_symlink, depth: depth, max_depth: max_depth, chdir: chdir)
			bases.collect!{|d| raise Errno::ENOENT unless File.exist?(d); d.dup}.each do |base|
				klass=base.is_a?(::Pathname) ? base.class : ::Pathname
				base=klass.new(base)

				test_filter=lambda do |filter,*files|
					case filter
					when Proc
						filter.call(*files)
					when Array
						file=files.first
						filter.any? do |test|
							case test
							when :directory? #special case
								file.directory? && !file.symlink?
							else
								file.send(test)
							end
						end
					end
				end

				yield_files=lambda do |*files|
					unless test_filter.(filter,*files)
						files.map! {|f| f.dup.taint}
						if chdir
							Dir.chdir(base) do
								yield *files, base
							end
						else
							yield *files, base
						end
					end
				end

				do_find=lambda do |*files|
					file,filerel=*files
					catch(:prune) do #use throw(:prune) to skip a path (recursively)
						unless test_filter.(prune,*files)
							yield_files.(*files) unless depth
							if file.directory? and (max_depth.nil? or (filerel.to_s=="." and max_depth>0) or filerel.each_filename.to_a.size < max_depth)
								next if !follow_symlink && file.symlink?
								file.children(false).sort.reverse_each do |f|
									fj = file + f
									f = filerel + f
									do_find.(fj.untaint,f.untaint)
								end
								yield_files.(*files) if depth
							end
						end
					end
				end
				do_find.call(base, klass.new('.'))
			end
		end

		#all output is sent to the pager
		def run_pager(opt=nil)
			return unless $stdout.tty? and opt != :never
			read, write = IO.pipe

			unless Kernel.fork # Child process
				$stdout.reopen(write)
				$stderr.reopen(write) if $stderr.tty?
				read.close
				write.close
				return
			end

			# Parent process, become pager
			$stdin.reopen(read)
			read.close
			write.close

			#ENV['LESS'] = 'FSRX' # Don't page if the input is short enough
			lessenv=ENV['LESS']
			lessenv="-FRX" if lessenv.empty?
			lessenv+="F" unless lessenv.match(/F/) or opt == :always
			lessenv+="R" unless lessenv.match(/R/)
			lessenv+="X" unless lessenv.match(/X/)
			ENV['LESS']=lessenv

			Kernel.select [$stdin] # Wait until we have input before we start the pager
			pager = ENV['PAGER'] || 'less'
			exec pager rescue exec "/bin/sh", "-c", pager
		end

		#inside run_pager, escape from the pager
		#does not work :-(
		def escape_pager(mode=nil)
			case mode
			when :orig
				stdout=ShellUtils.orig_stdout
				stderr=ShellUtils.orig_stderr
				stdin=ShellUtils.orig_stdin
			else
				stdout=STDOUT
				stderr=STDERR
				stdin=STDIN
			end
			$stdout.reopen(stdout)
			$stderr.reopen(stderr)
			$stdin.reopen(stdin)
		end

		def output_list(s, split: "\n")
			s=s.shelljoin if s.kind_of?(Array)
			return open("| #{s}").read.split(split)
		end

		#Stolen from mkmf:
		# Searches for the executable +bin+ on +path+.	The default path is your
		# +PATH+ environment variable. If that isn't defined, it will resort to
		# searching /usr/local/bin, /usr/ucb, /usr/bin and /bin.
		# If found, it will return the full path, including the executable name, of
		# where it was found.
		# exts: an array of extensions to add
		def find_executable(bin, path = nil, exts: nil)
			executable_file = lambda do |name|
				name=Pathname.new(name)
				return name if name.file? and name.executable?
			end
			#we use Proc so that 'return' escapes the block
			try_executable = Proc.new do |file|
				return file if executable_file.call(file)
				exts && exts.each {|ext| executable_file.call(ext = file.append_name(ext)) and return ext}
				nil
			end

			bin=Pathname.new(bin)
			if bin.absolute?
				try_executable.call(bin)
			else
				path ||= ENV['PATH'] || %w[/usr/local/bin /usr/bin /bin]
				path = path.split(File::PATH_SEPARATOR) unless path.kind_of?(Array)
				path.each do |dir|
					dir=Pathname.new(dir)
					try_executable.call(dir+bin)
				end
			end
			nil
		end

		def find_file(file,path)
			path.each do |dir|
				dir=Pathname.new(dir)
				path=dir+file
				return path if path.file?
			end
			return nil
		end

		def find_files(pattern,path)
			path.map { |dir| Pathname.glob(dir+pattern) }.flatten
		end

		def rsync(*files, out, preserve: true, keep_dirlinks: false, sudo: false, backup: false, relative: false, delete: false, clean_out: false, expected: 23, **opts)
			require 'shell_helpers/sh'
			rsync_opts=[]
			rsync_opts << "-vaczP" if preserve
			rsync_opts+=%w(--no-owner --no-group) if preserve==:nochown
			rsync_opts << "--keep-dirlinks" if keep_dirlinks
			rsync_opts << "--relative" if relative
			rsync_opts << "--delete" if delete
			if clean_out
				out=Pathname.new(out)
				out.rmtree
				out.mkpath
			end
			opts[:log]||=true
			opts[:log_level_execute]||=:info
			if backup
				rsync_opts << "--backup"
				rsync_opts << (backup.to_s[-1]=="/" ? "--backup-dir=#{backup}" : "--suffix=#{backup}") unless backup==true
			end
			Sh.sh( (sudo ? ["sudo"] : [])+["rsync"]+rsync_opts+files.map(&:to_s)+[out.to_s], expected: expected, **opts)
			#rsync error code 23 is some files/attrs were not transferred
		end

	end
end
