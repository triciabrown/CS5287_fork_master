# Plant Monitoring Data Processor
FROM python:3.9-alpine

WORKDIR /app

# Install dependencies
RUN apk add --no-cache gcc musl-dev && \
    pip install --no-cache-dir kafka-python pymongo

# Copy application code
COPY processor.py .
COPY requirements.txt .

# Install application dependencies
RUN pip install -r requirements.txt

# Run as non-root user
RUN adduser -D appuser && chown -R appuser:appuser /app
USER appuser

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD python -c "import pymongo, kafka; print('Health OK')" || exit 1

CMD ["python", "plant-care-processor.py"]