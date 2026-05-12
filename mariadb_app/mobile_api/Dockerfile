FROM python:3.11-slim-bookworm

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

COPY mobile_api/requirements.txt /tmp/requirements.txt

RUN apt-get update \
    && apt-get install -y --no-install-recommends libgl1 libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/* \
    && pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir -r /tmp/requirements.txt

COPY pyodbc.py /app/pyodbc.py
COPY mobile_api /app/mobile_api

WORKDIR /app/mobile_api

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
