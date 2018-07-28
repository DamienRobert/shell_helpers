require 'shellwords'
require 'shell_helpers/pathname'

module ShellHelpers

	module ExtendSSHKit
		def backend(&b)
			local? ? SSHKit::Backend::Local.new(&b) : SSHKit.config.backend.new(self, &b)
		end
		def connect(&b)
			backend(&b).run
		end
	end

	module Utils
		extend self

		def eval_shell(r, shell: :puts)
			return r if r.nil? or r.empty?
			case (shell||"").to_sym
			when :puts
				puts r
			when :eval
				r+=";" if r && !r.end_with?(';')
				print r
			when :exec
				require 'shell_helpers/sh'
				return ShLog.sh(r)
			when :exec_quiet
				require 'shell_helpers/sh'
				return Sh.sh(r)
			end
			return r
		end

		class << self
			attr_accessor :orig_stdin, :orig_stdout, :orig_stderr
		end
		@orig_stdin=$stdin
		@orig_stdout=$stdout
		@orig_stderr=$stderr

		#An improved find from Find::find that takes in the block the absolute and relative name of the files (+the directory where the relative file is from), and has filter options
		#Returns ::Pathname, except when the value is a SH::Pathname where it
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
		def run_pager(*args, launch: :tty, default_less_env: "-FRX")
			return unless $stdout.tty? and launch != :never
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
			less_env=ENV['LESS']
			less_env=default_less_env if less_env.empty?
			less_env+="F" unless less_env.match(/F/) or launch == :always
			less_env+="R" unless less_env.match(/R/)
			less_env+="X" unless less_env.match(/X/)
			ENV['LESS']=less_env

			Kernel.select [$stdin] # Wait until we have input before we start the pager
			pager = ENV['PAGER'] || 'less'
			run=args.unshift(pager)
			exec *run rescue exec "/bin/sh", "-c", *run
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

		def rsync(*files, out, default_opts: "-vcz", preserve: true, partial: true, keep_dirlinks: false, sudo: false, backup: false, relative: false, delete: false, clean_out: false, expected: 23, chown: nil, sshcommand: nil, exclude: [], **opts)
			require 'shell_helpers/sh'
			rsync_opts=[*opts.delete(:rsync_opts)] || []
			rsync_opts << default_opts
			rsync_opts << "-a" if preserve
			rsync_opts << "-P" if partial #--partial --progress
			rsync_opts+=%w(--no-owner --no-group) if preserve==:nochown
			rsync_opts+=["--chown", chown] if chown
			#on dest: do not replace a symlink to a directory with the real directory
			#use --copy-dirlinks for the same usage on source
			rsync_opts << "--keep-dirlinks" if keep_dirlinks
			exclude.each do |ex|
				rsync_opts += ["--exclude", ex.shellescape]
			end
			if relative
				rsync_opts << "--relative"
				rsync_opts << "--no-implied-dirs"
			end
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
			if sshcommand
				rsync_opts << "-e"
				rsync_opts << sshcommand.shellescape
			end
			rsync_opts+=opts.delete(:rsync_late_opts)||[]
			Sh.sh( (sudo ? ["sudo"] : [])+["rsync"]+rsync_opts+files.map(&:to_s)+[out.to_s], expected: expected, **opts)
			#expected: rsync error code 23 is some files/attrs were not transferred
		end

		# host can be of the form user@host:port
		# warning this is different from standard ssh syntax of user@host:path
		def ssh(host, *commands, mode: :exec, ssh_command: 'ssh',
			ssh_options: [], ssh_Ooptions: [],
			port: nil, forward: nil, x11: nil, user: nil, path: nil, parse: true,
			**opts)

			#sshkit has a special setting for :local
			host=host.to_s unless mode==:sshkit and host.is_a?(Symbol)
			parse and host.is_a?(String) and host.match(/^(?:(.*)@)?(.*?)(?::(\d*))?$/) do |m|
				user||=m[1]
				host=m[2]
				port||=m[3]
			end
			unless mode==:net_ssh or mode==:sshkit
				ssh_command, *command_options= ssh_command.shellsplit
				ssh_options=command_options+ssh_options
				ssh_options += ["-p", port.to_s] if port
				ssh_options += ["-W", forward] if forward
				if x11 == :trusted
					ssh_options << "-Y"
				elsif x11
					ssh_options << "-X"
				end
				ssh_options += ssh_Ooptions.map {|o| ["-o", o]}.flatten
			else #net_ssh options needs to be a hash
				ssh_options={} if ssh_options.is_a?(Array)
				ssh_options[:port]=port if port
			end
			case mode
			when :system,:spawn,:capture,:exec
				host="#{user}@#{host}" if user
				Sh.sh([ssh_command]+ssh_options+[host]+commands, mode: mode, **opts)
			when :net_ssh
				require 'net/ssh'
				user=nil;
				Net::SSH.start(host, user, ssh_options)
			when :sshkit
				require 'sshkit'
				host=SSHKit::Host.new(host)
				host.extend(ExtendSSHKit)
				host.port=port if port
				host.user=user if user
				host.ssh_options=ssh_options
				host
			when :uri
				URI::Generic.build(scheme: 'ssh', userinfo: user, host: host, path: path, port: port) #, query: ssh_options.join('&'))
			else
				# return options
				{ ssh_command: ssh_command,
				  ssh_options: ssh_options,
				  ssh_command_options: ([ssh_command]+ssh_options).shelljoin,
				  user: user,
				  host: host,
				  hostssh: user ? "#{user}@#{host}" : host,
				  command: commands }
			end
		end

		def capture_stdout
			old_stdout = $stdout
			$stdout = StringIO.new('','w')
			if block_given?
				begin
					yield
					output=$stdout.string
				ensure
					$stdout = old_stdout
				end
				return output
			else
				return old_stdout
			end
		end

	end
end
