class IO
	def read_network_unsigned_long;	read(4).unpack("N")[0]; end
	def read_network_signed_long;	read(4).unpack("N").pack("L").unpack("l") end
	def read_network_unsigned_short;read(2).unpack("n")[0]; end
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

module Packet
	#directions. is there a slightly more ruby way to do this?
	:client_to_server
	:server_to_client
	BOTH=[:client_to_server,:server_to_client]
	
	class BasicPacket
		class << self
			attr_reader :tag
			attr_reader :directions
			
			#it's kind of ugly, but it allows fancy meta-programming in the class definitions, while still allowing reading.
			def tag(*args); args.empty? ? @tag : @tag=args[0]; end
			def directions(*args); args.empty? ? @directions : @directions=args[0]; end
			def default_initializer(*args)
				#I don't like using eval, but I want enforced arity, and I don't see how to do that with a 'raw' define_method.
				method_arg_names = args.map {|x| x.is_a?(Array) ? "_#{x[0].to_s}=#{x[1]}" : "_"+x.to_s}*','
				instance_var_names=args.map {|x| "@"+(x.is_a?(Array) ? x[0] : x).to_s}*','
				set_names = args.map {|x| "_"+(x.is_a?(Array) ? x[0] : x).to_s}*','
				class_eval("def initialize(#{method_arg_names}); #{instance_var_names}=#{set_names}; end")
			end
		end
		
		def my_tag
			self.class.instance_variable_get("@tag")
		end
		#every basic packet should have a to_s. so, we undefine it here, so we get a nice proper error if it doesn't exist.
		#undef_method :to_s
	end

	class KeepAlive < BasicPacket
		tag 0x00
		directions BOTH
		def self.read_from_socket(s)
		
		end
		def to_s
			[my_tag].pack("c")
		end
	end
	class LoginRequest < BasicPacket
		tag 0x01
		directions [:client_to_server]
		attr_accessor :protocol_version,:username,:password,:unused_mapseed,:unused_dimension
		default_initializer :protocol_version,:username,:password,:unused_mapseed,:unused_dimension
		def self.read_from_socket(socket)
			self.new(
				socket.read_network_unsigned_long,
				socket.read_java_string,
				socket.read_java_string,
				socket.read(8),
				socket.readbyte)
		end
	end
	class LoginResponse < BasicPacket
		tag 0x01
		directions [:server_to_client]
		attr_accessor :map_seed,:dimension
		default_initializer [:map_seed,0],[:dimension,0]
		def to_s
			[my_tag,0].pack("CN")+"".to_java_string+"".to_java_string+[@map_seed,@dimension].pack("QC")
		end
	end
	class ClientHandshake < BasicPacket
		tag 0x02
		directions [:client_to_server]
		attr_accessor :username
		default_initializer :username
		def self.read_from_socket(socket)
			self.new(socket.read_java_string)
		end
	end
	class ServerHandshake < BasicPacket
		tag 0x02
		directions [:server_to_client]
		NO_AUTH="-"
		PASSWORD_AUTH="+"
		attr_accessor :auth_hash
		#TODO: what should the default auth_hash be? can we config it?
		default_initializer [:auth_hash,"NO_AUTH"]
		def to_s
			[my_tag].pack("C")+@auth_hash.to_java_string
		end
	end
	class ChatMessage < BasicPacket
		tag 0x03
		directions BOTH
		attr_accessor :message
		default_initializer [:message,"''"]
		def self.read_from_socket(socket)
			self.new(socket.read_java_string)
		end
		def to_s
			[my_tag].pack("C")+@message.to_java_string
		end
	end
	class TimeUpdate < BasicPacket
		tag 0x04
		directions [:server_to_client]
		attr_accessor :time_in_minutes
		default_initializer :time_in_minutes
		def to_s
			[my_tag,@time_in_minutes].pack("CQ")
		end
	end
	class InventoryUpdate < BasicPacket
		tag 0x05
		directions BOTH
		attr_accessor :section,:count,:inventory
		MAIN_INVENTORY=-1
		EQUIPPED_ARMOR=-2
		CRAFTING_SLOTS=-3
		DEFAULT_COUNT={MAIN_INVENTORY=>36,EQUIPPED_ARMOR=>4,CRAFTING_SLOTS=>4}
		default_initializer :section,[:count,"DEFAULT_COUNT[_section]"],[:inventory,"Array.new(_count,-1)"]
		def self.read_from_socket(s)
			section=s.read_network_signed_long
			count=s.read_network_unsigned_short
			inventory=Array.new(count)
			inventory.map do 
				item_id=s.read_network_unsigned_short
				unless (item_id == -1)
					{:item_id=>item_id,
					:count=>s.readbyte,
					:health=>s.read_network_unsigned_short}
				end
			end
			self.new(section,count,inventory)
		end
		def to_s
			inv_string = @inventory.map {|x| x.nil? ? [-1].pack("n") : x.values_at(:item_id,:count,:health).pack("ncn")}*""
			[my_tag,@section,@count].pack("CNn")+inv_string
		end
	end
	class SpawnPosition < BasicPacket
		tag 0x06
		directions [:server_to_client]
		attr_accessor :x,:y,:z
		default_initializer :x,:y,:z
		def to_s
			[my_tag,@x,@y,@z].pack("CNNN")
		end
	end
	class OnGround < BasicPacket
		tag 0x0A
		directions [:client_to_server]
		attr_accessor :is_on_ground
		default_initializer :is_on_ground
		def self.read_from_socket(s)
			self.new(s.readbyte)
		end
	end
	class PlayerPosition < BasicPacket
		tag 0x0B
		directions [:client_to_server]
		attr_accessor :x,:y,:z,:stance,:is_on_ground
		default_initializer :x,:y,:z,:stance,:is_on_ground
		def self.read_from_socket(s)
			x,y,stance,z,is_on_ground=s.read(33).unpack("GGGGC")
			self.new(x,y,z,stance,is_on_ground)
		end
	end
	class PlayerLook < BasicPacket
		tag 0x0C
		directions [:client_to_server]
		attr_accessor :yaw,:pitch,:is_on_ground
		default_initializer :yaw,:pitch,:is_on_ground
		def self.read_from_socket(s)
			self.new(*s.read(9).unpack("ggC"))
		end
	end
	#OK, how retarded is this? two, almost identical packets, with just the ordering swapped? Really, Notch?
	#I can't think of a good way to name 'em.
	class CtoSPlayerPosLook < BasicPacket #the client informing the server about an update, maybe name it that way?
		tag 0x0D
		directions [:client_to_server]
		attr_accessor :x,:y,:z,:stance,:yaw,:pitch,:is_on_ground
		default_initializer :x,:y,:z,:stance,:yaw,:pitch,:is_on_ground
		def self.read_from_socket(s)
			x,y,stance,z,yaw,pitch,is_on_ground=s.read(41).unpack("GGGGggc")
			self.new(x,y,z,stance,yaw,pitch,is_on_ground)
		end
	end
	class StoCPlayerPosLook < BasicPacket #the server imposing a new poslook on the client, name it that way maybe?
		tag 0x0D
		directions [:server_to_client]
		attr_accessor :x,:y,:z,:stance,:yaw,:pitch,:is_on_ground
		default_initializer :x,:y,:z,:stance,:yaw,:pitch,:is_on_ground
		def self.from_position(p)
			self.new(p.x,p.y,p.z,p.stance,p.yaw,p.pitch,p.is_on_ground)
		end
		def to_s
			[my_tag,@x,@stance,@y,@z,@yaw,@pitch,@is_on_ground].pack("CGGGGggC")
		end
	end
	#TODO: double check the "-Y +Y -Z +Z -X	 +X" against cardinal directions.
	#for that matter, DEFINE cardinal directions...
	ALL_FACES=[TOP=0,BOTTOM=1,EAST=2,WEST=3,SOUTH=4,NORTH=5]
	class PlayerDigging < BasicPacket
		tag 0x0E
		directions [:client_to_server]
				ALL_STATUS=[STARTED_DIGGING=0,DIGGING=1,STOPPED_DIGGING=2,BLOCK_BROKEN=3]
		attr_accessor :x,:y,:z,:status,:face
		default_initializer :x,:y,:z,:status,:face
		def self.read_from_socket(s)
			status,x,y,z,face=s.read(11).unpack("CNCNC")
			self.new(x,y,z,status,face)
		end
	end
	class PlayerBlockPlacement < BasicPacket
		tag 0x0F
		directions [:client_to_server]
		attr_accessor :x,:y,:z,:item_id,:face
		default_initializer :x,:y,:z,:item_id,:face
		def self.read_from_socket(s)
			item_id,x,y,z,face=s.read(12).unpack("nNCNC")
			self.new(x,y,z,item_id,face)
		end
	end
	class HoldingChange < BasicPacket
		tag 0x10
		directions [:client_to_server]
		attr_accessor :unused,:item_id
		default_initializer :unused,:item_id
		def self.read_from_socket(s)
			self.new(*s.read(6).unpack("Nn"))
		end
	end
	class AddToInventory < BasicPacket
		tag 0x11
		directions [:server_to_client]
		attr_accessor :item_id,:count,:health
		default_initializer :item_id,:count,:health
		def to_s
			[my_tag,@item_id,@count,@health].pack("CnCn")
		end
	end
	class ArmAnimation < BasicPacket
		tag 0x12
		directions BOTH #despite the protocol documentation at http://mc.kev009.com/wiki/Protocol, the client will send this to the server as well when it's swingin'
		attr_accessor :entity_id, :animate
		default_initializer :entity_id, :animate
		def self.read_from_socket(s)
			self.new(*s.read(5).unpack("NC"))
		end
		def to_s
			[my_tag,@entity_id,@animate].pack("NC")
		end
	end
	class NamedEntitySpawn < BasicPacket
		tag 0x14
		directions [:server_to_client]
		attr_accessor :entity_id,:name,:x,:y,:z,:yaw,:pitch,:held_item_id
		default_initializer :entity_id,:name,:x,:y,:z,:yaw,:pitch,:held_item_id
		def self.from_player(player)
			p=player.position
			self.new(player.entity_id,player.username,p.x,p.y,p.z,p.yaw,p.pitch,0)
		end
		def to_s
			[my_tag,@entity_id].pack("CN")+@name.to_java_string+[@x,@y,@z,@yaw,@pitch,@held_item_id].pack("NNNCCn")
		end
	end
	class PickupSpawn < BasicPacket
		tag 0x15
		directions [:server_to_client]
		attr_accessor :entity_id,:item_id,:count,:x,:y,:z,:yaw,:pitch,:roll
		default_initializer :entity_id,:item_id,:count,:x,:y,:z,:yaw,:pitch,:roll
		def to_s
			[my_tag,@entity_id,@item_id,@count,@x,@y,@z,@yaw,@pitch,@roll].pack("CNnCNNNCCC")
		end
	end
	class CollectItem < BasicPacket
		tag 0x16
		directions [:server_to_client]
		attr_accessor :collected_id, :collector_id
		default_initializer :collected_id, :collector_id
		def to_s
			[my_tag,@collected_id,@collector_id].pack("CNN")
		end
	end
	class AddVehicle < BasicPacket
		tag 0x17
		directions [:server_to_client]
		attr_accessor :entity_id,:vehicle_type,:x,:y,:z
		default_initializer :entity_id,:vehicle_type,:x,:y,:z
		ALL_VEHICLE_TYPES=[BOAT=1,MINECART=10,STORAGE_CART=11,POWERED_CART=12]
		def to_s
			[my_tag,@entity_id,@vehicle_type,@x,@y,@z].pack("CNCNNN")
		end
	end
	class MobSpawn < BasicPacket
		tag 0x18
		directions [:server_to_client]
		attr_accessor :entity_id,:mob_type,:x,:y,:z,:yaw,:pitch
		default_initializer :entity_id,:mob_type,:x,:y,:z,:yaw,:pitch
		def to_s
			[my_tag,@entity_id,@mob_type,@x,@y,@z,@yaw,@pitch].pack("CNCNNNCC")
		end
	end
	class DestroyEntity < BasicPacket
		tag 0x1D
		directions [:server_to_client]
		attr_accessor :entity_id
		default_initializer :entity_id
		def to_s
			[my_tag,@entity_id].pack("CN")
		end
	end
	class EntityInitialize < BasicPacket
		tag 0x1E
		directions [:server_to_client]
		attr_accessor :entity_id
		default_initializer :entity_id
		def to_s
			[my_tag,@entity_id].pack("CN")
		end
	end
		#relative move is for moves<4 blocks [128 pixels]
	class EntityRelativeMove < BasicPacket
		tag 0x1f
		directions [:server_to_client]
		attr_accessor :entity_id, :x,:y,:z
		default_initializer :entity_id, :x,:y,:z
		def to_s
			[my_tag,@entity_id, @x,@y,@z].pack("CNCCC")
		end
	end
	class EntityLook < BasicPacket
		tag 0x20
		directions [:server_to_client]
		attr_accessor :entity_id, :yaw,:pitch
		default_initializer :entity_id, :yaw,:pitch
		def to_s
			[my_tag,@entity_id, @yaw,@pitch].pack("CNCC")
		end
	end
	class EntityLookAndRelativeMove < BasicPacket
		tag 0x20
		directions [:server_to_client]
		attr_accessor :entity_id, :x,:y,:z, :yaw, :pitch
		default_initializer :entity_id, :x,:y,:z, :yaw, :pitch
		def to_s
			[my_tag,@entity_id, @x,@y,@z, @yaw, @pitch].pack("CNCCCCC")
		end
	end
		#teleport is for moves >4blocks [128 pixels]
	class EntityTeleport < BasicPacket
		tag 0x22
		directions [:server_to_client]
		attr_accessor :entity_id, :x,:y,:z, :yaw, :pitch
		default_initializer :entity_id, :x,:y,:z, :yaw, :pitch
		def self.from_player(player)
			p=player.position
			self.new(player.entity_id,p.x*32,p.y*32,p.z*32,p.yaw,p.pitch)
			
		end
		def to_s
			[my_tag,@entity_id, @x,@y,@z, @yaw, @pitch].pack("CNNNNCC")
		end
	end
	
	#TODO: the rest
	all_packets=constants.map {|x| const_get x}.select {|x| x.respond_to?(:directions)} -[BasicPacket]
#	require 'pp'
#	pp temp.select {|x| x.respond_to?(:directions)}.map {|x| [x,x.directions]}
	CLIENT_PACKETS = all_packets.select {|x| x.directions.include?(:client_to_server)}
	SERVER_PACKETS = all_packets.select {|x| x.directions.include?(:server_to_client)}
	class << self
		def client_packet_for_tag(t)
			CLIENT_PACKETS.find {|x| x.tag==t}
		end
		def server_packet_for_tag(t)
			SERVER_PACKETS.find {|x| x.tag==t}
		end
	end
end