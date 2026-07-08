


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE SCHEMA IF NOT EXISTS "public";


ALTER SCHEMA "public" OWNER TO "pg_database_owner";


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE TYPE "public"."credit_modality" AS ENUM (
    'CONVENCIONAL',
    'INTELIGENTE'
);


ALTER TYPE "public"."credit_modality" OWNER TO "postgres";


CREATE TYPE "public"."currency_code" AS ENUM (
    'PEN',
    'USD'
);


ALTER TYPE "public"."currency_code" OWNER TO "postgres";


CREATE TYPE "public"."grace_type" AS ENUM (
    'NINGUNO',
    'PARCIAL',
    'TOTAL'
);


ALTER TYPE "public"."grace_type" OWNER TO "postgres";


CREATE TYPE "public"."initial_payment_mode" AS ENUM (
    'MONTO',
    'PORCENTAJE'
);


ALTER TYPE "public"."initial_payment_mode" OWNER TO "postgres";


CREATE TYPE "public"."rate_type" AS ENUM (
    'TEA',
    'TEM'
);


ALTER TYPE "public"."rate_type" OWNER TO "postgres";


CREATE TYPE "public"."simulation_status" AS ENUM (
    'BORRADOR',
    'ENVIADA',
    'CONTACTADO'
);


ALTER TYPE "public"."simulation_status" OWNER TO "postgres";


CREATE TYPE "public"."user_role" AS ENUM (
    'ADMIN',
    'USER'
);


ALTER TYPE "public"."user_role" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_new_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
begin
  insert into public.profiles (id, email, first_name, last_name, role)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'first_name', ''),
    coalesce(new.raw_user_meta_data->>'last_name', ''),
    'USER'
  );
  return new;
end;
$$;


ALTER FUNCTION "public"."handle_new_user"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_admin"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    AS $$
  select exists (
    select 1 from profiles
    where id = auth.uid() and role = 'ADMIN'
  );
$$;


ALTER FUNCTION "public"."is_admin"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  new.updated_at = now();
  return new;
end;
$$;


ALTER FUNCTION "public"."set_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."simular_credito"("p_modality" "public"."credit_modality", "p_currency" "public"."currency_code", "p_vehicle_price" numeric, "p_initial_payment_mode" "public"."initial_payment_mode", "p_initial_payment_input" numeric, "p_rate_type_input" "public"."rate_type", "p_rate_input" numeric, "p_loan_term_months" integer, "p_grace_type" "public"."grace_type" DEFAULT 'NINGUNO'::"public"."grace_type", "p_grace_months" integer DEFAULT 0, "p_residual_value_pct" numeric DEFAULT NULL::numeric, "p_vehicle_id" integer DEFAULT NULL::integer) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
declare
  v_user_id               uuid := auth.uid();
  v_params                constant_parameters%rowtype;
  v_tem                    numeric(15,10);
  v_initial_amount         numeric(15,2);
  v_initial_pct            numeric(5,2);
  v_residual_amount        numeric(15,2) := 0;
  v_residual_pct           numeric(5,2) := 0;
  v_financed_amount        numeric(15,2);
  v_saldo_a_financiar      numeric(15,2); -- para INTELIGENTE, excluye VP del balón
  v_simulation_id           uuid;

  v_max_total_grace        int;
  v_max_partial_grace       int;
  v_years                   numeric;

  v_n                        int;   -- cuotas regulares (sin contar balón)
  v_saldo                    numeric(15,6);
  v_interes                  numeric(15,6);
  v_amort                    numeric(15,6);
  v_cuota_capital             numeric(15,6); -- solo la parte de capital+interés (sin seguros)
  v_seg_desg                  numeric(15,6);
  v_seg_veh                   numeric(15,6);
  v_gps                       numeric(15,6);
  v_portes                    numeric(15,6);
  v_gasadm                    numeric(15,6);
  v_total_cuota               numeric(15,6);
  v_saldo_final                numeric(15,6);
  v_grace_this_installment      grace_type;
  v_cuotas_restantes            int;

  v_total_interest              numeric(15,2) := 0;
  v_total_paid                   numeric(15,2) := 0;
  v_flows                        numeric[] := array[]::numeric[];
  i                                int;
begin
  if v_user_id is null then
    raise exception 'No autenticado';
  end if;

  select * into v_params from constant_parameters where id = 1;

  -- ------------------------------------------------------------
  -- 1) Validar plazos permitidos por modalidad
  -- ------------------------------------------------------------
  if p_modality = 'CONVENCIONAL' then
    if p_loan_term_months not in (12, 24, 36, 48, 60, 72) then
      raise exception 'Plazo inválido para crédito convencional. Use 12, 24, 36, 48, 60 o 72 meses.';
    end if;
  elsif p_modality = 'INTELIGENTE' then
    if p_loan_term_months not in (25, 37) then
      raise exception 'Plazo inválido para crédito inteligente. Use 25 o 37 meses.';
    end if;
    if p_residual_value_pct is null or p_residual_value_pct <= 0 or p_residual_value_pct >= 1 then
      raise exception 'Debe indicar %% de valor residual (cuota balón) entre 0 y 1 para crédito inteligente.';
    end if;
  end if;

  -- ------------------------------------------------------------
  -- 2) Validar período de gracia: máx 1 año TOTAL, 2 años PARCIAL
  --    por cada año de plazo (ej: 48 meses = 4 años -> máx 4 TOTAL / 8 PARCIAL)
  -- ------------------------------------------------------------
  v_years := p_loan_term_months / 12.0;
  v_max_total_grace := floor(v_years * 1) * 12;    -- 1 año de gracia total por año de plazo... 
  -- Nota: interpretamos "1*años" como máx 1 mes de gracia TOTAL por cada año de plazo,
  -- y "2*años" como máx 2 meses de gracia PARCIAL por cada año de plazo.
  v_max_total_grace := floor(v_years) * 1;
  v_max_partial_grace := floor(v_years) * 2;

  if p_grace_type = 'TOTAL' and p_grace_months > v_max_total_grace then
    raise exception 'Máximo % meses de gracia total permitidos para un plazo de % meses.', v_max_total_grace, p_loan_term_months;
  end if;
  if p_grace_type = 'PARCIAL' and p_grace_months > v_max_partial_grace then
    raise exception 'Máximo % meses de gracia parcial permitidos para un plazo de % meses.', v_max_partial_grace, p_loan_term_months;
  end if;
  if p_grace_type = 'NINGUNO' and p_grace_months > 0 then
    p_grace_months := 0;
  end if;
  if p_grace_months >= p_loan_term_months then
    raise exception 'El período de gracia no puede cubrir todas las cuotas.';
  end if;

  -- ------------------------------------------------------------
  -- 3) Resolver TEM a partir de TEA o TEM ingresada
  -- ------------------------------------------------------------
  if p_rate_type_input = 'TEA' then
    v_tem := power(1 + p_rate_input, 1.0/12.0) - 1;
  else
    v_tem := p_rate_input;
  end if;

  -- ------------------------------------------------------------
  -- 4) Resolver cuota inicial (monto <-> %)
  -- ------------------------------------------------------------
  if p_initial_payment_mode = 'MONTO' then
    v_initial_amount := p_initial_payment_input;
    v_initial_pct := round((v_initial_amount / p_vehicle_price) * 100, 2);
  else
    v_initial_pct := p_initial_payment_input;
    v_initial_amount := round(p_vehicle_price * (v_initial_pct / 100.0), 2);
  end if;

  -- ------------------------------------------------------------
  -- 5) Resolver valor residual (solo INTELIGENTE) y monto a financiar
  -- ------------------------------------------------------------
  v_financed_amount := p_vehicle_price - v_initial_amount;

  if p_modality = 'INTELIGENTE' then
    v_residual_pct := p_residual_value_pct * 100;
    v_residual_amount := round(p_vehicle_price * p_residual_value_pct, 2);
    -- Saldo a financiar con cuotas regulares = financiado - VP(cuota balón)
    v_saldo_a_financiar := v_financed_amount - (v_residual_amount / power(1 + v_tem, p_loan_term_months));
    v_n := p_loan_term_months - 1; -- la última posición es la cuota balón
  else
    v_saldo_a_financiar := v_financed_amount;
    v_n := p_loan_term_months;
  end if;

  -- ------------------------------------------------------------
  -- 6) Insertar cabecera de la simulación
  -- ------------------------------------------------------------
  insert into simulations (
    user_id, vehicle_id, modality, currency,
    vehicle_price, initial_payment_mode, initial_payment_input,
    initial_payment_amount, initial_payment_pct,
    residual_value_pct, residual_value_amount,
    financed_amount,
    rate_type_input, rate_input, effective_monthly_rate,
    loan_term_months, grace_type, grace_months,
    seguro_desgravamen_pct, seguro_vehicular_pct, gps_monto,
    portes_monto, gastos_adm_monto, cok_anual,
    status
  ) values (
    v_user_id, p_vehicle_id, p_modality, p_currency,
    p_vehicle_price, p_initial_payment_mode, p_initial_payment_input,
    v_initial_amount, v_initial_pct,
    nullif(v_residual_pct,0), nullif(v_residual_amount,0),
    v_financed_amount,
    p_rate_type_input, p_rate_input, v_tem,
    p_loan_term_months, p_grace_type, p_grace_months,
    v_params.seguro_desgravamen_pct, v_params.seguro_vehicular_pct, v_params.gps_monto,
    v_params.portes_monto, v_params.gastos_adm_monto, v_params.cok_anual,
    'BORRADOR'
  )
  returning id into v_simulation_id;

  -- Fila 0: desembolso
  insert into simulation_installments (
    simulation_id, installment_number, is_balloon, grace_applied,
    initial_balance, final_balance, flow
  ) values (
    v_simulation_id, 0, false, 'NINGUNO',
    v_saldo_a_financiar, v_saldo_a_financiar, -v_saldo_a_financiar
  );
  v_flows := array_append(v_flows, -v_saldo_a_financiar);

  -- ------------------------------------------------------------
  -- 7) Cronograma cuota a cuota (método francés + gracia)
  -- ------------------------------------------------------------
  v_saldo := v_saldo_a_financiar;

  for i in 1..v_n loop
    v_cuotas_restantes := v_n - i + 1;

    if i <= p_grace_months then
      v_grace_this_installment := p_grace_type;
    else
      v_grace_this_installment := 'NINGUNO';
    end if;

    v_interes := v_saldo * v_tem;

    if v_grace_this_installment = 'TOTAL' then
      v_cuota_capital := 0;
      v_amort := 0;
      v_saldo_final := v_saldo + v_interes; -- capitaliza
    elsif v_grace_this_installment = 'PARCIAL' then
      v_cuota_capital := v_interes;
      v_amort := 0;
      v_saldo_final := v_saldo; -- no amortiza, no capitaliza
    else
      -- PMT clásico sobre saldo y cuotas restantes
      v_cuota_capital := (v_saldo * v_tem) / (1 - power(1 + v_tem, -v_cuotas_restantes));
      v_amort := v_cuota_capital - v_interes;
      v_saldo_final := v_saldo - v_amort;
    end if;

    v_seg_desg := v_saldo * v_params.seguro_desgravamen_pct;
    v_seg_veh  := v_saldo * v_params.seguro_vehicular_pct;
    v_gps      := v_params.gps_monto;
    v_portes   := v_params.portes_monto;
    v_gasadm   := v_params.gastos_adm_monto;

    v_total_cuota := v_cuota_capital + v_seg_desg + v_seg_veh + v_gps + v_portes + v_gasadm;

    insert into simulation_installments (
      simulation_id, installment_number, is_balloon, grace_applied,
      initial_balance, interest_amount, amortization,
      insurance_amount, vehicle_insurance_amount, gps_amount,
      portes_amount, admin_fee_amount, total_installment,
      final_balance, flow
    ) values (
      v_simulation_id, i, false, v_grace_this_installment,
      v_saldo, v_interes, v_amort,
      v_seg_desg, v_seg_veh, v_gps,
      v_portes, v_gasadm, v_total_cuota,
      v_saldo_final, v_total_cuota
    );

    v_total_interest := v_total_interest + v_interes;
    v_total_paid := v_total_paid + v_total_cuota;
    v_flows := array_append(v_flows, v_total_cuota);

    v_saldo := v_saldo_final;
  end loop;

  -- ------------------------------------------------------------
  -- 8) Cuota balón (solo INTELIGENTE) - se paga en loan_term_months
  -- ------------------------------------------------------------
  if p_modality = 'INTELIGENTE' then
    v_total_cuota := v_residual_amount;
    insert into simulation_installments (
      simulation_id, installment_number, is_balloon, grace_applied,
      initial_balance, interest_amount, amortization,
      insurance_amount, vehicle_insurance_amount, gps_amount,
      portes_amount, admin_fee_amount, total_installment,
      final_balance, flow
    ) values (
      v_simulation_id, p_loan_term_months, true, 'NINGUNO',
      v_residual_amount, 0, v_residual_amount,
      0, 0, 0, 0, 0, v_residual_amount,
      0, v_residual_amount
    );
    v_total_paid := v_total_paid + v_residual_amount;
    v_flows := array_append(v_flows, v_residual_amount);
  end if;

  -- ------------------------------------------------------------
  -- 9) Indicadores: TIR (aproximación Newton-Raphson simple) y TCEA
  -- ------------------------------------------------------------
  declare
    v_tir numeric := v_tem; -- semilla
    v_npv numeric;
    v_dnpv numeric;
    j int;
    iter int;
  begin
    for iter in 1..100 loop
      v_npv := 0; v_dnpv := 0;
      for j in 1..array_length(v_flows,1) loop
        v_npv := v_npv + v_flows[j] / power(1+v_tir, j-1);
        if j > 1 then
          v_dnpv := v_dnpv - (j-1) * v_flows[j] / power(1+v_tir, j);
        end if;
      end loop;
      exit when abs(v_npv) < 0.0001 or v_dnpv = 0;
      v_tir := v_tir - v_npv / v_dnpv;
    end loop;

    update simulations set
      total_interest = v_total_interest,
      total_amount_paid = v_total_paid,
      tir_mensual = v_tir,
      tcea = power(1+v_tir, 12) - 1,
      van = (
        select sum(f / power(1+v_params.cok_anual/12, idx-1))
        from unnest(v_flows) with ordinality as t(f, idx)
      )
    where id = v_simulation_id;
  end;

  return v_simulation_id;
end;
$$;


ALTER FUNCTION "public"."simular_credito"("p_modality" "public"."credit_modality", "p_currency" "public"."currency_code", "p_vehicle_price" numeric, "p_initial_payment_mode" "public"."initial_payment_mode", "p_initial_payment_input" numeric, "p_rate_type_input" "public"."rate_type", "p_rate_input" numeric, "p_loan_term_months" integer, "p_grace_type" "public"."grace_type", "p_grace_months" integer, "p_residual_value_pct" numeric, "p_vehicle_id" integer) OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."constant_parameters" (
    "id" integer DEFAULT 1 NOT NULL,
    "seguro_desgravamen_pct" numeric(8,6) DEFAULT 0.00049 NOT NULL,
    "seguro_vehicular_pct" numeric(8,6) DEFAULT 0.00300 NOT NULL,
    "gps_monto" numeric(10,2) DEFAULT 20.00 NOT NULL,
    "portes_monto" numeric(10,2) DEFAULT 3.50 NOT NULL,
    "gastos_adm_monto" numeric(10,2) DEFAULT 3.50 NOT NULL,
    "cok_anual" numeric(8,6) DEFAULT 0.10 NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "uuid",
    CONSTRAINT "single_row" CHECK (("id" = 1))
);


ALTER TABLE "public"."constant_parameters" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."profiles" (
    "id" "uuid" NOT NULL,
    "email" "text" NOT NULL,
    "first_name" "text" NOT NULL,
    "last_name" "text" NOT NULL,
    "phone" "text",
    "dni" "text",
    "role" "public"."user_role" DEFAULT 'USER'::"public"."user_role" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."profiles" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."simulation_installments" (
    "id" bigint NOT NULL,
    "simulation_id" "uuid" NOT NULL,
    "installment_number" integer NOT NULL,
    "is_balloon" boolean DEFAULT false NOT NULL,
    "grace_applied" "public"."grace_type" DEFAULT 'NINGUNO'::"public"."grace_type" NOT NULL,
    "initial_balance" numeric(15,6) NOT NULL,
    "interest_amount" numeric(15,6) DEFAULT 0 NOT NULL,
    "amortization" numeric(15,6) DEFAULT 0 NOT NULL,
    "insurance_amount" numeric(15,6) DEFAULT 0 NOT NULL,
    "vehicle_insurance_amount" numeric(15,6) DEFAULT 0 NOT NULL,
    "gps_amount" numeric(15,6) DEFAULT 0 NOT NULL,
    "portes_amount" numeric(15,6) DEFAULT 0 NOT NULL,
    "admin_fee_amount" numeric(15,6) DEFAULT 0 NOT NULL,
    "total_installment" numeric(15,6) DEFAULT 0 NOT NULL,
    "final_balance" numeric(15,6) NOT NULL,
    "flow" numeric(15,6)
);


ALTER TABLE "public"."simulation_installments" OWNER TO "postgres";


ALTER TABLE "public"."simulation_installments" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."simulation_installments_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."simulations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "vehicle_id" integer,
    "modality" "public"."credit_modality" NOT NULL,
    "currency" "public"."currency_code" NOT NULL,
    "vehicle_price" numeric(15,2) NOT NULL,
    "initial_payment_mode" "public"."initial_payment_mode" NOT NULL,
    "initial_payment_input" numeric(15,2) NOT NULL,
    "initial_payment_amount" numeric(15,2) NOT NULL,
    "initial_payment_pct" numeric(5,2) NOT NULL,
    "residual_value_pct" numeric(5,2),
    "residual_value_amount" numeric(15,2),
    "financed_amount" numeric(15,2) NOT NULL,
    "rate_type_input" "public"."rate_type" NOT NULL,
    "rate_input" numeric(10,6) NOT NULL,
    "effective_monthly_rate" numeric(15,10) NOT NULL,
    "loan_term_months" integer NOT NULL,
    "grace_type" "public"."grace_type" DEFAULT 'NINGUNO'::"public"."grace_type" NOT NULL,
    "grace_months" integer DEFAULT 0 NOT NULL,
    "seguro_desgravamen_pct" numeric(8,6) NOT NULL,
    "seguro_vehicular_pct" numeric(8,6) NOT NULL,
    "gps_monto" numeric(10,2) NOT NULL,
    "portes_monto" numeric(10,2) NOT NULL,
    "gastos_adm_monto" numeric(10,2) NOT NULL,
    "cok_anual" numeric(8,6) NOT NULL,
    "total_interest" numeric(15,2),
    "total_amount_paid" numeric(15,2),
    "tir_mensual" numeric(15,10),
    "tcea" numeric(15,10),
    "van" numeric(20,6),
    "status" "public"."simulation_status" DEFAULT 'BORRADOR'::"public"."simulation_status" NOT NULL,
    "contact_note" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."simulations" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."vehicles" (
    "id" integer NOT NULL,
    "brand" "text" NOT NULL,
    "model" "text" NOT NULL,
    "year" integer NOT NULL,
    "version" "text",
    "image_url" "text",
    "list_price_pen" numeric(15,2),
    "list_price_usd" numeric(15,2),
    "default_tea" numeric(10,6) NOT NULL,
    "default_rate_type" "public"."rate_type" DEFAULT 'TEA'::"public"."rate_type" NOT NULL,
    "default_initial_payment_pct" numeric(5,2) DEFAULT 20.00 NOT NULL,
    "is_available" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."vehicles" OWNER TO "postgres";


ALTER TABLE "public"."vehicles" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."vehicles_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



ALTER TABLE ONLY "public"."constant_parameters"
    ADD CONSTRAINT "constant_parameters_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."simulation_installments"
    ADD CONSTRAINT "simulation_installments_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."simulation_installments"
    ADD CONSTRAINT "simulation_installments_simulation_id_installment_number_key" UNIQUE ("simulation_id", "installment_number");



ALTER TABLE ONLY "public"."simulations"
    ADD CONSTRAINT "simulations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."vehicles"
    ADD CONSTRAINT "vehicles_pkey" PRIMARY KEY ("id");



CREATE INDEX "idx_installments_simulation" ON "public"."simulation_installments" USING "btree" ("simulation_id");



CREATE INDEX "idx_simulations_user" ON "public"."simulations" USING "btree" ("user_id");



CREATE INDEX "idx_simulations_vehicle" ON "public"."simulations" USING "btree" ("vehicle_id");



CREATE OR REPLACE TRIGGER "trg_constant_params_updated" BEFORE UPDATE ON "public"."constant_parameters" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_profiles_updated" BEFORE UPDATE ON "public"."profiles" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_vehicles_updated" BEFORE UPDATE ON "public"."vehicles" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



ALTER TABLE ONLY "public"."constant_parameters"
    ADD CONSTRAINT "constant_parameters_updated_by_fkey" FOREIGN KEY ("updated_by") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."simulation_installments"
    ADD CONSTRAINT "simulation_installments_simulation_id_fkey" FOREIGN KEY ("simulation_id") REFERENCES "public"."simulations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."simulations"
    ADD CONSTRAINT "simulations_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."simulations"
    ADD CONSTRAINT "simulations_vehicle_id_fkey" FOREIGN KEY ("vehicle_id") REFERENCES "public"."vehicles"("id");



ALTER TABLE "public"."constant_parameters" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."profiles" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."simulation_installments" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."simulations" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "solo admin borra vehiculos" ON "public"."vehicles" FOR DELETE USING ("public"."is_admin"());



CREATE POLICY "solo admin edita parametros" ON "public"."constant_parameters" FOR UPDATE USING ("public"."is_admin"());



CREATE POLICY "solo admin edita vehiculos" ON "public"."vehicles" FOR UPDATE USING ("public"."is_admin"());



CREATE POLICY "solo admin inserta vehiculos" ON "public"."vehicles" FOR INSERT WITH CHECK ("public"."is_admin"());



CREATE POLICY "todos leen parametros" ON "public"."constant_parameters" FOR SELECT USING (true);



CREATE POLICY "todos leen vehiculos" ON "public"."vehicles" FOR SELECT USING (true);



CREATE POLICY "usuarios actualizan sus simulaciones (enviar/contactar)" ON "public"."simulations" FOR UPDATE USING ((("user_id" = "auth"."uid"()) OR "public"."is_admin"()));



CREATE POLICY "usuarios crean sus simulaciones" ON "public"."simulations" FOR INSERT WITH CHECK (("user_id" = "auth"."uid"()));



CREATE POLICY "usuarios editan su propio perfil" ON "public"."profiles" FOR UPDATE USING ((("id" = "auth"."uid"()) OR "public"."is_admin"()));



CREATE POLICY "usuarios ven su propio perfil" ON "public"."profiles" FOR SELECT USING ((("id" = "auth"."uid"()) OR "public"."is_admin"()));



CREATE POLICY "usuarios ven sus simulaciones" ON "public"."simulations" FOR SELECT USING ((("user_id" = "auth"."uid"()) OR "public"."is_admin"()));



ALTER TABLE "public"."vehicles" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "ver cronograma si se ve la simulacion" ON "public"."simulation_installments" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."simulations" "s"
  WHERE (("s"."id" = "simulation_installments"."simulation_id") AND (("s"."user_id" = "auth"."uid"()) OR "public"."is_admin"())))));



GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "service_role";



GRANT ALL ON FUNCTION "public"."is_admin"() TO "anon";
GRANT ALL ON FUNCTION "public"."is_admin"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_admin"() TO "service_role";



GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "service_role";



GRANT ALL ON FUNCTION "public"."simular_credito"("p_modality" "public"."credit_modality", "p_currency" "public"."currency_code", "p_vehicle_price" numeric, "p_initial_payment_mode" "public"."initial_payment_mode", "p_initial_payment_input" numeric, "p_rate_type_input" "public"."rate_type", "p_rate_input" numeric, "p_loan_term_months" integer, "p_grace_type" "public"."grace_type", "p_grace_months" integer, "p_residual_value_pct" numeric, "p_vehicle_id" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."simular_credito"("p_modality" "public"."credit_modality", "p_currency" "public"."currency_code", "p_vehicle_price" numeric, "p_initial_payment_mode" "public"."initial_payment_mode", "p_initial_payment_input" numeric, "p_rate_type_input" "public"."rate_type", "p_rate_input" numeric, "p_loan_term_months" integer, "p_grace_type" "public"."grace_type", "p_grace_months" integer, "p_residual_value_pct" numeric, "p_vehicle_id" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."simular_credito"("p_modality" "public"."credit_modality", "p_currency" "public"."currency_code", "p_vehicle_price" numeric, "p_initial_payment_mode" "public"."initial_payment_mode", "p_initial_payment_input" numeric, "p_rate_type_input" "public"."rate_type", "p_rate_input" numeric, "p_loan_term_months" integer, "p_grace_type" "public"."grace_type", "p_grace_months" integer, "p_residual_value_pct" numeric, "p_vehicle_id" integer) TO "service_role";



GRANT ALL ON TABLE "public"."constant_parameters" TO "anon";
GRANT ALL ON TABLE "public"."constant_parameters" TO "authenticated";
GRANT ALL ON TABLE "public"."constant_parameters" TO "service_role";



GRANT ALL ON TABLE "public"."profiles" TO "anon";
GRANT ALL ON TABLE "public"."profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."profiles" TO "service_role";



GRANT ALL ON TABLE "public"."simulation_installments" TO "anon";
GRANT ALL ON TABLE "public"."simulation_installments" TO "authenticated";
GRANT ALL ON TABLE "public"."simulation_installments" TO "service_role";



GRANT ALL ON SEQUENCE "public"."simulation_installments_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."simulation_installments_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."simulation_installments_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."simulations" TO "anon";
GRANT ALL ON TABLE "public"."simulations" TO "authenticated";
GRANT ALL ON TABLE "public"."simulations" TO "service_role";



GRANT ALL ON TABLE "public"."vehicles" TO "anon";
GRANT ALL ON TABLE "public"."vehicles" TO "authenticated";
GRANT ALL ON TABLE "public"."vehicles" TO "service_role";



GRANT ALL ON SEQUENCE "public"."vehicles_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."vehicles_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."vehicles_id_seq" TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";







