FROM python:3.11-slim

WORKDIR /app

# Copy telegram-bot files
COPY telegram-bot/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY telegram-bot/bot.py .

CMD ["python", "bot.py"]
