# ==============================================================================
# Milestone 1: Multi-Stage Production Dockerfile for Macky Merch API
# DevSecOps Standards:
#   1. Multi-stage build for minimal attack surface & lean image size
#   2. Deterministic dependency resolution via npm ci
#   3. Least Privilege: Run as non-root user (node - UID:GID 1000:1000)
#   4. Explicit signal handling via exec-form CMD (proper PID 1 termination)
# ==============================================================================

# ------------------------------------------------------------------------------
# Stage 1: Builder
# Purpose: Install dependencies deterministically and prepare application files
# ------------------------------------------------------------------------------
FROM node:20-alpine AS builder

WORKDIR /app

# Copy dependency manifests first to leverage Docker layer caching
COPY package*.json ./

# Install only production dependencies deterministically
# --omit=dev ensures testing/dev dependencies (jest, supertest) are excluded
RUN npm ci --omit=dev && npm cache clean --force

# Copy application source code
COPY . .

# ------------------------------------------------------------------------------
# Stage 2: Runner
# Purpose: Lean, minimal production container copying only necessary artifacts
# ------------------------------------------------------------------------------
FROM node:20-alpine AS runner

# Set production environment variables
ENV NODE_ENV=production \
    PORT=3000

# Set application directory and ensure ownership for the non-root node user
WORKDIR /app
RUN chown -R node:node /app

# Switch to non-root user (Principle of Least Privilege)
USER node

# Copy only necessary production artifacts from the builder stage
COPY --chown=node:node --from=builder /app/node_modules ./node_modules
COPY --chown=node:node --from=builder /app/package.json ./package.json
COPY --chown=node:node --from=builder /app/server.js ./server.js

# Expose API port
EXPOSE 3000

# Start Express server using exec form to allow graceful SIGTERM/SIGINT shutdown
CMD ["node", "server.js"]
