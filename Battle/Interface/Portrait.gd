extends Control

var colors_shader = preload("res://Assets/colors.shader")

var character:Character


func setup(character):
    # Before _ready
    self.character = character
    $Name.text = String(character.name)
    $Head/head.texture = character.textures["head"]
    $Head/hair.texture = character.textures["hair"]
    
    var new_material = ShaderMaterial.new()
    new_material.shader = colors_shader
    
    var colors = character.colors
    var darken_amount = 0.4
    new_material.set_shader_param("hair_normal", colors.hair)
    new_material.set_shader_param("hair_shadow", colors.hair.darkened(darken_amount))
    
    new_material.set_shader_param("skin_normal", colors.skin)
    new_material.set_shader_param("skin_shadow", colors.skin.darkened(darken_amount))
    
    $Head.material = new_material
    
    SignalManager.connect("health_changed", self, "_on_health_changed")


func set_outline(value):
    return
    if value:
        # ShaderMaterial is shared by all instances,
        # so it is necessary to create a new one each time.
        var material = ShaderMaterial.new()
        #material.shader = outline_shader
        #image.material = material
    else:
        pass
        #image.material.shader = null


func _on_Portrait_gui_input(event):
    if event is InputEventMouseButton and event.is_pressed():
        get_tree().set_input_as_handled()
        SignalManager.emit_signal("character_selected", character)


func _on_health_changed(target):
    if character == target and not target.is_alive:
        # I die... die.... DIE!!
        queue_free()
        
