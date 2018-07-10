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
			return [props[:devname]] unless props[:devname].nil?
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
			return [devs].flatten.first&.fetch(:devname)
		end

		def find_disk_part(disk, props)
			find_device(props) do |devs|
				devs.select {|dev| dev[:devname].start_with?(disk)}
			end
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

		def partition_type(type, mode: :guid)
			case type
			when :boot
				mode == :hexa ? "ef00" : "c12a7328-f81f-11d2-ba4b-00a0c93ec93b"
			when :swap
				mode == :hexa ? "8200" : "0657fd6d-a4ab-43c4-84e5-0933c84b4f4f"
			when :home
				mode == :hexa ? "8302" : "933ac7e1-2eb4-4f13-b844-0e14e2aef915"
			when :x86_root
				mode == :hexa ? "8303" : "44479540-f297-41b2-9af7-d131d5f0458a"
			when :"x86-64_root"
				mode == :hexa ? "8304" : "4f68bce3-e8cd-4db1-96e7-fbcaf984b709"
			when :arm64_root
				mode == :hexa ? "8305" : "b921b045-1df0-41c3-af44-4c6f280d3fae"
			when :arm32_root
				mode == :hexa ? "8307" : "69dad710-2ce4-4e3c-b16c-21a1d49abed3"
			when :linux
				mode == :hexa ? "8300" : "0fc63daf-8483-4772-8e79-3d69d8477de4"
			end
		end

		def make_partitions(disk, *partitions)
			opts=[]
			partitions.each do |partition|
				num=partition[:partnum]&.to_i || 0
				start=partition[:partstart] || 0
				length=partition[:partlength] || 0
				name=partition[:partlabel] || partition[:name]
				attributes=partition[:partattributes]
				type=partition[:parttype]
				attributes=2 if type==:boot
				type=partition_type(type, mode: :hexa) if type.is_a?(Symbol)
				uuid=partition[:partuuid]
				alignment=partition[:partalignment]
				opts += ["-n", "#{num}:#{start}:#{length}"]
				opts += ["-c", "#{num}:#{name}"] if name
				opts += ["-t", "#{num}:#{type}"] if type
				opts += ["-u", "#{num}:#{uuid}"] if uuid
				opts << "--attributes=#{num}:set:#{attributes}" if attributes
				opts << ["--set-alignment=#{alignment}"] if alignment
			end
			Sh.sh!("sudo sgdisk #{opts.shelljoin} #{disk.shellescape}")
		end

		def zap_partitions(disk)
			# Zap (destroy) the GPT and MBR data  structures  and  then  exit.
			Sh.sh("sudo sgdisk --zap-all #{disk.shellescape}")
		end
		def wipe(disk)
			# wipe all signatures
			Sh.sh("sudo wipefs -a #{disk.shellescape}")
		end

		def make_fs(disk, fs)
			fs.each do |partfs|
				dev=SH.find_disk_part(disk, partfs)
				if dev and (fstype=partfs[:fs])
					SH.sh("echo sudo mkfs.#{fstype.shellescape} #{opts.shelljoin} #{dev.shellescape}")
				end
			end
		end

		def make_raw_image(name, size="1G")
			raw=Pathname.new(name)
			raw.touch
			raw.chattr("+C")
			Sh.sh("fallocate -l #{size} #{raw.shellescape}")
		end
	end
end
