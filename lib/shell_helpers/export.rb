require 'dr/ruby_ext/core_ext' #for Hash#keyed_value
require 'dr/parse/simple_parser'

module ShellHelpers
	module Export
		extend self

		#export a value for SHELL consumption
		def export_value(v)
			case v
				when String
					return v.shellescape
				when Array
					return "(#{v.map {|i| i.to_s.shellescape}.join(' ')})"
				when Hash
					return "(#{v.map {|k,v| k.to_s.shellescape+" "+v.to_s.shellescape}.join(' ')})"
				when nil
					return ""
				when ->(x){x.respond_to?(:to_a)}
					return export_value(v.to_a)
				when ->(x){x.respond_to?(:to_h)}
					return export_value(v.to_h)
				else
					return v.to_s.shellescape
			end
		end
		def import_value(v, type: String, unquote: true)
			#String === String => false
			case type.to_s
			when "String"
				v.gsub!(/\A['"]+|['"]+\Z/, "") if unquote
				v.to_s
			when "Integer"
				v.to_i
			when "Symbol"
				v.to_sym
			when "Array"
				#v is of the form (ploum plam)
				#TODO: handle quotes in the array
				eval "%w#{v}"
			when "Hash"
				import_value(v, type: Array).each_slice(2).to_h
			end
		end

		def escape_name(name, prefix:"", upcase: true)
			name=name.to_s
			name=name.upcase if upcase
			(prefix+name).gsub('/','_')
		end

		#export_variable("ploum","plam") yields ploum="plam"
		def export_variable(name, value, local: false, export: false, prefix:"",upcase:true)
			r=""
			name=escape_name(name,prefix:prefix,upcase:upcase)
			r+="local #{name}\n" if local
			r+="typeset -A #{name}\n" if Hash === value
			r+="#{name}=#{export_value(value)}\n"
			r+="export #{name}\n" if export
			return r
		end

		def import_variable(namevalue, downcase:true, type: :auto)
			namevalue.match(/(local|export)?\s*(\S*)=(.*)$/) do |m|
				_match,_type,name,value=m.to_a
				name=name.downcase if downcase
				if type == :auto
					if value=~/^\(.*\)$/
						value=import_value(value, type: Array)
					else
						value=import_value(value)
					end
				else
					value=import_value(value, type: type)
				end
				return name, value
			end
		end

		#from {ploum: plim} return something like
		#PLOUM=plim
		#that can be evaluated by the shell
		def export_variables(hash, local: false, export: false, prefix:"",upcase:true)
			names=hash.keys.map {|s| escape_name(s,prefix:prefix,upcase:upcase)}
			r=""
			r+="local #{names.join(" ")}\n" if local
			hash.each do |k,v|
				r+=export_variable(k,v,prefix:prefix,upcase:upcase)
			end
			r+="export #{names.join(" ")}\n" if export
			return r
		end

		#export_parse(hash,"name:value")
		#will output name=$(hash[value])
		#special cases: when value = '/' we return the full hash
		#		when value ends by /, we return the splitted hash (and name serves
		#		as a prefix)
		#Ex: Numenor ~ $ ./mine/00COMPUTERS.rb --export=//
		#		 HOSTNAME=Numenor;
		#		 HOSTTYPE=perso;
		#		 HOMEPATH=/home/dams;...
		#		 Numenor ~ $ ./mine/00COMPUTERS.rb --export=syst/
		#		 LAPTOP=true;
		#		 ARCH=i686;...
		#Remark: in name:value, we don't put name in uppercase
		#But in split hash mode, we put the keys in uppercase (to prevent collisions)
		def export_parse(hash,s)
			r=""
			args=DR::SimpleParser.parse_string(s.to_s)
			args[:values].each do |k,v|
				if v
					name=k.to_s
				else
					#no name given
					v=k.to_s
					if v !='/' && v[-1]=='/'
						#in split mode we don't need the name
						name="" 
					else
						#else since no name was given we reuse the variable
						name=v
						name="all" if v=="/"
					end
				end
				if v != '/' && v[-1]=='/'
					all=true
					v=v[0...-1]
				end
				value=hash.keyed_value(v)
				opts=args[:opts][k]
				if all
					r+=export_variables(value, prefix: name, **opts)
				else
					r+=export_variable(name,value, **opts)
				end
			end
			return r
		end

		def import_parse(s, split_on: :auto, var_separator:'/', inline: false)
			r={}
			if split_on == :auto
				split_on=","
				split_on="\n" if s =~ /\n/
			end
			if s.is_a?(Enumerable)
				instructions=s
			else
				instructions=s.split(split_on)
			end
			instructions.each do |namevalue|
				if inline
					name,value=DR::SimpleParser.parse_namevalue(optvalue,sep:'=')
				else
					name,value=import_variable(namevalue)
				end
				r.set_keyed_value(name,value, sep: var_separator)
			end
			r
		end
	end
end
