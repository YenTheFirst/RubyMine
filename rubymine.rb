#until I can figure out the best way of doing things, for now I'm refactoring into the simplest thing possible. more features & elegant solutions can come as they're needed.
#so, for now, there will be a single threaded, pure network oriented server, and it will make regular, single thread, blocking calls to a world model
require 'socket'

require 'packets.rb'
require 'things.rb'
require 'world_model.rb'


server=TCPServer.new 25565
world=WorldModel.new

puts "server started"

players=world.all_players #use that as our direct working copy

last_keepalive=Time.now
last_tick=Time.now

while true
	c=Kernel.select(players+[server],nil,nil,(Time.now-last_tick))
	
	if (Time.now-last_keepalive) > 30
		last_keepalive=Time.now
			#I think keepalive is more of a protocol thing than a world model thing, so the server thread will handle it.
		players.each {|p| p.to_io.write(Packet::KeepAlive.new)}
	end
	if (Time.now-last_tick) > 1 #do a 'tick' every second
		last_tick=Time.now
		world.tick
	end

	next if c.nil? #timed out on socket select
	
	if c[0].include? server
		puts "adding a new player..."
		p=Player.new
		p.socket=server.accept
		p.status=Player::STATUS_CONNECTED
		players << p
		puts "\taccepted new player. count=#{players.length}"
		c[0].delete server
	end
	
	for current_player in c[0]
#		other_players = players-[current_player]
		socket=current_player.to_io
		
		begin #catch errors in reading the packet, or writing a response
		
			packet_type=Packet::client_packet_for_tag(tag=socket.readbyte)
			raise "unknown packet 0x%02x"%tag unless packet_type
			packet=packet_type.read_from_socket(socket)
			
			
			case packet
				#THESE 3 packets are all login related. this relates to protocol.
				#the last can actually be both, depending on player state
				when Packet::ClientHandshake
					current_player.assert_status Player::STATUS_CONNECTED
					current_player.status=Player::STATUS_HANDSHAKE_SENT
					socket.write(Packet::ServerHandshake.new(Packet::ServerHandshake::NO_AUTH))
				when Packet::LoginRequest
					current_player.assert_status Player::STATUS_HANDSHAKE_SENT
					
					current_player.username=packet.username
					#theoretically, do auth here.
					socket.write(Packet::LoginResponse.new)
					current_player.status=Player::STATUS_LOGGED_IN
					world.setup_player(current_player)
				when Packet::CtoSPlayerPosLook
					#if the player is not ready yet, they send us this packet when they are ready.
					if current_player.status < Player::STATUS_READY
						current_player.status=Player::STATUS_READY
						# TODO: assert that the packet indicates the same position we told them to come in at. or, maybe the server thread will do that.
						current_player.position.update_from_object(packet)
						world.player_ready(current_player)
					else
						#world.handle(current_player,packet)
					end
				when Packet::Disconnect
					world.disconnect current_player,packet.reason
					current_player.status=Player::STATUS_DISCONNECTED
					players.delete current_player
					current_player.socket.close
				else
					world.handle(current_player,packet)
			end #of case
		
		rescue EOFError, IOError, Errno::EPIPE, Errno::ECONNRESET => e 
			STDERR.puts "communication error #{e}. disconnecting player"
			world.disconnect current_player,"connection error"
			current_player.status=PLAYER::STATUS_DISCONNECTED
			players.delete current_player
			current_player.socket.close
		end # of begin-rescue
	end # of for each player
end