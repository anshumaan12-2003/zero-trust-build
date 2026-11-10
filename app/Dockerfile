# For local use only, such as the kind drills in Week 2. It runs npm while
# building, so it is never used for release. Releases use release/Dockerfile.

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
