CREATE TABLE drug (
    primaryid BIGINT,
    caseid BIGINT,
    drug_seq INT,
    role_cod VARCHAR(5),
    drugname VARCHAR(255),
    prod_ai VARCHAR(255),
    val_vbm VARCHAR(5),
    route VARCHAR(100),
    dose_vbm VARCHAR(255),
    cum_dose_chr FLOAT,
    cum_dose_unit VARCHAR(20),
    dechal VARCHAR(5),
    rechal VARCHAR(5),
    lot_num VARCHAR(100),
    exp_dt VARCHAR(10),
    nda_num VARCHAR(20),
    dose_amt FLOAT,
    dose_unit VARCHAR(20),
    dose_form VARCHAR(50),
    dose_freq VARCHAR(20),
    drugname_clean VARCHAR(255),
    generic_name VARCHAR(255),
    is_primary_suspect VARCHAR(5)
);

CREATE TABLE reac (
    primaryid BIGINT,
    caseid BIGINT,
    pt VARCHAR(255)
);

CREATE TABLE outc (
    primaryid BIGINT,
    caseid BIGINT,
    outc_cod VARCHAR(5),
    is_death VARCHAR(5)
);

CREATE TABLE ther (
    primaryid BIGINT,
    caseid BIGINT,
    dsg_drug_seq INT,
    start_dt VARCHAR(10),
    end_dt VARCHAR(10),
    dur FLOAT,
    dur_cod VARCHAR(10)
);

CREATE TABLE indi (
    primaryid BIGINT,
    caseid BIGINT,
    indi_drug_seq INT,
    indi_pt VARCHAR(255)
);

CREATE TABLE rpsr (
    primaryid BIGINT,
    caseid BIGINT,
    rpsr_cod VARCHAR(5)
);

SHOW TABLES;

select count(*)
from ther;

--  1.Attaching reactions to the case's outcomes
select r.pt, count(*) as reaction_count
from reac r
join outc o 	
	on r.primaryid = o.primaryid
where o.is_death = 'True'
group by r.pt
order by reaction_count desc
limit 15;


-- 2. top primary-suspect drugs specifically in fatal cases
select d.generic_name, count(distinct d.primaryid) as fatal_case_count
from drug d
join outc o
	on d.primaryid = o.primaryid
where o.is_death='True' and d.is_primary_suspect = 'True'
group by d.generic_name
order by fatal_case_count desc
limit 15;


-- 3. Reactions most associated with fatal cases
-- Which adverse reactions appear most often in cases where the outcome was death?
select r.pt, count(r.pt) as case_count
from reac r
join outc o
	on r.primaryid = o.primaryid
where o.is_death = 'True'
group by r.pt
order by case_count desc
limit 15;


-- 4. Drug classes with disproportionate fatal outcomes
-- Which primary-suspect drugs have a death appearing in more than, say, 15% of their total case reports?
select d.generic_name,  count(distinct d.primaryid) as total_cases,
	count(distinct case
		when o.is_death='True'
        then d.primaryid
        end ) as fatal_cases,
        round(
			count(distinct case 
				when o.is_death = 'True'
                then d.primaryid
                end ) *100 / count(distinct d.primaryid),2 
        ) as death_rate
from drug d
join outc o
	on d.primaryid = o.primaryid
where  d.is_primary_suspect = 'True'
group by d.generic_name
having count(distinct d.primaryid) >=500 and death_rate > 15
order by death_rate desc;


-- 5. Reports by month, using a window function
-- how the running (cumulative) total of case reports month by month across 2025 
with monthly_counts as (
	select report_month,
    count(distinct primaryid) as case_count
    from demo
    where report_month like '2025-%'
    group by report_month
)
select report_month, 
	 case_count,  
	sum(case_count) over(order by report_month) as cumulative_case_count
from monthly_counts
order by report_month;

-- 6. Age group vs. serious outcome type
-- For each age group, how many cases had each outcome type (death, hospitalization, life-threatening, etc.
select d.age_group, 
	count(distinct case 
		when o.outc_cod='DE' then d.primaryid	
        end ) as death_count,
        
	count(distinct case 
		when o.outc_cod = 'HO' then d.primaryid
		end ) as hospitalization_count,
        
	count(distinct case
        WHEN o.outc_cod = 'LT' THEN d.primaryid
    END) AS life_threatening_count,

    count(distinct case
        WHEN o.outc_cod = 'DS' THEN d.primaryid
    END) AS disability_count,

    count(distinct case
        WHEN o.outc_cod = 'CA' THEN d.primaryid
    END) AS congenital_anomaly_count,

    count(distinct case
        WHEN o.outc_cod = 'RI' THEN d.primaryid
    END) AS intervention_count,

    count(distinct case
        WHEN o.outc_cod = 'OT' THEN d.primaryid
    END) AS other_serious_outcome_count

from demo d
join outc o
	on d.primaryid = o.primaryid
group by d.age_group
order by d.age_group;

-- better query

SELECT
    d.age_group,

    COUNT(DISTINCT CASE
        WHEN o.outc_cod = 'DE' THEN d.primaryid
    END) AS death_count,

    COUNT(DISTINCT CASE
        WHEN o.outc_cod = 'HO' THEN d.primaryid
    END) AS hospitalization_count,

    COUNT(DISTINCT CASE
        WHEN o.outc_cod = 'LT' THEN d.primaryid
    END) AS life_threatening_count,

    COUNT(DISTINCT CASE
        WHEN o.outc_cod = 'DS' THEN d.primaryid
    END) AS disability_count,

    COUNT(DISTINCT CASE
        WHEN o.outc_cod = 'CA' THEN d.primaryid
    END) AS congenital_anomaly_count,

    COUNT(DISTINCT CASE
        WHEN o.outc_cod = 'RI' THEN d.primaryid
    END) AS intervention_required_count,

    COUNT(DISTINCT CASE
        WHEN o.outc_cod = 'OT' THEN d.primaryid
    END) AS other_serious_outcome_count

FROM demo d
JOIN (
    SELECT DISTINCT
        primaryid,
        outc_cod
    FROM outc
) o
    ON d.primaryid = o.primaryid

GROUP BY d.age_group
ORDER BY d.age_group;

-- 7. Which reporter type (occp_cod) reports the most serious (death) cases 
-- Among all reporter types (physician, pharmacist, consumer, etc.), which ones report deaths most often, and what percentage of their own reports turn out to be deaths (not just raw counts)
SELECT
    occp_cod,
    total_cases,
    death_cases,
    ROUND((death_cases * 100.0) / total_cases, 2) AS death_percentage
from (
    select
        d.occp_cod,

        COUNT(DISTINCT d.primaryid) AS total_cases,

        COUNT(DISTINCT CASE
            WHEN o.outc_cod = 'DE'
            THEN d.primaryid
        END) AS death_cases

    from demo d
    join outc o
        on d.primaryid = o.primaryid
    group by d.occp_cod
) as reporter_summary

order by death_percentage desc;


-- 8. Top drug-reaction pairs in fatal cases (a real pharmacovigilance signal query)
-- For cases where the outcome was death, which specific drug + reaction combinations appear most frequently together?
select d.generic_name, r.pt as reaction, 
	count(distinct d.primaryid) as fatal_count
from drug d
join outc o
		on d.primaryid = o.primaryid
join reac r
		on o.primaryid = r.primaryid
where o.outc_cod = 'DE'
group by d.generic_name, r.pt
order by fatal_count desc
limit 20;


-- 9. Countries with highest death report rates
/* Which countries report the most deaths as a proportion of their total reports — 
but only for countries with at least 100 total reports (to avoid noise from countries with just 1-2 reports)  */
select d.occr_country, 
	count(distinct o.primaryid) as total_reports,
	count(distinct case
					when o.is_death = 'True' then o.primaryid end) as death_count,
	round(
    count(distinct case 
					when o.is_death = 'True'  then o.primaryid end) * 100 / count(distinct o.primaryid), 2) as death_report_rate
from demo d
join outc o
	on o.primaryid = d.primaryid
group by d.occr_country
having count(distinct(o.primaryid)) > 100
order by death_report_rate desc;

-- ------------------------------------------------------------------------------------------------------------------------------------------------
-- ------------------------------------------------------------------------------------------------------------------------------------------------

