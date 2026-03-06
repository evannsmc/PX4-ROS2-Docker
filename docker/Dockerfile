FROM osrf/ros:jazzy-desktop-full

SHELL ["/bin/bash", "-c"]

ENV DEBIAN_FRONTEND=noninteractive
ENV VIRTUAL_ENV=/opt/px4-venv
ENV PATH="${VIRTUAL_ENV}/bin:${PATH}"
# Venv site-packages first, then ROS 2 Python bindings — no system site-packages mixed in.
ENV PYTHONPATH="${VIRTUAL_ENV}/lib/python3.12/site-packages:/opt/ros/jazzy/lib/python3.12/site-packages"

# ── System deps ───────────────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3-pip \
    python3-venv \
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

# ── Python virtual environment (isolated — no --system-site-packages) ─────────
COPY docker/requirements.txt /tmp/requirements.txt

RUN python3 -m venv "${VIRTUAL_ENV}" && \
    "${VIRTUAL_ENV}/bin/pip" install --no-cache-dir --upgrade pip "setuptools<72" wheel && \
    "${VIRTUAL_ENV}/bin/pip" install --no-cache-dir -r /tmp/requirements.txt

# ── immrax (jax-0.9-support branch) ──────────────────────────────────────────
# Interval arithmetic library used by the contraction controller.
RUN git clone --depth 1 --branch jax-0.9-support \
        https://github.com/Akash-Harapanahalli/immrax.git /tmp/immrax && \
    sed -i 's|git@github.com:|https://github.com/|g' /tmp/immrax/.gitmodules 2>/dev/null || true && \
    git -C /tmp/immrax submodule sync --recursive 2>/dev/null || true && \
    git -C /tmp/immrax submodule update --init --recursive 2>/dev/null || true && \
    "${VIRTUAL_ENV}/bin/pip" install --no-cache-dir /tmp/immrax && \
    rm -rf /tmp/immrax

# ── linrax (jax-0.9-support branch) ──────────────────────────────────────────
# Linear systems support library used by the contraction controller.
RUN git clone --depth 1 --branch jax-0.9-support \
        https://github.com/gtfactslab/linrax.git /tmp/linrax && \
    "${VIRTUAL_ENV}/bin/pip" install --no-cache-dir /tmp/linrax && \
    rm -rf /tmp/linrax

# ── Shell setup: source chain ROS → px4_msgs → venv → workspace ──────────────
# /etc/profile.d/ is sourced by login shells (bash -lc); .bashrc for interactive.
RUN echo "source /opt/ros/jazzy/setup.bash" > /etc/profile.d/ros_setup.sh && \
    echo "source /opt/ws_px4_msgs/install/setup.bash" >> /etc/profile.d/ros_setup.sh && \
    echo "source ${VIRTUAL_ENV}/bin/activate" >> /etc/profile.d/ros_setup.sh && \
    echo 'if [ -f /workspace/install/setup.bash ]; then source /workspace/install/setup.bash; fi' >> /etc/profile.d/ros_setup.sh && \
    echo "source /etc/profile.d/ros_setup.sh" >> /root/.bashrc

WORKDIR /workspace

CMD ["bash"]
