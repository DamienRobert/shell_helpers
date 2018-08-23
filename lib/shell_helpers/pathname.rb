require 'pathname'

#backports from ruby 2.1
class Pathname
	unless method_defined?(:write)
		def write(*args,&b)
			IO.write(self,*args,&b)
		end
	end
	unless method_defined?(:to_path)
		alias to_path to_str
	end
end

autoload :FileUtils, "fileutils"

module ShellHelpers
	#SH::Pathname is Pathname with extra features
	#and methods from FileUtils rather than File when possible
	#to use this module rather than ::Pathname in a module or class,
	#simply define Pathname=SH::Pathname in an appropriate nesting level
	module PathnameExt
		class Base < ::Pathname
			#Some alias defined in FileUtils
			alias_method :mkdir_p, :mkpath
			alias_method :rm_r, :rmtree #rmtree should be rm_rf, not rm_r!
			def rmtree
				require 'fileutils'
				FileUtils.rm_rf(@path)
				nil
			end
			alias_method :rm_rf, :rmtree

			def shellescape
				require 'shellwords'
				to_s.shellescape
			end

			def to_relative
				return self if relative?
				relative_path_from(Pathname.slash)
			end

			#use the low level FileUtils feature to copy the metadata
			#if passed a dir just copy the dir metadata, not the directory recursively
			#Note this differs from FileUtils.copy_entry who copy directories recursively
			def copy_entry(dest, dereference: false, preserve: true)
				require 'fileutils'
				ent = FileUtils::Entry_.new(@path, nil, dereference)
				ent.copy dest.to_s
				ent.copy_metadata dest.to_s if preserve
			end

			class <<self
				def home
					return Pathname.new(Dir.home)
				end
				def hometilde
					return Pathname.new('~')
				end
				def slash
					return Pathname.new("/")
				end
				#differ from Pathname.pwd in that this returns a relative path
				def current
					return Pathname.new(".")
				end
				def null
					return Pathname.new('/dev/null')
				end

				#Pathname / 'usr'
				def /(path)
					new(path)
				end
				#Pathname['/usr']
				def [](path)
					new(path)
				end

				def cd(dir,&b)
					self.new(dir).cd(&b)
				end
			end

			#these Pathname methods explicitly call Pathname.new so do not respect
			#our subclass :-(
			[:+,:join,:relative_path_from].each do |m|
				define_method m do |*args,&b|
					self.class.new(super(*args,&b))
				end
			end
			alias_method :/, :+

			#exist? returns false if called on a symlink pointing to a non existing file
			def may_exist?
				exist? or symlink?
			end

			def filewrite(*args,mode:"w",perm: nil,mkpath: false,backup: false)
				logger.debug("Write to #{self}"+ (perm ? " (#{perm})" : "")) if respond_to?(:logger)
				self.dirname.mkpath if mkpath
				self.backup if backup and exist?
				if !exist? && symlink?
					logger.debug "Removing bad symlink #{self}" if respond_to?(:logger)
					self.unlink
				end
				self.open(mode: mode) do |fh|
					fh.chmod(perm) if perm
					#hack to pass an array to write and do the right thing
					if args.length == 1 && Array === args.first
						fh.puts(args.first)
					else
						fh.write(*args)
					end
					yield fh if block_given?
				end
			end

			def components
				each_filename.to_a
			end
			def depth
				each_filename.count
			end

			def entries(filter: true)
				c=super()
				if filter
					c.reject {|c| c.to_s=="." or c.to_s==".."}
				else
					c
				end
			end

			#Pathname.new("foo")+"bar" return "foo/bar"
			#Pathname.new("foo").append_name("bar") return "foobar"
			def append_name(*args,join:'')
				Pathname.new(self.to_s+args.join(join))
			end

			#loop until we get a name satisfying cond
			def new_name(cond)
				loop.with_index do |_,ind|
					n=self.class.new(yield(self,ind))
					return n if cond.call(n)
				end
			end
			#find a non existing filename
			def nonexisting_name
				return self unless self.may_exist?
				new_name(Proc.new {|f| !f.may_exist?}) do |old_name, ind|
					old_name.append_name("%02d" % ind)
				end
			end

			#stolen from ptools (https://github.com/djberg96/ptools/blob/master/lib/ptools.rb)
			def binary?
				return false if directory?
				bytes = stat.blksize
				bytes = 4096 if bytes > 4096
				s = read(bytes, bytes) || ""
				#s = s.encode('US-ASCII', :undef => :replace).split(//)
				s=s.split(//)
				((s.size - s.grep(" ".."~").size) / s.size.to_f) > 0.30
			end

			#return true if the file is a text
			def text?
				#!! %x/file #{self.to_s}/.match(/text/)
				return false if directory?
				!binary?
			end

			def readbin(*args)
				open("rb").read(*args)
			end

			#taken from facets/split_all
			def split_all
				head, tail = split
				return [tail] if head.to_s == '.' || tail.to_s == '/'
				return [head, tail] if head.to_s == '/'
				return head.split_all + [tail]
			end

			def backup(suffix: '.old', overwrite: true)
				if self.exist?
					filebk=self.append_name(suffix)
					filebk=nonexisting_name if filebk.exist? and !overwrite
					logger.debug "Backup #{self} -> #{filebk}" if respond_to?(:logger)
					FileUtils.mv(self,filebk)
				end
			end

			def abs_path(base: self.class.pwd, mode: :clean)
				f= absolute? ? self : base+self
				case mode
				when :clean
					f.cleanpath
				when :clean_sym
					f.cleanpath(consider_symlink: true)
				when :real
					f.realpath
				when :realdir
					f.realdirpath
				else
					f
				end
			end

			def rel_path(base: self.class.pwd, checkdir: false)
				base=base.dirname unless base.directory? if checkdir
				relative_path_from(base)
			rescue ArgumentError => e
				warn "#{self}.relative_path_from(#{base}): #{e}"
				self
			end

			#call abs_path or rel_path according to :mode
			def convert_path(base: self.class.pwd, mode: :clean, checkdir: false)
				case mode
				when :clean
					cleanpath
				when :clean_sym
					cleanpath(consider_symlink: true)
				when :rel
					rel_path(base: base, checkdir: checkdir)
				when :relative
					rel_path(base: base, checkdir: checkdir) unless self.relative?
				when :absolute,:abs
					abs_path(base: base, mode: :abs)
				when :abs_clean
					abs_path(base: base, mode: :clean)
				when :abs_cleansym
					abs_path(base: base, mode: :cleansym)
				when :abs_real
					abs_path(base: base, mode: :real)
				when :abs_realdir
					abs_path(base: base, mode: :realdir)
				else
					self
				end
			end

			#path from self to target (warning: we always assume that we are one
			#level up self, except if inside is true)
			# bar=SH::Pathname.new("foo/bar"); baz=SH::Pathname.new("foo/baz")
			# bar.rel_path_to(baz)  #<ShellHelpers::Pathname:baz>
			# bar.rel_path_to(baz, inside: true) #<ShellHelpers::Pathname:../baz>
			#note: there is no real sense to use mode: :rel here, but we don't
			#prevent it
			def rel_path_to(target=self.class.pwd, base: self.class.pwd, mode: :rel, clean_mode: :abs_clean, inside: false, **opts)
				target=self.class.new(target) unless target.is_a?(self.class)
				sbase=opts[:source_base]||base
				smode=opts[:source_mode]||clean_mode
				tbase=opts[:target_base]||base
				tmode=opts[:target_mode]||clean_mode
				source=self.convert_path(base: sbase, mode: smode)
				target=target.convert_path(base: tbase, mode: tmode)
				from=inside ? source : source.dirname
				target.convert_path(base: from, mode: mode)
			end

			#overwrites Pathname#find
			alias orig_find find
			def find(*args,&b)
				require 'shell_helpers/utils'
				Utils.find(self,*args,&b)
			end

			def glob(pattern, expand: false)
				g=[]
				self.cd { g=Dir.glob(pattern) }
				g=g.map {|f| self+f} if expand
				g
			end

			#follow a symlink
			def follow
				return self unless symlink?
				l=readlink
				if l.relative?
					self.dirname+l
				else
					l
				end
			end

			def dereference(mode=true)
				return self unless mode
				case mode
				when :simple
					return follow if symlink?
				else
					return follow.dereference(mode) if symlink?
				end
				self
			end

			def bad_symlink?
				symlink? and !dereference.exist?
			end

			def hidden?
				#without abs_path '.' is considered as hidden
				abs_path.basename.to_s[0]=="."
			end

			#remove all empty directories inside self
			#this includes directories which only include empty directories
			def rm_empty_dirs(rm:true)
				r=[]
				if directory?
					find(depth:true) do |file|
						if file.directory? and file.children(false).empty?
							r<<file
							file.rmdir if rm
						end
					end
				end
				r
			end

			def rm_bad_symlinks(rm:false,hidden:false)
				r=[]
				if directory?
					filter=if hidden
							->(x,_) {x.hidden?}
						else
							->(*x) {false}
						end
					find(filter:filter) do |file|
						if file.bad_symlink?
							r<<file
							file.rm if rm
						end
					end
				end
				r
			end

			#calls an external program
			def call(prog,*args,pos: :last,full:false,**opts)
				name=to_s
				name=(self.class.pwd+self).to_s if full and relative?
				sh_args=args
				pos=sh_args.length if pos==:last
				sh_args[pos,0]=name
				Sh.sh(prog,*sh_args,**opts)
			end

			def chattr(*args,**opts)
				call("chattr",*args,**opts)
			end

			def sudo_mkdir
				Sh.sh("mkdir -p #{shellescape}", sudo: true)
			end
			def sudo_mkpath
				Sh.sh("mkdir -p #{shellescape}", sudo: true)
			end
		end

		module FUClass
			attr_writer :fu_class
			def fu_class
				@fu_class||=::FileUtils
			end
		end
		def self.included(base)
			base.extend(FUClass)
		end

		module FileUtilsWrapper
			extend FUClass
			#wrapper around FileUtils
			#For instance Pathname#rmdir uses Dir.rmdir, but the rmdir from FileUtils is a wrapper around Dir.rmdir that accepts extra options
			[:chdir, :rmdir, :mkdir, :cmp, :touch, :rm, :rm_r, :uptodate?, :cmp, :cp,:cp_r,:mv,:ln,:ln_s,:ln_sf].each do |method|
				define_method method do |*args,&b|
					self.class.fu_class.public_send(method,self,*args,&b)
				end
			end
			# for these the path argument goes last
			[:chown, :chown_R].each do |method|
				define_method method do |*args,**opts,&b|
					require 'pry'; binding.pry
					self.class.fu_class.public_send(method,*args,self.to_path,&b)
				end
			end

			# we rewrap chdir this way, so that the argument stays a SH::Pathname
			def chdir(*args)
				self.class.fu_class.public_send(:chdir, self, *args) do |dir|
					yield self.class.new(dir)
				end
			end

			#These methods are of the form FileUtils.chmod paramater, file
			[:chmod, :chmod_R].each do |method|
				define_method method do |*args,&b|
					self.class.fu_class.public_send(method,*args,self,&b)
				end
			end
			#Some alias defined in FileUtils
			alias_method :cd, :chdir
			alias_method :identical?, :cmp

			#We need to inverse the way we call cp, since it is the only way we can
			#mv/cp several files in a directory:
			#		 self.on_cp("file1","file2")
			#Options: preserve noop verbose force
			#Note: if ActionHandler is included, this will overwrite these
			#methods
			[:cp,:cp_r,:mv,:ln,:ln_s,:ln_sf].each do |method|
				define_method :"on_#{method}" do |*files,**opts,&b|
					files.each do |file|
						self.class.fu_class.send(method,file,self,**opts,&b)
					end
				end
			end
			alias_method :on_link, :on_ln
			alias_method :on_symlink, :on_ln_s
		end
		include FileUtilsWrapper

		module ActionHandler
			extend FUClass
			class PathnameError < Exception
				#encapsulate another exception
				attr_accessor :ex
				def initialize(ex=nil)
					@ex=ex
				end
				def to_s
					@ex.to_s
				end
			end

			protected def do_action?(mode: :all, dereference: false, **others)
				path=self.dereference(dereference)
				case mode
				when :none, false
					return false
				when :noclobber
					return false if path.may_exist?
				when :symlink
					return false unless path.symlink?
				when :dangling_symlink
					return false unless path.symlink? && ! self.exist?
				when :file
					return false if path.directory?
				when :dir
					return false unless path.directory?
				end
				true
			end

			RemoveError = Class.new(PathnameError)
			def on_rm(recursive: false, mode: :all, dereference: false, rescue_error: true, **others)
				path=self.dereference(dereference)
				return nil unless path.may_exist?
				if path.do_action?(mode: mode)
					fuopts=others.select {|k,v| [:verbose,:noop,:force].include?(k)}
					if recursive
						#this is only called if both recursive=true and mode=:all or :dir
						logger.debug("rm_r #{self} (#{path}) #{fuopts}") if respond_to?(:logger)
						self.class.fu_class.rm_r(path, **fuopts)
					else
						logger.debug("rm #{self} (#{path}) #{fuopts}") if respond_to?(:logger)
						self.class.fu_class.rm(path, **fuopts)
					end
				else
					puts "\# #{__method__}: Skip #{self} [mode=#{mode}]" if others[:verbose]
				end
			rescue => e
				warn "Error in #{path}.#{__method__}: #{e}"
				raise RemoveError.new(e) unless rescue_error
			end
			def on_rm_r(**opts)
				on_rm(recursive:true,**opts)
			end
			def on_rm_rf(**opts)
				on_rm(recursive:true,force:true,**opts)
			end

			FSError = Class.new(PathnameError)
			[:cp,:cp_r,:mv,:ln,:ln_s,:ln_sf].each do |method|
				define_method :"on_#{method}" do |*files, rescue_error: true,
					dereference: false, mode: :all, rm: nil, mkpath: false, **opts,&b|
					#FileUtils.{cp,mv,ln_s} dereference a target symlink if it points to a
					#directory; the only solution to not dereference it is to remove it
					#before hand
					if dereference==:none and rm.nil?
						dereference=false
						rm=:symlink
					end
					path=self.dereference(dereference)
					if path.do_action?(mode: mode)
						begin
							path.on_rm(mode: rm, rescue_error: false, **opts) if rm
							if mkpath
								path.to_s[-1]=="/" ? path.mkpath : path.dirname.mkpath
							end
							fuopts=opts.reject {|k,v| [:recursive].include?(k)}
							logger.debug("#{method} #{self} -> #{files.join(' ')} #{fuopts}") if respond_to?(:logger)
							files.each do |file|
								self.class.fu_class.send(method,file,path,**fuopts,&b)
							end
						rescue RemoveError
							raise unless rescue_error
						rescue => e
							warn "Error in #{self}.#{__method__}(#{files}): #{e}"
							raise FSError.new(e) unless rescue_error
						end
					else
						puts "\# #{__method__}: Skip #{path} [mode=#{mode}]" if opts[:verbose]
					end
				end
			end
			alias_method :on_link, :on_ln
			alias_method :on_symlink, :on_ln_s

			#Pathname.new("foo").squel("bar/baz", action: :on_ln_s)
			#will create a symlink foo/bar/baz -> ../../bar/baz
			def squel(target, base: self.class.pwd, action: nil, rel_path_opts: {}, mkpath: false, **opts)
				target=self.class.new(target)
				out=self+base.rel_path_to(target, inside: true)
				out.dirname.mkpath if mkpath
				rel_path=out.rel_path_to(target, **rel_path_opts)
				#rel_path is the path from out to target
				out.public_send(action, rel_path,**opts) if action
				yield(out,rel_path, target: target, orig: self, **opts) if block_given?
			end

			def squel_dir(target, action: nil, **opts)
				target=self.class.new(target)
				target.find do |file|
					squel(file,mkpath: opts.fetch(:mkpath,!!action), **opts) do |out,rel_path|
						out.public_send(action, rel_path,**opts) if action and !file.directory?
						yield(out,rel_path, target: file, squel_target: target, orig: self, **opts) if block_given?
					end
				end
			end
			#Example: symlink all files in a directory into another, while
			#preserving the structure
			#Pathname.new("foo").squel_dir("bar',action: :on_ln_s)
			#Remove these symlinks:
			#SH::Pathname.new("foo").squel_dir("bar") {|o,t| o.on_rm(mode: :symlink)}

			#add the relative path to target in the symlink
			#Pathname.new("foo/bar").rel_ln_s(Pathname.new("baz/toto"))
			#makes a symlink foo/bar -> ../baz/toto
			#this is similar to 'ln -rs ...' from coreutils
			def rel_ln_s(target)
				on_ln_s(rel_path_to(target))
			end
		end
		include ActionHandler
	end

	#to affect the original ::Pathname, just include PathnameExt there
	class Pathname < PathnameExt::Base
		include PathnameExt
	end
	#an alternative to use Pathname::Verbose explicitly is to use
	#Pathname.fu_class=FileUtils::Verbose
	class Pathname::Verbose < Pathname
		@fu_class=FileUtils::Verbose
	end
	class Pathname::NoWrite < Pathname
		@fu_class=FileUtils::NoWrite
	end
	class Pathname::DryRun < Pathname
		@fu_class=FileUtils::DryRun
	end
end

=begin
pry
load "dr/sh.rb"
ploum=SH::Pathname.new("ploum")
plim=SH::Pathname.new("plim")
plam=SH::Pathname.new("plam")
plim.on_cp_r(ploum, mode: :symlink, verbose: true)
plim.on_cp_r(ploum, mode: :file, verbose: true)
plim.on_cp_r(ploum, mode: :file, rm: :file, verbose: true)
=end
