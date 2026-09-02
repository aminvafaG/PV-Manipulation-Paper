% clc;
% clear all;

%% main.m  --  Project entry point:  load  ->  analyse  ->  visualize
%
%  You can run this from ANY folder: the section below puts the project root
%  (this file's folder) on the MATLAB path, so the +data / +analysis / +filter
%  / +viz packages always resolve no matter what the current directory is.
%  Run section-by-section (Ctrl+Enter) while developing.
%
%  Pipeline
%    1) loadData            : pull the initial variables out of the configured dataset
%    2) analysis.computeMetrics : add per-unit metrics (firing rates, tuning
%                                 indexes, ...). These become filterable /
%                                 plottable just like the raw variables.
%    3) viz.Visualizer      : open the multi-tab visualizer and add plot pages.

%% 0) Make the app path-independent
%  Add this file's own folder (the project root) to the MATLAB path so the
%  packages resolve regardless of the current working directory. This is what
%  lets you change MATLAB's folder, or move the project, without the app (and
%  its UI callbacks, which call filter.* / analysis.* / viz.*) breaking.
projectRoot = fileparts(mfilename('fullpath'));
if ~isempty(projectRoot) && exist(projectRoot, 'dir') == 7
    addpath(projectRoot);
end

%% 1) Load the initial working set
%  ===== DATA SOURCE -- everything you change to swap datasets lives here =====
%  dataset     : which registered dataset to load. Keys come from
%                data.defineDatasets -- this repository ships one:
%                   'example' -> data/Units_example.mat, a SAMPLE of the units
%                                analysed in the paper (621 units, 35 recordings,
%                                both manipulation directions, all layer groups)
%                To run your own recordings, drop a .mat with the same 'Unit'
%                structure into data/ and set sourceFile below; for a different
%                structure add a mapping -- see data.defineDatasets' header.
%  sourceFile  : '' uses the dataset's default .mat. Otherwise a file NAME inside
%                the data/ folder, to swap between same-format files without
%                editing any mapping.
%  useCorrectedFits : true loads hand-corrected tuning fits from a sidecar
%                <dataset>_Fit_correction.mat, if one sits next to the data file,
%                as the ACTIVE fit_L / fit_NL (originals kept as fit_L_orig /
%                fit_NL_orig). No sidecar ships with the sample data, so leave
%                this false.
dataset          = 'example';
sourceFile       = '';
useCorrectedFits = false;

[D, dm] = loadData([], 'Dataset', dataset, 'SourceFile', sourceFile, ...
                       'UseCorrected', useCorrectedFits);   % dm kept to convert more later

%% 2) Run initial analysis (adds per-unit metric fields to D)
%  Pass dm so the precomputed F1F0 column can be pulled in alongside the
%  raster/fit-derived metrics (firing rates, OSI, CV, HBW, ...).
%  Cached: the ~20 s per-unit model fitting runs only when the data or the
%  +analysis/+data source changes; otherwise the metrics load from
%  metrics_cache.mat. Use analysis.computeMetrics(D, dm) directly to force a
%  fresh run, or pass 'Rebuild', true.
%  The toolbar's startup fit options (LTM floor=0 (2-param), I/O no-bounds+single-
%  seed) are baked in here via viz.Visualizer.defaultCacheArgs, so the window opens
%  already showing those fits and nothing is refit until you change a dropdown.
fitArgs = viz.Visualizer.defaultCacheArgs();
D = analysis.computeMetricsCached(D, dm, fitArgs{:});

%% 3) Launch the visualizer and register plot pages
app = viz.Visualizer(D);

%  Each page is a self-contained module under +viz/+plots. To add a new page,
%  copy one of these classes and register it here -- nothing else to wire up.
app.addTab( viz.plots.Dashboard01Tab()  );  % Visualizer_01 main dashboard (window f)
app.addTab( viz.plots.ExampleUnitsTab() );  % three example units, full per-unit panel set
app.addTab( viz.plots.Categorization06Tab() ); % Visualizer_01 f06: effect types
app.addTab( viz.plots.Stability07Tab()  );  % Visualizer_01 f07: tuning-stability spread
app.addTab( viz.plots.Selectivity05Tab() ); % Visualizer_01 f05: selectivity + gain
app.addTab( viz.plots.LayerNoLaser07Tab() ); % no-laser OSI/CV/HBW by layer
app.addTab( viz.plots.LayerSelectivity02Tab() ); % Visualizer_02: OSI/CV/HBW by layer
app.addTab( viz.plots.LayerSelectivityChange02Tab() ); % Visualizer_02 change: delta/ratio + paired + change-dist by layer
app.addTab( viz.plots.GainLaminar03Tab() );      % Visualizer_03 f: gain + laminar dashboard
app.addTab( viz.plots.Composition03Tab() );      % Visualizer_03 f2: population composition
app.addTab( viz.plots.EffectSizeTab()   );  % compact effect-size table by layer x manipulation
app.addTab( viz.plots.UnitExplorerTab() );  % rasters + tuning + PSTH + population
app.addTab( viz.plots.ScatterTab()      );  % X/Y scatter of any two metrics
app.addTab( viz.plots.LaminarTab()      );  % parameter vs channel, per-penetration laminar scatter
app.addTab( viz.plots.LaminarViewsTab() );  % channel-vs-penetration & dFR-vs-layer views
app.addTab( viz.plots.TuningTab()       );  % tuning curve; dropdown picks the fit
app.addTab( viz.plots.RasterTab()       );  % single spike raster; slider picks unit

app.show();                     % bring to front + initial draw
