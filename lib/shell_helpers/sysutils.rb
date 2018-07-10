require 'shell_helpers/export'
require 'shell_helpers/sh'
require 'shell_helpers/pathname'
require 'shellwords'

module ShellHelpers

	module SysUtils
		extend self

		# output should be the result of `blkid -o export ...`
		# return a list of things like
		#  {:devname=>"/dev/sda2",
		#   :label=>"swap",
  	#   :uuid=>"82af0d2f-5ef6-418a-8656-bdfe843f19e1",
  	#   :type=>"swap",
  	#   :partlabel=>"swap",
  	#   :partuuid=>"f4eef373-0803-4701-bd47-b968c44065a6"}

		def parse_blkid(output)
			devs=[]
			r=[]
			output.each_line do |l|
				l=l.chomp
				if l.empty?
					devs << Export.import_parse(r)
					r=[]
				else
					r<<l
				end
			end
			devs << Export.import_parse(r) unless r.empty?
			devs
		end

		def refresh_blkid_cache
			Sh.sh("sudo blkid")
		end

		def find_devices(props)
			return props[:devname] unless props[:devname].nil?
			# search from most discriminant to less discriminant
			%i(uuid label partuuid partlabel type).each do |key|
				if (label=props[key])
					return parse_blkid(%x/blkid -o export -t #{key.to_s.upcase}=#{label.shellescape}/)
				end
			end
			return []
		end

		def find_device(props)
			devs=find_devices(props)
			devs=yield(devs) if block_given?
			return [devs].flatten.first.fetch(:devname)
		end

		def mount(*paths, mkpath: true, abort_on_error: true)
			paths.each do |path|
				dev=find_device(path)
				options=path[:mntoptions]||[]
				mntpoint=path[:mntpoint]
				Sh.sh("sudo mkdir -p #{mntpoint.shellescape}") if mkpath
				cmd="sudo mount #{options.empty? ? "" : "-o #{options.join(',').shellescape}"} #{dev.shellescape} #{mntpoint.shellescape}"
				abort_on_error ? Sh.sh!(cmd) : Sh.sh(cmd)
			end
		end

		def umount(*paths)
			paths.reverse.each do |path|
				mntpoint=path[:mntpoint]
				Sh.sh("sudo umount #{mntpoint.shellescape}")
			end
		end

		def make_partitions(disk, *partitions)
			opts=[]
			partitions.each do |partition|
				num=partition[:num]&.to_i || 0
				start=partition[:start] || 0
				length=partition[:length] || 0
				name=partition[:name]
				type=partition[:type]
				attributes=partition[:attributes]
				alignment=partition[:alignment]
				case type
				when :boot
					type="ef00"
					attributes=2
				when :swap
					type="8200"
				when :home
					type="8302"
				when :x86_root
					type="8303"
				when :"x86-64_root"
					type="8304"
				when :arm64_root
					type="8305"
				when :arm32_root
					type="8307"
				when :linux
					type="8300"
				end
				opts += ["-n", "#{num}:#{start}:#{length}"]
				opts += ["-c", "#{num}:#{name}"] if name
				opts += ["-t", "#{num}:#{type}"] if type
				opts << "--attributes=#{num}:set:#{attributes}" if attributes
				opts << ["--set-alignment=#{alignment}"] if alignment
			end
			Sh.sh("echo sudo sgdisk #{opts.shelljoin} #{disk.shellescape}")
		end

		def zap_partitions(disk)
			# Zap (destroy) the GPT and MBR data  structures  and  then  exit.
			Sh.sh("sudo sgdisk --zap-all #{disk.shellescape}")
		end
		def wipe(disk)
			# wipe all signatures
			Sh.sh("sudo wipefs -a #{disk.shellescape}")
		end

		def make_raw_image(name, size="1G")
			raw=Pathname.new(name)
			raw.touch
			raw.chattr("+C")
			Sh.sh("fallocate -l #{size} #{raw.shellescape}")
		end
	end
end
