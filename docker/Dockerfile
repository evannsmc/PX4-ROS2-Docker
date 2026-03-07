FROM osrf/ros:jazzy-desktop-full

SHELL ["/bin/bash", "-c"]

ENV DEBIAN_FRONTEND=noninteractive
# ── System deps ───────────────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3-pip \
    python3-dev \
    git \
    libgmp-dev \
    libcdd-dev \
    && apt-get remove -y python3-matplotlib \
    && rm -rf /var/lib/apt/lists/*

# ── ws_px4_msgs: pre-built inside the image, sourced as upstream overlay ──────
# px4_msgs provides all PX4 ↔ ROS 2 message types (VehicleOdometry,
# TrajectorySetpoint, OffboardControlMode, etc.).  It is pinned to the branch
# that matches the PX4 firmware version used in this stack.
RUN mkdir -p /opt/ws_px4_msgs/src && \
    git clone --depth 1 --branch v1.16_minimal_msgs \
        https://github.com/evannsm/px4_msgs.git /opt/ws_px4_msgs/src/px4_msgs && \
    source /opt/ros/jazzy/setup.bash && \
    cd /opt/ws_px4_msgs && \
    colcon build \
        --cmake-args -DCMAKE_BUILD_TYPE=Release && \
    rm -rf /opt/ws_px4_msgs/build /opt/ws_px4_msgs/log /opt/ws_px4_msgs/src

# ── Python deps — installed to system Python ──────────────────────────────────
COPY docker/requirements.txt /tmp/requirements.txt

RUN pip3 install --no-cache-dir --break-system-packages --ignore-installed -r /tmp/requirements.txt

# ── immrax (jax-0.9-support branch) ──────────────────────────────────────────
# Interval arithmetic library used by the contraction controller.
RUN git clone --depth 1 --branch jax-0.9-support \
        https://github.com/Akash-Harapanahalli/immrax.git /tmp/immrax && \
    sed -i 's|git@github.com:|https://github.com/|g' /tmp/immrax/.gitmodules 2>/dev/null || true && \
    git -C /tmp/immrax submodule sync --recursive 2>/dev/null || true && \
    git -C /tmp/immrax submodule update --init --recursive 2>/dev/null || true && \
    pip3 install --no-cache-dir --break-system-packages /tmp/immrax && \
    rm -rf /tmp/immrax

# ── linrax (jax-0.9-support branch) ──────────────────────────────────────────
# Linear systems support library used by the contraction controller.
RUN git clone --depth 1 --branch jax-0.9-support \
        https://github.com/gtfactslab/linrax.git /tmp/linrax && \
    pip3 install --no-cache-dir --break-system-packages /tmp/linrax && \
    rm -rf /tmp/linrax

# ── Shell setup: source chain ROS → px4_msgs → workspace ─────────────────────
# /etc/profile.d/ is sourced by login shells (bash -lc); .bashrc for interactive.
RUN echo "source /opt/ros/jazzy/setup.bash" > /etc/profile.d/ros_setup.sh && \
    echo "source /opt/ws_px4_msgs/install/setup.bash" >> /etc/profile.d/ros_setup.sh && \
    echo 'if [ -f /workspace/install/setup.bash ]; then source /workspace/install/setup.bash; fi' >> /etc/profile.d/ros_setup.sh && \
    echo "source /etc/profile.d/ros_setup.sh" >> /root/.bashrc

WORKDIR /workspace

CMD ["bash"]
