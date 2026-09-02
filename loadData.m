function [D, dm] = loadData(varNames, varargin)
%LOADDATA  Load the project's initial working set from the configured dataset.
%
%   [D, dm] = loadData()           loads the default initial variable set.
%   [D, dm] = loadData(varNames)   loads the cellstr/string list you pass.
%   [D, dm] = loadData(varNames, 'UseCorrected', true)   use the tuning-fitter's
%                                  corrected fits as the ACTIVE fit_L / fit_NL.
%
%   D   project struct: one field per requested variable, arranged across the
%       1332 units (see data.DataManager / data.defineUnitsMapping).
%   dm  the DataManager itself -- keep it if you want to register derived
%       variables, attach computed metrics, or convert more fields later.
%
%   CORRECTED FITS (fit corrector)
%     If a sidecar <dataset>_Fit_correction.mat exists next to the source .mat
%     (written by tunefit.FitCorrectorApp / fitCorrector), loadData adds the corrected
%     curves as SEPARATE fields  D.fit_NL_corr / D.fit_L_corr  (originals kept).
%     Pass 'UseCorrected', true to make those the ACTIVE D.fit_NL / D.fit_L (the
%     originals are preserved as fit_NL_orig / fit_L_orig) so every downstream
%     metric and plot recomputes from the corrected fits. Default is false:
%     originals stay active and the corrected curves are just available to view.
%
%   Options (name/value):
%     'Dataset'          char, default '' -> project default. Which registered
%                        dataset to load (a key from data.defineDatasets, e.g.
%                        'pixel' / 'paper').
%     'SourceFile'       char, default '' -> the dataset's default .mat. A file
%                        NAME inside that dataset's data folder, to swap between
%                        same-format files without editing the mapping.
%     'UseCorrected'     logical, default false (corrected fits active?)
%     'CorrectionSource' char, default dm.SourceFile (which dataset's sidecar)
%
%   Run from the project root (the folder that holds +data, +analysis, ...).
%
%   See also: data.DataManager, data.mergeCorrectedFits, tunefit.FitCorrectorApp

    p = inputParser; p.FunctionName = 'loadData';
    p.addParameter('Dataset', '');          % registered dataset key (data.defineDatasets); '' = project default
    p.addParameter('SourceFile', '');       % file NAME override inside that dataset's folder; '' = its default
    p.addParameter('UseCorrected', false);
    p.addParameter('CorrectionSource', '');
    p.parse(varargin{:});
    useCorrected = logical(p.Results.UseCorrected);

    % Which dataset + which .mat -> a DataManager. All dataset-specific choices
    % (mapping, data folder, file name) are resolved from the registry here, so
    % main.m only sets a dataset key (+ optional file). See data.defineDatasets.
    dm = data.makeDataManager(p.Results.Dataset, p.Results.SourceFile);

    corrSource = char(p.Results.CorrectionSource);
    if isempty(corrSource), corrSource = dm.SourceFile; end

    if nargin < 1 || isempty(varNames)
        % ---- Initial working set (edit this list as the project grows) ----
        varNames = { ...
            'RasL', ...        % spike raster, laser trials      (Nx1 cell)
            'RasNL', ...       % spike raster, no-laser trials   (Nx1 cell)
            'Ori_N', ...       % number of orientations / similar
            'fit_L', ...       % fitted tuning curve, laser      (360 x N)
            'fit_NL', ...      % fitted tuning curve, no-laser   (360 x N)
            'U_unity', ...     % unit unity number (neuron identity across laser levels)
            'Rast_time', ...   % raster start/duration/end time
            'LG', ...          % recording layer group SG_G_IG_Deep
            'EI', ...          % excitation/inhibition experiment (string)
            'Dataset', ...     % DS index (animal: DS1..DS4 in Name DSx_Py_...)
            'Penetration', ... % P index (penetration within the animal)
            'ch' };            % recording channel/electrode (Laminar viewer: x vs channel)
        % Pixel-only identity fields the Laminar viewer groups panels by; added
        % only when the active mapping provides them (old Units.mat lacks them).
        optional = {'Animal','Tasknumb'};
        varNames = [varNames, optional(cellfun(@(v) dm.has(v), optional))];
    end

    D  = dm.convert(varNames);         % build the project struct

    % Per-unit QUALITY flag (good/bad), default all GOOD. Always present so the
    % filter/visualizer can use it (filter.filterableVars auto-picks up the Nx1
    % logical); the tuning fitter's sidecar (data.mergeCorrectedFits) flips units
    % to BAD. Attached via dm so it is documented in D.Meta like other fields.
    nU = filter.unitCount(D);
    D  = dm.attach(D, 'UnitGood', true(nU,1), ...
        ['Per-unit quality flag (true = good). Default all good; the tuning fitter ' ...
         'marks units bad and stores them in <dataset>_Fit_correction.mat. Filterable.']);

    % --- merge tuning-fitter corrected fits (adds fit_*_corr if a sidecar -----
    %     exists; makes them active only when 'UseCorrected' is true) ----------
    try
        [D, mi] = data.mergeCorrectedFits(D, corrSource);
        if mi.merged
            D.CorrectionFile = mi.file;   % lets computeMetricsCached stamp the exact sidecar used
            fprintf('loadData: merged corrected fits (%d NL, %d L, %d skipped) from %s\n', ...
                mi.nNL, mi.nL, mi.nSkipped, mi.file);
            if mi.nNL == 0 && mi.nL == 0 && mi.nSkipped > 0
                warning('loadData:allSkipped', ...
                    'Correction sidecar found but every row was skipped (identity mismatch). Using original fits.');
            end
            if useCorrected
                D.fit_NL_orig = D.fit_NL;  D.fit_L_orig = D.fit_L;
                D.fit_NL = D.fit_NL_corr;  D.fit_L = D.fit_L_corr;
                fprintf(['loadData: UseCorrected = true -> corrected fits are ACTIVE ' ...
                         '(originals kept as fit_NL_orig / fit_L_orig).\n']);
            end
        elseif useCorrected
            warning('loadData:noCorrection', ...
                'UseCorrected requested but no correction sidecar at %s', mi.file);
        end
    catch err
        warning('loadData:merge', 'Could not merge corrected fits: %s', err.message);
    end

    % NOTE: D.Meta is a table documenting every field above. The visualizer and
    % filter layers skip it automatically (it is not a per-unit variable).
end
