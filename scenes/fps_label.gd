extends Label


func _physics_process(delta: float) -> void:
	self.text = "FPS: " + str(Engine.get_frames_per_second())
