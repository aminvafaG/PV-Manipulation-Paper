# PV Manipulation — analysis code and interactive visualizer

MATLAB code accompanying the manuscript *Laminar-specific control of response gain and
orientation-tuning by parvalbumin-expressing inhibitory interneurons in primate visual cortex*
([https://doi.org/10.64898/2025.12.23.696300](https://doi.org/10.64898/2025.12.23.696300)).

The repository contains the full analysis pipeline and the multi-tab visualizer used to build the
figures, plus a **sample of the recordings** so that everything can be run and inspected without
the complete dataset. Clone it, open MATLAB in the repository root, and run `main.m`.

The repository works as a standalone root — no paths need editing.

---

## Quick start

```matlab
cd('C:/path/to/this/repository')
main
```

`main.m` adds the repository to the MATLAB path, loads `data/Units_example.mat`, computes the
per-unit metrics, and opens the visualizer with every analysis page registered.

The first run computes the per-unit model fits (a few seconds) and caches them next to `main.m`
in `metrics_cache.mat`; later runs load the cache and open immediately. Delete that file to force
a recompute — it rebuilds itself.

To open the standalone model app used for part of Fig. 6:

```matlab
Model_APP_01
```

## Requirements

- MATLAB R2023b or a recent compatible desktop release
- Statistics and Machine Learning Toolbox (metrics, mixed-effects statistics)
- Optimization Toolbox (the tuning and I/O-model fits)
- `Model_APP_01` needs base MATLAB only
- No special hardware; any desktop or laptop that can run interactive MATLAB figures

Installation is just cloning or downloading the repository — a few seconds. The app uses
interactive MATLAB windows, so start it from a desktop MATLAB session rather than `-nodisplay`.

---

## What is in the visualizer

`main.m` registers each analysis as a self-contained page. Some pages draw inside their tab;
the larger dashboards open their own maximized figure window from an **Open figure window**
button, and refresh live as you change the controls.

| Tab | What it shows |
| --- | --- |
| Dashboard (V01) | The main dashboard: ΔHBW vs ΔFr, effect-magnitude groups, population tuning, model simulations, per-unit examples |
| Example units | Three example units with the complete per-unit panel set |
| Effect types | Classification of units into linear divisive/multiplicative (D/M) and non-linear (NL) motifs |
| Tuning stability | Spread of the ΔT and RT curves used by the classification |
| Selectivity (V05) | Orientation selectivity, gain parameters, and the I/O-vs-threshold-linear model comparison |
| No-laser by layer | Control-condition OSI / CV / HBW across layer groups |
| Layer selectivity (V02) | OSI / CV / HBW by layer, control vs laser |
| Layer change (V02) | Laser-induced change by layer: differences, ratios and paired comparisons |
| Gain + laminar (V03) | Gain analysis together with the laminar dashboard |
| Composition | Population composition across layers and effect types |
| Effect size | Compact effect-size table by layer × manipulation |
| Unit explorer | Rasters, tuning curves, PSTH and per-unit metrics, unit by unit |
| Scatter | Any metric against any other |
| Laminar / Laminar views | Metrics against recording channel, per penetration |
| Tuning / Raster | Single-unit tuning curves and spike rasters |

### Controls

- **Per-tab controls** sit in the panel on the left of each tab (unit group, manipulation,
  effect-magnitude level, which orientation metric, how repeated recordings of the same neuron are
  treated, and so on).
- **Filters** (toolbar, top left) opens a global filter panel: build rules on any per-unit
  variable, save and reload named filter sets, and see how many units pass.
- **I/O fit** and **LTM fit** (toolbar) choose how the two models are fitted. The defaults —
  unbounded single-seed for the I/O model and a floor-locked 2-parameter threshold-linear model —
  are the settings used in the paper, and give both models the same number of free parameters.
- **Save PDF** exports the current page as vector graphics.
- **Stats report** (on the pages that have it) prints the statistics behind the panels, including
  the mixed-effects versions that account for the same neuron being recorded at several laser
  intensities.

`Model_APP_01` is separate and self-contained: an interactive illustration of how a PV⁺
manipulation can change gain, spiking threshold, the input–output function and the resulting
output tuning (part of Fig. 6).

---

## Sample data

`data/Units_example.mat` holds a **sample** of the dataset analysed in the paper — 501 single
units (621 recorded samples), spanning both directions of PV⁺ manipulation (activation and
inactivation) and all three cortical layer groups. It is provided so the code can be run,
reviewed and tested end to end.

It is not the complete dataset. The full dataset is available from the corresponding author on
reasonable request, and the source data behind each figure are published with the paper.

`data/README.md` documents the structure of the file field by field.

### Running your own recordings

If your data uses the same `Unit` structure, drop the `.mat` into `data/` and name it in `main.m`:

```matlab
dataset    = 'example';
sourceFile = 'MyUnits.mat';
```

For a different structure, copy `+data/defineUnitsMapping.m`, edit the field translations, and
register it in `+data/defineDatasets.m` — that file's header walks through it. Nothing else needs
to change.

---

## Repository layout

| Path | Contents |
| --- | --- |
| `main.m` | Entry point: load → compute metrics → open the visualizer |
| `loadData.m` | Builds the working struct from the configured dataset |
| `Model_APP_01.m` | Standalone interactive model app (part of Fig. 6) |
| `+data/` | Dataset registry, data dictionary and the loader (`DataManager`) |
| `+analysis/` | Metrics, tuning fits, the threshold-linear and I/O models, statistics |
| `+viz/` | The visualizer shell and every analysis page (`+viz/+plots`) |
| `+filter/` | The filter panel and the rule engine behind it |
| `data/` | The sample dataset |
| `expected_outputs/` | Reference screenshots of what the app should look like |

Analysis code is organised so that each piece is usable on its own: `analysis.computeMetrics`
derives every per-unit metric, `analysis.linearThresholdModel` and `analysis.exponentialModel` are
the two models compared in the paper, and `analysis.stats` holds the statistical tests reported in
the figures and tables.

## Expected output

`expected_outputs/` contains reference screenshots produced from the sample data with this code:
the main dashboard, effect types, tuning by layer, selectivity and gain, the unit explorer, the
scatter page and the effect-size table, plus `Model_APP_01.png` for the model app. Your run should
look like these.

## Citation and licence

If you use this code, please cite the manuscript above.

Released under the MIT licence — see `License.txt`.
