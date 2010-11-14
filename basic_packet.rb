class IO
	def read_java_string
		len=read(2).unpack("n")[0]
		read(len)
	end
end
class String
	def to_java_string
		[self.length].pack("n")+self
	end
end
require 'minecraft_units.rb'

module Packet

	:client_to_server
	:server_to_client
	BOTH=[:client_to_server,:server_to_client]

	class BasicPacket
		class << self
			attr_reader :tag, :directions, :my_attributes
			def warnnew
				STDERR.puts "warning, the packet #{this.name} is still not yet fully understood"
			
			#it's kind of ugly, but it allows fancy meta-programming in the class definitions, while still allowing reading.
			def tag(*args); args.empty? ? @tag : @tag=args[0]; end
			def directions(*args); args.empty? ? @directions : @directions=args[0]; end
			def default_initializer(attr_array)
				#attr_hash will be an array of [:attr,{:default=>,:internal_type=>}] tuples or simple :attrs
				#I don't like using eval, but I want enforced arity, and I don't see how to do that with a 'raw' define_method.
				#pp attr_array DEBUG
				method_arg_names = attr_array.map do |x| 
					if x.is_a?(Array)
						if x[1][:default]
							temp="_#{x[0].to_s}=#{x[1][:default]}"
							temp += ".#{INTERNAL_TYPE_METHODS[x[1][:internal_type]]}" if x[1][:internal_type]
							temp
						else
							"_#{x[0].to_s}"
						end
					else
						"_"+x.to_s
					end
				end*','
				instance_var_names=attr_array.map {|x| "@"+(x.is_a?(Array) ? x[0] : x).to_s}*','
				set_names = attr_array.map do |x| 
					"_"+if x.is_a?(Array)
						temp = x[0].to_s
						temp += ".#{INTERNAL_TYPE_METHODS[x[1][:internal_type]]}" if x[1][:internal_type]
						temp
					else
						x.to_s
					end
				end*','
				class_eval("def initialize(#{method_arg_names}); #{instance_var_names}=#{set_names}; end")
			end
			
			#attributes will be an array of [name,packettype,internal_type] tuples
			#it MUST be an array or some ordered list, so it can be read and written properly.
			#internal_type can be nil, meaning it has no internal enforcement
			
			PACKET_ATTR_TYPES={
				:byte=>{:format=>"C",:len=>1},
				:short=>{:format=>"n",:len=>2,:signed_format=>"s"},
				:int=>{:format=>"N",:len=>4,:signed_format=>"L"},
				:long=>{:format=>"q",:len=>8}, #NOTE: this in in native order, not network order.
					#there must be a better way in ruby to convert native<=>network, without having a bunch of platform detecting code.
					#maybe I'll just do platform detecting code...
				:float=>{:format=>"g",:len=>4},
				:double=>{:format=>"G",:len=>8},
				:bool=>{:format=>"C",:len=>1},
				:string=>nil}
			INTERNAL_TYPE_METHODS={
				:rotation_in_degrees=>"to_rotation_in_degrees",
				:rotation_in_byte=>"to_rotation_in_byte_fraction",
				:block_len=>"to_block_length",
				:abs_len=>"to_abs_length",
				:chunk_len=>"to_chunk_length"
			}
			INTERNAL_TYPE_CLASSES={
				:rotation_in_degrees=>Units::RotationInDegrees,
				:rotation_in_byte=>Units::RotationInByteFraction,
				:block_len=>Units::BlockLength,
				:abs_len=>Units::AbsLength,
				:chunk_len=>Units::ChunkLength
			}
			def attributes(attr_array)
				#do the whole packet class in one easy method!
				
				@my_attributes=attr_array
				
				#1st important method- read from socket
				 (class << self; self; end).send(:define_method,:read_from_socket) do |s|
				 	new_instance=self.allocate
					@my_attributes.each do |attribute,packettype,internal_type|
						if (packettype==:string)
							len=s.read(2).unpack("n")[0]
							temp = s.read(len)
						else
							f=PACKET_ATTR_TYPES[packettype]
							temp = s.read(f[:len]).unpack(f[:format])[0]
							temp = [temp].pack(f[:signed_format]).unpack(f[:signed_format])[0] if f[:signed_format]
						end
						temp = INTERNAL_TYPE_CLASSES[internal_type].new(temp) if (internal_type)
						new_instance.instance_variable_set("@"+attribute.to_s,temp)
					end
					new_instance
				end
				
				#2nd important method - to_s
				define_method(:to_s) do
					out=[self.class.instance_variable_get("@tag")].pack("C")
					self.class.my_attributes.each do |attribute,packettype,internal_type|
						val=instance_variable_get("@"+attribute.to_s)
						out << if (packettype==:string)
							val.to_java_string
						else
							[val].pack(PACKET_ATTR_TYPES[packettype][:format])
						end
					end
					out
				end
				#3rd - set all the readers
				attr_reader(*@my_attributes.map {|attribute,packettype,internal_type| attribute})
				
				#4th - set the writers
				normal,special = @my_attributes.partition {|attribute,packettype,internal_type| internal_type.nil?}
					#the normal ones use the default writer
				attr_writer(*normal.map {|attribute,packettype,internal_type| attribute})
					#the internally enforced ones use a special writer
				special.each do |attribute,packettype,internal_type|
					define_method(attribute.to_s+"=") do |val|
						instance_variable_set("@"+attribute.to_s,val.send(INTERNAL_TYPE_METHODS[internal_type]))
					end
				end
				
				#finally, set the default initializer - it just copies everything, with no default values supplied. if they want default values, they can call default_initializer themselves.
				default_initializer(@my_attributes.map {|attribute,packettype,internal_type| [attribute,{:internal_type=>internal_type}]}) unless @my_attributes.empty?
			end
		end
		
		def my_tag
			self.class.instance_variable_get("@tag")
		end
		#every basic packet should have a to_s. so, we undefine it here, so we get a nice proper error if it doesn't exist.
		#undef_method :to_s
	end
end