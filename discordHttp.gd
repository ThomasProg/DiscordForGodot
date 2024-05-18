extends Node
class_name DiscordHttp

var bot_token = ""
var appID = ""

var queue:Array[HttpRequestPostArgs] = []

var http_request = HTTPRequest.new()

func _ready():
	add_child(http_request)
	http_request.request_completed.connect(on_queue_request_completed)
	
func run_request(post:HttpRequestPostArgs):
	post.request(http_request)
	
func add_request(url:String, headers, body):
	var post = HttpRequestPostArgs.new()
	post.url = url
	post.headers = headers
	post.body = body
	
	if (queue.is_empty()):
		run_request(post)		
	
	queue.push_back(post)

func request_next():
	queue.pop_front()
	if (!queue.is_empty()):
		run_request(queue.front())

func on_queue_request_completed(result, response_code, headers, body: PackedByteArray):
	if response_code >= 200 and response_code < 300:
		print("Message sent successfully!")
		request_next()
		#print(body.get_string_from_utf8())
	else:
		print("Failed to send message with error %s / %s: %s" % [response_code, result, body.get_string_from_utf8()])
		print("Retrying:")
		if (response_code == 429):
			var response = JSON.parse_string(body.get_string_from_utf8())
			get_tree().create_timer(response["retry_after"]).timeout.connect(func(): run_request(queue.front()))
		elif (response_code == 404):
			print("Unknown interaction ; took too much time to reply to the command")
			request_next()
		else:
			run_request(queue.front())
			

func dictionary_to_packed_string_array(dictionary: Dictionary) -> PackedStringArray:
	var packed_array = PackedStringArray()

	# Iterate over the dictionary keys and add their string representations to the packed array
	for key in dictionary.keys():
		packed_array.append(key + ":" + str(dictionary[key]))

	return packed_array

# https://forum.godotengine.org/t/uploading-file-to-server-through-rest/6402/2
func send_message_with_attachment(channel_id: String, content: String, image:Image):
	
	var body = PackedByteArray()

	var json = {
		"content":content,
		"attachments": [{
		  "id": 0,
		  "description": "Image",
		  "filename": "myfilename.png"
		}]
	}
	
	var boundary = "--BodyBoundaryHere"
	var crlf = "\r\n"
	body.append_array((boundary + crlf).to_utf8_buffer())
	body.append_array(("Content-Disposition: form-data; name=\"payload_json\"" + crlf).to_utf8_buffer())
	body.append_array(("Content-Type: application/json" + crlf + crlf).to_utf8_buffer())
	body.append_array((JSON.stringify(json) + crlf).to_utf8_buffer())

	body.append_array((boundary + crlf).to_utf8_buffer())
	body.append_array(("Content-Disposition: form-data; name=\"files[0]\"; filename=\"myfilename.png\"" + crlf).to_utf8_buffer())
	body.append_array(("Content-Type: image/png" + crlf).to_utf8_buffer())
	body.append_array((crlf).to_utf8_buffer())
	body.append_array(image.save_png_to_buffer())
	body.append_array((crlf).to_utf8_buffer())

	body.append_array((boundary + "--").to_utf8_buffer())

	var url = "https://discord.com/api/v9/channels/" + channel_id + "/messages"
	
	var headers = [
		"Authorization: Bot %s" % bot_token,
		"Content-Length: " + str(body.size()),
		"Content-Type: multipart/form-data; boundary=\"BodyBoundaryHere\""
	]

	add_request(url, headers, body)
	#http_request.request_raw(url, headers, HTTPClient.METHOD_POST, body)
	
	
	
	
func respond_command_with_attachment(interaction_id: String, interaction_token: String, content: String, image:Image):
	if (image == null):
		push_error("invalid image")
	
	
	var body = PackedByteArray()

	var json = {
		"content":content,
		"attachments": [{
		  "id": 0,
		  "description": "Image of a cute little cat",
		  "filename": "myfilename.png"
		}],
		"flags": 1 << 6
	}
	
	json = {
		"type": 4,
		"data": json
	}
	
	var boundary = "--BodyBoundaryHere"
	var crlf = "\r\n"
	body.append_array((boundary + crlf).to_utf8_buffer())
	body.append_array(("Content-Disposition: form-data; name=\"payload_json\"" + crlf).to_utf8_buffer())
	body.append_array(("Content-Type: application/json" + crlf + crlf).to_utf8_buffer())
	body.append_array((JSON.stringify(json) + crlf).to_utf8_buffer())

	body.append_array((boundary + crlf).to_utf8_buffer())
	body.append_array(("Content-Disposition: form-data; name=\"files[0]\"; filename=\"myfilename.png\"" + crlf).to_utf8_buffer())
	body.append_array(("Content-Type: image/png" + crlf).to_utf8_buffer())
	body.append_array((crlf).to_utf8_buffer())
	body.append_array(image.save_png_to_buffer())
	body.append_array((crlf).to_utf8_buffer())

	body.append_array((boundary + "--").to_utf8_buffer())

	#var url = "https://discord.com/api/v9/channels/" + channel_id + "/messages"
	var url = "https://discord.com/api/v10/interactions/%s/%s/callback" % [interaction_id, interaction_token]
	
	var headers = [
		"Authorization: Bot %s" % bot_token,
		"Content-Length: " + str(body.size()),
		"Content-Type: multipart/form-data; boundary=\"BodyBoundaryHere\""
	]
	
	var httpRequestTemp = HTTPRequest.new()
	add_child(httpRequestTemp)
	
	httpRequestTemp.request_completed.connect(func (result, response_code, headers, body: PackedByteArray):
		httpRequestTemp.queue_free()
		)

	#add_request(url, headers, body)
	httpRequestTemp.request_raw(url, headers, HTTPClient.METHOD_POST, body)
	
	
func respond_command(interaction_id: String, interaction_token: String, content: String, ephemeral:bool = false):
	
	var body = PackedByteArray()

	var json = {
		"content":content,
	}
	
	if (ephemeral):
		json["flags"] = 1 << 6
	
	json = {
		"type": 4,
		"data": json
	}
	
	var boundary = "--BodyBoundaryHere"
	var crlf = "\r\n"
	body.append_array((boundary + crlf).to_utf8_buffer())
	body.append_array(("Content-Disposition: form-data; name=\"payload_json\"" + crlf).to_utf8_buffer())
	body.append_array(("Content-Type: application/json" + crlf + crlf).to_utf8_buffer())
	body.append_array((JSON.stringify(json) + crlf).to_utf8_buffer())
#
	#body.append_array((boundary + crlf).to_utf8_buffer())
	#body.append_array(("Content-Disposition: form-data; name=\"files[0]\"; filename=\"myfilename.png\"" + crlf).to_utf8_buffer())
	#body.append_array(("Content-Type: image/png" + crlf).to_utf8_buffer())
	#body.append_array((crlf).to_utf8_buffer())
	#body.append_array(image.save_png_to_buffer())
	#body.append_array((crlf).to_utf8_buffer())

	body.append_array((boundary + "--").to_utf8_buffer())

	#var url = "https://discord.com/api/v9/channels/" + channel_id + "/messages"
	var url = "https://discord.com/api/v10/interactions/%s/%s/callback" % [interaction_id, interaction_token]
	
	var headers = [
		"Authorization: Bot %s" % bot_token,
		"Content-Length: " + str(body.size()),
		"Content-Type: multipart/form-data; boundary=\"BodyBoundaryHere\""
	]

	var httpRequestTemp = HTTPRequest.new()
	add_child(httpRequestTemp)
	
	httpRequestTemp.request_completed.connect(func (result, response_code, headers, body: PackedByteArray):
		httpRequestTemp.queue_free()
		)
	
	#add_request(url, headers, body)
	httpRequestTemp.request_raw(url, headers, HTTPClient.METHOD_POST, body)
	
	

func send_message(channel_id: String, content: String):
	
	var message_data = {
		"content": content
	}
	
	var url = "https://discord.com/api/v9/channels/" + channel_id + "/messages"
	var headers = {
		"Authorization": "Bot " + bot_token,
		"Content-Type": "application/json"
	}

	add_request(url, dictionary_to_packed_string_array(headers), JSON.stringify(message_data))
	#http_request.request(url, dictionary_to_packed_string_array(headers), HTTPClient.METHOD_POST, JSON.stringify(message_data))
	
func register_slash_command(cmd: SlashCommand):
	register_slash_command_internal(cmd.name, cmd.description, cmd.options)

func register_guild_slash_command(cmd: SlashCommand, guildID:String):
	register_guild_slash_command_internal(cmd.name, guildID, cmd.description, cmd.options)
	
# https://discord.com/developers/docs/interactions/application-commands#registering-a-command
func register_slash_command_internal(name:String, description:String, options:Array[Dictionary]):
	
	var message_data = {
		"name": name,
		"description": description,
		"options": options
	}
	
	var url = "https://discord.com/api/v10/applications/%s/commands" % appID
	var headers = {
		"Authorization": "Bot " + bot_token,
		"Content-Type": "application/json"
	}

	add_request(url, dictionary_to_packed_string_array(headers), JSON.stringify(message_data))
	#http_request.request(url, dictionary_to_packed_string_array(headers), HTTPClient.METHOD_POST, JSON.stringify(message_data))
	
# https://discord.com/developers/docs/interactions/application-commands#registering-a-command
func register_guild_slash_command_internal(name:String, guildID:String, description:String, options:Array[Dictionary]):
	
	var message_data = {
		"name": name,
		"type": 1, # when used in chat
		"description": description,
		"options": options
	}
	
	#var url = "https://discord.com/api/v10/applications/%s/commands" % bot_token
	var url = "https://discord.com/api/v10/applications/%s/guilds/%s/commands" % [appID, guildID]
	var headers = {
		"Authorization": "Bot " + bot_token,
		"Content-Type": "application/json"
	}
	
	add_request(url, dictionary_to_packed_string_array(headers), JSON.stringify(message_data))
	#http_request.request(url, dictionary_to_packed_string_array(headers), HTTPClient.METHOD_POST, JSON.stringify(message_data))

