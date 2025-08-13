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
FROM nixos/nix:2.19.2

# Install runtime dependencies
RUN nix-channel --add https://nixos.org/channels/nixpkgs-unstable nixpkgs && \
    nix-channel --update && \
    nix-env -iA nixpkgs.bash \
                nixpkgs.coreutils \
                nixpkgs.git \
                nixpkgs.gnutar \
                nixpkgs.gzip \
                nixpkgs.openssh \
                nixpkgs.cacert && \
    nix-collect-garbage -d

# Copy the built binary from builder stage
COPY --from=builder /build/nixery /usr/local/bin/server

# Copy web assets
COPY --from=builder /build/web /var/lib/nixery/web

# Copy prepare-image scripts
COPY --from=builder /build/prepare-image /nix/store/nixery-prepare-image

# Create nixery user and group
RUN echo 'nixbld:x:30000:nixbld' >> /etc/group && \
    echo 'nixbld:x:30000:30000:nixbld:/tmp:/bin/bash' >> /etc/passwd

# Set up Nix configuration
RUN mkdir -p /etc/nix && \
    echo 'sandbox = false' >> /etc/nix/nix.conf && \
    echo 'experimental-features = nix-command flakes' >> /etc/nix/nix.conf

# Set environment variables
ENV WEB_DIR=/var/lib/nixery/web \
    PATH=/nix/store/nixery-prepare-image:$PATH \
    NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt

# Create necessary directories
RUN mkdir -p /tmp /var/cache/nixery

# Expose the default port
EXPOSE 8080

# Set the default command
CMD ["/usr/local/bin/server"]