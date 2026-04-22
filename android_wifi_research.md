# Wifi/WakeLock Android Background Network Throttling 

## Android Doze & App Standby
When Android apps go into the background, the OS imposes several constraints to save battery:
1. **Network access is suspended**: Unless the app is running a Foreground Service.
2. **CPU is throttled**: Threads may not get scheduled.
3. **WifiManager.WifiLock**: In modern Android (API 29+), `WIFI_MODE_FULL_HIGH_PERF` can keep the radio awake but does NOT bypass the background network restriction itself. Bypassing requires explicit foreground state.

## Bypassing Android Network Throttling during Background
If PiP (Picture-in-Picture) and In-App Browser are discarded, we have three technical approaches to keep a socket alive when an app goes to the background:

1. **Foreground Service (FGS)**
   - Create an Android Foreground Service of type `dataSync` or `connectedDevice`.
   - Requires a persistent notification ("Pairing in progress...").
   - 100% guarantees the OS will not kill the TCP connection.
   - Bypasses Doze mode and App Standby.
   
2. **Request IGNORE_BATTERY_OPTIMIZATIONS**
   - Use `ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` Intent.
   - User gets a system dialog: "Let app always run in background? May use more battery."
   - Keeps sockets alive longer but still subject to deep-sleep Doze if the screen is off (not applicable during pairing, but good to know).
   - Google Play policy is strict about this; requires justification.

3. **Wakeful Intents / WorkManager**
   - Not suitable for real-time TCP socket preservation (better for periodic background tasks).
