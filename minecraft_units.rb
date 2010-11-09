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
		def initialize(val);@val=val;end
		def to_f
			@val.to_f
		end
		def to_i
			@val.to_i
		end
	end
	#rotational
	class RotationInDegrees < BasicUnit
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
		def to_rotation_in_degrees
			RotationInDegrees(@val * (360.0/255.0))
		end
		def to_rotation_in_byte_fraction
			self
		end
	end
	
	#length - it can be measured either in block lengths (which == 1 meter, apparently), or in 'pixels', which are 32 pixels:1 block.
	class BlockLength < BasicUnit
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
	end
	class AbsLength < BasicUnit
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
end

class Numeric
	def degrees
		Units::RotationInDegrees.new(self)
	end
	def byte_fractions #wtf to call it?
		Units::RotationInByteFraction.new(self)
	end
	def block_lengths
		Units::BlockLength.new(self)
	end
	def abs_lengths
		Units::AbsLength.new(self)
	end
	def chunk_lengths
		Units::ChunkLength.new(self)
	end
end
