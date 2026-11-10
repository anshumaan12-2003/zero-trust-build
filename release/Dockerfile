# Release image: COPY only. There is no RUN step, so nothing from the build
# executes on the machine that holds the signing permission.
# The build context is the judged build output, unpacked by release/unpack.py.
FROM node:22-slim@sha256:5ec23b7c622b00547753bc6ffd78085dd868a68aeb41c8e0a1418f033e13d96d
ENV NODE_ENV=production
WORKDIR /app
COPY package.json ./
COPY node_modules ./node_modules
COPY dist ./dist
USER node
EXPOSE 3000
CMD ["node", "dist/server.js"]
