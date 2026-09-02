# Sample dataset

`Units_example.mat` is the **sample** of the dataset the analysis code and visualizer run on; it is
loaded automatically by `main.m`.

It is not the complete dataset: the full recordings are available from the corresponding author on
reasonable request, and the source data behind each published figure are provided with the paper.

## Contents

| File | Contents |
| --- | --- |
| `Units_example.mat` | MATLAB structure array named `Unit`, size `1 x 621` — one element per recorded sample (a single unit at one laser intensity) |

Each element is one recorded sample of a spike-sorted single unit from marmoset V1 during
drifting-grating stimulation, under a no-laser control condition and a laser (optogenetic)
condition. The sample contains **501 single units (621 recorded samples)** and spans both
directions of PV⁺ manipulation and all three cortical layer groups, so every page of the
visualizer has data to show.

A unit recorded at several laser intensities appears as several elements that share a `UU`
(unit-unity) number; the analysis code uses that to avoid counting one neuron more than once.

Recording session filenames, dates and times are deliberately **not** included: the analysis never
reads them. A recording is identified numerically by `DS` (animal) and `P` (penetration), which is
what the penetration grouping and the mixed-effects models use.

## Conventions

- `L = laser`, `NL = no laser` (control).
- Two-element metric vectors are ordered `[laser, control]`.
- Raster matrices cover 500 ms before stimulus onset, 1000 ms of stimulus, and 1000 ms after
  offset — 2500 columns of 1 ms bins. Rows concatenate trials across stimulus directions, so the
  row count varies between units.
- `fit` stores the fitted orientation-tuning curves as `360 x 2`, with `fit(:,1) = laser` and
  `fit(:,2) = control`.

## Fields

### Identity and recording

| Field | Description |
| --- | --- |
| `id` | Unit index within its recording |
| `UU` | Unit-unity number — the same neuron recorded at different laser intensities shares this |
| `ch` | Recording channel / electrode number |
| `DS` | Animal (dataset) index |
| `P` | Penetration index within the animal |
| `EI` | Manipulation direction: `E` = PV⁺ activation, `I` = PV⁺ inactivation |
| `LG` | Layer group of the recording site: `SG`, `G` or `IG` |
| `LPow` | Laser power level (a.u.) |
| `Ori_N` | Number of stimulus directions tested |
| `Raster_Start_Duration_End_time` | Raster window as `[start duration end]` in seconds |

### Responses

| Field | Description |
| --- | --- |
| `RasNL`, `RasL` | Spike rasters, control and laser (trials × 2500 ms bins) |
| `fit` | Fitted orientation-tuning curves, `360 x [laser control]` |
| `Fr` | Mean firing rate during the stimulus, `[laser control]` (Hz) |
| `Fr_L123`, `Fr_NL123` | Firing rate across the three laser / control epochs |
| `Si` | Orientation selectivity index, `[laser control]` |
| `Cv` | Circular variance, `[laser control]` |
| `HBW` | Half-bandwidth, `[laser control]` (deg) |
| `F1F0` | F1/F0 modulation ratio, `[laser control]` |
| `Rsq` | Tuning-fit R², `[laser control]` |
| `OPL`, `OPNL`, `ONPL`, `ONPNL` | Spike counts at the preferred / non-preferred orientation, laser and control |
| `FrPL`, `FrPNL`, `FrNPL`, `FrNPNL` | Firing rates at the preferred / non-preferred orientation, laser and control |
| `Ra`, `Rb`, `Rbn` | Response summary metrics |

The visualizer works from these fields directly — it does not need any field to be added after
loading. `+data/defineUnitsMapping.m` is the data dictionary that translates them into the project
names used throughout the code (for example `UU → U_unity`, `DS → Dataset`, `P → Penetration`),
and every derived quantity (firing-rate change, ΔOSI, ΔCV, ΔHBW, the model fits) is recomputed
from the rasters and tuning curves by `+analysis/`.

## Using your own data

Keep the same `Unit` structure and field names and the code will load your file as it stands —
drop it into this folder and name it in `main.m` (`sourceFile = 'MyUnits.mat';`). For a different
structure, copy `+data/defineUnitsMapping.m`, edit the field translations, and register it in
`+data/defineDatasets.m`.
