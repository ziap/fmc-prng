import pandas as pd

data = pd.read_csv("candidates.csv")
data.drop_duplicates(inplace=True)

data = data.loc[data["Spectral score"] >= data["Spectral score"].quantile(0.95)]

data["Period"] = data["Multiplier"].apply(int, base=16) / (1 << 64)

print(data.describe())
print(data.sort_values(by="Period", ascending=False).head(50))
