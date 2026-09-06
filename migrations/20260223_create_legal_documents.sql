-- ============================================================
-- 新增 legal_documents 表
-- 用於存放隱私權政策、合作條約、推廣夥伴協議等法律文件
-- 支援多語言 (i18n)、富文本 HTML 內容、版本追蹤
-- ============================================================

CREATE TABLE IF NOT EXISTS legal_documents (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  role             TEXT NOT NULL CHECK (role IN ('customer', 'driver', 'all')),
  doc_key          TEXT NOT NULL,
  title            TEXT NOT NULL,
  title_i18n       JSONB DEFAULT '{}'::jsonb,
  content          TEXT NOT NULL DEFAULT '',
  content_i18n     JSONB DEFAULT '{}'::jsonb,
  is_active        BOOLEAN NOT NULL DEFAULT true,
  version          INTEGER NOT NULL DEFAULT 1,
  sort_order       INTEGER DEFAULT 0,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),

  UNIQUE (role, doc_key)
);

-- 索引
CREATE INDEX IF NOT EXISTS idx_legal_docs_role
  ON legal_documents (role, is_active);

CREATE INDEX IF NOT EXISTS idx_legal_docs_doc_key
  ON legal_documents (doc_key);

-- updated_at 自動更新觸發器
CREATE OR REPLACE FUNCTION update_legal_documents_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_legal_documents_updated_at
  BEFORE UPDATE ON legal_documents
  FOR EACH ROW EXECUTE FUNCTION update_legal_documents_updated_at();

-- version 自動遞增觸發器（每次更新 content 或 content_i18n 時 +1）
CREATE OR REPLACE FUNCTION increment_legal_document_version()
RETURNS TRIGGER AS $$
BEGIN
  IF OLD.content IS DISTINCT FROM NEW.content
     OR OLD.content_i18n IS DISTINCT FROM NEW.content_i18n THEN
    NEW.version = OLD.version + 1;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_legal_documents_version
  BEFORE UPDATE ON legal_documents
  FOR EACH ROW EXECUTE FUNCTION increment_legal_document_version();

-- ============================================================
-- 種子資料
-- ============================================================
INSERT INTO legal_documents (role, doc_key, title, title_i18n, sort_order)
VALUES
  ('customer', 'privacy_policy_customer', '客戶隱私權政策',
   '{"zh-TW": "客戶隱私權政策", "en": "Customer Privacy Policy"}'::jsonb, 1),

  ('driver', 'privacy_policy_driver', '司機隱私權政策',
   '{"zh-TW": "司機隱私權政策", "en": "Driver Privacy Policy"}'::jsonb, 2),

  ('driver', 'partnership_agreement', '合作條約',
   '{"zh-TW": "合作條約", "en": "Partnership Agreement"}'::jsonb, 3),

  ('driver', 'affiliate_agreement', '推廣夥伴合作協議',
   '{"zh-TW": "推廣夥伴合作協議", "en": "Affiliate Partnership Agreement"}'::jsonb, 4),

  ('customer', 'cancellation_policy', '取消政策公告',
   '{"zh-TW": "取消政策公告", "en": "Cancellation Policy"}'::jsonb, 5)

ON CONFLICT (doc_key) DO NOTHING;
