classdef Selectivity05Tab < viz.PlotTab
%SELECTIVITY05TAB  Controls for Visualizer_01's f05 window (selectivity + gain);
%   the actual figure opens in its OWN maximized uifigure, built with the literal
%   old pixel positions, fonts (11 pt) and colors so it is 1:1 with the old f05.
%
%   The TAB shows only the controls; the global filter panel is in the toolbar.
%   Panels are placed in PIXELS at the exact old monitor fractions (old fig spans
%   [0 .03 1 .95] of screen, y/height /0.95), recomputed on resize.
%
%   Reproduces the old F2_5B_3 f05 window (20 panels + 3 floating labels):
%     LEFT  s5{1..4} : gain parameters vs the firing-rate input (ExpM_dFR).
%                      beta  = ExpM_exponent, V0 = ExpM_theta. PVI (s5{1,2}) and
%                      PVE (s5{3,4}); per panel the Multiplicative (G_type 1, dark)
%                      and MXH (G_type 2, Cyellow) classes are overlaid, each with
%                      its regression (exp for beta, linear for V0) + s/r/p text.
%     MID-L s6{3,4}  : goodness-of-fit R^2 distributions, ExpM (black) vs LTM (red),
%                      for E (s6{3}) and I (s6{4}). signrank marker. A THIRD panel
%                      (s6Ax{3}, below them) shows the same comparison with E+I
%                      POOLED (no negative-R^2 clip); with group ORI_NON_PV_NL or
%                      _MD it reproduces the manuscript's per-class ExpM-vs-LTM
%                      comparison. All three carry an ExpM/LTM color legend.
%     MID-R s7{1..4} : multiplicative I/O transfer F(x) = exp(beta*x - offset) =
%                      exp(beta*(x-theta)) (old F2_5B_3 formula, Lambda=1), drawn at
%                      a LOW-input (dFR=0) and HIGH-input (dFR=-.8) operating point
%                      read off the s5 regressions. PVI/PVE x Multiplicative/MXH.
%     RIGHT ID{1..8} : measured CV / OSI / HBW / DSI control-vs-laser distribution
%                      histograms; PVE (laser green [0 1 .2]) in the right column,
%                      PVI (laser blue [0 .3 1]) in the left column; control black.
%                      Medians ('v') + signrank marker per panel.
%     BOTTOM I2a1/2  : control(x)-vs-laser(y) selectivity scatter for the dropdown
%                      index, colored by delta firing rate (green-white-blue), with
%                      the identity line. I2a1 = PVI, I2a2 = PVE.
%     LABELS U1{1..3}: 'Delta Firing Rate (%)', 'Normalized Firing Rate' (rot 90),
%                      'Input (\gamma.V)'.
%
%   DATA: gain panels map to the exponential-model fields in D (beta=ExpM_exponent,
%   V0=ExpM_theta, x=ExpM_dFR, F(x) uses ExpM_exponent/ExpM_offset). The old
%   I_ext_g/I_inh_g effect-category split (g2/g3) maps to the gain class G_type
%   1 (Multiplicative) / 2 (MXH). ID/I2a use the CALCULATED selectivity metrics
%   already in D: OSI=fitOSI, CV=fitCV, HBW=fitHBW, DSI=DSiL/DSiNL.
%
%   CONTROLS: unit group (TuningG), scatter index (I2a), repeated-obs handling,
%   and Class grouping (NL / D/M): 'Any-intensity populations' keeps G_type's
%   per-observation labels (the Figs. 4-5 populations; a class-straddling neuron
%   contributes to both classes), 'Majority-rule partition' resolves one class
%   per neuron (the Fig. 3 partition; Mix joins neither). The choice drives the
%   _MD/_NL/_U group masks, the s5 gain classes, and the stats report.
%   The old f05 applied NO TuningG filter and no dedup; choose group=ALL_UNITS +
%   repeated-obs=All + Any-intensity to reproduce the old population exactly.
%
%   See also: analysis.tuningGroupMask, viz.plots.V01util, viz.plots.Stability07Tab

    properties
        groupDD; indexDD; repDD; partDD; statusLbl; infoLabel
        PlotFig
        s5Ax = {}            % 1x4: PVI-beta, PVI-V0, PVE-beta, PVE-V0
        s6Ax = {}            % 1x2: E, I goodness-of-fit
        s7Ax = {}            % 1x4: PVI-Mlt, PVI-MXH, PVE-Mlt, PVE-MXH I/O
        idAx = {}            % 1x8: ID{1..4}=PVE CV/OSI/HBW/DSI, ID{5..8}=PVI CV/OSI/HBW/DSI
        i2Ax = {}            % 1x2: I2a1 (PVI), I2a2 (PVE)
        u1Lbl = {}           % 1x3 floating axis labels (dFr-x / norm-FR-y / input-x), retuned per paper-style
        LayoutSpec = {}
        LastD = []; LastMask = []
        SelectedUnit = NaN
    end

    properties (Constant)
        GROUPS = {'ALL_UNITS','NO_ORI_ON_PV','NO_ORI_NO_PV','ORI_ON_PV','ORI_NON_PV','ORI_NON_PV_MD','ORI_NON_PV_NL','ORI_NON_PV_U','OUTLIER'};
        REP_ITEMS = {'All (match old code)','First per neuron','Max laser power', ...
                     'Mean per neuron','Mixed-effects (stats)'};
        REP_DATA  = {'all','first','maxpow','mean','lme'};
        PART_ITEMS = {'Any-intensity populations','Majority-rule partition'};
        PART_DATA  = {'any','majority'};
        IDX_NAMES = {'OSI','CV','HBW','DSI'};
        CYELLOW      = [253 219 85]/255;
        CYELLOW_DARK = ([253 219 85]-70)/255;
        COL_MLT  = [.1 .1 .1];           % s5 Multiplicative (G_type 1) = colorsL{2}
        GREEN = [0 1 .2];                % PVE laser
        BLUE  = [0 .3 1];                % PVI laser
        BLACK = [0 0 0];                 % control
        GAIN_X = -3:.01:1;               % s7 input axis
        LAMBDA = 1;
        X1X2 = [-.8 0];                  % s7 high/low operating points
        FONT = 11; LW = 1; SZ = 16.5;    % fonts=11, LWidth=1, sz=fonts*1.5
    end

    methods
        function obj = Selectivity05Tab()
            obj@viz.PlotTab('Selectivity (V05)');
        end

        % --------------------------------------------------------------- %
        function buildControls(obj, parent)
            g = uigridlayout(parent, [14 1]);
            g.RowHeight = repmat({'fit'}, 1, 14); g.RowHeight{end} = '1x';
            g.RowSpacing = 4; g.Padding = [8 8 8 8];
            uilabel(g, 'Text', 'Unit group (TuningG)');
            obj.groupDD = uidropdown(g, 'Items', obj.GROUPS, 'Value', 'ORI_NON_PV', ...
                'ValueChangedFcn', @(s,e) obj.requestRefresh());
            uilabel(g, 'Text', 'Scatter index (I2a)');
            obj.indexDD = uidropdown(g, 'Items', obj.IDX_NAMES, 'Value', 'HBW', ...
                'ValueChangedFcn', @(s,e) obj.requestRefresh());
            uilabel(g, 'Text', 'Repeated obs (per neuron)');
            obj.repDD = uidropdown(g, 'Items', obj.REP_ITEMS, 'ItemsData', obj.REP_DATA, ...
                'Value', 'all', 'ValueChangedFcn', @(s,e) obj.requestRefresh());
            uilabel(g, 'Text', 'Class grouping (NL / D/M)');
            obj.partDD = uidropdown(g, 'Items', obj.PART_ITEMS, 'ItemsData', obj.PART_DATA, ...
                'Value', 'any', 'ValueChangedFcn', @(s,e) obj.requestRefresh(), ...
                'Tooltip', sprintf(['How NL/D-M class membership is resolved (the _MD/_NL/_U\n' ...
                'groups, the s5 gain classes, and the stats report):\n' ...
                '  Any-intensity: per-observation G_type labels -- a neuron that showed\n' ...
                '    both effects contributes to BOTH classes (Figs. 4-5 populations).\n' ...
                '  Majority-rule: one class per neuron by majority vote; Mix joins\n' ...
                '    neither class (the Fig. 3 partition).']));
            uilabel(g, 'Text', '');
            uibutton(g, 'Text', 'Open figure window', 'ButtonPushedFcn', @(s,e) obj.openFigure());
            obj.addReportButton(g);
            obj.statusLbl = uilabel(g, 'Text', '', 'WordWrap', 'on', 'VerticalAlignment','top');
            obj.infoLabel = uilabel(g, 'Text', '', 'WordWrap', 'on', 'VerticalAlignment','top');
            obj.addInspectCheckbox(g);
            obj.addDataSelectors(g);
        end

        function buildView(obj, parent)
            gg = obj.buildReportInstr(parent);
            uilabel(gg, 'Text', sprintf(['The Visualizer-01 "Selectivity" (f05) window opens in its ' ...
                'own maximized window (1:1 with the old figure).\n\nUse the controls on the left ' ...
                '(and the toolbar Filters) \x2014 the window refreshes live.']), ...
                'HorizontalAlignment','center', 'WordWrap','on', 'FontSize', 13);
        end

        % --------------------------------------------------------------- %
        function update(obj, D, mask)
            obj.LastD = D; obj.LastMask = mask;
            % NOTE: the figure window opens ONLY when the user clicks "Open figure
            % window" (obj.openFigure); selecting/refreshing the tab never auto-opens.
            if ~isempty(obj.PlotFig) && isvalid(obj.PlotFig), obj.drawFigure(); end
            if obj.ShowReport, obj.refreshReport(); end
            obj.refreshStatus();
        end

        function rs = reportSpec(obj)
            if isempty(obj.LastD), rs = []; return; end
            mask = obj.LastMask; if isempty(mask), mask = true(viz.plots.V01util.nU(obj.LastD),1); end
            state = struct('group', obj.groupDD.Value, 'mask', mask(:), 'index', obj.indexDD.Value, ...
                           'partition', obj.partDD.Value);
            hdr = sprintf(['Visualizer-01 selectivity (f05) \x2014 group %s, scatter index %s, ' ...
                'class grouping %s.  ExpM-vs-LTM goodness-of-fit (E, I, and E+I pooled), ' ...
                'Laser-vs-Control CV/OSI/HBW/DSI distributions, the control-vs-laser scatters, ' ...
                'PVI-vs-PVE no-laser OSI, and the gain dose-response (model-based) split PER ' ...
                'GAIN CLASS, as the s5 panels fit them.'], ...
                obj.groupDD.Value, obj.indexDD.Value, obj.partDD.Value);
            rs = struct('figKey','f05', 'state',state, 'D',obj.LastD, 'header',hdr);
        end

        function openFigure(obj)
            if ~isempty(obj.PlotFig) && isvalid(obj.PlotFig)
                figure(obj.PlotFig); obj.drawFigure(); obj.refreshStatus(); return;
            end
            ss = get(0,'screensize'); Mx = ss(3); My = ss(4);
            obj.PlotFig = uifigure('Name','Visualizer 01 - Selectivity (f05)', 'Color','w', ...
                'Position', [0, round(.03*My), Mx, round(.95*My)]);
            obj.PlotFig.CloseRequestFcn = @(s,e) delete(s);
            obj.LayoutSpec = {};
            obj.createPanels();
            try, obj.PlotFig.AutoResizeChildren = 'off'; catch, end %#ok<CTCH>
            obj.PlotFig.SizeChangedFcn = @(s,e) obj.relayout();
            obj.relayout(); obj.drawFigure(); obj.refreshStatus();
        end

        function s = getControlState(obj)
            s = struct('group', obj.groupDD.Value, 'index', obj.indexDD.Value, ...
                       'rep', obj.repDD.Value, 'part', obj.partDD.Value);
        end
        function setControlState(obj, s)
            if isfield(s,'group'), obj.setCtrl(obj.groupDD, s.group); end
            if isfield(s,'index'), obj.setCtrl(obj.indexDD, s.index); end
            if isfield(s,'rep'),   obj.setCtrl(obj.repDD,   s.rep);   end
            if isfield(s,'part'),  obj.setCtrl(obj.partDD,  s.part);  end
        end
    end

    % =================================================================== %
    methods (Access = private)
        function refreshStatus(obj)
            isOpen = ~isempty(obj.PlotFig) && isvalid(obj.PlotFig);
            if isOpen, obj.statusLbl.Text = 'window: open'; else, obj.statusLbl.Text = 'window: closed (click Open)'; end
        end

        % ---- panel construction --------------------------------------- %
        function createPanels(obj)
            % s5 gain params (left column): [x y w h]; odd i -> x=.015 w=.17, even -> x=.01 w=.175
            obj.s5Ax = cell(1,4);
            xw = {[.015 .17],[.01 .175],[.015 .17],[.01 .175]};
            for i = 1:4
                obj.s5Ax{i} = obj.addAx(xw{i}(1), .10+.20*(i-1), xw{i}(2), .20);
            end
            % s6 goodness of fit (x=.28): {1}=E at y=.5, {2}=I at y=.7,
            % {3}=E+I pooled at y=.3 (new; same drawGof, both conditions)
            obj.s6Ax = {obj.addAx(.28,.50,.15,.20), obj.addAx(.28,.70,.15,.20), ...
                        obj.addAx(.28,.30,.15,.20)};
            % s7 I/O transfer (x=.48): 1 PVI-Mlt .1, 2 PVI-MXH .3, 3 PVE-Mlt .5, 4 PVE-MXH .7
            obj.s7Ax = cell(1,4);
            for i = 1:4, obj.s7Ax{i} = obj.addAx(.48, .10+.20*(i-1), .15, .20); end
            % ID distribution hists: ID{1..4} PVE at x=.83, ID{5..8} PVI at x=.65; y=.75-(k-1)*.14
            obj.idAx = cell(1,8);
            for k = 1:4
                obj.idAx{k}   = obj.addAx(.83, .75-(k-1)*.14, .12, .14);   % PVE CV/OSI/HBW/DSI
                obj.idAx{k+4} = obj.addAx(.65, .75-(k-1)*.14, .12, .14);   % PVI CV/OSI/HBW/DSI
            end
            % I2a selectivity scatters: I2a1 PVI x=.83, I2a2 PVE x=.65, y=.02
            obj.i2Ax = {obj.addAx(.83,.02,.15,.17), obj.addAx(.65,.02,.15,.17)};
            obj.createLabels();
        end

        function ax = addAx(obj, fx, fy, fw, fh)
            ax = uiaxes(obj.PlotFig); ax.Units = 'pixels'; ax.FontUnits = 'points';
            ax.FontSize = obj.FONT; ax.LineWidth = obj.LW; ax.XTickLabelRotation = 0;
            obj.LayoutSpec{end+1} = {ax, [fx fy fw fh]};
        end
        function th = addLabel(obj, fx, fy, fw, fh, txt, rot)
            ax = uiaxes(obj.PlotFig); ax.Units = 'pixels'; ax.Visible = 'off';
            th = text(ax, 0, 0, txt, 'Color','k', 'Rotation',rot, 'FontUnits','points', 'FontSize',obj.FONT);
            obj.LayoutSpec{end+1} = {ax, [fx fy fw fh]};
        end
        function createLabels(obj)
            obj.u1Lbl = cell(1,3);
            obj.u1Lbl{1} = obj.addLabel(.05, .07, .04, .20, 'Delta Firing Rate (%)', 0);     % U1{1} s5 x
            obj.u1Lbl{2} = obj.addLabel(.46, .45, .04, .20, 'Normalized Firing Rate', 90);   % U1{2} s7 y
            obj.u1Lbl{3} = obj.addLabel(.53, .07, .04, .20, 'Input (\gamma.V)', 0);          % U1{3} s7 x
        end
        function retuneLabels(obj)
            %RETUNELABELS  Floating axis labels -> paper Fig 7 wording in paper mode.
            if numel(obj.u1Lbl) < 3, return; end
            if viz.paperStyle(), t = {'\DeltaFr (%)', 'Normalized firing rate', 'Membrane potential (\itu\rm) (\gamma.V)'};
            else,                t = {'Delta Firing Rate (%)', 'Normalized Firing Rate', 'Input (\gamma.V)'}; end
            for k = 1:3
                if ~isempty(obj.u1Lbl{k}) && isvalid(obj.u1Lbl{k}), obj.u1Lbl{k}.String = t{k}; end
            end
        end
        function relayout(obj)
            if isempty(obj.PlotFig) || ~isvalid(obj.PlotFig), return; end
            pos = obj.PlotFig.Position; W = pos(3); H = pos(4);
            if W < 30 || H < 30, return; end
            for k = 1:numel(obj.LayoutSpec)
                h = obj.LayoutSpec{k}{1}; fr = obj.LayoutSpec{k}{2};
                if ~isvalid(h), continue; end
                try, h.Position = [fr(1)*W, (fr(2)/0.95)*H, max(2,fr(3)*W), max(2,(fr(4)/0.95)*H)]; catch, end %#ok<CTCH>
            end
        end

        % ---- main draw ------------------------------------------------ %
        function drawFigure(obj)
            D = obj.LastD; mask = obj.LastMask;
            if isempty(D) || isempty(obj.PlotFig) || ~isvalid(obj.PlotFig), return; end
            obj.relayout(); obj.clearAll(); obj.retuneLabels();

            try, grpMask = analysis.tuningGroupMask(D, obj.groupDD.Value, ...
                    'ClassGrouping', obj.partDD.Value);
            catch err, title(obj.s5Ax{1}, ['Group error: ' err.message]); return; end

            colv = @viz.plots.V01util.colv;
            isI  = viz.plots.V01util.isInhib(D);
            sel  = mask(:) & grpMask(:);
            mode = obj.repDD.Value;
            Re = viz.plots.V01util.reducer(D, find(sel & ~isI), mode); eRep = viz.plots.V01util.redIdx(Re);
            Ri = viz.plots.V01util.reducer(D, find(sel &  isI), mode); iRep = viz.plots.V01util.redIdx(Ri);

            % ===== s5 gain parameters + s7 I/O ============================
            expo = colv(D,'ExpM_exponent'); th = colv(D,'ExpM_theta');
            dfr  = colv(D,'ExpM_dFR');      G  = colv(D,'G_type');
            uuA  = colv(D,'U_unity');
            eObs = find(sel & ~isI); iObs = find(sel & isI);
            % Per-neuron modes ('mean'/'lme'): the panels get OBSERVATION rows and
            % collapse to one value per neuron internally, so 'mean' truly averages
            % (the reducer's 'mean' representative is the FIRST row).
            perCell = any(strcmp(mode, {'mean','lme'}));
            if perCell, eStat = eObs; iStat = iObs; else, eStat = eRep; iStat = iRep; end
            % Class grouping (partDD): 'majority' resolves G_type to each neuron's
            % majority class (Fig. 3 partition; Mix joins neither class, and no
            % neuron lands in both s5 classes); 'any' keeps the per-observation
            % labels (Figs. 4-5 populations: in per-neuron modes a class-straddling
            % neuron contributes one aggregated value to EACH class it showed).
            % 'any' + All reproduces the old f05 figure; 'majority' + Mean
            % reproduces the printed Fig. 6K,L "cells:" statistics.
            Gc = G;
            if strcmp(obj.partDD.Value, 'majority')
                Gc = viz.plots.V01util.classPerNeuron(G, uuA, [eObs; iObs]);
            end
            condReps = {iStat, eStat};               % cond 1 = PVI, 2 = PVE
            IE = cell(2,2,2);                        % {cond, class, param(1=beta,2=theta)} = [v@-.8 v@0]
            s5beta = {obj.s5Ax{1}, obj.s5Ax{3}};     % PVI-beta, PVE-beta
            s5v0   = {obj.s5Ax{2}, obj.s5Ax{4}};     % PVI-V0,   PVE-V0
            tags   = {'PVI','PVE'};
            for c = 1:2
                rp = condReps{c};
                [IE{c,1,1}, IE{c,2,1}] = obj.drawGainPanel(s5beta{c}, dfr(rp), expo(rp), Gc(rp), uuA(rp), mode, ...
                    true,  c, [tags{c} ' Gain (\beta)'], '\beta Value');
                [IE{c,1,2}, IE{c,2,2}] = obj.drawGainPanel(s5v0{c}, dfr(rp), th(rp), Gc(rp), uuA(rp), mode, ...
                    false, c, [tags{c} ' Gain V_0'], 'V_0 Value');
            end
            % s7{1}=PVI-Mlt, {2}=PVI-MXH, {3}=PVE-Mlt, {4}=PVE-MXH
            obj.drawIO(obj.s7Ax{1}, IE{1,1,1}, IE{1,1,2}, 1, 1, 'PVI Multiplicative I/O\it-F');
            obj.drawIO(obj.s7Ax{2}, IE{1,2,1}, IE{1,2,2}, 2, 1, 'PVI MXH I/O\it-F');
            obj.drawIO(obj.s7Ax{3}, IE{2,1,1}, IE{2,1,2}, 1, 2, 'PVE Multiplicative I/O\it-F');
            obj.drawIO(obj.s7Ax{4}, IE{2,2,1}, IE{2,2,2}, 2, 2, 'PVE MXH I/O\it-F');

            % ===== s6 goodness of fit (ExpM black vs LTM red) =============
            er2 = colv(D,'ExpM_R2'); lr2 = colv(D,'LTM_R2');
            uu  = colv(D,'U_unity');
            pk  = viz.plots.V01util.penKey(D);
            obj.drawGof(obj.s6Ax{1}, er2(eStat), lr2(eStat), uu(eStat), pk(eStat), true,  'Goodness of Fit E (ExpM vs LTM)');
            obj.drawGof(obj.s6Ax{2}, er2(iStat), lr2(iStat), uu(iStat), pk(iStat), false, 'Goodness of Fit I (ExpM vs LTM)');
            % E+I pooled (same panel, both conditions; no negative-R^2 clipping --
            % the E panel's clip is an old-code quirk, not applied here). With
            % group ORI_NON_PV_NL / _MD this reproduces the manuscript's per-class
            % model comparison (Results: NL P=4.0e-20, D/M P=0.0029 per cell,
            % any-intensity + Mean).
            allStat = [eStat(:); iStat(:)];
            obj.drawGof(obj.s6Ax{3}, er2(allStat), lr2(allStat), uu(allStat), pk(allStat), false, ...
                'Goodness of Fit E+I (ExpM vs LTM)');

            % ===== ID measured-index distribution histograms =============
            % PVE (green) right column, PVI (blue) left column. DSI bin width flows ID4 -> ID8.
            [osiE_L,osiE_NL] = obj.selIndex(D,'OSI'); [cvE_L,cvE_NL] = obj.selIndex(D,'CV');
            [hbwE_L,hbwE_NL] = obj.selIndex(D,'HBW'); [dsE_L,dsE_NL] = obj.selIndex(D,'DSI');
            cfgCV  = struct('bin','fixed','arg',0.05,'xl',[0 1], 'yl',[],    'xlab','CV',     'star',0.05);
            cfgOSI = struct('bin','half', 'arg',[],   'xl',[0 1], 'yl',[],    'xlab','OSI',    'star',0.05);
            cfgHBW = struct('bin','fixed','arg',2,    'xl',[0 60],'yl',[],    'xlab','Degrees','star',0.05);
            cfgDSI = struct('bin','nbins','arg',20,   'xl',[0 1], 'yl',[],    'xlab','DSI',    'star',0.80);
            obj.drawIDHist(obj.idAx{1}, cvE_L(eStat),  cvE_NL(eStat),  uu(eStat), pk(eStat), obj.GREEN, ' PVE CV distribution',  cfgCV);
            obj.drawIDHist(obj.idAx{2}, osiE_L(eStat), osiE_NL(eStat), uu(eStat), pk(eStat), obj.GREEN, ' PVE OSI distribution', cfgOSI);
            obj.drawIDHist(obj.idAx{3}, hbwE_L(eStat), hbwE_NL(eStat), uu(eStat), pk(eStat), obj.GREEN, 'PVE HBW distribution', cfgHBW);
            dsiBW = obj.drawIDHist(obj.idAx{4}, dsE_L(eStat), dsE_NL(eStat), uu(eStat), pk(eStat), obj.GREEN, 'PVE DSI distribution', cfgDSI);
            obj.drawIDHist(obj.idAx{5}, cvE_L(iStat),  cvE_NL(iStat),  uu(iStat), pk(iStat), obj.BLUE, ' PVI CV distribution',  cfgCV);
            cfgOSI_I = cfgOSI; cfgOSI_I.yl = [0 100];
            obj.drawIDHist(obj.idAx{6}, osiE_L(iStat), osiE_NL(iStat), uu(iStat), pk(iStat), obj.BLUE, ' PVI OSI distribution', cfgOSI_I);
            obj.drawIDHist(obj.idAx{7}, hbwE_L(iStat), hbwE_NL(iStat), uu(iStat), pk(iStat), obj.BLUE, 'PVI HBW distribution', cfgHBW);
            cfgDSI_I = cfgDSI; cfgDSI_I.bin = 'usebw'; cfgDSI_I.arg = dsiBW;
            obj.drawIDHist(obj.idAx{8}, dsE_L(iStat), dsE_NL(iStat), uu(iStat), pk(iStat), obj.BLUE, 'PVI DSI distribution', cfgDSI_I);
            obj.matchIDWidths();

            % ===== I2a control-vs-laser selectivity scatters =============
            idx = obj.indexDD.Value;
            [selL, selNL] = obj.selIndex(D, idx);
            dFrPct = 100 * colv(D,'Delta_Fr');
            obj.drawSel(obj.i2Ax{1}, selNL, selL, dFrPct, iStat, uu, mode, idx, 'PV inhibition');  % I2a1 = PVI
            obj.drawSel(obj.i2Ax{2}, selNL, selL, dFrPct, eStat, uu, mode, idx, 'PV excitation');  % I2a2 = PVE

            obj.infoLabel.Text = sprintf(['group %s   index %s   E=%d  I=%d   classes: %s\n' ...
                'gain: \\beta=ExpM\\_exponent, V0=ExpM\\_theta; GoF ExpM(black) vs LTM(red).\n' ...
                'ALL_UNITS + All + Any-intensity reproduces the old f05 population.'], ...
                obj.groupDD.Value, idx, numel(eRep), numel(iRep), obj.partDD.Value);
        end

        function clearAll(obj)
            grp = [obj.s5Ax(:); obj.s6Ax(:); obj.s7Ax(:); obj.idAx(:); obj.i2Ax(:)];
            for k = 1:numel(grp), if ~isempty(grp{k}) && isvalid(grp{k}), cla(grp{k}); end, end
        end

        % ---- s5 gain panel -------------------------------------------- %
        function [endMlt, endMXH] = drawGainPanel(obj, ax, x, y, G, neur, mode, isBeta, cond, ttl, ylab)
            %DRAWGAINPANEL  Overlay D/M (G_type1) + NL (G_type2) scatters of param y vs
            %   input x, each with its regression (exp for beta, linear for V0) + s/r/p
            %   text. Returns the regression value [@-.8  @0] per class (for the s7
            %   operating points). cond 1=PVI, 2=PVE. PAPER (Fig 7 A/B): gray (D/M) +
            %   yellow (NL) ring-edged ratio-sized dots, RED-dashed regression, per-class
            %   colored stats, PVA/PVI colored title, theta/beta y-label, D/M-NL legend.
            hold(ax,'on');
            paper = viz.paperStyle();
            yMax = 17*isBeta + 3*(~isBeta);          % beta ylim top 17, V0 top 3
            classes = {1, 2};
            if paper
                cols   = {[0.366 0.366 0.366], [0.911 0.899 0]};   % D/M gray, NL yellow (PDF-measured Fig 7)
                edgeCols = {'w', [.2 .2 .2]};                       % paper Fig 7 s5: WHITE ring on D/M gray, DARK ring on NL yellow (each ring contrasts its own fill)
                txtCol = {[0.33 0.33 0.33],    [0.62 0.61 0]};      % stats text: gray (D/M) / dark-yellow (NL)
                regCol = [0.922 0.132 0];                           % red-dashed regression (PDF-measured)
                sz0 = viz.plots.V01util.paperDotArea(ax);           % NL yellow dot dia ~3.3% of plot (scales with panel)
                szCls = {1.9*sz0, sz0};                             % paper Fig 7: D/M gray dots ~1.9x AREA (~1.38x dia) of NL yellow (PDF-measured)
            else
                cols = {obj.COL_MLT, obj.CYELLOW}; alphas = [.2 .4];
            end
            ends = {[NaN NaN],[NaN NaN]};
            for q = 1:2
                sub = (G == classes{q}) & isfinite(x) & isfinite(y);
                xc = x(sub); yc = y(sub);
                if any(strcmp(mode, {'mean','lme'}))     % one dot / fit point per neuron
                    nc = neur(sub);
                    xc = viz.plots.V01util.aggMean(xc, nc);
                    yc = viz.plots.V01util.aggMean(yc, nc);
                end
                if isempty(xc), continue; end
                if paper
                    scatter(ax, xc, yc, szCls{q}, 'MarkerFaceColor',cols{q}, 'MarkerEdgeColor',edgeCols{q}, 'LineWidth',0.75);   % per-class ring + size: D/M gray->white ring, ~1.9x area; NL yellow->dark ring (paper Fig 7)
                else
                    scatter(ax, xc, yc, 'MarkerEdgeColor','none', 'MarkerFaceColor',cols{q}, 'MarkerFaceAlpha', alphas(q));
                end
                try
                    if isBeta
                        m = yc < yMax;
                        mdl = fitnlm(xc(m), yc(m), @(b,xx) b(1).*exp(b(2).*xx), [1 -0.1]);
                    else
                        mdl = fitlm(xc, yc);
                    end
                    xes = (0:-.05:min(xc))';
                    ply = predict(mdl, xes);
                    if paper, plot(ax, xes, ply, '--', 'Color',regCol, 'LineWidth',1);
                    else,     h = plot(ax, xes, ply, 'k--', 'LineWidth', 1); h.Color(4) = 1; end
                    ev = predict(mdl, obj.X1X2(:));            % [@-.8 ; @0]
                    ends{q} = ev(:)';
                    R = corrcoef(xc, yc); rc = R(1,2);
                    slp = (ply(end)-ply(1)) / (xes(end)-xes(1));
                    pv = mdl.Coefficients.pValue(min(2,end));
                    if paper                                   % stats stacked at top-left, per-class color
                        text(ax, 0.02, 0.96-0.09*(q-1), sprintf('s = %.2f , r = %.2f, p = %.4f', slp, rc, pv), ...
                            'Units','normalized', 'Color',txtCol{q}, 'FontUnits','points', 'FontSize',obj.FONT-3, 'FontWeight','bold');
                    else
                        text(ax, -.1*mean(xes), -.1+2*mean(ply), sprintf('s = %.2f , r = %.2f, p = %.4f', slp, rc, pv), ...
                            'Color','k', 'FontUnits','points', 'FontSize',obj.FONT, 'FontWeight','bold');
                    end
                catch
                end
            end
            endMlt = ends{1}; endMXH = ends{2};
            ylim(ax, [-2 yMax]);
            xticks(ax, -1:.2:0); xticklabels(ax, string(100*(-1:.2:0)));
            if paper
                if cond == 2, title(ax, 'PVA', 'Color', viz.Colors.PVA); else, title(ax, 'PVI', 'Color', viz.Colors.PVI); end
                if isBeta, ylabel(ax, '\beta'); else, ylabel(ax, '\theta'); end
                if cond == 2 && ~isBeta                        % legend once (top panel, paper Fig 7 A)
                    text(ax, 0.55, 0.93, 'D/M', 'Units','normalized', 'Color',[0.366 0.366 0.366], 'FontWeight','bold', 'FontSize',obj.FONT-1);
                    text(ax, 0.78, 0.93, 'NL',  'Units','normalized', 'Color',[0.62 0.61 0],       'FontWeight','bold', 'FontSize',obj.FONT-1);
                end
            else
                title(ax, ttl); ylabel(ax, ylab);
            end
            hold(ax,'off');
        end

        % ---- s7 multiplicative I/O ------------------------------------ %
        function drawIO(obj, ax, betaEnd, thetaEnd, classIdx, cond, ttl)
            %DRAWIO  F(x) = Lambda*exp(beta*(x-theta)) at the LOW (dFR=0, control-like)
            %   and HIGH (dFR=-.8, manipulation) operating points from the s5 regressions.
            %   classIdx 1=Multiplicative(D/M) 2=MXH(NL); cond 1=PVI 2=PVE. PAPER (Fig 7
            %   C/D): control curve gray (D/M) / yellow (NL); manipulation curve green
            %   (PVA) / blue (PVI), with a Control / PVA-PVI legend.
            hold(ax,'on');
            gx = obj.GAIN_X; paper = viz.paperStyle();
            if paper
                if classIdx == 1, loCol = [.5 .5 .5]; else, loCol = obj.CYELLOW; end        % control: D/M gray / NL yellow
                if cond == 2, hiCol = viz.Colors.PVA; else, hiCol = viz.Colors.PVI; end     % manipulation: PVA green / PVI blue
            elseif classIdx == 1
                loCol = [.5 .5 .5 .7]; hiCol = [0 0 0 .7];
            else
                loCol = [obj.CYELLOW .7]; hiCol = [obj.CYELLOW_DARK .7];
            end
            if all(isfinite(betaEnd)) && all(isfinite(thetaEnd))
                bLo = betaEnd(2);  tLo = thetaEnd(2);   % @0   (low input)
                bHi = betaEnd(1);  tHi = thetaEnd(1);   % @-.8 (high input)
                yLo = obj.LAMBDA * exp(bLo * (gx - tLo));
                yHi = obj.LAMBDA * exp(bHi * (gx - tHi));
                plot(ax, gx, yLo, 'Color', loCol, 'LineWidth', 2);
                plot(ax, gx, yHi, 'Color', hiCol, 'LineWidth', 2);
            end
            xline(ax, 0, ':'); yline(ax, 1, ':');
            xlim(ax, [min(gx) max(gx)]); ylim(ax, [0 2]);
            if paper                                     % Control / PVA-PVI legend (paper Fig 7 C/D)
                if cond == 2, mt = 'PVA'; else, mt = 'PVI'; end
                text(ax, 0.03, 0.93, 'Control', 'Units','normalized', 'Color',loCol, 'FontWeight','bold', 'FontSize',obj.FONT-1);
                text(ax, 0.52, 0.93, mt,        'Units','normalized', 'Color',hiCol, 'FontWeight','bold', 'FontSize',obj.FONT-1);
                title(ax, '');
            else
                title(ax, ttl);
            end
            hold(ax,'off');
        end

        % ---- s6 goodness of fit --------------------------------------- %
        function drawGof(obj, ax, expR2, ltmR2, neur, pen, clipNeg, ttl)
            hold(ax,'on');
            a = expR2(:); b = ltmR2(:);                      % paired per unit (er2(reps), lr2(reps))
            neur = neur(:);                                  % U_unity aligned to a/b (same reps rows)
            if clipNeg, a(a<0) = 0; b(b<0) = 0; end          % old s6{3} (E) clips; s6{4} (I) does not
            mode = obj.repDD.Value;
            aD = a; bD = b;
            if any(strcmp(mode, {'mean','lme'}))             % display one value per neuron
                aD = viz.plots.V01util.aggMean(a, neur); bD = viz.plots.V01util.aggMean(b, neur);
            end
            af = aD(isfinite(aD)); bf = bD(isfinite(bD));    % per-side finite (histograms + medians)
            if ~isempty(af), histogram(ax, af, 'BinWidth',0.01, 'FaceColor',obj.BLACK, 'FaceAlpha',0.3); end
            if ~isempty(bf), histogram(ax, bf, 'BinWidth',0.01, 'FaceColor',[1 0 0],   'FaceAlpha',0.3); end
            title(ax, ttl); ylabel(ax,'Count'); xlabel(ax,'R-squared'); xlim(ax,[0.8 1]);
            % color legend: which histogram is which model (user request)
            text(ax, 0.03, 0.78, 'ExpM', 'Units','normalized', 'Color',obj.BLACK, ...
                'FontWeight','bold', 'FontUnits','points', 'FontSize',obj.FONT-2);
            text(ax, 0.03, 0.66, 'LTM', 'Units','normalized', 'Color',[1 0 0], ...
                'FontWeight','bold', 'FontUnits','points', 'FontSize',obj.FONT-2);
            ax.YLimMode = 'auto';                            % reset so Y re-fits on each group/filter change
            yl = ylim(ax); ylim(ax, [yl(1) 1.1*yl(2)]); yl = ylim(ax);   % old 1.1x headroom (X stays [0.8 1])
            if ~isempty(af), scatter(ax, median(af), 0.9*yl(2), 4*obj.SZ, obj.BLACK, 'v','filled','MarkerFaceAlpha',0.3); end
            if ~isempty(bf), scatter(ax, median(bf), 0.9*yl(2), 4*obj.SZ, [1 0 0],   'v','filled','MarkerFaceAlpha',0.3); end
            xl = xlim(ax);
            % paired Control-vs-Laser via shared helper (honors repeated-obs mode;
            % red star when mixed-effects significance differs from the All method)
            if strcmp(mode, 'mean')                          % signrank on the shown per-neuron means
                [p, isRed] = viz.plots.V01util.smPaired(aD, bD, [], 'all');
            else
                [p, isRed] = viz.plots.V01util.smPaired(a, b, neur, mode, pen);
            end
            viz.plots.V01util.drawSig(ax, 0.8*xl(2), 0.9*yl(2), p, isRed, 'left');
            hold(ax,'off');
        end

        % ---- ID measured-index histogram ------------------------------ %
        function bw = drawIDHist(obj, ax, lv, nlv, neur, pen, laserCol, ttl, cfg)
            %DRAWIDHIST  Control(black, =NL) vs laser(laserCol, =L) overlaid hist +
            %   medians ('v' at .9*ymax) + signrank marker. Returns the NL bin width.
            hold(ax,'on');
            neur = neur(:);                                      % U_unity aligned to lv/nlv (same reps rows)
            mode = obj.repDD.Value;
            lvD = lv(:); nlvD = nlv(:);
            if any(strcmp(mode, {'mean','lme'}))                 % display one value per neuron
                lvD = viz.plots.V01util.aggMean(lv, neur); nlvD = viz.plots.V01util.aggMean(nlv, neur);
            end
            a = lvD(isfinite(lvD)); b = nlvD(isfinite(nlvD));    % a=laser(L), b=control(NL)
            bw = NaN;
            % control (NL) first -> sets the reference bin width
            if ~isempty(b)
                switch cfg.bin
                    case 'fixed', H = histogram(ax, b, 'BinWidth',cfg.arg, 'FaceColor',obj.BLACK,'FaceAlpha',0.3);
                    case 'half',  H = histogram(ax, b, 'FaceColor',obj.BLACK,'FaceAlpha',0.3); H.BinWidth = H.BinWidth/2;
                    case 'nbins', H = histogram(ax, b, cfg.arg, 'FaceColor',obj.BLACK,'FaceAlpha',0.3);
                    case 'usebw', H = histogram(ax, b, 'BinWidth',cfg.arg, 'FaceColor',obj.BLACK,'FaceAlpha',0.3);
                end
                bw = H.BinWidth;
            end
            if ~isempty(a)
                if isfinite(bw), histogram(ax, a, 'BinWidth',bw, 'FaceColor',laserCol,'FaceAlpha',0.3);
                else,            histogram(ax, a, 'FaceColor',laserCol,'FaceAlpha',0.3); end
            end
            title(ax, ttl); ylabel(ax,'Count'); xlabel(ax, cfg.xlab);
            xlim(ax, cfg.xl); if ~isempty(cfg.yl), ylim(ax, cfg.yl); end
            yl = ylim(ax); xl = xlim(ax);
            if ~isempty(a), scatter(ax, median(a), 0.9*yl(2), 4*obj.SZ, laserCol, 'v','filled','MarkerFaceAlpha',0.3); end
            if ~isempty(b), scatter(ax, median(b), 0.9*yl(2), 4*obj.SZ, obj.BLACK, 'v','filled','MarkerFaceAlpha',0.3); end
            % paired Control-vs-Laser via shared helper (honors repeated-obs mode;
            % red star when mixed-effects significance differs from the All method)
            if strcmp(mode, 'mean')                              % signrank on the shown per-neuron means
                [p, isRed] = viz.plots.V01util.smPaired(lvD, nlvD, [], 'all');
            else
                [p, isRed] = viz.plots.V01util.smPaired(lv, nlv, neur, mode, pen);
            end
            viz.plots.V01util.drawSig(ax, cfg.star*xl(2), 0.9*yl(2), p, isRed, 'left');
            hold(ax,'off');
        end

        % equalize the DATA-area width of the 8 ID panels (old TightInset trick)
        function matchIDWidths(obj)
            if isempty(obj.PlotFig) || ~isvalid(obj.PlotFig), return; end
            inner = 0.08 * obj.PlotFig.Position(3);
            for k = 1:numel(obj.idAx)
                ax = obj.idAx{k}; if isempty(ax) || ~isvalid(ax), continue; end
                try
                    ti = ax.TightInset; p = ax.Position;
                    ax.Position = [p(1), p(2), inner + ti(1) + ti(3), p(4)];
                catch
                end
            end
        end

        % ---- I2a selectivity scatter ---------------------------------- %
        function drawSel(obj, ax, nlv, lv, dFrPct, reps, neur, mode, idx, condStr)
            hold(ax,'on');
            x = nlv(reps); y = lv(reps); c = dFrPct(reps);
            ok = isfinite(x) & isfinite(y); x=x(ok); y=y(ok); c=c(ok);
            pick = reps(ok);                                   % D-row behind each dot
            if any(strcmp(mode, {'mean','lme'}))               % one dot per neuron
                nc = neur(reps); nc = nc(ok);
                x = viz.plots.V01util.aggMean(x, nc);
                y = viz.plots.V01util.aggMean(y, nc);
                c = viz.plots.V01util.aggMean(c, nc);
                % aggMean groups by unique(...,'stable'), so the k-th dot is the
                % k-th neuron in first-appearance order; keep ONE row per neuron
                % in that same order or click/ring/highlight index the wrong unit
                % (they were still holding all the observation rows).
                [~, ia] = unique(nc, 'stable'); pick = pick(ia);
            end
            c(c > 100) = 100;                                  % old clamp
            if ~isempty(x)
                if viz.paperStyle()                              % paper (Fig 2 C/G): DFr-colored dots, THIN BLACK ring around ALL (no red -- the red-CV highlight is Fig 2 A/E, not this HBW panel), ratio-sized
                    sz = viz.plots.V01util.paperDotArea(ax);     % dot dia = ~3.3% of plot (scales with panel)
                    scatter(ax, x, y, sz, c, 'filled', 'MarkerEdgeColor','k', 'LineWidth',0.25);   % PDF-measured Fig 2: thin black outline on every dot
                else
                    scatter(ax, x, y, obj.SZ/3, c, 'filled', 'MarkerEdgeColor',[.6 .6 .6], 'LineWidth',0.1);
                end
            end
            % colorbar/colormap drawn unconditionally (old f05 sets them regardless of points)
            colormap(ax, obj.deltaCmap());
            try, clim(ax, [-100 100]); catch, caxis(ax, [-100 100]); end %#ok<CAXIS>
            cb = colorbar(ax); if viz.paperStyle(), cb.Label.String = 'DFr (%)'; else, cb.Label.String = 'Delta Firing Rate'; end
            cb.Ticks = -100:50:100; cb.TickLabels = {'-100','-50','0','50','100+'};
            % Stable frame so filter changes stay visible. (Old f05 autoscaled, but it
            % used MEASURED indices; not-aligned units are now dropped from HBW in
            % selIndex via Align_bad, so the cloud no longer needs an autoscale
            % guard.) OSI/CV/DSI in [0 1]; HBW max = 90 deg.
            if strcmpi(idx,'HBW'), lims = [0 90]; else, lims = [0 1]; end
            if viz.paperStyle(), uls = '--'; else, uls = '-'; end          % paper: dashed unity line
            plot(ax, lims, lims, uls, 'Color', [0 0 0], 'LineWidth', 1);
            xlim(ax, lims); ylim(ax, lims);
            if viz.paperStyle()
                unit = ''; if strcmpi(idx,'HBW'), unit = ' (\circ)'; end
                xlabel(ax, [idx '_{control}' unit]); ylabel(ax, [idx '_{laser}' unit]); title(ax, '');
                try, pv = signrank(x, y); viz.plots.V01util.drawSig(ax, mean(lims), 0.94*lims(2), pv, false, 'center'); catch, end %#ok<CTCH>
            else
                title(ax, [idx ' ' condStr]); xlabel(ax, [idx ' Control']); ylabel(ax, [idx ' Laser']);
            end
            ax.ButtonDownFcn = @(s,e) obj.onSelClick(s, e, x, y, pick);
            obj.registerRing(ax, x, y, pick);       % track unit across plots
            viz.plots.V01util.highlightUnits(ax, x, y, pick, obj.SelectedUnit);
            hold(ax,'off');
        end

        function onSelClick(obj, ax, e, X, Y, reps)
            if isempty(reps), return; end
            try, pt = e.IntersectionPoint(1:2); catch, return; end
            [~,k] = min((X-pt(1)).^2 + (Y-pt(2)).^2); u = reps(k);
            obj.SelectedUnit = u;
            uu = NaN; if isfield(obj.LastD,'U_unity'), uu = double(obj.LastD.U_unity(u)); end
            obj.infoLabel.Text = sprintf('clicked unit #%d  (U_unity %g)', u, uu);
            viz.plots.V01util.highlightUnits(ax, X, Y, reps, u);   % ring the picked point
            obj.inspectPick(u);                                    % open/update the inspector popup
            obj.trackPick(u);                                      % ring across every plot if tracking
        end

        % ---- helpers -------------------------------------------------- %
        function [L, NL] = selIndex(~, D, name)
            %SELINDEX  Selectivity index columns (L=laser, NL=control) from the
            %   CALCULATED metrics already in D: OSI=fitOSI, CV=fitCV, HBW=fitHBW,
            %   DSI=DSiL/DSiNL (see analysis.computeMetrics).
            N = viz.plots.V01util.nU(D);
            colv = @viz.plots.V01util.colv;
            switch upper(name)
                case 'OSI', L = colv(D,'fitOSI_L',N); NL = colv(D,'fitOSI_NL',N);
                case 'CV',  L = colv(D,'fitCV_L', N); NL = colv(D,'fitCV_NL', N);
                case 'HBW'
                    L = colv(D,'fitHBW_L',N); NL = colv(D,'fitHBW_NL',N);
                    badU = colv(D,'Align_bad',N) == 1;   % not-aligned: exclude (was fitHBW<0, off-axis)
                    L(badU) = NaN; NL(badU) = NaN;
                case 'DSI', L = colv(D,'DSiL',   N); NL = colv(D,'DSiNL',   N);
                otherwise,  L = nan(N,1); NL = nan(N,1);
            end
        end

        function cmap = deltaCmap(~)
            % old green-white-blue diverging map (neg=green, 0=white, pos=blue).
            n = 200; mid = round(n/2); cmap = zeros(n,3);
            cmap(1:mid,1)     = linspace(0,1,mid);
            cmap(1:mid,2)     = 1;
            cmap(1:mid,3)     = linspace(0,1,mid);
            cmap(mid+1:end,1) = linspace(1,0,n-mid);
            cmap(mid+1:end,2) = linspace(1,0,n-mid);
            cmap(mid+1:end,3) = 1;
        end
    end
end
