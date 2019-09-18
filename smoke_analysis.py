# Using the CSV file created by the Pike parser from the SourcePawn log,
# perform some analysis and prediction.

from sklearn.linear_model import LogisticRegression # ImportError? 'pip install sklearn'
import pandas as pd

def parse_timing(x):
	if not x: return float("nan")
	# Return 1 for "+0" and then increment everything else beyond that
	# Allows +0 and -0 to be distinguished.
	return int(x) + x.startswith("+")
data = pd.read_csv("smoke_analysis.csv", converters={"timing": parse_timing})

# Calculate the distance-squared to our defined start point (-299.96,-1163.96)
# If the throw wasn't fairly close to that, it's irrelevant to this analysis.
data["origin_dsq"] = (data["x1"] - -299.96) ** 2 + (data["y1"] - -1163.96) ** 2
data = data[data["timing"].notnull() & (data["origin_dsq"] < 1)]

parameters = data.filter(items=["a1", "a2", "timing"])
target = data["result"] == "GOOD"
# print(parameters)

from sklearn import svm
clf = svm.SVC(gamma=0.001)
clf.fit(parameters[:-10], target[:-10])

output = data[-10:].filter(["result"])
output["Predicted"] = clf.predict(parameters[-10:])
print(output)
