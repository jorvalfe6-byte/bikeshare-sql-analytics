-- =====================================================================
-- 12_duration_distribution.sql — How long do trips last?
-- Grain: 1 row per duration bucket.
--
-- Shares are within each rider type, so each column sums to 100 %.
-- =====================================================================
WITH bucketed AS (
    SELECT member_type,
           CASE WHEN duration_min <   5 THEN 1
                WHEN duration_min <  10 THEN 2
                WHEN duration_min <  20 THEN 3
                WHEN duration_min <  30 THEN 4
                WHEN duration_min <  60 THEN 5
                ELSE                         6 END AS bucket
    FROM mart.fact_trip
    WHERE is_valid
)
SELECT bucket,
       CASE bucket WHEN 1 THEN 'under 5 min'  WHEN 2 THEN '5–10 min'  WHEN 3 THEN '10–20 min'
                   WHEN 4 THEN '20–30 min'    WHEN 5 THEN '30–60 min' ELSE '1 h or more' END AS duration,
       ROUND(100.0 * COUNT(*) FILTER (WHERE member_type = 'member')
                   / SUM(COUNT(*) FILTER (WHERE member_type = 'member')) OVER (), 1) AS pct_members,
       ROUND(100.0 * COUNT(*) FILTER (WHERE member_type = 'casual')
                   / SUM(COUNT(*) FILTER (WHERE member_type = 'casual')) OVER (), 1) AS pct_casual
FROM bucketed
GROUP BY bucket
ORDER BY bucket;
