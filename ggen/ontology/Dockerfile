FROM python:3.9-slim

# Set working directory
WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    wget \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy ontology files
COPY *.ttl .
COPY examples/ ./examples/
COPY *.py ./
COPY Makefile ./

# Make validation script executable
RUN chmod +x validate_ontology.py test_ontology.py

# Default command
CMD ["make", "help"]