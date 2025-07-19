-- Initialize Energrid Database Schema
CREATE DATABASE IF NOT EXISTS energrid;
USE energrid;

-- Users table
CREATE TABLE IF NOT EXISTS users (
    id INT PRIMARY KEY AUTO_INCREMENT,
    wallet_address VARCHAR(42) UNIQUE NOT NULL,
    email VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_wallet_address (wallet_address)
);

-- Energy transactions table
CREATE TABLE IF NOT EXISTS energy_transactions (
    id INT PRIMARY KEY AUTO_INCREMENT,
    tx_hash VARCHAR(66) UNIQUE NOT NULL,
    from_address VARCHAR(42) NOT NULL,
    to_address VARCHAR(42) NOT NULL,
    amount DECIMAL(18,8) NOT NULL,
    token_type ENUM('kWh', 'CEL') NOT NULL,
    block_number BIGINT,
    gas_used INT,
    gas_price DECIMAL(18,8),
    status ENUM('pending', 'confirmed', 'failed') DEFAULT 'pending',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_tx_hash (tx_hash),
    INDEX idx_from_address (from_address),
    INDEX idx_to_address (to_address),
    INDEX idx_status (status)
);

-- IoT meter readings table
CREATE TABLE IF NOT EXISTS meter_readings (
    id INT PRIMARY KEY AUTO_INCREMENT,
    meter_id VARCHAR(100) NOT NULL,
    user_address VARCHAR(42) NOT NULL,
    energy_consumed DECIMAL(10,3) NOT NULL,
    energy_produced DECIMAL(10,3) DEFAULT 0,
    timestamp TIMESTAMP NOT NULL,
    processed BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_meter_id (meter_id),
    INDEX idx_user_address (user_address),
    INDEX idx_timestamp (timestamp),
    INDEX idx_processed (processed)
);

-- Trading orders table
CREATE TABLE IF NOT EXISTS trading_orders (
    id INT PRIMARY KEY AUTO_INCREMENT,
    user_address VARCHAR(42) NOT NULL,
    order_type ENUM('buy', 'sell') NOT NULL,
    energy_amount DECIMAL(10,3) NOT NULL,
    price_per_kwh DECIMAL(10,6) NOT NULL,
    total_price DECIMAL(18,8) NOT NULL,
    status ENUM('open', 'filled', 'cancelled', 'expired') DEFAULT 'open',
    expires_at TIMESTAMP,
    filled_at TIMESTAMP NULL,
    tx_hash VARCHAR(66) NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_user_address (user_address),
    INDEX idx_status (status),
    INDEX idx_order_type (order_type)
);

-- System configuration table
CREATE TABLE IF NOT EXISTS system_config (
    config_key VARCHAR(100) PRIMARY KEY,
    config_value TEXT,
    description TEXT,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- Insert default configuration
INSERT IGNORE INTO system_config (config_key, config_value, description) VALUES
('kwh_token_address', '0x0000000000000000000000000000000000000000', 'kWh Token Contract Address'),
('cel_token_address', '0x0000000000000000000000000000000000000000', 'CEL Token Contract Address'),
('energy_1155_address', '0x0000000000000000000000000000000000000000', 'Energy1155 Contract Address'),
('min_trading_amount', '0.1', 'Minimum energy amount for trading (kWh)'),
('max_trading_amount', '1000.0', 'Maximum energy amount for trading (kWh)'),
('trading_fee_percentage', '0.5', 'Trading fee percentage'),
('network_name', 'sepolia', 'Current blockchain network'),
('block_confirmation_count', '12', 'Number of block confirmations required');
