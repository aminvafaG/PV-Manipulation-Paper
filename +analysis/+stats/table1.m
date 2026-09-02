function T = table1(D, varargin)
%TABLE1  The manuscript's Table 1, computed from the app's OWN pipeline.
%
%   T = analysis.stats.table1(D)
%   T = analysis.stats.table1(D, 'Write','table1_app.csv')
%
%   Companion to analysis.stats.fig2Table: same selection, same dominant-layer
%   assignment, same per-cell reduction, so Table 1, Table 2, the Results text
%   and the Layer-Selectivity tab's stats report are all one source.
%
%   One row per manipulation x layer (SG/G/IG/All) with, PER CELL (each unit
%   contributing one value, averaged over the laser intensities at which it was
%   recorded):
%       dFrMean/dFrSem            laser-induced change in firing rate (%)
%       osiC/osiL/dOsi (+ Sem)    control / laser / change in OSI
%       cvC/cvL/dCv    (+ Sem)    ... CV
%       hbwC/hbwL/dHbw (+ Sem)    ... HBW (degrees; not-aligned units dropped)
%       nUnit/nAnimal/nPen        distinct cells / animals / penetrations
%   The All row pools the three layers; because each cell is assigned to ONE
%   dominant layer, a cell is counted exactly once there.
%
%   See also: analysis.stats.fig2Table, analysis.stats.figureCatalog

    p = inputParser;
    p.addParameter('Group', 'ORI_NON_PV');
    p.addParameter('Mask', []);
    p.addParameter('Write', '');
    p.parse(varargin{:});
    o = p.Results;

    mask = o.Mask;
    if isempty(mask), mask = ~viz.plots.V01util.noiseMask(D); end
    mask = logical(mask(:));

    colv = @viz.plots.V01util.colv;
    isI  = viz.plots.V01util.isInhib(D); isI = isI(:);
    UU   = colv(D, 'U_unity');
    PK   = viz.plots.V01util.penKey(D);
    DS   = colv(D, 'Dataset');
    LGn  = viz.plots.V01util.layerNum(D); LGn = LGn(:);
    grp  = analysis.tuningGroupMask(D, o.Group); grp = grp(:);

    dFr  = 100 * colv(D, 'Delta_Fr');
    bad  = colv(D, 'Align_bad') == 1;
    M = struct( ...
      'OSI', {{colv(D,'fitOSI_NL'), colv(D,'fitOSI_L')}}, ...
      'CV',  {{colv(D,'fitCV_NL'),  colv(D,'fitCV_L')}}, ...
      'HBW', {{colv(D,'fitHBW_NL'), colv(D,'fitHBW_L')}});
    M.HBW{1}(bad) = NaN; M.HBW{2}(bad) = NaN;      % drop not-aligned units, as the tabs do

    manips = {false,'PVA'; true,'PVI'};
    labs   = {'SG','G','IG'};
    rows = {};
    for mm = 1:2
        sel = mask & grp & (isI == manips{mm,1});
        rb  = viz.plots.V01util.layerReps(D, find(sel), LGn, 'first', 1:3);   % dominant layer per cell
        allRows = [];
        for li = 1:4
            if li <= 3
                cells = UU(rb{li}); lab = labs{li};
            else
                cells = UU(allRows);  lab = 'All';
            end
            cells = unique(cells);
            if li <= 3, allRows = [allRows; rb{li}(:)]; end %#ok<AGROW>
            % all selected rows of those cells, restricted to their dominant layer
            if li <= 3, keepRows = find(sel & LGn == li & ismember(UU, cells));
            else,       keepRows = find(sel & ismember(UU, cells) & isfinite(LGn) & LGn <= 3); end
            r = i_percell(keepRows, UU, dFr, M);
            r.manip = manips{mm,2}; r.layer = lab;
            r.nUnit = numel(cells);
            r.nAnimal = numel(unique(DS(keepRows(isfinite(DS(keepRows))))));
            r.nPen    = numel(unique(PK(keepRows(isfinite(PK(keepRows))))));
            rows{end+1} = r; %#ok<AGROW>
        end
    end
    T = struct2table([rows{:}]);
    T = movevars(T, {'manip','layer'}, 'Before', 1);

    if ~isempty(o.Write)
        try, writetable(T, o.Write); fprintf('table1: wrote %s\n', o.Write);
        catch e, warning('table1:write','%s', e.message); end
    end
end

% ===================================================================== %
function r = i_percell(rows, UU, dFr, M)
%I_PERCELL  Per-cell means of every Table 1 quantity over `rows`.
    r = struct();
    ids = UU(rows);
    r.dFrMean = NaN; r.dFrSem = NaN;
    v = i_agg(dFr(rows), ids);
    if ~isempty(v), r.dFrMean = mean(v); r.dFrSem = std(v)/sqrt(numel(v)); end
    for f = {'OSI','CV','HBW'}
        c = i_agg(M.(f{1}){1}(rows), ids);      % control
        l = i_agg(M.(f{1}){2}(rows), ids);      % laser
        d = i_aggPair(M.(f{1}){1}(rows), M.(f{1}){2}(rows), ids);
        r.([lower(f{1}) 'C'])    = i_m(c);  r.([lower(f{1}) 'Csem']) = i_s(c);
        r.([lower(f{1}) 'L'])    = i_m(l);  r.([lower(f{1}) 'Lsem']) = i_s(l);
        r.(['d' f{1}])           = i_m(d);  r.(['d' f{1} 'sem'])     = i_s(d);
    end
end
function v = i_agg(x, ids)
    x = x(:); ok = isfinite(x);
    if ~any(ok), v = []; return; end
    v = viz.plots.V01util.aggMean(x(ok), ids(ok)); v = v(isfinite(v));
end
function v = i_aggPair(a, b, ids)
    a = a(:); b = b(:); ok = isfinite(a) & isfinite(b);
    if ~any(ok), v = []; return; end
    v = viz.plots.V01util.aggMean(b(ok) - a(ok), ids(ok)); v = v(isfinite(v));
end
function m = i_m(v), if isempty(v), m = NaN; else, m = mean(v); end, end
function s = i_s(v), if isempty(v), s = NaN; else, s = std(v)/sqrt(numel(v)); end, end
