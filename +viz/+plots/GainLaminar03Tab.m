classdef GainLaminar03Tab < viz.PlotTab
%GAINLAMINAR03TAB  Controls for Visualizer_03.m's main window (f); the actual
%   figure opens in its OWN maximized uifigure, built with the literal old pixel
%   positions, fonts (11 pt) and colors so it is 1:1 with the old V03 fig 1.
%
%   The TAB shows only the controls; the global filter panel is in the toolbar.
%   Panels are placed in PIXELS at the exact old monitor fractions (old fig spans
%   [0 .03 1 .95] of screen, y/height /0.95), recomputed on resize.
%
%   Reproduces the 26-panel old `f` window (Visualizer_03.m):
%     a0       : non-preferred(min) - background scatter, x=laser/y=control, E
%                green / I blue; edge RED for the more-selective (CV<=.8) units.
%     a1{1..5} : pref->nonpref & pref->2nd-pref orientation-distance histograms;
%                pref-ori L-vs-NL scatter; CV-vs-HBW scatters (control / laser).
%     a3{1,2}  : OSI distributions split by gain class (MXH yellow / Mlt black),
%                for PVE / PVI.
%     a2{1..6} : Mlt/Add (=Mlt/MXH) ratio per layer, observation-level (1..3) and
%                unique-neuron (4..6), for PVE / PVI / All.
%     a2{7..9} : Mlt / MXH unique-neuron counts per layer (E green / I blue), and
%                MXH(yellow) vs Mlt(black) totals.
%     a2{10..12}: per-neuron laminar composition (MXH / MUL / MXH-MUL / UCT %),
%                grouped by layer, MXH-vs-Mlt only, and global.
%     a4{1..6} : OSI/CV/HBW box plots over MXH/Mlt/UCT, for PVE then PVI (ranksum).
%
%   Gain class = G_type: 1=Mlt (multiplicative/linear, black), 2=MXH (additive/
%   non-linear, yellow), 3=UCT (unclassified, red). Orientation distances derive
%   from fitPrefOri1/fitPrefOri2/fitMinOri1; non-pref-minus-baseline from
%   FrMin/FrBase; OSI/CV/HBW from the FITTED metrics (f05/V02-consistent). No new
%   computeMetrics fields are needed.
%
%   CONTROLS: unit group (TuningG); repeated obs (per neuron); layers (3 or 4).
%   The old script used TuningG='ORI_NON_PV' and laminar_N=4 with no dedup, so
%   group=ORI_NON_PV + rep=All + layers=4 reproduces the old f. The laminar
%   ratio/count/composition panels (a2) mirror the old fixed per-observation /
%   per-neuron counts and are NOT affected by the repeated-obs control.
%   Under "Mixed-effects (stats)" the gain-class distribution panels (a3 OSI
%   histograms, a4 OSI/CV/HBW box plots) are collapsed to one per-neuron mean per
%   class and the a4 MXH-vs-Mlt rank-sum aggregates per neuron (star turns red when
%   that changes significance) -- the pseudo-replication correction, matching the
%   Layer-selectivity tabs. The a0/a1 scatter panels stay observation-level.
%
%   STATS REPORT: the Mixed-effects column fits
%       metric ~ class + (1|penetration) + (1|penetration:neuron)
%   to every observation (Satterthwaite df), after resolving each neuron to its
%   majority MXH/Mlt class; the All column keeps the published per-observation
%   rank-sum. See analysis.stats.figureCatalog i_classBetween.
%
%   See also: analysis.tuningGroupMask, viz.plots.V01util, viz.plots.Composition03Tab

    properties
        groupDD; repDD; laminarDD; statusLbl; infoLabel
        PlotFig
        a0                      % non-pref - background scatter
        a1 = {}                 % 1x5 scatters / histograms
        a2 = {}                 % 1x12 laminar ratio / count / composition
        a3 = {}                 % 1x2 OSI MXH-Mlt histograms (PVE / PVI)
        a4 = {}                 % 1x6 OSI/CV/HBW box plots (PVE then PVI)
        LayoutSpec = {}
        LastD = []; LastMask = []
        SelectedUnit = NaN
    end

    properties (SetAccess = private)
        CurrentSet = []
    end

    properties (Constant)
        GROUPS = {'ALL_UNITS','NO_ORI_ON_PV','NO_ORI_NO_PV','ORI_ON_PV','ORI_NON_PV','ORI_NON_PV_MD','ORI_NON_PV_NL','ORI_NON_PV_U','OUTLIER'};
        REP_ITEMS = {'All (match old code)','First per neuron','Max laser power', ...
                     'Mean per neuron','Mixed-effects (stats)'};
        REP_DATA  = {'all','first','maxpow','mean','lme'};
        COL_E = [0 1 0];                 % PVE green (old [0 1 0])
        COL_I = [0 0 1];                 % PVI blue
        C_MXH = [253 219 85]/255;        % additive / MXH (old Cyellow)
        C_MLT = [0 0 0];                 % multiplicative (old black)
        C_MIX = [0 0 1];                 % MXH-MUL tie (old [0 0 1] blue)
        C_UCT = [1 0 0];                 % unclassified (old red)
        COLORS_NL = {[254 141 165]/255, [255 173 72]/255, [67 183 194]/255};  % SG / G / IG
        CV_TH = 0.8;                     % old Cvt3: edge red for CV<=.8 (more selective)
        LAYER_LAB = {'SG','G','IG','Deep'};
        FONT = 11; LW = 1; SZ = 7.7;     % fonts=11, sz=fonts*.7
    end

    methods
        function obj = GainLaminar03Tab()
            obj@viz.PlotTab('Gain & laminar (V03)');
        end

        % --------------------------------------------------------------- %
        function buildControls(obj, parent)
            g = uigridlayout(parent, [12 1]);
            g.RowHeight = repmat({'fit'}, 1, 12); g.RowHeight{end} = '1x';
            g.RowSpacing = 4; g.Padding = [8 8 8 8];
            uilabel(g, 'Text', 'Unit group (TuningG)');
            obj.groupDD = uidropdown(g, 'Items', obj.GROUPS, 'Value', 'ORI_NON_PV', ...
                'ValueChangedFcn', @(s,e) obj.requestRefresh());
            uilabel(g, 'Text', 'Repeated obs (per neuron)');
            obj.repDD = uidropdown(g, 'Items', obj.REP_ITEMS, 'ItemsData', obj.REP_DATA, ...
                'Value', 'all', 'ValueChangedFcn', @(s,e) obj.requestRefresh());
            uilabel(g, 'Text', 'Layers');
            obj.laminarDD = uidropdown(g, 'Items', {'3 (SG/G/IG)','4 (+Deep)'}, ...
                'ItemsData', [3 4], 'Value', 4, 'ValueChangedFcn', @(s,e) obj.requestRefresh());
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
            uilabel(gg, 'Text', sprintf(['The Visualizer-03 "Gain & laminar" (fig 1) window opens ' ...
                'in its own maximized window (1:1 with the old figure).\n\nUse the controls on the ' ...
                'left (and the toolbar Filters) \x2014 the window refreshes live.']), ...
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
            state = struct('group', obj.groupDD.Value, 'mask', mask(:));
            hdr = sprintf(['Visualizer-03 gain & laminar \x2014 group %s.  No-laser OSI/CV/HBW MXH-vs-Mlt ' ...
                'rank-sums, PVE & PVI.'], obj.groupDD.Value);
            rs = struct('figKey','V03f', 'state',state, 'D',obj.LastD, 'header',hdr);
        end

        function openFigure(obj)
            if ~isempty(obj.PlotFig) && isvalid(obj.PlotFig)
                figure(obj.PlotFig); obj.drawFigure(); obj.refreshStatus(); return;
            end
            ss = get(0,'screensize'); Mx = ss(3); My = ss(4);
            obj.PlotFig = uifigure('Name','Visualizer 03 - Gain & laminar (fig 1)', 'Color','w', ...
                'Position', [0, round(.03*My), Mx, round(.95*My)]);
            obj.PlotFig.CloseRequestFcn = @(s,e) delete(s);
            obj.LayoutSpec = {};
            obj.createPanels();
            try, obj.PlotFig.AutoResizeChildren = 'off'; catch, end %#ok<CTCH>
            obj.PlotFig.SizeChangedFcn = @(s,e) obj.relayout();
            obj.relayout(); obj.drawFigure(); obj.refreshStatus();
        end

        function s = getControlState(obj)
            s = struct('group', obj.groupDD.Value, 'rep', obj.repDD.Value, ...
                       'lam', obj.laminarDD.Value, 'sel', obj.SelectedUnit);
        end
        function setControlState(obj, s)
            if isfield(s,'group'), obj.setCtrl(obj.groupDD, s.group); end
            if isfield(s,'rep'),   obj.setCtrl(obj.repDD,   s.rep);   end
            if isfield(s,'lam'),   obj.setCtrl(obj.laminarDD,s.lam);  end
            if isfield(s,'sel'),   obj.SelectedUnit = s.sel; end
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
            pa1 = {[.46 .01 .17 .20],[.64 .21 .17 .20],[.82 .21 .17 .20],[.64 .01 .17 .20],[.82 .01 .17 .20]};
            pa2 = {[.0415 .78 .11 .17],[.2015 .78 .11 .17],[.3615 .78 .11 .17], ...
                   [.54 .78 .11 .17],[.70 .78 .11 .17],[.86 .78 .11 .17], ...
                   [.54 .60 .11 .17],[.70 .60 .11 .17],[.86 .60 .11 .17], ...
                   [.78 .42 .16 .17],[.22 .01 .14 .17],[.485 .23 .10 .17]};
            pa3 = {[.50 .42 .13 .17],[.63 .42 .13 .17]};
            pa4 = {[.02 .52 .14 .24],[.18 .52 .14 .24],[.34 .52 .14 .24], ...
                   [.02 .27 .14 .24],[.18 .27 .14 .24],[.34 .27 .14 .24]};

            obj.a0 = obj.addAx(.01,.01,.20,.24);
            obj.a1 = cell(1,5); for k=1:5, obj.a1{k} = obj.addAx(pa1{k}(1),pa1{k}(2),pa1{k}(3),pa1{k}(4)); end
            obj.a2 = cell(1,12); for k=1:12, obj.a2{k} = obj.addAx(pa2{k}(1),pa2{k}(2),pa2{k}(3),pa2{k}(4)); end
            obj.a3 = cell(1,2); for k=1:2, obj.a3{k} = obj.addAx(pa3{k}(1),pa3{k}(2),pa3{k}(3),pa3{k}(4)); end
            obj.a4 = cell(1,6); for k=1:6, obj.a4{k} = obj.addAx(pa4{k}(1),pa4{k}(2),pa4{k}(3),pa4{k}(4)); end
            obj.createLabels();
        end

        function ax = addAx(obj, fx, fy, fw, fh)
            ax = uiaxes(obj.PlotFig); ax.Units = 'pixels'; ax.FontUnits = 'points';
            ax.FontSize = obj.FONT; ax.LineWidth = obj.LW; ax.XTickLabelRotation = 0;
            obj.LayoutSpec{end+1} = {ax, [fx fy fw fh]};
        end

        function addLabel(obj, fx, fy, fw, fh, txt, rot, col, fsz)
            if nargin < 8 || isempty(col), col = 'k'; end
            if nargin < 9 || isempty(fsz), fsz = obj.FONT; end
            ax = uiaxes(obj.PlotFig); ax.Units = 'pixels'; ax.Visible = 'off';
            text(ax, 0, 0, txt, 'Color', col, 'Rotation', rot, 'FontUnits','points', 'FontSize', fsz);
            obj.LayoutSpec{end+1} = {ax, [fx fy fw fh]};
        end

        function createLabels(obj)
            % T1 panel letters A C B D (2x font) at the old floating-axes anchors
            locs = {[-.01 .90],[.49 .90],[-.01 .68],[.47 .50]}; abcs = {'A','C','B','D'};
            for i = 1:4, obj.addLabel(locs{i}(1), locs{i}(2), .05, .10, abcs{i}, 0, 'k', obj.FONT*2); end
            % T2 rotated ratio labels over the two laminar-ratio blocks
            obj.addLabel(.01,  .76, .04, .20, 'Multiplicative/MXH Ratio', 90);
            obj.addLabel(.513, .76, .04, .20, sprintf('Multiplicative/MXH Ratio \n          Single unit ratio'), 90);
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
            % The 3 laminar bar panels are narrowed to the paper's proportions in
            % paper mode; restore the original wider boxes when Original style is on.
            if ~viz.paperStyle()
                orig = {obj.a2{10}, [.78 .42 .20 .17]; obj.a2{11}, [.22 .01 .17 .17]; obj.a2{12}, [.485 .23 .15 .17]};
                for i = 1:size(orig,1)
                    h = orig{i,1}; fr = orig{i,2};
                    if isempty(h) || ~isvalid(h), continue; end
                    try, h.Position = [fr(1)*W, (fr(2)/0.95)*H, max(2,fr(3)*W), max(2,(fr(4)/0.95)*H)]; catch, end %#ok<CTCH>
                end
            end
        end

        % ---- main draw ------------------------------------------------ %
        function drawFigure(obj)
            D = obj.LastD; mask = obj.LastMask;
            if isempty(D) || isempty(obj.PlotFig) || ~isvalid(obj.PlotFig), return; end
            obj.relayout(); obj.clearAll();
            need = {'G_type','FrMin_NL','FrBase_NL','fitOSI_NL','fitCV_NL','fitHBW_NL', ...
                    'fitPrefOri1_NL','fitMinOri1_NL','fitPrefOri2_NL'};
            for q = 1:numel(need)
                if ~isfield(D, need{q}), title(obj.a0, ['Missing ' need{q}]); return; end
            end
            try, grpMask = analysis.tuningGroupMask(D, obj.groupDD.Value);
            catch err, title(obj.a0, ['Group error: ' err.message]); return; end

            colv = @viz.plots.V01util.colv;
            isI  = viz.plots.V01util.isInhib(D);
            G    = colv(D,'G_type');
            LGn  = viz.plots.V01util.layerNum(D);
            UU   = colv(D,'U_unity');
            sel  = mask(:) & grpMask(:);
            mode = obj.repDD.Value;
            eObs = find(sel & ~isI);                 % observation-level (no dedup)
            iObs = find(sel &  isI);
            Re = viz.plots.V01util.reducer(D, eObs, mode); eRep = viz.plots.V01util.redIdx(Re);
            Ri = viz.plots.V01util.reducer(D, iObs, mode); iRep = viz.plots.V01util.redIdx(Ri);
            PK = viz.plots.V01util.penKey(D);
            % class boxes: one MXH/Mlt/UCT class per neuron for every per-neuron
            % view, and 'mean'/'lme' feed ALL observations (collapsed per neuron
            % inside classBox) so 'mean' truly averages instead of keeping the
            % first recording per neuron.
            Gc = G;
            if ~strcmp(mode, 'all'), Gc = viz.plots.V01util.classPerNeuron(G, UU, [eObs; iObs]); end
            if any(strcmp(mode, {'mean','lme'})), eCls = eObs; iCls = iObs; else, eCls = eRep; iCls = iRep; end
            allRep = [eRep(:); iRep(:)];        % CurrentSet / unit picking
            nL = obj.laminarDD.Value;

            % derived per-unit quantities (from existing D fields)
            npbNL = colv(D,'FrMin_NL') - colv(D,'FrBase_NL');
            npbL  = colv(D,'FrMin_L')  - colv(D,'FrBase_L');
            prefNL= colv(D,'fitPrefOri1_NL'); prefL = colv(D,'fitPrefOri1_L');
            minNL = colv(D,'fitMinOri1_NL');  minL  = colv(D,'fitMinOri1_L');
            pre2NL= colv(D,'fitPrefOri2_NL'); pre2L = colv(D,'fitPrefOri2_L');
            cvNL  = colv(D,'fitCV_NL');  cvL  = colv(D,'fitCV_L');
            hbwNL = colv(D,'fitHBW_NL'); hbwL = colv(D,'fitHBW_L');
            badU = colv(D,'Align_bad') == 1;              % not-aligned units (was fitHBW<0)
            hbwNL(badU) = NaN; hbwL(badU) = NaN;
            osiNL = colv(D,'fitOSI_NL');
            odPNP_NL = obj.foldDist(prefNL, minNL);  odPNP_L = obj.foldDist(prefL, minL);
            odP2P_NL = abs(pre2NL - prefNL);         odP2P_L = abs(pre2L - prefL);

            % Per-neuron DISPLAY copies for the a0/a1 scatter + histogram panels:
            % under 'mean'/'lme' every neuron's rows hold its MEAN (avgIntoReps)
            % and the panels get ONE representative row per neuron, so each neuron
            % is one dot with its averaged value. The RAW vectors stay untouched
            % for classBox / classMetric, which collapse per neuron themselves.
            perCell = any(strcmp(mode, {'mean','lme'}));
            if perCell
                obsAll = [eObs; iObs];
                eRepP = viz.plots.V01util.redIdx(viz.plots.V01util.reducer(D, eObs, 'first'));
                iRepP = viz.plots.V01util.redIdx(viz.plots.V01util.reducer(D, iObs, 'first'));
                avg = @(v) viz.plots.V01util.avgIntoReps(v, obsAll, UU);
                npbNLd = avg(npbNL); npbLd = avg(npbL);
                prefNLd = avg(prefNL); prefLd = avg(prefL);
                odPNP_NLd = avg(odPNP_NL); odPNP_Ld = avg(odPNP_L);
                odP2P_NLd = avg(odP2P_NL); odP2P_Ld = avg(odP2P_L);
                cvNLd = avg(cvNL); cvLd = avg(cvL); hbwNLd = avg(hbwNL); hbwLd = avg(hbwL);
            else
                eRepP = eRep; iRepP = iRep;
                npbNLd = npbNL; npbLd = npbL; prefNLd = prefNL; prefLd = prefL;
                odPNP_NLd = odPNP_NL; odPNP_Ld = odPNP_L; odP2P_NLd = odP2P_NL; odP2P_Ld = odP2P_L;
                cvNLd = cvNL; cvLd = cvL; hbwNLd = hbwNL; hbwLd = hbwL;
            end
            allRepP = [eRepP(:); iRepP(:)];

            % ---- a0 : non-pref(min) - background, laser(x) vs control(y) ----
            obj.drawA0(npbLd, npbNLd, eRepP, iRepP, cvNLd);
            % ---- a1{1}/a1{2} : orientation-distance histograms -------------
            % a1{1} = paper Fig S1B (Delta orientation, control black / laser gray)
            if viz.paperStyle()
                obj.twoHistAuto(obj.a1{1}, odPNP_NLd(allRepP), odPNP_Ld(allRepP), [0 0 0], [.5 .5 .5], ...
                    '', '\Delta orientation (\circ)', 'Number of cells', {'control','laser'});
            else
                obj.twoHistAuto(obj.a1{1}, odPNP_NLd(allRepP), odPNP_Ld(allRepP), [0 0 0], [0 1 1], ...
                    'Preferred to non preferred', 'Degrees');
            end
            obj.twoHistAuto(obj.a1{2}, odP2P_NLd(allRepP), odP2P_Ld(allRepP), [0 0 0], [0 1 1], ...
                'Preferred to second preferred', 'Degrees');
            % ---- a1{3} : pref ori L vs NL ----------------------------------
            obj.drawPrefScatter(prefLd, prefNLd, eRepP, iRepP);
            % ---- a1{4}/a1{5} : CV vs HBW (control / laser) -----------------
            obj.drawCvhScatter(obj.a1{4}, hbwNLd, cvNLd, allRepP, [], 'CV vs HBW  No Laser');
            obj.drawCvhScatter(obj.a1{5}, hbwLd,  cvLd,  eRepP, iRepP, 'CV vs HBW Laser');
            % ---- a3 : OSI by gain class (MXH yellow vs Mlt black) ----------
            % Like the a4 boxes, these gain-class OSI distributions collapse to one
            % per-neuron mean under Mixed-effects (classMetric); other modes show obs.
            obj.twoHistAuto(obj.a3{1}, obj.classMetric(osiNL,eCls,Gc,2,UU,mode), obj.classMetric(osiNL,eCls,Gc,1,UU,mode), ...
                obj.C_MXH, obj.C_MLT, 'OSI MXH-MUL (PVE)', 'OSI');
            obj.twoHistAuto(obj.a3{2}, obj.classMetric(osiNL,iCls,Gc,2,UU,mode), obj.classMetric(osiNL,iCls,Gc,1,UU,mode), ...
                obj.C_MXH, obj.C_MLT, 'OSI MXH-MUL (PVI)', 'OSI');

            % ---- a2{1..6} : Mlt/Add ratio per layer (obs then unique) ------
            ce = obj.layerCounts(G, LGn, eObs, false, UU);   % 2x3 [Add;Mlt] obs counts (E)
            ci = obj.layerCounts(G, LGn, iObs, false, UU);
            ue = obj.layerCounts(G, LGn, eObs, true,  UU);   % unique-neuron counts (E)
            ui = obj.layerCounts(G, LGn, iObs, true,  UU);
            obj.ratioBar(obj.a2{1}, ce(2,:)./obj.nz(ce(1,:)), 'PV Excitation', true);
            obj.ratioBar(obj.a2{2}, ci(2,:)./obj.nz(ci(1,:)), 'PV Inhibition', false);
            obj.ratioBar(obj.a2{3}, (ce(2,:)+ci(2,:))./obj.nz(ce(1,:)+ci(1,:)), 'All', false);
            obj.ratioBar(obj.a2{4}, ue(2,:)./obj.nz(ue(1,:)), 'PV Excitation', true);
            obj.ratioBar(obj.a2{5}, ui(2,:)./obj.nz(ui(1,:)), 'PV Inhibition', false);
            obj.ratioBar(obj.a2{6}, (ue(2,:)+ui(2,:))./obj.nz(ue(1,:)+ui(1,:)), 'All', false);
            % ---- a2{7..9} : Mlt / MXH unique counts (E green / I blue) -----
            obj.countBar(obj.a2{7}, ue(2,:), ui(2,:), obj.COL_E, obj.COL_I, 'Multiplicative');
            obj.countBar(obj.a2{8}, ue(1,:), ui(1,:), obj.COL_E, obj.COL_I, 'MXH');
            obj.countBar(obj.a2{9}, ue(1,:)+ui(1,:), ue(2,:)+ui(2,:), obj.C_MXH, obj.C_MLT, 'MXH VS Mlt');
            % ---- a2{10..12} : per-neuron laminar composition ---------------
            M = obj.lamComposition(UU, G, LGn, find(sel), nL);   % 4 x nL [MXH;MUL;MXH-MUL;UCT]
            obj.lamGrouped(obj.a2{10}, M,        {'MXH','MUL','MXH-MUL','UCT'}, ...
                {obj.C_MXH,obj.C_MLT,obj.C_MIX,obj.C_UCT}, nL, [0 80]);
            obj.lamGrouped(obj.a2{11}, M(1:2,:), {'MXH','MUL'}, ...
                {obj.C_MXH,obj.C_MLT}, nL, [0 90]);
            obj.lamGlobal(obj.a2{12}, M, {'MXH','MUL','MXH-MUL','UCT'}, ...
                {obj.C_MXH,obj.C_MLT,obj.C_MIX,obj.C_UCT});

            % ---- a4 : OSI/CV/HBW box plots over MXH/Mlt/UCT (E then I) ------
            mets = {osiNL,'OSI',[0 1.1]; cvNL,'CV',[0 1.1]; hbwNL,'HBW',[0 50]};
            for k = 1:3
                obj.classBox(obj.a4{k},   mets{k,1}, eCls, Gc, ['PVE - ' mets{k,2}], mets{k,2}, mets{k,3}, UU, PK, mode);
                obj.classBox(obj.a4{k+3}, mets{k,1}, iCls, Gc, ['PVI - ' mets{k,2}], mets{k,2}, mets{k,3}, UU, PK, mode);
            end

            obj.CurrentSet = allRep;
            if ~ismember(obj.SelectedUnit, allRep) && ~isempty(allRep), obj.SelectedUnit = NaN; end
            selTxt = ''; if isfinite(obj.SelectedUnit), selTxt = sprintf('   sel unit %d (UU %g)', obj.SelectedUnit, UU(obj.SelectedUnit)); end
            % Counts match what the gain-class panels (a3/a4) draw: under Mixed-effects
            % those are per-neuron, so report distinct-neuron counts + label 'neurons'.
            if strcmp(mode,'lme')
                nlab = 'neurons';
                cnt = @(r,g) numel(unique(UU(r(G(r)==g))));   % distinct neurons in a gain class
                nE = numel(unique(UU(eRep))); nI = numel(unique(UU(iRep)));
            else
                nlab = 'units';
                cnt = @(r,g) sum(G(r)==g);                    % observations in a gain class
                nE = numel(eRep); nI = numel(iRep);
            end
            obj.infoLabel.Text = sprintf(['group %s   E=%d I=%d (%s)   MXH/Mlt/UCT E:%d/%d/%d I:%d/%d/%d%s\n' ...
                'ORI_NON_PV + All + 4 layers reproduces the old f. Under Mixed-effects the gain-class ' ...
                'panels (a3 OSI hists, a4 box plots) show one per-neuron mean. Laminar (a2) panels use ' ...
                'per-observation / per-neuron counts (not the repeated-obs control).'], ...
                obj.groupDD.Value, nE, nI, nlab, ...
                cnt(eRep,2), cnt(eRep,1), cnt(eRep,3), ...
                cnt(iRep,2), cnt(iRep,1), cnt(iRep,3), selTxt);
        end

        function clearAll(obj)
            ax = [{obj.a0}, obj.a1, obj.a2, obj.a3, obj.a4];
            for k = 1:numel(ax), if ~isempty(ax{k}) && isgraphics(ax{k}), cla(ax{k}); end, end
        end

        % ---- a0 : non-pref - background scatter (CV-split red edges) ---- %
        function drawA0(obj, x, y, eRep, iRep, cvNL)
            ax = obj.a0; hold(ax,'on');
            % old draws high-CV (normal edge) first, then low-CV (red edge) on top
            obj.scoreSplit(ax, x, y, eRep, obj.COL_E, cvNL, false);
            obj.scoreSplit(ax, x, y, iRep, obj.COL_I, cvNL, false);
            obj.scoreSplit(ax, x, y, eRep, obj.COL_E, cvNL, true);
            obj.scoreSplit(ax, x, y, iRep, obj.COL_I, cvNL, true);
            plot(ax, [-100 100], [0 0],     'k--', 'PickableParts','none');
            plot(ax, [0 0],     [-100 100], 'k--', 'PickableParts','none');
            plot(ax, [-100 100],[-100 100], 'k--', 'PickableParts','none');
            xlabel(ax,'Firing rate Laser'); ylabel(ax,'Firing rate No Laser');
            title(ax,' Non preferred - Background');
            xlim(ax,[-30 60]); ylim(ax,[-20 40]);
            reps = [eRep(:); iRep(:)];
            ax.ButtonDownFcn = @(s,e) obj.onPick(s, e, x(reps), y(reps), reps);
            obj.registerRing(ax, x(reps), y(reps), reps);   % track unit across plots
            viz.plots.V01util.highlightUnits(ax, x(reps), y(reps), reps, obj.SelectedUnit);
            hold(ax,'off');
        end

        function scoreSplit(obj, ax, x, y, reps, col, cvNL, lowCV)
            if isempty(reps), return; end
            if lowCV, sub = reps(cvNL(reps)<=obj.CV_TH); edge = obj.C_UCT;
            else,     sub = reps(cvNL(reps)> obj.CV_TH); edge = col; end
            xx = x(sub); yy = y(sub); ok = isfinite(xx)&isfinite(yy);
            if ~any(ok), return; end
            msz = obj.SZ; if viz.paperStyle(), msz = viz.plots.V01util.paperDotArea(ax); end   % paper: ratio-sized dots
            scatter(ax, xx(ok), yy(ok), msz, 'MarkerFaceColor',col, 'MarkerEdgeColor',edge, ...
                'LineWidth',0.5, 'MarkerFaceAlpha',0.5, 'PickableParts','none');   % click reaches the axes picker
        end

        % ---- a1{3} : pref ori L vs NL ---------------------------------- %
        function drawPrefScatter(obj, x, y, eRep, iRep)
            ax = obj.a1{3}; hold(ax,'on');
            obj.scOne(ax, x, y, eRep, obj.COL_E, obj.SZ/10);
            obj.scOne(ax, x, y, iRep, obj.COL_I, obj.SZ/10);
            if viz.paperStyle()                     % paper Fig S1A: dashed black identity/±180 shift lines
                for d = [-180 0 180], plot(ax, (0:360)+d, 0:360, 'k--', 'LineWidth',0.75, 'PickableParts','none'); end
                xlabel(ax,'Preferred orientation laser (\circ)'); ylabel(ax,'Preferred orientation control (\circ)');
                title(ax,'');
                text(ax, 0.30, 1.03, 'PVA', 'Units','normalized', 'Color',obj.COL_E, 'FontWeight','bold', 'FontSize',obj.FONT-1);
                text(ax, 0.58, 1.03, 'PVI', 'Units','normalized', 'Color',obj.COL_I, 'FontWeight','bold', 'FontSize',obj.FONT-1);
            else
                plot(ax, 0:360, 0:360, 'PickableParts','none'); plot(ax, (0:360)+180, 0:360, 'PickableParts','none'); plot(ax, (0:360)-180, 0:360, 'PickableParts','none');
                xlabel(ax,'Ori prifered Laser'); ylabel(ax,'Ori prifered No Laser');
                title(ax,' Ori preferred Laser VS No Laser');
            end
            xlim(ax,[0 360]); ylim(ax,[0 360]);
            reps = [eRep(:); iRep(:)];
            ax.ButtonDownFcn = @(s,e) obj.onPick(s, e, x(reps), y(reps), reps);
            obj.registerRing(ax, x(reps), y(reps), reps);   % track unit across plots
            viz.plots.V01util.highlightUnits(ax, x(reps), y(reps), reps, obj.SelectedUnit);
            hold(ax,'off');
        end

        % ---- a1{4}/a1{5} : CV vs HBW scatter --------------------------- %
        function drawCvhScatter(obj, ax, x, y, eRep, iRep, ttl)
            hold(ax,'on');
            if isempty(iRep)        % a1{4}: all units, black
                obj.scOne(ax, x, y, eRep, [0 0 0], obj.SZ/10);
                reps = eRep(:);
            else                    % a1{5}: E green / I blue
                obj.scOne(ax, x, y, eRep, obj.COL_E, obj.SZ/10);
                obj.scOne(ax, x, y, iRep, obj.COL_I, obj.SZ/10);
                reps = [eRep(:); iRep(:)];
            end
            xlabel(ax,'HBW ( \circ )'); ylabel(ax,'Circular variance ');
            title(ax, ttl); xlim(ax,[0 60]); ylim(ax,[0 1]);
            ax.ButtonDownFcn = @(s,e) obj.onPick(s, e, x(reps), y(reps), reps);
            obj.registerRing(ax, x(reps), y(reps), reps);   % track unit across plots
            viz.plots.V01util.highlightUnits(ax, x(reps), y(reps), reps, obj.SelectedUnit);
            hold(ax,'off');
        end

        function scOne(~, ax, x, y, reps, col, msz)
            if isempty(reps), return; end
            xx = x(reps); yy = y(reps); ok = isfinite(xx)&isfinite(yy);
            if ~any(ok), return; end
            scatter(ax, xx(ok), yy(ok), msz, 'MarkerFaceColor',col, 'MarkerEdgeColor',col, ...
                'MarkerFaceAlpha',0.5, 'PickableParts','none');   % click reaches the axes picker
        end

        % ---- two overlaid histograms, auto bin width, no stars --------- %
        function twoHistAuto(~, ax, v1, v2, c1, c2, ttl, xlab, ylab, legTxt)
            if nargin < 9 || isempty(ylab), ylab = 'Count'; end
            if nargin < 10, legTxt = {}; end
            fa = 0.3; if viz.paperStyle(), fa = 0.75; end   % paper: near-solid bars
            hold(ax,'on');
            v1 = v1(isfinite(v1)); v2 = v2(isfinite(v2));
            bw = []; H1 = []; H2 = [];
            if ~isempty(v1)
                H1 = histogram(ax, v1, 'FaceColor',c1, 'FaceAlpha',fa); bw = H1.BinWidth;
            end
            if ~isempty(v2)
                if isempty(bw), H2 = histogram(ax, v2, 'FaceColor',c2, 'FaceAlpha',fa);
                else,           H2 = histogram(ax, v2, 'BinWidth',bw, 'FaceColor',c2, 'FaceAlpha',fa); end
            end
            title(ax, ttl); ylabel(ax,ylab); xlabel(ax,xlab);
            if ~isempty(legTxt) && ~isempty(H1) && ~isempty(H2)
                legend(ax, [H1 H2], legTxt, 'Box','off', 'Location','northeast');
            end
            hold(ax,'off');
        end

        % ---- a2{1..6} : single-series 3-layer ratio bar ---------------- %
        function ratioBar(obj, ax, vals, ttl, withYticks)
            vals = vals(:)'; vals(~isfinite(vals)) = NaN;
            hold(ax,'on');
            b = bar(ax, 1:3, vals, 'FaceColor','flat');
            b.CData = [obj.COLORS_NL{1}; obj.COLORS_NL{2}; obj.COLORS_NL{3}];
            b.FaceAlpha = 0.6;
            set(ax,'XTick',1:3,'XTickLabel',{'SG','G','IG'}); xlim(ax,[0.5 3.5]);
            title(ax, ttl); grid(ax,'on');
            if withYticks, yticks(ax, 0:.5:3); end
            hold(ax,'off');
        end

        % ---- a2{7..9} : two overlaid 3-layer count bars ---------------- %
        function countBar(~, ax, v1, v2, c1, c2, ttl)
            hold(ax,'on');
            b1 = bar(ax, 1:3, v1(:)', 'FaceColor','flat'); b1.CData = repmat(c1,3,1); b1.FaceAlpha = 0.3;
            b2 = bar(ax, 1:3, v2(:)', 'FaceColor','flat'); b2.CData = repmat(c2,3,1); b2.FaceAlpha = 0.3;
            set(ax,'XTick',1:3,'XTickLabel',{'SG','G','IG'}); xlim(ax,[0.5 3.5]);
            ylabel(ax,'Unit count'); title(ax, ttl); grid(ax,'on'); hold(ax,'off');
        end

        % ---- a2{10}/a2{11} : grouped laminar composition --------------- %
        function lamGrouped(obj, ax, M, cats, colors, nL, ylimv)
            paper = viz.paperStyle();
            pp2 = paper && numel(colors) == 2;      % paper Fig 4C  = 2-category NL/D-M panel
            pp4 = paper && numel(colors) == 4;      % paper Fig S5C = 4-category NL/D-M/Mix/Uct panel
            pp  = pp2 || pp4;
            if pp2                                  % NL yellow / D/M gray bars, opaque, clean
                cats = {'NL','D/M'}; colors = {[232 229 0]/255, [.366 .366 .366]}; ylimv = [0 80];
            elseif pp4                              % NL yellow / D/M gray / Mix white / Uct red
                cats = {'NL','D/M','Mix','Uct'}; ylimv = [0 80];
                colors = {[232 229 0]/255, [.366 .366 .366], [1 1 1], [1 0 0]};
            end
            colsum = sum(M,1); colsum(colsum==0) = NaN;
            P = 100 * M ./ colsum;                 % nCat x nL, % within layer
            data = P';                             % nL x nCat
            hold(ax,'on');
            h = bar(ax, data, 'grouped');
            for m = 1:numel(h)
                h(m).FaceColor = colors{m}; h(m).FaceAlpha = 0.3 + 0.7*pp;   % opaque in paper mode
                if pp4, h(m).EdgeColor = [0 0 0]; h(m).LineWidth = 0.5; end  % edge so the white Mix bar is visible
            end
            if pp                                   % paper: slightly larger, bold cortical-layer labels
                ax.FontSize = obj.FONT + 1;
                xl = cellfun(@(s)['\bf' s], obj.LAYER_LAB(1:nL), 'UniformOutput', false);
                set(ax, 'XTick', 1:nL, 'TickLabelInterpreter','tex', 'XTickLabel', xl);
            else
                set(ax, 'XTick', 1:nL, 'XTickLabel', obj.LAYER_LAB(1:nL));
            end
            ylim(ax, ylimv);
            if pp2
                ylabel(ax, '% of layer count', 'FontWeight','bold');
                text(ax, 0.72, 0.84, cats{1}, 'Units','normalized', 'Color',colors{1}, 'FontWeight','bold', 'FontSize',obj.FONT-1);
                text(ax, 0.85, 0.84, cats{2}, 'Units','normalized', 'Color',colors{2}, 'FontWeight','bold', 'FontSize',obj.FONT-1);
            elseif pp4
                ylabel(ax, '% of layer count', 'FontWeight','bold');
                try, legend(ax, h, cats, 'Box','off', 'Location','northeast'); catch, end %#ok<CTCH>
            else
                title(ax,'Laminar distribution'); ylabel(ax,'Unit Count %');
                try, legend(ax, cats); catch, end %#ok<CTCH>     % old: default box-on, 11pt, auto-located
            end
            for k = 1:nL                            % N/n labels
                if pp, yText = 0.90*ylimv(2); fmt = 'n=%d'; fw = 'normal'; fs = obj.FONT-4;
                else,  yMax = max(data(k,:)); if ~isfinite(yMax), yMax = 0; end
                       yText = yMax + 0.05*range(ax.YLim); fmt = 'N = %d'; fw = 'bold'; fs = obj.FONT; end
                text(ax, k, yText, sprintf(fmt, sum(M(:,k))), 'HorizontalAlignment','center', ...
                    'VerticalAlignment','bottom', 'FontSize',fs, 'FontWeight',fw);
            end
            if ~pp, grid(ax,'on'); end
            hold(ax,'off');
        end

        % ---- a2{12} : global composition (4 single bars) --------------- %
        function lamGlobal(obj, ax, M, cats, colors)
            tot = sum(M,2); pct = 100 * tot / max(sum(tot), eps);   % tot/pct = [MXH; MUL; MXH-MUL; UCT]
            hold(ax,'on');
            if viz.paperStyle(), obj.lamGlobalPaper(ax, tot, pct); hold(ax,'off'); return; end
            hb = gobjects(1,numel(cats));
            for m = 1:numel(cats)
                hb(m) = bar(ax, m, pct(m), 'FaceColor', colors{m}, 'FaceAlpha', 0.3, 'BarWidth', 0.5);
            end
            set(ax,'XTick',1:numel(cats),'XTickLabel',{'1','2','3','4'});
            title(ax,'Laminar distribution'); ylabel(ax,'Unit Count %'); ylim(ax,[0 65]);
            try, legend(ax, hb, cats); catch, end %#ok<CTCH>     % old: default box-on, 11pt, auto-located
            for k = 1:numel(cats)
                yText = pct(k) + 0.05*range(ax.YLim);
                text(ax, k, yText, sprintf('N = %d', tot(k)), 'HorizontalAlignment','center', ...
                    'VerticalAlignment','bottom', 'FontSize',obj.FONT, 'FontWeight','bold');
            end
            grid(ax,'on'); hold(ax,'off');
        end

        % ---- paper Fig S2-B: NL / D/M / U(=Mix+Uct stacked), "% of total" -- %
        function lamGlobalPaper(obj, ax, tot, pct)
            cla(ax);
            LF = obj.FONT + 1;  ax.FontSize = LF;                              % paper labels slightly larger than default
            yNL = [0.886 0.890 0]; gDM = [0.294 0.294 0.294]; red = [1 0 0];   % PDF-sampled S2-B colors
            pNL=pct(1); pDM=pct(2); pMix=pct(3); pUct=pct(4);                  % MXH/MUL/MXH-MUL/UCT -> NL/D/M/Mix/Uct
            nNL=tot(1); nDM=tot(2); nMix=tot(3); nUct=tot(4);
            hold(ax,'on'); bw = 0.6; ax.YGrid='on'; ax.XGrid='off';
            bar(ax, 1, pNL, 'FaceColor',yNL, 'EdgeColor','k', 'LineWidth',0.5, 'BarWidth',bw);   % NL
            bar(ax, 2, pDM, 'FaceColor',gDM, 'EdgeColor','k', 'LineWidth',0.5, 'BarWidth',bw);   % D/M
            % U = BLACK total bar (n=Mix+Uct) with white-Mix (left) + red-Uct (right) sub-bars at its base
            bar(ax, 3, pMix+pUct, 'FaceColor','k', 'EdgeColor','k', 'LineWidth',0.5, 'BarWidth',bw);
            hMix = bar(ax, 3-0.135, pMix, 'FaceColor','w', 'EdgeColor','k', 'LineWidth',0.5, 'BarWidth',0.26);  % Mix (white, left)
            hUct = bar(ax, 3+0.135, pUct, 'FaceColor',red, 'EdgeColor','k', 'LineWidth',0.5, 'BarWidth',0.26);  % Uct (red, right)
            ylim(ax,[0 60]); xlim(ax,[0.4 3.6]); yticks(ax,0:20:60);
            nl=sprintf('\\bf\\color[rgb]{%g,%g,%g}NL',yNL); dm=sprintf('\\bf\\color[rgb]{%g,%g,%g}D/M',gDM);
            set(ax,'XTick',1:3, 'TickLabelInterpreter','tex', 'XTickLabel',{nl,dm,'\bfU'});
            ylabel(ax,'% of total','FontWeight','bold'); title(ax,'');
            ns = {nNL, nDM, nMix+nUct}; ph = [pNL pDM pMix+pUct];             % n= over each bar (small, non-bold)
            for k=1:3, text(ax, k, ph(k)+1.5, sprintf('n=%d', ns{k}), 'HorizontalAlignment','center', ...
                    'VerticalAlignment','bottom', 'FontSize',LF-3, 'Clipping','off'); end
            try, legend(ax, [hMix hUct], {sprintf('Mix (n=%d)',nMix), sprintf('Uct (n=%d)',nUct)}, ...
                    'Location','northeast', 'Box','off', 'FontSize',LF-3); catch, end %#ok<CTCH>
        end

        % ---- a4 : OSI/CV/HBW box plot over MXH/Mlt/UCT ----------------- %
        function classBox(obj, ax, vals, reps, G, ttl, ylab, ylimv, UU, PK, mode)
            % Observation-level group values (+ aligned U_unity ids + D rows). The
            % star below is an LME on these observations under Mixed-effects, a
            % rank-sum of the displayed per-neuron means under Mean/neuron, and the
            % classic rank-sum otherwise. `reps` is ALL observations for the
            % per-neuron modes (collapsed below), representatives otherwise.
            rMXH = reps(G(reps)==2); gMXH = vals(rMXH); okMXH = isfinite(gMXH); gMXH = gMXH(okMXH); rMXHf = rMXH(okMXH);
            rMlt = reps(G(reps)==1); gMlt = vals(rMlt); okMlt = isfinite(gMlt); gMlt = gMlt(okMlt); rMltf = rMlt(okMlt);
            rUCT = reps(G(reps)==3); gUCT = vals(rUCT); okUCT = isfinite(gUCT); gUCT = gUCT(okUCT); rUCTf = rUCT(okUCT);
            nMXH = UU(rMXH); nMXH = nMXH(okMXH);          % U_unity aligned with gMXH (same rows+filter)
            nMlt = UU(rMlt); nMlt = nMlt(okMlt);          % U_unity aligned with gMlt
            nUCT = UU(rUCT); nUCT = nUCT(okUCT);          % U_unity aligned with gUCT
            % DISPLAY data: under Mean/neuron AND Mixed-effects, collapse each gain
            % class to ONE per-neuron mean (each neuron once within its class) so
            % the dots/boxes match the reported statistic; other modes plot the
            % observations unchanged. The ORIGINAL observation rows (rMXHf/rMltf)
            % are kept for the LME star below. See STATS_MIXED_EFFECTS.md 3e.
            rMXHd = rMXHf; rMltd = rMltf; rUCTd = rUCTf;
            if any(strcmp(mode, {'mean','lme'}))
                [gMXHd, ~, rMXHd] = viz.plots.V01util.aggNeuronScalar(gMXH, nMXH, rMXHf);
                [gMltd, ~, rMltd] = viz.plots.V01util.aggNeuronScalar(gMlt, nMlt, rMltf);
                [gUCTd, ~, rUCTd] = viz.plots.V01util.aggNeuronScalar(gUCT, nUCT, rUCTf);
            else
                gMXHd = gMXH; gMltd = gMlt; gUCTd = gUCT;
            end
            if viz.paperStyle()                            % paper Fig 4: NL(MXH) vs D/M(Mlt) only, yellow / gray (PDF-measured)
                data = {gMXHd(:), gMltd(:)};
                repByGrp = {rMXHd(:), rMltd(:)};
                colors = {[184 182 0]/255, [.366 .366 .366]};   % NL olive-yellow, D/M gray
                glab = {'NL','D/M'};
            else
                data = {gMXHd(:), gMltd(:), gUCTd(:)};
                repByGrp = {rMXHd(:), rMltd(:), rUCTd(:)};    % D row index per plotted dot (per group)
                colors = {obj.C_MXH, obj.C_MLT, obj.C_UCT};
                glab = {'MXH','Multiplicative ','ucl'};
            end
            nG = numel(data);
            vals2 = []; grp = {};
            for i = 1:nG
                d = data{i}; if isempty(d), d = 0; end
                vals2 = [vals2; d]; grp = [grp; repmat(glab(i), numel(d), 1)]; %#ok<AGROW>
            end
            hold(ax,'on');
            try
                hbp = boxplot(ax, vals2, grp, 'Colors','k', 'Symbol','', ...
                    'GroupOrder', glab, 'Positions', 1:nG, 'Widths', 0.5);
                set(hbp, 'PickableParts','none');               % box lines must not swallow clicks on interior dots
                h = findobj(ax, 'Tag', 'Box');
                for j = 1:numel(h)
                    patch(ax, get(h(j),'XData'), get(h(j),'YData'), colors{numel(h)-j+1}, 'FaceAlpha', .05, 'PickableParts','none');
                end
                if viz.paperStyle(), set(findobj(ax,'Tag','Median'), 'Color',[1 0 0], 'LineWidth',1); end   % paper: red median
            catch
            end
            edg = {}; dsz = obj.SZ/2;
            if viz.paperStyle()
                edg = {'MarkerEdgeColor','w', 'LineWidth',0.75};      % paper: visible white ring per dot
                dsz = viz.plots.V01util.paperDotAreaBox(ax, nG);     % paper: dot dia = ~6% of group-column width
            end
            jitX = cell(1,nG);
            for i = 1:nG
                d = data{i};
                if isempty(d), d = 0; end          % old Box_plot_02: empty group -> stray point at y=0
                d = d(:);
                jx = viz.plots.V01util.boxJitterX(i, numel(d), 0.15);   % known jittered x
                jitX{i} = jx;
                scatter(ax, jx, d, dsz, colors{i}, 'filled', edg{:}, 'PickableParts','none');
            end
            % box-plot dots clickable -> unit inspector (x = jittered group position)
            bx = []; by = []; brep = [];
            for i = 1:nG
                d = data{i}(:); r = repByGrp{i}(:); jx = jitX{i}(:);
                if isempty(d), continue; end
                m = min([numel(d) numel(r) numel(jx)]);
                bx = [bx; jx(1:m)]; by = [by; d(1:m)]; brep = [brep; r(1:m)]; %#ok<AGROW>
            end
            obj.enableDotPick(ax, bx, by, brep);
            viz.plots.V01util.medianOnTop(ax);          % red median line ABOVE the dots
            ylabel(ax, ylab); xlim(ax, [0.5 nG+0.5]);
            line(ax, xlim(ax), [0 0], 'Color',[0 0 0 .3], 'LineStyle','--', 'PickableParts','none');
            if viz.paperStyle()                            % paper: colored NL/D-M x labels, keep metric ylabel, drop title
                set(ax, 'XTick', 1:nG, 'XTickLabel', repmat({''},1,nG));
                for i = 1:nG
                    text(ax, (i-0.5)/nG, -0.04, glab{i}, 'Units','normalized', 'Color', colors{i}, ...
                        'HorizontalAlignment','center', 'VerticalAlignment','top', 'FontWeight','bold', 'Clipping','off');
                end
                title(ax, '');
            else
                title(ax, ttl);
            end
            ylim(ax, ylimv);
            % MXH-vs-Mlt star: LME on the observations under Mixed-effects (same
            % model as the stats report), rank-sum of the displayed per-neuron
            % means under Mean/neuron, classic rank-sum otherwise.
            if strcmp(mode, 'lme')
                [p, isRed] = viz.plots.V01util.smBetweenMM(gMXH, gMlt, nMXH, nMlt, PK(rMXHf), PK(rMltf));
            elseif strcmp(mode, 'mean')
                [p, isRed] = viz.plots.V01util.smBetween(gMXHd, gMltd, [], [], mode);
            else
                [p, isRed] = viz.plots.V01util.smBetween(gMXH, gMlt, nMXH, nMlt, mode);
            end
            yMax = max(ylim(ax));
            brLS = '-.'; if viz.paperStyle(), brLS = '-'; end   % paper: solid significance bracket
            line(ax, [1 2], [yMax yMax]-.04*yMax, 'Color','k', 'LineStyle',brLS);
            viz.plots.V01util.drawSig(ax, 1.5, yMax-.04*yMax+.01*yMax, p, isRed, 'center');
            hold(ax,'off');
        end

        % ---- data helpers --------------------------------------------- %
        function M = layerCounts(~, G, LGn, obsIdx, unique_uu, UU)
            %LAYERCOUNTS  2x3 [Add(G2); Mlt(G1)] counts in layers 1..3.
            %   unique_uu=true counts distinct U_unity neurons, else observations.
            M = zeros(2,3);
            for L = 1:3
                il = obsIdx(LGn(obsIdx)==L);
                add = il(G(il)==2); mlt = il(G(il)==1);
                if unique_uu
                    M(1,L) = numel(unique(UU(add))); M(2,L) = numel(unique(UU(mlt)));
                else
                    M(1,L) = numel(add); M(2,L) = numel(mlt);
                end
            end
        end

        function M = lamComposition(~, UU, G, LGn, pop, nL)
            %LAMCOMPOSITION  Old UU_A_M_34: per neuron classify MXH/MUL/MXH-MUL/UCT
            %   by dominant layer. M = 4 x nL, rows [MXH; MUL; MXH-MUL; UCT].
            M = zeros(4, nL);
            if isempty(pop), return; end
            uu = UU(pop);
            [u,~,gi] = unique(uu(:), 'stable');
            for j = 1:numel(u)
                obsIdx = pop(gi==j);
                mxh = sum(G(obsIdx)==2); mlt = sum(G(obsIdx)==1);
                Lvals = LGn(obsIdx); Lvals = Lvals(isfinite(Lvals));
                if isempty(Lvals), continue; end
                domL = mode(Lvals);
                if domL < 1 || domL > nL, continue; end
                if      mxh==0 && mlt==0, r = 4;        % UCT
                elseif  mxh==mlt,         r = 3;        % MXH-MUL (tie, both > 0)
                elseif  mxh> mlt,         r = 1;        % MXH
                else,                     r = 2;        % MUL
                end
                M(r,domL) = M(r,domL) + 1;
            end
        end

        function v = classMetric(~, vals, reps, G, gclass, UU, mode)
            %CLASSMETRIC  `vals` for the gain class `gclass` (G_type) within `reps`,
            %   collapsed to one per-neuron mean under 'mean' AND 'lme' like the a4
            %   boxes (reps carry ALL observations there); other modes return the
            %   finite observations. Used by the a3 OSI-by-gain-class histograms.
            r = reps(G(reps)==gclass);
            v = vals(r); ok = isfinite(v); v = v(ok); r = r(ok);
            if any(strcmp(mode, {'mean','lme'})), v = viz.plots.V01util.aggNeuronScalar(v, UU(r)); end
            v = v(:);
        end

        function v = nz(~, v)
            v = v(:)'; v(v==0) = NaN;     % avoid Inf/NaN-by-0 ratios (old left them unguarded)
        end

        function d = foldDist(~, a, b)
            d = abs(a(:) - b(:)); d(d>180) = d(d>180) - 180;
        end

        % ---- click -> nearest-unit readout ----------------------------- %
        function onPick(obj, ax, e, X, Y, reps)
            if isempty(reps), return; end
            try, pt = e.IntersectionPoint(1:2); catch, return; end
            xl = ax.XLim; yl = ax.YLim;
            dx = (X(:)-pt(1))/max(eps,diff(xl)); dy = (Y(:)-pt(2))/max(eps,diff(yl));
            [~,k] = min(dx.^2 + dy.^2);
            obj.SelectedUnit = reps(k);
            % Ring the clicked dot on THIS axes + open the inspector only. No
            % requestRefresh: a scatter click must NOT redraw the whole figure
            % (the box plots / other panels stay put). Matches the box plots'
            % own click handler (viz.PlotTab.dotPick).
            viz.plots.V01util.highlightUnits(ax, X, Y, reps, obj.SelectedUnit);
            obj.inspectPick(reps(k));
            obj.trackPick(reps(k));
        end
    end
end
