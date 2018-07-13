require 'shell_helpers/export'
require 'shell_helpers/sh'
require 'shell_helpers/pathname'
require 'shellwords'

module ShellHelpers

	module SysUtils
		extend self
		SysError=Class.new(StandardError)

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

		def blkid(*args, sudo: false)
			# get devname, (part)label/uuid, fstype
			fsoptions,_suc=Run.run_simple("blkid -o export #{args.shelljoin}", fail_mode: :empty, chomp: true, sudo: sudo)
			parse_blkid(fsoptions)
		end

		# use lsblk to get infos about devices
		def lsblk(sudo: false)
			# get devname, mountpoint, (part)label/uuid, (part/dev/fs)type
			fsoptions,_suc=Run.run_simple("lsblk -l -J -o NAME,MOUNTPOINT,LABEL,UUID,PARTLABEL,PARTUUID,PARTTYPE,TYPE,FSTYPE", fail_mode: :empty, chomp: true, sudo: sudo)
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

		# use findmnt to get infos about mount points
		def findmnt(sudo: false)
			# get devname, mountpoint, mountoptions, (part)label/uuid, fsroot
			# only looks at mounted devices (but in comparison to lsblk also show
			# virtual mounts and bind mounts)
			fsoptions,_suc=SH::Run.run_simple("findmnt --raw -o SOURCE,TARGET,FSTYPE,OPTIONS,LABEL,UUID,PARTLABEL,PARTUUID,FSROOT", fail_mode: :empty, chomp: true, sudo: sudo)
			fs={}
			fsoptions.each_line.to_a[1..-1]&.each do |l|
				#two '	' means a missing option, so we want to split on / /, not on ' '
				source,target,fstype,options,label,uuid,partlabel,partuuid,fsroot=l.chomp.split(/ /)
				next unless source=~%r(^/dev/) #skip non dev mountpoints
				options=options.split(',')
				fs[source]={mountpoint: target, devname: source, fstype: fstype, mountoptions: options, label: label, uuid: uuid, partlabel: partlabel, partuuid: partuuid, fsroot: fsroot}
			end
			fs
		end
		
		def fs_infos(mode: :devices)
			return findmnt if mode == :mount
			return lsblk.merge(findmnt) if mode == :all
			# :devname, :devtype, :mountpoint, [:mountoptions], :label, :uuid, :partlabel, :partuuid, :parttype, :fstype, [:fsroot]
			lsblk
		end

		def refresh_blkid_cache
			Sh.sh("sudo blkid")
		end

		def find_devices(props, method: :all)
			props=props.clone
			return [props[:devname]] unless props[:devname].nil?
			# name is both for label and partlabel
			if props.key?(:name)
				props[:label] = props[:name] unless props.key?(:label)
				props[:partlabel] = props[:name] unless props.key?(:partlabel)
			end

			if method==:blkid
				# Warning, since 'blkid' can only test one label, we cannot check
				# that all parameters are valid
				# search from most discriminant to less discriminant
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
						# the fsinfos should also have one of this parameter defined
						next false unless %i(uuid label partuuid partlabel parttype).any? {|k| fsprops[k]}
						!ptype or !fsprops[key] or ptype==fsprops[key]
					end
				end.map {|k| fs[k]}
			end
			return []
		end

		def find_device(props)
			devs=find_devices(props)
			devs=yield(devs) if block_given?
			devs=[devs].flatten
			warn "Device #{props} not found" if devs.empty?
			warn "Several devices for #{props} found: #{devs.map {|d| d&.fetch(:devname)}}" if devs.length >1
			return devs.first&.fetch(:devname)
		end

		def mount(paths, mkpath: true, abort_on_error: true, sort: true)
			paths=paths.values if paths.is_a?(Hash)
			paths=paths.select {|p| p[:mountpoint]}
			# sort so that the mounts are in correct order
			paths=paths.sort { |p1, p2| Pathname.new(p1[:mountpoint]) <=> Pathname.new(p2[:mountpoint]) } if sort
			close=lambda do
				umount(paths, sort: sort)
			end
			paths.each do |path|
				dev=find_device(path)
				raise SysError.new("Device #{path} not found") unless dev
				options=path[:mountoptions]||[]
				options<<"subvol=#{path[:subvol].shellescape}" if path[:subvol]
				mntpoint=Pathname.new(path[:mountpoint])
				mntpoint.sudo_mkpath if mkpath
				cmd="mount #{(fs=path[:fstype]) && "-t #{fs.shellescape}"} #{options.empty? ? "" : "-o #{options.join(',').shellescape}"} #{dev.shellescape} #{mntpoint.shellescape}"
				abort_on_error ? Sh.sh!(cmd, sudo: true) : Sh.sh(cmd, sudo: true)
			end
			if block_given?
				begin
					yield paths
				ensure
					close.call
				end
			end
			return paths, close
		end

		def umount(paths, sort: true)
			paths=paths.values if paths.is_a?(Hash)
			paths=paths.select {|p| p[:mountpoint]}
			paths=paths.sort { |p1, p2| Pathname.new(p1[:mountpoint]) <=> Pathname.new(p2[:mountpoint]) } if sort
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

		#options: check => check that no partitions exist first
		def make_partitions(partitions, check: true, partprobe: true)
			partitions=partitions.values if partitions.is_a?(Hash)
			done=[]
			disk_partitions=partitions.group_by {|p| p[:disk]}
			disk_partitions.each do |disk, dpartitions|
				next if disk.nil?
				if check
					partinfos=blkid(disk, sudo: true)
					# gpt partitions: PTUUID="652121ab-7935-403c-8b87-65a149a415ac" PTTYPE="gpt"
					# dos partitions: PTUUID="17a4a006" PTTYPE="dos"
					# others: PTTYPE="PMBR"
					unless partinfos.empty?
						raise SysError("Disk #{disk} is not empty: #{partinfos}") if check==:raise
						warn "Disk #{disk} is not empty: #{partinfos}, skipping..."
						next
					end
				end
				opts=[]
				dpartitions.each do |partition|
					next unless %i(partnum partstart partlength partlabel partattributes parttype).any? {|k| partition.key?(k)}
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
				Sh.sh!("sgdisk #{opts.shelljoin} #{disk.shellescape}", sudo: true)
				done << disk
			end
			SH.sh("partprobe #{done.shelljoin}", sudo: true) unless done.empty? or !partprobe
			done
		end

		def zap_partitions(disk)
			# Zap (destroy) the GPT and MBR data  structures  and  then  exit.
			Sh.sh("sgdisk --zap-all #{disk.shellescape}", sudo: true)
		end
		def wipefs(disk)
			# wipe all signatures
			Sh.sh("wipefs -a #{disk.shellescape}", sudo: true)
		end

		def make_fs(fs, check: true)
			fs=fs.values if fs.is_a?(Hash)
			fs.each do |partfs|
				dev=SH.find_device(partfs)
				if dev and (fstype=partfs[:fstype])
					opts=partfs[:fsoptions]||[]
					bin="mkfs.#{fstype.to_s.shellescape}"
					bin="mkswap" if fstype.to_s=="swap"
					label=partfs[:label]||partfs[:name]
					if label
						labelkey="-L"
						labelkey="-n" if fstype.to_s=="vfat"
						opts+=[labelkey, label]
					end
					if check
						diskinfos=blkid(dev, sudo: true)
						unless diskinfos.dig(dev,:fstype).nil?
							raise SysError("Device #{dev} already has a filesystem: #{diskinfos[dev]}") if check==:raise
							warn "Device #{dev} already has a filesystem: #{diskinfos[dev]}"
							next
						end
					end
					SH.sh("#{bin} #{opts.shelljoin} #{dev.shellescape}", sudo: true)
				end
			end
		end

		def make_raw_image(name, size="1G")
			raw=Pathname.new(name)
			raw.touch
			raw.chattr("+C")
			Sh.sh("fallocate -l #{size} #{raw.shellescape}")
			raw
		end

		def losetup(img)
			disk,_status=SH.run_simple("losetup -f --show #{img.shellescape}", sudo: true, chomp: true)
			close=lambda do
				SH.sh("losetup -d #{disk.shellescape}", sudo: true)
			end
			if block_given?
				begin
					yield disk
				ensure
					close.call
				end
			end
			return disk, close
		end
	end
end
