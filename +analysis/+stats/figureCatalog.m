function specs = figureCatalog(figKey, state) %#ok<INUSD>
%FIGURECATALOG  Statistic specs for one figure tab's report.
%
%   specs = analysis.stats.figureCatalog(figKey, state)
%
%   Returns a struct array of test specs (see analysis.stats.runTest for the
%   schema) that reproduce, from the loaded data D, the statistics the old
%   project computed for that figure -- including the console-only / unannotated
%   ones. Each spec's .build closure owns the figure-specific selection and
%   per-mode reduction so the report numbers match the figure.
%
%   figKey: 'V01' (Dashboard01), 'f06' (Categorization06), 'f07' (Stability07),
%           'f05' (Selectivity05), 'F27' (LayerNoLaser07), 'V02'
%           (LayerSelectivity02), 'V03f' (GainLaminar03). 'V03f2'
%           (Composition03) is descriptive-only and builds its report directly.
%
%   See also: analysis.stats.compute, analysis.stats.runTest

    switch upper(char(figKey))
        case {'V02','LAYERSELECTIVITY02'}, specs = i_v02();
        case {'V01','DASHBOARD01'},        specs = i_v01();
        case {'F06','CATEGORIZATION06'},   specs = i_f06();
        case {'F07','STABILITY07'},        specs = i_f07();
        case {'F05','SELECTIVITY05'},      specs = i_f05();
        case {'F27','LAYERNOLASER07'},     specs = i_f27();
        case {'V03F','GAINLAMINAR03'},     specs = i_v03f();
        otherwise
            specs = i_spec(); specs(1) = [];           % 1x0 struct with the schema fields
            warning('analysis:stats:figureCatalog', ...
                'No stats catalog for "%s" (see STATS_REPORTING_PLAN.md sec 6).', char(figKey));
    end
end

% ===================================================================== %
%  Shared selection + per-mode reduction helpers
%    paired (signrank/lme), between (ranksum; lme==mean-per-neuron),
%    corr (corrcoef+fitlm / fitlme), anova (anova1+tukey; lme==mean).
% ===================================================================== %
function [eIdx, iIdx, sel] = i_selEI(D, state)
    % state.partition ('any' | 'majority', from the f05 Class-grouping dropdown)
    % flows into the _MD/_NL/_U group masks; absent (every other tab) -> 'any',
    % which is tuningGroupMask's historical per-observation behavior.
    grpMask = analysis.tuningGroupMask(D, state.group, ...
        'ClassGrouping', i_getf(state, 'partition', 'any'));
    grpMask = grpMask(:);
    isI = viz.plots.V01util.isInhib(D); isI = isI(:);
    sel  = state.mask(:) & grpMask;
    eIdx = find(sel & ~isI); iIdx = find(sel & isI);
end
function e = i_eIdx(D, state), [e, ~] = i_selEI(D, state); end
function i = i_iIdx(D, state), [~, i] = i_selEI(D, state); end
function p = i_eiPool(D, state), [e, i] = i_selEI(D, state); p = [e(:); i(:)]; end

function v = i_field(D, fname, idx)
    a = viz.plots.V01util.colv(D, fname); v = a(idx); v = v(:);
end
function v = i_fieldBad(D, fname, idx)              % HBW: drop not-aligned units
    a = viz.plots.V01util.colv(D, fname);
    bad = viz.plots.V01util.colv(D, 'Align_bad') == 1; a(bad) = NaN;
    v = a(idx); v = v(:);
end

function out = i_pairedReduce(D, obs, vL, vNL, md)
    uu = viz.plots.V01util.colv(D, 'U_unity'); obs = obs(:);
    pk = viz.plots.V01util.penKey(D);
    switch md
        case {'all','lme'}
            out = struct('a', vL(D,obs), 'b', vNL(D,obs), 'neur', uu(obs), 'pen', pk(obs));
        case {'first','maxpow'}
            R = viz.plots.V01util.reducer(D, obs, md); reps = viz.plots.V01util.redIdx(R);
            out = struct('a', vL(D,reps), 'b', vNL(D,reps), 'neur', uu(reps), 'pen', pk(reps));
        otherwise   % mean: per-neuron average
            R = viz.plots.V01util.reducer(D, obs, 'mean');
            a = viz.plots.V01util.redVec(R, vL(D,obs));
            b = viz.plots.V01util.redVec(R, vNL(D,obs));
            out = struct('a', a(:), 'b', b(:), 'neur', uu(viz.plots.V01util.redIdx(R)), ...
                         'pen', pk(viz.plots.V01util.redIdx(R)));
    end
    out.a = out.a(:); out.b = out.b(:); out.neur = out.neur(:); out.pen = out.pen(:);
end

function g = i_reduceVals(D, idx, vfun, md)
    idx = idx(:);
    switch md
        case 'all', g = vfun(D, idx);
        case {'first','maxpow'}
            R = viz.plots.V01util.reducer(D, idx, md); g = vfun(D, viz.plots.V01util.redIdx(R));
        otherwise   % 'mean' or 'lme' -> per-neuron mean (between/anova lme == aggregate)
            R = viz.plots.V01util.reducer(D, idx, 'mean'); g = viz.plots.V01util.redVec(R, vfun(D, idx));
    end
    g = g(:);
end

function out = i_betweenReduce(D, idxA, idxB, vfun, md)
    uu = viz.plots.V01util.colv(D, 'U_unity');
    out = struct('ga', i_reduceVals(D, idxA, vfun, md), ...
                 'gb', i_reduceVals(D, idxB, vfun, md), ...
                 'neur', uu([idxA(:); idxB(:)]));
end

function out = i_corrReduce(D, obs, xfun, yfun, md, xfilt)
    uu = viz.plots.V01util.colv(D, 'U_unity'); obs = obs(:);
    pk = viz.plots.V01util.penKey(D);
    switch md
        case {'all','lme'}
            x = xfun(D,obs); y = yfun(D,obs); nu = uu(obs); pe = pk(obs);
        case {'first','maxpow'}
            R = viz.plots.V01util.reducer(D, obs, md); reps = viz.plots.V01util.redIdx(R);
            x = xfun(D,reps); y = yfun(D,reps); nu = uu(reps); pe = pk(reps);
        otherwise
            R = viz.plots.V01util.reducer(D, obs, 'mean');
            x = viz.plots.V01util.redVec(R, xfun(D,obs));
            y = viz.plots.V01util.redVec(R, yfun(D,obs));
            nu = uu(viz.plots.V01util.redIdx(R)); pe = pk(viz.plots.V01util.redIdx(R));
    end
    x = x(:); y = y(:); nu = nu(:); pe = pe(:);
    if nargin >= 6 && ~isempty(xfilt)
        keep = xfilt(x); x = x(keep); y = y(keep); nu = nu(keep); pe = pe(keep);
    end
    out = struct('x', x, 'y', y, 'neur', nu, 'pen', pe);
end

function out = i_anovaReduce(D, state, vfun, md, layers)
    [~,~,sel] = i_selEI(D, state);                 % pool E+I (old Allselected)
    LGn = viz.plots.V01util.layerNum(D); LGn = LGn(:);
    uu = viz.plots.V01util.colv(D, 'U_unity');
    labStr = {'SG','G','IG','Deep'};
    groups = cell(1,numel(layers)); labels = cell(1,numel(layers)); allreps = [];
    if any(strcmp(md, {'mean','lme'}))
        % per-neuron groups: dominant-layer assignment, value = MEAN of the
        % neuron's rows IN that layer (layerReps' per-neuron representative is
        % the FIRST row, so vfun at it would return firsts, not means)
        rbF = viz.plots.V01util.layerReps(D, find(sel), LGn, 'first', layers);
        selIdx = find(sel);
        for k = 1:numel(layers)
            nsel = uu(rbF{k});
            rows = selIdx(LGn(selIdx) == layers(k) & ismember(uu(selIdx), nsel));
            vv = vfun(D, rows); vv = vv(:);
            [~, ~, g] = unique(uu(rows), 'stable');
            if isempty(rows), groups{k} = zeros(0,1);
            else, groups{k} = accumarray(g, vv, [], @(z) mean(z,'omitnan')); end
            labels{k} = labStr{layers(k)};
            allreps = [allreps; rbF{k}(:)]; %#ok<AGROW>
        end
    else
        rb = viz.plots.V01util.layerReps(D, find(sel), LGn, md, layers);
        for k = 1:numel(layers)
            reps = rb{k}; groups{k} = vfun(D, reps); labels{k} = labStr{layers(k)};
            allreps = [allreps; reps(:)]; %#ok<AGROW>
        end
    end
    out = struct('groups', {groups}, 'labels', {labels}, 'neur', uu(allreps));
    % observation-level values + layer/unit/penetration ids: runTest's 'lme'
    % mode fits v ~ layer + (1|pen) + (1|pen:unit) to these (Satterthwaite).
    pk = viz.plots.V01util.penKey(D);
    rbA = viz.plots.V01util.layerReps(D, find(sel), LGn, 'all', layers);
    oV = []; oL = {}; oI = []; oP = [];
    for k = 1:numel(layers)
        rr = rbA{k}; rr = rr(:); vv = vfun(D, rr); vv = vv(:);
        oV = [oV; vv]; oL = [oL; repmat(labStr(layers(k)), numel(vv), 1)]; %#ok<AGROW>
        oI = [oI; uu(rr)]; oP = [oP; pk(rr)]; %#ok<AGROW>
    end
    out.obsVals = oV; out.obsLayer = oL; out.obsId = oI; out.obsPen = oP;
end

% per-unit tuning-curve spread metric (f06/f07), with the old good_v / dist gates
function v = i_spread(D, idx, fieldMat, kind, good_th, dist_th)
    M = D.(fieldMat); v = nan(numel(idx),1);
    for k = 1:numel(idx)
        col = M(:, idx(k)); col = col(isfinite(col));
        if isempty(col), continue; end
        mu = mean(col); if abs(mu) >= good_th, continue; end     % good_v column gate
        switch kind
            case 'std',    val = std(col);
            case 'sdmean', val = std(col)/abs(mu);
            case 'diff',   val = sum(abs(diff(col)));
            case 'pp',     val = max(abs(col)) - min(abs(col));
            otherwise,     val = NaN;
        end
        if ~isempty(dist_th) && val >= dist_th, continue; end
        v(k) = val;
    end
end

% ===================================================================== %
%  V02 -- Visualizer_02 f2: OSI/CV/HBW Control vs Laser per layer (9 paired).
% ===================================================================== %
function specs = i_v02()
    mets = {'OSI','CV','HBW'};
    fmap = struct('OSI', {{'fitOSI_L','fitOSI_NL'}}, ...
                  'CV',  {{'fitCV_L','fitCV_NL'}}, ...
                  'HBW', {{'fitHBW_L','fitHBW_NL'}});
    labs = {'SG','G','IG'};
    src  = {'Visualizer_02.m:936', 'Visualizer_02.m:1110', 'Visualizer_02.m:1268'};
    S = {};
    for mi = 1:3
        flds = fmap.(mets{mi});
        for li = 1:3
            sp = i_spec();
            sp.figure='V02'; sp.panel=sprintf('b1{%d} / D%d{%d}', mi, mi, li);
            sp.label=sprintf('%s  Control vs Laser - %s layer', mets{mi}, labs{li});
            sp.kind='paired'; sp.test='signrank / LME'; sp.groupFn=@(s) i_ei2pv(s.ei);
            sp.source=src{mi};
            sp.notes='fitted metric; HBW drops Align_bad; dominant-layer dedup for first/mean';
            sp.build=@(D,state,md) i_v02Paired(D, state, md, flds, li, mets{mi});
            S{end+1}=sp; %#ok<AGROW>
        end
    end
    specs = [S{:}];
end

function out = i_v02Paired(D, state, md, flds, layer, met)
    colv = @viz.plots.V01util.colv;
    isI  = viz.plots.V01util.isInhib(D); isI = isI(:);
    want = strcmp(state.ei, 'I');
    grpMask = analysis.tuningGroupMask(D, state.group); grpMask = grpMask(:);
    sel  = state.mask(:) & grpMask & (isI == want);
    LGn  = viz.plots.V01util.layerNum(D); LGn = LGn(:);
    lv   = colv(D, flds{1}); nlv = colv(D, flds{2});
    if strcmpi(met, 'HBW')
        bad = colv(D, 'Align_bad') == 1; lv(bad) = NaN; nlv(bad) = NaN;
    end
    uu = colv(D, 'U_unity');
    pk = viz.plots.V01util.penKey(D);
    pen = [];
    switch md
        case {'all','lme'}
            rows = find(sel & LGn == layer); a = lv(rows); b = nlv(rows); neur = uu(rows); pen = pk(rows);
        case 'mean'
            [a, b, neur] = i_perNeuronMeanLayer(D, sel, LGn, layer, lv, nlv, uu);
        otherwise   % first / maxpow -> dominant-layer representative
            rbCell = viz.plots.V01util.layerReps(D, find(sel), LGn, 'first', [1 2 3]);
            rows = rbCell{layer}; a = lv(rows); b = nlv(rows); neur = uu(rows); pen = pk(rows);
    end
    out = struct('a', a(:), 'b', b(:), 'neur', neur(:), 'pen', pen(:));
end

function [a, b, neur] = i_perNeuronMeanLayer(D, sel, LGn, layer, lv, nlv, uu)
    selIdx = find(sel);
    u = unique(uu(selIdx), 'stable');
    a = nan(numel(u),1); b = a; neur = a; m = 0;
    for j = 1:numel(u)
        oi = selIdx(uu(selIdx) == u(j));
        Lv = LGn(oi); Lv = Lv(isfinite(Lv));
        if isempty(Lv), continue; end
        domL = mode(Lv); if domL ~= layer, continue; end
        rr = oi(LGn(oi) == domL);
        m = m + 1; a(m) = mean(lv(rr),'omitnan'); b(m) = mean(nlv(rr),'omitnan'); neur(m) = u(j);
    end
    a = a(1:m); b = b(1:m); neur = neur(1:m);
end

% ===================================================================== %
%  V01 -- Dashboard (window f): a0{1} dFr%-vs-Dmetric regressions (E/I),
%  a0{3} 7 dFr-binned Control-vs-Laser signranks, Ax_r{2} slope ranksum.
%  index (HBW/OSI/CV) comes from state.index. Sim scatter (a0{2}) is model-
%  based and omitted from the report (see STATS_REPORTING_PLAN.md sec 11).
% ===================================================================== %
function specs = i_v01()
    S = {};
    % a0{1} real-data regressions
    sp = i_spec(); sp.figure='V01'; sp.panel='a0{1}'; sp.kind='corr'; sp.test='Pearson + OLS / LME';
    sp.group='PVE'; sp.source='Visualizer_01.m:1313/1319';
    sp.label='dFr% vs dmetric regression (PVE, dFr<0)';
    sp.notes='x=100*Delta_Fr, y=Delta_<index>; index from control dropdown';
    sp.build=@(D,state,md) i_corrReduce(D, i_eIdx(D,state), @(DD,ix) 100*i_field(DD,'Delta_Fr',ix), ...
        @(DD,ix) i_field(DD, i_v01Delta(state), ix), md, @(x) x<0);
    S{end+1}=sp;
    sp = i_spec(); sp.figure='V01'; sp.panel='a0{1}'; sp.kind='corr'; sp.test='Pearson + OLS / LME';
    sp.group='PVI'; sp.source='Visualizer_01.m:1258/1265';
    sp.label='dFr% vs dmetric regression (PVI, 0<dFr<200)';
    sp.notes='x=100*Delta_Fr, y=Delta_<index>';
    sp.build=@(D,state,md) i_corrReduce(D, i_iIdx(D,state), @(DD,ix) 100*i_field(DD,'Delta_Fr',ix), ...
        @(DD,ix) i_field(DD, i_v01Delta(state), ix), md, @(x) x>0 & x<200);
    S{end+1}=sp;
    % a0{3} 7 dFr-binned paired signranks (Control vs Laser of the index metric)
    binLab = {'PVE-H (dFr<-66)','PVE-M (-66..-33)','PVE-L (-33..0)', ...
              'PVI-L (0..33)','PVI-M (33..66)','PVI-H (66..100)','PVI-extra-H (>100)'};
    binF = {@(x) x<-66, @(x) x<-33 & x>=-66, @(x) x>=-33 & x<0, ...
            @(x) x>0 & x<=33, @(x) x>33 & x<=66, @(x) x>66 & x<=100, @(x) x>100};
    binWantI = [false false false true true true true];
    for k = 1:7
        sp = i_spec(); sp.figure='V01'; sp.panel='a0{3}'; sp.kind='paired'; sp.test='signrank / LME';
        sp.group=binLab{k}; sp.source='Visualizer_01.m:1523';
        sp.label=sprintf('%s: Control vs Laser', binLab{k});
        sp.notes='paired Control vs Laser of the selected index metric, within a dFr bin';
        sp.build=@(D,state,md) i_v01Bin(D, state, md, binWantI(k), binF{k});
        S{end+1}=sp; %#ok<AGROW>
    end
    % Ax_r{2} slope distribution ranksum (PVE vs PVI)
    sp = i_spec(); sp.figure='V01'; sp.panel='Ax_r{2}'; sp.kind='between'; sp.test='ranksum / LME';
    sp.group='PVE vs PVI'; sp.source='Visualizer_01.m:3324';
    sp.label='LTM gain-slope distribution: PVE vs PVI';
    sp.notes=['ranksum of LTM_slope between E and I populations. Mixed-effects column ' ...
              'fits v ~ grp + (1|pen) + (1|pen:neuron) to all obs (pen absorbs hemisphere).'];
    sp.build=@(D,state,md) i_v01SlopeBetween(D, state, md);
    S{end+1}=sp;
    specs = [S{:}];
end

function out = i_v01SlopeBetween(D, state, md)
%I_V01SLOPEBETWEEN  LTM slope PVE vs PVI, with obs-level ids for the LME mode.
    [eIdx, iIdx] = i_selEI(D, state);
    vfun = @(DD,ix) i_field(DD,'LTM_slope',ix);
    out = i_betweenReduce(D, eIdx, iIdx, vfun, md);
    [out.obsA, out.idA, out.penA] = i_obsLevel(D, eIdx, vfun);
    [out.obsB, out.idB, out.penB] = i_obsLevel(D, iIdx, vfun);
end

function f = i_v01Delta(state)
    switch upper(i_getf(state,'index','HBW'))
        case 'OSI', f = 'Delta_OSI';
        case 'CV',  f = 'Delta_CV';
        otherwise,  f = 'Delta_HBW';
    end
end
function flds = i_v01LNL(state)
    switch upper(i_getf(state,'index','HBW'))
        case 'OSI', flds = {'fitOSI_L','fitOSI_NL'};
        case 'CV',  flds = {'fitCV_L','fitCV_NL'};
        otherwise,  flds = {'fitHBW_L','fitHBW_NL'};
    end
end
function out = i_v01Bin(D, state, md, wantI, binf)
    [eIdx, iIdx] = i_selEI(D, state); obs = eIdx; if wantI, obs = iIdx; end
    x = 100 * i_field(D, 'Delta_Fr', obs);
    obs = obs(binf(x));
    flds = i_v01LNL(state);
    out = i_pairedReduce(D, obs, @(DD,ix) i_field(DD,flds{1},ix), @(DD,ix) i_field(DD,flds{2},ix), md);
end

% ===================================================================== %
%  f06 -- Categorization (f6b): STD of Delta/Ratio tuning, Linear(G_type==1)
%  vs Non-linear(G_type==2), ranksum, for PVE and PVI. Source F2_5B_3.m:2514.
% ===================================================================== %
function specs = i_f06()
    rows = { 'Delta_tun_nc','Delta', false, 'PVE'; ...
             'Ratio_tun',   'Ratio', false, 'PVE'; ...
             'Delta_tun_nc','Delta', true,  'PVI'; ...
             'Ratio_tun',   'Ratio', true,  'PVI' };
    S = {};
    for k = 1:size(rows,1)
        fieldMat = rows{k,1}; lab = rows{k,2}; wantI = rows{k,3}; pv = rows{k,4};
        sp = i_spec(); sp.figure='f06'; sp.panel=sprintf('f6b{%d}', k);
        sp.kind='between'; sp.test='ranksum / LME'; sp.group=[pv ' Lin vs Non-lin'];
        sp.source='F2_5B_3.m:2514';
        sp.label=sprintf('%s tuning STD: Linear vs Non-linear (%s)', lab, pv);
        sp.notes=['std of per-unit tuning curve over good_v columns; G_type 1 vs 2. ' ...
                  'Mixed-effects column fits v ~ class + (1|pen) + (1|pen:neuron) to all obs.'];
        sp.build=@(D,state,md) i_spreadBetween(D, state, md, wantI, fieldMat, 'std', 10, [], true);
        S{end+1}=sp; %#ok<AGROW>
    end
    specs = [S{:}];
end

function out = i_spreadBetween(D, state, md, wantI, fieldMat, kind, good_th, dist_th, withMM)
    if nargin < 9 || isempty(withMM), withMM = false; end
    [eIdx, iIdx] = i_selEI(D, state); pop = eIdx; if wantI, pop = iIdx; end
    G = viz.plots.V01util.colv(D, 'G_type'); G = G(:);
    if withMM && ~strcmp(md, 'all')
        G = i_classPerNeuron(G, viz.plots.V01util.colv(D,'U_unity'), pop);
    end
    gA = pop(G(pop) == 1); gB = pop(G(pop) == 2);          % Linear vs Non-linear
    vfun = @(DD,idx) i_spread(DD, idx, fieldMat, kind, good_th, dist_th);
    out = i_betweenReduce(D, gA, gB, vfun, md);
    if withMM
        % observation-level values + neuron/penetration ids, so runTest's 'lme'
        % mode can fit v ~ grp + (1|pen) + (1|pen:unit) instead of aggregating
        [out.obsA, out.idA, out.penA] = i_obsLevel(D, gA, vfun);
        [out.obsB, out.idB, out.penB] = i_obsLevel(D, gB, vfun);
    end
end

function Gc = i_classPerNeuron(G, UU, rows)
%I_CLASSPERNEURON  One class per neuron -- shared rule (V01util.classPerNeuron),
%   so the report's per-neuron / mixed-effects columns test the SAME populations
%   the figures draw. The 'all' column keeps the per-observation labels.
    Gc = viz.plots.V01util.classPerNeuron(G, UU, rows);
end

function [v, id, pen] = i_obsLevel(D, idx, vfun)
%I_OBSLEVEL  Ungated-out observations of vfun with their neuron/penetration ids.
    v  = vfun(D, idx); v = v(:);
    ok = isfinite(v); v = v(ok); rows = idx(ok);
    uu = viz.plots.V01util.colv(D, 'U_unity'); pk = viz.plots.V01util.penKey(D);
    id = uu(rows); pen = pk(rows);
end

% ===================================================================== %
%  f07 -- Stability: 12 ranksums of tuning-spread metrics (SD/mean, diff, PP)
%  for Delta/Ratio x PVE/PVI, Linear vs Non-linear. Sources F2_5B_3 3092/3249/3395.
% ===================================================================== %
function specs = i_f07()
    kinds = { 'sdmean','SD/mean',1.1,'F2_5B_3.m:3092'; ...
              'diff',  'diff',   1.0,'F2_5B_3.m:3249'; ...
              'pp',    'PP',     1.0,'F2_5B_3.m:3395' };
    panels = { 'Delta_tun_nc','Delta', false,'PVE'; ...
               'Ratio_tun',   'Ratio', false,'PVE'; ...
               'Delta_tun_nc','Delta', true, 'PVI'; ...
               'Ratio_tun',   'Ratio', true, 'PVI' };
    S = {};
    for ki = 1:size(kinds,1)
        kind = kinds{ki,1}; klab = kinds{ki,2}; dist = kinds{ki,3}; src = kinds{ki,4};
        for p = 1:size(panels,1)
            fieldMat = panels{p,1}; dlab = panels{p,2}; wantI = panels{p,3}; pv = panels{p,4};
            sp = i_spec(); sp.figure='f07'; sp.panel=sprintf('f7%c{%d}', 'a'+ki-1, p);
            sp.kind='between'; sp.test='ranksum / LME'; sp.group=[pv ' Lin vs Non-lin'];
            sp.source=src;
            sp.label=sprintf('%s %s tuning %s: Linear vs Non-linear (%s)', pv, dlab, klab, pv);
            sp.notes=['tuning-spread per unit over good_v columns (<dist_th); G_type 1 vs 2. ' ...
                      'Mixed-effects column fits v ~ class + (1|pen) + (1|pen:neuron) to all obs.'];
            sp.build=@(D,state,md) i_spreadBetween(D, state, md, wantI, fieldMat, kind, 10, dist, true);
            S{end+1}=sp; %#ok<AGROW>
        end
    end
    specs = [S{:}];
end

% ===================================================================== %
%  f05 -- Selectivity: s6 GoF (ExpM vs LTM R2), ID L-vs-NL distributions
%  (CV/OSI/HBW/DSI x PVE/PVI), between PVI-vs-PVE no-laser OSI, s5 gain
%  dose-response (model-based: ExpM params vs ExpM_dFR).
% ===================================================================== %
function specs = i_f05()
    S = {};
    % s6 goodness-of-fit (paired ExpM_R2 vs LTM_R2). The panel clips BOTH R^2 at
    % 0 for PVE (drawGof's clipNeg), so the spec must clip both too, and the two
    % sides are MODELS, not control/laser -- pairLabels renames the descriptive
    % so the row cannot be quoted as a control-vs-laser comparison.
    sp = i_pairedSpec('f05','s6{3}','PVE', 'Goodness-of-fit: ExpM vs LTM R^2 (PVE)', ...
        'F2_5B_3.m:440', false, @(DD,ix) max(i_field(DD,'ExpM_R2',ix),0), @(DD,ix) max(i_field(DD,'LTM_R2',ix),0), ...
        'ExpM vs LTM model R^2 (PVE clips both R^2 < 0 to 0, as the panel does)');
    sp.pairLabels = {'ExpM','LTM'}; S{end+1} = sp;
    sp = i_pairedSpec('f05','s6{4}','PVI', 'Goodness-of-fit: ExpM vs LTM R^2 (PVI)', ...
        'F2_5B_3.m:500', true,  @(DD,ix) i_field(DD,'ExpM_R2',ix), @(DD,ix) i_field(DD,'LTM_R2',ix), ...
        'ExpM vs LTM model R^2');
    sp.pairLabels = {'ExpM','LTM'}; S{end+1} = sp;
    % E+I POOLED goodness-of-fit (the tab's third s6 panel). No negative-R^2
    % clipping. With group ORI_NON_PV_NL / _MD (+ state.partition) this row IS
    % the manuscript's per-class ExpM-vs-LTM comparison (Results: per-cell
    % NL P=4.0e-20 n=309, D/M P=0.0029 n=186 under any-intensity + Mean).
    sp = i_spec(); sp.figure='f05'; sp.panel='s6{E+I}'; sp.kind='paired';
    sp.test='signrank / LME'; sp.group='E+I pooled';
    sp.source='Selectivity05Tab.drawGof (pooled panel)';
    sp.label='Goodness-of-fit: ExpM vs LTM R^2 (E+I pooled)';
    sp.notes=['ExpM vs LTM model R^2, PVA+PVI pooled, no clipping. The class scope ' ...
              'comes from the tab''s group (_NL / _MD) and Class-grouping dropdown ' ...
              '(state.partition: any-intensity vs majority-rule).'];
    sp.pairLabels = {'ExpM','LTM'};
    sp.build=@(D,state,md) i_pairedReduce(D, i_eiPool(D,state), ...
        @(DD,ix) i_field(DD,'ExpM_R2',ix), @(DD,ix) i_field(DD,'LTM_R2',ix), md);
    S{end+1} = sp;
    % ID distributions: CV/OSI/HBW/DSI, L vs NL, PVE then PVI
    idm = { 'CV', {'fitCV_L','fitCV_NL'},   false; 'OSI',{'fitOSI_L','fitOSI_NL'}, false; ...
            'HBW',{'fitHBW_L','fitHBW_NL'}, true;  'DSI',{'DSiL','DSiNL'},         false };
    pvs = {false 'PVE'; true 'PVI'};
    srcMap = struct('CV',{{'F2_5B_3.m:1265','F2_5B_3.m:1409'}}, 'OSI',{{'F2_5B_3.m:1308','F2_5B_3.m:1452'}}, ...
                    'HBW',{{'F2_5B_3.m:1347','F2_5B_3.m:1491'}}, 'DSI',{{'F2_5B_3.m:1591','F2_5B_3.m:1633'}});
    for pp = 1:2
        wantI = pvs{pp,1}; pv = pvs{pp,2};
        for m = 1:size(idm,1)
            met = idm{m,1}; flds = idm{m,2}; isHBW = idm{m,3};
            if isHBW, vL=@(DD,ix) i_fieldBad(DD,flds{1},ix); vNL=@(DD,ix) i_fieldBad(DD,flds{2},ix);
            else,     vL=@(DD,ix) i_field(DD,flds{1},ix);    vNL=@(DD,ix) i_field(DD,flds{2},ix); end
            srcs = srcMap.(met);
            S{end+1} = i_pairedSpec('f05', sprintf('ID{%s}',met), pv, ...
                sprintf('%s distribution: Laser vs Control (%s)', met, pv), srcs{pp}, wantI, vL, vNL, ...
                'fitted metric L vs NL'); %#ok<AGROW>
        end
    end
    % between: no-laser OSI PVI vs PVE (console-only in old code)
    sp = i_spec(); sp.figure='f05'; sp.panel='(console)'; sp.kind='between'; sp.test='ranksum / LME';
    sp.group='PVI vs PVE'; sp.source='F2_5B_3.m:1543';
    sp.label='No-laser OSI: PVI vs PVE (baseline selectivity)';
    sp.notes=['unannotated in old figure; between-population ranksum of fitOSI_NL. Mixed-' ...
              'effects column fits v ~ grp + (1|pen) + (1|pen:neuron) to all obs.'];
    sp.build=@(D,state,md) i_f05OsiBetween(D, state, md);
    S{end+1}=sp;
    % I2a control-vs-laser scatter of the tab's index dropdown (state.index)
    for pp = 1:2
        wantI = pvs{pp,1}; pv = pvs{pp,2};
        sp = i_spec(); sp.figure='f05'; sp.kind='paired'; sp.test='signrank / LME';
        sp.panel=sprintf('I2a%d', 2-double(wantI)); sp.group=pv;
        sp.source='F2_5B_3.m:1700'; sp.label=sprintf('Selectivity scatter: Laser vs Control (%s)', pv);
        sp.notes=['the bottom control-vs-laser scatter, for whatever index the tab''s ' ...
                  'dropdown shows (state.index; OSI/CV/HBW/DSI). Same values as the ' ...
                  'matching ID distribution row -- kept separate so the panel''s own ' ...
                  'star has a report row to be read against.'];
        sp.build=@(D,state,md) i_f05SelScatter(D, state, wantI, md);
        S{end+1}=sp; %#ok<AGROW>
    end
    % s5 gain dose-response (model-based), ONE ROW PER GAIN CLASS.
    % The panels fit and print D/M (G_type 1) and NL (G_type 2) SEPARATELY, and
    % for V0 the two classes correlate with OPPOSITE sign (e.g. PVE: D/M
    % r = -0.88, NL r = +0.73), so a single pooled row describes neither -- it
    % averages them into a weak artifact. Splitting also lets each row use the
    % panel's own estimator (exponential fit for beta, OLS for V0).
    gain = { 's5{1}','PVI',true,  'beta', 'F2_5B_3.m:557'; ...
             's5{2}','PVI',true,  'V0',   'F2_5B_3.m:633'; ...
             's5{3}','PVE',false, 'beta', 'F2_5B_3.m:776'; ...
             's5{4}','PVE',false, 'V0',   'F2_5B_3.m:849' };
    clsName = {'D/M','NL'};
    for k = 1:size(gain,1)
        pan=gain{k,1}; pv=gain{k,2}; wantI=gain{k,3}; gl=gain{k,4}; src=gain{k,5};
        isBeta = strcmp(gl,'beta');
        for cq = 1:2
            sp = i_spec(); sp.figure='f05'; sp.panel=pan; sp.kind='corr';
            if isBeta, sp.test='exp fit (fitnlm) / LME'; else, sp.test='Pearson + OLS / LME'; end
            sp.group=sprintf('%s %s (model-based)', pv, clsName{cq}); sp.source=src;
            sp.label=sprintf('Gain %s vs dFr dose-response (%s, %s)', gl, pv, clsName{cq});
            if isBeta
                sp.notes=['MODEL-BASED: ExpM_exponent vs ExpM_dFR for ONE gain class, matching ' ...
                          'Selectivity05Tab.drawGainPanel: r is Pearson over the class, p comes ' ...
                          'from the panel''s y = a*exp(b*x) fit with the y >= 17 cutoff applied ' ...
                          'after the per-neuron reduction. Mixed-effects linearizes it as ' ...
                          'log(y) ~ x + (1|pen) + (1|pen:neuron).'];
            else
                sp.notes=['MODEL-BASED: ExpM_theta vs ExpM_dFR for ONE gain class, matching ' ...
                          'drawGainPanel''s OLS fit. ExpM_theta IS V0 (= offset/exponent = the ' ...
                          'old F2_5B_3 b2/b3); the row previously divided it by the exponent ' ...
                          'AGAIN, i.e. b2/b3^2, which is neither the panel nor the old code.'];
            end
            sp.build=@(D,state,md) i_gainCorr(D, state, wantI, cq, isBeta, md);
            S{end+1}=sp; %#ok<AGROW>
        end
    end
    specs = [S{:}];
end

function out = i_f05SelScatter(D, state, wantI, md)
%I_F05SELSCATTER  f05 I2a bottom scatter: control vs laser for state.index.
    [eIdx, iIdx] = i_selEI(D, state);
    if wantI, obs = iIdx; else, obs = eIdx; end
    idx = 'OSI';
    if isstruct(state) && isfield(state,'index') && ~isempty(state.index), idx = char(state.index); end
    switch upper(idx)
        case 'CV',  vL=@(DD,ix) i_field(DD,'fitCV_L',ix);  vNL=@(DD,ix) i_field(DD,'fitCV_NL',ix);
        case 'HBW', vL=@(DD,ix) i_fieldBad(DD,'fitHBW_L',ix); vNL=@(DD,ix) i_fieldBad(DD,'fitHBW_NL',ix);
        case 'DSI', vL=@(DD,ix) i_field(DD,'DSiL',ix);     vNL=@(DD,ix) i_field(DD,'DSiNL',ix);
        otherwise,  vL=@(DD,ix) i_field(DD,'fitOSI_L',ix); vNL=@(DD,ix) i_field(DD,'fitOSI_NL',ix);
    end
    out = i_pairedReduce(D, obs, vL, vNL, md);
end

function out = i_gainCorr(D, state, wantI, classIdx, isBeta, md)
%I_GAINCORR  One f05 s5 gain regression, for ONE gain class.
%   Mirrors viz.plots.Selectivity05Tab.drawGainPanel exactly: the class is
%   G_type in 'all' mode and the neuron's MAJORITY class in the per-neuron modes
%   (so a class-straddling neuron cannot be fitted into both classes), x is
%   ExpM_dFR, y is beta = ExpM_exponent or V0 = ExpM_theta, and the beta fit
%   drops y >= 17 AFTER the reduction -- while r stays Pearson over every point,
%   which is what the panel prints.
    [eIdx, iIdx] = i_selEI(D, state);
    if wantI, obs = iIdx; else, obs = eIdx; end
    G  = viz.plots.V01util.colv(D, 'G_type');
    uu = viz.plots.V01util.colv(D, 'U_unity');
    % Class rule follows the tab's Class-grouping dropdown (state.partition):
    % 'majority' resolves one class per neuron for EVERY mode, 'any' keeps the
    % per-observation labels for every mode (a straddling neuron then appears
    % in both classes in the per-neuron modes, matching the panel). A state
    % without the field (older saved reports) keeps the legacy rule: majority
    % for the per-neuron modes, per-observation for 'all'.
    part = i_getf(state, 'partition', '');
    if strcmp(part, 'majority') || (isempty(part) && ~strcmp(md, 'all'))
        G = viz.plots.V01util.classPerNeuron(G, uu, [eIdx(:); iIdx(:)]);
    end
    obs = obs(G(obs) == classIdx);
    xf = @(DD,ix) i_field(DD,'ExpM_dFR',ix);
    if isBeta, yf = @(DD,ix) i_field(DD,'ExpM_exponent',ix);
    else,      yf = @(DD,ix) i_field(DD,'ExpM_theta',ix); end
    out = i_corrReduce(D, obs, xf, yf, md, []);
    out.showSlope = true;                    % report the panel's "s =" too
    if isBeta
        out.fitKind = 'exp';
        out.fitMask = out.y < 17;            % drawGainPanel's yMax cutoff
    end
end

function out = i_f05OsiBetween(D, state, md)
%I_F05OSIBETWEEN  No-laser OSI PVI vs PVE, with obs-level ids for the LME mode.
    [eIdx, iIdx] = i_selEI(D, state);
    vfun = @(DD,ix) i_field(DD,'fitOSI_NL',ix);
    out = i_betweenReduce(D, iIdx, eIdx, vfun, md);
    [out.obsA, out.idA, out.penA] = i_obsLevel(D, iIdx, vfun);
    [out.obsB, out.idB, out.penB] = i_obsLevel(D, eIdx, vfun);
end

function sp = i_pairedSpec(fig, panel, pv, label, src, wantI, vL, vNL, notes)
    sp = i_spec(); sp.figure=fig; sp.panel=panel; sp.kind='paired'; sp.test='signrank / LME';
    sp.group=pv; sp.source=src; sp.label=label; sp.notes=notes;
    if wantI, idxf=@(D,state) i_iIdx(D,state); else, idxf=@(D,state) i_eIdx(D,state); end
    sp.build=@(D,state,md) i_pairedReduce(D, idxf(D,state), vL, vNL, md);
end

% ===================================================================== %
%  F27 -- LayerNoLaser (F27_5_3 f2): 4 ANOVA+Tukey across SG/G/IG of the
%  no-laser metric (OSI/CV/HBW + baseline Fr). Sources F27_5_3 204/355/499/751.
% ===================================================================== %
function specs = i_f27()
    rows = { 'OSI',  @(DD,ix) i_field(DD,'fitOSI_NL',ix),  'F27_5_3.m:204'; ...
             'CV',   @(DD,ix) i_field(DD,'fitCV_NL',ix),   'F27_5_3.m:355'; ...
             'HBW',  @(DD,ix) i_fieldBad(DD,'fitHBW_NL',ix),'F27_5_3.m:499'; ...
             'Baseline Fr', @(DD,ix) i_baselineFr(DD,ix),  'F27_5_3.m:751' };
    S = {};
    for k = 1:size(rows,1)
        met = rows{k,1}; vfun = rows{k,2}; src = rows{k,3};
        sp = i_spec(); sp.figure='F27'; sp.panel=sprintf('b1{%d}',k);
        sp.kind='anova'; sp.test='anova1 + Tukey / LME'; sp.group='SG/G/IG';
        sp.source=src; sp.label=sprintf('No-laser %s across layers (SG/G/IG)', met);
        sp.notes='fitted no-laser metric; dominant-layer assignment for first/mean/lme';
        sp.build=@(D,state,md) i_anovaReduce(D, state, vfun, md, [1 2 3]);
        S{end+1}=sp; %#ok<AGROW>
    end
    specs = [S{:}];
end

function v = i_baselineFr(D, idx)
    M = D.fit_mid_self_NL; v = ((M(1,idx) + M(end,idx))/2)';   % orthogonal/baseline response
    v = v(:);
end

% ===================================================================== %
%  V03f -- GainLaminar (Visualizer_03 f): 6 ranksums of no-laser OSI/CV/HBW,
%  MXH(G_type==2) vs Mlt(G_type==1), PVE & PVI. Sources Visualizer_03 a4{1..6}.
% ===================================================================== %
function specs = i_v03f()
    rows = { 'OSI', 'fitOSI_NL', false, false,'PVE','Visualizer_03.m:2414'; ...
             'CV',  'fitCV_NL',  false, false,'PVE','Visualizer_03.m:2571'; ...
             'HBW', 'fitHBW_NL', true,  false,'PVE','Visualizer_03.m:2729'; ...
             'OSI', 'fitOSI_NL', false, true, 'PVI','Visualizer_03.m:2488'; ...
             'CV',  'fitCV_NL',  false, true, 'PVI','Visualizer_03.m:2648'; ...
             'HBW', 'fitHBW_NL', true,  true, 'PVI','Visualizer_03.m:2805' };
    S = {};
    for k = 1:size(rows,1)
        met=rows{k,1}; fname=rows{k,2}; isHBW=rows{k,3}; wantI=rows{k,4}; pv=rows{k,5}; src=rows{k,6};
        sp = i_spec(); sp.figure='V03f'; sp.panel=sprintf('a4{%d}',k);
        sp.kind='between'; sp.test='ranksum / LME'; sp.group=[pv ' MXH vs Mlt'];
        sp.source=src; sp.label=sprintf('No-laser %s: MXH vs Mlt (%s)', met, pv);
        sp.notes=['laser-off fitted metric; G_type 2 (MXH) vs 1 (Mlt). Mixed-effects ' ...
                  'column fits v ~ class + (1|pen) + (1|pen:neuron) to all obs.'];
        sp.build=@(D,state,md) i_classBetween(D, state, md, wantI, fname, isHBW);
        S{end+1}=sp; %#ok<AGROW>
    end
    specs = [S{:}];
end

function out = i_classBetween(D, state, md, wantI, fname, isHBW)
    [eIdx, iIdx] = i_selEI(D, state); pop = eIdx; if wantI, pop = iIdx; end
    G = viz.plots.V01util.colv(D, 'G_type'); G = G(:);
    % MXH/Mlt is a PER-OBSERVATION label, so a neuron can carry both. Any view
    % that is one-point-per-neuron must resolve it to a single class first, or
    % the neuron lands in both groups and the mixed model turns part of the
    % class contrast into a within-neuron comparison. 'all' keeps the published
    % per-observation labels.
    if ~strcmp(md, 'all')
        G = i_classPerNeuron(G, viz.plots.V01util.colv(D,'U_unity'), pop);
    end
    gA = pop(G(pop) == 2); gB = pop(G(pop) == 1);          % MXH vs Mlt
    if isHBW, vfun=@(DD,idx) i_fieldBad(DD,fname,idx); else, vfun=@(DD,idx) i_field(DD,fname,idx); end
    out = i_betweenReduce(D, gA, gB, vfun, md);
    % observation-level values + neuron/penetration ids for runTest's 'lme' mode
    [out.obsA, out.idA, out.penA] = i_obsLevel(D, gA, vfun);
    [out.obsB, out.idB, out.penB] = i_obsLevel(D, gB, vfun);
end

% ===================================================================== %
function s = i_ei2pv(ei)
    if strcmpi(ei, 'I'), s = 'PVI (inhibition)'; else, s = 'PVE (excitation)'; end
end

function v = i_getf(s, f, dflt)
    if isstruct(s) && isfield(s, f) && ~isempty(s.(f)), v = s.(f); else, v = dflt; end
end

function sp = i_spec()
%I_SPEC  Blank spec. `pairLabels` names the two sides of a 'paired' row in the
%   descriptive string ({A, B} -> "B <val> -> A <val>"); the default suits the
%   control-vs-laser rows that make up almost all of them, and a spec that pairs
%   something else (e.g. two model fits) overrides it so the cell cannot be read
%   as a control-vs-laser comparison.
    sp = struct('figure','', 'panel','', 'label','', 'group','', 'groupFn',[], ...
                'kind','', 'test','', 'source','', 'notes','', 'build',[], ...
                'pairLabels', {{'laser','ctrl'}});
end
