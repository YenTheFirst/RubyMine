require 'minecraft_units.rb'

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
	
	#all readers enforce that we don't give out nil values
	%w{x y z yaw pitch is_on_ground stance}.each do |field|
		define_method(field) {instance_variable_get("@"+field) || raise("#{field} is undefined!!!")}
	end
	#the attributes x,y,z,stance are kept in block lengths. the writer enforces this.
	%w{x y z stance}.each do |field|
		define_method(field+"=") {|val| instance_variable_set("@"+field,val.to_block_length)}
	end
	#yaw and pitch are kept in RotationInDegrees
	%w{yaw pitch}.each do |field|
		define_method(field+"=") {|val| instance_variable_set("@"+field,val.to_rotation_in_degrees)}
	end	
	#is_on_ground can just use the default
	attr_writer :is_on_ground
	
	#update us, using all applicable fields from obj. enforce type safety on those assignments.
	def update_from_object(obj)
		for to_type,fields in [["to_block_length",%w{x y z stance}],["to_rotation_in_degrees",%w{yaw pitch}],["to_i",["is_on_ground"]]]
			for field in fields do
				if obj.respond_to?(field)
					instance_variable_set("@"+field,obj.send(field).send(to_type))
					#puts "\tset field #{field} to value #{obj.send(field)} enforcing type #{to_type}"
				end
				
			end
		end
	end
end