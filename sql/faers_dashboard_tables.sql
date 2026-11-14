
-- These are the new tables that perform heavy computations here instead of doing that in Tableau so that we'll have a better dashboard
-- section 1   Helper tables (These perform very high computations and base for others)

-- 01. Helper_Case_Outcome ( Identify the no.of reported drug-related adverse event cases that resulted in patient deaths)
create table helper_case_outcome as 
select o.primaryid, max(case when o.outc_cod = 'DE' then 1 else 0 end) as is_fatal
from outc o
join demo d 
	on o.primaryid = d.primaryid
group by o.primaryid;

alter table helper_case_outcome add primary key (primaryid);


-- 02. Helper_Ps_Drug - Primary suspect drugs only, restricted to final cases  (Identify which drugs were suspected of causing adverse events in each reported patient case)
create table helper_ps_drug as 
select dr.primaryid, dr.generic_name 
from drug dr
join demo d
	on dr.primaryid = d.primaryid
where dr.is_primary_suspect = 'True';

alter table helper_ps_drug
	add index idx_ps_pid (primaryid),
    add index idx_ps_gn (generic_name);
    
-- ----------------------------------------------------------------------------------
-- section 02. Dashboard Tables (tableau ready, fast)

--                              Dashboard 1 : Overview
-- KPI Table (contains all KPI values like total_cases, serious_cases, total_deaths, fatality_rate_percent, avg_age_years, unique_reactions, unique_suspect_drugs )
create table tb_kpi as 
select 
	(select count(*) from demo ) as total_cases,
    (select count(*) from helper_case_outcome) as serious_cases,
    (select sum(is_fatal) from helper_case_outcome) as total_deaths,
    round(
		(select sum(is_fatal) from helper_case_outcome) * 100 / 
        nullif((select count(*) from helper_case_outcome), 0),2
    ) as fatality_rate_pct,
    (select round(avg(age_years),1) from demo where age_years is not null ) as avg_age_years,
    (select count(distinct r.pt) from reac r join demo d on d.primaryid = r.primaryid) as unique_reactions,
    (select count(distinct generic_name) from helper_ps_drug) as unique_suspect_drugs;
    
    
-- Table Monthly (Reports + Deaths per month across 2025)
create table tb_mothly as
select d.report_month, count(distinct d.primaryid) as total_cases, count(distinct c.primaryid) as serious_cases, coalesce(sum(c.is_fatal),0) as fatal_cases
from demo d
left join helper_case_outcome c 
	on d.primaryid = c.primaryid
where d.report_month like '2020-%'
group by d.report_month
order by d.report_month;


-- Table outcome mix (How many cases per outcome type)
create table tb_outcome_mix as
select 	o.outc_cod,
	case o.outc_cod
		when 'DE' then 'Death'
        when 'HO' then 'Hospitalization'
        when 'LT' then 'Life-Threatening'
		when 'DS' then 'Disability'
		when 'CA' then 'Congenital Anomaly'
		when 'RI' then 'Required Intervention'
        when 'OT' then 'Other Serious'
	end as outcome_label,
    count(distinct o.primaryid ) as cases
from outc o
join demo d
	on d.primaryid = o.primaryid
group by o.outc_cod;


-- Table Reaction (every reaction - total_cases + fatal_cases)
create table tb_reaction as 
select r.pt as reaction, count(distinct r.primaryid) as total_cases, count(distinct case when c.is_fatal = 1 then r.primaryid end) as fatal_cases
from reac r
join demo d
	on r.primaryid = d.primaryid
left join helper_case_outcome c 
	on c.primaryid = r.primaryid
group by r.pt;


-- ----------------------------------------------------------------------

--                 Dasbboard 2 - Drug Safety Signals

-- Table Drug (Drug leader -> volume + Death rate) # min 100 serious cases to avoid the noise from small sample
create table tb_drug as
select p.generic_name, count(distinct p.primaryid) as total_cases, count(distinct c.primaryid) as serious_cases, coalesce(sum(c.is_fatal),0) as fatal_cases,
	round(
		coalesce(sum(c.is_fatal),0) * 100  /
        nullif(count(distinct c.primaryid),0),2
    ) as death_rate
from helper_ps_drug p
left join helper_case_outcome c 
	on c.primaryid = p.primaryid
group by p.generic_name
having count(distinct c.primaryid) >= 100;

-- Table Drug_Reaction: (drug-reaction pairs in fatal cases only (min 10 cases))
create table tb_drug_reaction as 
select p.generic_name, r.pt as reaction, count(distinct p.primaryid) as fatal_cases
from helper_ps_drug p
join helper_case_outcome c
	on c.primaryid = p.primaryid
join reac r 
	on r.primaryid = p.primaryid
group by p.generic_name, r.pt
having count(distinct p.primaryid) >= 10;


-- -----------------------------------------------------------------------------------------------------

--         							  Dashboard 03 : Patient Demographics

-- Table Demographics (Age group * Sex case counts)
create table tb_demographics as
select age_group, sex, count(*) as cases
from demo
group by age_group, sex;


--  Table Demo Outcome (Age group * outcome type counts)
create table tb_demo_outcome as
select d.age_group, case o.outc_cod
		when 'DE' then 'Death'
        when 'HO' then 'Hospitalization'
		when 'LT' then 'Life-Threatening'
		when 'DS' then 'Disability'
		when 'CA' then 'Congenital Anomaly'
		when 'RI' then 'Required Intervention'
        when 'OT' then 'Other Serious'
	end as outcome_label,  
    count(distinct d.primaryid) as cases
from demo d
join outc o
	on d.primaryid = o.primaryid
group by d.age_group, o.outc_cod;


-- -------------------------------------------------------------------------------------------------

--                    Dashboard 04 : Geography & Reporters

-- tb_country : country - total_cases, serious_cases, deaths, death_rate  (min 100 total cases)
create table tb_country as
select d.occr_country, count(distinct d.primaryid) as total_cases, count( distinct c.primaryid) as serious_cases, coalesce(sum(c.is_fatal),0) as fatal_cases, 
		round(
        coalesce(sum(c.is_fatal), 0) * 100 /
        nullif(count(distinct c.primaryid),0),2
        ) as death_rate
from demo d
left join helper_case_outcome c 
	on d.primaryid = c.primaryid
group by d.occr_country
having count(distinct d.primaryid) >= 100;


-- tb_reporter : Reporter type - readable labels, total + death rate
create table tb_reporter as
select 
	case d.occp_cod
		when 'MD' then 'Physician'
        when 'PH' then 'Pharmacist'
        when 'OT' then 'Other Health Professional'
        when 'LW' then 'Lawyer'
        when 'CN' then 'Consumer'
        else 'Unknown'
	end as reporter_type, 
    count(distinct d.primaryid) as total_cases, count(distinct c.primaryid) as serious_cases, coalesce(sum(c.is_fatal),0) as fatal_cases,
    round(
		coalesce(sum(c.is_fatal),0)*100 /
        nullif(count(distinct c.primaryid),0),2
    ) as death_rate
from demo d
join helper_case_outcome c
	on c.primaryid = d.primaryid
group by reporter_type;


-- --------------------------------------------------------------------------------------------

--                    Dashboard 05 : Data Quality & Methodology

create table tb_data_quality (
	step_no INT, metric varchar(150), value varchar(50), note varchar(250)
);
insert into tb_data_quality values
(1,  'Raw DEMO rows loaded (4 quarters)',          '1,617,444',        'Before any cleaning'),
(2,  'Cases removed via FDA DELETE files',         '3,670',            'FDA-flagged invalid cases'),
(3,  'Duplicate case versions removed',            '148,296',          'Kept only latest caseversion per caseid'),
(4,  'Final unique clean cases',                   '1,465,808',        'Base for all analysis'),
(5,  'Implausible ages nulled (> 120 years)',      '30',               '23 were DEC-coded decade entries'),
(6,  'Implausible weights nulled (> 450 kg)',      'Small number',     'Same source-data error pattern as age'),
(7,  'Drug names sent to RxNorm API',              '500',              'Top 500 most frequent names'),
(8,  'Successfully mapped to generic name',        '470 of 500 (94%)', 'RxNorm ingredient lookup'),
(9,  'Drug rows standardized to generic name',     '5,276,680 (67.6%)','Out of 7,801,018 total drug rows'),
(10, 'Unmapped drug rows (kept original name)',    '2,524,338 (32.4%)','Combo drugs, discontinued brands, vague terms');



-- -------------------------------------------------------------------------------------------------------------------------------------------------
-- -------------------------------------------------------------------------------------------------------------------------------------------------

-- 												VERIFICATION

-- kpi no.s
select * from tb_kpi;

-- alter table tb_mothly rename to tb_monthly;


-- row counts for all the tables

select 'helper_case_outcome' as table_name, count(*) as row_count from helper_case_outcome
union all select 'helper_ps_drug', count(*) from helper_ps_drug
union all select 'tb_kpi', count(*) from tb_kpi
union all select 'tb_monthly', count(*) from tb_monthly
union all select 'tb_outcome_mix', count(*) from tb_outcome_mix
union all select 'tb_reaction', count(*) from tb_reaction
union all select 'tb_drug', count(*) from tb_drug
union all select 'tb_drug_reaction', count(*) from tb_drug_reaction
union all select 'tb_demographics', count(*) from tb_demographics
union all select 'tb_demo_outcome', count(*) from tb_demo_outcome
union all select 'tb_country', count(*) from tb_country
union all select 'tb_reporter', count(*) from tb_reporter
union all select 'tb_data_quality', count(*) from tb_data_quality;

--   -----------------------------------------------------------------------------------------------------------------------------------------------------------

USE faers_2025;
SET SQL_SAFE_UPDATES = 0;

-- Fix 1: blank ages were loaded as 0, so restore NULL
UPDATE demo SET age_years = NULL WHERE age_cod = '' OR age_cod IS NULL;
UPDATE demo SET age_years = NULL WHERE age_years = 0 AND age > 0;

UPDATE tb_kpi
SET avg_age_years = (SELECT ROUND(AVG(age_years), 1) FROM demo WHERE age_years IS NOT NULL);

-- Fix 2: rebuild tb_monthly with the right year
DROP TABLE IF EXISTS tb_mothly;
DROP TABLE IF EXISTS tb_monthly;
CREATE TABLE tb_monthly AS
SELECT
    d.report_month,
    COUNT(DISTINCT d.primaryid)  AS total_cases,
    COUNT(DISTINCT c.primaryid)  AS serious_cases,
    COALESCE(SUM(c.is_fatal), 0) AS fatal_cases
FROM demo d
LEFT JOIN helper_case_outcome c ON c.primaryid = d.primaryid
WHERE d.report_month LIKE '2025-%'
GROUP BY d.report_month;

-- Fix 3: rebuild tb_reporter with LEFT JOIN
DROP TABLE IF EXISTS tb_reporter;
CREATE TABLE tb_reporter AS
SELECT
    CASE d.occp_cod
        WHEN 'MD' THEN 'Physician'
        WHEN 'PH' THEN 'Pharmacist'
        WHEN 'OT' THEN 'Other Health Professional'
        WHEN 'LW' THEN 'Lawyer'
        WHEN 'CN' THEN 'Consumer'
        ELSE 'Unknown'
    END                          AS reporter_type,
    COUNT(DISTINCT d.primaryid)  AS total_cases,
    COUNT(DISTINCT c.primaryid)  AS serious_cases,
    COALESCE(SUM(c.is_fatal), 0) AS fatal_cases,
    ROUND(COALESCE(SUM(c.is_fatal), 0) * 100 / NULLIF(COUNT(DISTINCT c.primaryid), 0), 2) AS death_rate
FROM demo d
LEFT JOIN helper_case_outcome c ON c.primaryid = d.primaryid
GROUP BY reporter_type;

-- Fix 4: data quality table corrections
UPDATE tb_data_quality SET value = '147,966' WHERE step_no = 3;
UPDATE tb_data_quality
SET metric = 'Cases with unknown age (left as missing)',
    value  = (SELECT FORMAT(COUNT(*), 0) FROM demo WHERE age_years IS NULL),
    note   = 'Not guessed or imputed'
WHERE step_no = 6;

-- Fix 5: label the blank country
UPDATE tb_country SET occr_country = 'Unknown' WHERE occr_country = '' OR occr_country IS NULL;

-- Verify
SELECT * FROM tb_kpi;
SELECT * FROM tb_monthly ORDER BY report_month;
SELECT * FROM tb_reporter;
SELECT SUM(cases) AS demographics_total FROM tb_demographics;
SELECT step_no, metric, value FROM tb_data_quality ORDER BY step_no;


SELECT * FROM tb_kpi;
SELECT * FROM tb_monthly ORDER BY report_month;
SELECT * FROM tb_reporter;
SELECT SUM(cases) AS demographics_total FROM tb_demographics;
SELECT step_no, metric, value FROM tb_data_quality ORDER BY step_no;







SELECT generic_name FROM tb_drug ORDER BY generic_name LIMIT 30;
SELECT generic_name FROM tb_drug_reaction ORDER BY generic_name LIMIT 30;

UPDATE tb_drug SET generic_name = LOWER(generic_name);
UPDATE tb_drug_reaction SET generic_name = LOWER(generic_name);

SELECT generic_name FROM tb_drug WHERE generic_name = 'fentanyl';
SELECT generic_name FROM tb_drug_reaction WHERE generic_name = 'fentanyl';

SELECT generic_name FROM tb_drug ORDER BY death_rate DESC LIMIT 5;
SELECT generic_name FROM tb_drug_reaction ORDER BY fatal_cases DESC LIMIT 5;

SELECT generic_name, total_cases, serious_cases, fatal_cases, death_rate
FROM tb_drug
ORDER BY death_rate DESC
LIMIT 10;

SELECT generic_name, reaction, fatal_cases
FROM tb_drug_reaction
ORDER BY fatal_cases DESC
LIMIT 10;

SELECT 'tb_drug' AS source, generic_name FROM tb_drug WHERE generic_name = 'fentanyl'
UNION ALL
SELECT 'tb_drug_reaction', generic_name FROM tb_drug_reaction WHERE generic_name = 'fentanyl' LIMIT 5;


DROP TABLE IF EXISTS tb_drug_reaction;
CREATE TABLE tb_drug_reaction AS
SELECT
    p.generic_name,
    r.pt AS reaction,
    COUNT(DISTINCT p.primaryid) AS fatal_cases,
    RANK() OVER (
        PARTITION BY p.generic_name
        ORDER BY COUNT(DISTINCT p.primaryid) DESC
    ) AS reaction_rank
FROM helper_ps_drug p
JOIN helper_case_outcome c ON c.primaryid = p.primaryid AND c.is_fatal = 1
JOIN reac r ON r.primaryid = p.primaryid
GROUP BY p.generic_name, r.pt
HAVING COUNT(DISTINCT p.primaryid) >= 10;

-- Verify: check vedolizumab's top reactions now
SELECT generic_name, reaction, fatal_cases, reaction_rank
FROM tb_drug_reaction
WHERE generic_name = 'vedolizumab'
ORDER BY reaction_rank
LIMIT 5;

-- Verify: check a leaderboard drug
SELECT generic_name, reaction, fatal_cases, reaction_rank
FROM tb_drug_reaction
WHERE generic_name = 'fentanyl'
ORDER BY reaction_rank
LIMIT 5;


------------------------------------------

DROP TABLE IF EXISTS tb_drug_reaction;
CREATE TABLE tb_drug_reaction AS
WITH drug_totals AS (
    SELECT generic_name,
           SUM(fatal_cases) AS drug_total_fatal
    FROM (
        SELECT p.generic_name,
               COUNT(DISTINCT p.primaryid) AS fatal_cases
        FROM helper_ps_drug p
        JOIN helper_case_outcome c ON c.primaryid = p.primaryid AND c.is_fatal = 1
        GROUP BY p.generic_name
    ) base
    GROUP BY generic_name
),
drug_ranked AS (
    SELECT generic_name,
           drug_total_fatal,
           RANK() OVER (ORDER BY drug_total_fatal DESC) AS drug_rank
    FROM drug_totals
),
reaction_ranked AS (
    SELECT
        p.generic_name,
        r.pt AS reaction,
        COUNT(DISTINCT p.primaryid) AS fatal_cases,
        RANK() OVER (
            PARTITION BY p.generic_name
            ORDER BY COUNT(DISTINCT p.primaryid) DESC
        ) AS reaction_rank
    FROM helper_ps_drug p
    JOIN helper_case_outcome c ON c.primaryid = p.primaryid AND c.is_fatal = 1
    JOIN reac r ON r.primaryid = p.primaryid
    GROUP BY p.generic_name, r.pt
    HAVING COUNT(DISTINCT p.primaryid) >= 10
)
SELECT
    rr.generic_name,
    rr.reaction,
    rr.fatal_cases,
    rr.reaction_rank,
    dr.drug_rank,
    dr.drug_total_fatal
FROM reaction_ranked rr
JOIN drug_ranked dr ON dr.generic_name = rr.generic_name;

-- Verify: top 5 drugs by drug_rank
SELECT DISTINCT generic_name, drug_rank, drug_total_fatal
FROM tb_drug_reaction
ORDER BY drug_rank
LIMIT 5;

-- Verify: fentanyl's top 3 reactions still correct
SELECT generic_name, reaction, fatal_cases, reaction_rank, drug_rank
FROM tb_drug_reaction
WHERE generic_name = 'fentanyl'
ORDER BY reaction_rank
LIMIT 3;