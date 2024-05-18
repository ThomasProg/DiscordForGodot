extends Node
class_name DiscordGateway

# https://discord.com/developers/docs/topics/opcodes-and-status-codes#gateway-gateway-close-event-codes

signal onConnected()
signal onAuthentificated()

signal onMessageCreated(content)
signal onSlashCommand(content)

var websocket
var gateway_url = "wss://gateway.discord.gg/?v=9&encoding=json" # Discord gateway URL
var bot_token = ""
var isLoggedIn = false

var slashCmds:Dictionary = {}

var lastSequenceNumber = null
var resumeGatewayUrl:String
var sessionID:String

func register_slash_command(cmd: SlashCommand):
	slashCmds[cmd.name] = cmd

# Receive ALL available packets
func receive():
	#var buffer = PackedByteArray()
	#while websocket.get_available_packet_count():
		#buffer.append_array(websocket.get_packet())
		#
	#return buffer
	
	return websocket.get_packet()

func handle_message_create(event_payload: Dictionary):
	var message_id = event_payload["id"]
	var channel_id = event_payload["channel_id"]
	var guild_id = event_payload["guild_id"]
	var author = event_payload["author"]
	var content = event_payload["content"]
	var timestamp = event_payload["timestamp"]
	var edited_timestamp = event_payload["edited_timestamp"]
	var mentions = event_payload["mentions"]
	var mention_roles = event_payload["mention_roles"]
	var attachments = event_payload["attachments"]
	var embeds = event_payload["embeds"]
	
	onMessageCreated.emit(content)

func handle_slash_command(event_payload: Dictionary):
	
	var cmdArgs = SlashCommand.Args.new()
	cmdArgs.id = event_payload["id"]
	cmdArgs.token = event_payload["token"]
	cmdArgs.member = event_payload["member"]
	cmdArgs.payload = event_payload
	
	var data:Dictionary = event_payload["data"]
	cmdArgs.cmdname = data["name"]
	cmdArgs.type = data["type"]
	cmdArgs.options = data.get("options")
	
	var cmd = slashCmds.get(cmdArgs.cmdname)
	if (cmd != null):
		onSlashCommand.emit(cmd, cmdArgs)
		cmd.run(cmdArgs)
	else:
		push_error("Invalid slash command received.")

func handle_guild_member_update(event_payload: Dictionary):
	
	var cmdArgs = SlashCommand.Args.new()
	#cmdArgs.id = event_payload["id"]
	#cmdArgs.token = event_payload["token"]
	#cmdArgs.member = event_payload["member"]
	#


func handle_event(event_name: String, event_payload: Dictionary):
	print(event_name)
	match event_name:
		"READY":
			resumeGatewayUrl = event_payload["resume_gateway_url"]
			sessionID = event_payload["session_id"]
		"MESSAGE_CREATE":
			handle_message_create(event_payload)
		"INTERACTION_CREATE":
			handle_slash_command(event_payload)
		"GUILD_MEMBER_ADD":
			handle_guild_member_update(event_payload)
		"GUILD_MEMBER_UPDATE":
			handle_guild_member_update(event_payload)
		"THREAD_MEMBERS_UPDATE":
			handle_guild_member_update(event_payload)
			
		#"MESSAGE_UPDATE":
			#handle_message_update(event_payload)
		#"GUILD_CREATE":
			#handle_guild_create(event_payload)
		# Handle other event types as needed

func handle_gateway_packet(data: String):
	var payload = JSON.parse_string(data)
	var opcode:int = int(payload["op"])

	# https://discord.com/developers/docs/topics/opcodes-and-status-codes
	match opcode:
		0:  # Dispatch
			if ("t" in payload and "d" in payload):
				var event_name = payload["t"]
				var event_payload = payload["d"]
				lastSequenceNumber = payload["s"]
				handle_event(event_name, event_payload)

		1: # heartbeat immediate request
			sendHeartbeat()
			
		7: # Reconnect ; should resume immediately
			print("Should reconnect")
			#await login(bot_token)
			await resume()
			
		9: # Invalid session; 	The session has been invalidated. You should reconnect and identify/resume accordingly.
			print("invalid session")
			if (payload["d"]):
				print("can resume")
				await resume()
			else:
				print("cannot resume")
				await login(bot_token)
				
			
		10: # hello : must send heartbeat every x ms
			get_tree().create_timer(0.9 * payload["d"]["heartbeat_interval"] / 1000.0).timeout.connect(sendHeartbeat)
			
		11: # heartbeat ack ; heartbeat received
			print("heartbeat sent successfully")

func connect_to_gateway():
	while (websocket.get_ready_state() != WebSocketPeer.STATE_OPEN):
		websocket.poll()
		await get_tree().process_frame
		
	onConnected.emit()

func listen():
	while (true):
		websocket.poll()
		
		var state = websocket.get_ready_state()
		if state == WebSocketPeer.STATE_OPEN:
			while websocket.get_available_packet_count():
				var packets = receive()
				var message = packets.get_string_from_utf8()
				handle_gateway_packet(message)
					
		elif state == WebSocketPeer.STATE_CLOSING:
			var code = websocket.get_close_code()
			var reason = websocket.get_close_reason()
			var clean = (code != -1)
			on_connection_closing(clean, code, reason)
			# Keep polling to achieve proper close.

		elif state == WebSocketPeer.STATE_CLOSED:
			var code = websocket.get_close_code()
			var reason = websocket.get_close_reason()
			var clean = (code != -1)
			on_connection_closed(clean, code, reason)

		await get_tree().process_frame	

func login(botToken:String):
	bot_token = botToken
	
	if (websocket != null):
		(websocket as WebSocketPeer).close()
	
	websocket = WebSocketPeer.new()
	websocket.inbound_buffer_size *= 100
	websocket.outbound_buffer_size *= 100
	websocket.max_queued_packets *= 100
	websocket.encode_buffer_max_size *= 10
	websocket.connect_to_url(gateway_url)
	
	await connect_to_gateway()
	await authenticate_with_discord()
	await listen()

func resume():
	if (websocket != null):
		(websocket as WebSocketPeer).close()
	websocket.connect_to_url(resumeGatewayUrl)
	await connect_to_gateway()

	var resume_payload = {
	  "op": 6,
	  "d": {
		"token": bot_token,
		"session_id": sessionID,
		"seq": lastSequenceNumber
	  }
	}

	websocket.send_text(JSON.stringify(resume_payload))

	var state = websocket.get_ready_state()
	while (state == WebSocketPeer.STATE_CONNECTING):
		await get_tree().process_frame
		websocket.poll()	
		state = websocket.get_ready_state()

	match state:
		WebSocketPeer.STATE_OPEN:
			onAuthentificated.emit()
		WebSocketPeer.STATE_CLOSING:
			push_error("Connection is closing before authentification")
		WebSocketPeer.STATE_CLOSED:
			push_error("Connection has been closed before authentification")



func on_connection_closed(clean, code, reason):
	print("WebSocket connection closed. Clean:", clean, "Code:", code, "Reason:", reason)
	
	if (clean):
		await login(bot_token)
	else:
		await resume()


func on_connection_closing(clean, code, reason):
	print("WebSocket connection closing. Clean:", clean, "Code:", code, "Reason:", reason)

func sendHeartbeat():
	var heartbeat_payload = {
		"op": 1,
		"d": lastSequenceNumber
	}

	print("heartbeat sent : ", JSON.stringify(heartbeat_payload))
	websocket.send_text(JSON.stringify(heartbeat_payload))

func authenticate_with_discord():
	var auth_payload = {
		"op": 2,
		"d": {
			"token": bot_token,
			# 513 : receive messages etc
			# 8 : admin, but only receives slash commands
			"intents": 513, # Replace with your desired intents
			"properties": {
				"$os": "linux",
				"$browser": "python",
				"$device": "python"
			}
		}
	}

	websocket.send_text(JSON.stringify(auth_payload))

	var state = websocket.get_ready_state()
	while (state == WebSocketPeer.STATE_CONNECTING):
		await get_tree().process_frame
		websocket.poll()	
		state = websocket.get_ready_state()

	match state:
		WebSocketPeer.STATE_OPEN:
			onAuthentificated.emit()
		WebSocketPeer.STATE_CLOSING:
			push_error("Connection is closing before authentification")
		WebSocketPeer.STATE_CLOSED:
			push_error("Connection has been closed before authentification")


