# Build context: repository root (needs packages/content for seeding)
FROM node:20-bookworm-slim AS build
WORKDIR /repo/apps/api
RUN apt-get update && apt-get install -y --no-install-recommends openssl && rm -rf /var/lib/apt/lists/*
COPY apps/api/package*.json ./
COPY apps/api/prisma ./prisma
RUN npm install --no-audit --no-fund
COPY apps/api ./
COPY packages /repo/packages
RUN npx prisma generate && npm run build

FROM node:20-bookworm-slim
WORKDIR /repo/apps/api
RUN apt-get update && apt-get install -y --no-install-recommends openssl && rm -rf /var/lib/apt/lists/*
ENV NODE_ENV=production
COPY --from=build /repo/apps/api/node_modules ./node_modules
COPY --from=build /repo/apps/api/dist ./dist
COPY --from=build /repo/apps/api/prisma ./prisma
COPY --from=build /repo/apps/api/package.json ./
COPY --from=build /repo/packages /repo/packages
USER node
EXPOSE 3000
CMD ["sh", "-c", "npx prisma migrate deploy && node dist/main.js"]
