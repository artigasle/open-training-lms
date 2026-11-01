-- Execute once in Supabase SQL Editor. Run before inviting users.
create extension if not exists pgcrypto;
create table public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 email text not null,
 display_name text not null default '',
 role text not null default 'learner' check(role in ('system_admin','training_admin','instructor','learner')),
 created_at timestamptz not null default now()
);
create table public.courses (
 id uuid primary key default gen_random_uuid(),
 title text not null, description text not null default '',category text not null default 'General',
 status text not null default 'draft' check(status in ('draft','published')),
 owner_id uuid not null references public.profiles(id),
 created_at timestamptz not null default now()
);
create table public.lessons (
 id uuid primary key default gen_random_uuid(), course_id uuid not null references public.courses(id) on delete cascade,
 position integer not null, title text not null, body text not null default '',
 slide_data jsonb not null default '[]'::jsonb,
 unique(course_id,position)
);
create table public.questions (
 id uuid primary key default gen_random_uuid(), course_id uuid not null references public.courses(id) on delete cascade,
 position integer not null, prompt text not null, options jsonb not null,
 correct_index integer not null check(correct_index>=0 and correct_index<4),
 unique(course_id,position)
);
create table public.enrollments (
 id uuid primary key default gen_random_uuid(),course_id uuid not null references public.courses(id) on delete cascade,
 learner_id uuid not null references public.profiles(id) on delete cascade,
 assigned_by uuid references public.profiles(id), assigned_at timestamptz default now(),
 unique(course_id,learner_id)
);
create table public.lesson_completions (
 lesson_id uuid not null references public.lessons(id) on delete cascade,
 learner_id uuid not null references public.profiles(id) on delete cascade,
 completed_at timestamptz not null default now(),primary key(lesson_id,learner_id)
);
create table public.quiz_attempts (
 id uuid primary key default gen_random_uuid(),course_id uuid not null references public.courses(id) on delete cascade,
 learner_id uuid not null references public.profiles(id) on delete cascade,
 answers jsonb not null,score integer not null check(score between 0 and 100),passed boolean not null,
 submitted_at timestamptz not null default now()
);
create function public.new_profile() returns trigger language plpgsql security definer set search_path = '' as $$
begin insert into public.profiles(id,email,display_name) values(new.id,coalesce(new.email,''),coalesce(new.raw_user_meta_data->>'display_name','')); return new; end $$;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.new_profile();
create function public.my_role() returns text language sql stable security definer set search_path = '' as $$select role from public.profiles where id=(select auth.uid())$$;
create function public.can_author(p_owner uuid) returns boolean language sql stable security definer set search_path = '' as $$select public.my_role() in ('system_admin','training_admin') or (public.my_role()='instructor' and p_owner=(select auth.uid()))$$;
create function public.can_access_course(p_course uuid) returns boolean language sql stable security definer set search_path = '' as $$select exists(select 1 from public.courses c where c.id=p_course and (public.can_author(c.owner_id) or(c.status='published' and (public.my_role() in ('system_admin','training_admin','instructor') or exists(select 1 from public.enrollments e where e.course_id=c.id and e.learner_id=(select auth.uid()))))))$$;
create function public.assign_course(p_course uuid,p_learner uuid) returns void language plpgsql security definer set search_path = '' as $$
begin
 if public.my_role() not in ('system_admin','training_admin','instructor') then raise exception 'Not permitted'; end if;
 if not exists(select 1 from public.courses where id=p_course and status='published' and public.can_author(owner_id)) then raise exception 'Course not available to assign';end if;
 if not exists(select 1 from public.profiles where id=p_learner and role='learner') then raise exception 'Not a learner';end if;
 insert into public.enrollments(course_id,learner_id,assigned_by) values(p_course,p_learner,(select auth.uid())) on conflict(course_id,learner_id) do nothing;
end $$;
create function public.submit_quiz(p_course uuid,p_answers jsonb) returns jsonb language plpgsql security definer set search_path = '' as $$
declare n integer; hits integer; result integer; permitted boolean;
begin
 select exists(select 1 from public.enrollments where course_id=p_course and learner_id=(select auth.uid())) into permitted;
 if not permitted then raise exception 'Not enrolled'; end if;
 select count(*) into n from public.questions where course_id=p_course;
 if n=0 or jsonb_typeof(p_answers)<>'array' or jsonb_array_length(p_answers)<>n then raise exception 'Invalid answers';end if;
 select count(*) into hits from (select correct_index,row_number() over(order by position)-1 idx from public.questions where course_id=p_course) q where p_answers->>q.idx::int ~ '^[0-3]$' and (p_answers->>q.idx::int)::int=q.correct_index;
 result:=round(100.0*hits/n);
 insert into public.quiz_attempts(course_id,learner_id,answers,score,passed) values(p_course,(select auth.uid()),p_answers,result,result>=80);
 return jsonb_build_object('score',result,'passed',result>=80);
end $$;
-- Public users are denied by default; authenticated access is explicitly granted via policies.
alter table public.profiles enable row level security;
alter table public.courses enable row level security;
alter table public.lessons enable row level security;
alter table public.questions enable row level security;
alter table public.enrollments enable row level security;
alter table public.lesson_completions enable row level security;
alter table public.quiz_attempts enable row level security;
create policy profiles_read on public.profiles for select to authenticated using(id=(select auth.uid()) or public.my_role() in ('system_admin','training_admin','instructor'));
create policy profiles_admin_update on public.profiles for update to authenticated using(public.my_role()='system_admin') with check(public.my_role()='system_admin');
create policy courses_read on public.courses for select to authenticated using(public.can_access_course(id) or status='published');
create policy courses_create on public.courses for insert to authenticated with check(public.can_author(owner_id) and owner_id=(select auth.uid()));
create policy courses_update on public.courses for update to authenticated using(public.can_author(owner_id)) with check(public.can_author(owner_id));
create policy courses_delete on public.courses for delete to authenticated using(public.can_author(owner_id));
create policy lessons_read on public.lessons for select to authenticated using(public.can_access_course(course_id));
create policy lessons_write on public.lessons for all to authenticated using(exists(select 1 from public.courses c where c.id=course_id and public.can_author(c.owner_id))) with check(exists(select 1 from public.courses c where c.id=course_id and public.can_author(c.owner_id)));
-- Quiz correct answers should not be readable by learners: use RPC to score.
create policy questions_staff_read on public.questions for select to authenticated using(exists(select 1 from public.courses c where c.id=course_id and public.can_author(c.owner_id)));
create policy questions_write on public.questions for all to authenticated using(exists(select 1 from public.courses c where c.id=course_id and public.can_author(c.owner_id))) with check(exists(select 1 from public.courses c where c.id=course_id and public.can_author(c.owner_id)));
create function public.get_quiz(p_course uuid) returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
 if not exists(select 1 from public.enrollments where course_id=p_course and learner_id=(select auth.uid())) then raise exception 'Not enrolled';end if;
 return coalesce((select jsonb_agg(jsonb_build_object('prompt',prompt,'options',options) order by position) from public.questions where course_id=p_course),'[]'::jsonb);
end $$;
create policy enrollments_read on public.enrollments for select to authenticated using(learner_id=(select auth.uid()) or public.my_role() in ('system_admin','training_admin') or exists(select 1 from public.courses c where c.id=course_id and public.can_author(c.owner_id)));
create policy completions_read on public.lesson_completions for select to authenticated using(learner_id=(select auth.uid()) or public.my_role() in ('system_admin','training_admin','instructor'));
create policy completions_insert on public.lesson_completions for insert to authenticated with check(learner_id=(select auth.uid()) and exists(select 1 from public.lessons l join public.enrollments e on e.course_id=l.course_id where l.id=lesson_id and e.learner_id=(select auth.uid())));
create policy attempts_read on public.quiz_attempts for select to authenticated using(learner_id=(select auth.uid()) or public.my_role() in ('system_admin','training_admin','instructor'));
revoke all on function public.assign_course(uuid,uuid) from public;grant execute on function public.assign_course(uuid,uuid) to authenticated;
revoke all on function public.submit_quiz(uuid,jsonb) from public;grant execute on function public.submit_quiz(uuid,jsonb) to authenticated;
revoke all on function public.get_quiz(uuid) from public;grant execute on function public.get_quiz(uuid) to authenticated;
-- Promote the initial system administrator using the SQL Editor only after registering.
-- update public.profiles set role='system_admin' where email='YOUR_EMAIL';