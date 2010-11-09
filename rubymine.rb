require 'socket'
require 'zlib'

require 'pp'

require 'packets.rb'
require 'things.rb'
require 'mapdata.rb'


server=TCPServer.new 25565
players=[]


$simple_chunk = MapData.new(16.block_lengths,128.block_lengths,16.block_lengths)
for x in (0..15)
for z in (0..15)
	$simple_chunk[x,0,z]={:block_type=>7}
end
end

for i in (0..$simple_chunk.length-1) #because I haven't implemented .each yet
	$simple_chunk[i]={:sky_light=>255}
end

#put a little node at the 8 edges of the chunk
$simple_chunk[0,1,0]={:block_type=>2}	#NorthEast = grass
$simple_chunk[7,1,0]={:block_type=>5}	#North=wood
$simple_chunk[15,1,0]={:block_type=>18}	#NorthWest=leaves

$simple_chunk[0,1,7]={:block_type=>41}	#East = gold block
$simple_chunk[7,1,7]={:block_type=>12}	#Center=sand
$simple_chunk[15,1,7]={:block_type=>20}	#West=glass

$simple_chunk[0,1,15]={:block_type=>45}	# SouthEast = Brick
$simple_chunk[7,1,15]={:block_type=>57}	# South=Diamond Block
$simple_chunk[15,1,15]={:block_type=>86}# SouthWest=Pumpkin

def send_level(socket)	
	for x in -3..3 do 
	for z in -3..3 do
		socket.write Packet::PreChunk.new(x.chunk_lengths,z.chunk_lengths,Packet::PreChunk::INITIALIZE_CHUNK)
		socket.write Packet::MapChunk.from_map_data(x.chunk_lengths,0.chunk_lengths,z.chunk_lengths,$simple_chunk)
	end
	end
end



=begin #uncomment this for some useful debugging
class BasicSocket
	alias_method :old_write,:write
	def write(s)
		STDOUT.puts "writing the stream "
		pp s.to_s.bytes.to_a[0,20]
		old_write s
	end
end
=end

begin

last_keepalive=Time.now
last_tick=Time.now
	server_time = 0
	tick_x,tick_y,tick_z=[-3*16,3,-3*16]
while true
	c=Kernel.select(players+[server],nil,nil,0.1)
	
	if (Time.now-last_keepalive) > 30
		puts "doing keepalive"
		last_keepalive=Time.now
		players.each {|p| p.to_io.write(Packet::KeepAlive.new)}
	end

	if (Time.now-last_tick) > 1
		last_tick=Time.now
		
		server_time+=0.25
		puts "server_time = #{server_time} (day=#{server_time/24}, hour=#{server_time%24})"
		players.each {|p| p.to_io.write(Packet::TimeUpdate.new(server_time.minecraft_hours))}
		
		
		tick_x+=1
		if tick_x > 3*16
			tick_x=0
			tick_z+=1
			if tick_z > 3*16
				tick_z=0
				tick_y+=1
			end
		end
		
		#players.each {|p| p.to_io.write(Packet::BlockChange.new(tick_x.block_lengths,tick_y.block_lengths,tick_z.block_lengths,86,0))}
	end
	
	if c.nil?
		#puts "timedout on socket select."
		next
	end
	
	if c[0].include? server
		puts "adding a new player..."
		p=Player.new
		p.socket=server.accept
		players << p
		puts "\taccepted new player. count=#{players.length}"
		c[0].delete server
	end
	
	for current_player in c[0]
		other_players = players-[current_player]
		socket=current_player.to_io
		packet_type=Packet::client_packet_for_tag(tag=socket.readbyte)
		raise "unknown packet 0x%02x"%tag unless packet_type
		packet=packet_type.read_from_socket(socket)
		#puts "read the packet:"
		#pp packet
		case packet
			when Packet::ArmAnimation
				#puts "got arm animation: #{packet.entity_id} #{packet.animate}"
			when Packet::ChatMessage
				puts "got message: #{packet.message}"
				msg=Packet::ChatMessage.new("#{current_player.username}: #{packet.message}").to_s
				players.each {|p| p.to_io.write(msg)}
			when Packet::ClientHandshake
				puts "got handshake from #{packet.username}. responding with server handshake"
				socket.write(Packet::ServerHandshake.new(Packet::ServerHandshake::NO_AUTH))
			when Packet::LoginRequest
				puts "got login request from client with username #{packet.username} and password #{packet.password}. protocol version #{packet.protocol_version}. responding with login_response"
				current_player.username=packet.username
				socket.write(Packet::LoginResponse.new)
				#puts "sending level...."
				send_level(socket)
				#puts "sending initial location"
				socket.write(Packet::StoCPlayerPosLook.new(0.block_lengths,10.block_lengths,10.block_lengths,0.block_lengths,
					0.degrees,0.degrees,0))
				socket.write(Packet::ChatMessage.new("Welcome to Yen's world!"))
				
				#give them a free watch.
				socket.write(Packet::InventoryUpdate.new(
					Packet::InventoryUpdate::MAIN_INVENTORY,
					36,
					[{:item_id=>0x15b,:count=>1,:health=>0x00}]+[nil]*35))
			when Packet::CtoSPlayerPosLook
				#pp current_player.position
				current_player.position.update_from_object(packet)
				current_player.last_relative_position=current_player.position.clone
				
				if (!current_player.initial_position_set)
					
					current_player.initial_position_set=true
					#this is their first response look. this is when we know they're logged in for good. set their position, and tell them about the other players.
					
					#inform them of other players, and inform the other players we'll just do all, since it's a small map and we assume they're all visible
					other_msg=Packet::NamedEntitySpawn.from_player(current_player).to_s
					other_players.each {|p| p.to_io.write(other_msg)}
					other_players.each {|p| socket.write(Packet::NamedEntitySpawn.from_player(p)); puts "\tdid my nameentityspawn"}
				else
					other_msg = Packet::EntityTeleport.from_player(current_player)
					other_players.each {|p| p.to_io.write(other_msg)}
				end
			when Packet::PlayerLook
				#pp packet
				current_player.position.update_from_object(packet)
				other_msg = Packet::EntityLook.new(current_player.entity_id,current_player.position.yaw,current_player.position.pitch).to_s
				other_players.each {|p| p.to_io.write(other_msg)}
			when Packet::PlayerPosition
				#pp packet
				current_player.position.update_from_object(packet)
				#diff = ["x","y","z"].map {|field| (current_player.position.send(field)-current_player.last_relative_position.send(field)).to_i}
				#if diff.map(&:abs).max > 0
					#other_msg = if (diff.map(&:abs).max) > 4*32 #movements of more than 4 blocks use a teleport, not a relativemove
						current_player.last_relative_position=current_player.position.clone
					other_msg=	Packet::EntityTeleport.from_player(current_player)
					#else
					#	current_player.last_relative_position.x +=diff[0]
					#	current_player.last_relative_position.y +=diff[1]
					#	current_player.last_relative_position.z +=diff[2]
					#	Packet::EntityRelativeMove.new(current_player.entity_id,*diff)
					#end
					other_players.each {|p| p.to_io.write(other_msg)}
				#end
			when Packet::Disconnect
				puts "current player is quitting for reason: #{packet.reason}"
				players.delete current_player
				current_player.socket.close
				puts "now there are #{players.length} players"
			when Packet::OnGround
			#	puts "client tells us they are #{'not ' unless packet.is_on_ground} on the ground. good for them."
			else
			#	puts "client tells us: #{packet.inspect}"
		end
	end
end


ensure
	server.close
end