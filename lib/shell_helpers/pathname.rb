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

			def rm(recursive: false, mode: :file, verbose: true, noop: false, force: false)
				mode.to_s.match(/^recursive-(.*)$/) do |m|
					recursive=true
					mode=m[1].to_sym
				end
				case mode
				when :symlink
					return unless self.symlink?
				when :dangling_symlink
					return unless self.symlink? && ! self.exist?
				end
				if recursive
					FileUtils.rm_r(self, verbose: verbose, noop: noop, force: force)
				else
					FileUtils.rm(self, verbose: verbose, noop: noop, force: force)
				end
			rescue => e
				warn "Error in #{self}.clobber: #{e}"
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
			#wrapper around FileUtils
			#Pathname#rmdir uses Dir.rmdir, but the rmdir from FileUtils is a wrapper
			#around Dir.rmdir that accepts extra options
			#The same for mkdir
			[:chdir, :rmdir, :mkdir, :chmod, :chmod_R, :chown, :chown_R, :cmp, :touch, :rm, :rm_r, :uptodate?, :cmp].each do |method|
				define_method method do |*args,&b|
					klass.send(method,self,*args,&b)
				end
			end
			#Some alias defined in FileUtils
			alias_method :mkdir_p, :mkpath
			alias_method :rm_rf, :rmtree
			alias_method :cd, :chdir
			alias_method :identical?, :cmp

			#We need to inverse the way we call cp, since it is the only way we can
			#mv/cp several files in a directory:
			#    self.cp("file1","file2")
			#Options: preserve noop verbose
			[:cp,:cp_r,:mv,:ln,:ln_s,:ln_sf].each do |method|
				define_method method do |*files,**opts,&b|
					FileUtils.send(method,*files,self,**opts,&b)
				end
			end
			alias_method :link, :ln
			alias_method :symlink, :ln_s
		end
		fileutils_wrapper
	end

end
