FROM python:3.11-slim-bookworm

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

COPY zkteco_adms/requirements.txt /tmp/requirements.txt

RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir -r /tmp/requirements.txt

COPY pyodbc.py /app/pyodbc.py
COPY zkteco_adms /app/zkteco_adms

WORKDIR /app/zkteco_adms

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
