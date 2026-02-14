FROM mcr.microsoft.com/playwright/python:v1.50.0-noble

WORKDIR /app

# Install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Install Playwright browsers
RUN playwright install chromium

# Copy application code
COPY agent.py .
COPY entrypoint.sh .
RUN chmod +x entrypoint.sh

# Run as non-root for security
RUN useradd -m agent || true
USER agent

ENTRYPOINT ["/app/entrypoint.sh"]
