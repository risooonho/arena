extends "res://Battle/SkillCheck/SkillCheck.gd"

const METER_PADDING = 15
const HIT_BASE_SIZE = 50
const CRIT_BASE_SIZE = 10

var _size:int = 200
var _speed:int = 3

var _hit_range:Array
var _crit_range:Array

const MAX_ANGLE = 60
const RADIUS = 100

const POWER_STEP = 0.01
const POWER_MAX = 1
const POWER_MIN = 0
var _power:float = 0.0

const VELOCITY_MIN = 0.1
const VELOCITY_MAX = 0.2
var _average_velocity:float = 0.0

const SCORE_STEP = 8.0
var _score:float = 0.0

var _has_entered_once:bool = false

var _color:Color = Color.white

var _is_mouse_down:bool = false
var _is_swinging:bool = false

var _points:PoolVector2Array = []

const MOUSE_MAX_WIDTH:float = 20.0
var _prev_mouse_position:Vector2
var _mouse_points:Array

onready var _power_progress:TextureProgress = $Power
onready var _target:Area2D = $MouseTargetArea
onready var _arc:Polygon2D = $Arc
onready var _swoosh:Polygon2D = $Swoosh


func start():
    .start()
    
    _score = 0.0
    _mouse_points = []
    
    _get_points()
    _set_collision_polygon()
    

func _process(delta):
    if _is_running:
        var prev_power = _power
        var prev_swinging = _is_swinging
        var current_velocity = _get_velocity(delta)
        
        # The mouse needs to be moving a minimum speed
        # to count as a swing to prevent the player from
        # holding it still within the area.
        _is_mouse_down = Input.is_mouse_button_pressed(1)
        _is_swinging = current_velocity > VELOCITY_MIN and _is_mouse_down

        # Collisions being removed and added need a frame to init.
        yield(get_tree(), "physics_frame")
        var is_within_target = _get_is_within_target()

        # End the skillcheck if the player stopped swinging, or if they've exited the target.
        if (prev_swinging and !_is_swinging and _has_entered_once) or \
            (_has_entered_once and !is_within_target):
            ._resolve()
        
        if _is_swinging:
            _average_velocity = (_average_velocity + current_velocity) / 2
        
        if _is_swinging and is_within_target:
            # Update the score and track that the target has
            # been entered at least once (to prevent tiny misclicks).
            _has_entered_once = true
            _score += SCORE_STEP * delta
            _color = Color.yellow
        else:
            # Adjust the current power based on if the mouse
            # is being held down (charged) or not.
            if _is_mouse_down:
                _power += POWER_STEP
                _color = Color.green
            else:
                _power -= POWER_STEP
                _color = Color.gray
            
            # Clamp the power and update the progress texture.
            _power = clamp(_power, POWER_MIN, POWER_MAX)
            _power_progress.value = _power
        
        _arc.color = _color
        
        if _is_swinging:
            # Add a point to draw the mouse's trail while down.
            var mouse_position = get_local_mouse_position()
            _add_mouse_points(mouse_position)

        if prev_power != _power:
            # Recalculate the target's area and recreate all collision boxes.
            _get_points()
            _set_collision_polygon()
            

func _get_is_within_target() -> bool:
    if _is_mouse_down:
        # Get all overlapping areas but only register the cursor.
        var overlapping_areas = _target.get_overlapping_areas()
        for area in overlapping_areas:
            if area.name == "Cursor":
                return true
    
    return false


func _get_points():
    var angle_half = (MAX_ANGLE - ((_power / 1.5) * MAX_ANGLE)) / 2
    
    var center = _arc.position
    var b = angle_half
    var c = angle_half * -1
    
    _points = _get_arc(center, b, c)
    _arc.polygon = _points


func _add_mouse_points(mouse_position:Vector2):
    var angle:float
    var num_points = _mouse_points.size()
    if num_points > 0:
        var prev_position:Vector2 = _mouse_points[num_points - 1].origin;
        var diff = mouse_position - prev_position
        
        if abs(diff.x) + abs(diff.y) < 10: return
        angle = diff.x
    else:
        angle = 0.0
        
    var size = _get_velocity_score(_average_velocity) * 3
    _mouse_points.append({
        "origin": mouse_position,
        "size": pow(size, 2),
        "angle": angle
    })
    
    var top_points = []
    var bottom_points = []
    for point in _mouse_points:
        var offset = Vector2(point.size, point.size)
        top_points.append(point.origin + offset)
        bottom_points.append(point.origin - offset)
    
    bottom_points.invert()
    _swoosh.polygon = top_points + bottom_points
    
    

func _set_collision_polygon():
    for collision in _target.get_children():
        collision.free()
    
    var new_collision = CollisionPolygon2D.new()
    new_collision.polygon = _points
    _target.add_child(new_collision)
    
    
func _get_cone_point(angle, distance) -> Vector2 :
    return Vector2(cos(angle), sin(angle)) * distance


func _get_arc(center, angle_from, angle_to) -> PoolVector2Array:
    var num_points = 8
    var points_arc = PoolVector2Array([center])
    
    for i in range(num_points + 1):
        var angle_point = deg2rad(angle_from + i * (angle_to - angle_from) / num_points - 90)
        var angle_vector = _get_rad_vector(angle_point)       
        points_arc.push_back(center + angle_vector * RADIUS)
        
    return points_arc


func _get_deg_vector(angle) -> Vector2:
    var rad = deg2rad(angle)
    return Vector2(cos(rad), sin(rad))   


func _get_rad_vector(rad) -> Vector2:
    return Vector2(cos(rad), sin(rad))  


func _prepare_textures():
    ._prepare_textures()


func _get_multiplier():   
    var velocity_score = _get_velocity_score(_average_velocity)
    var rating = (_power / 2) + (_score * velocity_score)
    
    print("%s + (%s * %s) = %s" % [_power, _score, velocity_score, rating])
    
    if rating > 0.6: return CRIT_MULTIPLIER
    elif rating > 0.3: return HIT_MULTIPLIER
    elif rating > 0.1: return rating
    else: return MISS_MULTIPLIER


func _get_velocity_score(velocity) -> float:
    return clamp(velocity, VELOCITY_MIN, VELOCITY_MAX) / VELOCITY_MAX


func _get_velocity(delta):
    var mouse_position = get_local_mouse_position()
    var velocity = mouse_position - _prev_mouse_position
    _prev_mouse_position = mouse_position
    return (abs(velocity.x) + abs(velocity.y)) * delta
