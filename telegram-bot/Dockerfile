FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY bot.py .
COPY analytics.py .
COPY mcp_server.py .
COPY egregore-setup.zip .
COPY .env.example .env

CMD ["python", "bot.py"]
