ARG NODE_IMAGE
FROM ${NODE_IMAGE}
ARG TARGETARCH
RUN test "$TARGETARCH" = "arm64"
WORKDIR /app
COPY --chmod=0555 build/server/gnom-racing.arm64 ./gnom-racing.arm64
COPY build/server/gnom-racing.pck ./gnom-racing.pck
USER node
ENTRYPOINT ["/app/gnom-racing.arm64"]
CMD ["--headless", "--log-file", "/tmp/godot.log", "--", "--race-worker"]
