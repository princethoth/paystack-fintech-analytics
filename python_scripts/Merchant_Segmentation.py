#!/usr/bin/env python
# coding: utf-8

# In[1]:


import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns


# In[2]:


df = pd.read_csv('Merchant Segmentation.csv')


# In[3]:


df.head()


# In[4]:


df.info()


# In[11]:


df['avg_monthly_transactions'] = df['avg_monthly_transactions'].fillna(df['avg_monthly_transactions'].median())


# In[12]:


df.info()


# In[13]:


X = df.drop('merchant_id', axis=1)


# In[14]:


from sklearn.preprocessing import StandardScaler


# In[15]:


scaler = StandardScaler()
X_scaled = scaler.fit_transform(X)


# In[16]:


from sklearn.cluster import KMeans


# In[ ]:


inertia = []
for k in range(2, 10):
    km = KMeans(n_clusters=k, random_state=42)
    km.fit(X_scaled)
    inertia.append(km.inertia_)


# In[18]:


plt.plot(range(2,10), inertia)
plt.xlabel("k")
plt.ylabel("Inertia")
plt.title("Elbow Method")
plt.savefig('Kmeans_Graph.png', dpi=300, bbox_inches='tight')
plt.show()


# In[19]:


kmeans = KMeans(n_clusters=3, random_state=42)
X['Cluster'] = kmeans.fit_predict(X_scaled)


# In[20]:


summary = X.groupby('Cluster').agg({
    'total_transaction_volume': 'mean',
    'avg_transaction_size': 'mean',
    'transaction_frequency': 'mean',
    'avg_monthly_transactions': 'mean',
    'payment_method_diversity': 'mean',
    'success_rate': 'mean',
    'merchant_age_days': 'mean',
}).round(2)
print(summary)


# In[22]:


# Scatter plot: Total Transaction Volume vs Merchant Age Days
sns.scatterplot(
    data=summary,
    x='merchant_age_days',
    y='total_transaction_volume',
    hue='Cluster',
    palette='viridis',
    alpha=0.6
)
plt.title('Behavioral Segments')
plt.xlabel('Age Days')
plt.ylabel('Transaction Volume')
plt.legend(title='Cluster', bbox_to_anchor=(1.05, 1), loc='upper left')
plt.savefig('behavioral_segments.png', dpi=300, bbox_inches='tight')
plt.show()


# In[23]:


summary = summary.reset_index()   # adds 'Cluster' as a column
cluster_names = {
    0: 'Growing Merchants',
    1: 'Dormant Merchants',
    2: 'Power Merchants'
}
summary['Segment_Name'] = summary['Cluster'].map(cluster_names)


# In[24]:


print(summary)


# In[28]:


df['Cluster'] = kmeans.fit_predict(X_scaled)


# In[29]:


summary = X.groupby('Cluster').agg({
    'total_transaction_volume': 'mean',
    'avg_transaction_size': 'mean',
    'transaction_frequency': 'mean',
    'avg_monthly_transactions': 'mean',
    'payment_method_diversity': 'mean',
    'success_rate': 'mean',
    'merchant_age_days': 'mean',
}).round(2)
print(summary)


# In[43]:


df.head()


# In[42]:


df = df.reset_index()   # adds 'Cluster' as a column
cluster_names = {
    0: 'Growing Merchants',
    1: 'Dormant Merchants',
    2: 'Power Merchants'
}
df['Segment_Name'] = df['Cluster'].map(cluster_names)


# In[44]:


df.to_csv('merchants_with_segments.csv', index=False)


# In[46]:


df.info()


# In[ ]:





# In[47]:


df['Segment_Name'].value_counts()


# In[48]:


churn_df = pd.read_csv("churn_predictions_with_risk.csv")


# In[49]:


churn_df = churn_df[
    ["merchant_id", "churn_flag", "churn_probability"]
]


# In[50]:


segmentation_with_churn = df.merge(
    churn_df,
    on="merchant_id",
    how="left"
)


# In[52]:


segmentation_with_churn.info()


# In[53]:


segment_churn = (
    segmentation_with_churn
    .groupby("Segment_Name")
    .agg(
        merchants=("merchant_id", "count"),
        churned=("churn_flag", "sum"),
        avg_churn_prob=("churn_probability", "mean")
    )
)

segment_churn["churn_rate"] = (
    segment_churn["churned"] / segment_churn["merchants"]
)

segment_churn.sort_values("churn_rate", ascending=False)


# In[ ]:





# In[ ]:





# In[39]:


revenue_by_cluster = (
    df_segments
    .groupby('Cluster')['total_transaction_volume']
    .sum()
    .reset_index()
)

# Percentage of total revenue
revenue_by_cluster['pct_of_total_revenue'] = (
    revenue_by_cluster['total_transaction_volume']
    / revenue_by_cluster['total_transaction_volume'].sum()
    * 100
)

print(revenue_by_cluster)


# In[40]:


plt.figure(figsize=(6,6))
plt.pie(
    revenue_by_cluster['total_transaction_volume'],
    labels=revenue_by_cluster['Cluster'],
    autopct='%1.1f%%',
    startangle=140
)
plt.title('Revenue Share by Merchant Segment')
plt.tight_layout()
plt.show()


# In[45]:


plt.savefig('revenue share by merchant segment.png', dpi=300, bbox_inches='tight')


# In[ ]:


get_ipython().system('jupyter nbconvert --to python Churn_Prediction.ipynb')

