# Stock Market Data Pipeline

A robust, Dockerized data pipeline that automatically fetches stock market data from Alpha Vantage API and stores it in PostgreSQL using Apache Airflow for orchestration.

## 🏗️ Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Alpha Vantage │    │     Apache       │    │   PostgreSQL    │
│      API        │◄──►│     Airflow      │◄──►│    Database     │
│                 │    │                  │    │                 │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                              │
                       ┌──────▼──────┐
                       │    Redis    │
                       │  (Celery)   │
                       └─────────────┘
```

## ✨ Features

- **🔄 Automated Data Fetching**: Scheduled data retrieval every 4 hours
- **🛡️ Robust Error Handling**: Comprehensive retry logic and error management
- **📊 Data Quality Checks**: Automated validation of fetched data
- **🐳 Full Dockerization**: One-command deployment with Docker Compose
- **📈 Scalable Architecture**: Celery-based task execution with Redis
- **🔍 Monitoring**: Built-in logging and pipeline execution tracking
- **🗄️ Database Management**: Automated table creation and data cleanup
- **⚡ Rate Limit Handling**: Respects API rate limits with intelligent retry logic

## 📋 Prerequisites

- Docker Engine 20.10+
- Docker Compose 2.0+
- Alpha Vantage API Key ([Get Free Key](https://www.alphavantage.co/support/#api-key))
- At least 4GB RAM and 2GB disk space

## 🚀 Quick Start

### 1. Clone and Setup

```bash
# Create project directory
mkdir stock-data-pipeline && cd stock-data-pipeline

# Create required directories
mkdir -p dags logs plugins scripts init-db config

# Copy all provided files to their respective directories
```

### 2. Configure Environment

Copy the `.env.example` to `.env` and configure:

```bash
cp .env .env.local
```

Edit `.env.local` with your settings:

```bash
# REQUIRED: Get your free API key from https://www.alphavantage.co/support/#api-key
ALPHA_VANTAGE_API_KEY=your_actual_api_key_here

# Database Configuration (you can keep defaults)
POSTGRES_DB=stockdata
POSTGRES_USER=airflow
POSTGRES_PASSWORD=airflow123

# Airflow Web UI Credentials
_AIRFLOW_WWW_USER_USERNAME=admin
_AIRFLOW_WWW_USER_PASSWORD=admin123

# Stock symbols to track (comma-separated)
STOCK_SYMBOLS=AAPL,GOOGL,MSFT,AMZN,TSLA
```

### 3. Deploy the Pipeline

```bash
# Build and start all services
docker-compose --env-file .env.local up -d

# Wait for services to be ready (this may take 2-3 minutes)
docker-compose --env-file .env.local logs -f airflow-init

# Check service health
docker-compose --env-file .env.local ps
```

### 4. Access the Dashboard

- **Airflow Web UI**: http://localhost:8080
  - Username: `admin` (or your configured username)
  - Password: `admin123` (or your configured password)
- **Flower (Celery Monitor)**: http://localhost:5555

## 🎯 Pipeline Overview

### DAG: `stock_data_pipeline`

The main pipeline consists of 6 tasks that run every 4 hours:

1. **🔍 API Connectivity Check**: Validates Alpha Vantage API access
2. **🗄️ Database Validation**: Ensures database tables and structure are correct
3. **📥 Fetch & Store Data**: Downloads and stores stock data for all configured symbols
4. **✅ Data Quality Check**: Validates data integrity and completeness
5. **🧹 Cleanup**: Removes old logs and data beyond retention period
6. **📧 Notification**: Sends execution summary and alerts

### Monitored Stock Data

By default, the pipeline tracks these symbols:
- **AAPL** (Apple Inc.)
- **GOOGL** (Alphabet Inc.)
- **MSFT** (Microsoft Corporation)
- **AMZN** (Amazon.com Inc.)
- **TSLA** (Tesla Inc.)

You can modify the `STOCK_SYMBOLS` environment variable to track different stocks.

## 📊 Database Schema

### Tables Created

1. **`stock_data`**: Main table storing historical stock prices
   - `symbol`, `timestamp`, `open_price`, `high_price`, `low_price`, `close_price`, `volume`
   
2. **`stock_metadata`**: Tracks pipeline execution metadata per symbol
   - `symbol`, `last_updated`, `last_fetch_success`, `error_message`, `total_records`
   
3. **`pipeline_logs`**: Detailed execution logs
   - `dag_id`, `task_id`, `execution_date`, `status`, `duration`, `error_message`

## 🔧 Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `ALPHA_VANTAGE_API_KEY` | Your Alpha Vantage API key | **Required** |
| `STOCK_SYMBOLS` | Comma-separated stock symbols | `AAPL,GOOGL,MSFT,AMZN,TSLA` |
| `POSTGRES_DB` | Database name | `stockdata` |
| `POSTGRES_USER` | Database username | `airflow` |
| `POSTGRES_PASSWORD` | Database password | `airflow123` |
| `AIRFLOW_FERNET_KEY` | Airflow encryption key | Auto-generated |

### Customizing Stock Symbols

To track different stocks, update the `STOCK_SYMBOLS` environment variable:

```bash
# In your .env file
STOCK_SYMBOLS=NVDA,AMD,INTC,CRM,NFLX
```

### Adjusting Schedule

To change the pipeline schedule, edit `dags/stock_data_pipeline.py`:

```python
# Current: Every 4 hours
schedule_interval='0 */4 * * *'

# Daily at 9 AM
schedule_interval='0 9 * * *'

# Every hour during market hours (9 AM - 4 PM, Mon-Fri)
schedule_interval='0 9-16 * * 1-5'
```

## 🚨 Error Handling

The pipeline includes comprehensive error handling:

### API Errors
- **Rate Limiting**: Automatic backoff and retry
- **Invalid Symbols**: Graceful handling with logging
- **Network Issues**: Exponential backoff with 3 retry attempts
- **API Key Issues**: Clear error messages and validation

### Database Errors
- **Connection Failures**: Automatic retry with connection pooling
- **Data Conflicts**: UPSERT operations to handle duplicates
- **Transaction Management**: Rollback on errors to maintain consistency

### Pipeline Resilience
- **Individual Task Failures**: Pipeline continues for other symbols
- **Partial Success Handling**: Tracks and reports which symbols succeeded
- **Data Quality Issues**: Non-blocking warnings with detailed reporting

## 📈 Monitoring

### Airflow Dashboard

1. Go to http://localhost:8080
2. Click on `stock_data_pipeline` DAG
3. Monitor task execution, logs, and retry attempts
4. View detailed logs for each task

### Database Queries

Connect to PostgreSQL to query data:

```bash
# Connect to database
docker-compose exec postgres psql -U airflow -d stockdata

# Sample queries
SELECT symbol, COUNT(*) as records, MAX(timestamp) as latest 
FROM stock_data 
GROUP BY symbol;

SELECT * FROM pipeline_logs 
ORDER BY created_at DESC 
LIMIT 10;
```

### Health Checks

The pipeline includes built-in health checks accessible via the database:

```sql
-- Check recent pipeline executions
SELECT dag_id, status, COUNT(*) 
FROM pipeline_logs 
WHERE created_at >= NOW() - INTERVAL '1 day' 
GROUP BY dag_id, status;

-- Check data freshness
SELECT symbol, MAX(timestamp) as latest_data,
       NOW() - MAX(timestamp) as age
FROM stock_data 
GROUP BY symbol;
```

## 🛠️ Troubleshooting

### Common Issues

#### 1. Pipeline Not Starting
```bash
# Check all services are running
docker-compose ps

# Check Airflow initialization
docker-compose logs airflow-init

# Restart if needed
docker-compose restart
```

#### 2. API Key Issues
```bash
# Verify API key is set
docker-compose exec airflow-webserver printenv | grep ALPHA_VANTAGE

# Test API manually
curl "https://www.alphavantage.co/query?function=GLOBAL_QUOTE&symbol=AAPL&apikey=YOUR_KEY"
```

#### 3. Database Connection Issues
```bash
# Check database logs
docker-compose logs postgres

# Test database connection
docker-compose exec postgres psql -U airflow -d stockdata -c "SELECT 1;"
```

#### 4. Permission Issues
```bash
# Fix Airflow permissions
sudo chown -R 50000:0 logs/ dags/ plugins/

# Or set correct ownership
export AIRFLOW_UID=$(id -u)
docker-compose up
```

### Logs and Debugging

```bash
# View all logs
docker-compose logs

# View specific service logs
docker-compose logs airflow-scheduler
docker-compose logs airflow-worker

# Follow logs in real-time
docker-compose logs -f stock_data_pipeline

# View DAG logs in Airflow UI
# Go to DAG -> Click on task -> View logs
```

## 🔄 Maintenance

### Daily Operations

The pipeline is designed to be low-maintenance:

- **Automatic data cleanup**: Removes data older than 1 year
- **Log rotation**: Keeps pipeline logs for 30 days
- **Health monitoring**: Built-in data quality checks
- **Error recovery**: Automatic retries and graceful degradation

### Manual Maintenance

```bash
# Update stock symbols
docker-compose exec airflow-webserver airflow dags trigger stock_data_pipeline

# Force refresh all data
docker-compose exec airflow-webserver airflow tasks clear stock_data_pipeline

# Backup database
docker-compose exec postgres pg_dump -U airflow stockdata > backup_$(date +%Y%m%d).sql

# View pipeline statistics
docker-compose exec postgres psql -U airflow -d stockdata -c "
  SELECT 
    symbol, 
    COUNT(*) as total_records, 
    MIN(timestamp) as oldest_data,
    MAX(timestamp) as newest_data 
  FROM stock_data 
  GROUP BY symbol;"
```

## 🚀 Scaling

### Horizontal Scaling

To handle more stock symbols or higher frequency:

1. **Add more Celery workers**:
   ```yaml
   # In docker-compose.yml
   airflow-worker-2:
     build:
       context: .
       dockerfile: Dockerfile.airflow
     command: celery worker
     # ... same config as airflow-worker
   ```

2. **Increase worker concurrency**:
   ```bash
   # In environment variables
   AIRFLOW__CELERY__WORKER_CONCURRENCY=8
   ```

3. **Optimize database**:
   ```bash
   # Add more memory to PostgreSQL
   POSTGRES_SHARED_BUFFERS=256MB
   POSTGRES_EFFECTIVE_CACHE_SIZE=1GB
   ```

### Performance Optimization

1. **Batch processing**: The pipeline already uses bulk inserts
2. **Connection pooling**: Implemented in DatabaseManager
3. **Rate limiting**: Respects API limits automatically
4. **Parallel execution**: Celery workers process symbols in parallel

## 📚 API Reference

### Alpha Vantage Integration

The pipeline uses these Alpha Vantage endpoints:

- **Daily Time Series**: `TIME_SERIES_DAILY`
  - Provides OHLCV data for each trading day
  - Used for historical analysis and daily summaries

- **Global Quote**: `GLOBAL_QUOTE`
  - Real-time price and basic stats
  - Used for health checks and validation

### Rate Limits

- **Free Tier**: 5 requests per minute, 500 requests per day
- **Pipeline Handling**: 12-second delay between requests
- **Retry Logic**: Exponential backoff on rate limit hits

## 🔐 Security

### Secrets Management

- All sensitive data stored in environment variables
- Database credentials isolated in Docker network
- API keys never logged or exposed in output
- Fernet key encryption for Airflow connections

### Network Security

- Services communicate via Docker internal network
- Only necessary ports exposed to host
- Database not directly accessible from outside

### Best Practices

- Regular credential rotation recommended
- Monitor API key usage in Alpha Vantage dashboard
- Use strong passwords for production deployments
- Consider using Docker secrets for production

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 🆘 Support

If you encounter any issues:

1. Check the [Troubleshooting](#-troubleshooting) section
2. Review logs using the provided commands
3. Open an issue with detailed logs and configuration

## 🗺️ Roadmap

Future enhancements planned:

- [ ] Integration with additional data sources (Yahoo Finance, IEX Cloud)
- [ ] Real-time streaming data support
- [ ] Advanced analytics and alerting
- [ ] Web dashboard for monitoring
- [ ] Machine learning predictions
- [ ] Export capabilities (CSV, JSON, Parquet)
- [ ] Enhanced data visualization
- [ ] Multi-exchange support

---

**Happy Data Engineering! 📈✨**