from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.python_operator import PythonOperator
from airflow.operators.postgres_operator import PostgresOperator
from airflow.hooks.postgres_hook import PostgresHook
import os
import sys

# Add scripts directory to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../scripts'))

from fetch_stock_data import fetch_and_process_stock_data

default_args = {
    'owner': 'airflow',
    'depends_on_past': False,
    'email_on_failure': True,
    'email_on_retry': False,
    'retries': 3,
    'retry_delay': timedelta(minutes=5),
}

def create_stock_table():
    """Create stock data table if it doesn't exist"""
    create_table_sql = """
    CREATE TABLE IF NOT EXISTS stock_data (
        symbol VARCHAR(10) NOT NULL,
        timestamp TIMESTAMP NOT NULL,
        open_price DECIMAL(15, 4),
        high_price DECIMAL(15, 4),
        low_price DECIMAL(15, 4),
        close_price DECIMAL(15, 4),
        volume BIGINT,
        last_refreshed TIMESTAMP,
        time_zone VARCHAR(50),
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (symbol, timestamp)
    );
    """
    postgres_hook = PostgresHook(postgres_conn_id='postgres_default')
    postgres_hook.run(create_table_sql)

with DAG(
    'stock_data_pipeline',
    default_args=default_args,
    description='Fetch and process stock market data',
    schedule_interval=timedelta(hours=1),
    start_date=datetime(2024, 1, 1),
    catchup=False,
    tags=['stock', 'data', 'pipeline'],
) as dag:

    create_table_task = PythonOperator(
        task_id='create_stock_table',
        python_callable=create_stock_table,
    )

    fetch_data_task = PythonOperator(
        task_id='fetch_and_process_stock_data',
        python_callable=fetch_and_process_stock_data,
        op_kwargs={
            'api_key': os.getenv('ALPHA_VANTAGE_API_KEY'),
            'symbols': os.getenv('STOCK_SYMBOLS', 'AAPL').split(',')
        }
    )

    create_table_task >> fetch_data_task
