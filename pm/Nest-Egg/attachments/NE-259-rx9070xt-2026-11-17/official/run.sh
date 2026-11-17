#!/usr/bin/env bash
python3() { 'C:/Users/stanl/AppData/Local/Programs/Python/Python313/python.exe' "$@"; }
export -f python3
exec tools/run_tests_changed.sh 38d8f3d3d404cb7baba0727804e86ffb1e882157
