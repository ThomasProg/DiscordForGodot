class_name HttpRequestPostArgs

var url:String
var headers 
var body




func request(httpRequest):
	if (body is String):
		httpRequest.request(url, headers, HTTPClient.METHOD_POST, body)	
	else:
		httpRequest.request_raw(url, headers, HTTPClient.METHOD_POST, body)	
