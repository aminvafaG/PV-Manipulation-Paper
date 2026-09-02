function out = compute(D, state, specs, modes)
%COMPUTE  Run a catalog of statistic specs across repeated-obs modes.
%
%   out = analysis.stats.compute(D, state, specs)
%   out = analysis.stats.compute(D, state, specs, modes)
%
%   Runs every spec (from analysis.stats.figureCatalog) under
%   each requested `mode` and assembles a display-ready table. `out` has:
%     .ColumnName  1xC cellstr   (Statistic, Group, Test, <one col per mode>,
%                                 'N (obs/neuron)', 'Effect', 'Source')
%     .Data        RxC cell      (formatted strings; feed straight to a uitable)
%     .modes       the modes used
%
%   modes default = {'all','first','mean','lme'}  (maxpow omitted; LPow is all
%   zero so it is inactive). The repeated-obs dropdown still drives the FIGURE
%   drawing; the report always shows all modes side-by-side for comparison.
%
%   See also: analysis.stats.runTest, analysis.stats.figureCatalog, viz.plots.StatsReport

    if nargin < 4 || isempty(modes), modes = {'all','first','mean','lme'}; end
    nMode = numel(modes);

    nS       = numel(specs);
    hasPaper = nS > 0 && isfield(specs, 'paper');
    tail = {'N (obs/neuron)','Effect'};
    if hasPaper, tail = [tail, {'Paper (published)'}]; end
    tail = [tail, {'Source'}];
    % Benjamini-Hochberg column: the Mixed-effects p's of one report form a
    % family of tests (one figure), so show their BH-adjusted values alongside.
    hasBH = any(strcmp(modes, 'lme')) && nS > 1;
    bh = {}; if hasBH, bh = {'LME p(BH)'}; end
    ColumnName = [{'Statistic','Group','Test'}, i_modeHeads(modes), bh, tail];
    nCol = numel(ColumnName);

    if nS == 0
        Data = repmat({''}, 1, nCol);
        Data{1,1} = '(no statistics catalogued for this figure yet)';
        out = struct('ColumnName', {ColumnName}, 'Data', {Data}, 'modes', {modes});
        return;
    end

    Data = cell(nS, nCol);
    hl   = false(nS, 1);                 % rows where mixed-effects significance differs from All
    lmeP = nan(nS, 1);                   % raw Mixed-effects p per row (for the BH column)
    for i = 1:nS
        sp = specs(i);
        Data{i,1} = sp.label;
        Data{i,2} = i_resolveGroup(sp, state);
        Data{i,3} = sp.test;
        allRes = []; lmeRes = [];
        for m = 1:nMode
            r = analysis.stats.runTest(sp, D, state, modes{m});
            Data{i,3+m} = i_fmtCell(r);
            if strcmp(modes{m},'all'), allRes = r; end
            if strcmp(modes{m},'lme'), lmeRes = r; lmeP(i) = r.p; end
        end
        if isempty(allRes), allRes = analysis.stats.runTest(sp, D, state, modes{1}); end
        Data{i, 3+nMode+double(hasBH)+1} = sprintf('%d / %s', allRes.n, i_num(allRes.neurons));
        Data{i, 3+nMode+double(hasBH)+2} = i_effect(sp, allRes);
        col = 3 + nMode + double(hasBH) + 2;
        if hasPaper
            col = col + 1;
            if isfield(sp,'paper') && ~isempty(sp.paper), Data{i,col} = sp.paper; else, Data{i,col} = ''; end
        end
        Data{i, col+1} = sp.source;
        if ~isempty(allRes) && ~isempty(lmeRes) && allRes.ok && lmeRes.ok
            hl(i) = ~strcmp(viz.plots.V01util.sigStars(allRes.p), viz.plots.V01util.sigStars(lmeRes.p));
        end
    end

    if hasBH
        padj = i_bh(lmeP);
        for i = 1:nS
            if isfinite(padj(i))
                Data{i, 3+nMode+1} = sprintf('%s  p=%s', viz.plots.V01util.sigStars(padj(i)), i_pstr(padj(i)));
            else
                Data{i, 3+nMode+1} = '';
            end
        end
    end

    lmeCol = find(strcmp(ColumnName, 'Mixed-effects'), 1);
    out = struct('ColumnName', {ColumnName}, 'Data', {Data}, 'modes', {modes}, ...
                 'highlightRows', find(hl), 'lmeCol', lmeCol);
end

% ===================================================================== %
function padj = i_bh(p)
%I_BH  Benjamini-Hochberg adjusted p over the finite entries (one report's tests).
    padj = nan(size(p));
    ok = find(isfinite(p)); m = numel(ok);
    if m == 0, return; end
    [ps, si] = sort(p(ok));
    adj = ps(:) .* m ./ (1:m)';
    adj = flipud(cummin(flipud(adj))); adj = min(adj, 1);
    padj(ok(si)) = adj;
end

function h = i_modeHeads(modes)
    lab = containers.Map( ...
        {'all','first','maxpow','mean','lme'}, ...
        {'All','First/neuron','Max power','Mean/neuron','Mixed-effects'});
    h = cell(1, numel(modes));
    for m = 1:numel(modes)
        if isKey(lab, modes{m}), h{m} = lab(modes{m}); else, h{m} = modes{m}; end
    end
end

function s = i_fmtCell(r)
    if ~r.ok || ~isfinite(r.p)
        s = sprintf('n/a (n=%d)', r.n);
    else
        s = sprintf('%s  p=%s  n=%d', viz.plots.V01util.sigStars(r.p), i_pstr(r.p), r.n);
        % a mixed model is fitted to the observations while its descriptives are
        % per neuron -- name both so the cell is not read as one or the other
        if isfield(r,'nObs') && isfinite(r.nObs) && r.nObs ~= r.n
            s = sprintf('%s cells / %d obs', s, r.nObs);
        end
    end
    % EVERY mode column carries its OWN mean +/- s.e.m. (runTest builds the
    % string), so the per-cell descriptives can be read straight off the
    % Mean/neuron or Mixed-effects column instead of only the All-mode Effect.
    if isfield(r,'descr') && ~isempty(r.descr)
        s = sprintf('%s  (%s)', s, r.descr);
    end
end

function s = i_pstr(p)
    if ~isfinite(p),  s = '-';
    elseif p < 1e-4,  s = sprintf('%.1e', p);
    else,             s = sprintf('%.4f', p);
    end
end

function s = i_num(x)
    if ~isfinite(x), s = '-'; else, s = sprintf('%d', round(x)); end
end

function g = i_resolveGroup(sp, state)
    g = '';
    if isfield(sp,'groupFn') && ~isempty(sp.groupFn)
        try, g = sp.groupFn(state); catch, g = sp.group; end %#ok<CTCH>
    elseif isfield(sp,'group')
        g = sp.group;
    end
end

function s = i_effect(sp, r)
    % Same descriptive string the mode columns show (built once in runTest), so
    % Effect == the All-mode column's descriptives, in an identical format.
    d = ''; if isfield(r,'descr'), d = r.descr; end
    switch lower(sp.kind)
        case 'paired'
            s = sprintf('%s (d %.3g)', d, r.stat);
        case {'corr','regression'}
            s = d;
        case 'between'
            s = sprintf('mean %s; median %.3g vs %.3g', d, r.mA, r.mB);
        case 'anova'
            if isfinite(r.stat), s = sprintf('%s; F = %.3g; %s', d, r.stat, r.note);
            else,                s = sprintf('%s; %s', d, r.note); end
        case 'descriptive'
            s = d;
        otherwise
            s = '';
    end
end
