function out = sourceData(D, outFile, varargin)
%SOURCEDATA  Build the journal's Source Data workbook from the app's own data.
%
%   analysis.sourceData()             % loads data, writes 'Source Data.xlsx'
%   analysis.sourceData(D, outFile)
%   analysis.sourceData(D, outFile, 'nIntensities', true)   % add the per-row
%       recording counts (off by default)
%   analysis.sourceData(D, outFile, 'perObs', true)   % also write the
%       per-recording (unit-intensity) *_perobs sheets (off by default)
%
%   Besides the raw values, *_stats sheets carry the statistics the panels and
%   legends quote, computed from the same tables (regressions and within-group
%   comparisons per cell for Figs. 4-5; NL-vs-D/M rank-sums for Fig. 3E; the
%   ExpM-vs-LTM goodness-of-fit per unit-intensity observation).
%
%   One sheet per display item, holding the raw numbers behind the plots:
%     Fig2_percell   per-cell OSI/CV/HBW control & laser, by layer x manipulation
%                    (the box plots / pairwise scatters of Fig. 2D-I); values
%                    averaged across the recordings in the cell's dominant layer
%     Fig3_counts    the Fig. 3B partition (majority rule) and Fig. 3D laminar
%                    prevalence of the NL and D/M classes
%     Fig3E_percell  per-cell OSI/CV/HBW by class (majority rule) x manipulation,
%                    averaged across all the cell's recordings
%     Fig4_percell   ΔHBW vs ΔFr per cell, any-intensity populations
%                    (Fig. 4A,B,E,F; the control/laser HBW of Fig. 4C,G)
%     Fig5_percell   same for ΔOSI and ΔCV (Fig. 5)
%     GoF_percell    ExpM vs LTM goodness-of-fit R^2 per cell x any-intensity
%                    class (model comparison, the text's convention: NL
%                    P=4.0e-20 n=309, D/M P=0.0029 n=186 via signrank)
%     Table1 / Table2  the manuscript tables, from the same single-source code
%
%   With 'perObs', true the workbook ALSO carries the per-recording sheets
%   (one row per unit-intensity recording): Fig4_perobs / Fig5_perobs (the
%   panels' dots, with the magnitude group L/M/H/XH), Fig6KL_perobs (I/O-model
%   theta, beta vs ΔFr; Fig. 6K,L), Fig7_perobs and SuppFig6_perobs (model-
%   simulated metrics). By default they are NOT written -- repeated UnitID rows
%   would reveal per-cell recording counts -- but they are still computed
%   internally (the *_stats sheets are derived from them) and returned in
%   out.perObs.
%
%   Conventions (all identical to the app's stats engine):
%     - the 5 noise recordings are excluded (V01util.noiseMask)
%     - group mask ORI_NON_PV (orientation-selective, non-PV+)
%     - Fig. 3 classes: majority rule (classPerNeuron; Mix in neither class)
%     - Fig. 4/5 populations: ANY-intensity membership; per-cell values are the
%       mean over the intensities at which the cell was recorded within that
%       population, matching the revised text
%
%   See also: analysis.stats.table1, analysis.stats.fig2Table, check_consistency

    if nargin < 1 || isempty(D)
        [D, dm] = loadData([], 'Dataset', 'paper');
        fitArgs = viz.Visualizer.defaultCacheArgs();
        D = analysis.computeMetricsCached(D, dm, fitArgs{:});
    end
    if nargin < 2 || isempty(outFile), outFile = 'Source Data.xlsx'; end
    ip = inputParser;
    ip.addParameter('nIntensities', false, @islogical);
    ip.addParameter('perObs', false, @islogical);
    ip.parse(varargin{:});
    wantN = ip.Results.nIntensities;
    wantObs = ip.Results.perObs;
    if exist(outFile, 'file'), delete(outFile); end

    U   = viz.plots.V01util;
    keep = ~U.noiseMask(D); keep = keep(:);
    grp  = analysis.tuningGroupMask(D, 'ORI_NON_PV'); grp = grp(:);
    sel  = keep & grp;

    uu   = U.colv(D,'U_unity');   uu  = uu(:);
    pk   = U.penKey(D);           pk  = pk(:);
    isI  = U.isInhib(D);          isI = isI(:);
    lay  = U.layerNum(D);         lay = lay(:);
    G    = U.colv(D,'G_type');    G   = G(:);
    dfr  = 100 * U.colv(D,'Delta_Fr'); dfr = dfr(:);
    osiC = U.colv(D,'fitOSI_NL'); osiL = U.colv(D,'fitOSI_L');
    cvC  = U.colv(D,'fitCV_NL');  cvL  = U.colv(D,'fitCV_L');
    hbwC = U.colv(D,'fitHBW_NL'); hbwL = U.colv(D,'fitHBW_L');
    bad  = U.colv(D,'Align_bad') == 1;
    hbwC(bad) = NaN; hbwL(bad) = NaN;
    er2  = U.colv(D,'ExpM_R2');   lr2 = U.colv(D,'LTM_R2');
    th   = U.colv(D,'ExpM_theta');    bet = U.colv(D,'ExpM_exponent');
    layN = {'SG','G','IG'};

    manip = repmat("PVA", numel(uu), 1); manip(isI) = "PVI";
    Gc = U.classPerNeuron(G, uu, find(sel));
    clsMaj = strings(numel(uu),1);
    clsMaj(Gc==1) = "D/M"; clsMaj(Gc==2) = "NL"; clsMaj(Gc==0) = "Mix"; clsMaj(Gc==3) = "Uct";
    layS = strings(numel(uu),1);
    okL = isfinite(lay) & lay >= 1 & lay <= 3;
    layS(okL) = string(layN(lay(okL)));

    sheets = {};

    % ------------------------------------------------------------- Fig2_percell
    % Engine rule (V01util.layerReps): each cell belongs to its DOMINANT layer
    % (mode over its recordings) and its per-cell values average only the
    % recordings in that layer -- exactly what Tables 1-2 quote.
    rows = find(sel);
    [~, ~, gci] = unique(uu(rows), 'stable');
    T = table('Size', [0 12], 'VariableTypes', ...
        {'double','double','string','string','double','double','double','double', ...
         'double','double','double','double'}, 'VariableNames', ...
        {'UnitID','Penetration','Manipulation','Layer','dFr_pct_mean', ...
         'OSI_control','OSI_laser','CV_control','CV_laser', ...
         'HBW_control_deg','HBW_laser_deg','nIntensities'});
    for j = 1:max(gci)
        oi = rows(gci == j);
        Lv = lay(oi); Lv = Lv(isfinite(Lv));
        if isempty(Lv), continue; end
        domL = mode(Lv);
        if domL < 1 || domL > 3, continue; end
        od = oi(lay(oi) == domL);
        T(end+1,:) = {uu(od(1)), pk(od(1)), manip(od(1)), string(layN{domL}), ...
            mean(dfr(od),'omitnan'), mean(osiC(od),'omitnan'), mean(osiL(od),'omitnan'), ...
            mean(cvC(od),'omitnan'), mean(cvL(od),'omitnan'), ...
            mean(hbwC(od),'omitnan'), mean(hbwL(od),'omitnan'), numel(od)};
    end
    sheets(end+1,:) = {'Fig2_percell', T}; %#ok<*AGROW>

    % ------------------------------------------- per-cell over ALL recordings
    R = U.reducer(D, rows, 'mean');
    reps = U.redIdx(R);
    Tall = table(uu(reps), pk(reps), manip(reps), ...
        U.redVec(R, dfr(rows)), ...
        U.redVec(R, osiC(rows)), U.redVec(R, osiL(rows)), ...
        U.redVec(R, cvC(rows)),  U.redVec(R, cvL(rows)), ...
        U.redVec(R, hbwC(rows)), U.redVec(R, hbwL(rows)), ...
        accumn(R, rows), ...
        'VariableNames', {'UnitID','Penetration','Manipulation', ...
        'dFr_pct_mean','OSI_control','OSI_laser','CV_control','CV_laser', ...
        'HBW_control_deg','HBW_laser_deg','nIntensities'});

    % ------------------------------------------------------------- Fig3_counts
    cellRows = reps;                                   % one row per cell
    C = table(); k = 0;
    for mv = ["PVA" "PVI" "all"]
        for cv = ["NL" "D/M" "Mix" "Uct"]
            m = cellRows(clsMaj(cellRows) == cv & (mv == "all" | manip(cellRows) == mv));
            k = k + 1;
            C.Manipulation(k) = mv; C.Class(k) = cv; C.nCells(k) = numel(m);
        end
    end
    % Fig. 3D laminar prevalence (NL vs D/M, per layer, classes pooled over manip)
    P = table(); k = 0;
    for li = 1:3
        m = cellRows(layS(cellRows) == layN{li});
        nNL = sum(clsMaj(m) == "NL"); nDM = sum(clsMaj(m) == "D/M");
        k = k + 1;
        P.Layer(k) = string(layN{li}); P.nNL(k) = nNL; P.nDM(k) = nDM;
        P.pctNL(k) = 100 * nNL / max(1, nNL + nDM);
        P.pctDM(k) = 100 * nDM / max(1, nNL + nDM);
    end
    sheets(end+1,:) = {'Fig3B_counts', C};
    sheets(end+1,:) = {'Fig3D_laminar', P};

    % ----------------------------------------------------------- Fig3E_percell
    m3 = cellRows(clsMaj(cellRows) == "NL" | clsMaj(cellRows) == "D/M");
    i3 = ismember(reps, m3);
    T3 = Tall(i3, :);
    T3.Class = clsMaj(reps(i3));
    T3 = movevars(T3, 'Class', 'After', 'Manipulation');
    sheets(end+1,:) = {'Fig3E_percell', T3};

    % ------------------------------------------------- Fig4 / Fig5 populations
    % any-intensity membership: within each manipulation, a cell is in the D/M
    % population if ANY of its recordings is G_type==1, in NL if ANY is ==2;
    % per-cell values average over that population's own rows for the cell.
    for fig = [4 5]
        pc = table(); po = table();
        for cls = ["D/M" "NL"]
            gwant = 1 + (cls == "NL");
            obs = find(sel & G == gwant);
            Rp = U.reducer(D, obs, 'mean'); rp = U.redIdx(Rp);
            dfrC  = U.redVec(Rp, dfr(obs));
            base = table(uu(rp), pk(rp), manip(rp), repmat(cls,numel(rp),1), ...
                dfrC, accumn(Rp, obs), 'VariableNames', ...
                {'UnitID','Penetration','Manipulation','Population', ...
                 'dFr_pct_mean','nIntensities'});
            baseO = table(uu(obs), pk(obs), manip(obs), repmat(cls,numel(obs),1), ...
                dfr(obs), magGroup(dfr(obs)), 'VariableNames', ...
                {'UnitID','Penetration','Manipulation','Population','dFr_pct', ...
                 'MagnitudeGroup'});
            if fig == 4
                base.dHBW_deg    = U.redVec(Rp, hbwL(obs) - hbwC(obs));
                base.HBW_control = U.redVec(Rp, hbwC(obs));
                base.HBW_laser   = U.redVec(Rp, hbwL(obs));
                baseO.dHBW_deg    = hbwL(obs) - hbwC(obs);
                baseO.HBW_control = hbwC(obs);  baseO.HBW_laser = hbwL(obs);
            else
                base.dOSI  = U.redVec(Rp, osiL(obs) - osiC(obs));
                base.dCV   = U.redVec(Rp, cvL(obs) - cvC(obs));
                base.OSI_control = U.redVec(Rp, osiC(obs)); base.OSI_laser = U.redVec(Rp, osiL(obs));
                base.CV_control  = U.redVec(Rp, cvC(obs));  base.CV_laser  = U.redVec(Rp, cvL(obs));
                baseO.dOSI = osiL(obs) - osiC(obs);  baseO.dCV = cvL(obs) - cvC(obs);
            end
            pc = [pc; base]; po = [po; baseO];
        end
        sheets(end+1,:) = {sprintf('Fig%d_percell', fig), pc};
        sheets(end+1,:) = {sprintf('Fig%d_perobs',  fig), po};
    end

    % ------------------------------------------------------------ Fig6KL_perobs
    obs = find(sel & (G == 1 | G == 2));
    cls6 = strings(numel(obs),1); cls6(G(obs)==1) = "D/M"; cls6(G(obs)==2) = "NL";
    T6 = table(uu(obs), pk(obs), manip(obs), cls6, dfr(obs), th(obs), bet(obs), ...
        'VariableNames', {'UnitID','Penetration','Manipulation','Class', ...
                          'dFr_pct','ExpM_theta','ExpM_beta'});
    sheets(end+1,:) = {'Fig6KL_perobs', T6};

    % --------------------------- Fig 7 / Supp Fig 6: model-simulated metrics
    % The app stores, per recording, the tuning metrics of the MODEL-simulated
    % laser curves (ExpM_* = I/O model -> Fig. 7; LTM_* = threshold-linear ->
    % Supplementary Fig. 6), computed by the same alignTunings pipeline as the
    % empirical metrics.
    obs = find(sel & (G == 1 | G == 2));
    cls7 = strings(numel(obs),1); cls7(G(obs)==1) = "D/M"; cls7(G(obs)==2) = "NL";
    for mdl = {{'ExpM','Fig7_perobs'}, {'LTM','SuppFig6_perobs'}}
        pre = mdl{1}{1};
        hC = U.colv(D,[pre '_HBW_NL']); hL = U.colv(D,[pre '_HBW_L']);
        oC = U.colv(D,[pre '_OSI_NL']); oL = U.colv(D,[pre '_OSI_L']);
        cC = U.colv(D,[pre '_CV_NL']);  cL = U.colv(D,[pre '_CV_L']);
        Tm = table(uu(obs), pk(obs), manip(obs), cls7, dfr(obs), ...
            hC(obs), hL(obs), hL(obs)-hC(obs), ...
            oC(obs), oL(obs), oL(obs)-oC(obs), ...
            cC(obs), cL(obs), cL(obs)-cC(obs), ...
            'VariableNames', {'UnitID','Penetration','Manipulation','Class','dFr_pct', ...
            'simHBW_control','simHBW_laser','sim_dHBW_deg', ...
            'simOSI_control','simOSI_laser','sim_dOSI', ...
            'simCV_control','simCV_laser','sim_dCV'});
        sheets(end+1,:) = {mdl{1}{2}, Tm};
    end

    % -------------------------------------------------------------- GoF_percell
    % One row per (cell x ANY-INTENSITY class), matching the text's model
    % comparison: R^2 averaged across the cell's recordings WITHIN that class
    % (the Figs. 4-5 populations, so a class-straddling cell has one row per
    % class). signrank(ExpM_R2, LTM_R2) per class reproduces the manuscript's
    % per-cell values exactly (NL P = 4.0e-20, n = 309; D/M P = 0.0029,
    % n = 186).
    cls2 = ["D/M" "NL"];
    Tg = table();
    for q = [1 2]
        obs = find(sel & (G == q) & isfinite(er2(:)) & isfinite(lr2(:)));
        Rg = U.reducer(D, obs, 'mean'); rg = U.redIdx(Rg);
        Tq = table(uu(rg), pk(rg), manip(rg), repmat(cls2(q), numel(rg), 1), ...
            U.redVec(Rg, er2(obs)), U.redVec(Rg, lr2(obs)), accumn(Rg, obs), ...
            'VariableNames', {'UnitID','Penetration','Manipulation','Class', ...
                              'ExpM_R2','LTM_R2','nIntensities'});
        Tg = [Tg; Tq]; %#ok<AGROW>
    end
    sheets(end+1,:) = {'GoF_percell', Tg};

    % ------------------------------------------------- panel-statistics sheets
    sheets(end+1,:) = {'Fig4_stats', i_figStats(i_getsheet(sheets,'Fig4_percell'), ...
                                               i_getsheet(sheets,'Fig4_perobs'), {'dHBW_deg'})};
    sheets(end+1,:) = {'Fig5_stats', i_figStats(i_getsheet(sheets,'Fig5_percell'), ...
                                               i_getsheet(sheets,'Fig5_perobs'), {'dOSI','dCV'})};
    E3 = i_getsheet(sheets,'Fig3E_percell');
    S3 = table('Size',[0 10],'VariableTypes',{'string','string','double','double','double', ...
        'double','double','double','double','string'},'VariableNames', ...
        {'Metric','Manipulation','NL_mean','NL_sem','NL_nCells','DM_mean','DM_sem', ...
         'DM_nCells','P','Test'});
    for met = {{'OSI','OSI_control'},{'CV','CV_control'},{'HBW','HBW_control_deg'}}
        for mv = ["PVA" "PVI"]
            a = E3.(met{1}{2})(E3.Class == "NL"  & E3.Manipulation == mv);
            b = E3.(met{1}{2})(E3.Class == "D/M" & E3.Manipulation == mv);
            a = a(isfinite(a)); b = b(isfinite(b));
            S3(end+1,:) = {string(met{1}{1}), mv, mean(a), std(a)/sqrt(numel(a)), numel(a), ...
                mean(b), std(b)/sqrt(numel(b)), numel(b), ranksum(a,b), ...
                "Wilcoxon rank-sum on per-cell values"};
        end
    end
    sheets(end+1,:) = {'Fig3E_stats', S3};

    % goodness-of-fit statistics PER CELL -- the reporting convention of the
    % text: one value per cell, averaged across its recordings within the
    % class (any-intensity classes, the Figs. 4-5 populations). The unlabeled
    % mean/sem/median/Pct/P columns are these per-cell statistics (what the
    % Results quote); the *_obs columns keep the per-observation aggregates
    % alongside for transparency.
    SG = table('Size',[0 16],'VariableTypes',{'string','string','double','double', ...
        'double','double','double','double','double','double','double','double', ...
        'double','double','double','double'},'VariableNames', ...
        {'Class','Manipulation','N_cells','N_obs','ExpM_mean','ExpM_sem','LTM_mean', ...
         'LTM_sem','ExpM_median','LTM_median','PctCells_ExpM_better','P_signrank', ...
         'ExpM_mean_obs','LTM_mean_obs','PctObs_ExpM_better','P_signrank_obs'});
    finR = isfinite(er2(:)) & isfinite(lr2(:));
    for cls = ["D/M" "NL"]
        gwant = 1 + (cls == "NL");
        for mv = ["all" "PVA" "PVI"]
            m = sel & (G == gwant) & finR;
            if mv ~= "all", m = m & (manip == mv); end
            o = find(m);
            if isempty(o), continue; end
            a = er2(o); b = lr2(o);
            Rg2 = U.reducer(D, o, 'mean');
            ac = U.redVec(Rg2, a); bc = U.redVec(Rg2, b);
            SG(end+1,:) = {cls, mv, numel(ac), numel(o), ...
                mean(ac), std(ac)/sqrt(numel(ac)), mean(bc), std(bc)/sqrt(numel(bc)), ...
                median(ac), median(bc), 100*mean(ac > bc), signrank(ac,bc), ...
                mean(a), mean(b), 100*mean(a > b), signrank(a,b)};
        end
    end
    sheets(end+1,:) = {'GoF_stats', SG};

    % ------------------------------------------------------------ Tables 1 & 2
    try, sheets(end+1,:) = {'Table1', analysis.stats.table1(D)}; catch e, warning('Table1: %s', e.message); end
    try, sheets(end+1,:) = {'Table2', analysis.stats.fig2Table(D)}; catch e, warning('Table2: %s', e.message); end

    % ------------------------------------------------------------------- write
    % The *_perobs sheets (one row per unit-intensity recording) are always
    % computed -- the *_stats sheets above are derived from them -- but they are
    % written to the workbook only with 'perObs', true: their repeated UnitID
    % rows would let a reader count each cell's recordings.
    perObsNames = {'Fig4_perobs','Fig5_perobs','Fig6KL_perobs','Fig7_perobs','SuppFig6_perobs'};
    isObs = ismember(sheets(:,1), perObsNames);
    perObsSheets = sheets(isObs, :);
    if ~wantObs
        sheets = sheets(~isObs, :);
    end
    if ~wantN
        for s = 1:size(sheets,1)
            Ts = sheets{s,2};
            if ismember('nIntensities', Ts.Properties.VariableNames)
                sheets{s,2} = removevars(Ts, 'nIntensities');
            end
        end
    end
    rd = table(string({}), string({}), 'VariableNames', {'Sheet','Contents'});
    desc = containers.Map( ...
      {'Fig2_percell','Fig3B_counts','Fig3D_laminar','Fig3E_percell', ...
       'Fig4_percell','Fig4_perobs','Fig5_percell','Fig5_perobs', ...
       'Fig6KL_perobs','GoF_percell','Table1','Table2','Fig7_perobs','SuppFig6_perobs', ...
       'Fig4_stats','Fig5_stats','Fig3E_stats','GoF_stats'}, ...
      {'Per-cell tuning metrics by layer & manipulation (Fig. 2D-I box plots and pairwise scatters); values averaged across the recordings in the cell''s dominant layer (as in Tables 1-2)', ...
       'Fig. 3B: cell counts per class (majority rule; Mix belongs to neither NL nor D/M)', ...
       'Fig. 3D: laminar prevalence of NL vs D/M cells', ...
       'Fig. 3E: per-cell metrics for the NL and D/M classes; values averaged across all the cell''s recordings', ...
       'Fig. 4: per-cell dHBW vs dFr, any-intensity populations; values averaged across the cell''s recordings within that population', ...
       'Fig. 4: the same at unit-intensity resolution (one row per recording), with magnitude group (L/M/H/XH)', ...
       'Fig. 5: per-cell dOSI and dCV vs dFr; values averaged across the cell''s recordings within that population', ...
       'Fig. 5: the same at unit-intensity resolution', ...
       'Fig. 6K,L: I/O-model parameters (theta, beta) vs dFr per recording', ...
       'Model comparison: ExpM vs LTM goodness-of-fit R^2 per cell, any-intensity classes (one row per cell x class; values averaged across the cell''s recordings within that class, as quoted in the text)', ...
       'Manuscript Table 1 (single-sourced from the app)', ...
       'Manuscript Table 2 (single-sourced from the app)', ...
       'Fig. 7: I/O-model-simulated tuning metrics per recording (vs the empirical dFr)', ...
       'Supp. Fig. 6: TLM-simulated tuning metrics per recording', ...
       'Fig. 4 panel statistics: per-cell regressions and within-magnitude-group comparisons', ...
       'Fig. 5 panel statistics: per-cell regressions and within-magnitude-group comparisons', ...
       'Fig. 3E statistics: NL vs D/M rank-sums on per-cell values', ...
       'Model goodness-of-fit statistics per cell (the text''s reporting convention: one value per cell averaged across its recordings within the class; any-intensity classes), with per-observation aggregates in the *_obs columns'});
    for s = 1:size(sheets,1)
        nm = sheets{s,1};
        if isKey(desc, nm), dd = desc(nm); else, dd = ''; end
        rd = [rd; {string(nm), string(dd)}];
    end
    writetable(rd, outFile, 'Sheet', 'ReadMe');
    for s = 1:size(sheets,1)
        writetable(sheets{s,2}, outFile, 'Sheet', sheets{s,1});
        fprintf('  sheet %-14s %5d rows x %d cols\n', sheets{s,1}, height(sheets{s,2}), width(sheets{s,2}));
    end
    fprintf('wrote %s\n', outFile);
    % out.sheets = what was written; out.perObs = the per-recording tables,
    % always carried here (whether written or not) so checks can use them.
    out = struct('file', outFile, 'sheets', {sheets}, 'perObs', {perObsSheets});
end

% ------------------------------------------------------------------------- %
function T = i_getsheet(sheets, name)
    T = sheets{strcmp(sheets(:,1), name), 2};
end

function S = i_figStats(pc, po, metrics)
%I_FIGSTATS  Per-cell regression + within-magnitude-group stats for Figs. 4/5.
    S = table('Size',[0 11],'VariableTypes',{'string','string','string','string', ...
        'string','double','double','double','double','double','double'}, ...
        'VariableNames', {'Population','Manipulation','Metric','Analysis','Group', ...
        'N_cells','N_obs','Value','SEM','r','P'});
    for cls = ["D/M" "NL"]
        for mv = ["PVA" "PVI"]
            mc = pc.Population == cls & pc.Manipulation == mv;
            for met = metrics
                x = pc.dFr_pct_mean(mc); y = pc.(met{1})(mc);
                ok = isfinite(x) & isfinite(y);
                [r, p] = corr(x(ok), y(ok));
                S(end+1,:) = {cls, mv, string(met{1}), "regression vs dFr (per cell)", ...
                    "", sum(ok), NaN, NaN, NaN, r, p}; %#ok<*AGROW>
                mo = po.Population == cls & po.Manipulation == mv;
                for gv = ["L" "M" "H" "XH"]
                    mg = mo & po.MagnitudeGroup == gv;
                    if ~any(mg), continue; end
                    u = unique(po.UnitID(mg));
                    pv = nan(numel(u),1);
                    for j = 1:numel(u)
                        pv(j) = mean(po.(met{1})(mg & po.UnitID == u(j)), 'omitnan');
                    end
                    pv = pv(isfinite(pv));
                    if isempty(pv), continue; end
                    S(end+1,:) = {cls, mv, string(met{1}), ...
                        "within-group change (per cell, signrank)", gv, ...
                        numel(pv), sum(mg), mean(pv), std(pv)/sqrt(numel(pv)), ...
                        NaN, signrank(pv)};
                end
            end
        end
    end
end

function n = accumn(R, ~)
%ACCUMN  observations per reduced cell (recordings averaged into each row).
    if isempty(R.idx), n = []; return; end
    n = accumarray(R.g, 1);                 % same stable-unique order as redVec
end

function g = magGroup(dfrPct)
%MAGGROUP  Fig. 4B magnitude bins on the per-cell mean |dFr|%.
    a = abs(dfrPct(:));
    g = strings(numel(a),1);
    g(a <= 33)            = "L";
    g(a > 33  & a <= 66)  = "M";
    g(a > 66  & a <= 100) = "H";
    g(a > 100)            = "XH";
end
