import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

data = pd.read_csv("candidates.csv")
data.drop_duplicates(inplace=True)

data["min_fm"] = data[["MinFM mod B", "MinFM mod M"]].min(axis=1)
data["geom_mean"] = (data["Spectral mod B"] * data["Spectral mod M"]) ** 0.5

threshold = data["min_fm"].quantile(0.99)
survivors = data.loc[data["min_fm"] >= threshold]
chosen = survivors.loc[survivors["geom_mean"].idxmax()]

print(survivors.describe())
print()
print(chosen)

for name, x_col, y_col in [
  ("harmonic", "Spectral mod B", "Spectral mod M"),
  ("min_fm", "MinFM mod B", "MinFM mod M"),
]:
  fig, ax = plt.subplots()
  ax.scatter(data[x_col], data[y_col], s=2, alpha=0.3, label="all")
  ax.scatter(survivors[x_col], survivors[y_col], s=4, alpha=0.7, label="survivors")
  ax.scatter([chosen[x_col]], [chosen[y_col]], s=80, marker="*", c="red", label="chosen")
  ax.set_xlabel(x_col)
  ax.set_ylabel(y_col)
  ax.legend()
  fig.tight_layout()
  fig.savefig(f"charts/{name}.png", dpi=300)
