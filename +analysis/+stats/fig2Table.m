function T = fig2Table(D, varargin)
%FIG2TABLE  The Fig. 2 statistics table, computed from the app's OWN pipeline.
%
%   T = analysis.stats.fig2Table(D)
%   T = analysis.stats.fig2Table(D, 'Group','ORI_NON_PV', 'Write','fig2_stats.csv')
%
%   THE single source for every Fig. 2 / Table 1 / Table 2 number in the
%   manuscript. It calls analysis.stats.figureCatalog('V02') + runTest, i.e. the
%   exact selection, layer assignment, per-cell reduction and mixed model the
%   Layer-Selectivity tab's stats report shows on screen -- so a number in the
%   paper, a number in the report and a number in this table cannot disagree.
%   (It replaces an ad-hoc script that produced fig2_lme_results.csv in an
%   earlier session and was not kept; that file is superseded by this function.)
%
%   One row per metric x layer x manipulation (3 x 3 x 2 = 18) with
%       nCell/nObs        distinct neurons / unit-x-intensity observations
%       ctrlMean/ctrlSem  per-cell control descriptives  (Table 1)
%       lasMean/lasSem    per-cell laser descriptives    (Table 1)
%       dMean/dSem        per-cell change, laser - control (the paper's Delta)
%       est/estSE/ciLo/ciHi/tStat/df/p    the mixed model's fixed effect of
%                         condition, signed laser-minus-control  (Table 2)
%       pBH               Benjamini-Hochberg across the 18 tests
%       pSignrank         distribution-free check on the per-cell changes
%       model             the formula actually fitted
%   The model is  metric ~ condition + (1|penetration) + (1|penetration:unit)
%   with Satterthwaite degrees of freedom (see viz.plots.V01util.smPaired /
%   analysis.stats.runTest).
%
%   Name/value:
%     'Group'  ('ORI_NON_PV')  unit group, as in the tabs' TuningG dropdown
%     'Mask'   ([])            extra unit mask; default = every unit the app
%                              keeps, i.e. ~viz.plots.V01util.noiseMask(D)
%     'Write'  ('')            path of a CSV to write
%
%   See also: analysis.stats.figureCatalog, analysis.stats.runTest,
%             viz.plots.LayerSelectivity02Tab

    p = inputParser;
    p.addParameter('Group', 'ORI_NON_PV');
    p.addParameter('Mask', []);
    p.addParameter('Write', '');
    p.parse(varargin{:});
    o = p.Results;

    N = viz.plots.V01util.nU(D);
    mask = o.Mask;
    if isempty(mask)
        % same population the app shows: everything except the published
        % analysis's discarded noise units
        mask = ~viz.plots.V01util.noiseMask(D);
    end
    mask = logical(mask(:));

    mets   = {'OSI','CV','HBW'};
    layers = {'SG','G','IG'};
    manips = {'E','PVA'; 'I','PVI'};

    rows = {};
    for mm = 1:size(manips,1)
        state = struct('group', o.Group, 'mask', mask, 'ei', manips{mm,1}, 'index','HBW');
        specs = analysis.stats.figureCatalog('V02', state);   % 9 specs, metric-major
        for mi = 1:3
            for li = 1:3
                sp = specs((mi-1)*3 + li);
                rL = analysis.stats.runTest(sp, D, state, 'lme');    % model on all obs
                rM = analysis.stats.runTest(sp, D, state, 'mean');   % per-cell descriptives
                dm = i_deltaPerCell(sp, D, state);                   % per-cell laser-control
                rows{end+1} = { manips{mm,2}, mets{mi}, layers{li}, ...
                    rM.n, rL.n, ...
                    rM.mB, rM.seB, rM.mA, rM.seA, ...
                    dm.mean, dm.sem, dm.p, ...
                    rL.est, rL.estSE, rL.ciLo, rL.ciHi, rL.tStat, rL.df, rL.p, ...
                    NaN, string(rL.model) };  %#ok<AGROW>
            end
        end
    end

    V = vertcat(rows{:});
    T = cell2table(V, 'VariableNames', {'manip','metric','layer','nCell','nObs', ...
        'ctrlMean','ctrlSem','lasMean','lasSem','dMean','dSem','pSignrank', ...
        'est','estSE','ciLo','ciHi','tStat','df','p','pBH','model'});
    T.pBH = i_bh(T.p);                        % family = the 18 Fig. 2 tests

    if ~isempty(o.Write)
        try, writetable(T, o.Write); fprintf('fig2Table: wrote %s\n', o.Write);
        catch e, warning('fig2Table:write', 'could not write %s: %s', o.Write, e.message);
        end
    end
end

% ===================================================================== %
function d = i_deltaPerCell(sp, D, state)
%I_DELTAPERCELL  Per-cell change (laser - control) and its signed-rank p, from
%   the SAME build the model used, so descriptives and inference agree.
    d = struct('mean',NaN, 'sem',NaN, 'p',NaN);
    try
        data = sp.build(D, state, 'mean');           % already one value per cell
        a = data.a(:); b = data.b(:);
        ok = isfinite(a) & isfinite(b); a = a(ok); b = b(ok);
        if isempty(a), return; end
        v = a - b;
        d.mean = mean(v); d.sem = std(v)/sqrt(numel(v));
        try, d.p = signrank(a, b); catch, end %#ok<CTCH>
    catch
    end
end

% ===================================================================== %
function padj = i_bh(p)
%I_BH  Benjamini-Hochberg adjusted p over the finite entries.
    p = p(:); padj = nan(size(p));
    ok = find(isfinite(p)); m = numel(ok);
    if m == 0, return; end
    [ps, si] = sort(p(ok));
    adj = ps .* m ./ (1:m)';
    adj = flipud(cummin(flipud(adj))); adj = min(adj, 1);
    padj(ok(si)) = adj;
end
