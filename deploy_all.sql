!source sql/01_setup.sql
SELECT '2026-10-22'::DATE AS expiration_date,
       DATEDIFF(day, CURRENT_DATE(), '2026-10-22'::DATE) AS days_remaining,
       IFF(CURRENT_DATE() > '2026-10-22'::DATE, 'REVIEW DUE', 'DEMO') AS demo_status;
!source sql/01_load.sql
!source sql/02_analytics.sql