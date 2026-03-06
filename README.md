# PX4-ROS2-Docker

A general-purpose Docker + Makefile workspace for building and running PX4 ROS 2 offboard controllers.

---

## How the full stack fits together

```
┌─────────────────────────────────────────────────────────────┐
│  HOST MACHINE                                               │
│                                                             │
│  ┌──────────────────┐      ┌─────────────────────────────┐ │
│  │  PX4 Autopilot   │      │  MicroXRCE-DDS Agent        │ │
│  │  (sim or hw)     │◄────►│  UDP bridge                 │ │
│  │                  │      │  (translates uORB ↔ DDS)    │ │
│  └──────────────────┘      └────────────┬────────────────┘ │
│                                         │ ROS 2 topics      │
│                             ┌───────────▼────────────────┐  │
│                             │  Docker container          │  │
│                             │  (--net host)              │  │
│                             │                            │  │
│                             │  ROS 2 Jazzy               │  │
│                             │  px4_msgs overlay          │  │
│                             │  Python venv (JAX, etc.)   │  │
│                             │                            │  │
│                             │  /workspace  ←── mount ───────┤
│                             │    src/                    │  │
│                             │    build/                  │  │
│                             │    install/                │  │
│                             └────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

**PX4 Autopilot** runs the low-level flight controller (attitude, mixer, ESC output).
It communicates over uORB topics internally.

**MicroXRCE-DDS Agent** bridges uORB ↔ DDS/ROS 2, making PX4 topics visible as
standard ROS 2 topics (e.g. `/fmu/out/vehicle_odometry`, `/fmu/in/trajectory_setpoint`).

**The container** runs your ROS 2 controller node.  It subscribes to vehicle state
topics and publishes control setpoints back to PX4 via the bridge.  `--net host`
means the container shares the host network — no extra port mapping needed.

**Your workspace** is mounted into the container at `/workspace`.  All source code
lives on the host so you can edit normally; the container is only used for building
and running.

---

## Prerequisites (host machine)

### 1. Docker Engine

```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER   # log out and back in
```

### 2. PX4-Autopilot

```bash
git clone https://github.com/PX4/PX4-Autopilot.git --recursive ~/PX4-Autopilot
cd ~/PX4-Autopilot
bash Tools/setup/ubuntu.sh
make px4_sitl gz_x500     # verify sim runs
```

### 3. MicroXRCE-DDS Agent

```bash
git clone https://github.com/eProsima/Micro-XRCE-DDS-Agent.git
cd Micro-XRCE-DDS-Agent && mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j$(nproc) && sudo make install && sudo ldconfig
```

### 4. vcstool (to clone controller repos)

```bash
pip install vcstool
```

---

## Setup

### Step 1 — Clone this repo

```bash
git clone https://github.com/evannsm/PX4-ROS2-Docker.git
cd PX4-ROS2-Docker
```

### Step 2 — Create your workspace and clone controller packages

```bash
mkdir -p ~/ws_px4/src
vcs import ~/ws_px4/src < px4_ros2_controllers.repos
```

This clones into `~/ws_px4/src/`:
- `quad_platforms` — platform configs (motor curves, mass, etc.) for sim and hardware
- `quad_trajectories` — trajectory definitions (hover, circle, helix, figure-8, ...)
- `ROS2Logger` — CSV logging utility (used by nmpc)
- `geometric_px4` — Geometric controller
- `nmpc_acados_px4` — Nonlinear MPC controller (requires acados, see note below)

To use only specific controllers, clone just what you need — `quad_platforms` and
`quad_trajectories` are required by all of them.

### Step 3 — Build the Docker image (once)

```bash
make build
```

The image (`px4_ros2_jazzy`) contains:

| Component | Details |
|---|---|
| ROS 2 Jazzy | `osrf/ros:jazzy-desktop-full` base |
| px4_msgs | pre-built at `/opt/ws_px4_msgs` (branch `v1.16_minimal_msgs`) |
| Python venv | `/opt/px4-venv` — JAX, equinox, jaxtyping, scipy, matplotlib, pyJoules, casadi, immrax, linrax |

### Step 4 — Start the container

```bash
make run WORKSPACE=~/ws_px4
```

This mounts `~/ws_px4` → `/workspace` and starts the container in the background.

> `WORKSPACE` defaults to `~/ws_px4_work` if not specified.  Set it to wherever
> you created your workspace in Step 2.

### Step 5 — Build the ROS 2 workspace (first time, or after adding packages)

```bash
make build_ros
```

To build only specific packages:

```bash
make build_ros PACKAGES="newton_raphson_px4 quad_platforms quad_trajectories"
```

---

## Running a controller

### Terminal layout

You need three terminals on the host:

**Terminal 1 — PX4 sim:**
```bash
cd ~/PX4-Autopilot && make px4_sitl gz_x500
```

**Terminal 2 — DDS bridge:**
```bash
MicroXRCEAgent udp4 -p 8888
```

**Terminal 3 — controller:**
```bash
make ros2_run PKG=newton_raphson_px4 EXEC=run_node ARGS="--platform sim --trajectory hover --hover-mode 1"
```

Or attach a shell and run manually:
```bash
make attach
ros2 run newton_raphson_px4 run_node --platform sim --trajectory circle_horz
```

### Available controllers and their entry points

| Controller | Package | Entry point | Key args |
|---|---|---|---|
| Geometric | `geometric_px4` | `run_node` | `--platform`, `--trajectory` |
| NMPC (acados) | `nmpc_acados_px4` | `run_node` | `--platform`, `--trajectory` |

Common trajectory options: `hover`, `circle_horz`, `fig8_vert`, `helix`, `yaw_only`

Common platform options: `sim`, `hw`

---

## Makefile reference

| Command | Description |
|---|---|
| `make build` | Build the Docker image |
| `make run [WORKSPACE=path]` | Start the container, mounting the given workspace |
| `make attach` | Open a shell inside the running container |
| `make build_ros [PACKAGES="..."]` | Run `colcon build` inside the container |
| `make clean_build_ros` | Wipe `build/install/log` and rebuild from scratch |
| `make ros2_run PKG=... EXEC=... ARGS="..."` | Run a ROS 2 node inside the container |
| `make stop` | Stop the container |
| `make kill` | Force-kill the container |

---

## Notes on specific controllers

### NMPC (nmpc_acados_px4)

The NMPC controller uses [acados](https://docs.acados.org/) for the OCP solver.
`acados_template` (the Python interface) is installed in the venv, but the
generated C solver must be compiled inside the container after build:

```bash
make attach
cd /workspace/src/nmpc_acados_px4
python3 nmpc_acados_px4_utils/controller/nmpc/generate_nmpc.py
```

This produces a compiled shared library that `run_node` loads at runtime.

### Hardware vs simulation

The `--platform hw` flag switches to hardware-tuned parameters defined in
`quad_platforms`.  For hardware flights you also need to set the correct
`ROS_DOMAIN_ID` (default: 31) to match your onboard computer's DDS config.

---

## Docker image vs the contraction controller image

This image (`px4_ros2_jazzy`) is a general workspace image for all controllers.
The [contraction_controller_px4](https://github.com/evannsm/contraction_controller_px4)
repo ships its own self-contained image — use that if you only need the
contraction controller and want a single-repo clone-and-run experience.
