# Use Python 3.11 slim image
FROM python:3.11-slim

# Install system dependencies INCLUDING MUSESCORE
RUN apt-get update && apt-get install -y \
    build-essential \
    libsndfile1 \
    ffmpeg \
    musescore3 \
    xvfb \
    fonts-dejavu-core \
    fonts-freefont-ttf \
    && rm -rf /var/lib/apt/lists/*

# Create a non-root user (required by Hugging Face Spaces)
RUN useradd -m -u 1000 user

# Set working directory
WORKDIR /app

# Copy requirements first for better caching
COPY requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy all application files with proper ownership
COPY --chown=user:user . .

# Create necessary directories with proper permissions
RUN mkdir -p uploads output && \
    chown -R user:user /app && \
    chmod -R 755 /app && \
    chmod -R 777 /app/uploads /app/output

# Set up virtual display environment for MuseScore
ENV DISPLAY=:99

# Switch to non-root user
USER user

# Expose port
EXPOSE 7860

# Run the application with virtual display setup
CMD ["python", "app.py"]