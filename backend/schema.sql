-- ============================================================
-- GUTI — Esquema relacional (Supabase / PostgreSQL)
-- ============================================================
-- Ejecutar completo en Supabase → SQL Editor. Es idempotente:
-- se puede correr varias veces sin perder datos (usa IF NOT EXISTS).
--
-- Relaciones (integridad referencial):
--   emails 1─N email_drafts        (borrador que responde a un correo)
--   emails 1─N tasks               (tarea originada por un correo)
--   credit_cards 1─N transactions  (medio de pago de la transacción)
--   transactions 1─N bank_notifications (texto crudo del webhook → transacción)
--   savings_goals 1─N goal_deposits (historial de abonos a una meta)
-- ============================================================


-- ------------------------------------------------------------
-- AGENTE DE SECRETARÍA
-- ------------------------------------------------------------

create table if not exists public.emails (
    id          text primary key default gen_random_uuid()::text,
    sender      text not null,
    sender_name text,
    recipient   text,
    subject     text not null,
    snippet     text,
    body        text,
    date        timestamptz not null default now(),
    is_read     boolean not null default false,
    is_urgent   boolean not null default false
);

create table if not exists public.email_drafts (
    id                text primary key default gen_random_uuid()::text,
    reply_to_email_id text references public.emails(id) on delete set null,
    recipient         text not null,
    subject           text not null,
    body              text not null,
    status            text not null default 'borrador'
                      check (status in ('borrador', 'enviado')),
    created_at        timestamptz not null default now()
);

-- La tabla tasks ya existe; se crea solo si falta y se amplía con prioridad/estado.
create table if not exists public.tasks (
    id          text primary key,
    title       text not null,
    description text,
    due_date    timestamptz,
    completed   boolean not null default false,
    created_at  timestamptz not null default now()
);

alter table public.tasks add column if not exists priority text not null default 'media';
alter table public.tasks add column if not exists status   text not null default 'pendiente';
alter table public.tasks add column if not exists category text not null default 'personal';
alter table public.tasks add column if not exists source_email_id text
    references public.emails(id) on delete set null;

do $$ begin
    alter table public.tasks add constraint tasks_priority_check
        check (priority in ('alta', 'media', 'baja'));
exception when duplicate_object then null; end $$;

do $$ begin
    alter table public.tasks add constraint tasks_category_check
        check (category in ('universidad', 'trabajo', 'personal', 'proyecto'));
exception when duplicate_object then null; end $$;

do $$ begin
    alter table public.tasks add constraint tasks_status_check
        check (status in ('pendiente', 'en_progreso', 'completado'));
exception when duplicate_object then null; end $$;

create table if not exists public.events (
    id          text primary key,
    title       text not null,
    description text,
    start_date  timestamptz not null,
    end_date    timestamptz,
    created_at  timestamptz not null default now()
);


-- ------------------------------------------------------------
-- AGENTE FINANCIERO
-- ------------------------------------------------------------

create table if not exists public.credit_cards (
    id            text primary key default gen_random_uuid()::text,
    bank          text not null,
    card_name     text not null,
    total_limit   numeric(14, 2) not null check (total_limit > 0),
    used_amount   numeric(14, 2) not null default 0 check (used_amount >= 0),
    cutoff_day    smallint not null check (cutoff_day between 1 and 31),
    due_day       smallint not null check (due_day between 1 and 31),
    interest_rate_ea numeric(5, 2) not null,   -- tasa efectiva anual en %
    created_at    timestamptz not null default now()
);

create table if not exists public.transactions (
    id          text primary key,
    amount      numeric not null,
    merchant    text not null,
    category    text not null,
    date        timestamptz not null,
    month       integer not null,
    year        integer not null,
    is_income   boolean not null default false,
    created_at  timestamptz not null default now()
);

alter table public.transactions add column if not exists currency       text not null default 'COP';
alter table public.transactions add column if not exists payment_method text;
alter table public.transactions add column if not exists source         text not null default 'manual';
alter table public.transactions add column if not exists card_id        text
    references public.credit_cards(id) on delete set null;

do $$ begin
    alter table public.transactions add constraint transactions_amount_positive
        check (amount > 0) not valid;  -- not valid: no revalida filas antiguas
exception when duplicate_object then null; end $$;

do $$ begin
    alter table public.transactions add constraint transactions_source_check
        check (source in ('manual', 'voz', 'webhook'));
exception when duplicate_object then null; end $$;

create index if not exists transactions_month_year_idx on public.transactions (year, month);

-- Bitácora de ingesta cero-fricción: cada POST al webhook queda registrado,
-- con su transacción resultante o el error de extracción.
create table if not exists public.bank_notifications (
    id             text primary key default gen_random_uuid()::text,
    raw_text       text not null,
    received_at    timestamptz not null default now(),
    status         text not null default 'procesada'
                   check (status in ('procesada', 'error')),
    error          text,
    transaction_id text references public.transactions(id) on delete set null
);

create table if not exists public.savings_goals (
    id             text primary key default gen_random_uuid()::text,
    name           text not null,
    target_amount  numeric(14, 2) not null check (target_amount > 0),
    current_amount numeric(14, 2) not null default 0 check (current_amount >= 0),
    category       text not null default 'general',
    emoji          text not null default '🎯',
    target_date    date,
    created_at     timestamptz not null default now()
);

create table if not exists public.goal_deposits (
    id         text primary key default gen_random_uuid()::text,
    goal_id    text not null references public.savings_goals(id) on delete cascade,
    amount     numeric(14, 2) not null check (amount > 0),
    created_at timestamptz not null default now()
);


-- ------------------------------------------------------------
-- SEGURIDAD: RLS activado sin políticas públicas.
-- Solo el backend (clave secreta / service role) puede leer y escribir;
-- la app móvil nunca habla directo con Supabase, siempre vía Tailscale → FastAPI.
-- ------------------------------------------------------------

alter table public.emails             enable row level security;
alter table public.email_drafts       enable row level security;
alter table public.tasks              enable row level security;
alter table public.events             enable row level security;
alter table public.credit_cards       enable row level security;
alter table public.transactions       enable row level security;
alter table public.bank_notifications enable row level security;
alter table public.savings_goals      enable row level security;
alter table public.goal_deposits      enable row level security;


-- ------------------------------------------------------------
-- DATOS SEMILLA (solo si las tablas están vacías)
-- ------------------------------------------------------------

insert into public.emails (id, sender, sender_name, recipient, subject, snippet, body, is_read, is_urgent)
select * from (values
    ('email-decano-001',
     'Decanatura de Ingeniería <decanatura.ingenieria@universidad.edu.co>',
     'Decano Roberto Mendoza',
     'estudiante@universidad.edu.co',
     'Respuesta: Aprobación de prórroga para entrega de Proyecto GUTI',
     'Estimado estudiante, he revisado su solicitud. Se autoriza la sustentación técnica del asistente multi-agente...',
     E'Estimado estudiante,\n\nHe revisado su comunicación respecto al Asistente Personal GUTI. Le confirmo que la fecha de sustentación del segundo corte ha quedado ratificada.\n\nAtentamente,\nDr. Roberto Mendoza\nDecano de la Facultad de Ingeniería',
     false, true),
    ('email-prof-moviles-002',
     'Profesor Carlos Gómez <carlos.gomez@universidad.edu.co>',
     'Profesor Carlos Gómez',
     'estudiante@universidad.edu.co',
     'Rúbrica y Lineamientos Taller Segundo Corte - Aplicaciones Móviles',
     'Recordatorio sobre los criterios de evaluación: orquestador multi-agente, VPN Mesh Tailscale...',
     E'Apreciados estudiantes,\n\nSe evaluará el orquestador con Function Calling, la persistencia en Supabase y la ingesta cero fricción vía Tailscale.\n\nMuchos éxitos.',
     true, false)
) as seed(id, sender, sender_name, recipient, subject, snippet, body, is_read, is_urgent)
where not exists (select 1 from public.emails);

insert into public.credit_cards (bank, card_name, total_limit, used_amount, cutoff_day, due_day, interest_rate_ea)
select * from (values
    ('Bancolombia', 'Mastercard Joven', 2000000.00, 450000.00, 15, 5, 24.50),
    ('Nu Colombia', 'Nu Moradita',      1200000.00, 180000.00, 22, 2, 23.90)
) as seed(bank, card_name, total_limit, used_amount, cutoff_day, due_day, interest_rate_ea)
where not exists (select 1 from public.credit_cards);

insert into public.savings_goals (name, target_amount, current_amount, category, emoji)
select * from (values
    ('Fondo de emergencia', 3000000.00, 850000.00, 'emergencia', '🛟'),
    ('Viaje académico',     2500000.00, 400000.00, 'viajes',     '✈️')
) as seed(name, target_amount, current_amount, category, emoji)
where not exists (select 1 from public.savings_goals);

-- Refresca la caché de esquema de PostgREST para que la API vea las columnas nuevas.
notify pgrst, 'reload schema';
