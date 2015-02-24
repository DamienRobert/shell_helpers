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

module SH
	#SH::Pathname is Pathname with extra features
	#and methods from FileUtils rather than File when possible
	#to use this module rather than ::Pathname in a module or class,
	#simply define Pathname=SH::Pathname in an appropriate nesting level
	class Pathname < ::Pathname
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
		#write is not the same as filewrite
		#but if given only one argument we should be ok
		unless Pathname.method_defined?(:write)
			alias :write :filewrite
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

		#wrapper around FileUtils
		#Pathname#rmdir uses Dir.rmdir, but the rmdir from FileUtils is a wrapper
		#around Dir.rmdir that accepts extra options
		#The same for mkdir
		[:chdir, :rmdir, :mkdir].each do |method|
			define_method method do |*args,&b|
				FileUtils.send(method,*args,&b)
			end
		end
		#mkpath is already defined (use FileUtils), but not mkdir_p
		#alias mkdir_p mkpath

		#Options: verbose, noop, force
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

		#Options: preserve noop verbose
		def cp(*files,**opts)
			FileUtils.cp(files,self,**opts)
		end
		#Options: force noop verbose
		def mv(*files,**opts)
			FileUtils.mv(files,self,**opts)
		end

		#find already exists
		def dr_find(*args,&b)
			require 'dr/sh/utils'
			SH::ShellUtils.find(self,*args,&b)
		end

		def self.home
			return Pathname.new(Dir.home)
		end
		def self.hometilde
			return Pathname.new('~')
		end
		def self.slash
			return Pathname.new("/")
		end
		#differ from Pathname.pwd in that this returns a relative path
		def self.current
			return Pathname.new(".")
		end
		def self.null
			return Pathname.new('/dev/null')
		end

		#Pathname / 'usr'
		def self./(path)
			new(path)
		end
		#Pathname['/usr']
		def self.[](path)
			new(path)
		end

	end

end
