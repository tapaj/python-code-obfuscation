# Stage 1: Build obfuscated code
# Pin base image to digest for immutability, security, and consistency:
#   - Immutability: ensures the exact same image content is always used
#   - Security: prevents supply chain attacks by detecting tampered content
#   - Consistency: guarantees same image across dev, staging, and production
# See: https://docs.docker.com/build/building/best-practices/#pin-base-image-versions
FROM python:3.14-slim@sha256:cea0e6040540fb2b965b6e7fb5ffa00871e632eef63719f0ea54bca189ce14a6 AS builder

# Install system dependencies
# Use --no-install-recommends to skip suggested packages and reduce image size:
#   - Reduces image size: recommended packages often aren't required for the app
#   - Reduces attack surface: fewer packages = fewer potential vulnerabilities
#   - Faster builds: fewer packages to install and pull
#   - Cleaner dependencies: only explicit packages are included
# See: https://docs.docker.com/build/building/best-practices/
# rm -rf /var/lib/apt/lists/* removes apt package cache to reduce image size:
#   - Saves 20-40MB per layer by removing package metadata
#   - Cache is only needed during apt-get update/install, not at runtime
#   - Standard best practice for production images
# See: https://docs.docker.com/build/cache/optimize/
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Set environment variables
# PYTHONDONTWRITEBYTECODE=1: prevents Python from writing .pyc files to disk,
#   reducing image size by avoiding unnecessary bytecode (regenerated at runtime)
ENV PYTHONDONTWRITEBYTECODE=1

# Set work directory for builder
WORKDIR /build

# Copy project files for build
# Keep COPY commands separate for better layer caching:
#   - If application code (api/, core/) changes, only those layers rebuild
#   - Dependencies (pyproject.toml, uv.lock) stay cached and don't rebuild
#   - Combining into single COPY would invalidate entire layer on any file change,
#     forcing unnecessary rebuilds and defeating Docker's layer caching benefits
# See: https://docs.docker.com/build/cache/optimize/#order-your-layers
COPY pyproject.toml uv.lock ./
COPY api/ ./api/
COPY core/ ./core/
COPY manage.py ./

# Install uv
# rm -rf /root/.cache removes uv's download cache to reduce layer size:
#   - Cache is only needed during uv installation, not after
#   - Builder stage is discarded anyway, so keeping cache here is pure waste
#   - Keeps layer lean and follows Docker best practice of cleaning up package manager caches
# See: https://docs.docker.com/build/cache/optimize/
RUN curl -LsSf https://astral.sh/uv/install.sh | sh \
    && rm -rf /root/.cache

# Update PATH for uv
ENV PATH="/root/.local/bin:$PATH"

# Install dependencies
# Use --frozen --no-dev flags:
#   --frozen: prevents uv from updating uv.lock, ensuring exact versions are used
#     for reproducible builds (same lockfile = same dependencies, no surprises)
#   --no-dev: excludes development dependencies, reducing image size and attack surface
#     by skipping test frameworks, linters, type checkers not needed at runtime
# See: https://docs.docker.com/build/cache/
RUN uv sync --frozen --no-dev

# Install pyarmor for build stage only
RUN uv add pyarmor

# Generate obfuscated code
RUN uv run pyarmor generate --recursive --output dist/ api/ core/

# Copy manage.py to dist folder
RUN cp manage.py dist/

# Stage 2: Runtime image
# Pin base image to digest for immutability, security, and consistency:
#   - Immutability: ensures the exact same image content is always used
#   - Security: prevents supply chain attacks by detecting tampered content
#   - Consistency: guarantees same image across dev, staging, and production
# See: https://docs.docker.com/build/building/best-practices/#pin-base-image-versions
FROM python:3.14-slim@sha256:cea0e6040540fb2b965b6e7fb5ffa00871e632eef63719f0ea54bca189ce14a6 AS runtime

# Install system dependencies (curl needed for uv install)
# Use --no-install-recommends to skip suggested packages and reduce image size:
#   - Reduces image size: recommended packages often aren't required for the app
#   - Reduces attack surface: fewer packages = fewer potential vulnerabilities
#   - Faster builds: fewer packages to install and pull
#   - Cleaner dependencies: only explicit packages are included
# See: https://docs.docker.com/build/building/best-practices/
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    && rm -rf /var/lib/apt/lists/*
# rm -rf /var/lib/apt/lists/* removes apt package cache to reduce image size:
#   - Saves 20-40MB per layer by removing package metadata
#   - Cache is only needed during apt-get update/install, not at runtime
#   - Standard best practice for production images
# See: https://docs.docker.com/build/cache/optimize/

# Create a non-root user and group
ARG APP_USER=appuser
ARG APP_UID=1000
ARG APP_GID=1000

# --create-home creates $HOME directory (e.g., /home/appuser) which is needed for:
#   - Environment variables ($HOME) expected by many tools
#   - User-specific configs, caches, and temp data (.cache/, .config/, .local/)
#   - uv installation and cache management ($HOME/.local/bin, $HOME/.cache)
# See: https://docs.docker.com/engine/security/rootless/
RUN groupadd --gid ${APP_GID} ${APP_USER} \
    && useradd --uid ${APP_UID} --gid ${APP_GID} --shell /usr/sbin/nologin --create-home ${APP_USER}

# Set environment variables
# PYTHONDONTWRITEBYTECODE=1: prevents Python from writing .pyc files to disk,
#   reducing image size by avoiding unnecessary bytecode (regenerated at runtime)
# See: https://docs.docker.com/guides/python/
# PYTHONUNBUFFERED=1: makes Python output unbuffered so logs are written immediately
#   to stdout/stderr, enabling real-time log capture by Docker (critical for monitoring)
# PATH includes $HOME/.local/bin where uv installs its binary when installed as non-root user.
#   Without this, the CMD line (uv run gunicorn...) will fail with "command not found"
#   because the shell won't find the uv executable in the default PATH directories
# See: https://docs.docker.com/build/building/best-practices/
ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1
ENV PATH="/home/${APP_USER}/.local/bin:$PATH"

# Set work directory
WORKDIR /usr/app
RUN chown -R ${APP_USER}:${APP_USER} /usr/app

# Copy uv configuration from builder stage
COPY --from=builder --chown=${APP_USER}:${APP_USER} /build/pyproject.toml /build/uv.lock ./

# Install uv and dependencies as non-root user
USER ${APP_USER}
RUN curl -LsSf https://astral.sh/uv/install.sh | sh \
    && rm -rf /home/${APP_USER}/.cache
# rm -rf /home/${APP_USER}/.cache removes uv's download cache to reduce image size:
#   - Cache is only needed during uv installation, not at runtime
#   - Keeps final image lean and follows Docker best practice of cleaning up package manager caches
# See: https://docs.docker.com/build/cache/optimize/
# uv sync flags:
#   --frozen: prevents uv from updating uv.lock, ensuring exact versions are used
#     for reproducible builds (same lockfile = same dependencies, no surprises)
#   --no-dev: excludes development dependencies, reducing image size and attack surface
#     by skipping test frameworks, linters, type checkers not needed at runtime
# See: https://docs.docker.com/build/cache/
RUN uv sync --frozen --no-dev \
    && rm -rf /home/${APP_USER}/.cache

# Copy obfuscated code from builder stage
COPY --from=builder --chown=${APP_USER}:${APP_USER} /build/dist/ ./

# Expose port
EXPOSE 8000

# Run the application with Gunicorn using obfuscated code
CMD ["uv", "run", "gunicorn", "--bind", "0.0.0.0:8000", "core.wsgi:application"]
