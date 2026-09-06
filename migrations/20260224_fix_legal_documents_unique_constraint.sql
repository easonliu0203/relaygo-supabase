-- ============================================================
-- 修復 legal_documents 的 UNIQUE 約束
-- 從 UNIQUE(doc_key) 改為 UNIQUE(role, doc_key)
-- 讓同一 doc_key 可以為不同角色各建一筆
-- ============================================================

-- 移除舊的 UNIQUE 約束（doc_key 單獨）
ALTER TABLE legal_documents
  DROP CONSTRAINT IF EXISTS legal_documents_doc_key_key;

-- 新增複合 UNIQUE 約束（role + doc_key）
ALTER TABLE legal_documents
  ADD CONSTRAINT legal_documents_role_doc_key_key UNIQUE (role, doc_key);
