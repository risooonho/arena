extends Node

var Colors = load("res://Character/Colors.gd")
var Character = load("res://Character/Character.gd")
var Turn = load("res://Battle/Turn.gd")
var Action = load("res://Battle/Action.gd")
var Challenge = load("res://Battle/Challenge/Challenge.gd")

# SkillCheck Types
var SkillChecks = {
    "Bar": load("res://Battle/SkillCheck/Bar.tscn"),
    "Swing": load("res://Battle/SkillCheck/Swing.tscn")
}

var heroes:Array
var enemies:Array

var current_turn
var current_turn_count:int = 1
var end_turn_confirmation:bool = false

var hero_units:Array
var enemy_units:Array

var active_unit:Unit
var active_character:Character setget , _get_active_character
var hovered_unit:Unit

var active_targets:Array = []
var action_state:String = Action.WAIT
var action_debounce:bool = false

var challenges:Dictionary = {}

onready var Grid = $Grid
onready var ActionTimer = $ActionTimer
onready var AttackTimer = $AttackTimer
onready var EndTurnDialog = $Interface/EndTurnDialog
onready var Comparison = $Interface/Comparison
onready var AITimer = $AITimer


func setup(data):
    heroes = data.heroes
    enemies = data.enemies
    
    hero_units = Grid.add_characters(heroes)
    enemy_units = Grid.add_characters(enemies, true)
    
    current_turn = Turn.new(hero_units, current_turn_count, false)
    
    $Interface.setup()
    SignalManager.emit_signal("unit_focused", hero_units[0])


func _ready():
    SignalManager.connect("unit_focused", self, "_on_unit_focused")
    SignalManager.connect("unit_targeted", self, "_on_unit_targeted")
    SignalManager.connect("unit_hovered", self, "_on_unit_hovered")
    SignalManager.connect("unit_movement_done", self, "_on_movement_done")
    SignalManager.connect("ranked_up", self, "_on_ranked_up")


func _input(event):
    if action_state != Action.FREEZE:
        if Input.is_action_pressed("cheat"):
            self.current_turn = Turn.new(hero_units, current_turn_count, false)
        if Input.is_action_pressed("actions_attack"):
            set_action_state(Action.ATTACK)
        elif Input.is_action_pressed("actions_move"):
            set_action_state(Action.MOVE)
        elif Input.is_action_pressed("actions_analyze"):
            set_action_state(Action.ANALYZE)
        elif Input.is_action_pressed("actions_cancel"):
            set_action_state(Action.WAIT)
            Grid.deactivate()
        elif Input.is_action_pressed("actions_turn"):
            next_turn()
        elif Input.is_action_just_released("next") or Input.is_action_just_released("previous"):
            action_debounce = false
        else:
            var is_next = Input.is_action_pressed("next")
            var is_prev = Input.is_action_pressed("previous")
            if is_next or is_prev:
                if action_debounce: return
                debounce_actions()
                Grid.deactivate()
            
                var living_units = get_living_units(hero_units)
                var index = living_units.find(active_unit)
                var max_index = living_units.size() - 1
                
                if !is_prev:
                    if index < max_index:
                        index += 1
                    else:
                        index = 0
                else:
                    if index > 0:
                        index -= 1
                    else:
                        index = max_index
                
                set_action_state(Action.WAIT)
                SignalManager.emit_signal("unit_focused", living_units[index])


func _notification(event):
    if event == MainLoop.NOTIFICATION_WM_FOCUS_OUT and \
        action_state != Action.FREEZE:
            set_action_state(Action.WAIT)


# TURN ACTIVATION
# -----------------------------

# Activate enemies and let the next possible one take an action,
# until none can and the next turns (player) begins
func activate_enemies():
    var active_enemy = current_turn.next_character()
    if active_enemy == null:
        set_action_state(Action.WAIT)
        return next_turn()
        
    set_action_state(Action.FREEZE)
    
    active_unit = Grid.activate_character(active_enemy)
    
    # Get the next action and update the turn.
    var next_action = current_turn.next_possible_action(active_enemy.id)
    current_turn.take_action(active_enemy, next_action)
    
    # Let the AI decide to do with the current action...
    if next_action == Action.MOVE:
        # This starts movement which won't activated
        # enemies again until it finishes.
        if Grid.move_to_nearest_unit(active_unit):
            return
        
    elif next_action == Action.ATTACK:
            var nearest_unit = Grid.get_nearest_unit(active_unit)
            if is_instance_valid(nearest_unit) and is_instance_valid(active_unit) \
                and attack_within_range(active_unit, nearest_unit):
                    active_targets = [nearest_unit]
                    active_unit.turn_rig(nearest_unit.position)
                    resolve_attack(1, "")
      
    AITimer.start()


# When a character is selected, activate it on the grid
# and apply any other changes necessary.
func activate_character(character:Character):
    if character.is_alive:
        active_unit = Grid.activate_character(character)
        set_action_state(Action.WAIT)
    
    # Allow auto-selection of next action... maybe a setting later.
    # var next_action = current_turn.next_possible_action(character.id)
    # set_action_state(next_action)
    

# End the current turn, and activate the next group.
func next_turn():    
    if current_turn.is_enemy:
        current_turn_count += 1
        var units = get_living_units(hero_units)
        current_turn = Turn.new(units, current_turn_count, false)
        end_turn_confirmation = false
        
        # If any characters are alive, activate now.
        if units.size() > 0:
            activate_character(units[0].character)
    else:
        # If there are still remaining actions, ask the player
        # to confirm the end of the turn before continuing.
        if !current_turn.is_complete() and !end_turn_confirmation:
            EndTurnDialog.popup_centered(Vector2.ZERO)
            return
        
        var units = get_living_units(enemy_units)
        current_turn = Turn.new(units, current_turn_count, true)
        activate_enemies()


func get_living_units(units):
    var living = []
    for unit in units:
        if is_instance_valid(unit) and unit.character.is_alive:
            living.append(unit)
    
    return living


# CHARACTER ACTIONS
# -----------------------------

# Expose a challenge for the character to gain an advantage.
func character_analyze(target):
    var did_analyze = character_action(Action.ANALYZE)
    if did_analyze:
        var challenge = Challenge.new()
        challenge.setup(target, active_unit)
        challenges[target.character.id] = challenge
        Grid.show_challenge_overlay(challenge)
    
    set_action_state(Action.WAIT)


# Check if the character can move, then return if
# the action has been logged in the turn.
func character_move(distance) -> bool:
    var did_move = character_action(Action.MOVE)
    if did_move:
        set_action_state(Action.FREEZE)
        self.active_character.progress_action(Action.MOVE, distance)

    return did_move


# Telgegraph has completed and the targets are chosen,
# so continue with the skillcheck.
func character_attack(targets:Array):
    if targets.has(active_unit):
        return
    
    if targets.size() == 0:
        AttackTimer.start(0.3)
        return
 
    var did_attack = character_action(Action.ATTACK)
    if did_attack:    
        active_targets = targets
        
        # Get average target speed.
        var target_speed = 0
        for target in targets:
            target_speed += target.character.speed
            attempt_taunt(target)
            target.lock_targeted()
            
        target_speed /= targets.size()
        
        # Face toward the target(s)
        var first_target = targets[0]
        active_unit.turn_rig(first_target.position)
        
        # Initiate a skill check which will call
        # resolve_attack when the player compeletes it.
        var skill_check = SkillChecks.Swing.instance()
        $Interface.add_child(skill_check)
        skill_check.setup(self, active_unit, target_speed)
        set_action_state(Action.FREEZE)
        Grid.deactivate()
        Grid.camera.start_cinematic_target(first_target.position + Vector2(0, -150), true)


func character_action(type):
    if action_state == Action.FREEZE:
        return false
    
    return current_turn.take_action(self.active_character, type)


# Change the action state of the battle and handle some
# transitional logic between states.
func set_action_state(next_state):    
    # Verify that the next state is valid for the current battle state.
    if action_state == next_state or\
        not is_instance_valid(active_unit) or\
        not current_turn.can_take_action(self.active_character.id, next_state):
        return

    # The only action state that can follow FREEZE is WAIT.
    # This makes sure that different states are locked during FREEZE.
    if action_state == Action.FREEZE and next_state != Action.WAIT:
        return

    if action_state == Action.MOVE and next_state != Action.MOVE:
        Grid.deactivate()
    
    match(next_state):
        Action.MOVE:
            if self.active_character.is_enemy: return
            Grid.show_movement_overlay()
        Action.ATTACK:
            if self.active_character.is_enemy: return
            Grid.show_attack_overlay()
        Action.WAIT:
            pass
        Action.FREEZE:
            pass
            
    action_state = next_state
    SignalManager.emit_signal("battle_state_updated", action_state)


func debounce_actions():
    ActionTimer.start(0.5)
    action_debounce = true


# ATTACK RESOLUTION
# -----------------------------

# Skill check completed, calculate damage(s)
func resolve_attack(multiplier = 1, label = ""):
    if not active_targets or not active_unit or active_targets[0] == active_unit:
        return
    
    var color = Color.white
    
    # Reduce damage by how many targets are being hit (spread)
    var aoe_multiplier:float = float(active_targets.size()) / 2
    
    # Calculate final damage after target's mitigation.
    for target in active_targets:
        var challenge_bonus = get_challenge_multiplier(target)
        if challenge_bonus > 1:
            color = Colors.CHALLENGE
        
        # Calculate final damage.
        var target_character = target.character
        var damage = ((self.active_character.deal_damage() * multiplier) * challenge_bonus) / aoe_multiplier
        var final_damage = int(target_character.take_damage(damage))
        
        # Progress stats based on the attack for both characters
        self.active_character.progress_stat(Action.ATTACK, damage)
        target_character.progress_action(Action.ATTACK, final_damage)
        
        target.unlock_targeted()
        target.show_damage(final_damage, label, color)
        
        if !target_character.is_alive:
            _handle_character_death(target)
            
        SignalManager.emit_signal("health_changed", target_character)
        
        if !current_turn.is_enemy:
            AttackTimer.start(0.3)
        
    active_targets = []
    active_unit.set_animation("Idle")
    Grid.camera.end_cinematic_target()


# The first time a character is attacked in a turn,
# they will turn to face their attacker.
func attempt_taunt(target):
    var did_taunt = current_turn.can_be_taunted(target.character.id)
    if did_taunt:
        target.turn_rig(active_unit.position)


# When a character dies, remove them fom the turns list
# and check for a victory/defeat condition of one team
# being entirely deceased.
func _handle_character_death(target:Unit):
    var full_list = enemy_units
    if !target.character.is_enemy:
        full_list = hero_units
        current_turn.units_total.erase(target)
    
    var all_dead = true
    for unit in full_list:
        if is_instance_valid(unit) and unit is Unit and unit.character.is_alive:
            all_dead = false
            break
    
    if all_dead:
        # END THE BATTLE, one side is 100% dead
        ScreenManager.change_to(Scenes.BATTLE_EXIT, {
            "heroes": heroes,
            "enemies": enemies,
            "winner": "player" if target.is_enemy else "enemy"
        })


# Player has targeted an enemy in attack/analyze phase.
func _on_unit_targeted(unit):
    match(action_state):
        Action.ANALYZE: character_analyze(unit)
        Action.ATTACK:
            if attack_within_range(active_unit, unit):
                character_attack([unit])


func attack_within_range(attacker, victim):
    var attack_range = attacker.character.attack_range
    var distance = Grid.get_coord_distance(attacker.position, victim.position)
    return abs(distance.x) <= attack_range and abs(distance.y) <= attack_range


func get_challenge_multiplier(target) -> float:
    var challenge_multiplier = 1
    
    # Get challenge bonus if one is present.
    if challenges.keys().has(target.character.id):
        var challenge = challenges[target.character.id]
        challenge_multiplier = challenge.check(target, active_unit)
        
        if challenge_multiplier > 1:
            challenges.erase(target.character.id)
    
    return challenge_multiplier


# GETTERS
# -----------------------------

func _get_active_character():
    if is_instance_valid(active_unit) and active_unit.character != null:
        return active_unit.character


# SIGNAL LISTENERS
# -----------------------------

func _on_turn_ended():
    next_turn()


func _on_ai_action_taken():
    activate_enemies()


func _on_unit_focused(unit):
    if unit != null:
        activate_character(unit.character)


func _on_movement_done():
    if current_turn.is_enemy:
        activate_enemies()
    else:
        set_action_state(Action.WAIT)


func _on_ranked_up(character, stat):
    pass
    

func _on_ActionTimer_timeout():
    action_debounce = false


func _on_EndTurnDialog_confirmed():
    end_turn_confirmation = true
    next_turn()


func _on_AttackTimer_timeout():
    set_action_state(Action.WAIT)


func _on_AITimer_timeout():
    activate_enemies()
    
