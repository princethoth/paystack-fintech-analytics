#!/usr/bin/env python
# coding: utf-8

# In[1]:


import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns


# In[27]:


df = pd.read_csv('Churn Model.csv')


# In[28]:


df.head()


# In[30]:


df.info()


# In[31]:


df['churn_flag'].value_counts()


# In[32]:


X = df.drop(['merchant_id', 'volume_change_pct_30d', 'churn_flag'], axis=1)
y = df['churn_flag']


# In[33]:


from sklearn.model_selection import train_test_split


# In[34]:


X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.3, random_state=101, stratify=y)


# In[35]:


from sklearn.compose import ColumnTransformer
from sklearn.preprocessing import OneHotEncoder, StandardScaler


# In[36]:


num_cols = X_train.select_dtypes(include=['int64', 'float64']).columns
cat_cols = X_train.select_dtypes(include=['object']).columns


# In[37]:


preprocessor = ColumnTransformer(
    transformers=[
        ('num', StandardScaler(), num_cols),                  
        ('cat', OneHotEncoder(handle_unknown='ignore'), cat_cols)
    ]
)


# In[38]:


from sklearn.ensemble import RandomForestClassifier


# In[39]:


rfc = RandomForestClassifier(
    n_estimators=300,
    max_depth=None,
    min_samples_leaf=5,
    class_weight="balanced",
    random_state=42,
    n_jobs=-1
)


# In[40]:


from sklearn.pipeline import Pipeline


# In[41]:


rfc_pipeline = Pipeline([
    ('preprocessor', preprocessor),
    ('classifier', rfc)
])


# In[42]:


rfc_pipeline.fit(X_train, y_train)
rfc_pred = rfc_pipeline.predict(X_test)
rfc_pred_proba = rfc_pipeline.predict_proba(X_test)[:, 1]


# In[43]:


from sklearn.metrics import accuracy_score, classification_report, confusion_matrix, roc_auc_score


# In[44]:


print("RANDOM FOREST RESULTS")
print(f"Accuracy: {accuracy_score(y_test, rfc_pred):.4f}")
print(f"ROC-AUC Score: {roc_auc_score(y_test, rfc_pred_proba):.4f}")
print("\nClassification Report:")
print(classification_report(y_test, rfc_pred, target_names=['Yes', 'No']))
print("\nConfusion Matrix:")
print(confusion_matrix(y_test, rfc_pred))


# In[51]:


rf_model = rfc_pipeline.named_steps['classifier']


# In[52]:


num_features = num_cols.tolist()

cat_features = (
    rfc_pipeline
    .named_steps['preprocessor']
    .named_transformers_['cat']
    .get_feature_names_out(cat_cols)
)


all_feature_names = num_features + list(cat_features)


# In[53]:


feature_importance_rf = pd.DataFrame({
    'feature': all_feature_names,
    'importance': rf_model.feature_importances_
}).sort_values('importance', ascending=False)

print(feature_importance_rf.head(10))


# In[55]:


cm = confusion_matrix(y_test, rfc_pred)
plt.figure(figsize=(8, 6))
sns.heatmap(cm, annot=True, fmt='d', cmap='Blues')
plt.title('Confusion Matrix - Merchant Churn Prediction')
plt.ylabel('Actual')
plt.xlabel('Predicted')
plt.savefig('confusion_matrix_churn.png')
plt.show()


# In[56]:


import joblib


# In[57]:


joblib.dump(rfc_pipeline, 'rf=rfc_pipeline.pkl')


# In[59]:


feature_importance_rf.to_csv('feature_importance.csv', index=False)


# In[61]:


all_pred_proba = rfc_pipeline.predict_proba(X)[:, 1]
df['churn_probability'] = all_pred_proba


# In[66]:


def risk_category(prob):
    if prob >= 0.66:
        return 'High Risk'
    elif prob >= 0.33:
        return 'Medium Risk'
    else:
        return 'Low Risk'
df["Churn_Risk_Level"] = df['churn_probability'].apply(risk_category)


# In[72]:


df["Churn_Risk_Level"].value_counts()


# In[71]:


df.to_csv("churn_predictions_with_risk.csv", index=False)


# In[74]:


df.sort_values("churn_probability", ascending=False).head(20)


# In[ ]:




