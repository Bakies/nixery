# Build stage
FROM golang:1.20-alpine AS builder

# Install build dependencies
RUN apk add --no-cache git ca-certificates

# Set working directory
WORKDIR /build

# Copy go mod files
COPY go.mod go.sum ./

# Download dependencies
RUN go mod download

# Copy source code
COPY . .

# Build the server binary
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w -X main.version=docker" -o nixery ./cmd/server

# Runtime stage - use nixos/nix which has Nix pre-installed
FROM nixos/nix:2.19.2 AS nix-base

# Runtime stage with pre-installed Nix
FROM alpine:3.19

# Install runtime dependencies
RUN apk add --no-cache \
    bash \
    coreutils \
    git \
    tar \
    gzip \
    openssh \
    ca-certificates \
    curl \
    xz && \
    # Create user 1000 for non-root execution
    adduser -D -u 1000 -g 1000 nixery && \
    # Create directories with proper ownership
    mkdir -p /home/nixery/.nix-profile /var/cache/nixery /tmp && \
    chown -R nixery:nixery /home/nixery /var/cache/nixery /tmp

# Copy Nix installation from nixos/nix image
COPY --from=nix-base --chown=nixery:nixery /nix /nix
COPY --from=nix-base --chown=nixery:nixery /root/.nix-profile /home/nixery/.nix-profile
COPY --from=nix-base --chown=nixery:nixery /root/.nix-channels /home/nixery/.nix-channels

# Configure Nix for non-root user
RUN mkdir -p /etc/nix && \
    echo 'sandbox = false' >> /etc/nix/nix.conf && \
    echo 'experimental-features = nix-command flakes' >> /etc/nix/nix.conf && \
    echo 'build-users-group =' >> /etc/nix/nix.conf

# Copy the built binary from builder stage
COPY --from=builder /build/nixery /usr/local/bin/server

# Copy web assets
COPY --from=builder /build/web /var/lib/nixery/web

# Copy prepare-image scripts
COPY --from=builder /build/prepare-image /usr/local/bin/nixery-prepare-image


# Create simple startup script (as root before switching user)
RUN echo '#!/bin/bash' > /usr/local/bin/start-nixery.sh && \
    echo 'set -e' >> /usr/local/bin/start-nixery.sh && \
    echo '# Source Nix environment' >> /usr/local/bin/start-nixery.sh && \
    echo 'if [ -f /home/nixery/.nix-profile/etc/profile.d/nix.sh ]; then' >> /usr/local/bin/start-nixery.sh && \
    echo '  . /home/nixery/.nix-profile/etc/profile.d/nix.sh' >> /usr/local/bin/start-nixery.sh && \
    echo 'fi' >> /usr/local/bin/start-nixery.sh && \
    echo '# Start nixery server' >> /usr/local/bin/start-nixery.sh && \
    echo 'exec /usr/local/bin/server "$@"' >> /usr/local/bin/start-nixery.sh && \
    chmod +x /usr/local/bin/start-nixery.sh

# Set environment variables
ENV WEB_DIR=/var/lib/nixery/web \
    USER=nixery \
    HOME=/home/nixery \
    PATH=/home/nixery/.nix-profile/bin:/nix/var/nix/profiles/default/bin:/usr/local/bin/nixery-prepare-image:$PATH \
    NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt

# Expose the default port
EXPOSE 8080

# Switch to nixery user
USER nixery

# Set the default command
CMD ["/usr/local/bin/start-nixery.sh"]