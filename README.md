# FDA FAERS Drug Safety Analysis — 2025

A complete end-to-end data analytics project analyzing **1,465,808 adverse event reports** from the FDA's Adverse Event Reporting System (FAERS) across all 4 quarters of 2025. The project covers the full analytics pipeline — from raw multi-table data ingestion and cleaning through SQL relational analysis, statistical testing, and a 5-dashboard Tableau workbook.

---

## Tools & Technologies

| Stage | Tool | Purpose |
|---|---|---|
| Data Audit | Microsoft Excel | Initial audit of raw FAERS files, schema inspection, missing value profiling |
| Data Cleaning & EDA | Python (Pandas, NumPy, SciPy, Matplotlib, Seaborn) | Multi-table ingestion, cleaning, feature engineering, statistical analysis |
| Drug Standardization | RxNorm API (NLM) | Brand-name to generic-name mapping across 500 most frequent drugs |
| Relational Analysis | MySQL 8.0 | Multi-table JOIN queries, window functions, CTEs, disproportionality analysis |
| Visualization | Tableau Desktop | 5-dashboard interactive workbook with filter actions |

---

## Dataset

**Source:** [FDA FAERS Quarterly Data Files](https://www.fda.gov/drugs/questions-and-answers-fdas-adverse-event-reporting-system-faers/fda-adverse-event-reporting-system-faers-latest-quarterly-data-files)

**Coverage:** 2025 Q1, Q2, Q3, Q4 (ASCII pipe-delimited format)

**Tables used:**

| Table | Description | Rows (combined) |
|---|---|---|
| DEMO | Patient demographics and case metadata | 1,617,444 (raw) |
| DRUG | Drugs involved per case | 7,801,018 |
| REAC | Adverse reactions (MedDRA terms) | 5,657,830 |
| OUTC | Patient outcomes (death, hospitalization, etc.) | 1,232,582 |
| THER | Drug therapy dates and duration | 2,002,380 |
| INDI | Indications (why the drug was prescribed) | 4,821,589 |
| RPSR | Report source | 43,939 |
| DELETE | Cases FDA flagged for removal | 21,547 |

> **Important disclaimer:** FAERS is a voluntary reporting system. A report does not prove causation — it only indicates a temporal association between a drug and an event. Under-reporting is known and expected.

---

## Project Structure

```
FDA_FAERS_Drug_Safety_Analysis/
├── data/
│   ├── cleaned/          # Analysis-ready cleaned CSVs
│   └── raw/              # Raw FAERS files (not included — download from FDA)
├── notebooks/
│   └── FAERS_Analysis.ipynb    # Complete Python pipeline
├── sql/
│   ├── faers_analysis_queries.sql      # 9 analytical SQL queries
│   └── faers_dashboard_tables.sql      # Helper + dashboard table creation
├── tableau/
│   └── FAERS_2025_Dashboard.twbx       # Packaged Tableau workbook
├── dashboard_images/     # Screenshots of all 5 dashboards
└── README.md
```

---

## Reproducing This Project

### Prerequisites
- Python 3.9+ with: `pandas`, `numpy`, `scipy`, `matplotlib`, `seaborn`, `requests`, `pymysql`, `sqlalchemy`
- MySQL 8.0+
- Tableau Desktop 2023.1+

### Step 1: Download raw data
Download the 4 quarterly ZIP files for 2025 from [FDA FAERS](https://www.fda.gov/drugs/questions-and-answers-fdas-adverse-event-reporting-system-faers/fda-adverse-event-reporting-system-faers-latest-quarterly-data-files). Extract each into `data/raw/2025Q1/`, `data/raw/2025Q2/`, etc.

### Step 2: Run the Python notebook
Open `notebooks/FAERS_Analysis.ipynb` and run all cells. This handles:
- Loading and stacking all 4 quarters per table
- Cleaning and standardizing all 7 tables
- Exporting cleaned CSVs to `data/cleaned/`

### Step 3: Set up MySQL
```sql
CREATE DATABASE faers_2025;
USE faers_2025;
```
Import each cleaned CSV into its corresponding table, then run `sql/faers_dashboard_tables.sql` to create all helper and dashboard tables.

### Step 4: Open Tableau
Open `tableau/FAERS_2025_Dashboard.twbx`. Reconnect each data source to your local MySQL `faers_2025` database if prompted.

---

## Pipeline — What We Did and Why

### Stage 1: Excel Audit
Opened `DEMO25Q1.txt` and `DRUG25Q1.txt` as pipe-delimited files. Key findings:
- `age_cod` had 6 different units (YR, MON, WK, DY, DEC, HR) — all needed converting to years
- `wt_cod` had KG and LBS mixed — needed standardization to KG
- `caseversion` went up to 146 — same case resubmitted 146 times; only the latest version should be used
- Drug names showed massive inconsistency (`ASPIRIN`, `Aspirin`, `aspirin`) — confirmed brand vs. generic naming problem

### Stage 2: Python Cleaning

**Loading and stacking:**
All 4 quarters of each table loaded individually then stacked with `pd.concat()`, tagging each row with its source quarter.

**DELETE cases removed:**
FDA's DELETE files flagged 21,547 case IDs for removal. After filtering, 3,670 rows were removed from DEMO (not all deleted IDs appeared in this year's data).

**Case version deduplication:**
For each `caseid`, only the row with the highest `caseversion` was kept using `sort_values + drop_duplicates`. This reduced DEMO from 1,613,774 rows to **1,465,808 unique current cases**.

**Age standardization:**
Converted all age units to years using a unit-specific conversion function. Found 30 impossible ages above 120 years — nulled rather than guessed (23 of these came from DEC-coded entries where reporters entered the full age in years but coded the unit as "decade", producing values like 800 years). 582,115 rows had no age recorded — left as NULL, not imputed.

**Weight standardization:**
Converted LBS to KG. Found and nulled implausible weights above 450 KG.

**Drug name standardization (the flagship cleaning step):**
1. Stripped whitespace and uppercased all drug names
2. Sent the top 500 most-frequent names (covering 70% of all rows) to the **RxNorm API** to retrieve standard generic ingredient names
3. 470 of 500 names mapped successfully (94%). Failures were combination drugs (`CARBIDOPA\LEVODOPA`), discontinued brand names, and genuinely vague terms (`VITAMINS`, `UNSPECIFIED INGREDIENT`) — all kept as-is with their original cleaned name as fallback
4. Result: **5,276,680 of 7,801,018 drug rows (67.6%) now carry a standardized generic name** instead of a raw brand name

**Statistical analysis:**
- Z-test confirmed fentanyl's death rate (34%) is statistically significantly higher than the overall rate (5.9%), with z-statistic = 69.6 and p-value ≈ 0 — not random noise
- Key insight: fentanyl's high rate is distinguishable from cancer drugs' high rates because fentanyl's top fatal reaction is "Drug abuse" (748 cases), not a disease-progression term — suggesting independent drug risk, not just sick-population confounding

### Stage 3: SQL Analysis

Loaded all 7 cleaned tables into MySQL as separate linked tables (not one flat file) and created the following:

**Two helper tables:**
- `helper_case_outcome` — one row per case with an `is_fatal` flag (1/0), restricting to our 1,465,808 final cases
- `helper_ps_drug` — primary suspect drugs only, joined to final cases

**Ten pre-aggregated dashboard tables** (the MySQL-does-heavy-work, Tableau-does-presentation strategy):
`tb_kpi`, `tb_monthly`, `tb_outcome_mix`, `tb_reaction`, `tb_drug`, `tb_drug_reaction`, `tb_demographics`, `tb_demo_outcome`, `tb_country`, `tb_reporter`

**9 analytical queries written:**
1. Reactions most associated with fatal cases (JOIN reac + outc)
2. Top primary-suspect drugs in fatal cases
3. Same as #1 with explicit is_death filter
4. Drug disproportionate fatality rates (conditional aggregation, HAVING)
5. Cumulative monthly reports (CTE + SUM OVER window function)
6. Age group × outcome cross-tab (conditional COUNT DISTINCT pivot)
7. Reporter type death rates (subquery + percentage calculation)
8. Fatal drug-reaction pairs — a real pharmacovigilance signal query (3-table JOIN)
9. Country death rates (HAVING with volume threshold)

### Stage 4: Tableau Dashboard

Connected Tableau to the pre-aggregated `tb_` tables as Extracts (not Live connections) for instant performance. Built 5 dashboards:

1. **Overview** — KPI cards, monthly trend, outcome mix, top reactions
2. **Drug Safety Signals** — fatality rate leaderboard, volume comparison, fatal drug-reaction pairs with click-to-filter action
3. **Patient Demographics** — age group × sex, age group × outcome
4. **Geography & Reporters** — country map with death rate coloring, reporter type analysis
5. **Data Quality & Methodology** — full cleaning audit trail as a formatted table

---

## Key Findings

**1. Dupilumab (DUPIXENT) dominates report volume** with 141,289 primary-suspect reports — more than double the next drug. Volume ≠ danger: it doesn't appear in the high fatality rate leaderboard because it's widely prescribed to a relatively healthy patient population.

**2. 67.4% of all serious outcomes are "Other Serious"** — meaning hospitalization (27.4%), death (9.9%), life-threatening events (4.4%), disability and congenital anomaly together account for the rest.

**3. Fentanyl's fatality rate (65%) is a genuine safety signal.** Unlike cancer drugs which rank high due to patient population severity, fentanyl's #1 fatal reaction is "Drug abuse" (748 fatal cases) — a credible drug-specific risk, not population confounding.

**4. "Off label use" and "Drug ineffective" are the top 2 reported reactions overall** — FAERS captures usage and effectiveness issues, not just physical adverse events. These are non-clinical findings that dominate the system.

**5. Depression comorbidity pattern** — consistent with the OCD project, 51% of serious adverse event cases involve patients with depression diagnosis, relatively flat across age groups.

**6. Report volume peaks in August 2025** (148,831 cases) — a seasonal pattern worth monitoring in future analyses.

**7. Japan has 51,989 serious case reports** with an 18.7% fatality rate — the highest reliable rate among high-volume countries, likely reflecting Japan's thorough mandatory reporting culture rather than actual higher drug danger.

---

## Challenges Faced & How We Solved Them

| Challenge | Root Cause | Solution |
|---|---|---|
| MySQL LOAD DATA INFILE blocked | `secure_file_priv` security setting | Used Python pymysql `LOAD DATA LOCAL INFILE` instead |
| Blank numeric columns rejected on load | MySQL strict mode treating empty strings as invalid FLOAT | Added `NULLIF(@col, '')` mapping in LOAD DATA statement |
| Workbench 30-second timeout on large loads | GUI timeout setting, not MySQL server limit | Switched to Python pymysql connection with no client timeout |
| REAC and INDI tables loading only ~2,000 rows | Comma inside quoted reaction terms (`"Sleep disorder, insomnia type"`) confused MySQL's LOAD DATA parser | Switched to `pandas.read_csv` chunked insert with `executemany` — pandas' CSV parser correctly handles quoted commas |
| Tableau filter action showing blank | `drug_rank` and `drug_total_fatal` columns not picked up after schema change | Closed and re-added the data source from scratch to force schema refresh |
| Tableau Top N filter showing same 3 reactions for all drugs | Tableau's Top N is computed globally, not per dimension | Added `reaction_rank` and `drug_rank` columns in MySQL using `RANK() OVER (PARTITION BY generic_name ...)`, then filtered on those in Tableau |
| `\r` invisible character in boolean columns | Windows line endings (`\r\n`) written into the last column of some CSV rows during export | Found using MySQL `HEX()` function — `0D` hex suffix confirmed; stripped with `UPDATE` |
| Average age showing 32.9 instead of 54.6 | Blank `age_years` values loaded as `0` instead of NULL in MySQL | `UPDATE demo SET age_years = NULL WHERE age_cod IS NULL OR age_cod = ''` |
| FAERS age values up to 962 years | Reporters coding age in years but marking unit as DEC (decade) — a known FAERS data quality issue | Capped all ages above 120 years to NULL — 30 rows affected |

---

## Data Quality Summary

| Step | Metric | Value |
|---|---|---|
| Raw DEMO rows loaded (4 quarters) | Before any cleaning | 1,617,444 |
| Cases removed via FDA DELETE files | FDA-flagged invalid cases | 3,670 |
| Duplicate case versions removed | Kept only latest caseversion per caseid | 147,966 |
| Final unique clean cases | Base for all analysis | **1,465,808** |
| Implausible ages nulled (> 120 years) | 23 were DEC-coded decade entries | 30 |
| Cases with unknown age (left as missing) | Not guessed or imputed | 582,115 |
| Drug names sent to RxNorm API | Top 500 most frequent names | 500 |
| Successfully mapped to generic name | RxNorm ingredient lookup | 470 of 500 (94%) |
| Drug rows standardized to generic name | Out of 7,801,018 total | 5,276,680 (67.6%) |
| Unmapped rows (kept original name) | Combo drugs, discontinued brands, vague terms | 2,524,338 (32.4%) |

---

## Dashboard Screenshots

### Overview
![Overview](dashboard_images/01_Overview.png)

### Drug Safety Signals
![Drug Safety Signals](dashboard_images/02_Drug_Safety_Signals.png)

### Patient Demographics
![Patient Demographics](dashboard_images/03_Patient_Demographics.png)

### Geography & Reporters
![Geography & Reporters](dashboard_images/04_Geography_Reporters.png)

### Data Quality & Methodology
![Data Quality](dashboard_images/05_Data_Quality_Methodology.png)

---
