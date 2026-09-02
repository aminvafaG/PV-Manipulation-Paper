function D = computeMetricsCached(D, dm, varargin)
%COMPUTEMETRICSCACHED  Cached wrapper around analysis.computeMetrics.
%
%   D = analysis.computeMetricsCached(D, dm)
%   D = analysis.computeMetricsCached(D, dm, 'OSIPref',"peak0", ...)   % opts pass through
%   D = analysis.computeMetricsCached(D, dm, 'ExpMArgs',{'freeFloor',true})  % I/O-fit toggle
%   D = analysis.computeMetricsCached(D, dm, 'LTMArgs',{'floorAtZero',true})  % LTM-fit toggle
%   D = analysis.computeMetricsCached(D, dm, 'Rebuild', true)          % force recompute
%
%   Runs analysis.computeMetrics only when the cache is STALE; otherwise loads
%   the precomputed metric fields from disk and merges them into D, skipping the
%   ~20 s per-unit model fitting on every launch. The cache lives at
%   <projectRoot>/metrics_cache.mat and is invalidated AUTOMATICALLY when any of
%   the following change:
%     * the active data file         (dm.SourceFile -- e.g. data/Units_example.mat:
%                                     size + modified time)
%     * any +analysis or +data .m, or loadData.m   (the code that builds D /
%       the metrics; e.g. editing exponentialModel.m busts the cache)
%     * the computeMetrics options, or the set of variables loaded into D
%
%   Only the fields computeMetrics ADDS (plus the updated D.Meta) are cached, so
%   the file stays small (no rasters). viz.Visualizer uses D only (not dm), so a
%   cache hit needs no DataManager re-registration. Force a rebuild with
%   'Rebuild', true, or just delete metrics_cache.mat.
%
%   The smoke tests call analysis.computeMetrics directly (uncached) so they
%   always exercise the real computation.
%
%   See also: analysis.computeMetrics, loadData, viz.Visualizer

    % --- split off our own 'Rebuild' option; the rest go to computeMetrics ----
    rebuild = false;
    keep = true(1, numel(varargin));
    for k = 1:2:numel(varargin)-1
        if ischar(varargin{k}) || isstring(varargin{k})
            if strcmpi(varargin{k}, 'Rebuild')
                rebuild = logical(varargin{k+1});
                keep(k:k+1) = false;
            end
        end
    end
    cmArgs = varargin(keep);

    root      = fileparts(fileparts(mfilename('fullpath')));   % +analysis -> project root
    cacheFile = fullfile(root, 'metrics_cache.mat');
    sig       = signature(root, cmArgs, D, dm);

    % --- cache hit? ----------------------------------------------------------
    if ~rebuild && isfile(cacheFile)
        try
            S = load(cacheFile, 'sig', 'fields');
            if isfield(S,'sig') && isfield(S,'fields') && isequaln(S.sig, sig)
                fn = fieldnames(S.fields);
                for k = 1:numel(fn), D.(fn{k}) = S.fields.(fn{k}); end
                fprintf('computeMetricsCached: loaded %d cached metric fields (skipped refit).\n', numel(fn));
                return;
            end
        catch err
            warning('computeMetricsCached:load', 'Ignoring unreadable cache: %s', err.message);
        end
    end

    % --- cache miss: compute, then save the added/changed fields -------------
    inNames = fieldnames(D);
    D = analysis.computeMetrics(D, dm, cmArgs{:});
    saveNames = setdiff(fieldnames(D), inNames);            % everything computeMetrics added
    if isfield(D, 'Meta'), saveNames = [saveNames(:); {'Meta'}]; end   % Meta is updated in place
    fields = struct();
    for k = 1:numel(saveNames), fields.(saveNames{k}) = D.(saveNames{k}); end %#ok<AGROW>
    try
        save(cacheFile, 'sig', 'fields', '-v7.3');
        fprintf('computeMetricsCached: computed and cached %d fields -> %s\n', numel(saveNames), cacheFile);
    catch err
        warning('computeMetricsCached:save', 'Could not write cache (%s): %s', cacheFile, err.message);
    end
end

% ----------------------------------------------------------------------- %
function sig = signature(root, cmArgs, D, dm)
%SIGNATURE  Cache key = options + variable set + size/mtime of the data and of
%   every source file that can affect the metrics. Any change invalidates it.
%   The data file is taken from the DataManager (dm.SourceFile) so it tracks
%   whichever dataset is active (e.g. data/Units_example.mat), not a hardcoded
%   name. dm is optional; without it only the code + variable set + N are keyed.
    sig.opts  = cmArgs;
    sig.vars  = sort(fieldnames(D));            % which variables were loaded
    sig.N     = filter.unitCount(D);
    dataStamp = [];
    corrStamp = [];
    if nargin >= 4 && ~isempty(dm) && isprop(dm, 'SourceFile') && ~isempty(dm.SourceFile) ...
            && isfile(dm.SourceFile)
        dataStamp = dir(dm.SourceFile);
    end
    % corrected-fits sidecar: changing/re-saving it (or pointing at a different
    % CorrectionSource) must invalidate the cache. Prefer the exact file loadData
    % actually merged (D.CorrectionFile); fall back to the default sidecar path.
    cf = '';
    if isfield(D, 'CorrectionFile') && ~isempty(D.CorrectionFile)
        cf = char(D.CorrectionFile);
    elseif nargin >= 4 && ~isempty(dm) && isprop(dm,'SourceFile') && ~isempty(dm.SourceFile)
        try, cf = tunefit.correctionPath(dm.SourceFile); catch, cf = ''; end %#ok<CTCH>
    end
    if ~isempty(cf) && isfile(cf), corrStamp = dir(cf); end
    sig.files = fileStamps([ ...
        dataStamp; ...
        corrStamp; ...
        dir(fullfile(root, '+analysis', '*.m')); ...
        dir(fullfile(root, '+data', '*.m')); ...
        dir(fullfile(root, '+tunefit', '*.m')); ...
        dir(fullfile(root, 'loadData.m')) ]);
end

function st = fileStamps(d)
%FILESTAMPS  Reduce a dir() listing to a stable name/size/mtime fingerprint.
    st = struct('name', {}, 'bytes', {}, 'datenum', {});
    for i = 1:numel(d)
        st(i).name    = d(i).name;     %#ok<AGROW>
        st(i).bytes   = d(i).bytes;    %#ok<AGROW>
        st(i).datenum = d(i).datenum;  %#ok<AGROW>
    end
end
