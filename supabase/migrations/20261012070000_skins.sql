-- 랜딩 스킨 확장 — 업종·설정(폰트/토큰)·에셋 매핑.
alter table fl_skins add column if not exists industry text;
alter table fl_skins add column if not exists config jsonb not null default '{}'::jsonb;  -- { fonts:[], vars:{} }
alter table fl_skins add column if not exists assets jsonb not null default '[]'::jsonb;   -- [{path,url}]
