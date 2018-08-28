require 'shell_helpers/export'
require 'shell_helpers/sh'
require 'shell_helpers/pathname'
require 'shellwords'

module ShellHelpers

	module SysUtils
		extend self
		SysError=Class.new(StandardError)

		# wrap 'stat'
		def stat_file(file)
			require 'time'
			opts=%w(a b B f F g G h i m n N o s u U w x y z)
			stats,_suc=Run.run_simple("stat --format='#{opts.map{|o| "%#{o}\n"}.join}' #{file.shellescape}")
			stats=stats.each_line.map {|l| l.chomp}
			r={}
			r[:access]=stats[0]
			r[:blocknumber]=stats[1].to_i
			r[:blocksize]=stats[2].to_i
			r[:rawmode]=stats[3]
			r[:filetype]=stats[4]
			r[:gid]=stats[5].to_i
			r[:group]=stats[6]
			r[:hardlinks]=stats[7].to_i
			r[:inode]=stats[8].to_i
			r[:mountpoint]=stats[9]
			r[:filename]=stats[10]
			r[:quotedfilename]=stats[11]
			r[:optimalsize]=stats[12]
			r[:size]=stats[13].to_i
			r[:uid]=stats[14].to_i
			r[:user]=stats[15]
			r[:birthtime]  = begin Time.parse(stats[16]) rescue nil end
			r[:accesstime] = begin Time.parse(stats[17]) rescue nil end
			r[:changedtime]= begin Time.parse(stats[18]) rescue nil end
			r[:statustime] = begin Time.parse(stats[19]) rescue nil end
			r
		end
		# wrap stat --file-system
		def stat_filesystem(file, up: true)
			if up
				file=Pathname.new(file)
				file.ascend.each do |f|
					return stat_filesystem(f, up: false) if f.exist?
				end
			end
			opts=%w(a b c d f i l n s S T)
			stats,_suc=Run.run_simple("stat --file-system --format='#{opts.map{|o| "%#{o}\n"}.join}' #{file.shellescape}")
			stats=stats.each_line.map {|l| l.chomp}
			r={}
			r[:userfreeblocks]=stats[0].to_i
			r[:totalblocks]=stats[1].to_i
			r[:totalnodes]=stats[2].to_i
			r[:freenodes]=stats[3].to_i
			r[:freeblocks]=stats[4].to_i
			r[:fsid]=stats[5]
			r[:maxlength]=stats[6].to_i
			r[:name]=stats[7]
			r[:blocksize]=stats[8].to_i
			r[:innerblocksize]=stats[9].to_i
			r[:fstype]=stats[10]
			r
		end

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

		# output should be the result of `blkid -o export ...`
		# return a list of things like
		#  {:devname=>"/dev/sda2",
		#   :label=>"swap",
		#   :uuid=>"82af0d2f-5ef6-418a-8656-bdfe843f19e1",
		#   :type=>"swap",
		#   :partlabel=>"swap",
		#   :partuuid=>"f4eef373-0803-4701-bd47-b968c44065a6"}
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
			Sh.sh("blkid", sudo: true)
		end

		# find devices matching props
		def find_devices(props, method: :all)
			props=props.clone
			return [{devname: props[:devname]}] unless props[:devname].nil?
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
					# the fsinfos should have one of this parameters defined
					next false unless %i(uuid label partuuid partlabel parttype).any? {|k| fsprops[k]}
					next false if (disk=props[:disk]) && !fsprops[:devname].start_with?(disk.to_s)
					%i(uuid label partuuid partlabel parttype).all? do |key|
						ptype=props[key]
						ptype=partition_type(ptype) if key==:parttype and ptype.is_a?(Symbol)
						!ptype or !fsprops[key] or ptype==fsprops[key]
					end
				end.map {|k| fs[k]}
			end
			return []
		end

		# like find_devices but warn out if the result is of length > 1
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
				options=options.split(',') if options.is_a?(String)
				options<<"subvol=#{path[:subvol].shellescape}" if path[:subvol]
				#options=options.join(',') if options.is_a?(Array)
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
				Sh.sh("umount #{mntpoint.shellescape}", sudo: true)
			end
		end

		def partition_type(type, mode: :guid)
			if mode==:symbol
				%i(boot swap home x86_root x86-64_root arm64_root arm32_root linux).each do |symb|
					%i(hexa guid).each do |mode|
						partition_type(symb, mode: mode) == type.downcase and return symb
					end
				end
			end
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

		def partition_infos(device, sudo: false)
			parts, suc=Run.run_simple("partx -o NR --show #{device.shellescape}", sudo: sudo)
			return nil unless suc
			infos=[]
			nums=parts.each_line.count - 1
			(1..nums).each do |i|
				infos[i-1]={}
				part_options,suc=Run.run_simple("sgdisk -i#{i} #{device.shellescape}", chomp: true, sudo: sudo)
				part_options.match(/^Partition name: '(.*)'/) do |m|
					infos[i-1][:partlabel]=m[1]
				end
				part_options.match(/^Attribute flags: (.*)/) do |m|
					infos[i-1][:partattributes]=m[1]
				end
				part_options.match(/^Partition unique GUID: (.*)/) do |m|
					infos[i-1][:partuuid]=m[1].downcase
				end
				part_options.match(/^Partition GUID code: (\S*)/) do |m|
					infos[i-1][:parttype]=m[1].downcase
				end
			end
			infos
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
				unless opts.empty?
					Sh.sh!("sgdisk #{opts.shelljoin} #{disk.shellescape}", sudo: true)
					done << disk
				end
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
			rawfs=stat_filesystem(raw)
			raw.chattr("+C") if rawfs[:fstype]=="btrfs"
			Sh.sh("fallocate -l #{size} #{raw.shellescape}")
			raw
		end

		def make_btrfs_subvolume(dir, check: true)
			if check and dir.directory?
				raise SysError("Subvolume already exists at #{dir}") if check==:raise
				warn "Subvolume already exists at #{dir}, skipping..."
			else
				SH.sh("btrfs subvolume create #{dir.shellescape}", sudo: true)
				dir
			end
		end
		def make_dir_or_subvolume(dir)
			dir=Pathname.new(dir)
			return :directory if dir.directory?
			fstype=stat_filesystem(dir, up: true)
			if fstype[:fstype]=="btrfs"
				make_btrfs_subvolume(dir)
				return :subvol
			else
				dir.sudo_mkpath
				return :directory
			end
		end

		def losetup(img)
			disk,status=SH.run_simple("losetup -f --show #{img.shellescape}", sudo: true, chomp: true)
			disk=nil unless status
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
