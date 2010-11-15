require 'basic_packet.rb'

#largely based on the protocol information found at http://mc.kev009.com/wiki/Protocol

module Packet
	#directions. is there a slightly more ruby way to do this?
	XYZ_BYTE_ABS = [[:x,:byte,:abs_len],[:y,:byte,:abs_len],[:z,:byte,:abs_len]]
	XYZ_INT_ABS = [[:x,:int,:abs_len],[:y,:int,:abs_len],[:z,:int,:abs_len]]
	YP_BYTE = [[:yaw,:byte,:rotation_in_byte],[:pitch,:byte,:rotation_in_byte]]
	YPR_BYTE =[[:yaw,:byte,:rotation_in_byte],[:pitch,:byte,:rotation_in_byte],[:roll,:byte,:rotation_in_byte]]
	class KeepAlive < BasicPacket
		tag 0x00
		directions BOTH
		attributes []
	end
	class LoginRequest < BasicPacket
		tag 0x01
		directions [:client_to_server]
		attributes [
			[:protocol_version,:int],
			[:username,:string],
			[:password,:string],
			[:unused_mapseed,:long],
			[:unused_dimension,:byte]]
	end
	class LoginResponse < BasicPacket
		tag 0x01
		directions [:server_to_client]
		attr_accessor :map_seed,:dimension
		default_initializer [[:map_seed,{:default=>0}],[:dimension,{:default=>0}]]
		def to_s
			[my_tag,0].pack("CN")+"".to_java_string+"".to_java_string+[@map_seed,@dimension].pack("QC")
		end
	end
	class ClientHandshake < BasicPacket
		tag 0x02
		directions [:client_to_server]
		attributes [[:username,:string]]
	end
	class ServerHandshake < BasicPacket
		tag 0x02
		directions [:server_to_client]
		NO_AUTH="-"
		PASSWORD_AUTH="+"
		attributes [[:auth_hash,:string]]
		#TODO: what should the default auth_hash be? can we config it?
		default_initializer [[:auth_hash,{:default=>"NO_AUTH"}]]
	end
	class ChatMessage < BasicPacket
		tag 0x03
		directions BOTH
		attributes [[:message,:string]]
	end
	class TimeUpdate < BasicPacket
		tag 0x04
		directions [:server_to_client]
		#attributes [[:time_in_minutes,:long]]
		#for now, instead of trying to hack proper long support, I'll just have a 'high' and 'low' int
		attributes [[:high_time,:int],[:low_time,:int]]
		
		
		def time=(value)
			v=value.to_milli_hours.to_i
			@high_time = v >> 32
			@low_time = v & 0xFFFFFFFF
		end
		def time
			Units::MilliHours.new((@high_time << 32)+@low_time)
		end
		def initialize(value)
			self.time=value
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
		default_initializer [:section,[:count,{:default=>"DEFAULT_COUNT[_section]"}],[:inventory,{:default=>"Array.new(_count,-1)"}]]
		def self.read_from_socket(s)
			section=s.read(4).unpack("N").pack("L").unpack("l")[0]
			count=s.read(2).unpack("n")[0]
			inventory=Array.new(count)
			inventory.map! do
				item_id=s.read(2).unpack("n").pack("S").unpack("s")[0]
				unless (item_id == -1)
					{:item_id=>item_id,
					:count=>s.readbyte,
					:health=>s.read(2).unpack("n")[0]}
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
		attributes [[:x,:int,:block_len],[:y,:int,:block_len],[:z,:int,:block_len]]
	end
	class UseEntity < BasicPacket
		#warning, this packet is still not yet fully understood
		warnnew
		tag 0x07
		directions [:client_to_server]
		attributes [[:user_eid,:int],[:target_eid,:int]]
	end
	class OnGround < BasicPacket
		tag 0x0A
		directions [:client_to_server]
		attributes [[:is_on_ground,:bool]]
	end
	class PlayerPosition < BasicPacket
		tag 0x0B
		directions [:client_to_server]
		attributes [
			[:x,:double,:block_len],[:y,:double,:block_len],[:stance,:double,:block_len],[:z,:double,:block_len],
			[:is_on_ground,:bool]]
	end
	class PlayerLook < BasicPacket
		tag 0x0C
		directions [:client_to_server]
		attributes [[:yaw,:float,:rotation_in_degrees],[:pitch,:float,:rotation_in_degrees],[:is_on_ground,:bool]]
	end
	#OK, how retarded is this? two, almost identical packets, with just the ordering swapped? Really, Notch?
	#I can't think of a good way to name 'em.
	class CtoSPlayerPosLook < BasicPacket #the client informing the server about an update, maybe name it that way?
		tag 0x0D
		directions [:client_to_server]
		attributes [
			[:x,:double,:block_len],[:y,:double,:block_len],[:stance,:double,:block_len],[:z,:double,:block_len],
			[:yaw,:float,:rotation_in_degrees],[:pitch,:float,:rotation_in_degrees],
			[:is_on_ground,:bool]]
	end
	class StoCPlayerPosLook < BasicPacket #the server imposing a new poslook on the client, name it that way maybe?
		tag 0x0D
		directions [:server_to_client]
		attributes [
			[:x,:double,:block_len],[:stance,:double,:block_len],[:y,:double,:block_len],[:z,:double,:block_len],
			[:yaw,:float,:rotation_in_degrees],[:pitch,:float,:rotation_in_degrees],
			[:is_on_ground,:bool]]
		def self.from_position(p)
			self.new(p.x,p.stance,p.y,p.z,
				p.yaw,p.pitch,
				p.is_on_ground)
		end
	end
	#TODO: double check the "-Y +Y -Z +Z -X	 +X" against cardinal directions.
	#for that matter, DEFINE cardinal directions...
	ALL_FACES=[TOP=0,BOTTOM=1,EAST=2,WEST=3,SOUTH=4,NORTH=5]
	class PlayerDigging < BasicPacket
		tag 0x0E
		directions [:client_to_server]
		ALL_STATUS=[STARTED_DIGGING=0,DIGGING=1,STOPPED_DIGGING=2,BLOCK_BROKEN=3]
		attributes [[:status,:byte],
			[:x,:int,:block_len],[:y,:byte,:block_len],[:z,:int,:block_len],
			[:face,:byte]]
	end
	class PlayerBlockPlacement < BasicPacket
		tag 0x0F
		directions [:client_to_server]
		attributes [[:item_id,:short],
			[:x,:int,:block_len],[:y,:byte,:block_len],[:z,:int,:block_len],
			[:face,:byte]]
	end
	class HoldingChange < BasicPacket
		tag 0x10
		directions [:client_to_server]
		attributes [[:unused,:int],[:item_id,:short]]
	end
	class AddToInventory < BasicPacket
		tag 0x11
		directions [:server_to_client]
		attributes [[:item_id,:short],[:count,:byte],[:health,:short]]
	end
	class ArmAnimation < BasicPacket
		tag 0x12
		directions BOTH #despite the protocol documentation at http://mc.kev009.com/wiki/Protocol, the client will send this to the server as well when it's swingin'
		attributes [[:entity_id,:int],[:animate,:bool]]
	end
	class NamedEntitySpawn < BasicPacket
		tag 0x14
		directions [:server_to_client]
		attributes [[:entity_id,:int],[:name,:string]]+XYZ_INT_ABS+YP_BYTE+[[:held_item_id,:short]]
		def self.from_player(player)
			p=player.position
			self.new(player.entity_id,player.username,
				p.x,p.y,p.z,
				p.yaw,p.pitch,0)
		end
	end
	class PickupSpawn < BasicPacket
		tag 0x15
		directions [:server_to_client]
		attributes [[:entity_id,:int],[:item_id,:short],[:count,:byte]]+XYZ_INT_ABS+YPR_BYTE
	end
	class CollectItem < BasicPacket
		tag 0x16
		directions [:server_to_client]
		attributes [[:collected_id,:int],[:collector_id,:int]]
	end
	class AddVehicle < BasicPacket
		tag 0x17
		directions [:server_to_client]
		attributes [[:entity_id,:int],[:vehicle_type,:byte],*XYZ_INT_ABS]
		ALL_VEHICLE_TYPES=[BOAT=1,MINECART=10,STORAGE_CART=11,POWERED_CART=12]
	end
	class MobSpawn < BasicPacket
		tag 0x18
		directions [:server_to_client]
		attributes  [[:entity_id,:int],[:mob_type,:byte]]+XYZ_INT_ABS+YP_BYTE
	end
	class EntityVelocity < BasicPacket
		#WARNING: also new
		warnnew
		tag 0x1C
		directions [:server_to_client]
			#todo: create velocity-related units
		attributes [[:entity_id,:int],[:vel_x,:short],[:vel_y,:short],[:vel_z,:short]]
	end
	class DestroyEntity < BasicPacket
		tag 0x1D
		directions [:server_to_client]
		attributes [[:entity_id,:id]]
	end
	class EntityInitialize < BasicPacket
		tag 0x1E
		directions [:server_to_client]
		attributes [[:entity_id,:id]]
	end
		#relative move is for moves<4 blocks [128 pixels]
	class EntityRelativeMove < BasicPacket
		tag 0x1f
		directions [:server_to_client]
		attributes [[:entity_id,:int]]+XYZ_BYTE_ABS
	end
	class EntityLook < BasicPacket
		tag 0x20
		directions [:server_to_client]
		attributes [[:entity_id,:int]]+YP_BYTE
	end
	class EntityLookAndRelativeMove < BasicPacket
		tag 0x21
		directions [:server_to_client]
		attributes [[:entity_id,:int]]+XYZ_BYTE_ABS+YP_BYTE
	end
		#teleport is for moves >4blocks [128 pixels]
	class EntityTeleport < BasicPacket
		tag 0x22
		directions [:server_to_client]
		attributes [[:entity_id,:int]]+XYZ_INT_ABS+YP_BYTE
		def self.from_player(player)
			p=player.position
			self.new(player.entity_id,
				p.x,p.y,p.z,
				p.yaw,p.pitch)
		end
	end
	class AttachEntity < BasicPacket
		warnnew
		tag 0x27
		directions [:server_to_client]
		attributes [[:entity_id,:int],[:vehicle_id,:int]]
	end
	class PreChunk < BasicPacket
		#will allocate a 16x128x16 block space at the specified coordinates
		UNLOAD_CHUNK=0
		INITIALIZE_CHUNK=1
		tag 0x32
		directions [:server_to_client]
		attributes [[:x,:int,:chunk_len],[:z,:int,:chunk_len],[:mode,:bool]]
	end
	
	class MapChunk < BasicPacket
		tag 0x33
		directions [:server_to_client]
		attributes [
			[:x,:int,:block_len],[:y,:short,:block_len],[:z,:int,:block_len],
			[:size_x,:byte,:block_len],[:size_y,:byte,:block_len],[:size_z,:byte,:block_len]]
		#we'll use attributes for the basic accessors, and we'll alias the original to_s and read_from_socket to get the compressed data & size.
		#the default initializer won't be aware of compressed size/data.
		attr_accessor :compressed_data, :map_data #:map_data is the uncompressed data
		#just-in-time caching of the compressed/uncompressed data
		def compressed_data
			@compressed_data ||= @map_data.compress
		end
		def compressed_data=(val)
			@map_data=nil
			@compressed_data=val
		end
		def map_data
			@map_data ||= MapData.uncompress(@size_x+1,@size_y+1,@size_z+1,@compressed_data) #the internal size_'s are -1
		end
		def map_data=(val)
			@compressed_data=nil
			@map_data=val
		end
		class << self
			alias_method(:orig_read_from_socket,:read_from_socket)
			def read_from_socket(s)
				temp=orig_read_from_socket(s)
				len=s.read(4).unpack("N")[0]
				temp.compressed_data = s.read(len)
				temp
			end
			def from_map_data(x,y,z,m)
				temp=self.new(x,y,z,
					m.size_x-1.block_lengths,m.size_y-1.block_lengths,m.size_z-1.block_lengths)
				temp.map_data=m
				temp
			end
		end
		alias_method(:orig_to_s,:to_s)
		def to_s
			temp=orig_to_s
			temp << [compressed_data.length].pack("N")
			temp << compressed_data
			temp
		end
	end
	
	class MultiBlockChange < BasicPacket
		tag 0x034
		directions [:server_to_client]
		attributes [[:x,:int,:chunk_len],[:z,:int,:chunk_len]]
		attr_accessor :coords,:types,:metadata
		class << self
			alias_method(:orig_read_from_socket,:read_from_socket)
			def read_from_socket(s)
				temp=orig_read_from_socket(s)
				len=s.read(2).unpack("n")[0]
					#coords is an array of packed shorts - xxxxzzzzyyyyyyyy
				temp.coords=s.read(len*2).unpack("n"*len).map {|x| [(x/0x1000),(x%0x0100),(x%0x1000 / 0x0100)]}
				temp.types=s.read(len).unpack("C"*len)
				temp.metadata=s.read(len).unpack("C"*len)
				temp
			end
		end
		alias_method(:orig_to_s,:to_s)
		def to_s
			temp=orig_to_s
			len=@coords.length
			raise "Array Sizes don't match!" if (len != @types.length || len != @metadata.length)
			temp << [len].pack("n")
			temp << @coords.map {|(x,y,z)| (x*0x1000 + z*0x0100 + y)}.pack("n"*len)
			temp << @types.pack("C"*len)
			temp << @metadata.pack("C"*len)
			temp
		end
	end
	
	class BlockChange < BasicPacket
		tag 0x35
		directions [:server_to_client]
		attributes [
			[:x,:int,:block_len],[:y,:byte,:block_len],[:z,:int,:block_len],
			[:block_type,:byte],[:block_metadata,:byte]]
	end
	
	#todo: complex entities (0x3b)
	
	class Disconnect < BasicPacket
		tag 0xFF
		directions BOTH #when it's client to server, it's a 'quit', when it's server to client, it's a 'kick'. I'm just going to call it a disconnect and not write two identical packets.
		attributes [[:reason,:string]]
	end
	
	
	
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