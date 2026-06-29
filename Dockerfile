ARG ZIG_VERSION=0.16.0

FROM debian:bookworm-slim AS build

ARG ZIG_VERSION
ARG TARGETARCH
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl xz-utils \
    && rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    case "${TARGETARCH:-amd64}" in \
        amd64) zig_arch="x86_64-linux" ;; \
        arm64) zig_arch="aarch64-linux" ;; \
        *) echo "Unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    curl -fsSLo /tmp/zig.tar.xz "https://ziglang.org/download/${ZIG_VERSION}/zig-${zig_arch}-${ZIG_VERSION}.tar.xz"; \
    mkdir -p /opt/zig; \
    tar -xJf /tmp/zig.tar.xz -C /opt/zig --strip-components=1; \
    rm /tmp/zig.tar.xz

ENV PATH="/opt/zig:${PATH}"
ENV ZIG_CACHE_DIR=/tmp/zig-cache
ENV ZIG_GLOBAL_CACHE_DIR=/tmp/zig-global-cache
WORKDIR /app

COPY build.zig build.zig.zon ./
COPY deps ./deps
COPY src ./src

RUN zig version \
    && mkdir -p "${ZIG_CACHE_DIR}" "${ZIG_GLOBAL_CACHE_DIR}/tmp" zig-pkg/.tmp \
    && zig fetch --global-cache-dir "${ZIG_GLOBAL_CACHE_DIR}" "https://www.sqlite.org/2025/sqlite-amalgamation-3490200.zip" \
    && zig build --fetch --cache-dir "${ZIG_CACHE_DIR}" --global-cache-dir "${ZIG_GLOBAL_CACHE_DIR}" \
    && zig build -Doptimize=ReleaseFast --cache-dir "${ZIG_CACHE_DIR}" --global-cache-dir "${ZIG_GLOBAL_CACHE_DIR}"

FROM debian:bookworm-slim AS runtime

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
ENV PORT=3000
ENV DATA_DIR=/data

RUN mkdir -p /data
COPY --from=build /app/zig-out/bin/ZigReflect /app/ZigReflect

EXPOSE 3000
CMD ["/app/ZigReflect"]
