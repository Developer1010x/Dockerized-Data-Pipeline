import requests
import pandas as pd
from datetime import datetime
import os
from airflow.hooks.postgres_hook import PostgresHook
import logging
from typing import List, Dict, Any, Optional

logger = logging.getLogger(__name__)

class StockDataFetcher:
    def __init__(self, api_key: str):
        self.api_key = api_key
        self.base_url = "https://www.alphavantage.co/query"
        
    def fetch_stock_data(self, symbol: str) -> Optional[Dict[str, Any]]:
        """Fetch stock data from Alpha Vantage API"""
        try:
            params = {
                'function': 'TIME_SERIES_INTRADAY',
                'symbol': symbol,
                'interval': '60min',
                'apikey': self.api_key,
                'outputsize': 'compact'
            }
            
            response = requests.get(self.base_url, params=params, timeout=30)
            response.raise_for_status()
            
            data = response.json()
            
            # Check for API errors
            if 'Error Message' in data:
                logger.error(f"API Error for {symbol}: {data['Error Message']}")
                return None
            if 'Note' in data:
                logger.warning(f"API Rate limit note for {symbol}: {data['Note']}")
                return None
                
            return data
            
        except requests.exceptions.RequestException as e:
            logger.error(f"Request failed for {symbol}: {str(e)}")
            return None
        except ValueError as e:
            logger.error(f"JSON parsing failed for {symbol}: {str(e)}")
            return None
    
    def parse_stock_data(self, symbol: str, raw_data: Dict[str, Any]) -> List[Dict[str, Any]]:
        """Parse the JSON response and extract relevant data"""
        try:
            time_series = raw_data.get('Time Series (60min)', {})
            metadata = raw_data.get('Meta Data', {})
            
            parsed_data = []
            for timestamp, values in time_series.items():
                try:
                    data_point = {
                        'symbol': symbol,
                        'timestamp': datetime.strptime(timestamp, '%Y-%m-%d %H:%M:%S'),
                        'open_price': float(values.get('1. open', 0)),
                        'high_price': float(values.get('2. high', 0)),
                        'low_price': float(values.get('3. low', 0)),
                        'close_price': float(values.get('4. close', 0)),
                        'volume': int(values.get('5. volume', 0)),
                        'last_refreshed': metadata.get('3. Last Refreshed'),
                        'time_zone': metadata.get('5. Time Zone')
                    }
                    parsed_data.append(data_point)
                except (ValueError, TypeError) as e:
                    logger.warning(f"Failed to parse data point for {symbol} at {timestamp}: {str(e)}")
                    continue
            
            return parsed_data
            
        except Exception as e:
            logger.error(f"Failed to parse data for {symbol}: {str(e)}")
            return []
    
    def store_data(self, data: List[Dict[str, Any]]) -> bool:
        """Store parsed data in PostgreSQL database"""
        if not data:
            return False
            
        try:
            postgres_hook = PostgresHook(postgres_conn_id='postgres_default')
            conn = postgres_hook.get_conn()
            cursor = conn.cursor()
            
            insert_sql = """
            INSERT INTO stock_data 
            (symbol, timestamp, open_price, high_price, low_price, close_price, volume, last_refreshed, time_zone)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
            ON CONFLICT (symbol, timestamp) 
            DO UPDATE SET
                open_price = EXCLUDED.open_price,
                high_price = EXCLUDED.high_price,
                low_price = EXCLUDED.low_price,
                close_price = EXCLUDED.close_price,
                volume = EXCLUDED.volume,
                last_refreshed = EXCLUDED.last_refreshed
            """
            
            for record in data:
                cursor.execute(insert_sql, (
                    record['symbol'],
                    record['timestamp'],
                    record['open_price'],
                    record['high_price'],
                    record['low_price'],
                    record['close_price'],
                    record['volume'],
                    record['last_refreshed'],
                    record['time_zone']
                ))
            
            conn.commit()
            cursor.close()
            conn.close()
            
            logger.info(f"Successfully stored {len(data)} records")
            return True
            
        except Exception as e:
            logger.error(f"Failed to store data: {str(e)}")
            return False

def fetch_and_process_stock_data(api_key: str, symbols: List[str]) -> None:
    """Main function to fetch, parse and store stock data"""
    if not api_key or api_key == 'your_alpha_vantage_api_key_here':
        logger.error("API key not configured. Please set ALPHA_VANTAGE_API_KEY environment variable.")
        return
    
    fetcher = StockDataFetcher(api_key)
    
    successful_symbols = 0
    total_records = 0
    
    for symbol in symbols:
        symbol = symbol.strip().upper()
        if not symbol:
            continue
            
        logger.info(f"Processing symbol: {symbol}")
        
        # Fetch data
        raw_data = fetcher.fetch_stock_data(symbol)
        if not raw_data:
            logger.warning(f"No data retrieved for {symbol}")
            continue
        
        # Parse data
        parsed_data = fetcher.parse_stock_data(symbol, raw_data)
        if not parsed_data:
            logger.warning(f"No valid data parsed for {symbol}")
            continue
        
        # Store data
        if fetcher.store_data(parsed_data):
            successful_symbols += 1
            total_records += len(parsed_data)
            logger.info(f"Successfully processed {len(parsed_data)} records for {symbol}")
        else:
            logger.error(f"Failed to store data for {symbol}")
    
    logger.info(f"Pipeline completed. Processed {successful_symbols}/{len(symbols)} symbols with {total_records} total records")
