FROM python:3.9-slim

WORKDIR /app

# Install curl and jq for debugging
RUN apt-get update && apt-get install -y curl jq

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 5000

CMD ["python", "app.py"]
