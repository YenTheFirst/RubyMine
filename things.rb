class Player
	attr_accessor :socket, :timeout, :initial_position_set
	attr_accessor :username,:last_relative_position
	attr_accessor :position, :entity_id
	def initialize
		@initial_position_set=false
		@position=Position.new
		@last_relative_position
		@entity_id=rand(1000)
	end
	def to_io
		socket
	end
end

class Position
	attr_accessor :x,:y,:z,:yaw,:pitch,:is_on_ground,:stance
	
	def update_from_packet(p)
		for field in %w{x y z yaw pitch is_on_ground stance} do
			instance_variable_set("@"+field,p.send(field)) if p.respond_to?(field)
		end
	end
	
	def update_all!(_x,_y,_z,_yaw,_pitch,_is_on_ground)
		@x,@y,@z,@yaw,@pitch,@on_ground=_x,_y,_z,_yaw,_pitch,_is_on_ground
	end
	def update_orientation!(_yaw,_pitch)
		@yaw,@pitch=_yaw,_pitch
	end
	def update_position!(_x,_y,_z)
		@x,@y,@z=_x,_y,_z
	end
	%w{x y z yaw pitch is_on_ground stance}.each do |field|
		define_method(field) {instance_variable_get("@"+field) || raise("#{field} is undefined!!!")}
	end
	#convenience methods for working in units of blocks instead of pixels
	["x","y","z"].each do |var|
		define_method("block_#{var}".to_sym) {instance_variable_get("@#{var}").to_i/32}
		define_method("block_#{var}=".to_sym) {|new_val| instance_variable_set("@#{var}",new_val*32.0)}
	end
	#convenience methods for working in units of chunks instead of pixels
	["x","z"].each do |var|
		define_method("chunk_#{var}".to_sym) {instance_variable_get("@#{var}").to_i/512}
		define_method("chunk_#{var}=".to_sym) {|new_val| instance_variable_set("@#{var}",new_val*512.0)}
	end
end