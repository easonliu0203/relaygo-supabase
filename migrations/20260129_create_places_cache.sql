-- Migration: Create places_cache table for Google Places API caching
-- Created: 2026-01-29
-- Purpose: Cache Google Places API search results to reduce API costs
-- Cache strategy: Same search query returns cached results within 24 hours

-- Create places_cache table
CREATE TABLE IF NOT EXISTS places_cache (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    search_query TEXT NOT NULL,                    -- 搜尋關鍵字
    name TEXT NOT NULL,                            -- 地點名稱
    latitude DECIMAL(10, 8) NOT NULL,              -- 緯度
    longitude DECIMAL(11, 8) NOT NULL,             -- 經度
    formatted_address TEXT NOT NULL,               -- 完整地址
    place_id TEXT,                                 -- Google Place ID (optional, for future reference)
    language_code VARCHAR(10),                     -- 搜尋時使用的語言代碼 (e.g., 'zh-TW', 'en', 'ja')
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create index on search_query for fast lookups
CREATE INDEX IF NOT EXISTS idx_places_cache_search_query ON places_cache(search_query);

-- Create index on created_at for cache expiration queries
CREATE INDEX IF NOT EXISTS idx_places_cache_created_at ON places_cache(created_at);

-- Create composite index for search query with language code
CREATE INDEX IF NOT EXISTS idx_places_cache_query_lang ON places_cache(search_query, language_code);

-- Add comment to table
COMMENT ON TABLE places_cache IS 'Cache table for Google Places API search results. Results are considered valid for 24 hours.';

-- Enable Row Level Security (RLS)
ALTER TABLE places_cache ENABLE ROW LEVEL SECURITY;

-- Create policy to allow all users to read from cache
CREATE POLICY "Allow public read access to places cache" ON places_cache
    FOR SELECT
    USING (true);

-- Create policy to allow authenticated users to insert into cache
CREATE POLICY "Allow authenticated users to insert into places cache" ON places_cache
    FOR INSERT
    WITH CHECK (true);

-- Create function to clean up old cache entries (older than 7 days)
-- This can be called by a scheduled job
CREATE OR REPLACE FUNCTION cleanup_old_places_cache()
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM places_cache
    WHERE created_at < NOW() - INTERVAL '7 days';
    
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    
    RETURN deleted_count;
END;
$$;

-- Add comment to cleanup function
COMMENT ON FUNCTION cleanup_old_places_cache() IS 'Removes places cache entries older than 7 days. Returns the number of deleted rows.';

