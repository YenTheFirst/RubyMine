require 'socket'
require 'zlib'

require 'pp'

require 'packets.rb'
require 'things.rb'

server=TCPServer.new 25565
players=[]


def send_level(socket)
	#generate the level. it will just be 16x16 bedrocks on the bottom, with air above.
	full_level=[
		block_type_array=("\007"+"\000"*127)*(16*16),
		metadata_array=("\000")*(block_type_array.length/2), #no metadata
		block_light_array=("\000")*(block_type_array.length/2), #no block light?
		sky_light_array=("\377")*(block_type_array.length/2) #full sky light?
	]
	#put a little node at the 8 edges of the chunk
	block_type_array[1+(0*128)+(0*128*16)]=2.chr # NorthEast = grass
	block_type_array[1+(7*128)+(0*128*16)]=5.chr # North=wood
	block_type_array[1+(15*128)+(0*128*16)]=18.chr # NorthWest=leaves
	
	block_type_array[1+(0*128)+(7*128*16)]=41.chr # East = gold block
	block_type_array[1+(7*128)+(7*128*16)]=12.chr # Center=sand
	block_type_array[1+(15*128)+(7*128*16)]=20.chr # West=glass
	
	block_type_array[1+(0*128)+(15*128*16)]=45.chr # SouthEast = Brick
	block_type_array[1+(7*128)+(15*128*16)]=57.chr # South=Diamond Block
	block_type_array[1+(15*128)+(15*128*16)]=86.chr # SouthWest=Pumpkin
	
	compressed_level=Zlib::Deflate.deflate(full_level*"")
	
	for x in -3..3 do 
	for z in -3..3 do
	#5. send pre-chunk. let's do a simple update.
	out_message = "\062" #0x32
	out_message << [x].pack("N") #X
	out_message << [z].pack("N") #Z
	out_message << "\001" #1  - load the chunk
	socket.write(out_message)
	
	#send a siendmple 16x16 chunk
	out_message = "\063" #0x33
	out_message << [x*16,0,z*16].pack("NnN") #X,y,Z
	out_message << (16-1).chr #size_x
	out_message << (128-1).chr #size_y
	out_message << (16-1).chr #size_z
	
	out_message << [compressed_level.length].pack("N") #send the size
	#puts "sending #{compressed_level.length} bytes for the level. current packet length = #{out_message.length}"
	#puts "uncompressed size = #{Zlib::Inflate.inflate(compressed_level).length}"
	out_message << compressed_level
	socket.write(out_message)
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
while true
	c=Kernel.select(players+[server],nil,nil,2)
	
	if (Time.now-last_keepalive) > 30
		puts "doing keepalive"
		last_keepalive=Time.now
		players.each {|p| p.to_io.write(Packet::KeepAlive.new)}
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
				socket.write(Packet::StoCPlayerPosLook.new(Units::BlockLength.new(0),Units::BlockLength.new(10),Units::BlockLength.new(10),Units::BlockLength.new(0),
					Units::RotationInDegrees.new(0),Units::RotationInDegrees.new(0),0))
				socket.write(Packet::ChatMessage.new("Welcome to Yen's world!"))	
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