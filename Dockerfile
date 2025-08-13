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

# Runtime stage
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
    xz \
    shadow && \
    # Create nix directory and nixbld group (for runtime Nix installation)
    mkdir -m 0755 /nix && \
    groupadd -g 30000 nixbld && \
    useradd -u 30001 -g nixbld -M -s /bin/false nixbld1

# Copy the built binary from builder stage
COPY --from=builder /build/nixery /usr/local/bin/server

# Copy web assets
COPY --from=builder /build/web /var/lib/nixery/web

# Copy prepare-image scripts
COPY --from=builder /build/prepare-image /usr/local/bin/nixery-prepare-image


# Set environment variables
ENV WEB_DIR=/var/lib/nixery/web \
    PATH=/nix/var/nix/profiles/default/bin:/root/.nix-profile/bin:/usr/local/bin/nixery-prepare-image:$PATH \
    NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt

# Create necessary directories
RUN mkdir -p /tmp /var/cache/nixery

# Expose the default port
EXPOSE 8080

# Create startup script that installs Nix at runtime
RUN echo '#!/bin/bash' > /usr/local/bin/start-nixery.sh && \
    echo 'set -e' >> /usr/local/bin/start-nixery.sh && \
    echo '' >> /usr/local/bin/start-nixery.sh && \
    echo '# Debug: Check current user and /nix permissions' >> /usr/local/bin/start-nixery.sh && \
    echo 'echo "Current user: $(whoami) (UID: $(id -u))"' >> /usr/local/bin/start-nixery.sh && \
    echo 'echo "/nix directory permissions: $(ls -ld /nix)"' >> /usr/local/bin/start-nixery.sh && \
    echo '' >> /usr/local/bin/start-nixery.sh && \
    echo '# Install Nix if not already present' >> /usr/local/bin/start-nixery.sh && \
    echo 'if [ ! -f /root/.nix-profile/etc/profile.d/nix.sh ]; then' >> /usr/local/bin/start-nixery.sh && \
    echo '  echo "Installing Nix..."' >> /usr/local/bin/start-nixery.sh && \
    echo '  export USER=root' >> /usr/local/bin/start-nixery.sh && \
    echo '  # Ensure proper ownership of /nix directory' >> /usr/local/bin/start-nixery.sh && \
    echo '  chown -R root:root /nix' >> /usr/local/bin/start-nixery.sh && \
    echo '  sh <(curl -L https://nixos.org/nix/install) --no-daemon --yes' >> /usr/local/bin/start-nixery.sh && \
    echo '  # Configure Nix' >> /usr/local/bin/start-nixery.sh && \
    echo '  mkdir -p /etc/nix' >> /usr/local/bin/start-nixery.sh && \
    echo '  echo "sandbox = false" >> /etc/nix/nix.conf' >> /usr/local/bin/start-nixery.sh && \
    echo '  echo "experimental-features = nix-command flakes" >> /etc/nix/nix.conf' >> /usr/local/bin/start-nixery.sh && \
    echo 'fi' >> /usr/local/bin/start-nixery.sh && \
    echo '' >> /usr/local/bin/start-nixery.sh && \
    echo '# Source Nix environment' >> /usr/local/bin/start-nixery.sh && \
    echo 'if [ -f /root/.nix-profile/etc/profile.d/nix.sh ]; then' >> /usr/local/bin/start-nixery.sh && \
    echo '  . /root/.nix-profile/etc/profile.d/nix.sh' >> /usr/local/bin/start-nixery.sh && \
    echo 'fi' >> /usr/local/bin/start-nixery.sh && \
    echo '' >> /usr/local/bin/start-nixery.sh && \
    echo '# Start nixery server' >> /usr/local/bin/start-nixery.sh && \
    echo 'exec /usr/local/bin/server "$@"' >> /usr/local/bin/start-nixery.sh && \
    chmod +x /usr/local/bin/start-nixery.sh

# Set the default command
CMD ["/usr/local/bin/start-nixery.sh"]