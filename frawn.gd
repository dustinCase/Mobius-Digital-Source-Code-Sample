### Created by Dustin Macke for The Pit of Frawn ###
### 5/28/26 ###

extends CharacterBody2D

@onready var animated_sprite = $AnimatedSprite2D
@onready var animation_player = $AnimationPlayer
@onready var collision_shape = $CollisionShape2D
@onready var jump_percent_bar = $ProgressBar
@onready var ray_cast_right = $RayCastRight
@onready var ray_cast_left = $RayCastLeft
@onready var ray_cast_down_right = $CollisionShape2D/RayCastDownRight
@onready var ray_cast_down_left = $CollisionShape2D/RayCastDownLeft
@onready var gm = %GameManager
@onready var jump_sound = $Jump
@onready var walk_sound = $Walk
@onready var land_sound = $Land
@onready var jump_buildup_sound = $Jump_Buildup

@export var camera: Camera2D

const SPEED = 65.0
const MAX_JUMP = 105.0
const JUMP_INC = 270.0 # This is the ammount h increases per second
const HOR_JUMP_VEL = 210
const MAX_JUMP_VEL = 485

var jump_height = 0  # the height of the jump
var jump_frame = -1


# NOT: when Frawn is not jumping. Set after a successful jump
# CANCELED: set after a canceled jump. i.e. when a player turns to face a wall
# READY: while Frawn is still on the ground before any virtical velocity is applied
enum JUMP_STATE {NOT, CANCELED, READY, LAUNCHING, JUMPING, LANDING}
var jump_state = JUMP_STATE.NOT


# Called when the node enters the scene tree for the first time.
func _ready():
	jump_percent_bar.max_value = MAX_JUMP
	jump_percent_bar.hide()


# Dev tool for starting game in middle
func _on_game_game_state_start_override(game_state):
	if gm.game_state == gm.GS.pit:
		ready_pit()


# Sets up anything needed for the pit
func ready_pit():
	position = gm.PIT_START_POS


# Called whenever the game changes state
func _on_game_manager_game_state_change(game_state):
	if game_state == gm.GS.title:
		position = gm.TITLE_START_POS
		animated_sprite.play("walk")
		walk_sound.play()
	elif game_state == gm.GS.opening:
		pass
	elif game_state == gm.GS.fall:
		animated_sprite.play("fall into pit")
		walk_sound.stop()
	elif game_state == gm.GS.pit:
		pass
	elif game_state == gm.GS.credits:
		velocity = Vector2(0, 0)
		animated_sprite.play("walk")
		walk_sound.play()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _physics_process(delta):
	if gm.game_state == gm.GS.title:
		pass
	if gm.game_state == gm.GS.opening:
		process_opening_walk(delta)
	if gm.game_state == gm.GS.fall:
		process_fall(delta)
	if gm.game_state == gm.GS.pit:
		process_pit(delta)
	if gm.game_state == gm.GS.surface:
		process_surface(delta)
	if gm.game_state == gm.GS.credits:
		animated_sprite.play("stride")
	move_and_slide()


# Processes the opening walk cutscene
func process_opening_walk(delta):
	if position.x < gm.FALL_TRIGGER_POS_X:
		velocity.x = SPEED
	else:
		gm.set_gs(gm.GS.fall)

# Processes the opening fall cutscene
func process_fall(delta):
	velocity.x = 0
	if position.y < gm.PIT_TRIGGER_POS_Y:
		velocity += get_gravity() * delta
	else:
		gm.set_gs(gm.GS.pit)
		gm.set_ps(gm.PS.pit_1)
		
		animated_sprite.play("landing")
		jump_state = JUMP_STATE.LANDING
		land_sound.play()
		walk_sound.play()
		walk_sound.stream_paused = true


# Called from physics_process when the player is in the pit
func process_pit(delta):
	if is_on_floor() and position.y < gm.SURFACE_TRIGGER_POS_Y:
		gm.set_gs(gm.GS.surface)
	proccess_pit_surface_movement(delta)


# Called from physics_process when the player is on the surface
func process_surface(delta):
	if position.y > gm.SURFACE_TRIGGER_POS_Y:
		gm.set_gs(gm.GS.pit)
	proccess_pit_surface_movement(delta)


# Processes the players movement when they are either in the pit or on the surface
func proccess_pit_surface_movement(delta):
	 # Get the input direction and handle the movement/deceleration.
	var direction = Input.get_axis("Walk_Left", "Walk_Right")
	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta
	if is_on_wall() and velocity.y < 0:
		velocity.y = velocity.y / (1.15)
	
	# If player jumped, call jump physics
	if Input.is_action_pressed("Jump") or jump_state != JUMP_STATE.NOT or jump_state != JUMP_STATE.CANCELED:
		process_jump_physics(delta, direction)
	
	# If the player is not jumping, change the sprite direction based on input
	if jump_state != JUMP_STATE.JUMPING and jump_state != JUMP_STATE.LANDING:
		if direction == -1:
			animated_sprite.flip_h = true
		elif direction == 1:
			animated_sprite.flip_h = false
	
	if direction and (jump_state == JUMP_STATE.NOT or jump_state == JUMP_STATE.CANCELED):  # If not jumping, move based on input
		velocity.x = direction * SPEED
		var collision = move_and_collide(velocity * delta, true)
		# Check if about to collide
		if is_on_wall() or (collision and collision.get_normal().x != 0): 
			animated_sprite.play("idle")
			walk_sound.stream_paused = true
		else:
			animated_sprite.play("walk")
			walk_sound.stream_paused = not is_on_floor()  # Pauses the walking sound when not on the floor
	elif jump_state == JUMP_STATE.NOT or jump_state == JUMP_STATE.CANCELED:  # If not jumping and also not moving
		velocity.x = 0
		animated_sprite.play("idle")
		walk_sound.stream_paused = true


# Proccesses the jump. Must be called from physics
func process_jump_physics(delta, direction):
	# True when not yet in any jump state
	if (jump_state == JUMP_STATE.NOT and (Input.is_action_just_pressed("Jump") or Input.is_action_pressed("Jump")) or (jump_state == JUMP_STATE.CANCELED and Input.is_action_just_pressed("Jump"))) and is_on_floor():
		if (ray_cast_right.is_colliding() and !animated_sprite.flip_h) or (ray_cast_left.is_colliding() and animated_sprite.flip_h):
			cancel_jump()
			return
		jump_state = JUMP_STATE.READY
		walk_sound.stream_paused = true
		jump_buildup_sound.play()
		velocity.x = 0
		jump_percent_bar.show()
		jump_percent_bar.value = 0
		set_jump_frame(1)
	
	# True when player is holding [JUMP]
	elif jump_state == JUMP_STATE.READY and Input.is_action_pressed("Jump"):
		if (ray_cast_right.is_colliding() and !animated_sprite.flip_h) or (ray_cast_left.is_colliding() and animated_sprite.flip_h):
			cancel_jump()
			return
		jump_height = min(jump_height + JUMP_INC * delta, MAX_JUMP)
		jump_percent_bar.value = jump_height
		
	# True when player reseases [JUMP]
	elif jump_state == JUMP_STATE.READY and Input.is_action_just_released("Jump"):
		jump_percent_bar.hide()
		jump_state = JUMP_STATE.JUMPING
		jump_buildup_sound.stop()
		jump_sound.play()
		if direction == 0:
			if animated_sprite.flip_h:
				direction = -1
			else:
				direction = 1
		velocity.y = sqrt(jump_height * 2 * get_gravity().y) * -1
		velocity.x = HOR_JUMP_VEL * (jump_height / MAX_JUMP) * direction
		jump_height = 0
	
	# True while the player is in the air
	elif jump_state == JUMP_STATE.JUMPING:
		play_jump_animation(velocity.y)
		var colliding_body = move_and_collide(velocity*delta, true)
		if colliding_body and colliding_body.get_angle() == 0:
			velocity.x = 0
		if is_on_floor():
			jump_state = JUMP_STATE.LANDING
			land_sound.play()
			velocity.x = 0
			set_jump_frame(7)
			set_jump_frame(-1)
			animated_sprite.play("landing")
			
			colliding_body = move_and_collide(velocity*delta, true)
			while colliding_body:
				position.y -= 1
				colliding_body = move_and_collide(velocity*delta, true)
	
	# True once the player is on the ground
	elif jump_state == JUMP_STATE.LANDING and !animated_sprite.is_playing():
		jump_state = JUMP_STATE.NOT


# Resets the jump logic
func cancel_jump():
	jump_percent_bar.hide()
	jump_state = JUMP_STATE.CANCELED
	set_jump_frame(-1)
	jump_height = 0


# Takes in a vertical velocity and matches it to the corresponding frame of the jump arc via set_jump_frame()
func play_jump_animation(vel_y):
	if -MAX_JUMP_VEL < vel_y and jump_frame == 1:
		set_jump_frame(2)
	elif -MAX_JUMP_VEL * 0.385 <= vel_y and jump_frame == 2:
		set_jump_frame(3)
	elif -MAX_JUMP_VEL * 0.154 <= vel_y and jump_frame == 3:
		set_jump_frame(4)
	elif MAX_JUMP_VEL * 0.154 < vel_y and jump_frame == 4:
		set_jump_frame(5)
	elif MAX_JUMP_VEL * 0.385 < vel_y and jump_frame == 5 and !ray_cast_down_right.is_colliding() and !ray_cast_down_left.is_colliding():
		set_jump_frame(6)


# Takes in a frame represented as a number and sets the corresponding jump animation frame adjusting the player's position accordingly
func set_jump_frame(new_frame):
	# Check that new_frame is within bounds
	if new_frame < 0:
		jump_frame = new_frame
		return
	if new_frame > animated_sprite.sprite_frames.get_frame_count("jump"):
		push_error("set unexisting new_frame: ", new_frame, "/", animated_sprite.sprite_frames.get_frame_count("jump"))
	
	# Sets the correct animation frame
	animated_sprite.play("jump")
	animated_sprite.pause()
	animated_sprite.set_frame_and_progress(new_frame, 0)
	
	# Moves and resizes the player's hitbox depending on which part of the jump animation was set
	if new_frame == 1:
		position.x += 0
		collision_shape.shape.size = Vector2(44, 66)
	elif 2 <= new_frame and new_frame <= 5:
		if jump_frame == 1:
			position.x += compute_value_in_front_dir(37) * scale.x
			collision_shape.position.x += compute_value_in_front_dir(6)
			collision_shape.position.y = -22
			collision_shape.shape.size = Vector2(44, 50)
	elif new_frame == 6:
		collision_shape.position.x += compute_value_in_front_dir(27)
		collision_shape.position.y = 19
		collision_shape.shape.size = Vector2(28, 40)
	elif new_frame == 7:
		if jump_frame == 6:
			position.x += compute_value_in_front_dir(35) * scale.x
			collision_shape.position = Vector2(0, 6)
		else:
			position.x += compute_value_in_front_dir(6) * scale.x
			position.y -= 36 * scale.x
			collision_shape.position = Vector2(0, 6)
		collision_shape.shape.size = Vector2(44, 66)
	
	jump_frame = new_frame


# Computes the input value in the forwards direction.
func compute_value_in_front_dir(value):
	return value * -2 * (int(animated_sprite.flip_h) - 0.5)
