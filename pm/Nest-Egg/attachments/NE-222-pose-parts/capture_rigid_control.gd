extends "res://pm/Nest-Egg/attachments/NE-222-pose-parts/capture.gd"
## Same-source control with production limb bending disabled only in its private synthetic skin fixture.


func _same_source_fixture(source_skin: Dictionary) -> Dictionary:
	var fixture := super._same_source_fixture(source_skin)
	fixture["limb_bend"] = false
	fixture["pose_attachment_fixture_id"] = "Ne222PoseAttachmentNative.synthetic.same-source.rigid-control.v1"
	fixture["capture_geometry_mode"] = "rigid control: fixture limb_bend=false; production CharacterRig API"
	return fixture
