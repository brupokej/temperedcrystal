FROM ubuntu:24.04

RUN apt-get update \
	&& DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
		build-essential cmake ca-certificates curl liblua5.4-dev libpng-dev \
	&& rm -rf /var/lib/apt/lists/*

# Headless doesn't give the renderer an output buffer, so emu:screenshot would
# segfault without this patch.
COPY mgba-headless-video-buffer.patch /tmp/

ARG MGBA_COMMIT=9fcaa882f25de40258f9578480854e590db12699
RUN curl -fsSL "https://github.com/mgba-emu/mgba/archive/${MGBA_COMMIT}.tar.gz" | tar -xz -C /tmp \
	&& patch -d "/tmp/mgba-${MGBA_COMMIT}" -p1 < /tmp/mgba-headless-video-buffer.patch \
	&& cmake -S "/tmp/mgba-${MGBA_COMMIT}" -B /tmp/build \
		-DCMAKE_BUILD_TYPE=Release -DBUILD_HEADLESS=ON -DBUILD_QT=OFF -DBUILD_SDL=OFF \
	&& cmake --build /tmp/build -j"$(nproc)" \
	&& cmake --install /tmp/build \
	&& ldconfig \
	&& rm -rf /tmp/build "/tmp/mgba-${MGBA_COMMIT}"
