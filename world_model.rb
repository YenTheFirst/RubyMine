require 'packets.rb'
require 'things.rb'
require 'mapdata.rb'

require 'pp'
#this will be factored out more, later.
#for now, this will be one object which holds the world state, can handle packeted instructions to change that state, and will automatically call out to the correct players in the world with neccessary updates

class WorldModel

	attr_accessor :all_players, :map, :current_time
	
	def initialize
		#@map will be a two-dimensional array of map chunks
		#this won't support chunks with negative coordinates. this will have to be worked in later.
		@map=Array.new(3) do |ix|
			Array.new(3) do |iz|
				simple_chunk = MapData.new(Units::BlockLength.new(16),Units::BlockLength.new(128),Units::BlockLength.new(16))
				for x in (0..15);for z in (0..15);simple_chunk[x,0,z]={:block_type=>7};end;end
				
				for i in (0..simple_chunk.length-1) #because I haven't implemented .each yet
					simple_chunk[i]={:sky_light=>255}
				end
				
				#put a little node at the 8 edges of the chunk
				simple_chunk[0,1,0]={:block_type=>2}	#NorthEast = grass
				simple_chunk[7,1,0]={:block_type=>5}	#North=wood
				simple_chunk[15,1,0]={:block_type=>18}	#NorthWest=leaves
				
				simple_chunk[0,1,7]={:block_type=>41}	#East = gold block
				simple_chunk[7,1,7]={:block_type=>12}	#Center=sand
				simple_chunk[15,1,7]={:block_type=>20}	#West=glass
				
				simple_chunk[0,1,15]={:block_type=>45}	# SouthEast = Brick
				simple_chunk[7,1,15]={:block_type=>57}	# South=Diamond Block
				simple_chunk[15,1,15]={:block_type=>86}# SouthWest=Pumpkin
				
				#a bit of pre-loading for faster client connect
				simple_chunk.compress
				
				simple_chunk
			end
		end
		
		@current_time=0.milli_hours
		@all_players=[]
	end

	def tick # we will tick once every real-world second.
		#go with the standard timing of 1 real-world-second to 20 milli_hours
		#this leads to a 20 minute (1200 second = 24000 milli_hour) day/night cycle.
		@current_time.val +=20# = @current_time+200.milli_hours
		time_msg = Packet::TimeUpdate.new(@current_time).to_s
		@all_players.each {|p| p.to_io.write(time_msg)}
	end
	
	def setup_player(p)
		#in the future, we'll look up where the player left off, determine their spawn point & starting point, and send them map data for where they're starting in the world
		#for now, we'll just start & spawn everyone at (16,16), and send them map chunks [0,0]..[2,2]
		@map.each_with_index do |z_row,ix|
			z_row.each_with_index do |chunk,iz|
				p.to_io.write Packet::PreChunk.new(Units::ChunkLength.new(ix),Units::ChunkLength.new(iz),Packet::PreChunk::INITIALIZE_CHUNK)
				p.to_io.write Packet::MapChunk.from_map_data(Units::ChunkLength.new(ix),Units::ChunkLength.new(0),Units::ChunkLength.new(iz),chunk)
			end
		end
		#set spawn point
		p.to_io.write Packet::SpawnPosition.new(16.block_lengths,2.block_lengths,16.block_lengths)
		
		
		#set inventory
		#give them a free watch & compass. yay free stuff!
		p.to_io.write(Packet::InventoryUpdate.new(
			Packet::InventoryUpdate::MAIN_INVENTORY,
			36,
			[{:item_id=>0x15b,:count=>1,:health=>0x00},{:item_id=>0x159,:count=>1,:health=>0x00}]+[nil]*34))
		
		#give initial starting point
		p.to_io.write(Packet::StoCPlayerPosLook.new(16.block_lengths,(3.63).block_lengths,(2.01).block_lengths,16.block_lengths,
			0.degrees,0.degrees,1))

		#write an MOTD or something.
		p.to_io.write(Packet::ChatMessage.new("Welcome to Yen's world!"))
	end
	
	def player_ready(player)
		#the player client has indicated that they're ready to enter the world
		
		#inform all the other player clients (TODO: in range) of the entity spawn
		#inform player of all entities (TODO: in range)
		other_msg=Packet::NamedEntitySpawn.from_player(player).to_s
		(all_players-[player]).each do |other_p|
			other_p.to_io.write(other_msg)
			player.to_io.write(Packet::NamedEntitySpawn.from_player(other_p))
		end
		join_msg= Packet::ChatMessage.new("#{player.username} has joined").to_s
		all_players.each do |p|
			p.to_io.write join_msg
		end
	end
	
	def disconnect(player,reason)
		#for now, the server will handle the removing of player from the all_players
		#tell everyone else (TODO: in range) the player is gone
		delete_msg = Packet::DestroyEntity.new(player.entity_id).to_s
		bye_msg = Packet::ChatMessage.new("#{player.username} has left: #{reason}").to_s
		(all_players - [player]).each do |other_p|
			other_p.to_io.write delete_msg
			other_p.to_io.write bye_msg
		end
	end
	def handle(player,packet)
		other_players = all_players-[player]
		
		case packet
			when Packet::ChatMessage
				msg=Packet::ChatMessage.new("#{player.username}: #{packet.message}").to_s
				players.each {|p| p.to_io.write(msg)}
			when Packet::CtoSPlayerPosLook
				#pp packet
				
				player.position.update_from_object(packet)
				other_msg = Packet::EntityTeleport.from_player(player).to_s
				other_players.each {|p| p.to_io.write(other_msg)}
						when Packet::PlayerLook
				player.position.update_from_object(packet)
				other_msg = Packet::EntityLook.new(player.entity_id,player.position.yaw,player.position.pitch).to_s
				other_players.each {|p| p.to_io.write(other_msg)}
			when Packet::PlayerLook
				#pp packet
				
				player.position.update_from_object(packet)
				other_msg = Packet::EntityLook.new(player.entity_id,player.position.yaw,player.position.pitch).to_s
				other_players.each {|p| p.to_io.write(other_msg)}
			when Packet::PlayerPosition
				#pp packet
				
				player.position.update_from_object(packet)
				other_msg=Packet::EntityTeleport.from_player(player).to_s
				other_players.each {|p| p.to_io.write(other_msg)}
			else
				#puts "unhandled packet type #{packet.class}"
		end
	end
end