#!/usr/bin/env bash
set -eu
exec "${NE80_GODOT_BIN:?set NE80_GODOT_BIN to the verified official 4.7.2 binary}" --audio-driver Dummy "$@"
