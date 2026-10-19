"""Pose aliases can override draw order without mutating their source pose; invalid edits are atomic."""
from cut_layers import pose_slot_depths


def main():
    original = [{"slot": "near", "texture": "cloth", "bone": "thigh"}, {"slot": "far", "texture": "cloth", "bone": "thigh_far"}]
    seated = pose_slot_depths(original, {"near": -1.0}, -7, 10, "sit")
    crouched = pose_slot_depths(seated, {"near": 2}, -7, 10, "crouch")
    assert "z" not in original[0] and seated[0]["z"] == -1 and crouched[0]["z"] == 2
    assert pose_slot_depths(seated, {}, -7, 10, "same_as")[0]["z"] == -1
    for invalid in [{"missing": 0}, {"near": 0.2}, {"near": float("nan")}, {"near": True}, {"near": -8}, {"near": 11}, []]:
        try:
            pose_slot_depths(seated, invalid, -7, 10, "invalid")
        except ValueError:
            pass
        else:
            raise AssertionError(f"accepted invalid draw order {invalid}")
        assert seated[0]["z"] == -1 and "z" not in original[0]
    print("pose draw order: aliases isolated, inherited defaults retained, invalid edits rejected without mutation")


if __name__ == "__main__":
    main()
