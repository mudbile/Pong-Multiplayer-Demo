extends PanelContainer

const HANDSHAKE_PORT = 5189
const GAME_CODE = 'PongDemo'

const SCORE_TO_WIN = 3
const BALL_STARTING_SPEED = 100
const PADDLE_MOTION_SPEED = 150

enum MESSAGE_TYPE {GAME_START, UPDATE_PADDLE_POS_AND_MOTION, BOUNCE_BALL, PLAYER_LOST}

onready var _connect_button = find_node("ConnectButton")
onready var _disconnect_button = find_node("DisconnectButton")
onready var _disconnect_button2 = find_node("DisconnectButton2")
onready var _status_label = find_node("StatusLabel")

onready var _left_score_label = find_node("LeftScoreLabel")
onready var _right_score_label = find_node("RightScoreLabel")

onready var _field = find_node("Field")
onready var _left_paddle = _field.find_node("LeftPaddle")
onready var _right_paddle = _field.find_node("RightPaddle")
onready var _ball = find_node("Ball")
onready var _field_rect = find_node("FieldRect").get_global_rect()

var _left_score
var _right_score
var _left_player_name
var _is_playing = false

var _ball_speed
var _ball_direction
var _left_paddle_motion
var _right_paddle_motion

func _ready():
	randomize()
	_connect_button.connect("pressed", self, "_connect_pressed")
	_disconnect_button.connect("pressed", self, "_disconnect_pressed")
	_disconnect_button2.connect("pressed", self, "_disconnect_pressed")
	_session_terminated(false)
	
	Network.connect("auto_connect_failed", self, '_auto_connect_failed')
	Network.connect('registered_as_host', self, '_registered_as_host')
	Network.connect('register_host_failed', self, '_register_host_failed')
	Network.connect('joined_to_host', self, '_joined_to_host')
	Network.connect('join_host_failed', self, '_join_host_failed')
	Network.connect('client_joined', self, '_client_joined')
	Network.connect('player_dropped', self, '_player_dropped')
	Network.connect('message_received', self, '_message_received')
	Network.connect('session_terminated', self, '_session_terminated')
	Network.connect('debug', self, '_debug')
	Network.set_network_details({
		Network.DETAILS_KEY_LOCAL_PORTS: [5999, 6000, 60001, 60002],#give a few to try
		Network.DETAILS_KEY_HANDSHAKE_PORT: HANDSHAKE_PORT,
	})
	Handshake.set_node_and_func_for_am_i_handshake_request(self, '_get_am_i_handshake_response')

func _get_am_i_handshake_response(client_info):
	if client_info.has('game-code') and client_info['game-code'] == GAME_CODE:
		return {'game-code': GAME_CODE}


func _connect_pressed():
	_status_label.text = 'Connecting...'
	_connect_button.disabled = true
	var handshake_ip = '127.0.0.1'
	var func_key = Network.broadcast_lan_find_handshakes({'game-code': GAME_CODE})
	while Network.fapi.is_func_ongoing(func_key):
		yield(Network, 'broadcast_lan_find_handshakes_completed')
	var infos = Network.fapi.get_info_for_completed_func(func_key)
	for info in infos:
		var data = info['reply-data']
		if data.has('game-code') and data['game-code'] == GAME_CODE:
			handshake_ip = info['address'][0]
			break
	Network.set_network_details({
		Network.DETAILS_KEY_HANDSHAKE_IP: handshake_ip,
	})
	Network.auto_connect()



func _debug(message):
	$DebugLabel.text += message + '\n'

func _disconnect_pressed():
	_disconnect_button.disabled = true
	Network.reset()





###################################
#        NETWORK SIGNALS          #
###################################
func _auto_connect_failed(reason):
	print('Failed to connect: %s' % reason)

func _registered_as_host(host_name, handshake_address):
	Network.enable_broadcast()
	_status_label.text = 'Waiting for player 2...'
	_disconnect_button.visible = true
	_connect_button.visible = false

func _register_host_failed(reason):
	print('Failed to register host: %s' % reason)

func _joined_to_host(host_name, address):
	_disconnect_button.visible = true
	_connect_button.visible = false

func _join_host_failed(reason):
	print('Failed to join host: %s' % reason)

func _client_joined(player_name, player_address, extra_info):
	Network.send_message({
		'type': MESSAGE_TYPE.GAME_START, 
		'start-going-left': randf() < 0.5
	})
	Network.drop_handshake()

func _player_dropped(player_name):
	print('Player dropped: %s' % player_name)
	Network.reset()

func _session_terminated(was_registered_host):
	if was_registered_host:
		Network.disable_broadcast()
	_is_playing = false
	_connect_button.visible = true
	_connect_button.disabled = false
	_disconnect_button.disabled = false
	_disconnect_button.visible = false
	_disconnect_button2.visible = false
	_status_label.text = 'Ready to Connect'
	_left_score = 0
	_right_score = 0
	_left_score_label.text = str(_left_score)
	_right_score_label.text = str(_right_score)
	_left_paddle_motion = 0
	_right_paddle_motion = 0
	_mouse_pressed_motion = 0
	_ball_speed = BALL_STARTING_SPEED
	if _left_paddle.is_connected("area_entered", self, '_ball_entered_paddle'):
		_left_paddle.disconnect("area_entered", self, '_ball_entered_paddle')
	if _right_paddle.is_connected("area_entered", self, '_ball_entered_paddle'):
		_right_paddle.disconnect("area_entered", self, '_ball_entered_paddle')

func _message_received(from_player_name, to_players, message):
	match message['type']:
		MESSAGE_TYPE.GAME_START:
			_status_label.text = ''
			_connect_button.visible = false
			_disconnect_button.visible = false
			_disconnect_button2.visible = true
			_ball.position = rect_size / 2
			_ball_direction = Vector2.LEFT if message['start-going-left'] else Vector2.RIGHT
			_is_playing = true
			_left_player_name = Network.get_host_player_name()
			if Network.is_player_host():
				_left_paddle.connect("area_entered", self, '_ball_entered_paddle')
			else:
				_right_paddle.connect("area_entered", self, '_ball_entered_paddle')
		
		
		MESSAGE_TYPE.UPDATE_PADDLE_POS_AND_MOTION:
			if from_player_name == _left_player_name:
				_left_paddle.position = message['pos']
				_left_paddle_motion = message['motion']
			else:
				_right_paddle.position = message['pos']
				_right_paddle_motion = message['motion']
		
		
		MESSAGE_TYPE.BOUNCE_BALL:
			_bounce_ball(message['randf'])
		
		
		MESSAGE_TYPE.PLAYER_LOST:
			if from_player_name == _left_player_name:
				_right_score += 1
			else:
				_left_score += 1
			_right_score_label.text = str(_right_score)
			_left_score_label.text = str(_left_score)
			if _right_score == SCORE_TO_WIN: 
				_is_playing = false
				_right_score_label.text += " WINNER"
			elif _left_score == SCORE_TO_WIN:
				_is_playing = false
				_left_score_label.text += " WINNER"
			_ball.position = rect_size / 2
			#seems fair to send it winning player's way first
			_ball_direction.x = -_ball_direction.x
			_ball_direction.y = 0
			_ball_speed = BALL_STARTING_SPEED
			if not _is_playing:
				_disconnect_button.visible = true



###################################
###################################



var _mouse_pressed_motion = 0

func _process(delta):
	if _is_playing:
		#ball
		_ball_speed += delta
		_ball.translate(_ball_speed * delta * _ball_direction)
	
		if ((_ball.position.y < _field_rect.position.y and _ball_direction.y < 0) 
		or (_ball.position.y > _field_rect.position.y + _field_rect.size.y and _ball_direction.y > 0)):
			_ball_direction.y = -_ball_direction.y
		
		if Network.get_player_name() == _left_player_name:
			if _ball.position.x < _field_rect.position.x:
				Network.send_message({'type': MESSAGE_TYPE.PLAYER_LOST})
		else:
			if _ball.position.x > _field_rect.position.x +  _field_rect.size.x:
				Network.send_message({'type': MESSAGE_TYPE.PLAYER_LOST})
		
		#paddle
		var my_paddle_motion = 0
		var my_paddle = _left_paddle if Network.get_player_name() == _left_player_name else _right_paddle
		#if OS.get_name() == 'Android' or OS.get_name() == "iOS":
		if Input.is_action_just_pressed("left_mouse"):
			if get_global_mouse_position().y < my_paddle.global_position.y:
				_mouse_pressed_motion = -1
			else:
				_mouse_pressed_motion = 1
		if Input.is_action_just_released("left_mouse"):
			_mouse_pressed_motion = 0
		my_paddle_motion = _mouse_pressed_motion
		if my_paddle_motion == 0:
			my_paddle_motion = Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
		my_paddle_motion *= PADDLE_MOTION_SPEED
		var paddle_pos = _right_paddle.position
		if Network.get_player_name() == _left_player_name:
			paddle_pos = _left_paddle.position
		Network.send_unreliable_message({
			'type': MESSAGE_TYPE.UPDATE_PADDLE_POS_AND_MOTION,
			'pos': paddle_pos,
			'motion': my_paddle_motion
		})
		
		_left_paddle.translate(Vector2(0, _left_paddle_motion * delta))
		_left_paddle.position.y = clamp(_left_paddle.position.y, 16, rect_size.y - 16)
		
		_right_paddle.translate(Vector2(0, _right_paddle_motion * delta))
		_right_paddle.position.y = clamp(_right_paddle.position.y, 16, rect_size.y - 16)




func _ball_entered_paddle(_ball):
	Network.send_message({
		'type': MESSAGE_TYPE.BOUNCE_BALL,
		'randf': randf()
	})


func _bounce_ball(random):
	_ball_direction.x = -_ball_direction.x
	_ball_speed *= 1.1
	_ball_direction.y = random * 2.0 - 1
	_ball_direction = _ball_direction.normalized()




