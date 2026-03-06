# =============================================================================
# PX4-ROS2-Docker — general-purpose Docker workspace for PX4 ROS 2 controllers
# =============================================================================
#
# OVERVIEW
# ────────
# This Makefile manages a Docker container that provides the full software
# environment needed to build and run any of the PX4 ROS 2 controllers in
# this stack.  Your ROS 2 workspace lives on the host and is mounted into
# the container — so you edit files with your normal host tools, and use
# the container only for building and running nodes.
#
# WORKSPACE LAYOUT (host)
# ───────────────────────
# The container expects your workspace to follow standard colcon conventions:
#
#   <workspace>/
#   └── src/
#       ├── <controller_package>/      e.g. newton_raphson_px4
#       ├── quad_platforms/
#       ├── quad_trajectories/
#       └── ROS2Logger/                (required by newton_raphson, nmpc)
#
# Clone all packages via:
#   vcs import src < px4_ros2_controllers.repos
#
# CONTAINER MOUNT
# ───────────────
# `make run` mounts WORKSPACE → /workspace inside the container.
# colcon build artifacts (build/ install/ log/) are created there and
# persist on the host across container restarts.
#
# SOURCE CHAIN (inside container)
# ────────────────────────────────
#   /opt/ros/jazzy/setup.bash
#   → /opt/ws_px4_msgs/install/setup.bash   (px4_msgs overlay, pre-built)
#   → /opt/px4-venv/bin/activate            (Python venv)
#   → /workspace/install/setup.bash         (your built packages, if present)
#
# TYPICAL WORKFLOW
# ────────────────
#   make build                              # build image once
#   make run    WORKSPACE=~/my_ws          # start container
#   make build_ros                         # build all packages
#   make attach                            # shell into container
# =============================================================================

IMAGE_NAME     = px4_ros2_jazzy
CONTAINER_NAME = px4_ros2

# Override on the command line: make run WORKSPACE=~/my_ws
WORKSPACE ?= $(HOME)/ws_px4_work

# ── Docker image ──────────────────────────────────────────────────────────────
build:
	docker build -f docker/Dockerfile . -t $(IMAGE_NAME)

# ── Run container ─────────────────────────────────────────────────────────────
run:
	docker rm -f $(CONTAINER_NAME) 2>/dev/null || true
	docker run -itd --rm \
		--net host \
		-e ROS_DOMAIN_ID=31 \
		-v $(abspath $(WORKSPACE)):/workspace \
		--name $(CONTAINER_NAME) \
		$(IMAGE_NAME)

# ── Container lifecycle ───────────────────────────────────────────────────────
stop:
	docker stop $(CONTAINER_NAME)

kill:
	docker kill $(CONTAINER_NAME)

attach:
	docker exec -it $(CONTAINER_NAME) bash

# ── Build ROS 2 workspace ─────────────────────────────────────────────────────
# Optional: PACKAGES="pkg1 pkg2" to build only specific packages.
PACKAGES ?=

build_ros:
	docker exec -it $(CONTAINER_NAME) bash -lc \
		"cd /workspace && colcon build \
		   --symlink-install \
		   --cmake-args -DCMAKE_BUILD_TYPE=Release -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
		   $(if $(PACKAGES),--packages-select $(PACKAGES),)"

# Wipe build/install/log then rebuild from scratch.
clean_build_ros:
	docker exec -it $(CONTAINER_NAME) bash -lc \
		"rm -rf /workspace/build /workspace/install /workspace/log"
	$(MAKE) build_ros PACKAGES="$(PACKAGES)"

# ── Run a ROS 2 node inside the container ─────────────────────────────────────
# Usage: make ros2_run PKG=newton_raphson_px4 EXEC=run_node ARGS="--platform sim --trajectory hover"
PKG  ?=
EXEC ?=
ARGS ?=

ros2_run:
	docker exec -it $(CONTAINER_NAME) bash -lc \
		"ros2 run $(PKG) $(EXEC) $(ARGS)"

.PHONY: build run stop kill attach build_ros clean_build_ros ros2_run
