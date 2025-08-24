# Stock Data Pipeline Makefile
# Provides convenient commands for managing the pipeline

.PHONY: help build up down restart logs clean health test backup

# Default target
help: ## Show this help message
	@echo "Stock Data Pipeline - Available Commands:"
	@echo "=========================================="
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# Setup and Environment
setup: ## Create required directories and set permissions
	@echo "🏗️ Setting up project structure..."
	mkdir -p dags logs plugins scripts init-db config
	chmod 755 dags logs plugins scripts init-db config
	@if [ ! -f .env ]; then \
		echo "📝 Creating .env file from template..."; \
		cp .env .env; \
		echo "⚠️  Please edit .env file with your Alpha Vantage API key"; \
	fi
	@echo "✅ Setup complete!"

# Docker operations
build: ## Build all Docker images
	@echo "🐳 Building Docker images..."
	docker-compose build --no-cache

up: setup ## Start all services
	@echo "🚀 Starting all services..."
	docker-compose --env-file .env up -d
	@echo "⏳ Waiting for services to initialize..."
	@sleep 30
	@make health

down: ## Stop all services
	@echo "⏹️ Stopping all services..."
	docker-compose down

restart: down up ## Restart all services

# Monitoring and Logs
logs: ## Show logs from all services
	docker-compose logs -f

logs-airflow: ## Show Airflow scheduler logs
	docker-compose logs -f airflow-scheduler

logs-worker: ## Show Airflow worker logs
	docker-compose logs -f airflow-worker

logs-db: ## Show database logs
	docker-compose logs -f postgres

status: ## Show status of all containers
	@echo "📊 Container Status:"
	@docker-compose ps

health: ## Check health of all services
	@echo "🏥 Health Check:"
	@echo "=================="
	@echo "🐳 Docker containers:"
	@docker-compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"
	@echo ""
	@echo "🌐 Service endpoints:"
	@echo "  • Airflow Web UI: http://localhost:8080"
	@echo "  • Flower Monitor: http://localhost:5555"
	@echo "  • PostgreSQL: localhost:5432"
	@echo ""
	@echo "🔍 Quick connectivity test:"
	@docker-compose exec -T postgres pg_isready -U airflow || echo "❌ Database not ready"
	@curl -f http://localhost:8080/health 2>/dev/null && echo "✅ Airflow webserver healthy" || echo "❌ Airflow webserver not responding"

# Pipeline operations
trigger: ## Manually trigger the stock data pipeline
	@echo "🚀 Triggering stock data pipeline..."
	docker-compose exec airflow-webserver airflow dags trigger stock_data_pipeline

pause: ## Pause the stock data pipeline
	@echo "⏸️ Pausing stock data pipeline..."
	docker-compose exec airflow-webserver airflow dags pause stock_data_pipeline

unpause: ## Unpause the stock data pipeline
	@echo "▶️ Unpausing stock data pipeline..."
	docker-compose exec airflow-webserver airflow dags unpause stock_data_pipeline

clear: ## Clear pipeline task history
	@echo "🧹 Clearing pipeline task history..."
	docker-compose exec airflow-webserver airflow tasks clear stock_data_pipeline

# Database operations
db-connect: ## Connect to PostgreSQL database
	@echo "🗄️ Connecting to database..."
	docker-compose exec postgres psql -U airflow -d stockdata

db-status: ## Show database status and table info
	@echo "📊 Database Status:"
	@docker-compose exec postgres psql -U airflow -d stockdata -c "\dt"
	@echo ""
	@echo "📈 Stock data summary:"
	@docker-compose exec postgres psql -U airflow -d stockdata -c "SELECT symbol, COUNT(*) as records, MAX(timestamp) as latest FROM stock_data GROUP BY symbol ORDER BY symbol;"

backup: ## Backup database
	@echo "💾 Creating database backup..."
	@mkdir -p backups
	docker-compose exec postgres pg_dump -U airflow stockdata > backups/stockdata_backup_$(shell date +%Y%m%d_%H%M%S).sql
	@echo "✅ Backup created in backups/ directory"

restore: ## Restore database from backup (specify BACKUP_FILE=path)
	@if [ -z "$(BACKUP_FILE)" ]; then \
		echo "❌ Please specify BACKUP_FILE=path/to/backup.sql"; \
		exit 1; \
	fi
	@echo "🔄 Restoring database from $(BACKUP_FILE)..."
	docker-compose exec -T postgres psql -U airflow -d stockdata < $(BACKUP_FILE)
	@echo "✅ Database restored"

# Testing and validation
test: ## Run basic pipeline tests
	@echo "🧪 Running pipeline tests..."
	@echo "1. Testing API connectivity..."
	@docker-compose exec airflow-webserver python -c "
import os, requests
api_key = os.getenv('ALPHA_VANTAGE_API_KEY')
if not api_key or api_key == 'your_alpha_vantage_api_key_here':
    print('❌ API key not configured')
    exit(1)
response = requests.get(f'https://www.alphavantage.co/query?function=GLOBAL_QUOTE&symbol=AAPL&apikey={api_key}')
if response.status_code == 200 and 'Global Quote' in response.json():
    print('✅ API connectivity test passed')
else:
    print('❌ API connectivity test failed')
    exit(1)
"
	@echo "2. Testing database connection..."
	@docker-compose exec postgres psql -U airflow -d stockdata -c "SELECT 1;" > /dev/null && echo "✅ Database connection test passed" || echo "❌ Database connection test failed"
	@echo "3. Testing table structure..."
	@docker-compose exec postgres psql -U airflow -d stockdata -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_name IN ('stock_data', 'stock_metadata', 'pipeline_logs');" | grep -q "3" && echo "✅ Database tables test passed" || echo "❌ Database tables test failed"
	@echo "🎉 Basic tests completed!"

validate-env: ## Validate environment configuration
	@echo "🔍 Validating environment configuration..."
	@if [ ! -f .env ]; then echo "❌ .env file not found"; exit 1; fi
	@source .env && \
	if [ -z "$$ALPHA_VANTAGE_API_KEY" ] || [ "$$ALPHA_VANTAGE_API_KEY" = "your_alpha_vantage_api_key_here" ]; then \
		echo "❌ ALPHA_VANTAGE_API_KEY not configured"; \
		exit 1; \
	else \
		echo "✅ API key configured"; \
	fi
	@echo "✅ Environment validation passed"

# Development and debugging
dev-logs: ## Show development logs with filtering
	docker-compose logs -f | grep -E "(ERROR|WARN|Stock|Pipeline|✅|❌|🔍)"

shell-airflow: ## Open shell in Airflow webserver container
	docker-compose exec airflow-webserver bash

shell-db: ## Open shell in PostgreSQL container
	docker-compose exec postgres bash

debug: ## Show debug information
	@echo "🐛 Debug Information:"
	@echo "===================="
	@echo "📁 Current directory: $(PWD)"
	@echo "📋 Environment file:"
	@if [ -f .env ]; then echo "✅ .env file exists"; else echo "❌ .env file missing"; fi
	@echo "🐳 Docker info:"
	@docker --version
	@docker-compose --version
	@echo "📊 Container status:"
	@docker-compose ps
	@echo "💾 Disk usage:"
	@docker system df

# Cleanup operations
clean: ## Remove all containers and volumes
	@echo "🧹 Cleaning up containers and volumes..."
	docker-compose down -v --remove-orphans
	docker-compose rm -f

clean-all: clean ## Remove everything including images
	@echo "🗑️ Removing all images..."
	docker-compose down -v --remove-orphans --rmi all
	docker system prune -f

reset: clean-all setup up ## Complete reset - remove everything and start fresh

# Production operations
prod-check: ## Check if ready for production
	@echo "🏭 Production Readiness Check:"
	@echo "=============================="
	@echo "1. Environment configuration:"
	@make validate-env
	@echo "2. Security check:"
	@source .env && \
	if [ "$$_AIRFLOW_WWW_USER_PASSWORD" = "admin123" ]; then \
		echo "⚠️ Using default admin password - change for production"; \
	else \
		echo "✅ Custom admin password configured"; \
	fi
	@echo "3. Resource check:"
	@echo "💾 Available memory: $$(free -h | grep '^Mem:' | awk '{print $$7}')"
	@echo "💿 Available disk: $$(df -h . | tail -1 | awk '{print $$4}')"
	@echo "🔍 Recommended: 4GB RAM, 2GB disk space"

monitor: ## Start monitoring (shows key metrics)
	@echo "📊 Starting pipeline monitoring..."
	@echo "Press Ctrl+C to stop"
	@while true; do \
		clear; \
		echo "📈 Stock Data Pipeline Monitor - $$(date)"; \
		echo "==========================================="; \
		echo "🐳 Container Status:"; \
		docker-compose ps --format "table {{.Name}}\t{{.Status}}"; \
		echo ""; \
		echo "📊 Latest Pipeline Execution:"; \
		docker-compose exec -T postgres psql -U airflow -d stockdata -c "SELECT dag_id, status, records_processed, created_at FROM pipeline_logs ORDER BY created_at DESC LIMIT 5;" 2>/dev/null || echo "Database not ready"; \
		echo ""; \
		echo "📈 Stock Data Summary:"; \
		docker-compose exec -T postgres psql -U airflow -d stockdata -c "SELECT symbol, COUNT(*) as records, MAX(timestamp) as latest FROM stock_data GROUP BY symbol ORDER BY symbol;" 2>/dev/null || echo "No data available yet"; \
		sleep 30; \
	done

# Quick start for new users
quickstart: ## Complete setup for new users
	@echo "🚀 Quick Start Setup"
	@echo "==================="
	@echo "1. Setting up project..."
	@make setup
	@echo ""
	@echo "2. Please edit .env file with your Alpha Vantage API key:"
	@echo "   ALPHA_VANTAGE_API_KEY=your_actual_api_key_here"
	@echo ""
	@read -p "Press Enter after updating .env file..."
	@echo "3. Validating configuration..."
	@make validate-env
	@echo "4. Starting services..."
	@make up
	@echo "5. Running tests..."
	@make test
	@echo ""
	@echo "🎉 Quick start complete!"
	@echo "📱 Access Airflow at: http://localhost:8080"
	@echo "🌸 Access Flower at: http://localhost:5555"
	@echo "📊 Monitor with: make monitor"
