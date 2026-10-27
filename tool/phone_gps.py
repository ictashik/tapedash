#!/usr/bin/env python3
"""A faked GPS for a real phone, from the shell (docs/NAV.md, "How the phone was driven").

There is no drive to test on, so Google Maps is given a position that moves along a
straight line from a fixed test origin in central Bangalore towards a fixed
destination. It is not the person's own place and never reads the phone's.

  tool/phone_gps.py prepare [-s SERIAL]                      allow the shell to mock location,
                                                             add gps and network test providers,
                                                             and put the car at the origin
  tool/phone_gps.py drive KMH SECONDS [-s SERIAL] [--shots DIR]
                                                             move at KMH for SECONDS, then clean up
                                                             (a screenshot every 8 s into DIR)
  tool/phone_gps.py cleanup [-s SERIAL]                      remove both providers, restore the app-op

Start the route in Maps between `prepare` and `drive`:
  adb shell "am start -a android.intent.action.VIEW -d 'google.navigation:q=12.9352,77.6245&mode=d' \\
             -p com.google.android.apps.maps"

What it changes on the phone, and puts back (also on an error or Ctrl-C):
  * the app-op MOCK_LOCATION of the shell (uid 2000): `allow` while it runs, `default` after;
  * two test location providers, `gps` and `network` (both, so that the real network fix does not
    mix in): added, then removed. While they exist, EVERY app on the phone sees the fake position.

The shell can send no speed and no bearing: an app that reads the receiver's speed (TapeDash's GPS-only
drive) sees none; Google Maps works it out. The phone must be unlocked and awake (do not bypass the lock).
Afterwards `adb shell dumpsys location | grep -i "test provider"` must print nothing.
"""
import argparse
import math
import signal
import subprocess
import sys
import time

ORIGIN = (12.9716, 77.5946)
DEST = (12.9352, 77.6245)
PROVIDERS = ("gps", "network")


class Phone:
    def __init__(self, serial):
        self.adb = ["adb"] + (["-s", serial] if serial else [])

    def sh(self, cmd):
        return subprocess.run(self.adb + ["shell", cmd], capture_output=True, text=True).stdout

    def png(self):
        return subprocess.run(self.adb + ["exec-out", "screencap", "-p"], capture_output=True).stdout

    def at(self, lat, lon):
        return ";".join(
            f"cmd location providers set-test-provider-location {p} --location {lat:.6f},{lon:.6f} --accuracy 5"
            for p in PROVIDERS
        )

    def prepare(self):
        self.sh("appops set 2000 android:mock_location allow")
        for p in PROVIDERS:
            self.sh(f"cmd location providers add-test-provider {p} --supportsSpeed --supportsBearing --supportsAltitude")
            self.sh(f"cmd location providers set-test-provider-enabled {p} true")
        for _ in range(3):
            self.sh(self.at(*ORIGIN))
            time.sleep(1)
        print("fake position at the test origin")

    def cleanup(self):
        for p in PROVIDERS:
            self.sh(f"cmd location providers remove-test-provider {p}")
        self.sh("appops set 2000 android:mock_location default")
        left = self.sh("dumpsys location").lower().count("test provider")
        print(f"providers removed, app-op restored (test providers left: {left})")

    def drive(self, kmh, seconds, shots):
        lat, lon = ORIGIN
        m_lat, m_lon = 111320.0, 111320.0 * math.cos(math.radians(lat))
        bearing = math.atan2((DEST[1] - lon) * m_lon, (DEST[0] - lat) * m_lat)
        step = kmh / 3.6
        try:
            for i in range(seconds):
                t0 = time.time()
                lat += math.cos(bearing) * step / m_lat
                lon += math.sin(bearing) * step / m_lon
                self.sh(self.at(lat, lon))
                if shots and i % 8 == 0:
                    with open(f"{shots}/f{i // 8:03d}.png", "wb") as f:
                        f.write(self.png())
                time.sleep(max(0, 1 - (time.time() - t0)))
        finally:
            self.cleanup()


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("command", choices=["prepare", "drive", "cleanup"])
    ap.add_argument("args", nargs="*", help="drive: KMH SECONDS")
    ap.add_argument("-s", "--serial")
    ap.add_argument("--shots", help="drive: a folder for a screenshot every 8 s")
    a = ap.parse_args()
    phone = Phone(a.serial)
    # Always put things back, even on Ctrl-C or a kill.
    signal.signal(signal.SIGTERM, lambda *_: (_ for _ in ()).throw(KeyboardInterrupt()))
    if a.command == "prepare":
        phone.prepare()
    elif a.command == "cleanup":
        phone.cleanup()
    else:
        if len(a.args) != 2:
            sys.exit("drive needs KMH and SECONDS")
        phone.drive(float(a.args[0]), int(a.args[1]), a.shots)


if __name__ == "__main__":
    main()
