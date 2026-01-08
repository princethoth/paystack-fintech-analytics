CREATE TABLE merchants (
    merchant_id        VARCHAR(50) PRIMARY KEY,
    signup_timestamp  DATETIME2 NOT NULL,
    country            VARCHAR(50) NOT NULL,
    industry           VARCHAR(100) NOT NULL,
    business_type      VARCHAR(50),
    signup_channel     VARCHAR(50)
);

TRUNCATE TABLE transactions;
DELETE FROM merchants;
TRUNCATE TABLE api_keys;

SELECT
    OBJECT_NAME(fk.parent_object_id) AS child_table,
    COL_NAME(fkc.parent_object_id, fkc.parent_column_id) AS child_column
FROM sys.foreign_keys fk
JOIN sys.foreign_key_columns fkc
    ON fk.object_id = fkc.constraint_object_id
WHERE OBJECT_NAME(fk.referenced_object_id) = 'merchants';







CREATE TABLE api_keys (
    api_key_id         VARCHAR(50) PRIMARY KEY,
    merchant_id        VARCHAR(50) NOT NULL,
    created_timestamp  DATETIME2 NOT NULL,
    environment        VARCHAR(10) NOT NULL,
    key_type           VARCHAR(20),

    CONSTRAINT fk_api_keys_merchant
        FOREIGN KEY (merchant_id)
        REFERENCES merchants (merchant_id),

    CONSTRAINT chk_api_keys_environment
        CHECK (environment IN ('TEST', 'LIVE'))
);

CREATE TABLE transactions (
    transaction_id        VARCHAR(50) PRIMARY KEY,
    merchant_id           VARCHAR(50) NOT NULL,
    transaction_timestamp DATETIME2 NOT NULL,
    environment            VARCHAR(10) NOT NULL,
    status                 VARCHAR(20) NOT NULL,
    amount                 DECIMAL(18, 2),
    currency               VARCHAR(10),
    payment_method         VARCHAR(50),
    failure_reason         VARCHAR(255),

    CONSTRAINT fk_transactions_merchant
        FOREIGN KEY (merchant_id)
        REFERENCES merchants (merchant_id),

    CONSTRAINT chk_transactions_environment
        CHECK (environment IN ('TEST', 'LIVE')),

    CONSTRAINT chk_transactions_status
        CHECK (status IN ('SUCCESS', 'FAILED'))
);


CREATE VIEW merchant_onboarding AS
WITH txn_agg AS (
    SELECT
        merchant_id,

        MIN(CASE
            WHEN environment = 'TEST'
             AND status = 'SUCCESS'
            THEN transaction_timestamp
        END) AS first_test_txn_timestamp,

        MIN(CASE
            WHEN environment = 'LIVE'
             AND status = 'SUCCESS'
            THEN transaction_timestamp
        END) AS first_live_txn_timestamp

    FROM transactions
    GROUP BY merchant_id
)

SELECT
    m.merchant_id,
    m.signup_timestamp,

    t.first_test_txn_timestamp,
    t.first_live_txn_timestamp,

    CASE
        WHEN t.first_live_txn_timestamp IS NOT NULL
        THEN 1 ELSE 0
    END AS is_activated,

    DATEDIFF(
        day,
        m.signup_timestamp,
        t.first_test_txn_timestamp
    ) AS days_signup_to_test,

    DATEDIFF(
        day,
        m.signup_timestamp,
        t.first_live_txn_timestamp
    ) AS days_signup_to_live,

    DATEDIFF(
        day,
        t.first_test_txn_timestamp,
        t.first_live_txn_timestamp
    ) AS days_test_to_live

FROM merchants m
LEFT JOIN txn_agg t
    ON m.merchant_id = t.merchant_id;

    CREATE VIEW merchant_activity_daily AS
SELECT
    merchant_id,
    CAST(transaction_timestamp AS DATE) AS activity_date,

    COUNT(*) AS successful_live_txn_count,
    SUM(amount) AS total_live_amount

FROM transactions
WHERE environment = 'LIVE'
  AND status = 'SUCCESS'

GROUP BY
    merchant_id,
    CAST(transaction_timestamp AS DATE);

CREATE VIEW merchant_lifecycle AS
WITH dataset_max_date AS (
    SELECT
        MAX(CAST(transaction_timestamp AS DATE)) AS as_of_date
    FROM transactions
    WHERE environment = 'LIVE'
),
last_activity AS (
    SELECT
        merchant_id,
        MAX(activity_date) AS last_live_activity_date
    FROM merchant_activity_daily
    GROUP BY merchant_id
)

SELECT
    m.merchant_id,
    o.is_activated,
    la.last_live_activity_date,

    DATEDIFF(
        day,
        la.last_live_activity_date,
        d.as_of_date
    ) AS days_since_last_activity,

    CASE
        WHEN o.is_activated = 0
            THEN 'NOT_ACTIVATED'
        WHEN la.last_live_activity_date IS NULL
            THEN 'NOT_ACTIVATED'
        WHEN DATEDIFF(
                day,
                la.last_live_activity_date,
                d.as_of_date
             ) > 30
            THEN 'CHURNED'
        ELSE 'ACTIVE'
    END AS lifecycle_status

FROM merchants m
LEFT JOIN merchant_onboarding o
    ON m.merchant_id = o.merchant_id
LEFT JOIN last_activity la
    ON m.merchant_id = la.merchant_id
CROSS JOIN dataset_max_date d;







