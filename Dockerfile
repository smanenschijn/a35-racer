# A35 Racer, web build: Godot exports the game to WebAssembly, nginx serves it.
# Dokploy: "Build Type: Dockerfile", port 80.
FROM debian:bookworm-slim AS build
ARG GODOT_VERSION=4.7.2
ARG TARGETARCH
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl unzip libfontconfig1 && rm -rf /var/lib/apt/lists/*
WORKDIR /opt/godot
RUN arch=$([ "$TARGETARCH" = "arm64" ] && echo arm64 || echo x86_64) \
 && curl -fsSL -o godot.zip "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.${arch}.zip" \
 && unzip -q godot.zip && mv Godot_v*_linux.* /usr/local/bin/godot && rm godot.zip
# Only the web template is needed from the (large) template bundle.
RUN curl -fsSL -o t.tpz "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_export_templates.tpz" \
 && unzip -q t.tpz "templates/web_nothreads_release.zip" "templates/version.txt" \
 && mkdir -p /root/.local/share/godot/export_templates/${GODOT_VERSION}.stable \
 && mv templates/* /root/.local/share/godot/export_templates/${GODOT_VERSION}.stable/ && rm -rf t.tpz templates
WORKDIR /src
COPY godot/ ./
RUN mkdir -p build/web \
 && godot --headless --path . --import >/dev/null 2>&1 || true
RUN godot --headless --path . --export-release Web build/web/index.html \
 && test -s build/web/index.pck

FROM nginx:1.27-alpine
COPY deploy/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /src/build/web /usr/share/nginx/html
EXPOSE 80
