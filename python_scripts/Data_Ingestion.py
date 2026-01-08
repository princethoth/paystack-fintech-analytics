#!/usr/bin/env python
# coding: utf-8

# In[22]:


import pandas as pd


# In[23]:


NUM_MERCHANTS = 800

P_API_KEY = 0.85
P_TEST_TXN = 0.75
P_LIVE_TXN = 0.55
P_REGULAR_USAGE = 0.35

START_DATE = pd.Timestamp("2024-01-01")
SIMULATION_DAYS = 240   # ~8 months


# In[13]:


# MERCHANTS
import pandas as pd
import numpy as np
import uuid
import random
from datetime import timedelta

np.random.seed(42)

merchants = []

for _ in range(NUM_MERCHANTS):
    signup_ts = START_DATE + timedelta(days=np.random.randint(0, 60))

    merchants.append({
        "merchant_id": f"m_{uuid.uuid4().hex[:10]}",
        "signup_timestamp": signup_ts,
        "country": "NG",
        "industry": random.choice(
            ["Ecommerce", "SaaS", "Education", "Logistics", "Fintech"]
        ),
        "business_type": random.choice(["SME", "Enterprise"]),
        "signup_channel": random.choice(["Web", "Referral", "Sales"])
    })

merchants_df = pd.DataFrame(merchants)


# In[ ]:





# In[14]:


# API KEYS
api_keys = []

for _, m in merchants_df.iterrows():
    if np.random.rand() < P_API_KEY:
        # TEST key
        api_keys.append({
            "api_key_id": f"k_{uuid.uuid4().hex[:10]}",
            "merchant_id": m.merchant_id,
            "created_timestamp": m.signup_timestamp + timedelta(days=1),
            "environment": "TEST",
            "key_type": "secret"
        })

        # Some create LIVE keys
        if np.random.rand() < 0.65:
            api_keys.append({
                "api_key_id": f"k_{uuid.uuid4().hex[:10]}",
                "merchant_id": m.merchant_id,
                "created_timestamp": m.signup_timestamp + timedelta(days=5),
                "environment": "LIVE",
                "key_type": "secret"
            })

api_keys_df = pd.DataFrame(api_keys)


# In[ ]:





# In[15]:


# TRANSACTIONS
transactions = []

for _, m in merchants_df.iterrows():
    merchant_id = m.merchant_id

    # ---------- TEST TRANSACTIONS ----------
    if np.random.rand() < P_TEST_TXN:
        num_test = np.random.randint(5, 15)

        for i in range(num_test):
            transactions.append({
                "transaction_id": f"t_{uuid.uuid4().hex[:12]}",
                "merchant_id": merchant_id,
                "transaction_timestamp": m.signup_timestamp + timedelta(days=2+i),
                "environment": "TEST",
                "status": "SUCCESS",
                "amount": 0.00,
                "currency": "NGN",
                "payment_method": "card",
                "failure_reason": None
            })

        # ---------- LIVE TRANSACTIONS ----------
        if np.random.rand() < P_LIVE_TXN:
            current_day = m.signup_timestamp + timedelta(days=np.random.randint(7, 20))

            FAILURE_RATE = 0.08  # 8% realistic failure rate

            FAILURE_REASONS = [
                "Insufficient Funds",
                "Bank Timeout",
                "Network Error",
                "Invalid Card"
            ]

            status = "FAILED" if np.random.rand() < FAILURE_RATE else "SUCCESS"
            failure_reason = random.choice(FAILURE_REASONS) if status == "FAILED" else None

            # Activation transaction
            transactions.append({
                "transaction_id": f"t_{uuid.uuid4().hex[:12]}",
                "merchant_id": merchant_id,
                "transaction_timestamp": current_day,
                "environment": "LIVE",
                "status": status,
                "amount": np.random.randint(2000, 80000),
                "currency": "NGN",
                "payment_method": random.choice(["card", "bank", "ussd"]),
                "failure_reason": failure_reason
            })

            # Decide merchant type
            is_power_user = np.random.rand() < P_REGULAR_USAGE

            current_day = activation_day + timedelta(days=1)
            last_active_day = activation_day + timedelta(days=SIMULATION_DAYS)

            while current_day < last_active_day:
                # Churn chance (30-day inactivity)
                if np.random.rand() < 0.02:
                    break

                daily_txns = (
                    np.random.randint(1, 4) if is_power_user
                    else np.random.randint(0, 2)
                )

                for _ in range(daily_txns):
                    transactions.append({
                        "transaction_id": f"t_{uuid.uuid4().hex[:12]}",
                        "merchant_id": merchant_id,
                        "transaction_timestamp": current_day,
                        "environment": "LIVE",
                        "status": "SUCCESS",
                        "amount": np.random.randint(2000, 80000),
                        "currency": "NGN",
                        "payment_method": random.choice(["card", "bank", "ussd"]),
                        "failure_reason": None
                    })

                current_day += timedelta(days=1)


# In[16]:


# Activation rate
activated = transactions_df[
    (transactions_df.environment == "LIVE") &
    (transactions_df.status == "SUCCESS")
]["merchant_id"].nunique()

activated / merchants_df.shape[0]


# In[17]:


transactions_df = pd.DataFrame(transactions)

print("Merchants:", len(merchants_df))
print("API Keys:", len(api_keys_df))
print("Transactions:", len(transactions_df))


# In[14]:


merchants_df.shape


# In[15]:


merchants_df.isnull().sum()


# In[28]:


api_keys_df.isnull().sum()


# In[30]:


transactions_df.isnull().sum()


# In[ ]:





# In[16]:


# INSERT INTO SQL DATABASE


# In[18]:


import pyodbc

driver = "ODBC Driver 17 for SQL Server"
server = "THOTH\\SQLEXPRESS"
database = "PaystackFintechDB"

conn = pyodbc.connect(
    f"DRIVER={{{driver}}};"
    f"SERVER={server};"
    f"DATABASE={database};"
    "Trusted_Connection=yes;"
)

cursor = conn.cursor()


# In[24]:


insert_query = """
INSERT INTO merchants (
    merchant_id,
    signup_timestamp,
    country,
    industry,
    business_type,
    signup_channel
)
VALUES (?, ?, ?, ?, ?, ?)
"""

rows_inserted = 0

for _, row in merchants_df.iterrows():
    cursor.execute(
        insert_query,
        row.merchant_id,
        row.signup_timestamp,
        row.country,
        row.industry,
        row.business_type,
        row.signup_channel
    )
    rows_inserted += 1

conn.commit()

print(f"Inserted {rows_inserted} merchants")


# In[ ]:





# In[25]:


insert_api_keys = """
INSERT INTO api_keys (
    api_key_id,
    merchant_id,
    created_timestamp,
    environment,
    key_type
)
VALUES (?, ?, ?, ?, ?)
"""

rows_inserted = 0

for _, row in api_keys_df.iterrows():
    cursor.execute(
        insert_api_keys,
        row.api_key_id,
        row.merchant_id,
        row.created_timestamp,
        row.environment,
        row.key_type
    )
    rows_inserted += 1

conn.commit()

print(f"Inserted {rows_inserted} API keys")


# In[ ]:





# In[26]:


insert_transactions = """
INSERT INTO transactions (
    transaction_id,
    merchant_id,
    transaction_timestamp,
    environment,
    status,
    amount,
    currency,
    payment_method,
    failure_reason
)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
"""

batch_size = 1000
batch = []

for _, row in transactions_df.iterrows():
    batch.append((
        row.transaction_id,
        row.merchant_id,
        row.transaction_timestamp,
        row.environment,
        row.status,
        row.amount,
        row.currency,
        row.payment_method,
        row.failure_reason
    ))

    if len(batch) == batch_size:
        cursor.executemany(insert_transactions, batch)
        conn.commit()
        batch = []

# Insert remaining
if batch:
    cursor.executemany(insert_transactions, batch)
    conn.commit()

print("Transactions inserted successfully")


# In[ ]:




