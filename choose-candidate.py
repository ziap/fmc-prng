import pandas as pd

data = pd.read_csv("candidates.csv")
data.drop_duplicates(inplace=True)

threshold_b = data["Spectral mod B"].quantile(0.95)
threshold_m = data["Spectral mod M"].quantile(0.95)

data = data.loc[data["Spectral mod B"] >= threshold_b]
data = data.loc[data["Spectral mod M"] >= threshold_m]

data["Period"] = data["Multiplier"].apply(int, base=16) / (1 << 64)

print(data.describe())
print(data.sort_values(by="Period", ascending=False).head(50))
