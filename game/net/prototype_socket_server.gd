class_name PrototypeSocketServer
extends Node

signal received(peer_id: int, packet: Dictionary)
signal disconnected(peer_id: int)

const MAX_PEERS: int = 16
const MAX_PACKET_BYTES: int = 4096
const MAX_PACKETS_PER_SECOND: int = 100

var _listener: TCPServer = TCPServer.new()
var _peers: Dictionary = {}
var _next_peer_id: int = 1


func listen(port: int) -> Error:
	return _listener.listen(port, "127.0.0.1")


func _process(_delta: float) -> void:
	while _listener.is_connection_available():
		var stream: StreamPeerTCP = _listener.take_connection()
		if _peers.size() >= MAX_PEERS:
			stream.disconnect_from_host()
			continue
		stream.set_no_delay(true)
		var socket: WebSocketPeer = WebSocketPeer.new()
		socket.inbound_buffer_size = 16384
		socket.outbound_buffer_size = 262144
		socket.max_queued_packets = 128
		if socket.accept_stream(stream) != OK:
			stream.disconnect_from_host()
			continue
		_peers[_next_peer_id] = {"socket": socket, "stream": stream, "since": Time.get_ticks_msec(), "window": Time.get_ticks_msec(), "count": 0, "authenticated": false, "closing_at": 0}
		_next_peer_id += 1
	for peer_id: int in _peers.keys():
		var peer: Dictionary = _peers[peer_id]
		var socket: WebSocketPeer = peer["socket"]
		if int(peer["closing_at"]) > 0 and Time.get_ticks_msec() - int(peer["closing_at"]) > 1000:
			peer["stream"].disconnect_from_host()
			_peers.erase(peer_id)
			disconnected.emit(peer_id)
			continue
		socket.poll()
		if socket.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			_peers.erase(peer_id)
			disconnected.emit(peer_id)
			continue
		if not peer["authenticated"] and Time.get_ticks_msec() - int(peer["since"]) > 5000:
			close_peer(peer_id, "join_timeout")
			continue
		if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
			continue
		if Time.get_ticks_msec() - int(peer["window"]) >= 1000:
			peer["window"] = Time.get_ticks_msec()
			peer["count"] = 0
		while socket.get_available_packet_count() > 0:
			var bytes: PackedByteArray = socket.get_packet()
			peer["count"] += 1
			if not socket.was_string_packet():
				close_peer(peer_id, "text_required")
				break
			if bytes.size() > MAX_PACKET_BYTES or peer["count"] > MAX_PACKETS_PER_SECOND:
				close_peer(peer_id, "rate_limit")
				break
			var data: Variant = JSON.parse_string(bytes.get_string_from_utf8())
			if not data is Dictionary:
				close_peer(peer_id, "invalid_packet")
				break
			received.emit(peer_id, data)
			if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
				break


func authenticate(peer_id: int) -> void:
	if _peers.has(peer_id):
		_peers[peer_id]["authenticated"] = true


func send_to(peer_id: int, packet: Dictionary, disposable: bool = false) -> void:
	if not _peers.has(peer_id):
		return
	var socket: WebSocketPeer = _peers[peer_id]["socket"]
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	var backlog: int = socket.get_current_outbound_buffered_amount()
	if backlog > 131072:
		close_peer(peer_id, "slow_consumer")
		return
	if disposable and backlog > 16384:
		return
	socket.send_text(JSON.stringify(packet))


func close_peer(peer_id: int, reason: String) -> void:
	if _peers.has(peer_id) and int(_peers[peer_id]["closing_at"]) == 0:
		var socket: WebSocketPeer = _peers[peer_id]["socket"]
		_peers[peer_id]["closing_at"] = Time.get_ticks_msec()
		socket.close(1008, reason)


func _exit_tree() -> void:
	_listener.stop()
	for peer_id: int in _peers:
		var socket: WebSocketPeer = _peers[peer_id]["socket"]
		socket.close()
