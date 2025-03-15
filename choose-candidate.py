import pandas as pd

data = pd.read_csv("candidates.csv")
data.drop_duplicates(inplace=True)
columns = ["Spectral mod B", "Spectral lag-1 mod M", "Spectral lag-2 mod M"]

# Keep only the upper 25% quantile
lower_bounds = [data[col].quantile(0.75) for col in columns]
for lower_bound, col in zip(lower_bounds, columns):
  data = data.loc[data[col] >= lower_bound]

# Convert the period to a number from 0 to 1 (full-period)
data["Period"] = data["Multiplier"].apply(int, base=16) / (1 << 64)

data["Spectral"] = (data[columns] * [0.4, 0.4, 0.2]).sum(axis=1)
data["Score"] = data["Spectral"] * data["Period"]

print(data.describe())
print(data.sort_values(by="Score", ascending=False).head(50))
