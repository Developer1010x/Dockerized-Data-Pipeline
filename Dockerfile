FROM apache/airflow:2.7.0

USER root

# Install system dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        gcc \
        python3-dev \
        libpq-dev && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

USER airflow

# Install Python dependencies
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir \
        apache-airflow[postgres]==2.7.0 \
        pandas \
        requests \
        psycopg2-binary

# Create scripts directory
RUN mkdir -p /opt/airflow/scripts

WORKDIR /opt/airflow