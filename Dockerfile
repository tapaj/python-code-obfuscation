# Use official Python base image
FROM python:3.14-slim

# Set environment variables
ENV PYTHONDONTWRITEBYTECODE 1
ENV PYTHONUNBUFFERED 1

# Set work directory
WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Copy uv installation script and install uv
COPY --from=ghcr.io/astral-sh/uv:latest /uv /bin/uv

# Copy project requirements and install dependencies with uv
COPY pyproject.toml uv.lock ./
RUN uv pip install --system --no-cache-dir -r uv.lock

# Copy project
COPY . .

# Create non-root user
RUN adduser --disabled-password --gecos '' appuser && \
    chown -R appuser:appuser /app
USER appuser

# Expose port
EXPOSE 8000

# Run the application with WSGI using uv
CMD ["uv", "run", "gunicorn", "--bind", "0.0.0.0:8000", "core.wsgi:application"]