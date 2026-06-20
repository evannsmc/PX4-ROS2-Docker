# PX4-ROS2 Docker Workspace

[![Part of: PX4-ROS2 Control Stack](https://img.shields.io/badge/Part_of-PX4--ROS2_Control_Stack-blue)](https://www.evannsmc.com/projects)
[![ROS 2 Compatible](https://img.shields.io/badge/ROS%202-Humble_%7C_Jazzy-blue)](https://docs.ros.org/)
[![PX4 Compatible](https://img.shields.io/badge/PX4-Autopilot-pink)](https://github.com/PX4/PX4-Autopilot)
[![Docker: px4_ros2_jazzy](https://img.shields.io/badge/Docker-px4__ros2__jazzy-2496ED?logo=docker&logoColor=white)](https://www.docker.com/)
![License: MIT](https://img.shields.io/badge/License-MIT-green)

The **integration hub** for the [evannsmc PX4-ROS2 control stack](https://www.evannsmc.com/projects): a Docker image + Makefile that build and run the stack's ROS 2 offboard controllers against PX4. The image (`px4_ros2_jazzy`) ships ROS 2 Jazzy, a prebuilt `px4_msgs` overlay, and all the Python dependencies (JAX, acados, …), so any controller in the stack builds and runs with no per-machine setup beyond Docker, PX4-Autopilot, and the DDS agent.

PX4 SITL/hardware and the MicroXRCE-DDS agent run on the **host**; your controller node runs in the **container** (with `--net host`), and your workspace is bind-mounted at `/workspace`.

<div align="center">

---

**[<kbd> <br> Architecture <br> </kbd>](#how-the-full-stack-fits-together)** 
**[<kbd> <br> Prerequisites <br> </kbd>](#prerequisites-host-machine)** 
**[<kbd> <br> Setup <br> </kbd>](#setup)** 
**[<kbd> <br> Running <br> </kbd>](#running-a-controller)** 
**[<kbd> <br> Makefile <br> </kbd>](#makefile-reference)** 
**[<kbd> <br> Notes <br> </kbd>](#notes-on-specific-controllers)** 

---

</div>

<details>
<summary><b>📖 Table of Contents</b></summary>

- [How the full stack fits together](#how-the-full-stack-fits-together)
- [Prerequisites (host machine)](#prerequisites-host-machine)
- [Setup](#setup)
- [Running a controller](#running-a-controller)
- [Makefile reference](#makefile-reference)
- [Notes on specific controllers](#notes-on-specific-controllers)
- [License](#license)

</details>

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

**PX4 Autopilot** runs the low-level flight controller (attitude, mixer, ESC output). It communicates over uORB topics internally.

**MicroXRCE-DDS Agent** bridges uORB ↔ DDS/ROS 2, making PX4 topics visible as standard ROS 2 topics (e.g. `/fmu/out/vehicle_odometry`, `/fmu/in/trajectory_setpoint`).

**The container** runs your ROS 2 controller node. It subscribes to vehicle state topics and publishes control setpoints back to PX4 via the bridge. `--net host` means the container shares the host network — no extra port mapping needed.

**Your workspace** is mounted into the container at `/workspace`. All source code lives on the host so you can edit normally; the container is only used for building and running.

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

## Setup

### Step 1 — Clone this repo

```bash
git clone https://github.com/evannsmc/PX4-ROS2-Docker.git
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
- `ROS2Logger` — CSV logging utility (used by newton_raphson, nmpc)
- `newton_raphson_px4` — Newton-Raphson Flow controller
- `geometric_px4` — Geometric controller
- `nmpc_acados_px4` — Nonlinear MPC controller (requires acados, see note below)

To use only specific controllers, clone just what you need — `quad_platforms` and `quad_trajectories` are required by all of them.

### Step 3 — Build the Docker image (once)

```bash
make build
```

The image (`px4_ros2_jazzy`) contains:

| Component | Details |
|---|---|
| ROS 2 Jazzy | `osrf/ros:jazzy-desktop-full` base |
| px4_msgs | pre-built at `/opt/ws_px4_msgs` (branch `v1.16_minimal_msgs`) |
| Python venv | `/opt/px4-venv` — JAX, equinox, jaxtyping, scipy, matplotlib, pyJoules, casadi, immrax, linrax, acados_template |

### Step 4 — Start the container

```bash
make run WORKSPACE=~/ws_px4
```

This mounts `~/ws_px4` → `/workspace` and starts the container in the background.

> `WORKSPACE` defaults to `~/ws_px4_work` if not specified. Set it to wherever you created your workspace in Step 2.

### Step 5 — Build the ROS 2 workspace (first time, or after adding packages)

```bash
make build_ros
```

To build only specific packages:

```bash
make build_ros PACKAGES="newton_raphson_px4 quad_platforms quad_trajectories"
```

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
| Newton-Raphson Flow | `newton_raphson_px4` | `run_node` | `--platform`, `--trajectory`, `--hover-mode` |
| Geometric | `geometric_px4` | `run_node` | `--platform`, `--trajectory` |
| NMPC (acados) | `nmpc_acados_px4` | `run_node` | `--platform`, `--trajectory` |

Common trajectory options: `hover`, `circle_horz`, `fig8_vert`, `helix`, `yaw_only`

Common platform options: `sim`, `hw`

## Makefile reference

| Command | Description |
|---|---|
| `make build` | Build the Docker image (`px4_ros2_jazzy`) |
| `make run [WORKSPACE=path]` | Start the container, mounting the given workspace |
| `make attach` | Open a shell inside the running container |
| `make build_ros [PACKAGES="..."]` | Run `colcon build` inside the container |
| `make clean_build_ros` | Wipe `build/install/log` and rebuild from scratch |
| `make ros2_run PKG=... EXEC=... ARGS="..."` | Run a ROS 2 node inside the container |
| `make stop` | Stop the container |
| `make kill` | Force-kill the container |

## Notes on specific controllers

### NMPC (nmpc_acados_px4) — acados solver

The NMPC controllers use [acados](https://docs.acados.org/) for the OCP solver, with `acados_template` (the Python interface) preinstalled in the image. **The generated C solver is produced automatically** — the Python node (`nmpc_acados_px4`) generates/refreshes it on startup, and the C++ package (`nmpc_acados_px4_cpp`) generates it at build time via a stamp-cached guard. No manual code-generation step is required.

### Hardware vs simulation

The `--platform hw` flag switches to hardware-tuned parameters defined in `quad_platforms`. For hardware flights you also need to set the correct `ROS_DOMAIN_ID` (default: 31) to match your onboard computer's DDS config.

### Single-repo alternative

This image (`px4_ros2_jazzy`) is a general workspace image for all controllers. The [contraction_controller_px4](https://github.com/evannsmc/contraction_controller_px4) repo ships its own self-contained image — use that if you only need the contraction controller and want a single-repo clone-and-run experience.

## License

MIT
