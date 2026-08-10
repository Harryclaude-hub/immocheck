-- =====================================================================
--  ImmoCheck – komplettes Datenbank-Setup für Supabase
--  Im Supabase-Dashboard: SQL Editor öffnen, diese Datei einfügen, Run.
--  Legt Tabellen, Sicherheitsregeln, Fotospeicher und 179 Prüfpunkte an.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Tabellen
-- ---------------------------------------------------------------------
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null default '',
  full_name text,
  company text,
  phone text,
  role text not null default 'mitarbeiter' check (role in ('admin','mitarbeiter')),
  status text not null default 'wartend' check (status in ('aktiv','wartend','gesperrt')),
  created_at timestamptz not null default now()
);

create table if not exists public.properties (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  object_type text not null default 'wohnung'
    check (object_type in ('einzimmerwohnung','wohnung','einfamilienhaus','doppelhaus','reihenhaus','mehrfamilienhaus','wohnanlage','gewerbe','sonstiges')),
  street text, house_number text, zip text, city text, country text default 'Österreich',
  build_year int, last_renovation int, units_count int default 1, floors int,
  has_basement boolean default false, has_elevator boolean default false,
  has_garden boolean default false, has_parking boolean default false,
  living_area numeric, plot_area numeric,
  heating_type text, energy_class text,
  owner_name text, contact_name text, contact_phone text, contact_email text,
  description text, notes text,
  status text not null default 'aktiv' check (status in ('aktiv','archiviert')),
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Gebaeudestruktur: Mengen, Leitungen und Ausstattung je Ebene.
-- Als alter table, damit bestehende Installationen die Felder nachtraeglich bekommen.
alter table public.properties add column if not exists elevator_count   integer default 0;
alter table public.properties add column if not exists basement_units   integer;
alter table public.properties add column if not exists attic_units      integer;
alter table public.properties add column if not exists has_attic        boolean default false;
alter table public.properties add column if not exists utilities        text[] default '{}';
alter table public.properties add column if not exists basement_content text[] default '{}';
alter table public.properties add column if not exists ground_content   text[] default '{}';
alter table public.properties add column if not exists attic_content    text[] default '{}';
alter table public.properties add column if not exists structure_notes  text;

create table if not exists public.units (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references public.properties(id) on delete cascade,
  label text not null, floor text, rooms numeric, area numeric,
  tenant_name text, tenant_since date, notes text,
  created_at timestamptz not null default now()
);

create table if not exists public.categories (
  id uuid primary key default gen_random_uuid(),
  key text unique not null,
  name text not null,
  icon text default '📋',
  sort_order int not null default 0,
  scope text not null default 'beide' check (scope in ('gebaeude','einheit','beide')),
  is_system boolean not null default true,
  active boolean not null default true,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.criteria (
  id uuid primary key default gen_random_uuid(),
  category_id uuid not null references public.categories(id) on delete cascade,
  name text not null, hint text,
  sort_order int not null default 0,
  scope text not null default 'beide' check (scope in ('gebaeude','einheit','beide')),
  critical boolean not null default false,
  is_system boolean not null default true,
  active boolean not null default true,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.inspections (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references public.properties(id) on delete cascade,
  unit_id uuid references public.units(id) on delete set null,
  title text,
  inspection_date date not null default current_date,
  inspector_id uuid references public.profiles(id) on delete set null,
  inspector_name text, weather text, present_persons text,
  general_notes text, summary text,
  status text not null default 'offen' check (status in ('offen','abgeschlossen')),
  score numeric, score_percent numeric,
  rated_count int default 0, missing_count int default 0,
  defect_count int default 0, critical_count int default 0,
  created_at timestamptz not null default now(),
  completed_at timestamptz
);

create table if not exists public.inspection_items (
  id uuid primary key default gen_random_uuid(),
  inspection_id uuid not null references public.inspections(id) on delete cascade,
  criterion_id uuid references public.criteria(id) on delete set null,
  category_key text not null default 'sonstiges',
  category_name text not null default 'Sonstiges',
  criterion_name text not null, hint text,
  sort_order int not null default 0,
  presence text default 'offen' check (presence in ('offen','vorhanden','nicht_vorhanden','nicht_relevant')),
  rating int check (rating between 1 and 5),
  note text,
  defect boolean not null default false,
  priority text not null default 'keine' check (priority in ('keine','niedrig','mittel','hoch','kritisch')),
  due_date date, photo_path text,
  is_custom boolean not null default false,
  critical boolean not null default false,
  updated_at timestamptz not null default now()
);

create index if not exists idx_units_property on public.units(property_id);
create index if not exists idx_criteria_category on public.criteria(category_id);
create index if not exists idx_inspections_property on public.inspections(property_id, inspection_date desc);
create index if not exists idx_items_inspection on public.inspection_items(inspection_id, sort_order);

-- ---------------------------------------------------------------------
-- 2. Funktionen und Trigger
-- ---------------------------------------------------------------------

-- Erste Registrierung wird Administrator, alle weiteren warten auf Freigabe
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare first_user boolean;
begin
  select count(*) = 0 into first_user from public.profiles;
  insert into public.profiles (id, email, full_name, role, status)
  values (
    new.id,
    coalesce(new.email, ''),
    coalesce(nullif(new.raw_user_meta_data->>'full_name',''), split_part(coalesce(new.email,''), '@', 1)),
    case when first_user then 'admin' else 'mitarbeiter' end,
    case when first_user then 'aktiv' else 'wartend' end
  ) on conflict (id) do nothing;
  return new;
end; $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute function public.handle_new_user();

-- Registrierung ohne E-Mail-Bestaetigung
create or replace function public.auto_confirm_email()
returns trigger language plpgsql security definer set search_path = auth, public as $$
begin
  if new.email_confirmed_at is null then new.email_confirmed_at := now(); end if;
  if new.confirmation_token is null then new.confirmation_token := ''; end if;
  return new;
end; $$;

drop trigger if exists trg_auto_confirm_email on auth.users;
create trigger trg_auto_confirm_email before insert on auth.users
for each row execute function public.auto_confirm_email();

-- Nur Admins duerfen Rolle und Status aendern
create or replace function public.guard_profile_update()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then
    new.role := old.role;
    new.status := old.status;
  end if;
  return new;
end; $$;

create or replace function public.is_active_user()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles p where p.id = auth.uid() and p.status = 'aktiv');
$$;

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin' and p.status = 'aktiv');
$$;

create or replace function public.touch_updated_at()
returns trigger language plpgsql set search_path = public as $$
begin new.updated_at = now(); return new; end; $$;

drop trigger if exists trg_profiles_guard on public.profiles;
create trigger trg_profiles_guard before update on public.profiles
for each row execute function public.guard_profile_update();

drop trigger if exists trg_properties_touch on public.properties;
create trigger trg_properties_touch before update on public.properties
for each row execute function public.touch_updated_at();

drop trigger if exists trg_items_touch on public.inspection_items;
create trigger trg_items_touch before update on public.inspection_items
for each row execute function public.touch_updated_at();

-- Funktionen nicht ueber die oeffentliche API aufrufbar machen
revoke execute on function public.handle_new_user() from anon, authenticated, public;
revoke execute on function public.auto_confirm_email() from anon, authenticated, public;
revoke execute on function public.guard_profile_update() from anon, authenticated, public;
revoke execute on function public.touch_updated_at() from anon, authenticated, public;
revoke execute on function public.is_active_user() from anon, public;
revoke execute on function public.is_admin() from anon, public;
grant execute on function public.is_active_user() to authenticated;
grant execute on function public.is_admin() to authenticated;

-- ---------------------------------------------------------------------
-- 3. Zugriffsschutz (Row Level Security)
-- ---------------------------------------------------------------------
alter table public.profiles          enable row level security;
alter table public.properties        enable row level security;
alter table public.units             enable row level security;
alter table public.categories        enable row level security;
alter table public.criteria          enable row level security;
alter table public.inspections       enable row level security;
alter table public.inspection_items  enable row level security;

drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles for select to authenticated
  using (id = (select auth.uid()) or public.is_active_user());
drop policy if exists profiles_insert on public.profiles;
create policy profiles_insert on public.profiles for insert to authenticated
  with check (id = (select auth.uid()));
drop policy if exists profiles_update on public.profiles;
create policy profiles_update on public.profiles for update to authenticated
  using (id = (select auth.uid()) or public.is_admin())
  with check (id = (select auth.uid()) or public.is_admin());
drop policy if exists profiles_delete on public.profiles;
create policy profiles_delete on public.profiles for delete to authenticated
  using (public.is_admin() and id <> (select auth.uid()));

drop policy if exists properties_select on public.properties;
create policy properties_select on public.properties for select to authenticated using (public.is_active_user());
drop policy if exists properties_insert on public.properties;
create policy properties_insert on public.properties for insert to authenticated with check (public.is_active_user());
drop policy if exists properties_update on public.properties;
create policy properties_update on public.properties for update to authenticated using (public.is_active_user()) with check (public.is_active_user());
drop policy if exists properties_delete on public.properties;
create policy properties_delete on public.properties for delete to authenticated using (public.is_admin() or created_by = (select auth.uid()));

drop policy if exists units_select on public.units;
create policy units_select on public.units for select to authenticated using (public.is_active_user());
drop policy if exists units_insert on public.units;
create policy units_insert on public.units for insert to authenticated with check (public.is_active_user());
drop policy if exists units_update on public.units;
create policy units_update on public.units for update to authenticated using (public.is_active_user()) with check (public.is_active_user());
drop policy if exists units_delete on public.units;
create policy units_delete on public.units for delete to authenticated using (public.is_active_user());

drop policy if exists categories_select on public.categories;
create policy categories_select on public.categories for select to authenticated using (public.is_active_user());
drop policy if exists categories_insert on public.categories;
create policy categories_insert on public.categories for insert to authenticated with check (public.is_active_user());
drop policy if exists categories_update on public.categories;
create policy categories_update on public.categories for update to authenticated
  using (public.is_admin() or created_by = (select auth.uid()))
  with check (public.is_admin() or created_by = (select auth.uid()));
drop policy if exists categories_delete on public.categories;
create policy categories_delete on public.categories for delete to authenticated
  using ((public.is_admin() or created_by = (select auth.uid())) and is_system = false);

drop policy if exists criteria_select on public.criteria;
create policy criteria_select on public.criteria for select to authenticated using (public.is_active_user());
drop policy if exists criteria_insert on public.criteria;
create policy criteria_insert on public.criteria for insert to authenticated with check (public.is_active_user());
drop policy if exists criteria_update on public.criteria;
create policy criteria_update on public.criteria for update to authenticated
  using (public.is_admin() or created_by = (select auth.uid()))
  with check (public.is_admin() or created_by = (select auth.uid()));
drop policy if exists criteria_delete on public.criteria;
create policy criteria_delete on public.criteria for delete to authenticated
  using ((public.is_admin() or created_by = (select auth.uid())) and is_system = false);

drop policy if exists inspections_select on public.inspections;
create policy inspections_select on public.inspections for select to authenticated using (public.is_active_user());
drop policy if exists inspections_insert on public.inspections;
create policy inspections_insert on public.inspections for insert to authenticated with check (public.is_active_user());
drop policy if exists inspections_update on public.inspections;
create policy inspections_update on public.inspections for update to authenticated using (public.is_active_user()) with check (public.is_active_user());
drop policy if exists inspections_delete on public.inspections;
create policy inspections_delete on public.inspections for delete to authenticated using (public.is_admin() or inspector_id = (select auth.uid()));

drop policy if exists items_select on public.inspection_items;
create policy items_select on public.inspection_items for select to authenticated using (public.is_active_user());
drop policy if exists items_insert on public.inspection_items;
create policy items_insert on public.inspection_items for insert to authenticated with check (public.is_active_user());
drop policy if exists items_update on public.inspection_items;
create policy items_update on public.inspection_items for update to authenticated using (public.is_active_user()) with check (public.is_active_user());
drop policy if exists items_delete on public.inspection_items;
create policy items_delete on public.inspection_items for delete to authenticated using (public.is_active_user());

-- ---------------------------------------------------------------------
-- 4. Fotospeicher
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('check-fotos', 'check-fotos', false, 10485760, array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;

drop policy if exists fotos_select on storage.objects;
create policy fotos_select on storage.objects for select to authenticated
  using (bucket_id = 'check-fotos' and public.is_active_user());
drop policy if exists fotos_insert on storage.objects;
create policy fotos_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'check-fotos' and public.is_active_user());
drop policy if exists fotos_update on storage.objects;
create policy fotos_update on storage.objects for update to authenticated
  using (bucket_id = 'check-fotos' and public.is_active_user())
  with check (bucket_id = 'check-fotos' and public.is_active_user());
drop policy if exists fotos_delete on storage.objects;
create policy fotos_delete on storage.objects for delete to authenticated
  using (bucket_id = 'check-fotos' and public.is_active_user());

-- ---------------------------------------------------------------------
-- 5. Prüfkatalog: 21 Kategorien
-- ---------------------------------------------------------------------
insert into public.categories (key, name, icon, sort_order, scope, is_system) values
('allgemein','Allgemeinzustand & Ersteindruck','🏠',10,'beide',true),
('dach','Dach & Dachstuhl','🏚️',20,'gebaeude',true),
('fassade','Fassade, Balkone & Außenhülle','🧱',30,'gebaeude',true),
('keller','Keller, Fundament & Entwässerung','🕳️',40,'gebaeude',true),
('fenster','Fenster & Türen','🪟',50,'beide',true),
('elektro','Elektroinstallation','⚡',60,'beide',true),
('heizung','Heizung, Warmwasser & Lüftung','🔥',70,'beide',true),
('sanitaer','Wasser, Sanitär & Abfluss','🚿',80,'beide',true),
('brandschutz','Brandschutz & Fluchtwege','🧯',90,'beide',true),
('sicherheit','Sicherheit & Einbruchschutz','🔒',100,'beide',true),
('schimmel','Feuchtigkeit, Schimmel & Raumklima','💧',110,'beide',true),
('schadstoffe','Schadstoffe & Gesundheit','☣️',120,'beide',true),
('innen','Innenräume, Böden & Ausstattung','🛋️',130,'einheit',true),
('kueche','Küche & Geräte','🍳',140,'einheit',true),
('gemeinschaft','Treppenhaus & Gemeinschaftsflächen','🚪',150,'gebaeude',true),
('aussen','Außenanlagen, Zufahrt & Stellplätze','🌳',160,'gebaeude',true),
('technik','Aufzug, Technikräume & Medien','⚙️',170,'gebaeude',true),
('energie','Energie & Dämmung','🌡️',180,'gebaeude',true),
('entsorgung','Reinigung, Müll & Entsorgung','🗑️',190,'beide',true),
('dokumente','Dokumente, Prüfbefunde & Versicherung','📄',200,'beide',true),
('mietverhaeltnis','Mietverhältnis & Nutzung','🤝',210,'beide',true)
on conflict (key) do nothing;

-- ---------------------------------------------------------------------
-- 6. Prüfkatalog: 179 Prüfpunkte
-- ---------------------------------------------------------------------
insert into public.criteria (category_id, name, hint, sort_order, scope, critical, is_system)
select c.id, x.name, nullif(x.hint,''), x.ord, x.scope, x.crit, true
from (values
('allgemein','Objekt von außen sauber und gepflegt','Gesamteindruck von der Straße aus',10,'beide',false),
('allgemein','Hausnummer und Beschilderung gut sichtbar','Wichtig für Rettungskräfte',20,'gebaeude',false),
('allgemein','Klingel- und Briefkastenanlage vollständig funktionsfähig','Alle Taster und Schlösser testen',30,'gebaeude',false),
('allgemein','Namensschilder aktuell und lesbar','Abgleich mit Mieterliste',40,'gebaeude',false),
('allgemein','Keine offensichtlichen Bauschäden erkennbar','Risse, Absackungen, Verformungen',50,'beide',true),
('allgemein','Mängel der letzten Begehung wurden behoben','Vergleich mit letztem Protokoll',60,'beide',false),
('allgemein','Zugänglichkeit und Barrierefreiheit ausreichend','Stufen, Rampe, Türbreiten, Schwellen',70,'beide',false),
('allgemein','Beleuchtung im Eingangsbereich funktioniert','Auch Bewegungsmelder testen',80,'gebaeude',false),
('allgemein','Keine Vandalismus- oder Graffitischäden','Fotos bei Schaden anfertigen',90,'gebaeude',false),
('dach','Dacheindeckung vollständig, keine verschobenen Ziegel','Sichtprüfung, ggf. mit Fernglas',10,'gebaeude',true),
('dach','Kein Wassereintritt am Dachboden sichtbar','Sparren und Unterspannbahn prüfen',20,'gebaeude',true),
('dach','Dachstuhl frei von Fäulnis, Pilz- oder Insektenbefall','Bohrmehl und weiche Stellen beachten',30,'gebaeude',true),
('dach','Dachrinnen und Fallrohre frei, dicht und fest','Laub, Rost, lose Halterungen',40,'gebaeude',false),
('dach','Kamin bzw. Rauchfang äußerlich intakt','Verputz, Abdeckung, Risse',50,'gebaeude',true),
('dach','Dachfenster und Lichtkuppeln dicht und funktionsfähig','Dichtungen und Beschläge',60,'gebaeude',false),
('dach','Schneefanggitter vorhanden und fest montiert','Haftungsrelevant bei Schneelast',70,'gebaeude',true),
('dach','Blitzschutzanlage vorhanden und geprüft','Prüfintervall und Befund kontrollieren',80,'gebaeude',true),
('dach','Dachaufbauten sicher befestigt','Antennen, PV-Module, Klimageräte',90,'gebaeude',false),
('fassade','Putz oder Verkleidung ohne Risse und Hohlstellen','Abklopfen bei Verdacht',10,'gebaeude',true),
('fassade','Keine aufsteigende Feuchtigkeit im Sockelbereich','Salzausblühungen, dunkle Ränder',20,'gebaeude',true),
('fassade','Balkone und Loggien ohne Betonabplatzungen','Freiliegende Bewehrung ist kritisch',30,'gebaeude',true),
('fassade','Geländer fest verankert und ausreichend hoch','Mindesthöhe und Abstände prüfen',40,'gebaeude',true),
('fassade','Abdichtung und Gefälle bei Balkonen in Ordnung','Kein stehendes Wasser',50,'gebaeude',false),
('fassade','Fensterbänke und Anschlüsse dicht','Silikon und Blechabschlüsse',60,'gebaeude',false),
('fassade','Außenanstrich intakt, keine Algen- oder Moosbildung','Nord- und Wetterseite besonders',70,'gebaeude',false),
('fassade','Fassadendämmung unbeschädigt','Spechtlöcher, Ablösungen, Fugen',80,'gebaeude',false),
('keller','Keller trocken, kein stehendes Wasser','Auch nach Regenperiode prüfen',10,'gebaeude',true),
('keller','Kein muffiger Geruch im Keller','Deutlicher Hinweis auf Feuchte',20,'gebaeude',false),
('keller','Fundament und Kellerwände ohne Setzungsrisse','Risse markieren und beobachten',30,'gebaeude',true),
('keller','Kellerfenster und Lichtschächte dicht, Abläufe frei','Laub und Verstopfungen entfernen',40,'gebaeude',false),
('keller','Rückstauklappe vorhanden und funktionsfähig','Schutz bei Starkregen',50,'gebaeude',true),
('keller','Kellerabteile abgetrennt und beschriftet','Zuordnung zu Einheiten klar',60,'gebaeude',false),
('keller','Keine Brandlast in Kellergängen und Fluchtwegen','Kartons, Möbel, Reifen entfernen',70,'gebaeude',true),
('keller','Hebeanlage oder Drainage funktionsfähig','Falls vorhanden testen',80,'gebaeude',false),
('fenster','Fenster schließen dicht, keine Zugluft','Papiertest an der Dichtung',10,'beide',false),
('fenster','Dichtungen elastisch und vollständig','Nicht spröde oder gerissen',20,'beide',false),
('fenster','Beschläge gangbar, Griffe fest','Kipp- und Drehfunktion testen',30,'beide',false),
('fenster','Isolierglas ohne Beschlag zwischen den Scheiben','Hinweis auf defekten Randverbund',40,'beide',false),
('fenster','Rahmen ohne Fäulnis oder Rost','Besonders bei Holzfenstern',50,'beide',false),
('fenster','Rollläden, Jalousien und Markisen funktionsfähig','Gurte, Motoren, Endlagen',60,'beide',false),
('fenster','Wohnungs- und Haustür schließt sicher, Schloss gängig','Auch Schließzylinder testen',70,'beide',true),
('fenster','Absturzsicherung bei bodentiefen Fenstern vorhanden','Haftungsrelevant, besonders mit Kindern',80,'beide',true),
('elektro','Zählerkasten frei zugänglich und beschriftet','Keine Verstellung durch Lagerung',10,'beide',false),
('elektro','FI-Schutzschalter vorhanden und Testfunktion geprüft','Testknopf drücken, Auslösung prüfen',20,'beide',true),
('elektro','Sicherungsautomaten ohne Flickschaltungen','Keine überbrückten oder ausgebauten Teile',30,'beide',true),
('elektro','Steckdosen, Schalter und Abdeckungen unbeschädigt','Keine Brandspuren oder Risse',40,'beide',true),
('elektro','Keine losen oder provisorischen Kabel','Kabeltrommeln, Mehrfachstecker-Ketten',50,'beide',true),
('elektro','Ausreichend Steckdosen je Raum vorhanden','Vermeidet Provisorien',60,'einheit',false),
('elektro','Elektro-Prüfbefund aktuell und abgelegt','Prüfintervall je nach Nutzung einhalten',70,'beide',true),
('elektro','Beleuchtung in allen Räumen und Fluren funktioniert','Leuchtmittel und Schalter testen',80,'beide',false),
('elektro','Gegensprech- und Türöffneranlage funktioniert','Von außen und innen testen',90,'gebaeude',false),
('elektro','Feuchtraum- und Außenbereiche korrekt ausgeführt','Passender IP-Schutz, dichte Abdeckungen',100,'beide',true),
('elektro','Wallbox oder PV-Anlage fachgerecht angeschlossen','Nur falls vorhanden',110,'gebaeude',false),
('heizung','Heizung läuft störungsfrei, keine Fehlermeldung','Display und Störlampe prüfen',10,'beide',true),
('heizung','Letzte Wartung dokumentiert und im Intervall','Wartungsprotokoll am Gerät',20,'beide',true),
('heizung','Rauchfangkehrer- bzw. Kaminbefund aktuell','Gesetzlich vorgeschrieben',30,'beide',true),
('heizung','Kein Gasgeruch, Gasleitungen dicht','Bei Verdacht sofort absperren',40,'beide',true),
('heizung','CO-Melder bei Gas- oder Festbrennstoffheizung vorhanden','Lebensrettend, Funktion testen',50,'beide',true),
('heizung','Heizkörper werden gleichmäßig warm','Entlüften falls nötig',60,'beide',false),
('heizung','Thermostatventile funktionsfähig','Nicht festsitzend',70,'beide',false),
('heizung','Anlagendruck und Ausdehnungsgefäß in Ordnung','Manometer im grünen Bereich',80,'gebaeude',false),
('heizung','Heizungsrohre gedämmt und ohne Leckagen','Besonders in unbeheizten Räumen',90,'gebaeude',false),
('heizung','Öltank oder Pelletlager dicht und ordnungsgemäß','Auffangwanne und Füllstand prüfen',100,'gebaeude',true),
('heizung','Lüftungsanlage gereinigt, Filter getauscht','Falls kontrollierte Wohnraumlüftung',110,'beide',false),
('sanitaer','Keine tropfenden Armaturen oder sichtbaren Leckagen','Auch unter Waschbecken schauen',10,'beide',true),
('sanitaer','Wasserdruck an allen Entnahmestellen ausreichend','Mehrere Hähne gleichzeitig testen',20,'beide',false),
('sanitaer','Warmwasser erreicht ausreichende Temperatur','Mindestens 60 Grad wegen Legionellen',30,'beide',true),
('sanitaer','Abflüsse laufen frei, kein Geruch aus Siphons','Auch selten genutzte Abläufe spülen',40,'beide',false),
('sanitaer','Silikonfugen in Bad und Dusche intakt','Kein Schimmel, keine Ablösung',50,'beide',false),
('sanitaer','WC-Spülung dicht, kein Dauerlauf','Verursacht hohe Wasserkosten',60,'beide',false),
('sanitaer','Hauptabsperrventil auffindbar und gängig','Im Notfall entscheidend',70,'beide',true),
('sanitaer','Wasserzähler abgelesen und Verbrauch plausibel','Auffälliger Verbrauch deutet auf Leck',80,'beide',false),
('sanitaer','Rohrleitungen ohne Korrosion oder Ausblühungen','Besonders bei Altbestand',90,'gebaeude',false),
('sanitaer','Legionellenprüfung dokumentiert','Pflicht bei größeren Anlagen',100,'gebaeude',true),
('brandschutz','Rauchwarnmelder in allen erforderlichen Räumen','Schlafräume, Kinderzimmer, Flure',10,'beide',true),
('brandschutz','Rauchwarnmelder funktionsfähig, Batterie in Ordnung','Testknopf drücken',20,'beide',true),
('brandschutz','Feuerlöscher vorhanden, geprüft und plombiert','Auch Zugänglichkeit prüfen',30,'beide',true),
('brandschutz','Prüfplakette am Feuerlöscher aktuell','In der Regel alle zwei Jahre',40,'beide',true),
('brandschutz','Fluchtwege und Treppenhaus komplett frei','Keine Möbel, Kartons oder Fahrräder',50,'beide',true),
('brandschutz','Brandschutztüren schließen selbsttätig','Nicht verkeilt oder aufgebunden',60,'gebaeude',true),
('brandschutz','Notbeleuchtung und Fluchtwegkennzeichnung funktioniert','Falls vorgeschrieben',70,'gebaeude',true),
('brandschutz','Brandmelde- oder Alarmanlage funktionsfähig','Falls vorhanden, Störungsanzeige prüfen',80,'gebaeude',false),
('brandschutz','Keine brennbare Lagerung an Technik und Verteilern','Sicherheitsabstand einhalten',90,'gebaeude',true),
('brandschutz','Brandschutzordnung bzw. Aushang vorhanden','Bei Mehrparteienhäusern',100,'gebaeude',false),
('sicherheit','Haustür schließt selbsttätig und verriegelt','Türschließer und Falle prüfen',10,'gebaeude',true),
('sicherheit','Schließanlage vollständig, Schlüssel dokumentiert','Schlüsselverzeichnis abgleichen',20,'beide',true),
('sicherheit','Erdgeschossfenster und Terrassentüren gesichert','Pilzkopfverriegelung oder Zusatzsicherung',30,'beide',false),
('sicherheit','Außenbeleuchtung und Bewegungsmelder funktionieren','Abschreckung und Wegsicherheit',40,'gebaeude',false),
('sicherheit','Kamera- oder Gegensprechanlage funktionsfähig','Nur falls vorhanden, Datenschutz beachten',50,'gebaeude',false),
('sicherheit','Keller- und Nebeneingänge versperrt','Auch Garagenzugänge',60,'gebaeude',false),
('sicherheit','Handläufe und Geländer fest und ausreichend hoch','Haftungsrelevant',70,'beide',true),
('sicherheit','Treppenstufen ohne Stolperstellen und rutschhemmend','Kanten und Beläge prüfen',80,'beide',true),
('sicherheit','Technikräume für Unbefugte nicht zugänglich','Immer versperrt halten',90,'gebaeude',false),
('schimmel','Keine sichtbaren Schimmelflecken an Wänden oder Decken','Auch hinter Möbeln und in Ecken',10,'beide',true),
('schimmel','Keine Feuchteränder oder abblätternde Farbe','Foto und Ursache dokumentieren',20,'beide',true),
('schimmel','Raumluftfeuchte im normalen Bereich','Richtwert 40 bis 60 Prozent',30,'beide',false),
('schimmel','Kein modriger oder muffiger Geruch','Geruch ist ein Frühindikator',40,'beide',false),
('schimmel','Wärmebrücken unauffällig','Fensterlaibungen, Außenecken, Rollladenkästen',50,'beide',false),
('schimmel','Ausreichende Lüftungsmöglichkeit in Bad und Küche','Fenster oder Abluft vorhanden',60,'beide',false),
('schimmel','Abluftventilatoren funktionsfähig','Nachlauf und Leistung prüfen',70,'beide',false),
('schimmel','Kein dauerhaftes Kondenswasser an Fenstern','Hinweis auf Lüftungsproblem',80,'beide',false),
('schadstoffe','Kein Verdacht auf Asbest','Eternit, alte Bodenkleber, Nachtspeicheröfen',10,'beide',true),
('schadstoffe','Keine Bleirohre in der Trinkwasserleitung','Vor allem bei Bauten vor 1973',20,'beide',true),
('schadstoffe','Keine bekannten PCB- oder PAK-belasteten Materialien','Alte Fugenmassen und Klebstoffe',30,'gebaeude',false),
('schadstoffe','Radon-Situation im Keller unauffällig','In belasteten Regionen messen lassen',40,'gebaeude',false),
('schadstoffe','Kein Schädlings-, Nager- oder Taubenbefall','Kot, Nagespuren, Nester',50,'beide',true),
('schadstoffe','Keine offenen Mineralwolle- oder Dämmstoffstellen','Faserfreisetzung vermeiden',60,'gebaeude',false),
('innen','Bodenbeläge unbeschädigt, keine Stolperstellen','Fliesen, Parkett, Laminat prüfen',10,'einheit',false),
('innen','Wände und Decken ohne Risse oder Löcher','Dübellöcher und Setzrisse notieren',20,'einheit',false),
('innen','Innentüren schließen sauber, Beschläge fest','Klinken und Schlösser testen',30,'einheit',false),
('innen','Malerzustand in Ordnung','Vergilbung, Flecken, Abnutzung',40,'einheit',false),
('innen','Fußleisten und Übergangsprofile vollständig','Kleinigkeit mit optischer Wirkung',50,'einheit',false),
('innen','Sanitärobjekte ohne Sprünge oder Beschädigungen','WC, Waschbecken, Wanne',60,'einheit',false),
('innen','Einbaumöbel fest montiert und funktionsfähig','Kippsicherung bei hohen Möbeln',70,'einheit',false),
('innen','Keller- oder Dachbodenabteil der Einheit in Ordnung','Zuordnung und Zustand',80,'einheit',false),
('innen','Balkon oder Terrasse der Einheit sauber und intakt','Belag, Entwässerung, Geländer',90,'einheit',false),
('kueche','Küchengeräte funktionsfähig','Herd, Backofen, Kühlschrank testen',10,'einheit',false),
('kueche','Dunstabzug funktioniert, Filter sauber','Fettfilter und Leistung prüfen',20,'einheit',false),
('kueche','Spüle und Armatur dicht','Unterschrank auf Wasserspuren prüfen',30,'einheit',true),
('kueche','Arbeitsplatte ohne Wasserschäden','Besonders an Kanten und Spüle',40,'einheit',false),
('kueche','Geräteanschlüsse mit Aquastopp gesichert','Geschirrspüler und Waschmaschine',50,'einheit',true),
('kueche','Elektroanschluss Herd fachgerecht ausgeführt','Kein Provisorium zulässig',60,'einheit',true),
('gemeinschaft','Treppenhaus sauber und ausreichend beleuchtet','Reinigungsintervall prüfen',10,'gebaeude',false),
('gemeinschaft','Treppenhausbeleuchtung und Zeitschalter funktionieren','Laufzeit ausreichend eingestellt',20,'gebaeude',false),
('gemeinschaft','Handläufe durchgehend und fest','Über die gesamte Treppenlänge',30,'gebaeude',true),
('gemeinschaft','Waschküche und Trockenraum in Ordnung','Geräte, Lüftung, Sauberkeit',40,'gebaeude',false),
('gemeinschaft','Fahrrad- und Kinderwagenraum nutzbar und frei','Kein Fluchtweg blockiert',50,'gebaeude',false),
('gemeinschaft','Keine privaten Gegenstände im Fluchtweg','Regelmäßig kontrollieren',60,'gebaeude',true),
('gemeinschaft','Hausordnung und Aushänge aktuell','Notfallnummern gut sichtbar',70,'gebaeude',false),
('gemeinschaft','Postkasten- und Klingelanlage vollständig','Schlösser und Schilder',80,'gebaeude',false),
('gemeinschaft','Zugangstüren zu Gemeinschaftsflächen funktionsfähig','Schließen und versperren testen',90,'gebaeude',false),
('aussen','Zufahrt und Gehwege ohne Stolperstellen','Haftungsrelevant bei Unfällen',10,'gebaeude',true),
('aussen','Winterdienst organisiert und Streugut vorbereitet','Räum- und Streupflicht dokumentieren',20,'gebaeude',true),
('aussen','Entwässerung funktioniert, keine Pfützenbildung','Gefälle und Einläufe prüfen',30,'gebaeude',false),
('aussen','Bäume und Sträucher zurückgeschnitten, kein Totholz','Astbruchgefahr bei Sturm',40,'gebaeude',true),
('aussen','Zaun und Tore intakt und verschließbar','Auch Scharniere und Schlösser',50,'gebaeude',false),
('aussen','Stellplätze und Garagen markiert und nutzbar','Zuordnung eindeutig',60,'gebaeude',false),
('aussen','Garagentor funktioniert, Sicherheitsabschaltung geprüft','Einklemmschutz testen',70,'gebaeude',true),
('aussen','Außenbeleuchtung vollständig funktionsfähig','Wege und Zufahrten',80,'gebaeude',false),
('aussen','Spielplatz und Gartengeräte sicher','Regelmäßige Prüfpflicht',90,'gebaeude',true),
('technik','Aufzug läuft störungsfrei, Notruf funktioniert','Notruftaste tatsächlich testen',10,'gebaeude',true),
('technik','Aufzugsprüfung aktuell dokumentiert','Prüfbescheinigung in der Kabine',20,'gebaeude',true),
('technik','Technikräume versperrt und aufgeräumt','Keine Fremdlagerung',30,'gebaeude',false),
('technik','Hausanschlussraum zugänglich, Absperrungen beschriftet','Gas, Wasser, Strom klar gekennzeichnet',40,'gebaeude',true),
('technik','Internet- und TV-Verkabelung funktionsfähig','Verteiler und Anschlüsse',50,'gebaeude',false),
('technik','PV- oder Solaranlage ohne Fehlermeldung','Ertrag plausibel',60,'gebaeude',false),
('technik','Pump-, Hebe- oder Zisternenanlage funktionsfähig','Falls vorhanden testen',70,'gebaeude',false),
('technik','E-Ladestationen betriebsbereit','Abrechnung und Sicherheit prüfen',80,'gebaeude',false),
('energie','Energieausweis vorhanden und gültig','Gültigkeit maximal zehn Jahre',10,'gebaeude',true),
('energie','Oberste Geschossdecke oder Dach gedämmt','Größter Einsparhebel',20,'gebaeude',false),
('energie','Kellerdecke gedämmt','Verbessert Fußbodentemperatur',30,'gebaeude',false),
('energie','Fenster entsprechen dem geforderten Standard','Verglasung und U-Wert',40,'gebaeude',false),
('energie','Heizungsrohre in unbeheizten Räumen gedämmt','Gesetzlich oft gefordert',50,'gebaeude',false),
('energie','Verbrauchswerte gegenüber Vorjahr plausibel','Auffälligkeiten nachgehen',60,'gebaeude',false),
('entsorgung','Müllplatz sauber, Tonnen ausreichend dimensioniert','Überfüllung vermeiden',10,'gebaeude',false),
('entsorgung','Mülltrennung korrekt umgesetzt','Beschilderung vorhanden',20,'gebaeude',false),
('entsorgung','Kein dauerhaft gelagerter Sperr- oder Fremdmüll','Brandlast und Kosten',30,'gebaeude',true),
('entsorgung','Reinigungsintervalle eingehalten','Treppenhaus, Müllraum, Zugänge',40,'gebaeude',false),
('entsorgung','Kein Ungeziefer- oder Rattenbefall','Köderstellen kontrollieren',50,'beide',true),
('entsorgung','Grünflächenpflege erfolgt regelmäßig','Vertrag mit Dienstleister prüfen',60,'gebaeude',false),
('dokumente','Grundriss und Baupläne vorhanden','Digital abgelegt',10,'beide',false),
('dokumente','Energieausweis abgelegt','Pflicht bei Vermietung und Verkauf',20,'beide',true),
('dokumente','Wartungsverträge aktuell','Heizung, Aufzug, Rauchfang, Lüftung',30,'gebaeude',true),
('dokumente','Prüfbefunde vollständig abgelegt','Elektro, Blitzschutz, Feuerlöscher',40,'beide',true),
('dokumente','Gebäudeversicherung aufrecht und ausreichend','Deckungssumme prüfen',50,'gebaeude',true),
('dokumente','Haus- und Grundbesitzerhaftpflicht vorhanden','Schützt bei Personenschäden',60,'gebaeude',true),
('dokumente','Betriebskostenabrechnung aktuell','Fristen einhalten',70,'beide',false),
('dokumente','Schlüsselverzeichnis vollständig geführt','Übergaben dokumentiert',80,'beide',false),
('dokumente','Behördliche Auflagen erfüllt','Bescheide und Fristen prüfen',90,'gebaeude',true),
('dokumente','Fotodokumentation der letzten Begehung abgelegt','Vergleichbarkeit sicherstellen',100,'beide',false),
('mietverhaeltnis','Mietvertrag vorhanden und aktuell','Auch Nachträge ablegen',10,'beide',false),
('mietverhaeltnis','Kaution hinterlegt und korrekt dokumentiert','Getrennt vom Betriebsvermögen',20,'beide',true),
('mietverhaeltnis','Mietzahlungen aktuell, kein Rückstand','Kontostand abgleichen',30,'beide',false),
('mietverhaeltnis','Nutzung entspricht dem Mietvertrag','Keine ungenehmigte Untervermietung',40,'beide',false),
('mietverhaeltnis','Anzahl der Bewohner plausibel','Meldedaten abgleichen',50,'beide',false),
('mietverhaeltnis','Haustierhaltung gemäß Vereinbarung','Schäden dokumentieren',60,'beide',false),
('mietverhaeltnis','Keine baulichen Veränderungen ohne Zustimmung','Rückbaupflicht klären',70,'beide',false),
('mietverhaeltnis','Übergabeprotokoll vorhanden','Ein- und Auszug',80,'beide',false),
('mietverhaeltnis','Notfallkontakt und Erreichbarkeit aktuell','Für Wasserschaden und Co',90,'beide',false)
) as x(catkey, name, hint, ord, scope, crit)
join public.categories c on c.key = x.catkey
where not exists (
  select 1 from public.criteria k where k.category_id = c.id and k.name = x.name
);

-- ---------------------------------------------------------------------
-- 7. Vorlagen (Fragenkataloge je Immobilienart)
-- ---------------------------------------------------------------------
create table if not exists public.templates (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text,
  icon text default '📋',
  object_types text[] not null default '{}',
  sort_order int not null default 100,
  is_system boolean not null default false,
  active boolean not null default true,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.template_criteria (
  template_id uuid not null references public.templates(id) on delete cascade,
  criterion_id uuid not null references public.criteria(id) on delete cascade,
  primary key (template_id, criterion_id)
);
create index if not exists idx_template_criteria_tpl on public.template_criteria(template_id);

alter table public.inspection_items add column if not exists hidden boolean not null default false;
alter table public.inspection_items add column if not exists hidden_reason text;
alter table public.inspections add column if not exists skipped_categories jsonb not null default '{}'::jsonb;
alter table public.inspections add column if not exists template_id uuid references public.templates(id) on delete set null;
alter table public.inspections add column if not exists template_name text;
alter table public.inspections add column if not exists hidden_count int not null default 0;

-- Eigene Pruefpunkte, die nur zu einer bestimmten Immobilie gehoeren.
-- property_id null bedeutet: gilt global, wie bisher.
alter table public.criteria add column if not exists property_id uuid
  references public.properties(id) on delete cascade;
create index if not exists criteria_property_id_idx on public.criteria(property_id);

-- Eingescannte Papierboegen und die abgetippte Zusammenfassung
alter table public.inspections add column if not exists scan_paths   text[] default '{}';
alter table public.inspections add column if not exists scan_summary text;

-- Geometrie des gedruckten Bogens: wo liegt welches Ankreuzkaestchen.
alter table public.inspections add column if not exists sheet_layout jsonb;

-- Wie soll eine Frage beantwortet werden
alter table public.criteria add column if not exists answer_type text not null default 'skala';
alter table public.criteria drop constraint if exists criteria_answer_type_check;
alter table public.criteria add constraint criteria_answer_type_check
  check (answer_type in ('skala','ja_nein','messwert','text','auswahl'));
alter table public.criteria add column if not exists unit      text;
alter table public.criteria add column if not exists options   text[] default '{}';
alter table public.criteria add column if not exists min_value numeric;
alter table public.criteria add column if not exists max_value numeric;

-- Fragenkatalog kann an eine einzelne Immobilie gebunden werden
alter table public.templates add column if not exists property_id uuid
  references public.properties(id) on delete cascade;
create index if not exists templates_property_id_idx on public.templates(property_id);

-- Die Antwort selbst
alter table public.inspection_items add column if not exists answer_type text not null default 'skala';
alter table public.inspection_items add column if not exists unit       text;
alter table public.inspection_items add column if not exists options    text[] default '{}';
alter table public.inspection_items add column if not exists value_num  numeric;
alter table public.inspection_items add column if not exists value_text text;

-- Fotos zum Objekt, zu einem Raum, zu einer Einheit oder als Nachweis zu einer Notiz
create table if not exists public.property_photos (
  id uuid primary key default gen_random_uuid(),
  property_id   uuid not null references public.properties(id) on delete cascade,
  unit_id       uuid references public.units(id) on delete set null,
  inspection_id uuid references public.inspections(id) on delete set null,
  note_id       uuid references public.inspection_notes(id) on delete cascade,
  room text,
  caption text,
  path text not null,
  damage boolean not null default false,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists property_photos_property_idx on public.property_photos(property_id, created_at desc);
create index if not exists property_photos_note_idx     on public.property_photos(note_id);

alter table public.property_photos enable row level security;
drop policy if exists fotos_p_select on public.property_photos;
create policy fotos_p_select on public.property_photos for select to authenticated using (public.is_active_user());
drop policy if exists fotos_p_insert on public.property_photos;
create policy fotos_p_insert on public.property_photos for insert to authenticated with check (public.is_active_user());
drop policy if exists fotos_p_update on public.property_photos;
create policy fotos_p_update on public.property_photos for update to authenticated using (public.is_active_user()) with check (public.is_active_user());
drop policy if exists fotos_p_delete on public.property_photos;
create policy fotos_p_delete on public.property_photos for delete to authenticated using (public.is_active_user());

-- Geplante Begehungstermine, einmalig oder wiederkehrend
create table if not exists public.inspection_plans (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references public.properties(id) on delete cascade,
  unit_id uuid references public.units(id) on delete set null,
  title text not null default 'Begehung',
  start_date date not null,
  start_time text not null default '09:00',
  duration_min integer not null default 120,
  freq text not null default 'einmalig' check (freq in ('einmalig','wochen','monate','jahre')),
  interval_n integer not null default 1,
  reminder_days integer not null default 3,
  template_id uuid references public.templates(id) on delete set null,
  notes text,
  active boolean not null default true,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists inspection_plans_property_idx on public.inspection_plans(property_id, start_date);

alter table public.inspection_plans enable row level security;
drop policy if exists plans_select on public.inspection_plans;
create policy plans_select on public.inspection_plans for select to authenticated using (public.is_active_user());
drop policy if exists plans_insert on public.inspection_plans;
create policy plans_insert on public.inspection_plans for insert to authenticated with check (public.is_active_user());
drop policy if exists plans_update on public.inspection_plans;
create policy plans_update on public.inspection_plans for update to authenticated using (public.is_active_user()) with check (public.is_active_user());
drop policy if exists plans_delete on public.inspection_plans;
create policy plans_delete on public.inspection_plans for delete to authenticated using (public.is_active_user());

-- Gesprochene oder getippte Notizen waehrend der Begehung, je Raum
create table if not exists public.inspection_notes (
  id uuid primary key default gen_random_uuid(),
  inspection_id uuid not null references public.inspections(id) on delete cascade,
  property_id   uuid references public.properties(id) on delete cascade,
  room text,
  text text not null,
  damage boolean not null default false,
  source text not null default 'getippt' check (source in ('getippt','diktat')),
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists inspection_notes_inspection_idx on public.inspection_notes(inspection_id);
create index if not exists inspection_notes_property_idx   on public.inspection_notes(property_id, created_at desc);

alter table public.inspection_notes enable row level security;
drop policy if exists notes_select on public.inspection_notes;
create policy notes_select on public.inspection_notes for select to authenticated using (public.is_active_user());
drop policy if exists notes_insert on public.inspection_notes;
create policy notes_insert on public.inspection_notes for insert to authenticated with check (public.is_active_user());
drop policy if exists notes_update on public.inspection_notes;
create policy notes_update on public.inspection_notes for update to authenticated using (public.is_active_user()) with check (public.is_active_user());
drop policy if exists notes_delete on public.inspection_notes;
create policy notes_delete on public.inspection_notes for delete to authenticated using (public.is_active_user());

-- Grenzwerte mit in die Begehung kopieren, damit die Auswertung sie kennt
alter table public.inspection_items add column if not exists min_value numeric;
alter table public.inspection_items add column if not exists max_value numeric;

-- Ergebnis der automatischen Auswertung
alter table public.inspections add column if not exists analysis jsonb;

-- Fingerabdruck ueber die abgeschlossene Begehung, um spaetere Aenderungen sichtbar zu machen
alter table public.inspections add column if not exists integrity_hash text;
alter table public.inspections add column if not exists integrity_at   timestamptz;

-- Freie Gebaeudekonfiguration
alter table public.properties add column if not exists rooms_count    integer;
alter table public.properties add column if not exists corridor_count integer;
alter table public.properties add column if not exists basement_count integer;

alter table public.templates enable row level security;
alter table public.template_criteria enable row level security;

drop policy if exists templates_select on public.templates;
create policy templates_select on public.templates for select to authenticated using (public.is_active_user());
drop policy if exists templates_insert on public.templates;
create policy templates_insert on public.templates for insert to authenticated with check (public.is_active_user());
drop policy if exists templates_update on public.templates;
create policy templates_update on public.templates for update to authenticated
  using (public.is_admin() or created_by = (select auth.uid()))
  with check (public.is_admin() or created_by = (select auth.uid()));
drop policy if exists templates_delete on public.templates;
create policy templates_delete on public.templates for delete to authenticated
  using ((public.is_admin() or created_by = (select auth.uid())) and is_system = false);

drop policy if exists template_criteria_select on public.template_criteria;
create policy template_criteria_select on public.template_criteria for select to authenticated using (public.is_active_user());
drop policy if exists template_criteria_insert on public.template_criteria;
create policy template_criteria_insert on public.template_criteria for insert to authenticated with check (public.is_active_user());
drop policy if exists template_criteria_delete on public.template_criteria;
create policy template_criteria_delete on public.template_criteria for delete to authenticated using (public.is_active_user());

-- ---------------------------------------------------------------------
-- 8. Sieben Standard-Kataloge
-- ---------------------------------------------------------------------
insert into public.templates (name, description, icon, object_types, sort_order, is_system)
select * from (values
('Einzimmerwohnung, Kompaktcheck','Das Wesentliche für eine kleine Mieteinheit. Kurz, sicherheitsorientiert, in etwa 15 Minuten machbar.','🚪',
  array['einzimmerwohnung'],10,true),
('Wohnung','Vollständige Prüfung einer einzelnen Wohnung ohne Gebäudetechnik.','🏢',
  array['wohnung','einzimmerwohnung'],20,true),
('Einfamilienhaus','Haus mit eigenem Grundstück: Gebäudehülle, Technik, Innenräume und Außenanlagen.','🏡',
  array['einfamilienhaus','doppelhaus','reihenhaus'],30,true),
('Mehrfamilienhaus und Wohnanlage','Gebäude und Allgemeinbereiche. Einzelne Wohnungen werden separat geprüft.','🏘️',
  array['mehrfamilienhaus','wohnanlage'],40,true),
('Gewerbeobjekt','Schwerpunkt Betreiberpflichten, Brandschutz, Technik und Verkehrssicherung.','🏬',
  array['gewerbe'],50,true),
('Sicherheits-Schnellcheck','Nur die sicherheitskritischen Punkte. Für die Runde zwischendurch oder nach einem Vorfall.','⚡',
  array['einzimmerwohnung','wohnung','einfamilienhaus','doppelhaus','reihenhaus','mehrfamilienhaus','wohnanlage','gewerbe','sonstiges'],60,true),
('Vollständige Prüfung','Alle Prüfpunkte. Für Übernahmen, Ankauf oder die große Jahresrunde.','📚',
  array['einzimmerwohnung','wohnung','einfamilienhaus','doppelhaus','reihenhaus','mehrfamilienhaus','wohnanlage','gewerbe','sonstiges'],70,true)
) as v(name, description, icon, object_types, sort_order, is_system)
where not exists (select 1 from public.templates t where t.name = v.name);

insert into public.template_criteria (template_id, criterion_id)
select t.id, k.id from public.templates t, public.criteria k
where t.name = 'Vollständige Prüfung' and k.is_system
on conflict do nothing;

insert into public.template_criteria (template_id, criterion_id)
select t.id, k.id
from public.templates t
join public.criteria k on k.is_system
join public.categories c on c.id = k.category_id
where t.name = 'Mehrfamilienhaus und Wohnanlage'
  and c.key not in ('innen','kueche') and k.scope in ('gebaeude','beide')
on conflict do nothing;

insert into public.template_criteria (template_id, criterion_id)
select t.id, k.id
from public.templates t
join public.criteria k on k.is_system
join public.categories c on c.id = k.category_id
where t.name = 'Einfamilienhaus'
  and c.key not in ('gemeinschaft')
  and k.name not like 'Aufzug%'
  and k.name not like '%Brandschutzordnung%'
  and k.name not like '%Legionellenprüfung%'
on conflict do nothing;

insert into public.template_criteria (template_id, criterion_id)
select t.id, k.id
from public.templates t
join public.criteria k on k.is_system
join public.categories c on c.id = k.category_id
where t.name = 'Wohnung'
  and c.key in ('allgemein','fenster','elektro','heizung','sanitaer','brandschutz','sicherheit','schimmel','schadstoffe','innen','kueche','dokumente','mietverhaeltnis')
  and k.scope in ('einheit','beide')
on conflict do nothing;

insert into public.template_criteria (template_id, criterion_id)
select t.id, k.id
from public.templates t
join public.criteria k on k.is_system
join public.categories c on c.id = k.category_id
where t.name = 'Einzimmerwohnung, Kompaktcheck'
  and k.scope in ('einheit','beide')
  and (
    (k.critical and c.key in ('elektro','heizung','sanitaer','brandschutz','sicherheit','schimmel','schadstoffe','fenster','kueche'))
    or (c.key = 'innen' and k.sort_order <= 40)
    or (c.key = 'kueche' and k.sort_order <= 30)
    or (c.key = 'schimmel' and k.sort_order <= 40)
    or (c.key = 'mietverhaeltnis' and k.sort_order <= 30)
  )
on conflict do nothing;

insert into public.template_criteria (template_id, criterion_id)
select t.id, k.id
from public.templates t
join public.criteria k on k.is_system
join public.categories c on c.id = k.category_id
where t.name = 'Sicherheits-Schnellcheck'
  and k.critical and c.key in ('brandschutz','elektro','heizung','sicherheit')
on conflict do nothing;

insert into public.template_criteria (template_id, criterion_id)
select t.id, k.id
from public.templates t
join public.criteria k on k.is_system
join public.categories c on c.id = k.category_id
where t.name = 'Gewerbeobjekt'
  and c.key not in ('kueche','innen','mietverhaeltnis','schimmel')
  and k.scope in ('gebaeude','beide')
on conflict do nothing;

-- ---------------------------------------------------------------------
-- Fertig. Kontrolle:
-- ---------------------------------------------------------------------
select (select count(*) from public.categories) as kategorien,
       (select count(*) from public.criteria)   as pruefpunkte,
       (select count(*) from public.templates)  as vorlagen;
