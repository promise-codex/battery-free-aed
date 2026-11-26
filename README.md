# Battery-Free Automated External Defibrillators for Low-Resource Settings

A physics-constrained comparison of power and energy-storage designs for automated external defibrillators (AEDs) in Nigeria. All results come from simulation and open data. Nothing here is a medical device or clinical evidence.

## Scope

1. **Shock decision.** A shockable or non-shockable rhythm classifier sized for a low-cost microcontroller, tested on the open PhysioNet VFDB and CUDB databases against the AHA performance goals.
2. **Power and energy storage.** A side-by-side comparison of hand crank, solar, lithium-ion battery and mains sources, with battery, supercapacitor or hybrid storage. A flyback converter charges a high-voltage capacitor and an H-bridge delivers a biphasic shock into 25 to 175 ohm (the IEC 60601-2-4 test loads).

## Contents

| Folder | Step | What it does |
|---|---|---|
| `shock/` | 1 | Closed-form biphasic truncated exponential shock at the seven IEC test loads |
| `charger/` | 2 | Averaged flyback charging of the shock capacitor from a hand crank, a supercapacitor string and an LFP battery |
| `storage/` | 3 | Supercapacitor and LFP battery ageing and self-discharge in Nigerian heat (NASA POWER hourly weather, cabinet and parked-vehicle cases), plus crank start-up time |
| `solar/` | 4 | Smallest solar panel that keeps the supercapacitor or LFP battery ready every hour, and refill time after a rescue |
| `logger/` | Field | Arduino heat logger that measures temperature inside a parked car and a closed cabinet (not yet built) |

## How to run (MATLAB Online R2026b)

```matlab
gitclone("https://github.com/promise-codex/battery-free-aed")
cd battery-free-aed/shock
step1_bte_closed_form
cd ../charger
step2_charger_average
cd ../storage
step3_storage_heat
cd ../solar
step4_solar_sizing
```

Step 3 downloads hourly weather from NASA POWER (no account needed) into `storage/data` on its first run.

To get updates later: `cd` into the repository folder and run `!git pull`.

## Units

SI units throughout: F, V, ohm, s, J, A.
