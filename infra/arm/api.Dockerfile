ARG NODE_IMAGE
FROM ${NODE_IMAGE}
ARG TARGETARCH
RUN test "$TARGETARCH" = "arm64"
WORKDIR /app
COPY backend/package.json backend/package-lock.json ./
RUN npm ci --ignore-scripts --include=dev --no-audit --no-fund
COPY backend/src ./backend/src
COPY backend/migrations ./backend/migrations
COPY web ./web
COPY build/web ./build/web
COPY infra/arm/api-entry.ts ./infra/arm/api-entry.ts
USER node
CMD ["node", "--import", "tsx", "infra/arm/api-entry.ts"]
