# Makefile - kas-based helpers
# Targets:
#   make conf PROFILE=<generic|turtlebot3> MACHINE=<machine>  # generate conf/local.conf (no build)
#   make build PROFILE=<...> MACHINE=<...>                    # run kas build
#   make preview PROFILE=... MACHINE=...                      # preview generated conf (dry-run)
#   make clean                                               # remove generated conf/local.conf

SHELL := /bin/bash
PROFILE ?= generic
MACHINE ?= raspberrypi4-64

.PHONY: conf build preview clean

conf:
	./build.sh --profile $(PROFILE) --machine $(MACHINE) --no-build

build:
	./build.sh --profile $(PROFILE) --machine $(MACHINE)

preview:
	./build.sh --profile $(PROFILE) --machine $(MACHINE) --dry-run

clean:
	rm -f conf/local.conf
