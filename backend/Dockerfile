# Gunakan base image Python 3.11 slim yang ringan
FROM python:3.11-slim

# Set environment variables untuk Python
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app

# Set direktori kerja di dalam container
WORKDIR /app

# Install system dependencies (jika diperlukan untuk packages yang perlu dicompile seperti bcrypt/asyncpg dll)
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy file requirements terlebih dahulu untuk memanfaatkan caching layer Docker
COPY requirements.txt .

# Install dependencies Python
# (Opsional: kamu bisa memisahkan testing dependencies agar image production lebih kecil, tapi di sini kita install semua yang ada di requirements)
RUN pip install --no-cache-dir -r requirements.txt

# Copy seluruh source code backend ke dalam container
COPY . .

# Expose port yang akan digunakan oleh Uvicorn
EXPOSE 8080

# Jalankan Uvicorn dengan host 0.0.0.0 agar bisa diakses dari luar container
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]
