#!/bin/bash
# g.sh - grep helper
grep -nE "$1" "$2" | head -${3:-60}
