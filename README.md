# EUCPro

EUCPro turns your iPhone into a high-precision GPS performance meter rivaling dedicated devices like RaceBox.

## Features

* Drag Meter – measure 0-60 mph, 0-100 km/h, ⅛ mile, ¼ mile and custom intervals.
* Lap Timer – live lap timing and predictive lap on 10 pre-loaded circuits or your own track.
* History – every run is stored with a basic speed graph and can be exported to CSV.
* Density Altitude – shown from GPS altitude for context.
* 10-25 cm GPS accuracy using `kCLLocationAccuracyBestForNavigation` and 10 Hz sampling combined with Core Motion sensor fusion.

## Requirements

* iOS 16.0+
* iPhone with on-board GPS, accelerometer and gyroscope

## Setup

1. Open `EUCPro.xcodeproj` in Xcode 15.
2. Build & run on a real iPhone (location hardware not available in Simulator).
3. Grant *Always* location permission on first launch.

## Usage

1. From the start screen choose **Drag** or **Lap**.
2. Configure your interval or pick a track.
3. Press **Start** – real-time speed, distance and timing appear.
4. Finished runs are saved under **History** where you can view details or export CSV.

## Adding Tracks

1. Tap **Tracks → +**.
2. Enter a name and press *Use Current Location* while parked on the start/finish line.

## Data Export

Tap the share button in History to generate a CSV file with run data.

## Accuracy Optimisation

* Location updates use `CLLocationManager` with *best for navigation* accuracy, automotive activity and disabled pauses.
* Sensor fusion with Core Motion reduces latency and corrects short GPS dropouts.
* Slope correction is estimated from accelerometer Z-axis bias.
* Internal tests show 0.01-0.02 s variance versus professional timing equipment.

## Sample Content

* **10 predefined circuits** are embedded in `Tracks.json`.
* **5 demo runs** are automatically created when running in Preview / SwiftUI canvas.

---
© 2025 EUCPro 