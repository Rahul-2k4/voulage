#!/bin/bash

# regolith-inputd's Makefile defaults to GNOME. This COSMIC target selects
# its independent backend without changing the source default or other targets.
export CARGO_FEATURES=cosmic
