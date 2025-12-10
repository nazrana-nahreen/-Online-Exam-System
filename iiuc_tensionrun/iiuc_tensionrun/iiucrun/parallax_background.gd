extends ParallaxBackground

var obstacles = [
	preload("res://assets/img/obstacles/1.png"),
	preload("res://assets/img/obstacles/2.png"),
	preload("res://assets/img/obstacles/3.png"),
	preload("res://assets/img/obstacles/4.png"),
	preload("res://assets/img/obstacles/5.png"),
	preload("res://assets/img/obstacles/6.png"),
	preload("res://assets/img/obstacles/7.png"),
]

# NEW: Preload coin and bank scenes
var coin_scene = preload("res://scenes/coin.tscn")
var bank_scene = preload("res://scenes/bank.tscn")

@export var scroll_speed_base := -400.0
@export var obstacle_spawn_interval := 1.0
@export var coin_spawn_interval := 1.2  # NEW: Coins spawn more frequently than obstacles
var game_running := false
var score := 0
var coins := 0  # NEW: Coin counter
var highscore := 0
const SCORE_MODIFIER := 100
# Add these variables at the top with your other variables
var bank_count := 0  # NEW: Track how many banks have appeared
var current_bank_cost := 5  # NEW: Current cost for the bank (starts at 5)
const BASE_BANK_COST := 5 # NEW: Starting cost for first bank
const BANK_COST_INCREMENT := 3 # NEW: Coins needed to pass bank
const BANK_SPAWN_TIME := 10.0  # NEW: Bank appears after 10 seconds
const HIGHSCORE_FILE_PATH := "user://highscore.save"

var obstacle_timer := 0.0
var coin_timer := 0.0  # NEW: Timer for coin spawning
var bank_timer := 0.0  # NEW: Timer for bank spawning
var bank_spawned := false  # NEW: Track if bank has been spawned
var game_time := 0.0
var ground_y := 470
var spawned_obstacles: Array = []
var spawned_coins: Array = []  # NEW: Track spawned coins
var spawned_banks: Array = []  # NEW: Track spawned banks

# Bus movement variables
var bus_sprite: Sprite2D = null
var bus_initial_position: Vector2
var bus_moving := false
var bus_disappeared := false
var bus_speed := 50.0
var bus_acceleration_time := 8.0

# Sound variables
var crash_sound = preload("res://assets/sound/Iiuc soud.wav")
var coin_sound = preload("res://assets/sound/coin.wav")  # NEW: Add your coin sound
var bank_sound = preload("res://assets/sound/bank.wav")  # NEW: Add your bank sound
var crash_player = null
var coin_player = null  # NEW: Coin sound player
var bank_player = null  # NEW: Bank sound player

func _ready():
	$ParallaxLayer/TextureRect.texture = preload("res://assets/img/background/bg.png")
	$ParallaxLayer.motion_mirroring.x = $ParallaxLayer/TextureRect.texture.get_width()
	
	# Load highscore from file
	load_highscore()
	
	update_score()
	update_coin_display()  # NEW: Initialize coin display
	update_highscore_display()
	
	# Prepare sound players
	setup_sound_players()
	
	# Initialize UI state
	initialize_ui()

	
	# Get reference to the bus sprite
	bus_sprite = get_node_or_null("../bus")
	if not bus_sprite:
		bus_sprite = get_node_or_null("bus")
	
	if bus_sprite:
		bus_initial_position = bus_sprite.position
		print("Bus found at position: ", bus_initial_position)
		print("Bus node name: ", bus_sprite.name)
	else:
		print("Bus sprite not found - Please move the bus sprite outside of ParallaxLayer")
		print("The bus should be a direct child of the main scene, not inside ParallaxLayer")
		print("Available nodes in parent:")
		if get_parent():
			for child in get_parent().get_children():
				print("  - ", child.name, " (", child.get_class(), ")")


# NEW: Setup sound players
func setup_sound_players():
	# Crash sound player
	crash_player = AudioStreamPlayer.new()
	crash_player.stream = crash_sound
	crash_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(crash_player)
	
	# Coin sound player
	coin_player = AudioStreamPlayer.new()
	coin_player.stream = coin_sound
	coin_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(coin_player)
	
	# Bank sound player
	bank_player = AudioStreamPlayer.new()
	bank_player.stream = bank_sound
	bank_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(bank_player)

func initialize_ui():
	# Show initial UI elements
	if has_node("../HUD"):
		var hud = $"../HUD"
		
		# Show IIUCTAG if it exists
		if hud.has_node("IIUCTAG"):
			hud.get_node("IIUCTAG").show()
				# Hide GORIB label initially
		if hud.has_node("GORIB"):
			hud.get_node("GORIB").hide()
			print("GORIB label hidden initially") 
		# Show START label if it exists
		if hud.has_node("START"):
			hud.get_node("START").show()
		
		# Hide GameOver button initially
		if hud.has_node("RESTART"):
			hud.get_node("RESTART").hide()
		
		

func _process(delta):
	if game_running:
		game_time += delta
		bank_timer += delta  # NEW: Increment bank timer
		
		var speed_increase_factor = clamp(1.0 + (game_time / 10.0) * 0.55, 1.0, 7.0)
		
		scroll_speed_base = -400.0 * speed_increase_factor
		
		# Spawn obstacles faster as speed increases
		obstacle_spawn_interval = max(2.5, 2.0 / speed_increase_factor)
		# NEW: Coin spawn interval also decreases with speed but remains frequent
		coin_spawn_interval = max(0.8, 1.2 / speed_increase_factor)
		
		scroll_offset.x += scroll_speed_base * delta
		
		score += 25
		update_score()
		
		# Handle obstacle spawning
		obstacle_timer -= delta
		if obstacle_timer <= 0:
			spawn_obstacle()
			obstacle_timer = obstacle_spawn_interval
		
		# NEW: Handle coin spawning
		coin_timer -= delta
		if coin_timer <= 0:
			spawn_coin()
			coin_timer = coin_spawn_interval
		
		# NEW: Handle bank spawning (every 10 seconds)
		if bank_timer >= BANK_SPAWN_TIME and not bank_spawned:
			spawn_bank()
			bank_spawned = true
			bank_timer = 0.0  # Reset for next bank

		# Move obstacles leftwards
		for obstacle in spawned_obstacles.duplicate():
			if is_instance_valid(obstacle):
				obstacle.position.x += scroll_speed_base * delta
				
				if obstacle.position.x < -100:
					obstacle.queue_free()
					spawned_obstacles.erase(obstacle)
		
		# NEW: Move coins leftwards
		for coin in spawned_coins.duplicate():
			if is_instance_valid(coin):
				coin.position.x += scroll_speed_base * delta
				
				if coin.position.x < -100:
					coin.queue_free()
					spawned_coins.erase(coin)
		
		# NEW: Move banks leftwards
		for bank in spawned_banks.duplicate():
			if is_instance_valid(bank):
				bank.position.x += scroll_speed_base * delta
				
				# Remove bank when it goes off screen (no penalty)
				if bank.position.x < -100:
					bank.queue_free()
					spawned_banks.erase(bank)
					bank_spawned = false  # Allow next bank to spawn after 10 seconds

		# Handle bus movement
		if bus_sprite and not bus_disappeared:
			if game_time >= bus_acceleration_time and not bus_moving:
				print("Game time: ", game_time, " - Bus accelerating to leave forever!")
				accelerate_bus_offscreen()
			else:
				bus_sprite.position.x += bus_speed * delta
				
				var screen_width = get_viewport().get_visible_rect().size.x
				if bus_sprite.position.x > screen_width + 100:
					bus_disappeared_permanently()
		elif not bus_sprite and not bus_disappeared:
			if int(game_time) % 3 == 0 and game_time - int(game_time) < 0.1:
				print("Bus sprite not found - game time: ", game_time)

		# Jump input when game running
		if Input.is_action_just_pressed("ui_accept"):
			jump()
	else:
		# Start game on spacebar or enter if game not running
		if Input.is_action_just_pressed("ui_accept"):
			if not is_game_over_button_visible():
				start_game()

func is_game_over_button_visible() -> bool:
	if has_node("../HUD"):
		var hud = $"../HUD"
		if hud.has_node("RESTART"):
			return hud.get_node("RESTART").visible
	return false

func add_obs(obs, x, y):
	obs.position = Vector2i(x, y)
	obs.body_entered.connect(hit_obs)
	add_child(obs)
	obstacles.append(obs)

func remove_obs(obs):
	obs.queue_free()
	obstacles.erase(obs)
	
func hit_obs(body):
	if body.name == "Dino":
		game_over()

# NEW: Function to handle coin collection
func hit_coin(body):
	if body.name == "Dino":
		coins += 1
		update_coin_display()
		print("Coin collected! Total coins: ", coins)
		
		# Play coin collection sound
		if coin_player and coin_player.stream:
			coin_player.play()
		
		# Remove the collected coin from the scene
		for coin in spawned_coins.duplicate():
			if is_instance_valid(coin):
				# Check if this is the coin that was hit by comparing positions
				if coin.global_position.distance_to(body.global_position) < 50:
					coin.queue_free()
					spawned_coins.erase(coin)
					break

# NEW: Function to handle bank interaction
# Modify your existing hit_bank function
func hit_bank(body):
	if body.name == "Dino":
		var required_coins = current_bank_cost
		
		if coins >= required_coins:
			# Player has enough coins - deduct coins and let them pass through
			coins -= required_coins
			update_coin_display()
			print("Coins paid to bank! Cost: ", required_coins, " Remaining coins: ", coins)
			
			# Play bank transaction sound
			if bank_player and bank_player.stream:
				bank_player.play()
			
			# Find and remove this specific bank from collision
			for bank in spawned_banks.duplicate():
				if is_instance_valid(bank):
					if bank.global_position.distance_to(body.global_position) < 100:
						# Disable collision so dino can pass through
						if bank.has_method("set_collision_layer_value"):
							bank.set_collision_layer_value(1, false)
							bank.set_collision_mask_value(1, false)
						
						# Alternative method if the above doesn't work
						for child in bank.get_children():
							if child is CollisionShape2D:
								child.set_deferred("disabled", true)
						
						# Make bank slightly transparent to show it's been paid
						if bank.has_node("bank"):
							bank.get_node("bank").modulate.a = 0.5
						elif bank.get_child_count() > 0:
							# Try to find sprite in children
							for child in bank.get_children():
								if child is Sprite2D:
									child.modulate.a = 0.5
									break
						break
		else:
			# Not enough coins - game over
			game_over_insufficient_coins()

func jump():
	var jump_sound_node = get_node_or_null("../Dino/JumpSound")
	if jump_sound_node:
		jump_sound_node.play()
	else:
		print("JumpSound node not found at ../Dino/JumpSound")



# Modify your start_game function to reset bank progression
func start_game():
	get_tree().paused = false
	game_running = true
	score = 0
	coins = 0  # Reset coins
	bank_count = 0  # NEW: Reset bank count
	current_bank_cost = BASE_BANK_COST  # NEW: Reset bank cost to starting value
	game_time = 0.0
	bank_timer = 0.0  # Reset bank timer
	bank_spawned = false  # Reset bank spawn flag
	scroll_speed_base = -400.0
	obstacle_timer = 0.0
	coin_timer = 0.0  # Reset coin timer
	update_score()
	update_coin_display()  # Update coin display

	reset_bus_for_new_game()
	# Hide GORIB label when starting new game
	if has_node("../HUD"):
		var hud = $"../HUD"
		if hud.has_node("GORIB"):
			hud.get_node("GORIB").hide()
			print("GORIB label hidden for new game")
			
	# Clear existing obstacles, coins, and banks
	for obs in spawned_obstacles:
		if is_instance_valid(obs):
			obs.queue_free()
	spawned_obstacles.clear()
	
	# Clear coins
	for coin in spawned_coins:
		if is_instance_valid(coin):
			coin.queue_free()
	spawned_coins.clear()
	
	# Clear banks
	for bank in spawned_banks:
		if is_instance_valid(bank):
			bank.queue_free()
	spawned_banks.clear()

	hide_start_ui()
	hide_game_over_ui()
	
	print("New game started! Banks will cost: 5, 7, 9, 11, 13... coins")

func hide_start_ui():
	if has_node("../HUD"):
		var hud = $"../HUD"
		
		if hud.has_node("IIUCTAG"):
			hud.get_node("IIUCTAG").hide()
		
		if hud.has_node("START"):
			hud.get_node("START").hide()

func hide_game_over_ui():
	if has_node("../HUD"):
		var hud = $"../HUD"
		
		if hud.has_node("GameOverLabel"):
			hud.get_node("GameOverLabel").hide()
		
		if hud.has_node("RESTART"):
			hud.get_node("RESTART").hide()

func show_game_over_ui():
	if has_node("../HUD"):
		var hud = $"../HUD"
		
		
		
		if hud.has_node("RESTART"):
			var restart_node = hud.get_node("RESTART")
			
			if restart_node is Button:
				restart_node.show()
				if not restart_node.pressed.is_connected(restart_game):
					restart_node.pressed.connect(restart_game)
			elif restart_node is CanvasLayer:
				restart_node.show()
				for child in restart_node.get_children():
					if child is Button:
						if not child.pressed.is_connected(restart_game):
							child.pressed.connect(restart_game)
						break
			else:
				print("RESTART node type: ", restart_node.get_class())
				restart_node.show()

func restart_game():
	print("Restart button pressed")
	# Stop the crash sound immediately when restart is pressed
	if crash_player and crash_player.is_playing():
		crash_player.stop()
		print("Crash sound stopped due to restart")
	start_game()

func update_score():
	if has_node("../HUD"):
		var hud = $"../HUD"
		if hud.has_node("ScoreLabel"):
			hud.get_node("ScoreLabel").text = "সিজিপিএ: " + str(score / SCORE_MODIFIER)
	else:
		print("HUD node not found!")

# NEW: Function to update coin display
func update_coin_display():
	if has_node("../HUD"):
		var hud = $"../HUD"
		# Try multiple possible names for the coin label
		var coin_label = null
		var possible_names = ["CoinLabel", "coin", "Coin", "COIN", "coins", "Coins", "COINS"]
		
		for name in possible_names:
			if hud.has_node(name):
				coin_label = hud.get_node(name)
				break
		
		if coin_label:
			coin_label.text = "টাকা: " + str(coins)
			print("Coin display updated in UI: ", coins)
		else:
			print("No coin label found! Available HUD children:")
			for child in hud.get_children():
				print("  - ", child.name, " (", child.get_class(), ")")
			print("Please add a Label node named 'CoinLabel' to your HUD")
	else:
		print("HUD node not found!")

func update_highscore_display():
	if has_node("../HUD"):
		var hud = $"../HUD"
		if hud.has_node("HIGHSCORE"):
			hud.get_node("HIGHSCORE").text = "কামব্যাক স্কোর: " + str(highscore)
	else:
		print("HUD node not found!")

func check_and_update_highscore():
	var current_score = score / SCORE_MODIFIER
	if current_score > highscore:
		highscore = current_score
		save_highscore()
		update_highscore_display()
		print("New highscore: " + str(highscore))

func save_highscore():
	var file = FileAccess.open(HIGHSCORE_FILE_PATH, FileAccess.WRITE)
	if file:
		file.store_32(highscore)
		file.close()
		print("Highscore saved: " + str(highscore))
	else:
		print("Failed to save highscore")

func load_highscore():
	if FileAccess.file_exists(HIGHSCORE_FILE_PATH):
		var file = FileAccess.open(HIGHSCORE_FILE_PATH, FileAccess.READ)
		if file:
			highscore = file.get_32()
			file.close()
			print("Highscore loaded: " + str(highscore))
		else:
			print("Failed to load highscore file")
	else:
		highscore = 0
		print("No highscore file found, starting with 0")

var air_obstacle_indices = [1, 3, 5]

func spawn_obstacle():
	var index = randi() % obstacles.size()
	var texture = obstacles[index]
	
	var area = Area2D.new()
	var sprite = Sprite2D.new()
	sprite.texture = texture
	sprite.scale = Vector2(0.07, 0.07)
	area.add_child(sprite)
	
	var collision_shape = CollisionShape2D.new()
	var rect_shape = RectangleShape2D.new()
	var tex_size = texture.get_size() * sprite.scale
	rect_shape.extents = tex_size * 0.5
	collision_shape.shape = rect_shape
	area.add_child(collision_shape)
	
	var screen_width = get_viewport().get_visible_rect().size.x
	var spawn_x = screen_width + 100
	
	# Check if this position conflicts with any existing banks
	var safe_to_spawn = true
	for bank in spawned_banks:
		if is_instance_valid(bank):
			var distance = abs(spawn_x - bank.position.x)
			if distance < MIN_BANK_OBSTACLE_DISTANCE:
				safe_to_spawn = false
				print("Obstacle spawn blocked due to nearby bank")
				break
	
	# If not safe to spawn, skip this obstacle
	if not safe_to_spawn:
		area.queue_free()
		return

	
	if index in air_obstacle_indices:
		area.position = Vector2(screen_width + 100, ground_y - 30)
	else:
		area.position = Vector2(screen_width + 100, ground_y + 90)
	
	area.body_entered.connect(hit_obs)
	add_child(area)
	spawned_obstacles.append(area)

# NEW: Function to spawn coins
func spawn_coin():
	var coin_instance = coin_scene.instantiate()
	
	var screen_width = get_viewport().get_visible_rect().size.x
	
	# Randomly place coins on ground or in air
	if randi() % 2 == 0:
		# Ground coin
		coin_instance.position = Vector2(screen_width + 100, ground_y + 70)
	else:
		# Air coin
		coin_instance.position = Vector2(screen_width + 100, ground_y - 30)
	
	# Connect the signal for coin collection
	if coin_instance.has_signal("body_entered"):
		coin_instance.body_entered.connect(hit_coin)
	
	add_child(coin_instance)
	spawned_coins.append(coin_instance)
	print("Coin spawned at position: ", coin_instance.position)


# Replace your existing spawn_bank() function with this improved version:

const MIN_BANK_OBSTACLE_DISTANCE := 300.0  # Reduced for better gameplay
const MAX_SPAWN_ATTEMPTS := 10  # Prevent infinite loops

func can_spawn_bank_at(x_position: float) -> bool:
	# Check distance from any existing obstacles
	for obstacle in spawned_obstacles:
		if is_instance_valid(obstacle):
			var distance = abs(x_position - obstacle.position.x)
			if distance < MIN_BANK_OBSTACLE_DISTANCE:
				print("Bank spawn blocked by obstacle at distance: ", distance)
				return false
	
	# Check distance from any existing banks
	for bank in spawned_banks:
		if is_instance_valid(bank):
			var distance = abs(x_position - bank.position.x)
			if distance < MIN_BANK_OBSTACLE_DISTANCE:
				print("Bank spawn blocked by another bank at distance: ", distance)
				return false
	
	return true



# Modify your spawn_bank function to update the cost
func spawn_bank():
	if not bank_scene:
		print("ERROR: bank_scene is null! Make sure bank.tscn exists in res://scenes/")
		return
	
	# Increment bank count and calculate new cost
	bank_count += 1
	current_bank_cost = BASE_BANK_COST + ((bank_count - 1) * BANK_COST_INCREMENT)
	
	var screen_width = get_viewport().get_visible_rect().size.x
	var spawn_x = screen_width + 100
	var attempts = 0
	
	# Try to find a safe position for the bank
	while attempts < MAX_SPAWN_ATTEMPTS:
		# Add some randomness to spawn position
		var random_offset = randf_range(0, 200)
		var test_spawn_x = spawn_x + random_offset
		
		if can_spawn_bank_at(test_spawn_x):
			spawn_x = test_spawn_x
			break
		
		attempts += 1
		spawn_x += 100  # Try further right
	
	if attempts >= MAX_SPAWN_ATTEMPTS:
		print("Could not find safe position for bank, spawning anyway")
		spawn_x = screen_width + 300  # Spawn further out
	
	var bank_instance = bank_scene.instantiate()
	
	if not bank_instance:
		print("ERROR: Failed to instantiate bank scene!")
		return
	
	# Bank is always on the ground, make it more visible
	bank_instance.position = Vector2(spawn_x, ground_y - 165)
	
	# Make sure the bank is visible
	if bank_instance.has_node("Sprite2D"):
		var sprite = bank_instance.get_node("Sprite2D")
		sprite.modulate = Color.WHITE
		print("Bank sprite found and made visible")
	else:
		print("WARNING: No Sprite2D found in bank scene")
		for child in bank_instance.get_children():
			if child is Sprite2D:
				child.modulate = Color.WHITE
				print("Found sprite in bank children: ", child.name)
				break
	
	# Connect the signal for bank interaction
	if bank_instance.has_signal("body_entered"):
		bank_instance.body_entered.connect(hit_bank)
		print("Bank signal connected successfully")
	else:
		print("WARNING: Bank doesn't have body_entered signal")
	
	add_child(bank_instance)
	spawned_banks.append(bank_instance)
	
	# Temporarily pause obstacle spawning to create a clear area around the bank
	create_obstacle_free_zone_around_bank(bank_instance.position.x)
	
	print("Bank #", bank_count, " spawned! Cost: ", current_bank_cost, " coins at position: ", bank_instance.position)
	print("Player needs ", current_bank_cost, " coins to pass safely. Current coins: ", coins)

# New function to create obstacle-free zone around bank
func create_obstacle_free_zone_around_bank(bank_x: float):
	# Pause obstacle spawning temporarily
	var pause_duration = 3.0  # Seconds to pause obstacle spawning
	obstacle_timer = pause_duration
	
	print("Creating obstacle-free zone around bank at x: ", bank_x)
	
	# Optional: Remove any obstacles that are too close to the bank
	for obstacle in spawned_obstacles.duplicate():
		if is_instance_valid(obstacle):
			var distance = abs(bank_x - obstacle.position.x)
			if distance < MIN_BANK_OBSTACLE_DISTANCE:
				print("Removing obstacle too close to bank")
				obstacle.queue_free()
				spawned_obstacles.erase(obstacle)

# Also modify your obstacle spawning to respect bank positions





# Bus movement functions
func accelerate_bus_offscreen():
	if not bus_sprite or bus_disappeared:
		return
		
	bus_moving = true
	print("Bus accelerating and leaving forever!")
	
	var tween = create_tween()
	var screen_width = get_viewport().get_visible_rect().size.x
	var target_position = Vector2(screen_width + 300, bus_initial_position.y)
	
	tween.tween_property(bus_sprite, "position", target_position, 0.8)
	tween.tween_callback(func(): bus_disappeared_permanently())

func bus_disappeared_permanently():
	bus_disappeared = true
	bus_moving = false
	if bus_sprite:
		bus_sprite.hide()
		bus_sprite.queue_free()
		bus_sprite = null
	print("Bus has left forever and been removed from scene!")

func reset_bus_for_new_game():
	if bus_disappeared and bus_sprite == null:
		recreate_bus()
	elif bus_sprite and not bus_disappeared:
		bus_moving = false
		bus_sprite.position = bus_initial_position
		bus_sprite.show()
		print("Bus reset for new game")

func recreate_bus():
	if not bus_sprite:
		var bus_texture = preload("res://assets/bus.webp")
		
		bus_sprite = Sprite2D.new()
		bus_sprite.texture = bus_texture
		bus_sprite.position = bus_initial_position
		
		get_parent().add_child(bus_sprite)
		
		bus_moving = false
		bus_disappeared = false
		
		print("Bus recreated for new game")

# Legacy functions
func move_bus_offscreen():
	pass

func reset_bus_position():
	pass

# Modify your game_over_insufficient_coins function to show current bank cost
func game_over_insufficient_coins():
	if not game_running:
		return
	
	game_running = false
	
	check_and_update_highscore()
	
	if crash_player and crash_player.stream:
		crash_player.play()
		print("Playing crash sound - insufficient coins for bank!")
	else:
		print("Crash player or stream not available")
	
	print("Game Over! Not enough coins for bank #", bank_count, " (cost: ", current_bank_cost, " coins)!")
	# Show GORIB label for insufficient coins game over
	if has_node("../HUD"):
		var hud = $"../HUD"
		if hud.has_node("GORIB"):
			hud.get_node("GORIB").show()
			print("GORIB label shown - unable to pay semester fee!")
		else:
			print("GORIB label not found in HUD")
	else:
		print("HUD node not found!")
	await get_tree().create_timer(0.1).timeout
	
	get_tree().paused = true
	
	show_game_over_ui()

func game_over():
	if not game_running:
		return
	
	game_running = false
	
	check_and_update_highscore()
	
	if crash_player and crash_player.stream:
		crash_player.play()
		print("Playing crash sound")
	else:
		print("Crash player or stream not available")
	
	print("Game Over!")
	
	await get_tree().create_timer(0.1).timeout
	
	get_tree().paused = true
	
	show_game_over_ui()
