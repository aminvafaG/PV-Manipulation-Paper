classdef LayerSelectivity02Tab < viz.PlotTab
%LAYERSELECTIVITY02TAB  Controls for Visualizer_02.m's window (f2); the actual
%   figure opens in its OWN maximized uifigure, built with the literal old pixel
%   positions, fonts (11 pt) and colors so it is 1:1 with the old f2.
%
%   The TAB shows only the controls; the global filter panel is in the toolbar.
%   Panels are placed in PIXELS at the exact old monitor fractions. NOTE: the old
%   V02 figure spans [0 0 1 .98] of screen (bottom at 0, NOT the .03 offset used
%   by the V01 windows), so panel fractions are normalized by /0.98 here.
%
%   Reproduces the old Visualizer_02 f2 window (OSI / CV / HBW across cortical
%   layers SG/G/IG, control vs laser, for ONE population PVE or PVI):
%     b1{1..3} : OSI / CV / HBW box plots, 3 layers x control(No-Laser)+laser,
%                per-layer control colors (pink/orange/cyan) + green(PVE)/blue
%                (PVI) laser, paired signrank dashed lines + stars. ylim
%                [0 1.1]/[0 1.1]/[0 60]. (Box_plot_02 positions [1 1.8 3 3.8 5 5.8].)
%     D1/D2/D3{1..3} : 9 paired control->laser dot plots (paired_plot), one per
%                metric x layer; triangles, gray connectors, mean+/-std bars,
%                signrank star. HBW ylim [0 50] (PVE) / [10 50] (PVI), else [0 1.1].
%                Arranged as a narrow VERTICAL column (SG/G/IG) to the RIGHT of each
%                box plot, mimicking the paper Fig 5 layout. (The per-metric stats
%                tables + the mean-delta table were removed as redundant -- those
%                values now live in the toggled Stats report; see reportSpec.)
%     c2{i,j}  : 4x4 tuning-by-layer grid, peak-centered window (-90..90 deg).
%                ROWS i = 4 normalizations: (1) baseline-subtracted peak-norm,
%                (2) self-peak, (3) control-peak, (4) absolute. COLS j = SG/G/IG/All
%                (col 4 = the 3 control curves overlaid, no laser). Per-PVT ylim.
%     LABELS   : T1 A-D, T2 two rotated y-labels, T3 SG/G/IG per box (layer colors),
%                T4 angle-from-peak, T5 'Layer SG/G/IG' over the grid.
%
%   DATA: OSI/CV/HBW use the FITTED metrics already in D (fitOSI/fitCV/fitHBW_L/_NL)
%   -- the f05-consistent choice (the old window read Unit.Si/HBW computed in-script
%   and MEASURED Unit.Cv, which is not loaded into D). Align_bad flags a unit
%   whose laser is not aligned to control (no analogue in the old measured HBW);
%   such units are dropped from the HBW panels (clampNeg). fitHBW itself is now
%   always >=0. Tuning curves are reproduced directly from D.fit_L / D.fit_NL
%   (control), peak-centered exactly as the old TunU_18 block.
%
%   CONTROLS: unit group (TuningG), population E/I (old PVT), repeated-obs.
%   The old window's per-firing/CV culling (I_ext/I_inh) maps to the TuningG gate;
%   choose group=ALL_UNITS + repeated-obs=All to best reproduce the old population.
%
%   See also: viz.plots.LayerNoLaser07Tab, viz.plots.V01util, analysis.tuningGroupMask

    properties
        groupDD; eiDD; repDD; statusLbl; infoLabel
        frLevelLB; lmeTuneDD            % dFr-change-level filter + mixed-effects tuning method
        reportDD                        % report content: per-test stats vs Supplementary Table 1
        FrLevels cell = {}              % selected dFr-level keys (FR_KEYS); {} = all
        OverlayMode logical = false     % part C: overlay control + 3 laser-by-level tunings
        PlotFig
        boxAx  = {}       % 1x3 OSI/CV/HBW box plots (b1)
        pairAx = {}       % 3x3 paired plots {metric, layer} (D1/D2/D3)
        tunAx  = {}       % 4x4 tuning grid {norm, col} (c2)
        tunLegAx          % legend axis: laser-by-level overlay OR the colour guide
        tunYAbs; tunYNorm % part-C tuning y-labels (dual-mode text handles)
        LayoutSpec = {}
        LastD = []; LastMask = []
    end

    properties (Constant)
        GROUPS = {'ALL_UNITS','NO_ORI_ON_PV','NO_ORI_NO_PV','ORI_ON_PV','ORI_NON_PV','ORI_NON_PV_MD','ORI_NON_PV_NL','ORI_NON_PV_U','OUTLIER'};
        REP_ITEMS = {'All (match old code)','First per neuron','Max laser power', ...
                     'Mean per neuron','Mixed-effects (stats)'};
        REP_DATA  = {'all','first','maxpow','mean','lme'};
        % dFr-change levels: E uses the first 3, I uses all 4 (extra high = facilitated >100%)
        FR_LABELS = {'Low (0-33%)','Medium (33-66%)','High (66-100%)','Extra high (>100%)'};
        FR_KEYS   = {'low','medium','high','xhigh'};
        OVERLAY_LABEL = 'Ctrl + laser by level';   % 5th dFr option: part-C overlay mode
        COLORS_NL = {[254 141 165]/255, [255 173 72]/255, [67 183 194]/255};  % SG / G / IG control
        COL_E = [0 1 0];          % PVE laser (colorsL)
        COL_I = [0 0 1];          % PVI laser
        ERRTH = [0.001 0.01 0.05];
        LAYERS  = [1 2 3];
        LAYER_LAB = {'SG','G','IG'};
        GROUP_LAB = {'Layer SG','Layer G','Layer IG'};
        MET = {'OSI','CV','HBW'};
        BOX_POS = [1 1.8 3 3.8 5 5.8];   % Box_pos = [1 2-.2 3 4-.2 5 6-.2]
        FIGFRAC = 0.98;                  % old f2 height = .98*screen
        FONT = 16; LW = 1; SZ = 11;      % fonts sized to the paper Fig 5 font:panel ratio (~1.45x the old 11); box dots use SZ
        PAIRFONT = 11;                   % the tiny paired-plot insets keep a smaller font (as in the paper) so Ctrl/Laser fit
    end

    methods
        function obj = LayerSelectivity02Tab()
            obj@viz.PlotTab('Layer selectivity (V02)');
        end

        % --------------------------------------------------------------- %
        function buildControls(obj, parent)
            g = uigridlayout(parent, [18 1]);
            g.RowHeight = repmat({'fit'}, 1, 18); g.RowHeight{6} = 100; g.RowHeight{end} = '1x';
            g.RowSpacing = 4; g.Padding = [8 8 8 8];
            uilabel(g, 'Text', 'Unit group (TuningG)');
            obj.groupDD = uidropdown(g, 'Items', obj.GROUPS, 'Value', 'ORI_NON_PV', ...
                'ValueChangedFcn', @(s,e) obj.requestRefresh());
            uilabel(g, 'Text', 'Population');
            obj.eiDD = uidropdown(g, 'Items', {'PVE (excitation)','PVI (inhibition)'}, ...
                'ItemsData', {'E','I'}, 'Value', 'E', 'ValueChangedFcn', @(s,e) obj.onEiChanged());
            uilabel(g, 'Text', 'dFr change level(s)');
            obj.frLevelLB = uilistbox(g, 'Items', obj.frLevelItems(false), 'Multiselect', 'on', ...
                'Value', '(all levels)', 'Tooltip', sprintf(['Restrict to units by laser firing-rate change (%%).\n' ...
                    'E:  0-33 low,  33-66 medium,  66-100 high.   I adds  >100 extra high.']), ...
                'ValueChangedFcn', @(s,e) obj.onFrLevelChanged());
            uilabel(g, 'Text', 'Repeated obs (per neuron)');
            obj.repDD = uidropdown(g, 'Items', obj.REP_ITEMS, 'ItemsData', obj.REP_DATA, ...
                'Value', 'all', 'ValueChangedFcn', @(s,e) obj.requestRefresh());
            uilabel(g, 'Text', 'Mixed-effects tuning');
            obj.lmeTuneDD = uidropdown(g, 'Items', {'Per-neuron mean','Per-angle model (slow)'}, ...
                'ItemsData', {'neuron','angle'}, 'Value', 'neuron', ...
                'Tooltip', ['How the AVERAGE tunings are computed when Repeated obs = ' ...
                    '"Mixed-effects (stats)". Per-neuron = each neuron once (fast); ' ...
                    'Per-angle = fitlme at every angle (rigorous, slow).'], ...
                'ValueChangedFcn', @(s,e) obj.requestRefresh());
            uilabel(g, 'Text', '');
            uibutton(g, 'Text', 'Open figure window', 'ButtonPushedFcn', @(s,e) obj.openFigure());
            obj.addReportButton(g);
            uilabel(g, 'Text', 'Report content');
            obj.reportDD = uidropdown(g, 'Items', {'Supplementary Table 1','Paired tests (per layer)'}, ...
                'ItemsData', {'supp1','paired'}, 'Value', 'supp1', ...
                'Tooltip', ['What the Stats report shows. "Supplementary Table 1" = the layer-by-layer ' ...
                    char(916) 'Fr/' char(916) 'HBW/' char(916) 'OSI/' char(916) 'CV table with unit / animal / ' ...
                    'penetration counts (honors the Repeated-obs mode). "Paired tests" = the per-layer ' ...
                    'Control-vs-Laser signed-rank/LME table across all repeated-obs modes.'], ...
                'ValueChangedFcn', @(s,e) obj.onReportContentChanged());
            obj.statusLbl = uilabel(g, 'Text', '', 'WordWrap', 'on', 'VerticalAlignment','top');
            obj.infoLabel = uilabel(g, 'Text', '', 'WordWrap', 'on', 'VerticalAlignment','top');
            obj.addInspectCheckbox(g);     % + "Track unit on click" (box dots are clickable)
            obj.addDataSelectors(g);
        end

        function buildView(obj, parent)
            obj.buildReportView(parent, sprintf(['The Visualizer-02 "layer selectivity" (f2) window ' ...
                'opens in its own maximized window (1:1 with the old figure).\n\nUse the controls on ' ...
                'the left (and the toolbar Filters) \x2014 the window refreshes live.\n\nClick "Stats ' ...
                'report" to show the layer OSI/CV/HBW Control-vs-Laser statistics here, side-by-side ' ...
                'across repeated-observation modes (incl. mixed-effects).']));
        end

        function rs = reportSpec(obj)
            if isempty(obj.LastD), rs = []; return; end
            mask = obj.LastMask; if isempty(mask), mask = true(viz.plots.V01util.nU(obj.LastD), 1); end
            mask = mask(:) & obj.frLevelMask(obj.LastD, strcmp(obj.eiDD.Value, 'I'));   % honor the dFr-level filter
            if strcmp(obj.reportDD.Value, 'supp1')
                % Supplementary Table 1: layer-by-layer dFr/dHBW/dOSI/dCV + counts,
                % honoring the current repeated-obs mode (per-neuron under Mixed-effects).
                state = struct('group', obj.groupDD.Value, 'ei', obj.eiDD.Value, ...
                               'mask', mask(:), 'layers', obj.LAYERS, 'mode', obj.repDD.Value);
                out = analysis.stats.suppTable1(obj.LastD, state);
                rs  = struct('out', out, 'header', out.header);
                return;
            end
            state = struct('group', obj.groupDD.Value, 'ei', obj.eiDD.Value, ...
                           'mask', mask(:), 'layers', obj.LAYERS);
            eiName = obj.eiDD.Items{strcmp(obj.eiDD.ItemsData, obj.eiDD.Value)};
            hdr = sprintf(['Visualizer-02 layer selectivity \x2014 %s, group %s.  Paired Wilcoxon ' ...
                'signed-rank (Control vs Laser) per layer; fitted OSI/CV/HBW.'], eiName, obj.groupDD.Value);
            rs = struct('figKey', 'V02', 'state', state, 'D', obj.LastD, 'header', hdr);
        end

        function onReportContentChanged(obj)
            if obj.ShowReport, obj.refreshReport(); end
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

        function openFigure(obj)
            if ~isempty(obj.PlotFig) && isvalid(obj.PlotFig)
                figure(obj.PlotFig); obj.drawFigure(); obj.refreshStatus(); return;
            end
            ss = get(0,'screensize'); Mx = ss(3); My = ss(4);
            obj.PlotFig = uifigure('Name','Visualizer 02 - Layer selectivity (f2)', 'Color','w', ...
                'Position', [0, 0, Mx, round(obj.FIGFRAC*My)]);
            obj.PlotFig.CloseRequestFcn = @(s,e) delete(s);
            obj.LayoutSpec = {};
            obj.createPanels();
            try, obj.PlotFig.AutoResizeChildren = 'off'; catch, end %#ok<CTCH>
            obj.PlotFig.SizeChangedFcn = @(s,e) obj.relayout();
            obj.relayout(); obj.drawFigure(); obj.refreshStatus();
        end

        function s = getControlState(obj)
            s = struct('group', obj.groupDD.Value, 'ei', obj.eiDD.Value, ...
                       'rep', obj.repDD.Value, 'showReport', obj.ShowReport, ...
                       'frLevels', {obj.FrLevels}, 'overlay', obj.OverlayMode, ...
                       'lmeTune', obj.lmeTuneDD.Value, 'reportContent', obj.reportDD.Value);
        end
        function setControlState(obj, s)
            if isfield(s,'group'), obj.setCtrl(obj.groupDD, s.group); end
            if isfield(s,'ei'),    obj.setCtrl(obj.eiDD,    s.ei);    end
            if isfield(s,'rep'),   obj.setCtrl(obj.repDD,   s.rep);   end
            if isfield(s,'lmeTune'), obj.setCtrl(obj.lmeTuneDD, s.lmeTune); end
            if isfield(s,'reportContent'), obj.setCtrl(obj.reportDD, s.reportContent); end
            if isfield(s,'overlay'), obj.OverlayMode = logical(s.overlay); end
            if isfield(s,'frLevels'), obj.FrLevels = s.frLevels; obj.applyFrLevelsToLB(); end
            if isfield(s,'showReport'), obj.ShowReport = logical(s.showReport); obj.syncReport(); end
        end
    end

    % =================================================================== %
    methods (Access = private)
        function refreshStatus(obj)
            isOpen = ~isempty(obj.PlotFig) && isvalid(obj.PlotFig);
            if isOpen, obj.statusLbl.Text = 'window: open'; else, obj.statusLbl.Text = 'window: closed (click Open)'; end
        end

        % ---- dFr-change-level filter (3 for E, 4 for I) --------------- %
        function items = frLevelItems(obj, want)
            n = 3; if want, n = 4; end                 % I adds 'extra high'
            items = [{'(all levels)'}, obj.FR_LABELS(1:n), {obj.OVERLAY_LABEL}];
        end
        function onEiChanged(obj)
            want = strcmp(obj.eiDD.Value, 'I');         % rebuild the level list for E (3) / I (4)
            keepOverlay = obj.OverlayMode;
            obj.frLevelLB.Items = obj.frLevelItems(want);
            if keepOverlay, obj.frLevelLB.Value = obj.OVERLAY_LABEL;   % overlay persists across E/I
            else, obj.frLevelLB.Value = '(all levels)'; obj.FrLevels = {}; end
            obj.requestRefresh();
        end
        function onFrLevelChanged(obj)
            v = obj.frLevelLB.Value;
            if ischar(v), v = {v}; elseif isstring(v), v = cellstr(v); end
            if any(strcmp(v, obj.OVERLAY_LABEL))        % overlay mode is exclusive
                obj.OverlayMode = true; obj.FrLevels = {};
                obj.frLevelLB.Value = obj.OVERLAY_LABEL;
                obj.requestRefresh(); return;
            end
            obj.OverlayMode = false;
            if isempty(v) || any(strcmp(v, '(all levels)'))
                obj.FrLevels = {};
            else
                keys = {};
                for k = 1:numel(v)
                    idx = find(strcmp(obj.FR_LABELS, v{k}), 1);
                    if ~isempty(idx), keys{end+1} = obj.FR_KEYS{idx}; end %#ok<AGROW>
                end
                obj.FrLevels = keys;
            end
            obj.requestRefresh();
        end
        function applyFrLevelsToLB(obj)
            if isempty(obj.frLevelLB) || ~isvalid(obj.frLevelLB), return; end
            obj.frLevelLB.Items = obj.frLevelItems(strcmp(obj.eiDD.Value, 'I'));
            if obj.OverlayMode, obj.frLevelLB.Value = obj.OVERLAY_LABEL; return; end
            if isempty(obj.FrLevels), obj.frLevelLB.Value = '(all levels)'; return; end
            labs = {};
            for k = 1:numel(obj.FrLevels)
                idx = find(strcmp(obj.FR_KEYS, obj.FrLevels{k}), 1);
                if ~isempty(idx), labs{end+1} = obj.FR_LABELS{idx}; end %#ok<AGROW>
            end
            labs = labs(ismember(labs, obj.frLevelLB.Items));
            if isempty(labs), obj.frLevelLB.Value = '(all levels)'; obj.FrLevels = {};
            else,             obj.frLevelLB.Value = labs; end
        end
        function m = frLevelMask(obj, D, want)
            N = viz.plots.V01util.nU(D);
            if obj.OverlayMode || isempty(obj.FrLevels), m = true(N,1); return; end   % overlay uses all units (bands split inside the tuning grid)
            dfr = 100 * viz.plots.V01util.colv(D, 'Delta_Fr', N);   % laser FR change (%)
            m = false(N,1);
            for k = 1:numel(obj.FrLevels)
                switch obj.FrLevels{k}                  % E bands are negative (suppressed), I positive
                    case 'low',    if want, m = m | (dfr >  0 & dfr <=  33); else, m = m | (dfr >= -33 & dfr <  0); end
                    case 'medium', if want, m = m | (dfr > 33 & dfr <=  66); else, m = m | (dfr >= -66 & dfr < -33); end
                    case 'high',   if want, m = m | (dfr > 66 & dfr <= 100); else, m = m | (dfr < -66); end
                    case 'xhigh',  if want, m = m | (dfr > 100); end       % I only
                end
            end
            m = m(:);
        end

        % ---- mixed-effects tuning mode + per-curve mean/SE ------------ %
        function tf = useNeuronLme(obj)
            tf = strcmp(obj.repDD.Value, 'lme') && strcmp(obj.lmeTuneDD.Value, 'neuron');
        end
        function tf = useAngleLme(obj)
            tf = strcmp(obj.repDD.Value, 'lme') && strcmp(obj.lmeTuneDD.Value, 'angle');
        end
        function tf = useNeuronCurveAgg(obj)
            %USENEURONCURVEAGG  Collapse each neuron's observation-curves to its MEAN
            %   before the population mean/SEM -- for 'Mean per neuron' AND Mixed-
            %   effects+per-neuron (both need every observation, then a per-neuron
            %   mean, matching the stat reports). 'lme'+angle uses lmePerAngle inside
            %   curveMS instead, so it is NOT included here.
            tf = strcmp(obj.repDD.Value, 'mean') || obj.useNeuronLme();
        end
        function tf = curveObsMode(obj)
            %CURVEOBSMODE  True when the TUNING CURVES need every observation per
            %   neuron (so per-neuron aggregation can run): 'mean' and 'lme'. For
            %   'first'/'maxpow'/'all' the mode's own layerReps rows are used as-is.
            tf = any(strcmp(obj.repDD.Value, {'mean','lme'}));
        end
        function [mu, se] = curveMS(obj, M, neur)
            %CURVEMS  Population mean +/- SE of the P x K curve matrix M. Non-LME and
            %   "per-neuron" LME (M pre-aggregated) -> plain mean +/- SEM over columns
            %   (std norm 1, matching the old std(...,1,4)). "Per-angle" LME -> fitlme
            %   per row (slow). neur is the per-observation neuron id (per-angle only).
            if obj.useAngleLme()
                [mu, se] = viz.plots.V01util.lmePerAngle(M, neur);
            else
                K = max(size(M,2), 1);
                mu = mean(M, 2); se = std(M, 1, 2) / sqrt(K);
            end
        end

        % ---- panel construction --------------------------------------- %
        function createPanels(obj)
            % box plots b1{1}=OSI, b1{2}=CV, b1{3}=HBW
            obj.boxAx = {obj.addAx(.02,.67,.30,.30), ...
                         obj.addAx(.45,.67,.30,.30), ...
                         obj.addAx(.45,.20,.30,.30)};
            % paired plots (D1/D2/D3): a NARROW VERTICAL COLUMN to the RIGHT of each
            % box plot -- SG (top) / G (middle) / IG (bottom) -- mimicking the paper
            % Fig 5 arrangement (each metric's box carries its 3 paired insets beside it).
            obj.pairAx = cell(3,3);
            pcW = 0.085; pcH = 0.11; dY = 0.117;      % TALL paired insets (~their original .12 height), stacked
            colX  = [0.345, 0.775, 0.775];            % right of the OSI / CV / HBW boxes
            baseY = [0.67,  0.67,  0.20];             % each box's bottom (OSI/CV top row, HBW mid)
            for mi = 1:3
                for li = 1:3                          % li=1 SG (top) .. li=3 IG (bottom); the stack spills a
                    obj.pairAx{mi,li} = obj.addAx(colX(mi), baseY(mi)+0.18-(li-1)*dY, pcW, pcH);   % touch below each box
                end
            end
            for k = 1:numel(obj.pairAx), obj.pairAx{k}.FontSize = obj.PAIRFONT; end   % smaller font for the narrow insets
            % 4x4 tuning grid c2{i,j}: i = norm row (1..4), j = layer col (SG/G/IG/All)
            obj.tunAx = cell(4,4);
            for i = 1:4
                for j = 1:4
                    obj.tunAx{i,j} = obj.addAx(.04+.09*(j-1), .39-.11*(i-1), .09, .11);
                end
            end
            % legend for the laser-by-level overlay mode / colour guide, in the free
            % strip above the tuning grid.
            obj.tunLegAx = uiaxes(obj.PlotFig); obj.tunLegAx.Units = 'pixels';
            obj.tunLegAx.Visible = 'off'; obj.tunLegAx.XLim = [0 1]; obj.tunLegAx.YLim = [0 1];
            obj.LayoutSpec{end+1} = {obj.tunLegAx, [.13 .52 .12 .14]};   % moved LEFT to free room for the taller OSI paired column
            obj.createLabels();
        end

        function ax = addAx(obj, fx, fy, fw, fh)
            ax = uiaxes(obj.PlotFig); ax.Units = 'pixels'; ax.FontUnits = 'points';
            ax.FontSize = obj.FONT; ax.LineWidth = obj.LW; ax.XTickLabelRotation = 0;
            obj.LayoutSpec{end+1} = {ax, [fx fy fw fh]};
        end

        function h = addLabel(obj, fx, fy, fw, fh, txt, rot, col, fsz)
            if nargin < 8 || isempty(col), col = 'k'; end
            if nargin < 9 || isempty(fsz), fsz = obj.FONT; end
            ax = uiaxes(obj.PlotFig); ax.Units = 'pixels'; ax.Visible = 'off';
            h = text(ax, 0, 0, txt, 'Color', col, 'Rotation', rot, 'FontUnits','points', 'FontSize', fsz);
            obj.LayoutSpec{end+1} = {ax, [fx fy fw fh]};
        end

        function createLabels(obj)
            % T1 panel letters A-D (2x font)
            locs = {[0 .95],[.43 .95],[0 .5],[.43 .5]}; abcs = {'A','B','C','D'};
            for i = 1:4, obj.addLabel(locs{i}(1), locs{i}(2), .10, .10, abcs{i}, 0, 'k', obj.FONT*2); end
            % T2 rotated y-labels for the tuning grid (dual-mode via the master key,
            % retuned in retuneLabels: paper Fig 5 wording vs the original wording).
            obj.tunYAbs  = obj.addLabel(.02, .05, .05, .20, 'Absolute firing rate (sp/s)', 90);
            obj.tunYNorm = obj.addLabel(.02, .27, .05, .20, 'Normalized firing rate',      90);
            % T3 SG/G/IG layer labels above each box plot, in layer colors
            b1f = {[.02 .67],[.45 .67],[.45 .20]};
            for j = 1:3
                for i = 1:3
                    obj.addLabel(b1f{j}(1)+(i*.0917-.0367), b1f{j}(2)+.02, .05, .05, ...
                        obj.LAYER_LAB{i}, 0, obj.layerCol(i));
                end
            end
            % T4 angle-from-peak axis label
            obj.addLabel(.15, .02, .12, .05, 'Angle from peak ( \circ )', 0);
            % T5 'Layer SG/G/IG' over the tuning-grid columns
            for i = 1:3
                obj.addLabel(.33-i*.09, .50, .10, .05, obj.GROUP_LAB{4-i}, 0, 'k');
            end
        end

        function relayout(obj)
            if isempty(obj.PlotFig) || ~isvalid(obj.PlotFig), return; end
            pos = obj.PlotFig.Position; W = pos(3); H = pos(4); f = obj.FIGFRAC;
            if W < 30 || H < 30, return; end
            for k = 1:numel(obj.LayoutSpec)
                h = obj.LayoutSpec{k}{1}; fr = obj.LayoutSpec{k}{2};
                if ~isvalid(h), continue; end
                try, h.Position = [fr(1)*W, (fr(2)/f)*H, max(2,fr(3)*W), max(2,(fr(4)/f)*H)]; catch, end %#ok<CTCH>
            end
        end

        % ---- main draw ------------------------------------------------ %
        function drawFigure(obj)
            D = obj.LastD; mask = obj.LastMask;
            if isempty(D) || isempty(obj.PlotFig) || ~isvalid(obj.PlotFig), return; end
            obj.relayout(); obj.clearAll(); obj.retuneLabels();   % part-C y-labels track the master style key
            if ~isfield(D,'fitOSI_NL') || ~isfield(D,'fit_NL')
                title(obj.boxAx{1}, 'Missing fitOSI_NL / fit_NL'); return;
            end
            try, grpMask = analysis.tuningGroupMask(D, obj.groupDD.Value);
            catch err, title(obj.boxAx{1}, ['Group error: ' err.message]); return; end

            colv = @viz.plots.V01util.colv;
            isI  = viz.plots.V01util.isInhib(D);
            want = strcmp(obj.eiDD.Value, 'I');                 % old PVT
            sel  = mask(:) & grpMask(:) & (isI == want) & obj.frLevelMask(D, want);
            LGn  = viz.plots.V01util.layerNum(D);
            lcol = obj.lcolFor(want);

            % Per-neuron modes assign each neuron to ONE layer (its dominant/mode
            % layer, as in Visualizer_03 / GainLaminar03 lamComposition), so a neuron
            % spanning two layers is counted once -- not once per layer. 'all'/'lme'
            % stay observation-level (the old f2 applied no dedup).
            repByLayer = viz.plots.V01util.layerReps(D, find(sel), LGn, obj.repDD.Value, obj.LAYERS);
            if strcmp(obj.repDD.Value, 'mean')
                % 'Mean per neuron': dominant-layer assignment kept, but the paired
                % panels get ALL of each neuron's rows IN that layer, so its value
                % is the MEAN of its recordings (layerReps' 'mean' representative
                % is the first row -- values there would be firsts).
                UUv = viz.plots.V01util.colv(D, 'U_unity');
                for li = 1:numel(repByLayer)
                    rows = find(sel & LGn(:) == obj.LAYERS(li) & ismember(UUv, UUv(repByLayer{li})));
                    repByLayer{li} = rows(:);
                end
            end

            % U_unity per representative row, grouped by layer EXACTLY like
            % repByLayer (same rows, same order) so the significance helpers can
            % honor the repeated-obs dropdown (incl. mixed-effects).
            mode = obj.repDD.Value;
            UU = colv(D, 'U_unity');
            neurByLayer = cell(1,3);
            for li = 1:3, neurByLayer{li} = UU(repByLayer{li}); end

            % ---- box plots + paired plots + stats tables, per metric -------
            % Under Mixed-effects the DISPLAYED data is collapsed to one per-neuron
            % mean (each neuron once, within its layer), matching the per-neuron
            % tuning curves; the significance star/p keeps the LME model fitted on
            % the full unit x intensity observations (precomputed here, observation-
            % level, so the box/paired/table all share the same per-layer p).
            pk = viz.plots.V01util.penKey(D);
            aggN = any(strcmp(mode, {'mean','lme'}));
            deltas = nan(3,3);                               % deltas(layer, metric) = mean(Laser - Control)
            for mi = 1:3
                cfg = obj.metCfg(obj.MET{mi}, want);
                nlv = colv(D, cfg.NL); lv = colv(D, cfg.L);
                if cfg.clampNeg                              % HBW: drop not-aligned units (was fitHBW<0)
                    badU = colv(D,'Align_bad') == 1;
                    nlv(badU) = NaN; lv(badU) = NaN;
                end
                dispData = cell(1,6); dispRep = cell(1,3);
                pPair = nan(1,3); redPair = false(1,3);
                for li = 1:3
                    rp = repByLayer{li}; nu = neurByLayer{li};
                    cObs = nlv(rp); lObs = lv(rp);           % observation-level control / laser
                    if aggN                                  % collapse to one value per neuron
                        [cD, ~, rD] = viz.plots.V01util.aggNeuronScalar(cObs, nu, rp);
                        lD = viz.plots.V01util.aggNeuronScalar(lObs, nu);
                    else
                        cD = cObs; lD = lObs; rD = rp;
                    end
                    % star: LME on the observations under 'lme' (laser first ->
                    % resp~cond direction); signrank on the displayed per-neuron
                    % means under 'mean'; classic signrank otherwise.
                    if strcmp(mode, 'mean')
                        [pPair(li), redPair(li)] = viz.plots.V01util.smPaired(lD, cD, [], 'all');
                    else
                        [pPair(li), redPair(li)] = viz.plots.V01util.smPaired(lObs, cObs, nu, mode, pk(rp));
                    end
                    dispData{2*li-1} = cD; dispData{2*li} = lD; dispRep{li} = rD;
                    dd = lD - cD; deltas(li, mi) = mean(dd(isfinite(dd)));
                end
                colors = {obj.layerCol(1), lcol, obj.layerCol(2), lcol, obj.layerCol(3), lcol};
                obj.drawBoxCL(obj.boxAx{mi}, dispData, colors, obj.MET{mi}, cfg.boxYlim, dispRep, pPair, redPair, deltas(:,mi));
                for li = 1:3
                    obj.drawPairedCL(obj.pairAx{mi,li}, dispData{2*li-1}, dispData{2*li}, ...
                        obj.layerCol(li), lcol, obj.MET{mi}, obj.GROUP_LAB{li}, cfg.pairYlim, ...
                        pPair(li), redPair(li));
                end
            end

            % ---- 4x4 tuning grid -------------------------------------------
            % Population tuning curves honor the stat option like the reports: 'mean'
            % and 'lme' both need EVERY observation per neuron (layerReps collapses
            % 'mean' to first-obs, so re-derive all-obs rows); the per-neuron curve
            % mean then runs in drawTuningGrid (useNeuronCurveAgg). 'first'/'maxpow'/
            % 'all' reuse repByLayer as-is.
            if obj.curveObsMode()
                tunRep = viz.plots.V01util.layerReps(D, find(sel), LGn, 'all', obj.LAYERS);
            else
                tunRep = repByLayer;
            end
            obj.drawTuningGrid(tunRep, want);
            if ~obj.OverlayMode, obj.drawColorGuide(); end   % colour guide (overlay mode uses its own legend)

            if aggN                                          % Mixed-effects: count distinct neurons
                nlab = 'neurons';
                nSG = numel(unique(neurByLayer{1})); nG = numel(unique(neurByLayer{2})); nIG = numel(unique(neurByLayer{3}));
            else
                nlab = 'units';
                nSG = numel(repByLayer{1}); nG = numel(repByLayer{2}); nIG = numel(repByLayer{3});
            end
            obj.infoLabel.Text = sprintf(['group %s   %s   layer N (SG/G/IG, %s): %d/%d/%d\n' ...
                'OSI/CV/HBW are FITTED values. ALL_UNITS + All best reproduces the old f2.'], ...
                obj.groupDD.Value, obj.eiDD.Value, nlab, nSG, nG, nIG);
        end

        function clearAll(obj)
            for k = 1:numel(obj.boxAx),  if isvalid(obj.boxAx{k}),  cla(obj.boxAx{k});  end, end
            for k = 1:numel(obj.pairAx), if isvalid(obj.pairAx{k}), cla(obj.pairAx{k}); end, end
            for k = 1:numel(obj.tunAx),  if isvalid(obj.tunAx{k}),  cla(obj.tunAx{k});  end, end
            if ~isempty(obj.tunLegAx) && isvalid(obj.tunLegAx), cla(obj.tunLegAx); obj.tunLegAx.Visible = 'off'; end
        end

        function c = lcolFor(obj, want)
            if want, c = obj.COL_I; else, c = obj.COL_E; end
        end
        function c = layerCol(obj, i)
            %LAYERCOL  Cortical-layer color. Paper Fig 5 = saturated SG magenta / G
            %   orange / IG cyan; otherwise the muted original COLORS_NL.
            if viz.paperStyle()
                p = {[1 0 1], [1 0.5 0], [0 1 1]}; c = p{min(max(i,1),3)};
            else
                c = obj.COLORS_NL{i};
            end
        end

        function cfg = metCfg(~, name, isI)
            switch upper(name)
                case 'CV'
                    cfg = struct('L','fitCV_L', 'NL','fitCV_NL', 'boxYlim',[0 1.1], 'pairYlim',[0 1.1], 'clampNeg',false);
                case 'HBW'
                    if isI, py = [10 50]; else, py = [0 50]; end
                    cfg = struct('L','fitHBW_L','NL','fitHBW_NL','boxYlim',[0 60], 'pairYlim',py, 'clampNeg',true);
                otherwise
                    cfg = struct('L','fitOSI_L','NL','fitOSI_NL','boxYlim',[0 1.1], 'pairYlim',[0 1.1], 'clampNeg',false);
            end
        end

        % ---- box plot: 6 boxes (3 layers x No-Laser/Laser) -------------- %
        function drawBoxCL(obj, ax, data, colors, metName, ylimVal, repByLayer, pPair, redPair, deltaMet)
            % Reproduces Box_plot_02 (custom positions/widths, FaceAlpha .05 patches,
            % sz/2 jittered scatter, zero line) + the signrank dashed lines/stars.
            % data / repByLayer are the DISPLAY units (per-neuron means under
            % Mixed-effects); pPair/redPair are the per-layer significance (LME-on-
            % observations under Mixed-effects), precomputed by drawFigure.
            pos = obj.BOX_POS;
            glab = {'1SGc','2SGl','3Gc','4Gl','5IGc','6IGl'};   % unique, in display order
            vals = []; grp = {};
            for i = 1:6
                d = data{i}; if isempty(d), d = 0; end          % old Box_plot_02 empty->0
                d = d(:);
                vals = [vals; d]; grp = [grp; repmat(glab(i), numel(d), 1)]; %#ok<AGROW>
            end
            hold(ax,'on');
            try
                hbp = boxplot(ax, vals, grp, 'Colors','k', 'Symbol','', ...
                    'GroupOrder', glab, 'Positions', pos, 'Widths', 0.5);
                set(hbp, 'PickableParts','none');               % box lines must not swallow clicks on interior dots
                h = findobj(ax, 'Tag', 'Box');
                for j = 1:numel(h)
                    patch(ax, get(h(j),'XData'), get(h(j),'YData'), colors{numel(h)-j+1}, 'FaceAlpha', .05, 'PickableParts','none');
                end
                if viz.paperStyle()
                    set(findobj(ax,'Tag','Median'), 'Color',[1 0 0], 'LineWidth',1);   % paper: red median
                    set(findobj(ax,'Tag','Upper Whisker'), 'LineStyle','-'); set(findobj(ax,'Tag','Lower Whisker'), 'LineStyle','-');   % paper: solid whiskers
                end
            catch
            end
            edg = {}; dsz = obj.SZ/2;
            if viz.paperStyle()
                edg = {'MarkerEdgeColor','w', 'LineWidth',0.75};      % paper: visible white ring per dot
                dsz = viz.plots.V01util.paperDotAreaBox(ax, obj.BOX_POS(end)-obj.BOX_POS(1)+1, 0.10);   % paper Fig 5: bigger box dots (0.10 not 0.06 -- these 6-box panels are wider than the paper's, so box-width sizing looked too small vs the panel; PDF-matched to dot/axis ~0.022)
            end
            jitX = cell(1,6);
            for i = 1:6
                d = data{i}; if isempty(d), d = 0; end; d = d(:);
                jx = viz.plots.V01util.boxJitterX(pos(i), numel(d), 0.15);   % known jittered x
                jitX{i} = jx;
                scatter(ax, jx, d, dsz, colors{i}, 'filled', edg{:}, 'PickableParts','none');
            end
            % box-plot dots clickable -> unit inspector (box i -> layer ceil(i/2))
            bx = []; by = []; brep = [];
            for i = 1:6
                d = data{i}(:);
                if isempty(d), continue; end
                r = repByLayer{ceil(i/2)}(:); jx = jitX{i}(:);
                m = min([numel(d) numel(r) numel(jx)]);
                bx = [bx; jx(1:m)]; by = [by; d(1:m)]; brep = [brep; r(1:m)]; %#ok<AGROW>
            end
            obj.enableDotPick(ax, bx, by, brep);
            viz.plots.V01util.medianOnTop(ax);          % red median line ABOVE the dots
            if viz.paperStyle() && strcmpi(metName,'HBW'), ylabel(ax, 'HBW (\circ)'); else, ylabel(ax, metName); end
            xlim(ax, [pos(1)-0.5, pos(end)+0.5]);               % Box_dist = 1
            line(ax, xlim(ax), [0 0], 'Color', [0 0 0 .3], 'LineStyle', '--', 'PickableParts','none');
            if viz.paperStyle()                                 % paper: Ctrl / colored-Laser ticks, drop metric title
                lcol = colors{2}; lasTk = sprintf('\\color[rgb]{%g,%g,%g}Laser', lcol(1), lcol(2), lcol(3));
                set(ax, 'XTick', pos, 'TickLabelInterpreter','tex', 'XTickLabel', repmat({'Ctrl', lasTk}, 1, 3));
                title(ax, '');
            else
                title(ax, [metName ' - Control vs Laser']);
                set(ax, 'XTick', pos, 'XTickLabel', {'No-Laser','Laser','No-Laser','Laser','No-Laser','Laser'});
            end
            ylim(ax, ylimVal);

            gcs = {pos(1:2), pos(3:4), pos(5:6)}; yMax = max(ylim(ax));
            brLS = '-.'; if viz.paperStyle(), brLS = '-'; end   % paper: solid significance bracket
            for i = 1:3
                % per-layer paired significance precomputed by drawFigure (LME on
                % observations under Mixed-effects; the dots are the per-neuron means).
                line(ax, gcs{i}, [yMax yMax]-.04*yMax, 'Color','k', 'LineStyle',brLS);
                viz.plots.V01util.drawSig(ax, mean(gcs{i}), yMax-.04*yMax+.01*yMax, pPair(i), redPair(i), 'center');
            end
            % per-layer mean Delta (Laser - Control) printed IN the axes so it lands in
            % the PDF export (the deltaTbl uitable does not export). One per layer,
            % centred under each Ctrl/Laser pair, in the layer colour.
            if nargin >= 10 && ~isempty(deltaMet)
                dec = 2; if strcmpi(metName,'HBW'), dec = 1; end
                mids = [mean(pos(1:2)), mean(pos(3:4)), mean(pos(5:6))];
                yTxt = yMax - 0.05*yMax;                       % stick JUST UNDER the significance bracket (line at yMax-.04*yMax), top-aligned
                for i = 1:3
                    v = deltaMet(i); if ~isfinite(v), continue; end
                    text(ax, mids(i), yTxt, sprintf('\\Delta%+.*f', dec, v), 'Color', colors{2*i-1}, ...
                        'FontSize', obj.FONT-3, 'FontWeight','bold', 'HorizontalAlignment','center', ...
                        'VerticalAlignment','top', 'BackgroundColor',[1 1 1], 'Margin',1, 'PickableParts','none');
                end
            end
            hold(ax,'off');
        end

        % ---- paired plot (paired_plot.m) ------------------------------- %
        function drawPairedCL(obj, ax, g1, g2, col1, col2, metName, ttl, ylimVal, pSig, isRed)
            % g1=control, g2=laser are the DISPLAY units (per-neuron means under
            % Mixed-effects); pSig/isRed are the per-layer significance precomputed
            % by drawFigure (LME on observations under Mixed-effects).
            ok = isfinite(g1) & isfinite(g2); g1 = g1(ok); g2 = g2(ok); g1 = g1(:); g2 = g2(:);
            hold(ax,'on'); s = obj.SZ/2;                        % old passes sz/2
            for k = 1:numel(g1)
                plot(ax, [1 2], [g1(k) g2(k)], '-', 'Color', [0.6 0.6 0.6 .3], 'LineWidth', 1);
            end
            if ~isempty(g1)
                scatter(ax, ones(numel(g1),1),   g1, 2*s, col1, '^', 'filled', 'MarkerFaceAlpha', 0.3);
                scatter(ax, 2*ones(numel(g2),1), g2, 2*s, col2, '^', 'filled', 'MarkerFaceAlpha', 0.3);
                errorbar(ax, .7,  mean(g1), std(g1), 'k', 'LineWidth',0.5, 'CapSize',s, 'Marker','^', 'MarkerSize',s, 'MarkerFaceColor',col1);
                errorbar(ax, 2.3, mean(g2), std(g2), 'k', 'LineWidth',0.5, 'CapSize',s, 'Marker','^', 'MarkerSize',s, 'MarkerFaceColor',col2);
            end
            ylim(ax, ylimVal); xlim(ax, [0 3]);
            if viz.paperStyle()                                 % paper: Ctrl/Laser ticks, layer id in layer color, HBW degree
                set(ax, 'XTick', [1 2], 'XTickLabel', {'Ctrl','Laser'});
                yl = metName; if strcmpi(metName,'HBW'), yl = 'HBW (\circ)'; end
                ylabel(ax, yl); title(ax, strrep(ttl,'Layer ',''), 'Color', col1);
            else
                set(ax, 'XTick', [1 2], 'XTickLabel', {'C','L'});
                ylabel(ax, metName); title(ax, ttl);
            end
            yMax = max(ylim(ax));
            line(ax, [1 2], [yMax yMax]-.04*yMax, 'Color','k');
            viz.plots.V01util.drawSig(ax, 1.5, yMax-.04*yMax+.01*yMax, pSig, isRed, 'center');
            hold(ax,'off');
        end

        % ---- 4x4 tuning grid ------------------------------------------- %
        function drawTuningGrid(obj, repByLayer, want)
            D = obj.LastD;
            if ~isfield(D,'fit_L') || ~isfield(D,'fit_NL'), return; end
            lcol = obj.lcolFor(want); fitL = D.fit_L; fitNL = D.fit_NL;
            UU = viz.plots.V01util.colv(D, 'U_unity');
            % A{li} = per-observation centered curves. Under mixed-effects "per-neuron"
            % each neuron's observations are averaged first, so the population mean/SEM
            % below is over NEURONS (see STATS_MIXED_EFFECTS.md sec 3e). neur{li} is
            % the per-observation neuron id, used by the "per-angle" mixed model.
            A = cell(1,3); neur = cell(1,3);
            for li = 1:3
                A{li}    = obj.tunNorms(fitL, fitNL, repByLayer{li});
                neur{li} = UU(repByLayer{li});
                if obj.useNeuronCurveAgg(), A{li} = viz.plots.V01util.aggNeuronCurves(A{li}, neur{li}); end
            end
            if obj.OverlayMode                                   % control (all) + 3 laser-by-level curves per subplot
                obj.drawTuningOverlay(A, neur, repByLayer, want, fitL, fitNL, UU);
                return;
            end
            X = (1:180)';
            for t = 1:4
                yl = obj.gridYlim(t, want);
                % cols 1..3 = SG/G/IG : laser (drawn first) + control overlaid
                for li = 1:3
                    ax = obj.tunAx{t,li}; hold(ax,'on'); K = size(A{li},4);
                    if K > 0
                        [YL, SEL] = obj.curveMS(squeeze(A{li}(t,1,:,:)), neur{li});
                        viz.plots.V01util.plotSE(ax, X, YL, SEL, lcol, lcol, 0.2, 0.5);
                        [YC, SEC] = obj.curveMS(squeeze(A{li}(t,2,:,:)), neur{li});
                        viz.plots.V01util.plotSE(ax, X, YC, SEC, obj.layerCol(li), obj.layerCol(li), 0.4, 0.5);
                    end
                    obj.styleTunAx(ax, yl);
                end
                % col 4 = All : the 3 control curves overlaid (IG..SG, SG on top), no laser
                ax4 = obj.tunAx{t,4}; hold(ax4,'on');
                for li = 3:-1:1
                    K = size(A{li},4); if K == 0, continue; end
                    [YC, SEC] = obj.curveMS(squeeze(A{li}(t,2,:,:)), neur{li});
                    viz.plots.V01util.plotSE(ax4, X, YC, SEC, obj.layerCol(li), obj.layerCol(li), 0.4, 0.5);
                end
                obj.styleTunAx(ax4, yl);
                obj.applyRowYlim(t, want);           % single-level options: dynamic per-row shared ylim
            end
        end

        function applyRowYlim(obj, t, want)
            %APPLYROWYLIM  For a SINGLE dFr-level selection (not "(all levels)", not
            %   the overlay), replace the fixed per-row ylim with a DYNAMIC one shared
            %   by all 4 columns of the row, covering every curve+SEM shadow so the
            %   subset's tunings are not clipped and the columns stay comparable.
            if isempty(obj.FrLevels), return; end    % "(all levels)" / overlay keep the fixed gridYlim
            lo = inf; hi = -inf;
            for c = 1:4
                ax = obj.tunAx{t,c}; if isempty(ax) || ~isvalid(ax), continue; end
                kids = [findobj(ax,'Type','line'); findobj(ax,'Type','patch')];
                for h = kids'
                    yd = get(h,'YData'); yd = yd(isfinite(yd));
                    if ~isempty(yd), lo = min(lo, min(yd)); hi = max(hi, max(yd)); end
                end
            end
            if ~isfinite(lo) || ~isfinite(hi) || hi <= lo, return; end
            pad = 0.04*(hi-lo); yl = [lo-pad, hi+pad];
            for c = 1:4, if isvalid(obj.tunAx{t,c}), ylim(obj.tunAx{t,c}, yl); end, end
        end

        % ---- overlay mode: control (all) + 3 laser-by-level curves ----- %
        function drawTuningOverlay(obj, A, neur, repByLayer, want, fitL, fitNL, UU)
            % Each subplot shows the ALL-levels control tuning (same as the "(all
            % levels)" option) plus 3 laser tunings, one per dFr manipulation band
            % (Low/Medium/High), drawn in light->dark shades of the laser colour.
            lcol = obj.lcolFor(want);
            keys = {'low','medium','high'}; labs = {'Low','Medium','High'};
            shades = obj.levelShades(lcol, 3);
            X = (1:180)';
            allReps = [repByLayer{1}(:); repByLayer{2}(:); repByLayer{3}(:)];   % col-4 = all layers
            Aall = obj.tunNorms(fitL, fitNL, allReps); neurAll = UU(allReps);
            if obj.useNeuronCurveAgg(), Aall = viz.plots.V01util.aggNeuronCurves(Aall, neurAll); end
            % per-(column, band) laser curves; column 1..3 = SG/G/IG, 4 = All
            Lv = cell(4,3); Nv = cell(4,3);
            for b = 1:3
                bm = obj.frBand(obj.LastD, keys{b}, want);
                for li = 1:3
                    br = repByLayer{li}(bm(repByLayer{li}));
                    Lv{li,b} = obj.tunNorms(fitL, fitNL, br); Nv{li,b} = UU(br);
                    if obj.useNeuronCurveAgg(), Lv{li,b} = viz.plots.V01util.aggNeuronCurves(Lv{li,b}, Nv{li,b}); end
                end
                bra = allReps(bm(allReps));
                Lv{4,b} = obj.tunNorms(fitL, fitNL, bra); Nv{4,b} = UU(bra);
                if obj.useNeuronCurveAgg(), Lv{4,b} = viz.plots.V01util.aggNeuronCurves(Lv{4,b}, Nv{4,b}); end
            end
            for t = 1:4
                yl = obj.gridYlim(t, want);
                for col = 1:4
                    ax = obj.tunAx{t,col}; hold(ax,'on');
                    if col <= 3, Ac = A{col}; nc = neur{col}; ccol = obj.layerCol(col);
                    else,        Ac = Aall;   nc = neurAll;   ccol = [.2 .2 .2]; end
                    if size(Ac,4) > 0                            % control (all levels)
                        [YC, SEC] = obj.curveMS(squeeze(Ac(t,2,:,:)), nc);
                        viz.plots.V01util.plotSE(ax, X, YC, SEC, ccol, ccol, 0.25, 1.0);
                    end
                    for b = 1:3                                  % 3 laser bands (line + SEM shadow, as in single-level)
                        Ab = Lv{col,b}; if size(Ab,4) == 0, continue; end
                        [YL, SEL] = obj.curveMS(squeeze(Ab(t,1,:,:)), Nv{col,b});
                        viz.plots.V01util.plotSE(ax, X, YL, SEL, shades{b}, shades{b}, 0.2, 1.2);
                    end
                    obj.styleTunAx(ax, yl);
                end
            end
            obj.drawOverlayLegend(shades, labs);
        end

        function m = frBand(~, D, key, want)
            %FRBAND  Logical mask for ONE dFr manipulation band (3 bands cover all
            %   units: for I, 'high' is >66% so xhigh folds in).
            N = viz.plots.V01util.nU(D);
            dfr = 100 * viz.plots.V01util.colv(D, 'Delta_Fr', N);
            switch key
                case 'low',    if want, m = dfr >  0 & dfr <=  33; else, m = dfr >= -33 & dfr <   0; end
                case 'medium', if want, m = dfr > 33 & dfr <=  66; else, m = dfr >= -66 & dfr < -33; end
                case 'high',   if want, m = dfr > 66;              else, m = dfr < -66;              end
                otherwise,     m = false(N,1);
            end
            m = m(:);
        end

        function sh = levelShades(~, lcol, n)
            %LEVELSHADES  n light->dark shades of the laser colour (low->high).
            sh = cell(1,n);
            if n == 3
                sh = {0.5*lcol + 0.5*[1 1 1], lcol, 0.55*lcol};
            else
                for k = 1:n, f = (k-1)/max(n-1,1); sh{k} = (0.5+0.5*f)*lcol + (0.5-0.5*f)*[1 1 1]; end
            end
        end

        function drawOverlayLegend(obj, shades, labs)
            ax = obj.tunLegAx; if isempty(ax) || ~isvalid(ax), return; end
            cla(ax); ax.XLim = [0 1]; ax.YLim = [0 1]; hold(ax,'on');
            ys = linspace(0.85, 0.15, 4); fs = obj.FONT - 3;
            plot(ax, [0.05 0.28], [ys(1) ys(1)], 'Color',[.2 .2 .2], 'LineWidth',2.5);
            text(ax, 0.34, ys(1), 'Control (all)', 'FontSize',fs, 'VerticalAlignment','middle');
            for b = 1:3
                plot(ax, [0.05 0.28], [ys(b+1) ys(b+1)], 'Color',shades{b}, 'LineWidth',2.5);
                text(ax, 0.34, ys(b+1), [labs{b} ' laser'], 'FontSize',fs, 'VerticalAlignment','middle');
            end
            hold(ax,'off');
        end

        function drawColorGuide(obj)
            %DRAWCOLORGUIDE  Colour key for part C (paper Fig 5): the per-layer control
            %   colours (SG/G/IG ctrl) + the laser colours (PVA green / PVI blue).
            %   Drawn in tunLegAx when NOT in overlay mode (overlay uses its own legend).
            ax = obj.tunLegAx; if isempty(ax) || ~isvalid(ax), return; end
            cla(ax); ax.Visible = 'off'; ax.XLim = [0 1]; ax.YLim = [0 1]; hold(ax, 'on');
            items = {'SG ctrl', obj.layerCol(1); 'G ctrl', obj.layerCol(2); 'IG ctrl', obj.layerCol(3); ...
                     'PVA', obj.COL_E; 'PVI', obj.COL_I};
            fs = obj.FONT - 3; ys = linspace(0.9, 0.1, size(items,1));
            for r = 1:size(items,1)
                plot(ax, [0.05 0.30], [ys(r) ys(r)], 'Color', items{r,2}, 'LineWidth', 3);
                text(ax, 0.36, ys(r), items{r,1}, 'FontSize', fs, 'VerticalAlignment','middle', 'Interpreter','none');
            end
            hold(ax, 'off');
        end
        function retuneLabels(obj)
            %RETUNELABELS  Part-C tuning y-labels track the master style key: paper
            %   Fig 5 wording ("Mean response (spk/s)" / "Mean normalized Response")
            %   vs the original wording. Reversible via the Original-style checkbox.
            paper = viz.paperStyle();
            if ~isempty(obj.tunYAbs) && isvalid(obj.tunYAbs)
                if paper, obj.tunYAbs.String = 'Mean response (spk/s)';
                else,     obj.tunYAbs.String = 'Absolute firing rate (sp/s)'; end
            end
            if ~isempty(obj.tunYNorm) && isvalid(obj.tunYNorm)
                if paper, obj.tunYNorm.String = 'Mean normalized Response';
                else,     obj.tunYNorm.String = 'Normalized firing rate'; end
            end
        end

        function styleTunAx(~, ax, yl)
            % pass the literal old argument {[-90 0 90]} (a numeric vector in a
            % cell): MATLAB space-pads it to '-90'/'  0'/' 90', shifting the
            % digits slightly off tick-center exactly as the old figure does.
            xlim(ax, [0 180]); xticks(ax, [0 90 180]); xticklabels(ax, {[-90 0 90]});
            ylim(ax, yl); hold(ax,'off');
        end

        function A = tunNorms(~, fitL, fitNL, cols)
            % Per-unit peak-centered tuning over the window 91:270 (180 samples),
            % 4 normalizations x 2 conditions, exactly as the old TunU_18 block.
            % A is 4 x 2 x 180 x K  (norm, cond[1=laser,2=control], sample, unit).
            K = numel(cols); A = zeros(4, 2, 180, K);
            for kk = 1:K
                w = cols(kk); ctrlMax = 1;
                for n = [2 1]                                   % control first, then laser
                    if n == 2, tun = fitNL(:,w); else, tun = fitL(:,w); end
                    tun = tun(:);
                    if all(~isfinite(tun)) || isempty(tun), continue; end
                    [~, maxId] = max(tun);
                    tun = circshift(tun, round(0.5*numel(tun) - maxId));
                    w180 = tun(91:270);
                    t1 = w180 - min(w180); m1 = max(t1); if m1 == 0 || ~isfinite(m1), m1 = 1; end
                    A(1,n,:,kk) = t1 / m1;
                    m2 = max(w180); if m2 == 0 || ~isfinite(m2), m2 = 1; end
                    A(2,n,:,kk) = w180 / m2;
                    if n == 2, ctrlMax = max(w180); if ctrlMax == 0 || ~isfinite(ctrlMax), ctrlMax = 1; end, end
                    A(3,n,:,kk) = w180 / ctrlMax;
                    A(4,n,:,kk) = w180;
                end
            end
        end

        function yl = gridYlim(obj, t, want)
            if want                                              % PVI
                Y = {[0 1], [.4 1], [.4 1.8], [8 47]};
            else                                                 % PVE
                Y = {[0 1], [.2 1], [0 1], [0 47]};
            end
            yl = Y{t};
            if want && t == 3 && obj.OverlayMode, yl = [.4 2.5]; end   % overlay only: extra headroom for the 3 laser curves/shadows (other options keep 1.8)
        end

        function s = star(obj, p)
            if ~isfinite(p),            s = 'ns';
            elseif p < obj.ERRTH(1),    s = '***';
            elseif p < obj.ERRTH(2),    s = '**';
            elseif p < obj.ERRTH(3),    s = '*';
            else,                       s = 'ns';
            end
        end
    end
end
