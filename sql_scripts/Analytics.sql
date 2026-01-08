SELECT *
FROM merchants;
SELECT *
FROM api_keys;
SELECT *
FROM transactions;
SELECT *
FROM merchant_activity_daily;
SELECT *
FROM merchant_lifecycle;
SELECT *
FROM merchant_onboarding;


-- ACTIVATION
--1. Activation Rate
SELECT
    COUNT(*) AS total_merchants,
    COUNT(CASE WHEN is_activated = 1 THEN 1 END) AS activated_merchants,
    ROUND(
        COUNT(CASE WHEN is_activated = 1 THEN 1 END) * 100.0
        / COUNT(*),
        2
    ) AS activation_rate_pct
FROM merchant_onboarding;

--2. Time To Activate
WITH activation_times AS (
    SELECT
        DATEDIFF(
            day,
            signup_timestamp,
            first_live_txn_timestamp
        ) AS days_to_activation
    FROM merchant_onboarding
    WHERE is_activated = 1
),
summary_stats AS (
    SELECT
        COUNT(*) AS activated_merchants,
        AVG(days_to_activation * 1.0) AS avg_days_to_activation,
        MIN(days_to_activation) AS min_days_to_activation,
        MAX(days_to_activation) AS max_days_to_activation
    FROM activation_times
),
median_stat AS (
    SELECT
        PERCENTILE_CONT(0.5)
            WITHIN GROUP (ORDER BY days_to_activation)
            OVER () AS median_days_to_activation
    FROM activation_times
)
SELECT
    s.activated_merchants,
    s.avg_days_to_activation,
    s.min_days_to_activation,
    s.max_days_to_activation,
    m.median_days_to_activation
FROM summary_stats s
CROSS JOIN (
    SELECT DISTINCT median_days_to_activation
    FROM median_stat
) m;

--3. Activation Funnel
WITH signup AS (
    SELECT COUNT(*) AS cnt
    FROM merchants
),
api_integration AS (
    SELECT COUNT(DISTINCT merchant_id) AS cnt
    FROM api_keys
),
first_test AS (
    SELECT COUNT(*) AS cnt
    FROM merchant_onboarding
    WHERE first_test_txn_timestamp IS NOT NULL
),
activated AS (
    SELECT COUNT(*) AS cnt
    FROM merchant_onboarding
    WHERE is_activated = 1
),
engaged AS (
    SELECT COUNT(DISTINCT merchant_id) AS cnt
    FROM (
        SELECT
            merchant_id
        FROM transactions
        WHERE environment = 'LIVE'
          AND status = 'SUCCESS'
        GROUP BY merchant_id
        HAVING COUNT(*) >= 10
    ) t
)
SELECT
    stage,
    merchants_count,
    ROUND(
        merchants_count * 100.0
        / LAG(merchants_count) OVER (ORDER BY stage_order),
        2
    ) AS conversion_from_previous_pct
FROM (
    SELECT 1 AS stage_order, 'Signup' AS stage, cnt AS merchants_count FROM signup
    UNION ALL
    SELECT 2, 'API Integration', cnt FROM api_integration
    UNION ALL
    SELECT 3, 'First Test Transaction', cnt FROM first_test
    UNION ALL
    SELECT 4, 'Activated (First Live)', cnt FROM activated
    UNION ALL
    SELECT 5, 'Engaged (10+ Live Txns)', cnt FROM engaged
) funnel
ORDER BY stage_order;

--4. Activation Rate by Business Size
SELECT
    m.business_type,
    COUNT(*) AS total_merchants,
    COUNT(CASE WHEN o.is_activated = 1 THEN 1 END) AS activated_merchants,
    ROUND(
        COUNT(CASE WHEN o.is_activated = 1 THEN 1 END) * 100.0
        / COUNT(*),
        2
    ) AS activation_rate_pct
FROM merchant_onboarding o
JOIN merchants m
  ON o.merchant_id = m.merchant_id
GROUP BY m.business_type
ORDER BY activation_rate_pct DESC;


-- ENGAGEMENT
---5. Monthly Active Merchants (MAM)
WITH mam_by_month AS (
    SELECT
        DATEFROMPARTS(YEAR(activity_date), MONTH(activity_date), 1) AS activity_month,
        COUNT(DISTINCT merchant_id) AS monthly_active_merchants
    FROM merchant_activity_daily
    GROUP BY DATEFROMPARTS(YEAR(activity_date), MONTH(activity_date), 1)
),
mam_with_lag AS (
    SELECT
        activity_month,
        monthly_active_merchants,
        LAG(monthly_active_merchants) OVER (ORDER BY activity_month) AS previous_month_mam
    FROM mam_by_month
)
SELECT
    activity_month,
    monthly_active_merchants,
    previous_month_mam,
    ROUND(
        (monthly_active_merchants - previous_month_mam) * 100.0
        / NULLIF(prev_month_mam, 0),
        2
    ) AS mom_growth_pct
FROM mam_with_lag
ORDER BY activity_month;

--6. How many merchants are Low/Medium/High engagement (Engagement Levels Distribution)
WITH monthly_txns AS (
    SELECT
        DATEFROMPARTS(YEAR(activity_date), MONTH(activity_date), 1) AS activity_month,
        merchant_id,
        COUNT(*) AS monthly_live_txns
    FROM merchant_activity_daily
    GROUP BY
        DATEFROMPARTS(YEAR(activity_date), MONTH(activity_date), 1),
        merchant_id
),
bucketed AS (
    SELECT
        activity_month,
        merchant_id,
        CASE
            WHEN monthly_live_txns BETWEEN 1 AND 9 THEN 'Low'
            WHEN monthly_live_txns BETWEEN 10 AND 99 THEN 'Medium'
            WHEN monthly_live_txns >= 100 THEN 'High'
        END AS engagement_level
    FROM monthly_txns
)
SELECT
    activity_month,
    engagement_level,
    COUNT(DISTINCT merchant_id) AS merchant_count,
    ROUND(
        COUNT(DISTINCT merchant_id) * 100.0
        / SUM(COUNT(DISTINCT merchant_id)) OVER (PARTITION BY activity_month),
        2
    ) AS pct_of_active_merchants
FROM bucketed
GROUP BY activity_month, engagement_level
ORDER BY activity_month, engagement_level;

--7. Transaction Success Rate by Merchant Segment
WITH segment_base AS (
    SELECT
        m.business_type,
        t.merchant_id,
        t.status,
        t.amount
    FROM transactions t
    JOIN merchants m
      ON t.merchant_id = m.merchant_id
    WHERE t.environment = 'LIVE'
),
segment_agg AS (
    SELECT
        business_type,

        COUNT(DISTINCT merchant_id) AS num_merchants,

        COUNT(*) AS total_transactions,

        SUM(CASE
            WHEN status = 'SUCCESS' THEN 1
            ELSE 0
        END) AS total_successful,

        SUM(CASE
            WHEN status = 'FAILED' THEN 1
            ELSE 0
        END) AS total_failed,

        SUM(CASE
            WHEN status = 'SUCCESS' THEN amount
            ELSE 0
        END) AS total_volume_ngn

    FROM segment_base
    GROUP BY business_type
)
SELECT
    business_type,

    num_merchants,

    total_transactions,

    total_successful,

    total_failed,

    ROUND(
        total_successful * 100.0
        / NULLIF(total_transactions, 0),
        2
    ) AS success_rate_pct,

    ROUND(
        total_transactions * 1.0
        / NULLIF(num_merchants, 0),
        2
    ) AS avg_transactions_per_merchant,

    total_volume_ngn

FROM segment_agg
ORDER BY total_volume_ngn DESC;


--RETENTION 
--8.  M1 Retention (Month 1)
WITH signup_cohorts AS (
    SELECT
        m.merchant_id,
        DATEFROMPARTS(
            YEAR(m.signup_timestamp),
            MONTH(m.signup_timestamp),
            1
        ) AS cohort_month
    FROM merchants m
),

m1_activity AS (
    SELECT DISTINCT
        mad.merchant_id,
        DATEFROMPARTS(
            YEAR(mad.activity_date),
            MONTH(mad.activity_date),
            1
        ) AS activity_month
    FROM merchant_activity_daily mad
),

cohort_retention AS (
    SELECT
        sc.cohort_month,
        COUNT(DISTINCT sc.merchant_id) AS cohort_size,

        COUNT(DISTINCT CASE
            WHEN ma.activity_month = DATEADD(MONTH, 1, sc.cohort_month)
            THEN sc.merchant_id
        END) AS retained_m1
    FROM signup_cohorts sc
    LEFT JOIN m1_activity ma
        ON sc.merchant_id = ma.merchant_id
    GROUP BY sc.cohort_month
)

SELECT
    cohort_month,
    cohort_size,
    retained_m1,
    ROUND(
        retained_m1 * 100.0 / NULLIF(cohort_size, 0),
        2
    ) AS m1_retention_pct
FROM cohort_retention
ORDER BY cohort_month;

--9. M3 Retention (Month 3)
WITH signup_cohorts AS (
    SELECT
        m.merchant_id,
        DATEFROMPARTS(
            YEAR(m.signup_timestamp),
            MONTH(m.signup_timestamp),
            1
        ) AS cohort_month
    FROM merchants m
),

activity_months AS (
    SELECT DISTINCT
        mad.merchant_id,
        DATEFROMPARTS(
            YEAR(mad.activity_date),
            MONTH(mad.activity_date),
            1
        ) AS activity_month
    FROM merchant_activity_daily mad
),

cohort_m3_retention AS (
    SELECT
        sc.cohort_month,
        COUNT(DISTINCT sc.merchant_id) AS cohort_size,

        COUNT(DISTINCT CASE
            WHEN am.activity_month = DATEADD(MONTH, 3, sc.cohort_month)
            THEN sc.merchant_id
        END) AS retained_m3
    FROM signup_cohorts sc
    LEFT JOIN activity_months am
        ON sc.merchant_id = am.merchant_id
    GROUP BY sc.cohort_month
)

SELECT
    cohort_month,
    cohort_size,
    retained_m3,
    ROUND(
        retained_m3 * 100.0 / NULLIF(cohort_size, 0),
        2
    ) AS m3_retention_pct
FROM cohort_m3_retention
ORDER BY cohort_month;

--10. Cohort Retention Table
WITH signup_cohorts AS (
    SELECT
        m.merchant_id,
        DATEFROMPARTS(
            YEAR(m.signup_timestamp),
            MONTH(m.signup_timestamp),
            1
        ) AS cohort_month
    FROM merchants m
),

activity_months AS (
    SELECT DISTINCT
        mad.merchant_id,
        DATEFROMPARTS(
            YEAR(mad.activity_date),
            MONTH(mad.activity_date),
            1
        ) AS activity_month
    FROM merchant_activity_daily mad
),

cohort_activity AS (
    SELECT
        sc.cohort_month,
        sc.merchant_id,
        DATEDIFF(
            MONTH,
            sc.cohort_month,
            am.activity_month
        ) AS month_offset
    FROM signup_cohorts sc
    JOIN activity_months am
        ON sc.merchant_id = am.merchant_id
    WHERE
        DATEDIFF(
            MONTH,
            sc.cohort_month,
            am.activity_month
        ) BETWEEN 1 AND 6   
),

cohort_sizes AS (
    SELECT
        cohort_month,
        COUNT(*) AS cohort_size
    FROM signup_cohorts
    GROUP BY cohort_month
),

retention_counts AS (
    SELECT
        ca.cohort_month,
        ca.month_offset,
        COUNT(DISTINCT ca.merchant_id) AS retained_merchants
    FROM cohort_activity ca
    GROUP BY ca.cohort_month, ca.month_offset
),

retention_pct AS (
    SELECT
        rc.cohort_month,
        rc.month_offset,
        ROUND(
            rc.retained_merchants * 100.0
            / cs.cohort_size,
            2
        ) AS retention_pct
    FROM retention_counts rc
    JOIN cohort_sizes cs
        ON rc.cohort_month = cs.cohort_month
)

SELECT
    cs.cohort_month,

    100.00 AS M0,  

    MAX(CASE WHEN rp.month_offset = 1 THEN rp.retention_pct END) AS M1,
    MAX(CASE WHEN rp.month_offset = 2 THEN rp.retention_pct END) AS M2,
    MAX(CASE WHEN rp.month_offset = 3 THEN rp.retention_pct END) AS M3,
    MAX(CASE WHEN rp.month_offset = 4 THEN rp.retention_pct END) AS M4,
    MAX(CASE WHEN rp.month_offset = 5 THEN rp.retention_pct END) AS M5,
    MAX(CASE WHEN rp.month_offset = 6 THEN rp.retention_pct END) AS M6

FROM cohort_sizes cs
LEFT JOIN retention_pct rp
    ON cs.cohort_month = rp.cohort_month
GROUP BY cs.cohort_month
ORDER BY cs.cohort_month;

--11. What % of merchants return on Day 7, Day 14, Day 30, Day 60, Day 90?
WITH merchant_activity AS (
    SELECT DISTINCT
        m.merchant_id,
        CAST(m.signup_timestamp AS date) AS signup_date,
        CAST(t.transaction_timestamp AS date) AS txn_date
    FROM merchants m
    LEFT JOIN transactions t
        ON m.merchant_id = t.merchant_id
       AND t.environment = 'LIVE'
),

retention_flags AS (
    SELECT
        merchant_id,

        MAX(CASE
            WHEN txn_date BETWEEN DATEADD(day, 7, signup_date)
                              AND DATEADD(day, 13, signup_date)
            THEN 1 ELSE 0 END) AS D7,

        MAX(CASE
            WHEN txn_date BETWEEN DATEADD(day, 14, signup_date)
                              AND DATEADD(day, 20, signup_date)
            THEN 1 ELSE 0 END) AS D14,

        MAX(CASE
            WHEN txn_date BETWEEN DATEADD(day, 30, signup_date)
                              AND DATEADD(day, 36, signup_date)
            THEN 1 ELSE 0 END) AS D30,

        MAX(CASE
            WHEN txn_date BETWEEN DATEADD(day, 60, signup_date)
                              AND DATEADD(day, 66, signup_date)
            THEN 1 ELSE 0 END) AS D60,

        MAX(CASE
            WHEN txn_date BETWEEN DATEADD(day, 90, signup_date)
                              AND DATEADD(day, 96, signup_date)
            THEN 1 ELSE 0 END) AS D90

    FROM merchant_activity
    GROUP BY merchant_id
)

SELECT
    'D7'  AS retention_day,
    ROUND(AVG(D7 * 1.0) * 100, 2) AS retention_pct
FROM retention_flags

UNION ALL
SELECT
    'D14',
    ROUND(AVG(D14 * 1.0) * 100, 2)
FROM retention_flags

UNION ALL
SELECT
    'D30',
    ROUND(AVG(D30 * 1.0) * 100, 2)
FROM retention_flags

UNION ALL
SELECT
    'D60',
    ROUND(AVG(D60 * 1.0) * 100, 2)
FROM retention_flags

UNION ALL
SELECT
    'D90',
    ROUND(AVG(D90 * 1.0) * 100, 2)
FROM retention_flags;


--CHURN
--12. What % of merchants churn each month?
WITH activity_days AS (
    SELECT DISTINCT
        merchant_id,
        CAST(activity_date AS date) AS activity_date
    FROM merchant_activity_daily
),

month_ends AS (
    SELECT DISTINCT
        EOMONTH(activity_date) AS month_end
    FROM activity_days
),

merchant_month_status AS (
    SELECT
        me.month_end,
        ad.merchant_id,

        MAX(CASE
            WHEN ad.activity_date BETWEEN DATEADD(day, -30, me.month_end)
                                     AND me.month_end
            THEN 1 ELSE 0
        END) AS active_last_30_days,

        MAX(CASE
            WHEN ad.activity_date BETWEEN DATEADD(day, -60, me.month_end)
                                     AND DATEADD(day, -31, me.month_end)
            THEN 1 ELSE 0
        END) AS active_30_60_days_ago

    FROM month_ends me
    LEFT JOIN activity_days ad
        ON ad.activity_date <= me.month_end
    GROUP BY me.month_end, ad.merchant_id
),

churn_base AS (
    SELECT
        month_end,
        merchant_id
    FROM merchant_month_status
    WHERE
        active_30_60_days_ago = 1
),

churned_merchants AS (
    SELECT
        month_end,
        COUNT(DISTINCT merchant_id) AS churned_count
    FROM merchant_month_status
    WHERE
        active_30_60_days_ago = 1
        AND active_last_30_days = 0
    GROUP BY month_end
),

active_last_month AS (
    SELECT
        month_end,
        COUNT(DISTINCT merchant_id) AS active_last_month_count
    FROM churn_base
    GROUP BY month_end
)

SELECT
    a.month_end,
    a.active_last_month_count,
    c.churned_count,
    ROUND(
        c.churned_count * 100.0
        / NULLIF(a.active_last_month_count, 0),
        2
    ) AS monthly_churn_rate_pct
FROM active_last_month a
LEFT JOIN churned_merchants c
    ON a.month_end = c.month_end
ORDER BY a.month_end;

--13. What behaviors distinguish churned merchants in their last 30–60 days of activity?
WITH max_activity AS (
    SELECT MAX(activity_date) AS analysis_date
    FROM merchant_activity_daily
),

last_activity AS (
    SELECT
        merchant_id,
        MAX(activity_date) AS last_activity_date
    FROM merchant_activity_daily
    GROUP BY merchant_id
),

churned_merchants AS (
    SELECT
        la.merchant_id,
        la.last_activity_date
    FROM last_activity la
    CROSS JOIN max_activity ma
    WHERE la.last_activity_date < DATEADD(day, -30, ma.analysis_date)
),

pre_churn_txns AS (
    SELECT
        t.merchant_id,
        t.status,
        t.failure_reason
    FROM transactions t
    JOIN churned_merchants cm
        ON t.merchant_id = cm.merchant_id
    WHERE
        t.environment = 'LIVE'
        AND t.transaction_timestamp BETWEEN
            DATEADD(day, -60, cm.last_activity_date)
            AND cm.last_activity_date
)

SELECT
    status,
    COALESCE(failure_reason, 'NONE') AS failure_reason,
    COUNT(*) AS txn_count
FROM pre_churn_txns
GROUP BY
    status,
    COALESCE(failure_reason, 'NONE')
ORDER BY txn_count DESC;


-- REVENUE METRICS
--14. What's the total monthly revenue from transaction fees?
WITH monthly_revenue AS (
    SELECT
        DATEFROMPARTS(
            YEAR(transaction_timestamp),
            MONTH(transaction_timestamp),
            1
        ) AS revenue_month,
        SUM(amount) AS mrr
    FROM transactions
    WHERE
        environment = 'LIVE'
        AND status = 'SUCCESS'
    GROUP BY
        DATEFROMPARTS(
            YEAR(transaction_timestamp),
            MONTH(transaction_timestamp),
            1
        )
),

mrr_with_lag AS (
    SELECT
        revenue_month,
        mrr,
        LAG(mrr) OVER (ORDER BY revenue_month) AS prev_mrr
    FROM monthly_revenue
)

SELECT
    revenue_month,
    mrr,
    prev_mrr,
    ROUND(
        (mrr - prev_mrr) * 100.0 / NULLIF(prev_mrr, 0),
        2
    ) AS mom_growth_pct
FROM mrr_with_lag
ORDER BY revenue_month;

--15. Revenue Churn vs Logo Churn
-- How much revenue are we losing from churned merchants?
WITH merchant_monthly_revenue AS (
    SELECT
        merchant_id,
        DATEFROMPARTS(
            YEAR(transaction_timestamp),
            MONTH(transaction_timestamp),
            1
        ) AS revenue_month,
        SUM(amount) AS merchant_mrr
    FROM transactions
    WHERE
        environment = 'LIVE'
        AND status = 'SUCCESS'
    GROUP BY
        merchant_id,
        DATEFROMPARTS(
            YEAR(transaction_timestamp),
            MONTH(transaction_timestamp),
            1
        )
),

all_months AS (
    SELECT DISTINCT
        DATEFROMPARTS(
            YEAR(transaction_timestamp),
            MONTH(transaction_timestamp),
            1
        ) AS revenue_month
    FROM transactions
),

merchant_month_grid AS (
    SELECT
        m.merchant_id,
        am.revenue_month
    FROM merchants m
    CROSS JOIN all_months am
),

merchant_month_filled AS (
    SELECT
        g.merchant_id,
        g.revenue_month,
        COALESCE(r.merchant_mrr, 0) AS merchant_mrr
    FROM merchant_month_grid g
    LEFT JOIN merchant_monthly_revenue r
        ON g.merchant_id = r.merchant_id
       AND g.revenue_month = r.revenue_month
),

revenue_with_lag AS (
    SELECT
        merchant_id,
        revenue_month,
        merchant_mrr,
        LAG(merchant_mrr) OVER (
            PARTITION BY merchant_id
            ORDER BY revenue_month
        ) AS prev_merchant_mrr
    FROM merchant_month_filled
)
SELECT
    revenue_month,

    -- Logo churn
    COUNT(DISTINCT CASE
        WHEN prev_merchant_mrr > 0
             AND merchant_mrr = 0
        THEN merchant_id
    END) AS churned_merchants,

    COUNT(DISTINCT CASE
        WHEN prev_merchant_mrr > 0
        THEN merchant_id
    END) AS merchants_last_month,

    ROUND(
        COUNT(DISTINCT CASE
            WHEN prev_merchant_mrr > 0
                 AND merchant_mrr = 0
            THEN merchant_id
        END) * 100.0
        / NULLIF(
            COUNT(DISTINCT CASE
                WHEN prev_merchant_mrr > 0
                THEN merchant_id
            END),
            0
        ),
        2
    ) AS logo_churn_pct,

    -- Revenue churn
    SUM(CASE
        WHEN prev_merchant_mrr > 0
             AND merchant_mrr = 0
        THEN prev_merchant_mrr
        ELSE 0
    END) AS churned_mrr,

    SUM(CASE
        WHEN prev_merchant_mrr > 0
        THEN prev_merchant_mrr
        ELSE 0
    END) AS starting_mrr,

    ROUND(
        SUM(CASE
            WHEN prev_merchant_mrr > 0
                 AND merchant_mrr = 0
            THEN prev_merchant_mrr
            ELSE 0
        END) * 100.0
        / NULLIF(
            SUM(CASE
                WHEN prev_merchant_mrr > 0
                THEN prev_merchant_mrr
                ELSE 0
            END),
            0
        ),
        2
    ) AS revenue_churn_pct

FROM revenue_with_lag
GROUP BY revenue_month
ORDER BY revenue_month;
--INSIGHT: Although a large number of merchants churn each month, the revenue impact is
--significantly lower, indicating that churn is concentrated among low-volume merchants while high-value merchants are retained.

-- 16. Net Revenue Retention (NRR)
-- Are existing merchants spending more or less over time?
-- Formula: NRR = ((Starting MRR + Expansion MRR - Churned MRR) / Starting MRR) x 100
-- MRR = Monthly Recurring Revenue
WITH merchant_monthly_revenue AS (
    SELECT
        merchant_id,
        DATEFROMPARTS(
            YEAR(transaction_timestamp),
            MONTH(transaction_timestamp),
            1
        ) AS revenue_month,
        SUM(amount) AS merchant_mrr
    FROM transactions
    WHERE
        environment = 'LIVE'
        AND status = 'SUCCESS'
    GROUP BY
        merchant_id,
        DATEFROMPARTS(
            YEAR(transaction_timestamp),
            MONTH(transaction_timestamp),
            1
        )
),

all_months AS (
    SELECT DISTINCT
        DATEFROMPARTS(
            YEAR(transaction_timestamp),
            MONTH(transaction_timestamp),
            1
        ) AS revenue_month
    FROM transactions
),

merchant_month_grid AS (
    SELECT
        m.merchant_id,
        am.revenue_month
    FROM merchants m
    CROSS JOIN all_months am
),

merchant_month_filled AS (
    SELECT
        g.merchant_id,
        g.revenue_month,
        COALESCE(r.merchant_mrr, 0) AS merchant_mrr
    FROM merchant_month_grid g
    LEFT JOIN merchant_monthly_revenue r
        ON g.merchant_id = r.merchant_id
       AND g.revenue_month = r.revenue_month
),

revenue_with_lag AS (
    SELECT
        merchant_id,
        revenue_month,
        merchant_mrr,
        LAG(merchant_mrr) OVER (
            PARTITION BY merchant_id
            ORDER BY revenue_month
        ) AS prev_merchant_mrr
    FROM merchant_month_filled
)

SELECT
    revenue_month,

    -- Starting MRR (existing merchants)
    SUM(CASE
        WHEN prev_merchant_mrr > 0
        THEN prev_merchant_mrr
        ELSE 0
    END) AS starting_mrr,

    -- Ending MRR from existing merchants
    SUM(CASE
        WHEN prev_merchant_mrr > 0
        THEN merchant_mrr
        ELSE 0
    END) AS ending_mrr_existing,

    ROUND(
        SUM(CASE
            WHEN prev_merchant_mrr > 0
            THEN merchant_mrr
            ELSE 0
        END) * 100.0
        / NULLIF(
            SUM(CASE
                WHEN prev_merchant_mrr > 0
                THEN prev_merchant_mrr
                ELSE 0
            END),
            0
        ),
        2
    ) AS nrr_pct

FROM revenue_with_lag
GROUP BY revenue_month
ORDER BY revenue_month;
--INSIGHT: NRR spikes early because existing merchants ramp usage rapidly once fully live. Since payments revenue is usage-based,
--early expansion can dwarf the initial baseline. Over time, NRR normalizes as churn offsets expansion. 
-- Payments platforms have usage-based revenue, meaning revenue scales with transaction volume rather than a fixed subscription,
--which can lead to large revenue swings from existing merchants.

--17. Revenue by Merchant Segment
WITH segment_revenue AS (
    SELECT
        m.business_type,
        SUM(t.amount) AS total_revenue,
        COUNT(DISTINCT t.merchant_id) AS num_merchants
    FROM transactions t
    JOIN merchants m
        ON t.merchant_id = m.merchant_id
    WHERE
        t.environment = 'LIVE'
        AND t.status = 'SUCCESS'
    GROUP BY
        m.business_type
),

total_revenue AS (
    SELECT
        SUM(total_revenue) AS grand_total_revenue
    FROM segment_revenue
)

SELECT
    sr.business_type,
    sr.num_merchants,
    sr.total_revenue,
    ROUND(
        sr.total_revenue * 100.0 / tr.grand_total_revenue,
        2
    ) AS pct_of_total_revenue
FROM segment_revenue sr
CROSS JOIN total_revenue tr
ORDER BY sr.total_revenue DESC;
--INSIGHTS: SMEs collectively generate slightly more revenue than enterprises, highlighting
--the importance of scaling mid-market merchants rather than relying solely on a few large accounts.


-- PAYMENT METHOD ANALYSIS
--18. Which payment methods are most popular? Which have best success rates?
WITH payment_method_stats AS (
    SELECT
        payment_method,
        COUNT(*) AS total_transactions,
        SUM(CASE WHEN status = 'SUCCESS' THEN 1 ELSE 0 END) AS successful_transactions,
        SUM(CASE WHEN status = 'FAILED' THEN 1 ELSE 0 END) AS failed_transactions,
        SUM(CASE WHEN status = 'SUCCESS' THEN amount ELSE 0 END) AS total_revenue,
        AVG(CASE WHEN status = 'SUCCESS' THEN amount END) AS avg_transaction_value
    FROM transactions
    WHERE
        environment = 'LIVE'
    GROUP BY payment_method
)

SELECT
    payment_method,
    total_transactions,
    successful_transactions,
    failed_transactions,
    ROUND(successful_transactions * 100.0 / NULLIF(total_transactions, 0), 2)
        AS success_rate_pct,
    total_revenue,
    avg_transaction_value
FROM payment_method_stats
ORDER BY total_transactions DESC;

--19. Payment Method by Merchant Size
WITH segment_method_txns AS (
    SELECT
        m.business_type,
        t.payment_method,
        COUNT(*) AS total_transactions
    FROM transactions t
    JOIN merchants m
        ON t.merchant_id = m.merchant_id
    WHERE
        t.environment = 'LIVE'
    GROUP BY
        m.business_type,
        t.payment_method
),

segment_totals AS (
    SELECT
        business_type,
        SUM(total_transactions) AS segment_total_txns
    FROM segment_method_txns
    GROUP BY business_type
)

SELECT
    sm.business_type,
    sm.payment_method,
    sm.total_transactions,
    ROUND(
        sm.total_transactions * 100.0 / st.segment_total_txns,
        2
    ) AS pct_of_segment_transactions
FROM segment_method_txns sm
JOIN segment_totals st
    ON sm.business_type = st.business_type
ORDER BY
    sm.business_type,
    pct_of_segment_transactions DESC;

--20. Cohort LTV (Lifetime Value)
--Cohort LTV = cumulative fees generated by a signup cohort over time
WITH merchant_cohorts AS (
    SELECT
        merchant_id,
        DATEFROMPARTS(
            YEAR(signup_timestamp),
            MONTH(signup_timestamp),
            1
        ) AS cohort_month
    FROM merchants
),
merchant_monthly_revenue AS (
    SELECT
        t.merchant_id,
        DATEFROMPARTS(
            YEAR(t.transaction_timestamp),
            MONTH(t.transaction_timestamp),
            1
        ) AS revenue_month,
        SUM(t.amount) AS monthly_revenue
    FROM transactions t
    WHERE
        t.environment = 'LIVE'
        AND t.status = 'SUCCESS'
    GROUP BY
        t.merchant_id,
        DATEFROMPARTS(
            YEAR(t.transaction_timestamp),
            MONTH(t.transaction_timestamp),
            1
        )
),

cohort_revenue AS (
    SELECT
        mc.cohort_month,
        DATEDIFF(
            MONTH,
            mc.cohort_month,
            mmr.revenue_month
        ) AS months_since_signup,
        SUM(mmr.monthly_revenue) AS cohort_monthly_revenue
    FROM merchant_cohorts mc
    JOIN merchant_monthly_revenue mmr
        ON mc.merchant_id = mmr.merchant_id
    GROUP BY
        mc.cohort_month,
        DATEDIFF(
            MONTH,
            mc.cohort_month,
            mmr.revenue_month
        )
)

SELECT
    cohort_month,
    months_since_signup,
    cohort_monthly_revenue,

    SUM(cohort_monthly_revenue) OVER (
        PARTITION BY cohort_month
        ORDER BY months_since_signup
        ROWS UNBOUNDED PRECEDING
    ) AS cumulative_cohort_ltv
FROM cohort_revenue
ORDER BY
    cohort_month,
    months_since_signup;
--INSIGHTS: Calculated Cohort LTV by tracking cumulative transaction fees over time.
--Newer cohorts monetize faster and slightly outperform earlier ones, indicating improvements in activation and early merchant engagement.


--MACHINE LEARNING MODELS
--1. Merchant Churn Model
DECLARE @observation_end DATE;

SELECT
    @observation_end = DATEADD(day, -30, MAX(transaction_timestamp))
FROM transactions;

WITH observation_txns AS (
    SELECT
        t.merchant_id,
        t.transaction_timestamp,
        t.amount,
        t.status,
        t.payment_method
    FROM transactions t
    WHERE
        t.environment = 'LIVE'
        AND t.transaction_timestamp <= @observation_end
),
future_txns AS (
    SELECT DISTINCT
        t.merchant_id
    FROM transactions t
    WHERE
        t.environment = 'LIVE'
        AND t.status = 'SUCCESS'
        AND t.transaction_timestamp > @observation_end
        AND t.transaction_timestamp <= DATEADD(day, 30, @observation_end)
),
merchant_aggregates AS (
    SELECT
        merchant_id,

        COUNT(*) AS total_transactions,
        SUM(CASE WHEN status = 'SUCCESS' THEN amount ELSE 0 END)
            AS total_volume_processed,
        AVG(amount) AS avg_transaction_amount,

        AVG(CASE WHEN status = 'SUCCESS' THEN 1.0 ELSE 0.0 END)
            AS successful_transaction_rate,
        AVG(CASE WHEN status = 'FAILED' THEN 1.0 ELSE 0.0 END)
            AS failure_rate,

        MAX(transaction_timestamp) AS last_transaction_date,
        COUNT(DISTINCT payment_method) AS num_payment_methods_used
    FROM observation_txns
    GROUP BY merchant_id
),
recent_activity AS (
    SELECT
        merchant_id,

        SUM(CASE
            WHEN transaction_timestamp > DATEADD(day, -30, @observation_end)
            THEN 1 ELSE 0 END) AS txns_last_30d,

        SUM(CASE
            WHEN transaction_timestamp BETWEEN
                 DATEADD(day, -60, @observation_end)
             AND DATEADD(day, -31, @observation_end)
            THEN 1 ELSE 0 END) AS txns_prev_30d,

        SUM(CASE
            WHEN transaction_timestamp > DATEADD(day, -30, @observation_end)
            THEN amount ELSE 0 END) AS volume_last_30d,

        SUM(CASE
            WHEN transaction_timestamp BETWEEN
                 DATEADD(day, -60, @observation_end)
             AND DATEADD(day, -31, @observation_end)
            THEN amount ELSE 0 END) AS volume_prev_30d
    FROM observation_txns
    GROUP BY merchant_id
),
merchant_base AS (
    SELECT
        m.merchant_id,
        DATEDIFF(day, m.signup_timestamp, @observation_end)
            AS merchant_age_days,
        m.business_type
    FROM merchants m
)
SELECT
    ma.merchant_id,

    -- Core behavior
    ma.total_transactions,
    ma.total_volume_processed,
    ma.avg_transaction_amount,
    ma.successful_transaction_rate,
    ma.failure_rate,

    -- Recency
    DATEDIFF(day, ma.last_transaction_date, @observation_end)
        AS days_since_last_transaction,

    -- Trend
    ra.txns_last_30d,
    ra.txns_prev_30d,
    ra.volume_last_30d,
    ra.volume_prev_30d,

    CASE
        WHEN ra.volume_prev_30d = 0 THEN NULL
        ELSE (ra.volume_last_30d - ra.volume_prev_30d) * 1.0
             / ra.volume_prev_30d
    END AS volume_change_pct_30d,

    -- Adoption
    ma.num_payment_methods_used,

    -- Merchant context
    mb.merchant_age_days,
    mb.business_type,

    CASE
        WHEN ft.merchant_id IS NULL THEN 1
        ELSE 0
    END AS churn_flag

FROM merchant_aggregates ma
JOIN recent_activity ra
    ON ma.merchant_id = ra.merchant_id
JOIN merchant_base mb
    ON ma.merchant_id = mb.merchant_id
LEFT JOIN future_txns ft
    ON ma.merchant_id = ft.merchant_id;


--2. Payment Fraud Detection
WITH live_txns AS (
    SELECT
        t.transaction_id,
        t.merchant_id,
        t.transaction_timestamp,
        t.amount,
        t.status,
        t.payment_method
    FROM transactions t
    WHERE
        t.environment = 'LIVE'
),

merchant_stats AS (
    SELECT
        merchant_id,
        AVG(amount) AS merchant_avg_amount,
        STDEV(amount) AS merchant_std_amount
    FROM live_txns
    GROUP BY merchant_id
),

merchant_last_txn AS (
    SELECT
        transaction_id,
        merchant_id,
        transaction_timestamp,
        LAG(transaction_timestamp) OVER (
            PARTITION BY merchant_id
            ORDER BY transaction_timestamp
        ) AS prev_transaction_timestamp
    FROM live_txns
),

merchant_failure_7d AS (
    SELECT
        t1.merchant_id,
        t1.transaction_id,
        SUM(
            CASE WHEN t2.status = 'FAILED' THEN 1 ELSE 0 END
        ) * 1.0 / COUNT(*) AS merchant_failure_rate_7d
    FROM live_txns t1
    JOIN live_txns t2
        ON t1.merchant_id = t2.merchant_id
       AND t2.transaction_timestamp BETWEEN
            DATEADD(day, -7, t1.transaction_timestamp)
            AND t1.transaction_timestamp
    GROUP BY
        t1.merchant_id,
        t1.transaction_id
)

SELECT
    t.transaction_id,
    t.merchant_id,
    t.transaction_timestamp,

    -- Amount
    t.amount AS transaction_amount,

    -- Merchant baseline
    ms.merchant_avg_amount,
    ms.merchant_std_amount,

    -- Time features
    DATEPART(hour, t.transaction_timestamp) AS hour_of_day,
    CASE
        WHEN DATENAME(weekday, t.transaction_timestamp) IN ('Saturday', 'Sunday')
        THEN 1 ELSE 0
    END AS is_weekend,

    -- Timing / velocity base
    DATEDIFF(
        second,
        mlt.prev_transaction_timestamp,
        t.transaction_timestamp
    ) AS time_since_last_tx_sec,

    -- Merchant context
    DATEDIFF(
        day,
        m.signup_timestamp,
        t.transaction_timestamp
    ) AS merchant_age_days,

    CASE
        WHEN DATEDIFF(day, m.signup_timestamp, t.transaction_timestamp) <= 14
        THEN 1 ELSE 0
    END AS is_early_lifecycle_tx,

    -- Channel
    t.payment_method,

    -- Reliability
    mf.merchant_failure_rate_7d

FROM live_txns t
JOIN merchant_stats ms
    ON t.merchant_id = ms.merchant_id
JOIN merchant_last_txn mlt
    ON t.transaction_id = mlt.transaction_id
JOIN merchants m
    ON t.merchant_id = m.merchant_id
LEFT JOIN merchant_failure_7d mf
    ON t.transaction_id = mf.transaction_id;

--3. Merchant Segmentation (KMeans Clustering)
WITH live_txns AS (
    SELECT
        merchant_id,
        transaction_timestamp,
        amount,
        status,
        payment_method
    FROM transactions
    WHERE environment = 'LIVE'
),

merchant_aggregates AS (
    SELECT
        merchant_id,

        -- Revenue & scale
        SUM(amount) AS total_transaction_volume,
        AVG(amount) AS avg_transaction_size,

        -- Engagement
        COUNT(*) AS transaction_frequency,

        -- Quality
        SUM(CASE WHEN status = 'SUCCESS' THEN 1 ELSE 0 END) * 1.0
            / COUNT(*) AS success_rate,

        -- Platform adoption
        COUNT(DISTINCT payment_method) AS payment_method_diversity,

        -- Activity window
        MIN(transaction_timestamp) AS first_txn_date,
        MAX(transaction_timestamp) AS last_txn_date
    FROM live_txns
    GROUP BY merchant_id
),

merchant_months AS (
    SELECT
        merchant_id,
        COUNT(DISTINCT
            DATEFROMPARTS(
                YEAR(transaction_timestamp),
                MONTH(transaction_timestamp),
                1
            )
        ) AS active_months
    FROM live_txns
    GROUP BY merchant_id
),

merchant_lifecycle AS (
    SELECT
        merchant_id,
        DATEDIFF(day, signup_timestamp, GETDATE()) AS merchant_age_days
    FROM merchants
)

SELECT
    ma.merchant_id,

    -- Revenue & scale
    ma.total_transaction_volume,
    ma.avg_transaction_size,

    -- Engagement
    ma.transaction_frequency,
    CAST(ma.transaction_frequency AS FLOAT)
        / NULLIF(mm.active_months, 1) AS avg_monthly_transactions,

    -- Adoption & quality
    ma.payment_method_diversity,
    ma.success_rate,

    -- Lifecycle
    ml.merchant_age_days

FROM merchant_aggregates ma
JOIN merchant_months mm
    ON ma.merchant_id = mm.merchant_id
JOIN merchant_lifecycle ml
    ON ma.merchant_id = ml.merchant_id;





