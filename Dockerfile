FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

# Install system dependencies: texlive, libreoffice, python3, curl, wget
RUN apt-get update && apt-get install -y --no-install-recommends \
    texlive-full \
    texlive-extra-utils \
    latexmk \
    libreoffice \
    libreoffice-writer \
    python3.12 \
    python3.12-dev \
    python3-pip \
    python3-venv \
    curl \
    wget \
    ca-certificates \
    git \
    librsvg2-bin \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install uv for Python package management
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.cargo/bin:/root/.local/bin:$PATH"

# Install pandoc from GitHub releases (latest)
RUN PANDOC_VERSION=$(curl -s https://api.github.com/repos/jgm/pandoc/releases/latest | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/') && \
    wget -q "https://github.com/jgm/pandoc/releases/download/${PANDOC_VERSION}/pandoc-${PANDOC_VERSION}-linux-amd64.tar.gz" -O /tmp/pandoc.tar.gz && \
    tar -xzf /tmp/pandoc.tar.gz -C /tmp && \
    mv /tmp/pandoc-${PANDOC_VERSION}/bin/pandoc /usr/local/bin/pandoc && \
    rm -rf /tmp/pandoc*

WORKDIR /app

# Create virtual environment and install Python deps
COPY pyproject.toml ./
RUN uv venv /app/.venv && \
    . /app/.venv/bin/activate && \
    uv pip install -e .
ENV VIRTUAL_ENV=/app/.venv
ENV PATH="/app/.venv/bin:$PATH"

# Copy backend source
COPY backend/ ./backend/

EXPOSE 8000

CMD ["uvicorn", "backend.main:app", "--host", "0.0.0.0", "--port", "8000"]
