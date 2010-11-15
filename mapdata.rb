require 'zlib'

#because those half-bytes make a huge difference, especially considering all the data is passed through zlib. . .
class Array
	def pack_nibble_array
		even,odd = self.to_enum(:each_with_index).partition {|x,i| i%2==0}
		even.zip(odd).map {|(x,xi),(y,yi)| x*0x10+y}.pack("C"*even.length)
	end
end
class String
	def unpack_nibble_array
		self.unpack("C"*self.length).map {|x| [x/0x10,x%0x10]}.flatten
	end
end
class MapData
	#we don't want the outside world messing with our arrays directly, they have to go through us.
	#this design may change in the future, if I feel like it.
	attr_reader :block_type,:metadata,:block_light,:sky_light
	attr_reader :size_x,:size_y,:size_z #sizes can't be changed after the fact.
	
	#we can pretend to be a real array!
	#in the future, maybe we'll implement more array-like methods, or bring in the enumerable module.
	def length
		@length ||= size_x.to_i*size_y.to_i*size_z.to_i
	end
	def [](*args)
		case args.length
		when 1 #can be a range, or an individual index
			case args[0]
			when Fixnum
				raise IndexError unless (-length..length-1).include? args[0]
				{:type=>@block_type[args[0]],
				:metadata=>@metadata[args[0]],
				:block_light=>@block_light[args[0]],
				:sky_light=>@block_light[args[0]]}
			when Range
				raise "not yet implemented range"
			else
				raise "unrecognized index type"
			end
		when 2 #start,length
			raise "not yet implemented start,length"
		when 3 #single xyz index
			i=index_from_xyz(*args)
			raise IndexError unless (-length..length-1).include? i
			{:type=>@block_type[i],
			:metadata=>@metadata[i],
			:block_light=>@block_light[i],
			:sky_light=>@block_light[i]}
		else
			raise "wrong number of arguments for []"
		end
	end
	def []=(*args)
		@cached_compress = nil
		case args.length
		when 2 #simple index, or range
			case args[0]
			when Fixnum
				raise IndexError unless (-length..length-1).include? args[0]
				for key,val in args[1]
					instance_variable_get("@"+key.to_s)[args[0]]=val
				end
			when Range
				raise "not yet implemented range"
			else
				raise "unrecognized index type"
			end
		when 3 #start,length
			raise "not yet implemented start,length"
		when 4 #single xyz index
			i=index_from_xyz(*args[0,3])
			raise IndexError unless (-length..length-1).include? i
			for key,val in args[3]
				instance_variable_get("@"+key.to_s)[i]=val
			end
		else
			raise "wrong number of arguments for []="
		end
	end
	def index_from_xyz(x,y,z)
		y.to_i+(z*@size_y.to_i)+(x*@size_y.to_i*@size_z.to_i)
	end
	
	def initialize(_size_x,_size_y,_size_z)
		@size_x,@size_y,@size_z=_size_x.to_block_length,_size_y.to_block_length,_size_z.to_block_length
			#should be nil instead, maybe?
		@block_type=Array.new(length,0)
		@metadata=Array.new(length,0)
		@block_light=Array.new(length,0)
		@sky_light=Array.new(length,0)
	end
	def compress
		lengths = [length]+[@block_type,@metadata,@block_light,@sky_light].map(&:length)
		raise "Array Lengths don't match!: #{lengths*','}" if lengths.uniq.length!=1
		@cached_compress ||= Zlib::Deflate.deflate(
			@block_type.pack("C"*@block_type.length)+
			@metadata.pack_nibble_array+
			@block_light.pack_nibble_array+
			@sky_light.pack_nibble_array)
	end
	
	def all
		@block_type.pack("C"*@block_type.length)+
			@metadata.pack_nibble_array+
			@block_light.pack_nibble_array+
			@sky_light.pack_nibble_array
	end
	def self.uncompress(data,sx,sy,sz)
		my_new=self.new(sx,sy,sz)
		temp=Zlib::Inflate.inflate(data)
		len=(temp.length / 2.5).to_i
		my_new.block_type=temp(0..len).unpack("n"*len)
		my_new.metadata = temp(len..len*1.5).unpack_nibble_array
		my_new.block_light = temp(len*1.5..len*2).unpack_nibble_array
		my_new.sky_light = temp(len*2..len*2.5).unpack_nibble_array
		my_new
	end
end
