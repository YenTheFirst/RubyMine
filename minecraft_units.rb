#I had considered using something like the ruby-units gem, but I think that's kind of overkill for this
#basically, I just need two things: some automatic conversion niceness, but more importantly, some unit type safety

#I'll do things this way. the idea is, in accessor methods or initializers, the method will enforce the type safety by calling the appropriate to_ method.
#if you screw up and pass it an incompatible type, you'll get a NoMethodError. If it's compatible, it will auto-convert as appropriate.

#it really is ugly, and I welcome a better way to have some unit type safety and auto-convert. maybe I'll end up using that gem.
module Units
	#I'm unsure about being a subclass of numeric. we're really just a wrapper class. on the other hand, though, array.pack seems to want to check for numeric before it calls to_i
	#TODO: investigate!
	class BasicUnit < Numeric
		attr_accessor :val
		class << self
			attr_accessor :pp_name
		end
		def initialize(val);@val=val;end
		def to_f
			@val.to_f
		end
		def to_i
			@val.to_i
		end
		def pretty_print(the_pp)
			if @val.is_a? Fixnum
				the_pp.text "%8d %s" % [@val,self.class.pp_name]
			else
				the_pp.text "%8.2f %s" % [@val,self.class.pp_name]
			end
		end
	end
	#rotational
	class RotationInDegrees < BasicUnit
		@pp_name = "degrees"
		def to_rotation_in_degrees
			self
		end
		def to_rotation_in_byte_fraction
			RotationInByteFraction.new((@val%360) * (255.0 / 360.0))
		end
		#TODO: figure out which arithmatic methods make sense to override, and which don't, and whether they should take units or dimensionless values.
		#i.e., '+' should pass it's argument through 'to_rotation_in_degrees'. 
		#but, does '**' even make sense for a rotation value as a dimensional value, without casting it?
		#def method_missing(name,*args,&blk)
		#end
	end
	#because we HAVE to save those 3 bytes sending a byte fraction instead of a float in the EntityLookPackets. Really. serious business.
	class RotationInByteFraction < BasicUnit
		@pp_name="byte rotations"
		def to_rotation_in_degrees
			RotationInDegrees(@val * (360.0/255.0))
		end
		def to_rotation_in_byte_fraction
			self
		end
	end
	
	#length - it can be measured either in block lengths (which == 1 meter, apparently), or in 'pixels', which are 32 pixels:1 block.
	class BlockLength < BasicUnit
		@pp_name = "block lengths"
		def to_abs_length
			AbsLength.new(@val*32.0)
		end
		def to_block_length
			self
		end
		def to_chunk_length
			ChunkLength.new(@val/16)
		end
		def -(other)
			BlockLength.new(@val-other.to_block_length.val)
		end
		def +(other)
			BlockLength.new(@val+other.to_block_length.val)
		end
	end
	class AbsLength < BasicUnit
		@pp_name = "absolute pixels"
		def to_abs_length
			self
		end
		def to_block_length
			BlockLength.new(@val/32.0)
		end
		def to_chunk_length
			ChunkLength.new(@val/(16*32))
		end
	end
	class ChunkLength < BasicUnit
		@pp_name = "chunk lengths"
		def to_abs_length
			AbsLength.new(@val*16*32)
		end
		def to_block_length
			BlockLength.new(@val*16.0)
		end
		def to_chunk_length
			self
		end
	end
	
	
	#TIME
		#the documentation says time is sent out in minutes, but it's not really 'minutes'. one day cycle seems to be about 24000 increments of the value
		#so, if we call it a 24 hour day, each increment is 1/1000 of an 'hour'.
		#I'm going to call it a milli-hour for now. 
		#0/24 is dawn, 6 is noonish, 12 is dusk, 18 is midnightish
	class MinecraftHours < BasicUnit
		@pp_name = "minecraft hours"
		def to_minecraft_hours
			self
		end
		def to_milli_hours
			MilliHours.new @val * 1000
		end
	end
		#do we want to call it minecraft_milli_hours?
	class MilliHours < BasicUnit
		@pp_name="milli hours"
		def to_minecraft_hours
			MinecraftHours.new self / 1000.0
		end
		def to_milli_hours
			self
		end
	end
	ALL_UNITS = constants.map {|x| const_get x}.select {|x| x.is_a?(Class) && x.superclass == BasicUnit}
	#todo: add velocity units
end

class Numeric
	Units::ALL_UNITS.each do |u|
		sym=u.pp_name.downcase.gsub(/\s/,'_').to_sym
		define_method(u.pp_name.downcase.gsub(/\s/,'_').to_sym) {u.new(self)}
	end
end
