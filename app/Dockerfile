# Week 1 Dockerfile: a normal multi-stage build.
# Week 5 replaces it with a COPY-only file, so no code runs while the image is assembled.

# Stage 1: install everything, including TypeScript, and compile.
FROM node:22-slim AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY tsconfig.json ./
COPY src ./src
RUN npm run build

# Stage 2: only what the app needs to run. TypeScript and the source stay behind.
FROM node:22-slim
ENV NODE_ENV=production
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force
COPY --from=build /app/dist ./dist
USER node
EXPOSE 3000
CMD ["node", "dist/server.js"]
