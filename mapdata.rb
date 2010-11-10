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

class Range
	def subset?(other)
		self.first<= other.first && self.end >= other.end
	end
	def subset_of?(other)
		other.subset? self
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
				get_block(args[0])
			when Range
				#range can be an index range, or an coord triple range
				if (args[0].begin.is_a? Fixnum)
					get_index_range(args[0])
				else
					get_coord_range(args[0])
				end
			else
				raise "unrecognized index type"
			end
		when 2 #start,length
			get_index_range(args[0]..(args[0]+args[1]-1))
		when 3 #single xyz index
			get_block(index_from_xyz(*args))
		else
			raise "wrong number of arguments for []"
		end
	end
	def []=(*args)
		case args.length
		when 2 #simple index, or range
			case args[0]
			when Fixnum
				set_block(args[0],args[1])
			when Range
				if (args[0].begin.is_a? Fixnum)
					set_index_range(args[0],args[1])
				else
					set_coord_range(args[0],args[1])
				end
			else
				raise "unrecognized index type"
			end
		when 3 #start,length
			set_index_range((args[0]..args[0]+args[1]),args[2])
		when 4 #single xyz index
			set_block(index_from_xyz(*args[0..2]),args[3])
		else
			raise "wrong number of arguments for []="
		end
	end
	def index_from_xyz(x,y,z)
		# a negative index on any dimension will wrap around on that dimension, like an index array
		#also, we'll check individual dimensions for index legality
		
		%w{x y z}.each do |dim|
			s=instance_variable_get("@size_#{dim}").to_i
			val=eval(dim) #ugly. :(
			raise IndexError.new "#{dim}=#{val} is not in the acceptable range for #{dim} (#{-s..s-1})" unless (-s..s-1).include? val
			eval("#{dim} += s") if val < 0
		end
		(x.to_i*@size_z.to_i+z.to_i)*@size_y.to_i+y.to_i
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
	
	private
	def get_block(index)
		raise IndexError unless (-length..length-1) === index
		{:block_type=>@block_type[index],
		:metadata=>@metadata[index],
		:block_light=>@block_light[index],
		:sky_light=>@sky_light[index]}
	end
	def get_index_range(r)
		raise IndexError unless (-length..length-1).subset? r
		r.map {|x| get_block(x)}
	end
	def set_block(index,new_block)
		raise IndexError unless (-length..length-1).include? index
		return if new_block.nil?
		for key,val in new_block
			instance_variable_get("@"+key.to_s)[index]=val
		end
	end
	def set_index_range(r,new_val)
		raise IndexError unless (-length..length-1).subset? r
		case new_val
		when Hash #single new object
			r.each {|i| set_block(i,new_val)}
		when Array
			raise "Length Mismatch" unless new_val.length == r.count
			r.each {|i| set_block(i,new_val[i-r.begin])}
		else
			raise "unknown type to set"
		end
	end
	def get_coord_range(r)
		%w{x y z}.each_with_index do |dim,i|
			dim_range = r.begin[i]..r.end[i]
			size_range= 0..instance_variable_get("@size_#{dim}").to_i
			raise IndexError.new "#{dim}=#{dim_range} is not in the acceptable range for #{dim} (#{size_range})" unless size_range.subset? dim_range
		end
		#for now, it will return a triple array. in the future, I may have it return a new mapdata instead., and mapdata will have a .to_triple_array method or somesuch.
		#return things in XZY order, as that's how it's supposed to be indexed. debatable?
		Array.new((r.begin[0]..r.end[0]).count) do |ix| 
			Array.new((r.begin[2]..r.end[2]).count) do |iz|
				Array.new((r.begin[1]..r.end[1]).count) do |iy|
					get_block(index_from_xyz(ix-r.begin[0],iy-r.begin[1],iz-r.begin[2]))
				end
			end
		end
	end
	def set_coord_range(r,new_val)
		range_x=r.begin[0]..r.end[0]
		range_y=r.begin[2]..r.end[1]
		range_z=r.begin[2]..r.end[1]
		%w{x y z}.each_with_index do |dim,i|
			temp_r= r.begin[i]..r.end[i]
			size_range= 0..instance_variable_get("@size_#{dim}").to_i
			raise IndexError.new "#{dim}=#{temp_r} is not in the acceptable range for #{dim} (#{size_range})" unless size_range.subset? temp_r
		end
		
		case new_val
		when Hash #easy enough, set everything to that value
			(range_x).each do |ix|
			(range_y).each do |iy|
			(range_z).each do |iz|
				set_block(index_from_xyz(ix,iy,iz),new_val)
			end
			end
			end
		when Array
			#should be a 3-deep array.
			raise "Array Length Mismatch on x" unless new_val.length == range_x.count
			new_val.each_with_index do |zy_plane,ix|
				next if zy_plane.nil?
				raise "Array Length Mismatch on zy_plane #{ix}" unless zy_plane.length == range_z.count
				zy_plane.each_with_index do |y_col,iz|
					next if y_col.nil?
					raise "Array Length Mismatch on y_col #{ix},#{iz}. length=#{y_col.length}, range size=#{range_y.count}" unless y_col.length == range_y.count
					y_col.each_with_index do |block,iy|
						set_block(index_from_xyz(ix-range_x.begin,iy-range_y.begin,iz-range_z.begin),block)
					end
				end
			end
		when MapData
			raise "error, can't be set from mapdata yet"
		else
			raise "unknown type to set"
		end
		
	end
end

