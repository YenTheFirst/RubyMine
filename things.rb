require 'minecraft_units.rb'

class Player
	STATUS_UNCONNECTED=0
	STATUS_CONNECTED=1
	STATUS_HANDSHAKE_SENT=2
	STATUS_LOGIN_REQUESTED=3
	STATUS_LOGGED_IN=4
	STATUS_READY=5
	STATUS_DISCONNECTED=99
	attr_accessor :socket, :timeout, :status
	attr_accessor :username,:entity_id
	attr_accessor :position, :inventory
	def initialize
		@status=STATUS_UNCONNECTED
		@position=Position.new
		@last_relative_position
		@entity_id=rand(1000)
			#for now, all players get a free watch and compass. yay free stuff.
			#notch uses -1,-2,-3 for inventory types.. why? I dunno.
			#I'm mapping -1:0, -2:1, -3:2. i.e., my_i=-(i+1), or i=-(my_i+1)
				#or rather, abs(i)+1, -my_i -1
		@inventory=[[{:item_id=>0x15b,:count=>1,:health=>0x00},{:item_id=>0x159,:count=>1,:health=>0x00}]+[nil]*34,
			[nil]*4,[nil]*4]
	end
	def to_io
		socket
	end
	def assert_status(status)
		raise "Error, player status is #{@status}, not #{status}" if @status!=status
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
				#puts "checking field #{field}"
				if obj.respond_to?(field)
					instance_variable_set("@"+field,obj.send(field).send(to_type))
				#	puts "\tset field #{field} to value #{obj.send(field)} enforcing type #{to_type}"
				end
				
			end
		end
	end
end