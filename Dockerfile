# Use the official Python image as base
FROM python:3.14-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Create a non-root user and group
ARG APP_USER=appuser
ARG APP_UID=1000
ARG APP_GID=1000

RUN groupadd --gid ${APP_GID} ${APP_USER} \
    && useradd --uid ${APP_UID} --gid ${APP_GID} --shell /usr/sbin/nologin --create-home ${APP_USER}

# Set environment variables
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV PATH="/home/${APP_USER}/.local/bin:$PATH"

# Set work directory and adjust ownership
WORKDIR /usr/app
RUN chown -R ${APP_USER}:${APP_USER} /usr/app

# Copy uv configuration files
COPY --chown=${APP_USER}:${APP_USER} pyproject.toml uv.lock ./

# Install uv and dependencies as non-root user
USER ${APP_USER}
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
RUN uv sync --frozen --no-dev

# Copy application code
COPY --chown=${APP_USER}:${APP_USER} . .

# Expose port
EXPOSE 8000

# Run the application with Gunicorn
CMD ["uv", "run", "gunicorn", "--bind", "0.0.0.0:8000", "core.wsgi:application"]
