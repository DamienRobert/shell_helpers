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
	class Pathname < ::Pathname
		#Some alias defined in FileUtils
		alias_method :mkdir_p, :mkpath
		alias_method :rm_rf, :rmtree

		#these Pathname methods explicitely call Pathname.new so do not respect
		#our subclass :-(
		[:+,:join,:relative_path_from].each do |m|
			define_method m do |*args,&b|
				self.class.new(super(*args,&b))
			end
		end
		alias_method :/, :+

		module InstanceMethods
			def hidden?
				return self.basename.to_s[0]=="."
			end

			def filewrite(*args,mode:"w",perm: nil,mkdir: false)
				logger.debug("Write to #{self}"+ (perm ? " (#{perm})" : "")) if respond_to?(:logger)
				self.dirname.mkpath if mkdir
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

			#Pathname.new("foo")+"bar" return "foo/bar"
			#Pathname.new("foo").append_name("bar") return "foobar"
			def append_name(*args,join:'')
				Pathname.new(self.to_s+args.join(join))
			end

			#loop until we get a name satisfying cond
			def new_name(&cond)
				loop.with_index do |_,ind|
					n=self.class.new(yield(self,ind))
					return n if cond.call(n)
				end
			end
			#find a non existing filename
			def nonexisting_name(&change_method)
				new_name(Proc.new {|f| !f.exist?}, &change_method)
			end

			def backup(suffix: '.old', overwrite: true)
				if self.exist?
					filebk=self.append_name(suffix)
					if filebk.exist? and !overwrite
						filebk=new_name do |old_name, ind|
							old_name.append_name("%02d" % ind)
						end
					end
					logger.debug "Backup #{self} -> #{filebk}" if respond_to?(:logger)
					FileUtils.mv(self,filebk)
				end
			end

			def abs_path(base: Pathname.pwd, mode: :clean)
				f= absolute? ? base+self : self
				case clean
				when :clean
					f.cleanpath
				when :clean_sym
					f.cleanpath(consider_symlink: true)
				when :real
					f.realpath
				when :realdir
					f.realdirpath
				end
			end
			def rel_path(target=Pathname.pwd, base: Pathname.pwd, mode: :clean)
				target=target.abs_path(base: base, mode: mode)
				source=self.abs_path(base: base, mode: mode)
				source.relative_path_from(base)
			end
			#orig_mode, orig_base, target_mode, target_base)
			def convert_path(**opts)
				orig_mode=opts[:orig_mode]||[:mode]
				path=self
				path=path
			end

			#overwrites Pathname#find
			def find(*args,&b)
				require 'dr/sh/utils'
				SH::ShellUtils.find(self,*args,&b)
			end
		end
		include InstanceMethods

		module ClassMethods
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
		end
		extend ClassMethods

		#pass FileUtils::Verbose to active verbosity by default
		def self.fileutils_wrapper(klass=FileUtils)
			Module.new do
				#wrapper around FileUtils
				#For instance Pathname#rmdir uses Dir.rmdir, but the rmdir from FileUtils is a wrapper around Dir.rmdir that accepts extra options
				[:chdir, :rmdir, :mkdir, :chmod, :chmod_R, :chown, :chown_R, :cmp, :touch, :rm, :rm_r, :uptodate?, :cmp, :cp,:cp_r,:mv,:ln,:ln_s,:ln_sf].each do |method|
					define_method method do |*args,&b|
						klass.send(method,self,*args,&b)
					end
				end
				#Some alias defined in FileUtils
				alias_method :cd, :chdir
				alias_method :identical?, :cmp

				#We need to inverse the way we call cp, since it is the only way we can
				#mv/cp several files in a directory:
				#    self.on_cp("file1","file2")
				#Options: preserve noop verbose force
				[:cp,:cp_r,:cp_rf,:mv,:ln,:ln_s,:ln_sf].each do |method|
					define_method :"on_#{method}" do |*files,**opts,&b|
						FileUtils.send(method,*files,self,**opts,&b)
					end
				end
				alias_method :on_link, :on_ln
				alias_method :on_symlink, :on_ln_s
			end
		end
		include fileutils_wrapper

		module ActionHandler
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

			protected def do_action?(mode: :all, dereference: false, **others)
				path=self.dereference(dereference)
				case mode
				when :none, false
					return false
				when :noclobber
					return false if path.exist? || path.symlink?
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
				if path.do_action?(mode: mode)
					fuopts=opts.select {|k,v| [:verbose,:noop,:force].include?(k)}
					if recursive
						#this is only called if both recursive=true and mode=:all or :dir
						FileUtils.rm_r(path, **fuopts)
					else
						FileUtils.rm(path, **fuopts)
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
			[:cp,:cp_r,:cp_rf,:mv,:ln,:ln_s,:ln_sf].each do |method|
				define_method :"on_#{method}" do |*files,rescue_error: true,
					dereference: true, mode: :all, rm: nil, **opts,&b|
					path=self.dereference(dereference)
					if path.do_action?(mode: mode)
						begin
							path.on_rm(mode: rm, rescue_error: false, **opts) if rm
							fuopts=opts.reject {|k,v| [:recursive].include?(k)}
							FileUtils.send(method,*files,path,**fuopts,&b)
						rescue RemoveError
							raise unless rescue_error
						rescue => e
							warn "Error in #{self}.#{__method__}: #{e}"
							raise FSError.new(e) unless rescue_error
						end
					else
						puts "\# #{__method__}: Skip #{path} [mode=#{mode}]" if opts[:verbose]
					end
				end
			end
			alias_method :on_link, :on_ln
			alias_method :on_symlink, :on_ln_s

			#Pathname.new("foo").squel("bar/baz")
			#will create a symlink foo/bar/baz -> ../../bar/baz
			def squel(target,base: self.class.pwd, action: :on_ln_s, **opts)
			end
		end
		include ActionHandler
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
