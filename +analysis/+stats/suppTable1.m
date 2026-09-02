function out = suppTable1(D, state)
%SUPPTABLE1  Supplementary Table 1 for the new Fig.2 (layer selectivity, f2): a
%   layer-by-layer descriptive table of the laser-induced CHANGES plus the unit /
%   animal / penetration counts.
%
%   out = analysis.stats.suppTable1(D, state)
%
%   Columns: Layer, dFr (%), OSI Ctrl/Laser/dOSI/p, CV Ctrl/Laser/dCV/p,
%   HBW Ctrl/Laser/dHBW (deg)/p, # units, # animals, # penetrations.  Rows: SG / G /
%   IG (+ a pooled "All layers" row).  Absolute Control / Laser index values and
%   every delta (Laser - Control) are shown as mean +/- SEM; p = the paired
%   Control-vs-Laser test behind the figure's stars.  The table honors the figure's
%   current selection -- population (state.ei), unit group (state.group), the dFr
%   filter (folded into state.mask) -- and the repeated-obs mode (state.mode):
%     'all'              : every unit x intensity observation (the manuscript convention);
%     'first'/'maxpow'   : one representative observation per neuron;
%     'mean'/'lme'       : each neuron once, as its per-neuron mean, assigned to
%                          its DOMINANT layer (so the layer counts sum to the
%                          All-layers row). p under 'lme' is the same mixed model
%                          Table 2 reports: ~ cond + (1|pen) + (1|pen:neuron).
%   Under 'lme'/'mean' the counts are NEURON counts, matching the Mixed-effects
%   figure; under 'all' they are observation counts. HBW drops Align_bad units.
%
%   Returned as a render-ready struct for viz.plots.StatsReport (ColumnName/Data/
%   legend), so the f2 tab can show it via reportSpec().out.
%
%   See also: viz.plots.LayerSelectivity02Tab, analysis.stats.figureCatalog,
%             viz.plots.V01util.aggNeuronScalar

    colv = @viz.plots.V01util.colv;
    DD = char(916); DEG = char(176);                       % Greek delta, degree sign

    layers = [1 2 3]; labs = {'SG','G','IG'};
    if isfield(state,'layers') && ~isempty(state.layers)
        layers = state.layers; allLab = {'SG','G','IG','Deep'};
        labs = allLab(layers);
    end
    mode = 'all'; if isfield(state,'mode') && ~isempty(state.mode), mode = char(state.mode); end

    grpMask = analysis.tuningGroupMask(D, state.group); grpMask = grpMask(:);
    isI  = viz.plots.V01util.isInhib(D); isI = isI(:);
    want = strcmp(state.ei, 'I');
    sel  = state.mask(:) & grpMask & (isI == want);
    LGn  = viz.plots.V01util.layerNum(D); LGn = LGn(:);

    UU    = colv(D, 'U_unity');
    osiL  = colv(D,'fitOSI_L'); osiNL = colv(D,'fitOSI_NL');
    cvL   = colv(D,'fitCV_L');  cvNL  = colv(D,'fitCV_NL');
    hbwL  = colv(D,'fitHBW_L'); hbwNL = colv(D,'fitHBW_NL');
    bad   = colv(D,'Align_bad') == 1; hbwL(bad) = NaN; hbwNL(bad) = NaN;   % HBW: drop not-aligned
    dfr   = 100 * colv(D,'Delta_Fr');                      % laser firing-rate change (%)

    nL = numel(layers);
    Data = cell(nL+1, 17);

    % ---- per-layer rows: same display units the f2 figure draws ----------- %
    %   layerReps gives observation rows under 'all'/'lme' and dominant-layer
    %   representative rows under 'first'/'maxpow'/'mean'; under 'lme' (and 'mean')
    %   we then collapse each neuron to ONE per-neuron mean (within the layer),
    %   exactly as the Mixed-effects box / paired / change-distribution panels.
    repByLayer = viz.plots.V01util.layerReps(D, find(sel), LGn, mode, layers);
    perNeuron  = any(strcmp(mode, {'lme','mean'}));
    PK = viz.plots.V01util.penKey(D);
    % the V02 catalog's specs (same selection + model as Table 2 / the report);
    % only usable for the standard SG/G/IG set
    vspecs = [];
    if isequal(layers(:)', [1 2 3])
        try, vspecs = analysis.stats.figureCatalog('V02', state); catch, vspecs = []; end
    end
    if perNeuron
        % Each neuron belongs to ONE layer (its dominant layer), and the row then
        % uses ALL of that neuron's recordings IN that layer. Without this a
        % neuron recorded in two layers is counted in both, so the layer counts
        % do not sum to the All-layers row; and layerReps' 'mean' representative
        % is the FIRST row, so the values would be firsts, not means. Matches
        % analysis.stats.table1 / the V02 catalog, i.e. Table 1 and Table 2.
        rbDom = viz.plots.V01util.layerReps(D, find(sel), LGn, 'first', layers);
        for k = 1:nL
            nsel = UU(rbDom{k});
            repByLayer{k} = find(sel & LGn == layers(k) & ismember(UU, nsel));
        end
    end
    for k = 1:nL
        rp = repByLayer{k}; neur = UU(rp);
        % paired Control-vs-Laser p per metric (signed-rank, or LME under mixed-effects)
        % on the OBSERVATIONS -- exactly the test behind the figure's significance stars.
        % p comes from the SAME spec Table 2 and the stats report use, so the
        % table, the report and the manuscript can never disagree on a p value.
        if ~isempty(vspecs)
            li = find(layers == layers(k), 1);
            pOSI = i_specP(vspecs, 1, k, D, state, mode);
            pCV  = i_specP(vspecs, 2, k, D, state, mode);
            pHBW = i_specP(vspecs, 3, k, D, state, mode);
        else
            pOSI = viz.plots.V01util.smPaired(osiL(rp), osiNL(rp), neur, mode, PK(rp));
            pCV  = viz.plots.V01util.smPaired(cvL(rp),  cvNL(rp),  neur, mode, PK(rp));
            pHBW = viz.plots.V01util.smPaired(hbwL(rp), hbwNL(rp), neur, mode, PK(rp));
        end
        dFrU  = dfr(rp);  dHBWU = hbwL(rp)-hbwNL(rp);
        dOSIU = osiL(rp)-osiNL(rp); dCVU = cvL(rp)-cvNL(rp);
        osiCU = osiNL(rp); osiLU = osiL(rp);               % absolute Control / Laser index
        cvCU  = cvNL(rp);  cvLU  = cvL(rp);
        hbwCU = hbwNL(rp); hbwLU = hbwL(rp);
        repU  = rp(:);
        if perNeuron                                       % per-neuron within layer ('mean' AND 'lme')
            [dFrU, ~, repU] = viz.plots.V01util.aggNeuronScalar(dFrU, neur, rp);
            dHBWU = viz.plots.V01util.aggNeuronScalar(dHBWU, neur);
            dOSIU = viz.plots.V01util.aggNeuronScalar(dOSIU, neur);
            dCVU  = viz.plots.V01util.aggNeuronScalar(dCVU,  neur);
            osiCU = viz.plots.V01util.aggNeuronScalar(osiCU, neur); osiLU = viz.plots.V01util.aggNeuronScalar(osiLU, neur);
            cvCU  = viz.plots.V01util.aggNeuronScalar(cvCU,  neur); cvLU  = viz.plots.V01util.aggNeuronScalar(cvLU,  neur);
            hbwCU = viz.plots.V01util.aggNeuronScalar(hbwCU, neur); hbwLU = viz.plots.V01util.aggNeuronScalar(hbwLU, neur);
        end
        Data(k,:) = i_row(labs{k}, dFrU, osiCU, osiLU, dOSIU, pOSI, cvCU, cvLU, dCVU, pCV, hbwCU, hbwLU, dHBWU, pHBW, repU, D);
    end

    % ---- pooled "All layers" row: per-neuron reduction over all 3 layers --- %
    %   reuse the standard reducer so the count is distinct neurons (mean/lme/
    %   first) or observations (all); a neuron spanning two layers is counted
    %   once here even though it appears in both per-layer rows under 'lme'.
    rpAll = find(sel & ismember(LGn, layers));
    rmode = mode; if strcmp(rmode,'lme'), rmode = 'mean'; end
    R     = viz.plots.V01util.reducer(D, rpAll, rmode);
    dFrA  = viz.plots.V01util.redVec(R, dfr(rpAll));
    dHBWA = viz.plots.V01util.redVec(R, hbwL(rpAll)-hbwNL(rpAll));
    dOSIA = viz.plots.V01util.redVec(R, osiL(rpAll)-osiNL(rpAll));
    dCVA  = viz.plots.V01util.redVec(R, cvL(rpAll)-cvNL(rpAll));
    osiCA = viz.plots.V01util.redVec(R, osiNL(rpAll)); osiLA = viz.plots.V01util.redVec(R, osiL(rpAll));
    cvCA  = viz.plots.V01util.redVec(R, cvNL(rpAll));  cvLA  = viz.plots.V01util.redVec(R, cvL(rpAll));
    hbwCA = viz.plots.V01util.redVec(R, hbwNL(rpAll)); hbwLA = viz.plots.V01util.redVec(R, hbwL(rpAll));
    repA  = viz.plots.V01util.redIdx(R);
    pOSIa = viz.plots.V01util.smPaired(osiL(rpAll), osiNL(rpAll), UU(rpAll), mode, PK(rpAll));   % pooled across layers
    pCVa  = viz.plots.V01util.smPaired(cvL(rpAll),  cvNL(rpAll),  UU(rpAll), mode, PK(rpAll));
    pHBWa = viz.plots.V01util.smPaired(hbwL(rpAll), hbwNL(rpAll), UU(rpAll), mode, PK(rpAll));
    Data(nL+1,:) = i_row('All layers', dFrA, osiCA, osiLA, dOSIA, pOSIa, cvCA, cvLA, dCVA, pCVa, hbwCA, hbwLA, dHBWA, pHBWa, repA, D);

    ColumnName = {'Layer', [DD 'Fr (%)'], ...
                  'OSI Ctrl', 'OSI Laser', [DD 'OSI'], 'p(OSI)', ...
                  'CV Ctrl', 'CV Laser', [DD 'CV'], 'p(CV)', ...
                  ['HBW Ctrl (' DEG ')'], ['HBW Laser (' DEG ')'], [DD 'HBW (' DEG ')'], 'p(HBW)', ...
                  '# units', '# animals', '# penetrations'};

    eiName = 'PVE (excitation)'; if want, eiName = 'PVI (inhibition)'; end
    if perNeuron, cw = 'distinct neurons (each neuron once)';
    elseif strcmp(mode,'all'), cw = 'unit x intensity observations';
    else, cw = 'one representative observation per neuron'; end
    header = sprintf(['Supplementary Table 1 \x2014 new Fig.2 (%s, group %s, repeated-obs: %s). ' ...
        'Absolute Control / Laser OSI/CV/HBW and %s = Laser \x2212 Control, all mean \x00B1 SEM; ' ...
        'p = paired Control-vs-Laser (signed-rank; mixed-effects under LME). ' ...
        '%sFr in %%, HBW / %sHBW in degrees. Counts: %s.'], ...
        eiName, state.group, i_modeName(mode), DD, DD, DD, cw);

    legend = sprintf(['Absolute Ctrl / Laser index (mean \x00B1 SEM) shown beside each ' ...
        '%s = Laser \x2212 Control (mean \x00B1 SEM).  p(OSI/CV/HBW) = paired Control-vs-Laser ' ...
        'signed-rank (LME under Mixed-effects), same test as the figure stars; the All-layers p ' ...
        'pools every selected observation.  # units = neurons under ' ...
        'Mixed-effects / Mean, observations under All.  # penetrations counts distinct ' ...
        'animal\x00D7penetration sites.  HBW excludes not-aligned (Align_bad) units.'], DD);

    out = struct('ColumnName', {ColumnName}, 'Data', {Data}, 'modes', {{mode}}, ...
                 'header', header, 'legend', legend);
end

% ===================================================================== %
function p = i_specP(specs, metIdx, layerIdx, D, state, mode)
%I_SPECP  p for one metric x layer from the V02 catalog (metric-major order).
    p = NaN;
    k = (metIdx-1)*3 + layerIdx;
    if k > numel(specs), return; end
    try, r = analysis.stats.runTest(specs(k), D, state, mode); p = r.p; catch, end %#ok<CTCH>
end

% ===================================================================== %
function c = i_row(lab, dFr, osiC, osiLa, dOSI, pO, cvC, cvLa, dCV, pC, hbwC, hbwLa, dHBW, pH, rows, D)
    [nA, nP] = i_animalPen(D, rows);
    c = {lab, i_ms(dFr,1), ...
         i_ms(osiC,3), i_ms(osiLa,3), i_ms(dOSI,3), i_p(pO), ...
         i_ms(cvC,3),  i_ms(cvLa,3),  i_ms(dCV,3),  i_p(pC), ...
         i_ms(hbwC,1), i_ms(hbwLa,1), i_ms(dHBW,1), i_p(pH), ...
         sprintf('%d', numel(rows(:))), sprintf('%d', nA), sprintf('%d', nP)};
end

function s = i_ms(v, dec)
    v = v(:); v = v(isfinite(v));
    if isempty(v), s = '-'; return; end
    m = mean(v); se = std(v)/sqrt(numel(v));
    s = sprintf('%.*f \x00B1 %.*f', dec, m, dec, se);
end

function s = i_p(p)
    %I_P  Paired Control-vs-Laser p, with the significance stars used in the figure.
    if ~isfinite(p), s = '-'; return; end
    st = viz.plots.V01util.sigStars(p);
    if p < 1e-4, s = sprintf('%s %.1e', st, p);
    else,        s = sprintf('%s %.4f', st, p); end
    s = strtrim(s);
end

function [nA, nP] = i_animalPen(D, rows)
    rows = rows(:);
    if isempty(rows), nA = 0; nP = 0; return; end
    if     isfield(D,'Animal'),  ak = string(D.Animal(rows));
    elseif isfield(D,'Dataset'), ak = string(D.Dataset(rows));
    else,                        ak = strings(numel(rows),1); end
    if isfield(D,'Penetration'), pk = string(D.Penetration(rows)); else, pk = strings(numel(rows),1); end
    okA = ~(ismissing(ak) | ak == "");
    nA  = numel(unique(ak(okA)));
    okP = okA & ~(ismissing(pk) | pk == "");
    nP  = numel(unique(ak(okP) + "|" + pk(okP)));           % distinct animal x penetration
end

function s = i_modeName(mode)
    switch char(mode)
        case 'all',    s = 'All (observations)';
        case 'first',  s = 'First per neuron';
        case 'maxpow', s = 'Max laser power';
        case 'mean',   s = 'Mean per neuron';
        case 'lme',    s = 'Mixed-effects (per-neuron)';
        otherwise,     s = char(mode);
    end
end
