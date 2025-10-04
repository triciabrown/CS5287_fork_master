# Plant Monitoring Producer - Sensor Data Generator
FROM python:3.9-alpine

WORKDIR /app

# Install dependencies
RUN pip install --no-cache-dir kafka-python pymongo

# Copy application code
COPY producer.py .
COPY requirements.txt .

# Install application dependencies
RUN pip install -r requirements.txt

# Run as non-root user
RUN adduser -D appuser && chown -R appuser:appuser /app
USER appuser

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD python -c "import kafka; print('Health OK')" || exit 1

CMD ["python", "producer.py"]