classdef LayerSelectivityChange02Tab < viz.PlotTab
%LAYERSELECTIVITYCHANGE02TAB  Companion to LayerSelectivity02Tab (V02): the
%   LASER-vs-CONTROL CHANGE in orientation selectivity by cortical layer. Same
%   controllers (Unit group / Population PVE-PVI / Repeated-obs) and the same
%   own-window pattern, but a different set of panels:
%
%     A) Delta/Ratio population tuning (top row, 4 panels) -- the control-
%        normalized population tuning (= row 3 of LayerSelectivity02's part C),
%        shown as the V01-dashboard delta(red)/ratio(cyan) DUAL-AXIS curves per
%        layer (SG/G/IG). For PVI the sign is reversed exactly as
%        viz.plots.UnitPanels.deltaRatio (delta = control-laser, ratio =
%        control/laser). The 4th panel shows the 3 control curves only (no
%        delta/ratio), matching V02's "All" column.
%     B) Paired control->laser plots (left 3x3, larger + CLICKABLE) -- one per
%        metric (OSI/CV/HBW) x layer (SG/G/IG); click a dot to open the shared
%        unit inspector (viz.plots.UnitInspector).
%     C) Change distributions (right 3x3) -- histogram of the per-unit change
%        Delta = Laser - Control for each metric x layer, with a zero line, the
%        median, and the paired-signrank star.
%
%   DATA / metrics are identical to LayerSelectivity02Tab: the FITTED OSI/CV/HBW
%   (fitOSI/fitCV/fitHBW_L/_NL) and the peak-centered fit curves (fit_L/fit_NL).
%   Group=ALL_UNITS + repeated-obs=All best reproduces the old f2 population.
%
%   See also: viz.plots.LayerSelectivity02Tab, viz.plots.UnitPanels.deltaRatio,
%             viz.plots.V01util, analysis.tuningGroupMask

    properties
        groupDD; eiDD; repDD; normModeDD; statusLbl; infoLabel
        frLevelLB; lmeTuneDD            % dFr-change-level filter + mixed-effects tuning method
        FrLevels cell = {}              % selected dFr-level keys (FR_KEYS); {} = all
        PlotFig
        normAx = {}       % 1x4 control-peak-NORMALIZED mean pop tunings (SG/G/IG + controls)
        absAx  = {}       % 1x4 ABSOLUTE (Hz) mean pop tunings (SG/G/IG + controls)
        drAx   = {}       % 1x4 delta/ratio control-normalized tunings (SG/G/IG + controls)
        pairAx = {}       % 3x3 larger clickable paired plots {metric, layer}
        distAx = {}       % 3x3 change-distribution histograms {metric, layer}
        LayoutSpec = {}
        LastD = []; LastMask = []
        LastRepByLayer = {}; LastWant = false    % last per-layer reps + PVE/PVI, for paperDraw
    end

    properties (Constant)
        GROUPS = {'ALL_UNITS','NO_ORI_ON_PV','NO_ORI_NO_PV','ORI_ON_PV','ORI_NON_PV','ORI_NON_PV_MD','ORI_NON_PV_NL','ORI_NON_PV_U','OUTLIER'};
        REP_ITEMS = {'All (match old code)','First per neuron','Max laser power', ...
                     'Mean per neuron','Mixed-effects (stats)'};
        REP_DATA  = {'all','first','maxpow','mean','lme'};
        % dFr-change levels: E uses the first 3, I uses all 4 (extra high = facilitated >100%)
        FR_LABELS = {'Low (0-33%)','Medium (33-66%)','High (66-100%)','Extra high (>100%)'};
        FR_KEYS   = {'low','medium','high','xhigh'};
        COLORS_NL = {[254 141 165]/255, [255 173 72]/255, [67 183 194]/255};  % SG / G / IG control
        COL_E = [0 1 0];          % PVE laser
        COL_I = [0 0 1];          % PVI laser
        DELTA_COL = [1 0 0];      % V01 deltaRatio: delta red (right axis) = viz.Colors.Delta
        RATIO_COL = [0 1 1];      % V01 deltaRatio: ratio cyan (left axis)
        ERRTH = [0.001 0.01 0.05];
        LAYERS  = [1 2 3];
        LAYER_LAB = {'SG','G','IG'};
        GROUP_LAB = {'Layer SG','Layer G','Layer IG'};
        MET = {'OSI','CV','HBW'};
        FIGFRAC = 0.98;
        FONT = 11; LW = 1; SZ = 11;
    end

    methods
        function obj = LayerSelectivityChange02Tab()
            obj@viz.PlotTab('Layer selectivity change (V02)');
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
                'Tooltip', ['How the AVERAGE delta/ratio (and control) tunings are computed when ' ...
                    'Repeated obs = "Mixed-effects (stats)". Per-neuron = each neuron once (fast); ' ...
                    'Per-angle = fitlme at every angle (rigorous, slow).'], ...
                'ValueChangedFcn', @(s,e) obj.requestRefresh());
            uilabel(g, 'Text', 'Normalized-tuning ref');
            obj.normModeDD = uidropdown(g, 'Items', {'Control peak','Each tuning peak'}, ...
                'ItemsData', [3 2], 'Value', 3, 'ValueChangedFcn', @(s,e) obj.requestRefresh());
            uilabel(g, 'Text', '');
            uibutton(g, 'Text', 'Open figure window', 'ButtonPushedFcn', @(s,e) obj.openFigure());
            obj.addReportButton(g);
            obj.statusLbl = uilabel(g, 'Text', '', 'WordWrap', 'on', 'VerticalAlignment','top');
            obj.infoLabel = uilabel(g, 'Text', '', 'WordWrap', 'on', 'VerticalAlignment','top');
            obj.addInspectCheckbox(g);     % + "Track unit on click" (paired dots are clickable)
            obj.addDataSelectors(g);
        end

        function buildView(obj, parent)
            obj.buildReportView(parent, sprintf(['The Visualizer-02 "layer selectivity CHANGE" window ' ...
                'opens in its own maximized window.\n\nIt shows the LASER-vs-CONTROL change in OSI/CV/HBW ' ...
                'by layer: control-normalized delta/ratio population tunings (top), larger CLICKABLE ' ...
                'paired plots (left), and the change (Laser \x2212 Control) distributions (right).\n\nUse ' ...
                'the controls on the left (and the toolbar Filters) \x2014 the window refreshes live.\n\n' ...
                'Click "Stats report" for the per-layer Control-vs-Laser OSI/CV/HBW statistics.']));
        end

        function rs = reportSpec(obj)
            if isempty(obj.LastD), rs = []; return; end
            mask = obj.LastMask; if isempty(mask), mask = true(viz.plots.V01util.nU(obj.LastD), 1); end
            mask = mask(:) & obj.frLevelMask(obj.LastD, strcmp(obj.eiDD.Value, 'I'));   % honor the dFr-level filter
            state = struct('group', obj.groupDD.Value, 'ei', obj.eiDD.Value, ...
                           'mask', mask(:), 'layers', obj.LAYERS);
            eiName = obj.eiDD.Items{strcmp(obj.eiDD.ItemsData, obj.eiDD.Value)};
            hdr = sprintf(['Layer selectivity change \x2014 %s, group %s.  Paired Wilcoxon ' ...
                'signed-rank (Control vs Laser) per layer; fitted OSI/CV/HBW.'], eiName, obj.groupDD.Value);
            rs = struct('figKey', 'V02', 'state', state, 'D', obj.LastD, 'header', hdr);
        end

        % --------------------------------------------------------------- %
        function update(obj, D, mask)
            obj.LastD = D; obj.LastMask = mask;
            if ~isempty(obj.PlotFig) && isvalid(obj.PlotFig), obj.drawFigure(); end
            if obj.ShowReport, obj.refreshReport(); end
            obj.refreshStatus();
        end

        function openFigure(obj)
            if ~isempty(obj.PlotFig) && isvalid(obj.PlotFig)
                figure(obj.PlotFig); obj.drawFigure(); obj.refreshStatus(); return;
            end
            ss = get(0,'screensize'); Mx = ss(3); My = ss(4);
            obj.PlotFig = uifigure('Name','Visualizer 02 - Layer selectivity CHANGE', 'Color','w', ...
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
                       'frLevels', {obj.FrLevels}, 'lmeTune', obj.lmeTuneDD.Value, ...
                       'normMode', obj.normModeDD.Value);
        end
        function setControlState(obj, s)
            if isfield(s,'group'), obj.setCtrl(obj.groupDD, s.group); end
            if isfield(s,'ei'),    obj.setCtrl(obj.eiDD,    s.ei);    end
            if isfield(s,'rep'),   obj.setCtrl(obj.repDD,   s.rep);   end
            if isfield(s,'lmeTune'), obj.setCtrl(obj.lmeTuneDD, s.lmeTune); end
            if isfield(s,'normMode'), obj.setCtrl(obj.normModeDD, s.normMode); end
            if isfield(s,'frLevels'), obj.FrLevels = s.frLevels; obj.applyFrLevelsToLB(); end
            if isfield(s,'showReport'), obj.ShowReport = logical(s.showReport); obj.syncReport(); end
        end

        % ---- paper-figure tool hooks: native (vector) redraw of the yyaxis -- %
        % delta/ratio panels (copyobj can't clone a 2-ruler axes, so without these
        % the paper tool falls back to a uiimage snapshot that exportgraphics drops
        % from vector PDFs -- exactly the "missing 3E delta/ratio" bug).
        function [kind, slot] = specForAxes(obj, ax)
            kind = ''; slot = 0;
            for li = 1:3
                if numel(obj.drAx) >= li && ~isempty(obj.drAx{li}) && isequal(ax, obj.drAx{li})
                    kind = 'dr'; slot = li; return;
                end
            end
        end
        function paperDraw(obj, ax, kind, slot)
            %PAPERDRAW  Redraw ONE delta/ratio panel (layer SLOT) into an EXTERNAL axes
            %   with the same drawer the live figure uses -- no copyobj / snapshot.
            if ~strcmp(kind, 'dr') || slot < 1 || slot > 3, return; end
            D = obj.LastD;
            if isempty(D) || ~isfield(D,'fit_L') || ~isfield(D,'fit_NL'), return; end
            if numel(obj.LastRepByLayer) < slot, return; end
            rep = obj.LastRepByLayer{slot}; want = obj.LastWant;
            A = obj.tunNorms(D.fit_L, D.fit_NL, rep);
            neur = viz.plots.V01util.colv(D, 'U_unity'); neur = neur(rep);
            if obj.useNeuronLme(), A = viz.plots.V01util.aggNeuronCurves(A, neur); end
            K = size(A, 4); if K == 0, return; end
            X = (1:180)';
            laser = reshape(A(3,1,:,:), 180, K); ctrl = reshape(A(3,2,:,:), 180, K);
            if want, deltaU = ctrl - laser; ratioU = ctrl ./ laser;   % PVI reversed (V01 deltaRatio)
            else,    deltaU = laser - ctrl; ratioU = laser ./ ctrl; end
            ratioU(~isfinite(ratioU)) = NaN;
            [dMean, dSE] = obj.curveMS(deltaU, neur);
            [rMean, rSE] = obj.curveMS(ratioU, neur);
            obj.dualAxisDR(ax, X, dMean, dSE, rMean, rSE);
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
            items = [{'(all levels)'}, obj.FR_LABELS(1:n)];
        end
        function onEiChanged(obj)
            want = strcmp(obj.eiDD.Value, 'I');         % rebuild the level list for E (3) / I (4)
            obj.frLevelLB.Items = obj.frLevelItems(want);
            obj.frLevelLB.Value = '(all levels)'; obj.FrLevels = {};
            obj.requestRefresh();
        end
        function onFrLevelChanged(obj)
            v = obj.frLevelLB.Value;
            if ischar(v), v = {v}; elseif isstring(v), v = cellstr(v); end
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
            if isempty(obj.FrLevels), m = true(N,1); return; end
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
        function [mu, se] = curveMS(obj, M, neur)
            %CURVEMS  Population mean +/- SE of the P x K curve matrix M. Non-LME and
            %   "per-neuron" LME (M pre-aggregated) -> plain mean +/- SEM over columns
            %   (std norm 1, matching the old controls-panel band and LayerSelectivity02).
            %   "Per-angle" LME -> fitlme per row (slow). neur = per-observation neuron
            %   id (used by the per-angle model only). omitnan keeps the ratio /0 guard.
            if obj.useAngleLme()
                [mu, se] = viz.plots.V01util.lmePerAngle(M, neur);
            else
                K = max(size(M,2), 1);
                mu = mean(M, 2, 'omitnan'); se = std(M, 1, 2, 'omitnan') / sqrt(K);
            end
        end

        % ---- panel construction --------------------------------------- %
        function createPanels(obj)
            % top-left 3-row x 4-col band (columns SG / G / IG / Controls):
            %   Norm  mean population tunings (row 3 of tunNorms, control-peak norm)
            %   Abs   mean population tunings (row 4 of tunNorms, absolute Hz)
            %   D/R   delta(red)/ratio(cyan) dual-axis tunings (small + wide, like Example units)
            obj.normAx = cell(1,4); obj.absAx = cell(1,4); obj.drAx = cell(1,4);
            colX = {.04,.17,.30,.43}; fw = .11;
            for j = 1:4, obj.absAx{j}  = obj.addAx(colX{j}, .84,  fw, .10);  end   % Abs  row (top)
            for j = 1:4, obj.normAx{j} = obj.addAx(colX{j}, .725, fw, .10);  end   % Norm row (middle)
            for j = 1:4, obj.drAx{j}   = obj.addAx(colX{j}, .60,  fw, .095); end   % D/R  row (bottom, taller; titles dropped)
            % left 3x3 paired (clickable) + right 3x3 change distributions -- tightened
            % columns + the two blocks moved closer, opening space for the taller D/R row
            obj.pairAx = cell(3,3); obj.distAx = cell(3,3);
            pcx = {.04,.17,.30}; dcx = {.42,.55,.68}; ry = {.38,.21,.04};
            for mi = 1:3
                for li = 1:3
                    obj.pairAx{mi,li} = obj.addAx(pcx{li}, ry{mi}, .104, .13);
                    obj.distAx{mi,li} = obj.addAx(dcx{li}, ry{mi}, .104, .13);
                end
            end
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
            % top-band 3-row grid: section title + per-row + per-column labels
            obj.addLabel(.04, .955, .9, .03, ['Population tunings by layer  ' ...
                '(Norm / Absolute mean  +  Delta(red)/Ratio(cyan))'], 0, 'k', obj.FONT+1);
            % row labels at the far left of each row (rotated 90): Abs top, Norm middle
            obj.addLabel(.005, .885, .03, .05, 'Abs',           90, 'k');
            obj.addLabel(.005, .77,  .03, .05, 'Norm',          90, 'k');
            obj.addLabel(.005, .635, .04, .05, '\Delta/Ratio',  90, 'k');
            % (top-band column headers omitted: each panel already carries its own
            %  colored "SG (n=..)" / "Controls" title, so separate headers were redundant
            %  and overlapped the section title.)
            % block titles
            obj.addLabel(.04, .565, .45, .03, 'Paired control\rightarrowlaser per layer (click a dot to inspect)', 0);
            obj.addLabel(.42, .565, .45, .03, 'Distribution of change (Laser - Control)', 0);
            % column headers (SG/G/IG) over each 3x3 block
            pcx = {.04,.17,.30}; dcx = {.42,.55,.68};
            for li = 1:3
                obj.addLabel(pcx{li}+.05, .54, .05, .03, obj.LAYER_LAB{li}, 0, obj.layerCol(li));
                obj.addLabel(dcx{li}+.05, .54, .05, .03, obj.LAYER_LAB{li}, 0, obj.layerCol(li));
            end
            % row labels OSI/CV/HBW at the far left of the paired block
            ry = {.38,.21,.04};
            for mi = 1:3
                obj.addLabel(.004, ry{mi}+.06, .04, .05, obj.MET{mi}, 90, 'k', obj.FONT+1);
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
            obj.relayout(); obj.clearAll();
            if ~isfield(D,'fitOSI_NL') || ~isfield(D,'fit_NL')
                title(obj.pairAx{1,1}, 'Missing fitOSI_NL / fit_NL'); return;
            end
            try, grpMask = analysis.tuningGroupMask(D, obj.groupDD.Value);
            catch err, title(obj.pairAx{1,1}, ['Group error: ' err.message]); return; end

            colv = @viz.plots.V01util.colv;
            isI  = viz.plots.V01util.isInhib(D);
            want = strcmp(obj.eiDD.Value, 'I');
            sel  = mask(:) & grpMask(:) & (isI == want) & obj.frLevelMask(D, want);
            LGn  = viz.plots.V01util.layerNum(D);
            lcol = obj.lcolFor(want);
            mode = obj.repDD.Value;

            repByLayer = viz.plots.V01util.layerReps(D, find(sel), LGn, mode, obj.LAYERS);
            if strcmp(mode, 'mean')
                % 'Mean per neuron': dominant-layer assignment kept, but the panels
                % get ALL of each neuron's rows IN that layer, so its value is the
                % MEAN of its recordings (layerReps' 'mean' representative is the
                % first row -- values there would be firsts).
                UUv = viz.plots.V01util.colv(D, 'U_unity');
                for li = 1:numel(repByLayer)
                    rows = find(sel & LGn(:) == obj.LAYERS(li) & ismember(UUv, UUv(repByLayer{li})));
                    repByLayer{li} = rows(:);
                end
            end
            obj.LastRepByLayer = repByLayer; obj.LastWant = want;   % remembered for paperDraw (native delta/ratio redraw in the paper-figure tool)
            UU = colv(D, 'U_unity');
            neurByLayer = cell(1,3);
            for li = 1:3, neurByLayer{li} = UU(repByLayer{li}); end

            % ---- B) paired plots + C) change distributions, per metric x layer ----
            % Under Mixed-effects the DISPLAYED data is collapsed to one per-neuron
            % mean (each neuron once, within its layer); the paired/change-dist
            % significance keeps the LME model on the full observations (precomputed
            % here, observation-level), matching the per-neuron delta/ratio curves.
            pk = viz.plots.V01util.penKey(D);
            aggN = any(strcmp(mode, {'mean','lme'}));
            for mi = 1:3
                cfg = obj.metCfg(obj.MET{mi}, want);
                nlv = colv(D, cfg.NL); lv = colv(D, cfg.L);
                if cfg.clampNeg                              % HBW: drop not-aligned units
                    badU = colv(D,'Align_bad') == 1; nlv(badU) = NaN; lv(badU) = NaN;
                end
                G1 = cell(1,3); G2 = cell(1,3); Rp = cell(1,3);
                pPair = nan(1,3); redPair = false(1,3);
                for li = 1:3
                    rp = repByLayer{li}; nu = neurByLayer{li};
                    cObs = nlv(rp); lObs = lv(rp);          % observation-level control / laser
                    if aggN                                  % collapse to one value per neuron
                        [cD, ~, rD] = viz.plots.V01util.aggNeuronScalar(cObs, nu, rp);
                        lD = viz.plots.V01util.aggNeuronScalar(lObs, nu);
                    else
                        cD = cObs; lD = lObs; rD = rp;
                    end
                    % star: LME on the observations under 'lme'; signrank on the
                    % displayed per-neuron means under 'mean'; signrank otherwise.
                    if strcmp(mode, 'mean')
                        [pPair(li), redPair(li)] = viz.plots.V01util.smPaired(lD, cD, [], 'all');
                    else
                        [pPair(li), redPair(li)] = viz.plots.V01util.smPaired(lObs, cObs, nu, mode, pk(rp));
                    end
                    G1{li} = cD; G2{li} = lD; Rp{li} = rD;
                    obj.drawPairedClickable(obj.pairAx{mi,li}, G1{li}, G2{li}, Rp{li}, ...
                        obj.layerCol(li), lcol, obj.MET{mi}, obj.GROUP_LAB{li}, ...
                        cfg.pairYlim, pPair(li), redPair(li));
                end
                % shared x-limits + aligned bins for this metric's 3 layer distributions
                edges = obj.commonDeltaEdges(G1, G2);
                for li = 1:3
                    obj.drawChangeDist(obj.distAx{mi,li}, G1{li}, G2{li}, edges, ...
                        obj.layerCol(li), obj.MET{mi}, obj.GROUP_LAB{li}, pPair(li), redPair(li));
                end
            end

            % ---- A) delta/ratio control-normalized population tunings -------
            obj.drawDeltaRatioTuning(repByLayer, want);

            if aggN                                          % Mixed-effects: count distinct neurons
                nlab = 'neurons';
                nSG = numel(unique(neurByLayer{1})); nG = numel(unique(neurByLayer{2})); nIG = numel(unique(neurByLayer{3}));
            else
                nlab = 'units';
                nSG = numel(repByLayer{1}); nG = numel(repByLayer{2}); nIG = numel(repByLayer{3});
            end
            obj.infoLabel.Text = sprintf(['group %s   %s   layer N (SG/G/IG, %s): %d/%d/%d\n' ...
                'OSI/CV/HBW are FITTED values. Delta = Laser - Control (PVI reversed in A).'], ...
                obj.groupDD.Value, obj.eiDD.Value, nlab, nSG, nG, nIG);
        end

        function clearAll(obj)
            for k = 1:3                                      % dual-axis delta/ratio panels
                ax = obj.drAx{k};
                if ~isempty(ax) && isvalid(ax)
                    try, yyaxis(ax,'left'); cla(ax); yyaxis(ax,'right'); cla(ax); catch, try, cla(ax); catch, end, end %#ok<CTCH>
                end
            end
            if numel(obj.drAx) >= 4 && isvalid(obj.drAx{4}), cla(obj.drAx{4}); end
            for k = 1:numel(obj.normAx), if isvalid(obj.normAx{k}), cla(obj.normAx{k}); end, end
            for k = 1:numel(obj.absAx),  if isvalid(obj.absAx{k}),  cla(obj.absAx{k});  end, end
            for k = 1:numel(obj.pairAx), if isvalid(obj.pairAx{k}), cla(obj.pairAx{k}); end, end
            for k = 1:numel(obj.distAx), if isvalid(obj.distAx{k}), cla(obj.distAx{k}); end, end
        end

        function c = lcolFor(obj, want)
            if want, c = obj.COL_I; else, c = obj.COL_E; end
        end
        function c = layerCol(obj, i)
            %LAYERCOL  Cortical-layer color. Paper mode = saturated SG magenta / G
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
                    cfg = struct('L','fitCV_L', 'NL','fitCV_NL', 'pairYlim',[0 1.1], 'clampNeg',false);
                case 'HBW'
                    if isI, py = [10 50]; else, py = [0 50]; end
                    cfg = struct('L','fitHBW_L','NL','fitHBW_NL','pairYlim',py, 'clampNeg',true);
                otherwise
                    cfg = struct('L','fitOSI_L','NL','fitOSI_NL','pairYlim',[0 1.1], 'clampNeg',false);
            end
        end

        % ---- A) delta/ratio control-normalized population tunings ------ %
        function drawDeltaRatioTuning(obj, repByLayer, want)
            D = obj.LastD;
            if ~isfield(D,'fit_L') || ~isfield(D,'fit_NL'), return; end
            fitL = D.fit_L; fitNL = D.fit_NL; X = (1:180)';
            UU = viz.plots.V01util.colv(D, 'U_unity');
            % Under mixed-effects "per-neuron" each neuron's observation curves are
            % averaged first, so the delta/ratio and SE below are over NEURONS; the
            % "per-angle" model uses the per-observation neuron ids (see
            % STATS_MIXED_EFFECTS.md sec 3e).
            A = cell(1,3); neur = cell(1,3);
            for li = 1:3
                A{li}    = obj.tunNorms(fitL, fitNL, repByLayer{li});
                neur{li} = UU(repByLayer{li});
                if obj.useNeuronLme(), A{li} = viz.plots.V01util.aggNeuronCurves(A{li}, neur{li}); end
            end
            % Norm + Absolute mean population tunings (control black + laser colored)
            nRow = 3; if ~isempty(obj.normModeDD) && isvalid(obj.normModeDD), nRow = obj.normModeDD.Value; end
            obj.drawMeanTun(obj.normAx, A, neur, nRow, 'Norm. firing');
            obj.drawMeanTun(obj.absAx,  A, neur, 4, 'Firing (Hz)');
            for li = 1:3
                ax = obj.drAx{li}; K = size(A{li},4);
                if K == 0, title(ax, sprintf('%s  (n=0)', obj.LAYER_LAB{li})); continue; end
                laser = reshape(A{li}(3,1,:,:), 180, K);     % per-unit (or per-neuron) ctrl-peak-norm laser
                ctrl  = reshape(A{li}(3,2,:,:), 180, K);     % control (peak=1)
                if want, deltaU = ctrl - laser; ratioU = ctrl ./ laser;   % PVI reversed (V01 deltaRatio)
                else,    deltaU = laser - ctrl; ratioU = laser ./ ctrl;   % PVE
                end
                ratioU(~isfinite(ratioU)) = NaN;             % guard /0 before averaging
                [dMean, dSE] = obj.curveMS(deltaU, neur{li});
                [rMean, rSE] = obj.curveMS(ratioU, neur{li});
                obj.dualAxisDR(ax, X, dMean, dSE, rMean, rSE);
                title(ax, '');                               % title dropped -> taller curve area; layer+n shown in the Norm/Abs panels above
            end
            % 4th D/R panel is now empty: the Controls norm curves live in normAx{4}.
            if numel(obj.drAx) >= 4 && isvalid(obj.drAx{4}), cla(obj.drAx{4}); obj.drAx{4}.Visible = 'off'; end
        end

        % ---- Norm + Absolute mean population tunings (per layer + Controls) ---- %
        function drawMeanTun(obj, axset, A, neur, rowIdx, ylabTxt)
            % axset = obj.normAx (rowIdx=3, control-peak norm) or obj.absAx (rowIdx=4,
            % absolute Hz). Control curve = black, laser curve = PVE green / PVI blue.
            X = (1:180)';
            for li = 1:3
                ax = axset{li}; K = size(A{li},4);
                if K == 0, title(ax, sprintf('%s (n=0)', obj.LAYER_LAB{li})); continue; end
                ctrl  = reshape(A{li}(rowIdx,2,:,:), 180, K);
                laser = reshape(A{li}(rowIdx,1,:,:), 180, K);
                [mc,sc] = obj.curveMS(ctrl,  neur{li});
                [ml,sl] = obj.curveMS(laser, neur{li});
                lcol = obj.lcolFor(strcmp(obj.eiDD.Value,'I'));   % laser color: green PVE / blue PVI
                hold(ax,'on');
                viz.plots.V01util.plotSE(ax, X, mc, sc, 'k',  [.5 .5 .5], 0.4, 0.5);   % control (black)
                viz.plots.V01util.plotSE(ax, X, ml, sl, lcol, lcol,       0.4, 0.5);   % laser (colored)
                xlim(ax,[0 180]); xticks(ax,[0 90 180]); xticklabels(ax,{[-90 0 90]});
                ylabel(ax, ylabTxt);
                title(ax, sprintf('%s (n=%d)', obj.LAYER_LAB{li}, K), 'Color', obj.layerCol(li));
                hold(ax,'off');
            end
            % 4th "Controls" panel: the 3 layers' control curves overlaid (no laser)
            ax4 = axset{4}; hold(ax4,'on');
            for li = 3:-1:1
                K = size(A{li},4); if K == 0, continue; end
                [yc,sec] = obj.curveMS(reshape(A{li}(rowIdx,2,:,:), 180, K), neur{li});
                viz.plots.V01util.plotSE(ax4, X, yc, sec, obj.layerCol(li), obj.layerCol(li), 0.4, 0.5);
            end
            xlim(ax4,[0 180]); xticks(ax4,[0 90 180]); xticklabels(ax4,{[-90 0 90]});
            ylabel(ax4, ylabTxt); title(ax4,'Controls'); hold(ax4,'off');
        end

        function dualAxisDR(obj, ax, X, dMean, dSE, rMean, rSE)
            % delta (right, red) + ratio (left, cyan), each with a +/-SE shaded band
            % drawn by viz.plots.V01util.plotSE, exactly like the V01 dashboard
            % drawPopDeltaRatio error shadowing.
            try
                yyaxis(ax,'right'); ax.YColor = obj.DELTA_COL;
                viz.plots.V01util.plotSE(ax, X, dMean, dSE, obj.DELTA_COL, obj.DELTA_COL, 0.25, obj.LW);
                ylim(ax,'auto'); xlim(ax,[0 180]); xticks(ax,[0 90 180]); xticklabels(ax,{[-90 0 90]});
                yyaxis(ax,'left'); ax.YColor = obj.RATIO_COL;
                viz.plots.V01util.plotSE(ax, X, rMean, rSE, obj.RATIO_COL, obj.RATIO_COL, 0.25, obj.LW);
                ylim(ax,[0 1]); xlim(ax,[0 180]);
            catch
                cla(ax);
                viz.plots.V01util.plotSE(ax, X, dMean, dSE, obj.DELTA_COL, obj.DELTA_COL, 0.25, obj.LW); hold(ax,'on');
                viz.plots.V01util.plotSE(ax, X, rMean, rSE, obj.RATIO_COL, obj.RATIO_COL, 0.25, obj.LW);
                xlim(ax,[0 180]); xticks(ax,[0 90 180]); xticklabels(ax,{[-90 0 90]}); hold(ax,'off');
            end
        end

        % ---- B) larger CLICKABLE paired control->laser plot ----------- %
        function drawPairedClickable(obj, ax, g1, g2, reps, col1, col2, metName, ttl, ylimVal, pSig, isRed)
            % g1=control, g2=laser, reps are the DISPLAY units (per-neuron means +
            % representative rows under Mixed-effects); pSig/isRed are the per-layer
            % significance precomputed by drawFigure (LME on observations under
            % Mixed-effects).
            g1 = g1(:); g2 = g2(:); reps = reps(:);
            ok = isfinite(g1) & isfinite(g2); g1 = g1(ok); g2 = g2(ok); reps = reps(ok);
            hold(ax,'on'); s = obj.SZ;
            for k = 1:numel(g1)                              % gray connectors (click-through)
                plot(ax, [1 2], [g1(k) g2(k)], '-', 'Color', [0.6 0.6 0.6 .3], 'LineWidth', 1, 'PickableParts','none');
            end
            if ~isempty(g1)
                scatter(ax, ones(numel(g1),1),   g1, 2*s, col1, '^', 'filled', 'MarkerFaceAlpha', 0.4, 'PickableParts','none');
                scatter(ax, 2*ones(numel(g2),1), g2, 2*s, col2, '^', 'filled', 'MarkerFaceAlpha', 0.4, 'PickableParts','none');
                errorbar(ax, .7,  mean(g1), std(g1), 'k', 'LineWidth',0.7, 'CapSize',s, 'Marker','^', 'MarkerSize',s, 'MarkerFaceColor',col1, 'PickableParts','none');
                errorbar(ax, 2.3, mean(g2), std(g2), 'k', 'LineWidth',0.7, 'CapSize',s, 'Marker','^', 'MarkerSize',s, 'MarkerFaceColor',col2, 'PickableParts','none');
            end
            ylim(ax, ylimVal); xlim(ax, [0 3]);
            set(ax, 'XTick', [1 2], 'XTickLabel', {'C','L'});
            ylabel(ax, metName); title(ax, ttl);
            yMax = max(ylim(ax));
            line(ax, [1 2], [yMax yMax]-.04*yMax, 'Color','k', 'PickableParts','none');
            viz.plots.V01util.drawSig(ax, 1.5, yMax-.04*yMax+.01*yMax, pSig, isRed, 'center');
            % each unit = a control dot (x=1) + a laser dot (x=2) -> same rep
            n = numel(g1);
            obj.enableDotPick(ax, [ones(n,1); 2*ones(n,1)], [g1; g2], [reps; reps]);
            hold(ax,'off');
        end

        % ---- C) histogram of the per-unit change (Laser - Control) ---- %
        function drawChangeDist(obj, ax, g1, g2, edges, col, metName, ttl, pSig, isRed)
            % g1=control, g2=laser are the DISPLAY units (per-neuron means under
            % Mixed-effects), so the histogram + median are over neurons; pSig/isRed
            % are the per-layer significance precomputed by drawFigure.
            g1 = g1(:); g2 = g2(:);
            ok = isfinite(g1) & isfinite(g2);
            delta = g2(ok) - g1(ok);                         % Laser - Control
            hold(ax,'on');
            if ~isempty(delta)
                if ~isempty(edges)                           % shared bins -> same x-limits across layers
                    histogram(ax, delta, edges, 'FaceColor', col, 'FaceAlpha', 0.55, 'EdgeColor', col*0.6);
                else
                    histogram(ax, delta, 'FaceColor', col, 'FaceAlpha', 0.55, 'EdgeColor', col*0.6);
                end
            end
            if ~isempty(edges), xlim(ax, [edges(1) edges(end)]); end
            yl = ylim(ax); if isempty(yl) || yl(2) <= 0, yl = [0 1]; end
            xline(ax, 0, 'Color', [0 0 0 0.5], 'LineStyle','--');     % no-change reference
            if ~isempty(delta)
                md = median(delta);
                plot(ax, [md md], [0 yl(2)], 'Color', col*0.6, 'LineWidth', 1.4);   % median
                viz.plots.V01util.drawSig(ax, md, 0.95*yl(2), pSig, isRed, 'center');
            end
            xlabel(ax, ['\Delta ' metName]); ylabel(ax,'Count'); title(ax, ttl);
            hold(ax,'off');
        end

        function edges = commonDeltaEdges(~, G1, G2)
            %COMMONDELTAEDGES  Bin edges spanning the pooled Laser-Control change of
            %   all layers for ONE metric, so its 3 distributions share identical
            %   x-limits and aligned bars. Returns [] when there is no finite data.
            pooled = [];
            for li = 1:numel(G1)
                d = G2{li}(:) - G1{li}(:); pooled = [pooled; d(isfinite(d))]; %#ok<AGROW>
            end
            edges = [];
            if isempty(pooled), return; end
            if numel(pooled) < 2 || range(pooled) == 0
                c = pooled(1); edges = [c-0.5, c+0.5]; return;   % degenerate -> a unit-wide window
            end
            [~, edges] = histcounts(pooled);                 % auto bins over the pooled range
        end

        % ---- per-unit peak-centered tuning normalizations (TunU_18) ---- %
        function A = tunNorms(~, fitL, fitNL, cols)
            % A is 4 x 2 x 180 x K (norm, cond[1=laser,2=control], sample, unit);
            % row 3 = control-peak normalization (the one this tab uses). Verbatim
            % from LayerSelectivity02Tab so the curves match part C exactly.
            K = numel(cols); A = zeros(4, 2, 180, K);
            for kk = 1:K
                w = cols(kk); ctrlMax = 1;
                for n = [2 1]                                % control first, then laser
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
    end
end
