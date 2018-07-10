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
			devs={}
			r=[]
			convert=lambda do |h|
				h[:type] && h[:fstype]=h.delete(:type)
				name=h[:devname]
				devs[name]=h
			end
			output=output.each_line if output.is_a?(String)
			output.each do |l|
				l=l.chomp
				if l.empty?
					convert.(Export.import_parse(r))
					r=[]
				else
					r<<l
				end
			end
			convert.(Export.import_parse(r)) unless r.empty?
			devs
		end

		def blkid
			fsoptions,_suc=Run.run_simple("blkid -o export", fail_mode: :empty, chomp: true)
			parse_blkid(fsoptions)
		end

		def lsblk
			fsoptions,_suc=Run.run_simple("lsblk -l -J -o NAME,MOUNTPOINT,LABEL,UUID,PARTLABEL,PARTUUID,PARTTYPE,TYPE,FSTYPE", fail_mode: :empty, chomp: true)
			require 'json'
			json=JSON.parse(fsoptions)
			fs={}
			json["blockdevices"]&.each do |props|
				r={}
				props.each do |k,v|
					k=k.to_sym
					k=:devtype if k==:type
					if k==:name
						k=:devname
						v="/dev/#{v}"
					end
					r[k]=v unless v.nil?
				end
				fs[r[:devname]]=r
			end
			fs
		end

		def findmnt
			fsoptions,_suc=SH::Run.run_simple("findmnt --raw -o SOURCE,TARGET,FSTYPE,OPTIONS,LABEL,UUID,PARTLABEL,PARTUUID,FSROOT", fail_mode: :empty, chomp: true)
			fs={}
			fsoptions.each_line.to_a[1..-1]&.each do |l|
				#two '	' means a missing option, so we want to split on / /, not on ' '
				source,target,fstype,options,label,uuid,partlabel,partuuid,fsroot=l.chomp.split(/ /)
				next unless source=~%r(^/dev/) #skip non dev mountpoints
				options=options.split(',')
				fs[source]={mountpoint: target, devname: source, type: fstype, mountoptions: options, label: label, uuid: uuid, partlabel: partlabel, partuuid: partuuid, fsroot: fsroot}
			end
			fs
		end
		
		def fs_infos
			blkid.merge(findmnt).merge(lsblk)
		end

		def refresh_blkid_cache
			Sh.sh("sudo blkid")
		end

		def find_devices(props, method: :all)
			return [props[:devname]] unless props[:devname].nil?
			# search from most discriminant to less discriminant
			if method==:blkid
				# Warning, since 'blkid' can only test one label, we cannot check
				# that all parameters are valid
				%i(uuid label partuuid partlabel).each do |key|
					if (label=props[key])
						return parse_blkid(%x/blkid -o export -t #{key.to_s.upcase}=#{label.shellescape}/).values
					end
				end
				# unfortunately `blkid PARTTYPE=...` does not work, so we need to parse
				# ourselves
				if props[:parttype]
					find_devices(props, method: :all)
				end
			else
				fs=fs_infos
				# here we check all parameters
				# however, if none are defined, this return true, so we check that at least one is defined
				return [] unless %i(uuid label partuuid partlabel parttype).any? {|k| props[k]}
				return fs.keys.select do |k|
					fsprops=fs[k]
					next false if (disk=props[:disk]) && !fsprops[:devname].start_with?(disk)
					%i(uuid label partuuid partlabel parttype).all? do |key|
						ptype=props[key]
						ptype=partition_type(ptype) if key==:parttype and ptype.is_a?(Symbol)
						!ptype or ptype==fsprops[key]
					end
				end.map {|k| fs[k]}
			end
			return []
		end

		def find_device(props)
			devs=find_devices(props)
			devs=yield(devs) if block_given?
			return [devs].flatten.first&.fetch(:devname)
		end

		def mount(paths, mkpath: true, abort_on_error: true)
			paths=paths.values if paths.is_a?(Hash)
			paths.each do |path|
				dev=find_device(path)
				options=path[:mountoptions]||[]
				mntpoint=path[:mountpoint]
				Sh.sh("sudo mkdir -p #{mntpoint.shellescape}") if mkpath
				cmd="sudo mount #{options.empty? ? "" : "-o #{options.join(',').shellescape}"} #{dev.shellescape} #{mntpoint.shellescape}"
				abort_on_error ? Sh.sh!(cmd) : Sh.sh(cmd)
			end
		end

		def umount(paths)
			paths=paths.values if paths.is_a?(Hash)
			paths.reverse.each do |path|
				mntpoint=path[:mountpoint]
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

		def make_partitions(partitions)
			opts=[]
			partitions=partitions.values if partitions.is_a?(Hash)
			disk_partitions=partitions.group_by {|p| p[:disk]}
			disk_partitions.each do |disk, dpartitions|
				next if disk.nil?
				dpartitions.each do |partition|
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
			disk_partitions
		end

		def zap_partitions(disk)
			# Zap (destroy) the GPT and MBR data  structures  and  then  exit.
			Sh.sh("sudo sgdisk --zap-all #{disk.shellescape}")
		end
		def wipe(disk)
			# wipe all signatures
			Sh.sh("sudo wipefs -a #{disk.shellescape}")
		end

		def make_fs(fs)
			fs.each do |partfs|
				dev=SH.find_disk_part(partfs)
				if dev and (fstype=partfs[:fstype])
					opts=partfs[:fsoptions]||[]
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
