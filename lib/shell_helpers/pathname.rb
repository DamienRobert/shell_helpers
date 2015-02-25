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

			def backup(suffix: '.old', overwrite: true)
				if self.exist?
					filebk=self.append_name(suffix)
					if filebk.exist? and !overwrite
						num=0
						begin
							filebknum=filebk.append_name("%02d" % num)
							num+=1
						end while filebknum.exist?
						filebk=filebknum
					end
					logger.debug "Backup #{self} -> #{filebk}" if respond_to?(:logger)
					FileUtils.mv(self,filebk)
				end
			end

			def abs_path(base: Pathname.pwd, mode: :clean)
				f=base+self
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
				#Options: preserve noop verbose
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

		module RemovalHandler
			RemoveError = Class.new(Exception)
			def on_rm(recursive: false, mode: :file, dereference: false, rescue_error: false, verbose: true, noop: false, force: false)
				mode.to_s.match(/^recursive-(.*)$/) do |m|
					recursive=true
					mode=m[1].to_sym
				end
				mode.to_s.match(/^(.*)-force$/) do |m|
					force=true
					mode=m[1].to_sym
				end
				path=self
				path=path.readlink if dereference && path.symlink?
				case mode
				when :noclobber
					return false if path.exist? || path.symlink?
				when :symlink
					return false unless path.symlink?
				when :dangling_symlink
					return false unless path.symlink? && ! self.exist?
				when :file
					return false if path.directory?
				end
				if recursive
					FileUtils.rm_r(path, verbose: verbose, noop: noop, force: force)
				else
					FileUtils.rm(path, verbose: verbose, noop: noop, force: force)
				end
			rescue => e
				warn "Error in #{self}.#{__method__}: #{e}"
				raise unless rescue_error
			end

			#activates magic on_rm on these methods
			[:cp,:cp_r,:cp_rf,:mv,:ln,:ln_s,:ln_sf].each do |method|
				define_method :"on_#{method}" do |*files,rescue_error: true,**opts,&b|
					begin
						if opts.key?(:mode)
							r=on_rm(rescue_error: false, **opts) 
							return r unless r
						end
						#Options: preserve noop verbose
						fuopts=opts.select {|k,v| [:preserve,:noop,:verbose].include?(k)}
						p *files,self,**fuopts
						super(*files,self,**fuopts,&b)
					rescue => e
						warn "Error in #{self}.#{__method__}: #{e}"
						raise unless rescue_error
					end
				end
			end
		end
		include RemovalHandler
	end
end

=begin
load "dr/sh.rb"
ploum=SH::Pathname.new("ploum")
plim=SH::Pathname.new("plim")
plam=SH::Pathname.new("plam")
plim.on_cp_r(ploum, mode: :symlink)
plim.on_cp_r(ploum, mode: :file)
=end
