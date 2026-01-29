-- Migration: Add dropoff coordinates to bookings table
-- Created: 2026-01-29
-- Purpose: Store dropoff location coordinates for navigation functionality
-- Issue: Previously only pickup coordinates were stored, dropoff used default values

-- Add dropoff_latitude column
ALTER TABLE bookings 
ADD COLUMN IF NOT EXISTS dropoff_latitude DECIMAL(10, 8);

-- Add dropoff_longitude column
ALTER TABLE bookings 
ADD COLUMN IF NOT EXISTS dropoff_longitude DECIMAL(11, 8);

-- Add comments
COMMENT ON COLUMN bookings.dropoff_latitude IS '下車地點緯度 (精度: 8位小數)';
COMMENT ON COLUMN bookings.dropoff_longitude IS '下車地點經度 (精度: 8位小數)';

-- Note: DECIMAL(10, 8) for latitude allows values from -90.00000000 to 90.00000000
-- Note: DECIMAL(11, 8) for longitude allows values from -180.00000000 to 180.00000000

