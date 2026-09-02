classdef Dashboard01Tab < viz.PlotTab
%DASHBOARD01TAB  Controls for Visualizer_01's main dashboard (figure `f`); the
%   actual figure opens in its OWN maximized uifigure, built with the literal
%   old pixel positions, fonts (11 pt) and colors so it looks like Visualizer_01.
%
%   The TAB shows only the controls; the global filter panel is in the toolbar.
%   Panels are placed in PIXELS at the exact old monitor fractions (old fig spans
%   [0 .03 1 .95] of screen, y/height /0.95), recomputed on resize.
%
%   Under "Mixed-effects (stats)" EVERY population panel is collapsed to one value/
%   curve per NEURON (each neuron's observations averaged) -- the pseudo-replication
%   correction: the dFr-group box plots (a0{3}) + stats table, the data/model scatter
%   plots and their regression fits (a0{1}/a0{2}), the dFr histogram (a2{8}), the
%   linear-threshold slope histogram, the population tuning / delta / ratio curves
%   (a2{9}/a2{10}, I{i,6}, I{i,8}), the I/O linear-threshold fit (Ax_r{1}) and the LTM
%   parameter scatter. Box/slope STARS additionally use the per-neuron MODEL
%   (signrank/ranksum on per-neuron data, red when significance changes vs All); the
%   scatter regressions are OLS on the per-neuron points. Helpers aggLme/neurGroups/
%   aggVec/aggCols are identity no-ops in every other mode, so those render exactly as
%   before. The per-unit example panels (slider-selected) are single units, unaffected.
%
%   See also: analysis.tuningGroupMask, viz.plots.V01util

    properties
        groupDD; indexDD; modelDD; repDD; normDD; condSwitch; unitSlider; unitLabel; statusLbl
        frLB                                  % dFr-change-group(s) multi-select listbox
        fitAllICB                             % "PVI fit over all dFr>0" checkbox (a0{1}/a0{2} regressions)
        FrGroups cell = {}                    % selected dFr-change group keys (FR_KEYS); {} = all
        PlotFig
        axScatter; axSim; axBox; axLTM; axPopE; axPopI; axHist; axIO; axSlope; statsTable
        uRasL = {}; uRasNL = {}; uTun = {}; uDratio = {}; uPolar = {}; uIO = {}
        uPop6 = {}; uPop8 = {}        % I{i,6} pop mean tuning, I{i,8} pop delta/ratio
        % persistent figure-label text handles retuned by the paper-style key (applyPaperLabels):
        lblPVE; lblPVI                % column titles: PVE/PVI (black) <-> PVA/PVI (green/blue in paper mode)
        lblRD_pop; lblRD_unit         % 'Ratio Delta' y-labels (hidden in paper mode; colored RT/dT drawn instead)
        LblMap = struct()             % keyed floating-label text handles (addLabel key) -> paper Fig 1 writings in paper mode
        SelectedUnit = NaN; SecondUnit = NaN     % SecondUnit = LEFT/E (slot 1), SelectedUnit = RIGHT/I (slot 2)
        ERep = []; IRep = []                      % reduced E / I rep lists the slider scrolls
        LastD = []; LastMask = []
        GrpCounts = struct('eObs',0,'eNeur',0,'iObs',0,'iNeur',0)   % TuningG group size per side, obs / neurons (scatterPaperText)
        LayoutSpec = {}
    end

    properties (SetAccess = private)
        CurrentSet = []
    end

    properties (Constant)
        GROUPS = {'ALL_UNITS','NO_ORI_ON_PV','NO_ORI_NO_PV','ORI_ON_PV','ORI_NON_PV','ORI_NON_PV_MD','ORI_NON_PV_NL','ORI_NON_PV_U','OUTLIER'};
        REP_ITEMS = {'All (match old code)','First per neuron','Max laser power','Mean per neuron','Mixed-effects (stats)'};
        REP_DATA  = {'all','first','maxpow','mean','lme'};
        NORM_ITEMS = {'Absolute','Control peak','Self peak'};
        % dFr-change (laser firing-rate change %) groups -- EXACTLY the
        % drawBoxAndStats gE/gI band boundaries (E suppressed: 3 bands; I
        % facilitated: 4 bands). Same control as the layer-selectivity tabs.
        FR_ITEMS = {'(all groups)','E: low','E: medium','E: high','I: low','I: medium','I: high','I: extra high'};
        FR_KEYS  = {'all','E:low','E:medium','E:high','I:low','I:medium','I:high','I:xhigh'};
        COL_E = [0 1 0]; COL_I = [0 0 1];
        COL2_4 = {[1 1 0],[1 .5 0],[1 0 0],[.5 0 0]};
        COLORS_NL = {[254 141 165]/255,[255 173 72]/255,[67 183 194]/255};
        ANGLESS = [0 90 180 270 360];
        FONT = 11; LW = 1; SZ = 16.5;
    end

    methods
        function obj = Dashboard01Tab()
            obj@viz.PlotTab('Dashboard (V01)');
        end

        % --------------------------------------------------------------- %
        function buildControls(obj, parent)
            g = uigridlayout(parent, [26 1]);
            g.RowHeight = repmat({'fit'}, 1, 26); g.RowHeight{end} = '1x';
            g.RowHeight{4} = 130;            % dFr-change multi-select listbox (row 4)
            g.RowSpacing = 4; g.Padding = [8 8 8 8];
            try, g.Scrollable = 'on'; catch, end %#ok<CTCH>
            uilabel(g, 'Text', 'Unit group (TuningG)');
            obj.groupDD = uidropdown(g, 'Items', obj.GROUPS, 'Value', 'ORI_NON_PV', 'ValueChangedFcn', @(s,e) obj.requestRefresh());
            uilabel(g, 'Text', 'dFr change group(s)');
            obj.frLB = uilistbox(g, 'Items', obj.FR_ITEMS, 'Multiselect', 'on', 'Value', '(all groups)', ...
                'Tooltip', sprintf(['Restrict the shown units by laser firing-rate change (%%).\n' ...
                    'E (suppressed):  0-33 low,  33-66 medium,  66-100 high.\n' ...
                    'I (facilitated):  0-33 low,  33-66 medium,  66-100 high,  >100 extra high.\n' ...
                    'Select any combination; matches the box-plot groups.']), ...
                'ValueChangedFcn', @(s,e) obj.onFrChanged());
            uilabel(g, 'Text', 'Ori index');
            obj.indexDD = uidropdown(g, 'Items', {'HBW','OSI','CV'}, 'Value', 'HBW', 'ValueChangedFcn', @(s,e) obj.requestRefresh());
            % Scatter regression domain for the I (PVI) side. OFF = the V01/paper fit
            % (0 < dFr < 200, i.e. only the facilitated units inside the x-limit);
            % ON = every facilitated unit (dFr > 0), including those past the 200% edge.
            % The E (PVA) side is always dFr < 0. Applies to a0{1} AND the a0{2}
            % simulation scatter (and the fit lines a0{2} overlays back onto a0{1}).
            obj.fitAllICB = uicheckbox(g, 'Text', 'Fit line: PVI all dFr>0 (no 200 cap)', ...
                'Value', false, 'ValueChangedFcn', @(s,e) obj.requestRefresh(), 'Tooltip', ...
                sprintf(['Regression domain of the BLUE (PVI) fit line and its r/p/n text.\n' ...
                    'Off (default): 0 < dFr < 200 %% - the V01 / paper-figure fit.\n' ...
                    'On: every I unit with dFr > 0, including units past the 200 %% axis limit.\n' ...
                    'The green (PVA) fit is always dFr < 0 in both states.\n' ...
                    'Applies to the main scatter AND the simulation scatter; the stats report ' ...
                    'keeps its paper-faithful 0<dFr<200 PVI row.']));
            uilabel(g, 'Text', 'Model (sim scatter)');
            obj.modelDD = uidropdown(g, 'Items', {'ExpM (I/O)','LTM (Lin-Thresh)'}, 'ItemsData', {'ExpM','LTM'}, 'Value', 'ExpM', 'ValueChangedFcn', @(s,e) obj.requestRefresh());
            uilabel(g, 'Text', 'Repeated obs (per neuron)');
            obj.repDD = uidropdown(g, 'Items', obj.REP_ITEMS, 'ItemsData', obj.REP_DATA, 'Value', 'all', 'ValueChangedFcn', @(s,e) obj.requestRefresh());
            uilabel(g, 'Text', 'Population norm');
            % default 'Self peak' so a2{9}/a2{10} match V01 (each curve / its own peak); dropdown still selectable
            obj.normDD = uidropdown(g, 'Items', obj.NORM_ITEMS, 'Value', 'Self peak', 'ValueChangedFcn', @(s,e) obj.requestRefresh());
            uilabel(g, 'Text', 'Update example (E = left / I = right)');
            obj.condSwitch = uiswitch(g, 'Items', {'E','I'}, 'Value', 'E', 'Orientation','horizontal', 'ValueChangedFcn', @(s,e) obj.onCondSwitch());
            uilabel(g, 'Text', 'Selected unit (within group)');
            obj.unitSlider = uislider(g, 'Limits', [1 2], 'Value', 1, 'ValueChangedFcn', @(s,e) obj.onUnitSlider());
            sb = uigridlayout(g, [1 2], 'Padding',[0 0 0 0], 'ColumnSpacing',4);   % per-unit step buttons
            uibutton(sb, 'Text','−', 'ButtonPushedFcn', @(s,e) obj.stepUnit(-1));
            uibutton(sb, 'Text','+',       'ButtonPushedFcn', @(s,e) obj.stepUnit(+1));
            obj.unitLabel = uilabel(g, 'Text', 'unit: -', 'FontWeight', 'bold');
            uilabel(g, 'Text', '');
            uibutton(g, 'Text', 'Open figure window', 'ButtonPushedFcn', @(s,e) obj.openFigure());
            obj.addReportButton(g);
            obj.statusLbl = uilabel(g, 'Text', '', 'WordWrap', 'on', 'VerticalAlignment','top');
            obj.addInspectCheckbox(g);
            obj.addDataSelectors(g);
        end

        function buildView(obj, parent)
            gg = obj.buildReportInstr(parent);
            uilabel(gg, 'Text', sprintf(['The Visualizer-01 main dashboard opens in its own ' ...
                'maximized window (1:1 with the old figure).\n\nUse the controls on the left ' ...
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
            mask = mask(:) & obj.frGroupMask(obj.LastD, viz.plots.V01util.nU(obj.LastD));   % honor the dFr filter
            state = struct('group', obj.groupDD.Value, 'index', obj.indexDD.Value, 'mask', mask(:));
            dOp = char(916);   % Greek capital delta (as a var so the following 'F' is not eaten by the \x hex escape)
            hdr = sprintf(['Visualizer-01 dashboard \x2014 index %s, group %s.  ' dOp 'Fr-vs-' dOp 'metric ' ...
                'regressions, dFr-binned Control-vs-Laser signranks, gain-slope ranksum (sim scatter is ' ...
                'model-based, omitted).'], obj.indexDD.Value, obj.groupDD.Value);
            rs = struct('figKey','V01', 'state',state, 'D',obj.LastD, 'header',hdr);
        end

        function openFigure(obj)
            if ~isempty(obj.PlotFig) && isvalid(obj.PlotFig)
                figure(obj.PlotFig); obj.drawFigure(); obj.refreshStatus(); return;
            end
            ss = get(0,'screensize'); Mx = ss(3); My = ss(4);
            obj.PlotFig = uifigure('Name','Visualizer 01 - Main dashboard (f)', 'Color','w', ...
                'Position', [0, round(.03*My), Mx, round(.95*My)]);
            obj.PlotFig.CloseRequestFcn = @(s,e) delete(s);
            obj.LayoutSpec = {};
            obj.createPanels();
            try, obj.PlotFig.AutoResizeChildren = 'off'; catch, end %#ok<CTCH>
            obj.PlotFig.SizeChangedFcn = @(s,e) obj.relayout();
            obj.relayout(); obj.drawFigure(); obj.refreshStatus();
        end

        function s = getControlState(obj)
            s = struct('group',obj.groupDD.Value,'index',obj.indexDD.Value,'model',obj.modelDD.Value, ...
                'rep',obj.repDD.Value,'norm',obj.normDD.Value,'cond',obj.condSwitch.Value, ...
                'unit',obj.unitSlider.Value,'sel',obj.SelectedUnit, 'frGroups',{obj.FrGroups}, ...
                'fitAllI',obj.fitAllI());
        end
        function setControlState(obj, s)
            f = {'group','groupDD';'index','indexDD';'model','modelDD';'rep','repDD';'norm','normDD';'cond','condSwitch';'unit','unitSlider'};
            for k=1:size(f,1), if isfield(s,f{k,1}), obj.setCtrl(obj.(f{k,2}), s.(f{k,1})); end, end
            if isfield(s,'fitAllI'), obj.setCtrl(obj.fitAllICB, logical(s.fitAllI)); end
            if isfield(s,'sel'), obj.SelectedUnit = s.sel; end
            if isfield(s,'frGroups'), obj.FrGroups = s.frGroups; obj.applyFrToLB(); end
        end

        % ---- external composition (viz.plots.PaperFig01Tab) ---------- %
        function [kind, slot] = specForAxes(obj, ax)
            %SPECFORAXES  If AX is one of this dashboard's yyaxis panels (which copyobj
            %   cannot clone), return the paperDraw spec so a caller can native-redraw
            %   it instead of snapshotting. Empty kind = not a recognised yyaxis panel.
            kind = ''; slot = 0;
            try
                if numel(obj.uDratio) >= 1 && isequal(ax, obj.uDratio{1}), kind = 'ratio';    slot = 1; return; end
                if numel(obj.uDratio) >= 2 && isequal(ax, obj.uDratio{2}), kind = 'ratio';    slot = 2; return; end
                if numel(obj.uPop8)   >= 2 && isequal(ax, obj.uPop8{2}),   kind = 'popRatio'; slot = 1; return; end
                if numel(obj.uPop8)   >= 1 && isequal(ax, obj.uPop8{1}),   kind = 'popRatio'; slot = 2; return; end
            catch
            end
        end
        function paperDraw(obj, ax, kind, slot)
            %PAPERDRAW  Draw ONE dashboard panel into an EXTERNAL axes with the SAME
            %   drawer the dashboard uses -- no copyobj, no exportgraphics snapshot.
            %   Call prepareReps first to select the group's example units.
            %   kind: 'ctrlRaster'|'laserRaster'|'tuning'|'ratio'|'io'|'popMean'|'popRatio'
            %   slot: 1 = E/PVA (green), 2 = I/PVI (blue)
            D = obj.LastD;
            if isempty(D) || isempty(ax) || ~isgraphics(ax), return; end
            if slot == 1, u = obj.SecondUnit;   Cc = obj.COL_E; rep = obj.ERep;
            else,         u = obj.SelectedUnit; Cc = obj.COL_I; rep = obj.IRep; end
            try
                switch kind
                    case {'ctrlRaster','laserRaster'}
                        if ~isfinite(u), return; end
                        oriN = 24;
                        if isfield(D,'Ori_N'), v = double(D.Ori_N(u)); if isfinite(v) && v >= 2, oriN = round(v); end, end
                        timing = [-0.5 1 2];
                        if isfield(D,'Rast_time'), tt = D.Rast_time(u,:); if numel(tt) >= 3 && all(isfinite(tt)), timing = tt; end, end
                        isLaser = strcmp(kind, 'laserRaster');
                        fld = 'RasNL'; if isLaser, fld = 'RasL'; end
                        obj.drawRasterInto(ax, rasOf(D, fld, u), oriN, isLaser, timing, Cc);
                    case 'tuning',   if isfinite(u), obj.drawTunInto(ax, D, u, Cc, slot == 1); end
                    case 'ratio',    if isfinite(u), obj.drawDratioInto(ax, D, u, slot == 1); end
                    case 'io',       if isfinite(u), obj.drawIOInto(ax, D, u); end
                    case 'popMean'
                        lc = [.4 1 .4]; if slot == 2, lc = [.4 .4 1]; end
                        obj.drawPopMeanTwo(ax, D, rep, lc);
                    case 'popRatio', obj.drawPopDeltaRatio(ax, D, rep, slot == 1, true);
                end
            catch
            end
        end
    end

    % =================================================================== %
    methods (Access = private)
        function refreshStatus(obj)
            isOpen = ~isempty(obj.PlotFig) && isvalid(obj.PlotFig);
            if isOpen, obj.statusLbl.Text = 'window: open'; else, obj.statusLbl.Text = 'window: closed (click Open)'; end
        end

        function n = nUniq(~, v)
            %NUNIQ  Number of distinct finite values (neuron count from a U_unity list).
            v = double(v(:)); v = v(isfinite(v)); n = numel(unique(v));
        end

        function tf = fitAllI(obj)
            %FITALLI  True when the "Fit line: PVI all dFr>0" checkbox is ticked, i.e.
            %   the I-side scatter regression drops the V01/paper 0<dFr<200 upper cap.
            %   False (paper-faithful) whenever the control does not exist yet.
            tf = false;
            try, tf = ~isempty(obj.fitAllICB) && isvalid(obj.fitAllICB) && logical(obj.fitAllICB.Value); catch, end %#ok<CTCH>
        end

        % ---- dFr-change group filter (E: 3 bands, I: 4 bands) ---------- %
        % Restricts which units are shown across EVERY panel; bands mirror the
        % drawBoxAndStats gE/gI boundaries exactly. Same control as the layer tabs.
        function m = frGroupMask(obj, D, N)
            if isempty(obj.FrGroups), m = true(N,1); return; end
            dfr = 100 * obj.colv(D, 'Delta_Fr', N);     % laser FR change (%)
            isI = obj.isInhib(D);
            m = false(N,1);
            for k = 1:numel(obj.FrGroups)
                switch obj.FrGroups{k}
                    case 'E:low',    m = m | (~isI & dfr >= -33 & dfr <  0);
                    case 'E:medium', m = m | (~isI & dfr >= -66 & dfr < -33);
                    case 'E:high',   m = m | (~isI & dfr <  -66);
                    case 'I:low',    m = m | ( isI & dfr >   0 & dfr <=  33);
                    case 'I:medium', m = m | ( isI & dfr >  33 & dfr <=  66);
                    case 'I:high',   m = m | ( isI & dfr >  66 & dfr <= 100);
                    case 'I:xhigh',  m = m | ( isI & dfr > 100);
                end
            end
            m = m(:);
        end
        function onFrChanged(obj)
            v = obj.frLB.Value;
            if ischar(v), v = {v}; elseif isstring(v), v = cellstr(v); end
            if isempty(v) || any(strcmp(v, '(all groups)'))
                obj.FrGroups = {};
            else
                keys = {};
                for k = 1:numel(v)
                    idx = find(strcmp(obj.FR_ITEMS, v{k}), 1);   % display label -> key (idx 1 = '(all groups)')
                    if ~isempty(idx) && idx >= 2, keys{end+1} = obj.FR_KEYS{idx}; end %#ok<AGROW>
                end
                obj.FrGroups = keys;
            end
            obj.requestRefresh();
        end
        function applyFrToLB(obj)
            if isempty(obj.frLB) || ~isvalid(obj.frLB), return; end
            if isempty(obj.FrGroups), obj.frLB.Value = '(all groups)'; return; end
            items = {};
            for k = 1:numel(obj.FrGroups)
                idx = find(strcmp(obj.FR_KEYS, obj.FrGroups{k}), 1);
                if ~isempty(idx), items{end+1} = obj.FR_ITEMS{idx}; end %#ok<AGROW>
            end
            items = items(ismember(items, obj.frLB.Items));
            if isempty(items), obj.frLB.Value = '(all groups)'; obj.FrGroups = {};
            else,              obj.frLB.Value = items; end
        end

        function createPanels(obj)
            obj.axScatter = obj.addAx(.005, .60, .35, .35);
            obj.axSim     = obj.addAx(.005, .23, .35, .35);
            obj.axBox     = obj.addAx(.37, .615, .35, .335);
            obj.axHist    = obj.addAx(.37, .44, .09, .12);
            obj.axPopE    = obj.addAx(.50, .44, .09, .12);
            obj.axPopI    = obj.addAx(.50, .30, .09, .12);
            obj.axLTM  = obj.addAx(.33, .01, .20, .25);
            obj.axIO      = obj.addAx(.62, .26, .10, .20);
            obj.axSlope   = obj.addAx(.62, .46, .11, .14);
            tp = uipanel(obj.PlotFig, 'Units','pixels', 'BorderType','none');
            obj.LayoutSpec{end+1} = {tp, [.03 0 .30 .15]};
            tgl = uigridlayout(tp, [1 1]); tgl.Padding = [0 0 0 0];
            obj.statsTable = uitable(tgl, 'FontSize', obj.FONT-2);
            obj.uRasL = cell(1,2); obj.uRasNL = cell(1,2); obj.uTun = cell(1,2);
            obj.uDratio = cell(1,2); obj.uPolar = cell(1,2); obj.uIO = cell(1,2);
            obj.uPop6 = cell(1,2); obj.uPop8 = cell(1,2);
            % PAPER Figure 1 B+D as a clean 2-column x 7-row grid (D/M side). Columns:
            % i=1 -> PVA/E (left, x .76), i=2 -> PVI/I (right, x .88); population panels
            % use (3-i) so PVE/green sits under the green example column. Rows top->bottom:
            % raster-control, raster-laser, tuning, RT/dT, I/O, pop mean-normalized,
            % pop mean-RT/dT. The circular (polar) tunings sit to the LEFT (centre),
            % pulled in to open space for the grid. Sizes (w,h) unchanged -- x/y only.
            for i = 1:2
                obj.uRasNL{i}  = obj.addAx(.64+.12*i, .80, .10, .11);       % row1: raster control (top)
                obj.uRasL{i}   = obj.addAx(.64+.12*i, .68, .10, .11);       % row2: raster laser
                obj.uTun{i}    = obj.addAx(.64+.12*i, .55, .10, .10);       % row3: orientation tuning
                obj.uDratio{i} = obj.addAx(.64+.12*i, .47, .10, .05);       % row4: delta-ratio RT/dT (width matched to uTun)
                obj.uIO{i}     = obj.addAx(.64+.12*i, .32, .10, .12);       % row5: I/O model fit
                obj.uPop6{i}   = obj.addAx(.64+.12*(3-i), .18, .10, .10);   % row6: population mean-normalized tuning
                obj.uPop8{i}   = obj.addAx(.64+.12*(3-i), .10, .10, .05);   % row7: population mean RT/dT (width matched to uPop6)
                obj.uPolar{i}  = obj.addPolar(.42+.10*i, .06, .08, .08);    % circular tuning pulled LEFT (centre)
            end
            obj.createLabels();
        end

        function ax = addAx(obj, fx, fy, fw, fh)
            ax = uiaxes(obj.PlotFig); ax.Units = 'pixels'; ax.FontUnits = 'points';
            ax.FontSize = obj.FONT; ax.LineWidth = obj.LW;
            obj.LayoutSpec{end+1} = {ax, [fx fy fw fh]};
        end
        function ax = addPolar(obj, fx, fy, fw, fh)
            ax = polaraxes(obj.PlotFig); ax.Units = 'pixels'; ax.FontUnits = 'points'; ax.FontSize = obj.FONT;
            ax.LineWidth = obj.LW;                 % V01 sets LineWidth on every per-unit axis incl. the polar
            obj.LayoutSpec{end+1} = {ax, [fx fy fw fh]};
        end
        function [ax, t] = addLabel(obj, fx, fy, fw, fh, txt, rot, fsz, bold, key)
            % floating axis-label = invisible uiaxes holding one rotated text at (0,0),
            % positioned in figure fractions (V01 F2_5B_3 T1/T2/T4 labels). Returns the
            % text handle `t` too, so paper-style-dependent labels can be retuned live.
            % Optional `key` registers the handle in obj.LblMap so applyPaperLabels can
            % swap it to the paper Fig 1 writing in paper mode.
            ax = uiaxes(obj.PlotFig); ax.Units = 'pixels'; ax.Visible = 'off';
            t = text(ax, 0, 0, txt, 'Color','k', 'Rotation',rot, 'FontUnits','points', 'FontSize',fsz);
            if bold, t.FontWeight = 'bold'; end
            obj.LayoutSpec{end+1} = {ax, [fx fy fw fh]};
            if nargin >= 10 && ~isempty(key), obj.LblMap.(key) = t; end
        end
        function createLabels(obj)
            % figure-f floating labels ported verbatim from F2_5B_3 (Parent f): T1 panel
            % letters, T2 population-TC labels + dFr legend, T4 per-unit/pop panel labels.
            F = obj.FONT;
            obj.addLabel(0,   .91, .10, .10, 'A', 0, 2*F, true);     % T1 panel letters
            obj.addLabel(.36, .91, .10, .10, 'B', 0, 2*F, true);
            obj.addLabel(0,   .55, .10, .10, 'C', 0, 2*F, true);
            obj.addLabel(.36, .55, .10, .10, 'D', 0, 2*F, true);
            obj.addLabel(.48, .35, .04, .20, 'Normalized Firing Rate', 90, F, false, 'popTCy');   % T2 (-> 'Mean normalized response')
            obj.addLabel(.49, .275,.04, .20, 'Angle from peak ( \circ )', 0, F, false);          % already matches paper
            obj.addLabel(.49, .55, .20, .05, 'Population Average TC', 0, F, true, 'popTCtitle');  % (hidden in paper: no panel title)
            % --- paper Fig 1 B+D grid writings (positions follow the 2x7 grid above) ---
            obj.addLabel(.74, .74, .04, .20, 'Drift Direction', 90, F, false, 'rasY');   % rasters y (-> 'Trials/drift direction')
            obj.addLabel(.82, .53, .04, .40, 'Drift Direction', 0, F, false, 'tunX');    % tuning x (-> 'Drift direction')
            obj.addLabel(.82, .16, .04, .20, 'Drift Direction', 0, F, false, 'pop6X');   % pop mean-tuning x (-> 'Angle from peak')
            obj.addLabel(.84, .28, .04, .20, 'Population Tuning', 0, F, false, 'popTunTitle');    % (hidden in paper: no panel title)
            obj.addLabel(.82, .65, .04, .40, 'Time(s)', 0, F, false, 'rasX');            % rasters x (-> 'Time from stimulus onset (s)')
            obj.addLabel(.74, .57, .04, .20, 'Firing Rate (spk/s)', 90, F, false, 'tunY');   % tuning y (-> 'Response (spk/s)')
            obj.addLabel(.74, .18, .04, .20, 'Firing Rate (spk/s)', 90, F, false, 'pop6Y');   % pop6 y (-> 'Mean normalized response')
            [~, obj.lblRD_pop]  = obj.addLabel(.72, .10, .04, .20, 'Ratio Delta', 90, F, false);   % pop8 y (-> Mean RT/dT in paper mode)
            [~, obj.lblRD_unit] = obj.addLabel(.72, .47, .04, .20, 'Ratio Delta', 90, F, false);   % dratio y (-> RT/dT in paper mode)
            obj.addLabel(.74, .35, .04, .20, 'Pyr Cell response, Laser ON (%)', 90, F, false, 'ioY');  % IO y (-> 'Response (%) laser')
            obj.addLabel(.82, .30, .04, .20, 'Pyr Cell response, Control (%)', 0, F, false, 'ioX');    % IO x (-> 'Response (%) Control')
            obj.addLabel(.72, .80, .04, .11, 'Control', 90, F, false);                  % raster row label (control), rotated like the paper
            obj.addLabel(.72, .68, .04, .11, 'Laser ON', 90, F, false, 'laserHdr');      % raster row label (-> 'Laser'), rotated
            obj.addLabel(.55, .16, .04, .40, 'Polar Plot', 0, F, false, 'polarHdr');     % (hidden in paper; over the centred polar)
            obj.addLabel(.84, .44, .04, .40, 'Threshold-linear fit', 0, F, false, 'thrFit');   % (hidden in paper)
            obj.addLabel(.84, .65, .04, .40, 'Tuning Curve', 0, F, false, 'tunCurve');   % (hidden in paper)
            [~, obj.lblPVE] = obj.addLabel(.77, .915, .04, .40, 'PVE', 0, F, true);      % column header PVA/PVE (over col 1)
            [~, obj.lblPVI] = obj.addLabel(.89, .915, .04, .40, 'PVI', 0, F, true);      % column header PVI (over col 2)
            % T2{4} dFr-group legend: Low/Medium/High/Extra High, colored + stacked
            axL = uiaxes(obj.PlotFig); axL.Units = 'pixels'; axL.Visible = 'off';
            leg = {'Low','\n\nMedium','\n\n\n\nHigh','\n\n\n\n\n\nExtra High'};
            for k = 1:4
                text(axL, 0, 0, sprintf(leg{k}), 'Color', obj.COL2_4{k}, 'FontWeight','bold', 'FontUnits','points', 'FontSize', F);
            end
            obj.LayoutSpec{end+1} = {axL, [.37 .35 .15 .30]};
        end
        function applyPaperLabels(obj)
            %APPLYPAPERLABELS  Retune the persistent figure labels to the paper-style
            %   key: PVE/PVI titles become colored PVA/PVI, and the black 'Ratio Delta'
            %   y-labels hide (the colored RT/dT and Mean RT/dT labels are drawn in the
            %   panels instead). Runs every drawFigure so the master key flips them live.
            paper = viz.paperStyle();
            if ~isempty(obj.lblPVE) && isvalid(obj.lblPVE)
                if paper, obj.lblPVE.String = 'PVA'; obj.lblPVE.Color = viz.Colors.PVA;
                else,     obj.lblPVE.String = 'PVE'; obj.lblPVE.Color = [0 0 0]; end
            end
            if ~isempty(obj.lblPVI) && isvalid(obj.lblPVI)
                if paper, obj.lblPVI.Color = viz.Colors.PVI; else, obj.lblPVI.Color = [0 0 0]; end
            end
            for h = [obj.lblRD_pop, obj.lblRD_unit]         % black 'Ratio Delta' labels: off in paper mode
                if ~isempty(h) && isvalid(h)
                    if paper, h.Visible = 'off'; else, h.Visible = 'on'; end
                end
            end
            % Retune the per-unit / population axis labels to the PAPER FIGURE 1 writings
            % in paper mode (same floating-label positions -> relative to their plots, no
            % change to plot boxes); restore the internal Visualizer-01 wording otherwise.
            % Hidden-in-paper keys are Dashboard-only panels absent from paper Fig 1.
            T = obj.paperLabelTable();
            for r = 1:size(T,1)
                key = T{r,1};
                if ~isfield(obj.LblMap, key), continue; end
                h = obj.LblMap.(key); if isempty(h) || ~isvalid(h), continue; end
                if paper
                    if T{r,3}, h.Visible = 'off';
                    else,      h.Visible = 'on'; h.String = T{r,2}; end
                else
                    h.Visible = 'on'; h.String = obj.lblInternal(key);
                end
            end
        end
        function T = paperLabelTable(~)
            %PAPERLABELTABLE  key -> {paperString, hideInPaper}. In paper mode each keyed
            %   floating label shows the paper Fig 1 writing (or hides if it is a
            %   Dashboard-only panel). Internal (non-paper) wording comes from lblInternal.
            T = { ...
              'rasY',        'Trials/drift direction',       false; ...
              'rasX',        'Time from stimulus onset (s)', false; ...
              'tunY',        'Response (spk/s)',             false; ...
              'tunX',        'Drift direction',              false; ...
              'ioY',         'Response (%) laser',           false; ...
              'ioX',         'Response (%) Control',         false; ...
              'laserHdr',    'Laser',                        false; ...
              'popTCy',      'Mean normalized response',     false; ...
              'pop6Y',       'Mean normalized response',     false; ...
              'pop6X',       'Angle from peak ( \circ )',    false; ...
              'polarHdr',    '',                             true;  ...
              'thrFit',      '',                             true;  ...
              'tunCurve',    '',                             true;  ...
              'popTCtitle',  '',                             true;  ...
              'popTunTitle', '',                             true;  ...
            };
        end
        function s = lblInternal(~, key)
            %LBLINTERNAL  the ORIGINAL Visualizer-01 wording for a keyed label (restored
            %   when paper mode is off).
            switch key
                case 'rasY',        s = 'Drift Direction';
                case 'rasX',        s = 'Time(s)';
                case 'tunY',        s = 'Firing Rate (spk/s)';
                case 'tunX',        s = 'Drift Direction';
                case 'ioY',         s = 'Pyr Cell response, Laser ON (%)';
                case 'ioX',         s = 'Pyr Cell response, Control (%)';
                case 'laserHdr',    s = 'Laser ON';
                case 'popTCy',      s = 'Normalized Firing Rate';
                case 'pop6Y',       s = 'Firing Rate (spk/s)';
                case 'pop6X',       s = 'Drift Direction';
                case 'polarHdr',    s = 'Polar Plot';
                case 'thrFit',      s = 'Threshold-linear fit';
                case 'tunCurve',    s = 'Tuning Curve';
                case 'popTCtitle',  s = 'Population Average TC';
                case 'popTunTitle', s = 'Population Tuning';
                otherwise,          s = '';
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
            if viz.paperStyle()                    % paper: the delta/ratio panels are 1.3x TALLER (the x-arrows/numbers made them look short)
                kDR = 1.3; h0 = 0.05; hh = kDR*h0;   % .05 -> .065
                for i = 1:2                        % per-unit RT/dT: grow centred (base y .47); population Mean RT/dT: grow downward (top .15)
                    if numel(obj.uDratio)>=i && ~isempty(obj.uDratio{i}) && isvalid(obj.uDratio{i})
                        obj.uDratio{i}.Position = [(.64+.12*i)*W, ((.47-0.5*(hh-h0))/0.95)*H, .10*W, (hh/0.95)*H];
                    end
                    if numel(obj.uPop8)>=i && ~isempty(obj.uPop8{i}) && isvalid(obj.uPop8{i})
                        obj.uPop8{i}.Position = [(.64+.12*(3-i))*W, ((.15-hh)/0.95)*H, .10*W, (hh/0.95)*H];
                    end
                end
            end
        end

        % ---- main draw ------------------------------------------------ %
        function drawFigure(obj)
            D = obj.LastD; mask = obj.LastMask;
            if isempty(D) || isempty(obj.PlotFig) || ~isvalid(obj.PlotFig), return; end
            obj.relayout(); obj.clearAll();
            obj.applyPaperLabels();                 % retune the persistent titles/labels to the paper-style key
            cfg = obj.indexCfg(obj.indexDD.Value);
            if ~isfield(D, cfg.delta), title(obj.axScatter, sprintf('Missing %s', cfg.delta)); return; end
            try, grpMask = analysis.tuningGroupMask(D, obj.groupDD.Value);
            catch err, title(obj.axScatter, ['Group error: ' err.message]); return; end
            isI = obj.isInhib(D);
            sel = mask(:) & grpMask(:) & obj.frGroupMask(D, obj.nU(D));   % honor the dFr-change filter
            eIdx = find(sel & ~isI); iIdx = find(sel & isI);
            % Size of the selected TuningG group per side, as observations / distinct
            % neurons (U_unity) -- printed on a0{1} under the r/p/n of each fit. Counted
            % BEFORE the repeated-obs reduction, so it does not move with the "Repeated
            % obs" dropdown; it DOES honor the toolbar filters and the dFr-change filter.
            UUa = obj.colv(D, 'U_unity', numel(sel));
            obj.GrpCounts = struct('eObs',numel(eIdx), 'eNeur',obj.nUniq(UUa(eIdx)), ...
                                   'iObs',numel(iIdx), 'iNeur',obj.nUniq(UUa(iIdx)));
            dFr2 = 100 * obj.colv(D, 'Delta_Fr', numel(sel));
            Yall = obj.colv(D, cfg.delta, numel(sel));
            mode = obj.repDD.Value;
            Re = obj.makeReducer(D, eIdx, mode); Ri = obj.makeReducer(D, iIdx, mode);
            Xe = obj.redVec(Re, dFr2(eIdx)); Ye = obj.redVec(Re, Yall(eIdx)); eRep = obj.redIdx(Re);
            Xi = obj.redVec(Ri, dFr2(iIdx)); Yi = obj.redVec(Ri, Yall(iIdx)); iRep = obj.redIdx(Ri);
            % Curve reps for the population TUNING panels honor the stat option: 'mean'
            % and 'lme' need EVERY observation per neuron (curveGroups then averages
            % per neuron -> the per-neuron mean curve, matching the reports); the
            % scatter/box/scalar panels keep the reduced Xe/eRep. For 'lme' these
            % already equal Xe/eRep; for 'first'/'maxpow'/'all' the reduced rep is used.
            if obj.aggCurve()
                XeC = dFr2(eIdx); eRepC = eIdx(:);   XiC = dFr2(iIdx); iRepC = iIdx(:);
            else
                XeC = Xe; eRepC = eRep;              XiC = Xi; iRepC = iRep;
            end

            % Mixed-effects DISPLAY versions of the scatter / histogram scalars: under
            % 'lme' one point per NEURON (each neuron's observations averaged) + the
            % per-neuron representative rows for ring/pick; identity in every other
            % mode. The box panel keeps the raw obs (Xe/Ye/eRep) -- it aggregates and
            % runs its LME star internally.
            [eRepD, eGi, neE] = obj.neurGroups(eRep);
            [iRepD, iGi, neI] = obj.neurGroups(iRep);
            XeD = obj.aggVec(Xe, eGi, neE); YeD = obj.aggVec(Ye, eGi, neE);
            XiD = obj.aggVec(Xi, iGi, neI); YiD = obj.aggVec(Yi, iGi, neI);

            mainTtl = sprintf('V1 Single units     N-Exc = %d     N-inh = %d', numel(eRepD), numel(iRepD));
            obj.drawScatterCore(obj.axScatter, D, cfg, XeD, YeD, eRepD, XiD, YiD, iRepD, mainTtl, ...
                struct('isSim',false, 'interactive',true, 'overlayAx',[]));
            mdl = obj.modelDD.Value; simField = [mdl '_Delta_' cfg.idxKey];
            if isfield(D, simField)
                Ym = obj.colv(D, simField, numel(sel));
                % V01 a0{2}: X is the MODEL's predicted per-unit dFr (not the measured
                % Delta_Fr), so the panel shows the model's own dSi-vs-dFr self-consistency.
                % Here it is the sum-based dFr of the ExpM/LTM predicted curve vs control.
                Xse = obj.redVec(Re, obj.simDeltaFr(D, eIdx, mdl, false));
                Xsi = obj.redVec(Ri, obj.simDeltaFr(D, iIdx, mdl, true));
                XseD = obj.aggVec(Xse, eGi, neE); YmED = obj.aggVec(obj.redVec(Re, Ym(eIdx)), eGi, neE);
                XsiD = obj.aggVec(Xsi, iGi, neI); YmID = obj.aggVec(obj.redVec(Ri, Ym(iIdx)), iGi, neI);
                obj.drawScatterCore(obj.axSim, D, cfg, XseD, YmED, eRepD, ...
                    XsiD, YmID, iRepD, obj.simTitle(), ...
                    struct('isSim',true, 'interactive',false, 'overlayAx',obj.axScatter));
            else
                title(obj.axSim, sprintf('Missing %s', simField));
            end
            % Scalar/stat panels: the per-neuron modes ('mean'/'lme') hand these
            % the OBSERVATION rows -- neurGroups/aggVec inside collapse each neuron
            % to its mean, and the box/slope statistics see every observation.
            if obj.aggLme()
                eRepS = eIdx(:); iRepS = iIdx(:);
                XeB = dFr2(eIdx); YeB = Yall(eIdx); XiB = dFr2(iIdx); YiB = Yall(iIdx);
            else
                eRepS = eRep; iRepS = iRep; XeB = Xe; YeB = Ye; XiB = Xi; YiB = Yi;
            end
            obj.drawIO(D, eRepS, iRepS);        % Ax_r{1}: ALWAYS linear-threshold
            obj.drawSlope(D, eRepS, iRepS);     % Ax_r{2}: ALWAYS linear-threshold slope
            obj.drawBoxAndStats(D, cfg, XeB, YeB, eRepS, XiB, YiB, iRepS, mode);
            obj.drawHist(XeD, XiD);             % a2{8}: per-neuron dFr under Mixed-effects
            obj.drawPopulation(D, XeC, eRepC, obj.axPopE, true);   % a2{9}
            obj.drawPopulation(D, XiC, iRepC, obj.axPopI, false);  % a2{10}
            obj.drawLTM(D, eRepS, iRepS);
            % I{i,6} population mean tuning, I{i,8} population delta/ratio (curve reps)
            obj.drawPopMeanTwo(obj.uPop6{2}, D, eRepC, [.4 1 .4]);   % I{2,6} PVE
            obj.drawPopMeanTwo(obj.uPop6{1}, D, iRepC, [.4 .4 1]);   % I{1,6} PVI
            obj.drawPopDeltaRatio(obj.uPop8{2}, D, eRepC, true,  true);    % I{2,8} PVE (now LEFT column: Mean RT/dT labels)
            obj.drawPopDeltaRatio(obj.uPop8{1}, D, iRepC, false, false);   % I{1,8} PVI (now right column: no label)

            obj.ERep = eRep(:); obj.IRep = iRep(:);
            obj.syncSelection();
            obj.drawPerUnit(D);
            obj.matchPlotWidths();
            obj.updateUnitLabel();
        end

        function clearAll(obj)
            ax = {obj.axScatter, obj.axSim, obj.axBox, obj.axLTM, obj.axPopE, obj.axPopI, obj.axHist, obj.axIO, obj.axSlope};
            for i = 1:numel(ax), if isvalid(ax{i}), cla(ax{i}); end, end
            for i = 1:2
                for h = [obj.uRasL(i) obj.uRasNL(i) obj.uTun(i) obj.uIO(i) obj.uPop6(i)]
                    if isvalid(h{1}), cla(h{1}); end
                end
                try, cla(obj.uPolar{i}); catch, end %#ok<CTCH>
                obj.clearYY(obj.uDratio{i}); obj.clearYY(obj.uPop8{i});
            end
        end
        function clearYY(~, ax)
            try, yyaxis(ax,'left'); cla(ax); yyaxis(ax,'right'); cla(ax); catch, cla(ax); end %#ok<CTCH>
        end

        function cfg = indexCfg(~, name)
            switch upper(name)
                case 'OSI', cfg = struct('delta','Delta_OSI','L','fitOSI_L','NL','fitOSI_NL','ylim',[-0.6 0.7],'label','OSI','idxKey','OSI');
                case 'CV',  cfg = struct('delta','Delta_CV', 'L','fitCV_L', 'NL','fitCV_NL', 'ylim',[-0.65 0.4],'label','CV','idxKey','CV');
                % ylim [-30 30] is for Delta_HBW (laser-control, can be +/-); fitHBW itself is now always >=0 or NaN.
                otherwise,  cfg = struct('delta','Delta_HBW','L','fitHBW_L','NL','fitHBW_NL','ylim',[-30 30],'label','HBW (\circ)','idxKey','HBW');
            end
        end
        function pf = normPrefix(obj)
            switch obj.normDD.Value
                case 'Absolute',  pf = 'fit_mid';
                case 'Self peak', pf = 'fit_mid_self';
                otherwise,        pf = 'fit_mid_nc';
            end
        end

        function v = colv(~, D, name, N)
            if isfield(D, name) && ~isempty(D.(name)), v = double(D.(name)(:)); else, v = nan(N,1); end
        end
        function n = nU(~, D)
            try, n = filter.unitCount(D); catch
                if isfield(D,'EI'), n = numel(D.EI); elseif isfield(D,'fit_NL'), n = size(D.fit_NL,2); else, n = 0; end
            end
        end
        function isI = isInhib(obj, D)
            N = obj.nU(D); isI = false(N,1);
            if isfield(D,'EI'), for k=1:N, isI(k) = strcmpi(strtrim(string(D.EI(k))),"I"); end, end
        end
        function tf = isInhibUnit(~, D, u)
            tf = isfield(D,'EI') && strcmpi(strtrim(string(D.EI(u))),"I");
        end

        function R = makeReducer(~, D, idx, mode)
            idx = idx(:); R.mode = mode; R.idx = idx; n = numel(idx);
            if n == 0, R.g = []; R.nG = 0; R.repsel = []; return; end
            if isfield(D,'U_unity'), uu = double(D.U_unity(idx)); else, uu = (1:n)'; end
            [u,~,g] = unique(uu(:), 'stable'); R.g = g; R.nG = numel(u);
            if any(strcmp(mode, {'all','lme'})), R.repsel = (1:n)';
            else
                repsel = zeros(R.nG,1); useP = strcmp(mode,'maxpow') && isfield(D,'LPow');
                if useP, lp = double(D.LPow(idx)); end
                for j = 1:R.nG, m = find(g==j); if useP, [~,a]=max(lp(m)); repsel(j)=m(a); else, repsel(j)=m(1); end, end
                R.repsel = repsel;
            end
        end
        function out = redVec(~, R, v)
            if isempty(R.idx), out = []; return; end
            if strcmp(R.mode,'mean'), out = accumarray(R.g, v(:), [], @(z) mean(z,'omitnan')); else, out = v(R.repsel); end
        end
        function out = redIdx(~, R)
            if isempty(R.idx), out = []; else, out = R.idx(R.repsel); end
        end

        % ---- Mixed-effects DISPLAY helpers ---------------------------- %
        % Under "Mean per neuron" AND "Mixed-effects (stats)" every POPULATION
        % panel shows one value / curve per NEURON (each neuron's observations
        % averaged) so the picture respects the repeated recordings -- the same
        % per-neuron reduction the box / slope statistics use. 'all'/'first'/
        % 'maxpow' are unchanged: the helpers below are identity no-ops there,
        % so the validated figure renders byte-identically in those modes.
        function tf = aggLme(obj)
            %AGGLME  Per-neuron display modes: 'mean' AND 'lme'. Both collapse each
            %   neuron's observations to ONE displayed value; the scalar/stat panels
            %   are handed OBSERVATION rows in these modes (drawFigure), so the
            %   neurGroups/aggVec helpers below do the collapsing.
            tf = any(strcmp(obj.repDD.Value, {'mean','lme'}));
        end
        function tf = aggCurve(obj)
            %AGGCURVE  Per-neuron curve averaging for the POPULATION TUNING curves:
            %   'mean' AND 'lme' both average each neuron's observation-curves first
            %   (matching the stat reports / box per-neuron reduction). The SCALAR/
            %   scatter panels keep their own aggLme() (lme-only) gate, so only the
            %   tuning curves gain the 'mean' correction.
            tf = any(strcmp(obj.repDD.Value, {'mean','lme'}));
        end
        function [rep2, gi, nG] = curveGroups(obj, rep)
            %CURVEGROUPS  Like neurGroups but keyed on aggCurve() (mean OR lme), used
            %   only by the population TUNING curve drawers so 'Mean per neuron' shows
            %   the per-neuron mean curve, not the first-obs curve.
            rep = rep(:); n = numel(rep);
            if ~obj.aggCurve() || n == 0, rep2 = rep; gi = (1:n)'; nG = n; return; end
            uu = obj.colv(obj.LastD, 'U_unity', obj.nU(obj.LastD));
            [~, ~, gi] = unique(uu(rep), 'stable'); nG = max(gi);
            rep2 = zeros(nG,1);
            for j = 1:nG, k = find(gi==j,1); rep2(j) = rep(k); end
        end
        function [rep2, gi, nG] = neurGroups(obj, rep)
            %NEURGROUPS  Group rep rows by neuron (U_unity). Under 'lme': rep2 = a
            %   representative (first) row per neuron, gi maps each input row to its
            %   neuron group (1..nG), nG = #neurons. Else identity (rep2=rep, gi=1:n).
            rep = rep(:); n = numel(rep);
            if ~obj.aggLme() || n == 0, rep2 = rep; gi = (1:n)'; nG = n; return; end
            uu = obj.colv(obj.LastD, 'U_unity', obj.nU(obj.LastD));
            [~, ~, gi] = unique(uu(rep), 'stable'); nG = max(gi);
            rep2 = zeros(nG,1);
            for j = 1:nG, k = find(gi==j,1); rep2(j) = rep(k); end
        end
        function vN = aggVec(~, v, gi, nG)
            %AGGVEC  Collapse a scalar vector to per-neuron means by gi/nG (no-op
            %   when gi is 1:nG, i.e. non-lme).
            v = v(:);
            if nG == numel(v) && isequal(gi(:).', 1:nG), vN = v; return; end
            vN = accumarray(gi(:), v, [nG 1], @(z) mean(z, 'omitnan'));
        end
        function MN = aggCols(~, M, gi, nG)
            %AGGCOLS  Collapse matrix columns (samples x n) to per-neuron mean
            %   columns (samples x nG) by gi/nG (no-op when identity).
            if nG == size(M,2) && isequal(gi(:).', 1:nG), MN = M; return; end
            MN = zeros(size(M,1), nG);
            for j = 1:nG, MN(:,j) = mean(M(:, gi==j), 2, 'omitnan'); end
        end

        % ---- a0{1}/a0{2} ---------------------------------------------- %
        function t = simTitle(obj)
            % V01 a0{2} title switches on the tuning group (Visualizer_01:3095-3102)
            switch obj.groupDD.Value
                case 'ORI_NON_PV_MD', t = 'Simulation of multiplicative/divisive effect';
                case 'ORI_NON_PV_NL', t = 'Simulation of MXH effect';
                otherwise,            t = 'Simulation of All';
            end
        end
        function v = simDeltaFr(~, D, idx, mdl, isI)
            % Model-predicted per-unit firing-rate change (%) from the predicted tuning
            % vs the control: laser-vs-control sum ratio. ExpM predicts the TARGET (E:
            % laser, I: control); LTM predicts the laser. NaN where curves are missing.
            idx = idx(:); n = numel(idx); v = nan(n,1);
            NL = 'fit_mid_nc_NL'; L = 'fit_mid_nc_L';
            if ~isfield(D, NL) || ~isfield(D, L), return; end
            for j = 1:n
                u = idx(j);
                switch mdl
                    case 'ExpM'
                        if ~isfield(D,'ExpM_fit'), return; end
                        if isI, ctrl = D.ExpM_fit(:,u); las = D.(L)(:,u);     % I: predicted control, actual laser
                        else,   ctrl = D.(NL)(:,u);     las = D.ExpM_fit(:,u); % E: actual control, predicted laser
                        end
                    case 'LTM'
                        if ~isfield(D,'LTM_fit_L'), return; end
                        ctrl = D.(NL)(:,u); las = D.LTM_fit_L(:,u);            % predicted laser vs actual control
                    otherwise
                        return;
                end
                sc = sum(ctrl);
                if isfinite(sc) && sc ~= 0, v(j) = 100*(sum(las)-sc)/sc; end
            end
        end
        function drawScatterCore(obj, ax, D, cfg, Xe, Ye, eRep, Xi, Yi, iRep, ttl, opts)
            hold(ax,'on'); cvNL = obj.colv(D,'fitCV_NL', obj.nU(D));
            useSplit = ~opts.isSim;                  % a0{1}: CV red-edge split; a0{2}: plain markers
            if opts.isSim                            % V01 a0{2}: blue (I) drawn first, then green (E)
                obj.scatterSplit(ax, Xi, Yi, iRep, cvNL, obj.COL_I, 0.5, useSplit);
                obj.scatterSplit(ax, Xe, Ye, eRep, cvNL, obj.COL_E, 0.2, useSplit);
            else                                     % V01 a0{1}: green (E) first, then blue (I)
                obj.scatterSplit(ax, Xe, Ye, eRep, cvNL, obj.COL_E, 0.2, useSplit);
                obj.scatterSplit(ax, Xi, Yi, iRep, cvNL, obj.COL_I, 0.5, useSplit);
            end
            plot(ax, [-100 200], [0 0], 'k--'); plot(ax, [0 0], [-100 100], 'k--');
            % E regression on x<0, I regression on 0<x<200 (PV_cell==1). Black dashed +
            % r/p text on this panel; the sim panel also overlays its fits in red on a0{1}.
            % The "Fit line: PVI all dFr>0" checkbox lifts the 200% cap off the I side
            % (E side unchanged); it drives BOTH this panel and the sim panel/overlay.
            if obj.fitAllI(), keepI = Xi > 0; else, keepI = Xi > 0 & Xi < 200; end
            regE = obj.fitReg(Xe(Xe<0),  Ye(Xe<0));
            regI = obj.fitReg(Xi(keepI), Yi(keepI));
            obj.drawReg(ax, regE,  0.1, [0 0 0], true);
            obj.drawReg(ax, regI, -0.1, [0 0 0], true);
            if ~isempty(opts.overlayAx) && isvalid(opts.overlayAx)
                hold(opts.overlayAx,'on');                       % keep a0{1} contents, append the model-fit lines
                ovc = [1 0 0]; if viz.paperStyle(), ovc = [0 1 1]; end   % paper: model-fit line is CYAN (red originally)
                obj.drawReg(opts.overlayAx, regE,  0.1, ovc, false);
                obj.drawReg(opts.overlayAx, regI, -0.1, ovc, false);
            end
            xlim(ax, [-100 200]); ylim(ax, cfg.ylim);
            if viz.paperStyle() && ~opts.isSim                 % paper: group-name title, Delta labels, colored r/p/n + legend
                xlabel(ax, '\DeltaFr (%)'); ylabel(ax, ['\Delta' cfg.label]); title(ax, obj.groupTitle());
                obj.scatterPaperText(ax, regE, regI);
            else
                xlabel(ax, 'Delta Fr %'); ylabel(ax, ['Delta ' cfg.label]); title(ax, ttl);
            end
            if opts.interactive
                ax.ButtonDownFcn = @(s,e) obj.onScatterClick(s, e, [Xe(:);Xi(:)], [Ye(:);Yi(:)], [eRep(:);iRep(:)]);
                obj.registerRing(ax, [Xe(:);Xi(:)], [Ye(:);Yi(:)], [eRep(:);iRep(:)]);   % track unit across plots
                viz.plots.V01util.highlightUnits(ax, [Xe(:);Xi(:)], [Ye(:);Yi(:)], [eRep(:);iRep(:)], [obj.SecondUnit obj.SelectedUnit]);
            end
            hold(ax,'off');
        end
        function scatterSplit(obj, ax, X, Y, rep, cvNL, faceCol, normalLW, useSplit)
            if isempty(X), return; end
            if viz.paperStyle()                      % paper: ratio-sized dots + white ring (red for low-CV CV<=0.8), opaque fill
                sz = viz.plots.V01util.paperDotArea(ax);
                if ~useSplit
                    scatter(ax, X, Y, sz, 'MarkerFaceColor', faceCol, 'MarkerEdgeColor', 'w', 'LineWidth', 0.75); return;
                end
                lo = cvNL(rep) <= 0.8;
                if any(~lo), scatter(ax, X(~lo), Y(~lo), sz, 'MarkerFaceColor', faceCol, 'MarkerEdgeColor', 'w',     'LineWidth', 0.75); end
                if any(lo),  scatter(ax, X(lo),  Y(lo),  sz, 'MarkerFaceColor', faceCol, 'MarkerEdgeColor', [1 0 0], 'LineWidth', 0.75); end
                return;
            end
            if ~useSplit                             % a0{2} sim: plain markers, edge == face, default LineWidth
                scatter(ax, X, Y, obj.SZ, 'MarkerFaceColor', faceCol, 'MarkerEdgeColor', faceCol, 'MarkerFaceAlpha', 0.5);
                return;
            end
            lo = cvNL(rep) <= 0.8;                    % low control-CV -> red edge (V01 I_ext3 / I_inh3)
            if any(~lo), scatter(ax, X(~lo), Y(~lo), obj.SZ, 'MarkerFaceColor', faceCol, 'MarkerEdgeColor', faceCol, 'MarkerFaceAlpha', 0.5, 'LineWidth', normalLW); end
            if any(lo),  scatter(ax, X(lo),  Y(lo),  obj.SZ, 'MarkerFaceColor', faceCol, 'MarkerEdgeColor', [1 0 0], 'MarkerFaceAlpha', 0.5, 'LineWidth', 0.5); end
        end
        function reg = fitReg(~, x, y)
            % OLS line fit; returns endpoints + r/p + text anchor (V01: y = 2*mean(predict)). [] if <2 pts.
            reg = [];
            x = x(:); y = y(:); ok = isfinite(x)&isfinite(y); x=x(ok); y=y(ok);
            if numel(x) < 2, return; end
            try
                R = corrcoef(x,y); r = R(1,2); mdl = fitlm(x,y);
                px = [min(x) max(x)]; py = predict(mdl, px(:));
                reg = struct('px',px(:).', 'py',py(:).', 'r',r, 'p',mdl.Coefficients.pValue(2), ...
                             'xm',mean(x), 'ym',2*mean(predict(mdl,x)), 'n',numel(x));
            catch
            end
        end
        function drawReg(obj, ax, reg, yoff, col, withText)
            if isempty(reg), return; end
            if viz.paperStyle(), ls = '-'; else, ls = '--'; end            % paper: SOLID regression line
            h = plot(ax, reg.px, reg.py, ls, 'Color', col, 'LineWidth', 1);
            try, h.Color(4) = 1; catch, end %#ok<CTCH>
            if withText && ~viz.paperStyle()                               % original: black r/p text near the data
                text(ax, reg.xm, reg.ym + yoff, sprintf('r = %.2f, p = %.4f', reg.r, reg.p), ...
                    'Color','k', 'FontWeight','bold', 'FontSize',obj.FONT);
            end
        end
        function s = groupTitle(obj)
            %GROUPTITLE  Paper-style short title for the current unit group.
            switch obj.groupDD.Value
                case 'ORI_NON_PV_MD', s = 'D/M';
                case 'ORI_NON_PV_NL', s = 'NL';
                case 'ALL_UNITS',     s = 'All units';
                otherwise,            s = strrep(obj.groupDD.Value, '_', ' ');
            end
        end
        function scatterPaperText(obj, ax, regE, regI)
            %SCATTERPAPERTEXT  Paper-style overlay for the main scatter: a colored
            %   PVA/PVI legend and the green/blue italic r/p/n text at the top.
            yl = ylim(ax); span = yl(2) - yl(1);
            text(ax, -55, yl(2)+0.06*span, 'PVA', 'Color',obj.COL_E, 'FontWeight','bold', 'FontSize',obj.FONT, 'HorizontalAlignment','center', 'Clipping','off');
            text(ax,  35, yl(2)+0.06*span, 'PVI', 'Color',obj.COL_I, 'FontWeight','bold', 'FontSize',obj.FONT, 'HorizontalAlignment','center', 'Clipping','off');
            yt = yl(1) + 0.93*span;
            % Line 3 per side: the SELECTED TuningG group's size as obs / neurons
            % (GrpCounts, filled in drawFigure). Line 2's n stays the REGRESSION n --
            % only the dots inside that fit's dFr domain.
            gc = obj.GrpCounts;
            if ~isempty(regE)
                text(ax, -95, yt, sprintf('r = %.2f, p = %.3f\nn = %d\nnE = %d obs / %d cells', ...
                        regE.r, regE.p, regE.n, gc.eObs, gc.eNeur), ...
                    'Color',obj.COL_E, 'FontAngle','italic', 'FontSize',obj.FONT, 'VerticalAlignment','top');
            end
            if ~isempty(regI)
                text(ax, 8, yt, sprintf('r = %.2f, p = %.3f\nn = %d\nnI = %d obs / %d cells', ...
                        regI.r, regI.p, regI.n, gc.iObs, gc.iNeur), ...
                    'Color',obj.COL_I, 'FontAngle','italic', 'FontSize',obj.FONT, 'VerticalAlignment','top');
            end
        end

        % ---- a0{3} box + T10 ------------------------------------------ %
        function drawBoxAndStats(obj, D, cfg, Xe, Ye, eRep, Xi, Yi, iRep, mode)
            gE = { Xe < -66, Xe < -33 & Xe >= -66, Xe >= -33 & Xe < 0 };
            gI = { Xi > 0 & Xi <= 33, Xi > 33 & Xi <= 66, Xi > 66 & Xi <= 100, Xi > 100 };
            labels = {'PVE-H','PVE-M','PVE-L','PVI-L','PVI-M','PVI-H','PVI-extra-H'};
            colors = {obj.COL_E,obj.COL_E,obj.COL_E,obj.COL_I,obj.COL_I,obj.COL_I,obj.COL_I};
            % rawRep = the OBSERVATION rows per dFr group -> feed the paired LME test
            % (groupPValue, which aggregates per neuron itself); rawData the matching
            % Delta values.
            rawData = cell(1,7); rawRep = cell(1,7);
            for k = 1:3, rawData{k} = Ye(gE{k});   rawRep{k} = eRep(gE{k}); end
            for k = 1:4, rawData{3+k} = Yi(gI{k}); rawRep{3+k} = iRep(gI{k}); end
            % DISPLAY data: under Mixed-effects collapse each dFr group to one
            % per-neuron mean (each neuron once within its group) so the boxes/dots +
            % table N/Mean/Std match the per-neuron LME star; other modes show the
            % observations exactly as before. See STATS_MIXED_EFFECTS.md 3e.
            UU = obj.colv(D, 'U_unity', obj.nU(D));
            aggN = obj.aggLme();
            data = cell(1,7); gidx = cell(1,7);
            for k = 1:7
                if aggN
                    [data{k}, ~, gidx{k}] = viz.plots.V01util.aggNeuronScalar(rawData{k}, UU(rawRep{k}), rawRep{k});
                else
                    data{k} = rawData{k}; gidx{k} = rawRep{k};
                end
            end
            if viz.paperStyle(), boxYlab = ['\Delta' cfg.label]; boxTtl = ''; else, boxYlab = ['Delta ' cfg.label]; boxTtl = 'BOX Plot'; end
            jitX = viz.plots.V01util.drawBox(obj.axBox, labels, data, colors, boxYlab, boxTtl, obj.SZ/2, 0.105);   % paper Fig 2/3 box-dot ratio (dot dia ~10.5% of group-column width)
            obj.axBox.XTickLabelRotation = 0;          % V01 (line 1482): horizontal group labels
            ylim(obj.axBox, cfg.ylim);
            Lf = obj.colv(D, cfg.L, obj.nU(D)); Nf = obj.colv(D, cfg.NL, obj.nU(D));
            rows = cell(7,1); redK = false(7,1);
            for k = 1:7
                d = data{k};
                if isempty(rawRep{k}), rows{k} = {labels{k}, 0, NaN, NaN, NaN, NaN, 'ns'}; continue; end
                m = mean(d,'omitnan'); sd = std(d,'omitnan'); se = sd/sqrt(numel(d));
                % p from the OBSERVATIONS (LME under Mixed-effects); display N/Mean/Std
                % are per-neuron under 'lme', per-observation otherwise.
                [p, redK(k)] = obj.groupPValue(D, rawRep{k}, Lf, Nf, mode);
                rows{k} = {labels{k}, numel(d), round(m,3), round(sd,3), round(se,3), p, viz.plots.V01util.sigStars(p)};
            end
            obj.statsTable.Data = cell2table(vertcat(rows{:}), 'VariableNames', {'Group','N','Mean','Std','Ste','p','sig'});
            hold(obj.axBox,'on'); yl = ylim(obj.axBox);
            % V01: a star/ns is written only for groups whose signrank succeeded (finite p);
            % drawSig draws it RED+bold when the mixed-effects significance differs from All.
            for k = 1:7, if isfinite(rows{k}{6}), viz.plots.V01util.drawSig(obj.axBox, k, 0.9*yl(2), rows{k}{6}, redK(k), 'center'); end, end
            hold(obj.axBox,'off');
            % make the box-plot dots clickable -> unit inspector (x = group index 1..7)
            bx = []; by = []; brep = [];
            for k = 1:7
                d = data{k}(:); r = gidx{k}(:); jx = jitX{k}(:);
                if isempty(d), continue; end
                m = min([numel(d) numel(r) numel(jx)]);
                bx = [bx; jx(1:m)]; by = [by; d(1:m)]; brep = [brep; r(1:m)]; %#ok<AGROW>
            end
            obj.enableDotPick(obj.axBox, bx, by, brep);
        end
        function [p, isRed] = groupPValue(~, D, ii, Lf, Nf, mode)
            % Paired Control-vs-Laser p via shared helper (signrank, or LME for 'lme').
            % U_unity(ii) is the neuron id aligned to Lf(ii)/Nf(ii) (same rows ii);
            % the helper drops non-finite pairs (and the matching neur) internally.
            neur = viz.plots.V01util.colv(D, 'U_unity');
            pk   = viz.plots.V01util.penKey(D);
            if strcmp(mode, 'mean')
                % per-neuron mean Laser and Control first, then the pairwise
                % signrank -- matching the report's Mean/neuron column
                a = viz.plots.V01util.aggMean(Lf(ii), neur(ii));
                b = viz.plots.V01util.aggMean(Nf(ii), neur(ii));
                [p, isRed] = viz.plots.V01util.smPaired(a, b, [], 'all');
            else
                [p, isRed] = viz.plots.V01util.smPaired(Lf(ii), Nf(ii), neur(ii), mode, pk(ii));
            end
        end

        % ---- a2{8} dFr histogram -------------------------------------- %
        function drawHist(obj, Xe, Xi)
            ax = obj.axHist; hold(ax,'on');
            % V01 (lines 1415-1420): bars only for these tuning groups; axes/labels always
            % (the NO_ORI_* / ORI_ON_PV groups are population groups like ALL_UNITS/ORI_NON_PV -> bars too)
            if ismember(obj.groupDD.Value, {'ALL_UNITS','NO_ORI_ON_PV','NO_ORI_NO_PV','ORI_ON_PV','ORI_NON_PV','ORI_NON_PV_MD','ORI_NON_PV_NL'})
                if ~isempty(Xe), histogram(ax, Xe, 'BinWidth', 20, 'FaceColor', obj.COL_E, 'FaceAlpha', 0.3); end
                if ~isempty(Xi), histogram(ax, Xi, 'BinWidth', 20, 'FaceColor', obj.COL_I, 'FaceAlpha', 0.3); end
            end
            xlim(ax, [-100 200]); xlabel(ax,'Delta Fr %'); ylabel(ax,'Sample Count'); title(ax,'Sample Distribution'); hold(ax,'off');
        end

        % ---- a2{9}/a2{10} population mean (laser, by dFr group) ------- %
        function drawPopulation(obj, D, X, rep, ax, isE)
            if ~isfield(D,'fit_mid_L') || ~isfield(D,'fit_mid_NL') || isempty(rep), title(ax, 'pop'); return; end
            if isE
                bins = { X < -66, X < -33 & X >= -66, X >= -33 & X < 0 };          % G1-3
                baseCol = obj.COL_E;                                                % PVE laser fill (green)
            else
                bins = { X > 0 & X <= 33, X > 33 & X <= 66, X > 66 & X <= 100, X > 100 };  % G4-7 (FOUR groups)
                baseCol = [0 102 255]/255;                                         % V01 PVI laser fill [0 .4 1]
            end
            win = 91:270; xv = (1:numel(win))'; hold(ax,'on');
            paper = viz.paperStyle();
            greenShades = {[.55 .9 .55],[.2 .75 .2],[0 .45 0]};              % paper L/M/H (light->dark)
            blueShades  = {[.55 .8 1],[.3 .55 1],[.1 .3 .95],[0 .1 .5]};     % paper L/M/H/XH
            % per-dFr-group laser bands. Paper: shades of the manipulation color (green
            % PVA / blue PVI); original: the yellow/orange/red COL2_4 palette. E reversed
            % 4-b, I forward b. Under Mixed-effects each band collapses to per-neuron means.
            for b = 1:numel(bins)
                cols = rep(bins{b}); if isempty(cols), continue; end
                [~, gi, nG] = obj.curveGroups(cols);
                M = obj.aggCols(obj.popWin(D, cols, win, true), gi, nG);
                Y = mean(M,2,'omitnan'); SE = std(M,1,2,'omitnan')/sqrt(size(M,2));
                if paper
                    if isE, lc = greenShades{4-b}; else, lc = blueShades{b}; end
                    shc = lc;
                else
                    if isE, lc = obj.COL2_4{4-b}; else, lc = obj.COL2_4{b}; end
                    shc = baseCol;
                end
                viz.plots.V01util.plotSE(ax, xv, Y, SE, lc, shc, 0.4, 0.25);
            end
            % V01 (lines 1724-1735 / 1801-1812): one pooled gray CONTROL band over the grouped units.
            inAny = false(size(X)); for b = 1:numel(bins), inAny = inAny | bins{b}; end
            poolCols = rep(inAny);
            if ~isempty(poolCols)
                [~, gic, nGc] = obj.curveGroups(poolCols);
                Mc = obj.aggCols(obj.popWin(D, poolCols, win, false), gic, nGc);
                Yc = mean(Mc,2,'omitnan'); SEc = std(Mc,1,2,'omitnan')/sqrt(size(Mc,2));
                viz.plots.V01util.plotSE(ax, xv, Yc, SEc, 'k', [.4 .4 .4], 0.4, 0.5);
            end
            xlim(ax,[0 180]); xticks(ax,[0 90 180]); xticklabels(ax,{'-90','0','90'});
            % V01: only ORI_NON_PV_MD / _NL clamp ylim to [0 1.05]; other groups stay auto
            if ~strcmp(obj.normDD.Value,'Absolute') && ismember(obj.groupDD.Value, {'ORI_NON_PV_MD','ORI_NON_PV_NL'})
                ylim(ax,[0 1.05]);
            end
            title(ax, ternaryS(isE,'PVE All','PVI ALL')); hold(ax,'off');
        end
        function M = popWin(obj, D, cols, win, isLaser)
            % windowed population tuning, normalized WITHIN the displayed window (V01
            % TunU_18, TuningAVG=2): Self peak = each curve / its own window max (so the
            % aligned peak hits 1); Control peak = / control window max; Absolute = raw.
            % This is why peaks reach 1 here, unlike the global-peak fit_mid_self/_nc fields.
            Lw  = D.fit_mid_L(win, cols);
            NLw = D.fit_mid_NL(win, cols);
            if isLaser, M = Lw; else, M = NLw; end
            switch obj.normDD.Value
                case 'Absolute'
                    % raw aligned curve (no normalization)
                case 'Control peak'
                    mx = max(NLw, [], 1); mx(~isfinite(mx) | mx == 0) = NaN; M = M ./ mx;
                otherwise   % 'Self peak' (default; matches V01)
                    mx = max(M, [], 1);   mx(~isfinite(mx) | mx == 0) = NaN; M = M ./ mx;
            end
        end

        % ---- I{i,6} population mean tuning (control gray + laser) ----- %
        function drawPopMeanTwo(obj, ax, D, rep, laserCol)
            pf = 'fit_mid_nc';      % V01 I{i,6} is always control-peak normalized (not tied to the norm dropdown)
            if ~isfield(D,[pf '_NL']) || isempty(rep), return; end
            hold(ax,'on');
            % Under Mixed-effects average each neuron's curves first (aggCols), so the
            % population mean +/- SE below is over NEURONS; identity in other modes.
            [~, gi, nG] = obj.curveGroups(rep);
            Mc = obj.aggCols(D.([pf '_NL'])(:,rep), gi, nG);
            Ml = obj.aggCols(D.([pf '_L'])(:,rep), gi, nG); X = (1:size(Mc,1))';
            viz.plots.V01util.plotSE(ax, X, mean(Mc,2,'omitnan'), std(Mc,0,2,'omitnan')/sqrt(nG), 'k', [.5 .5 .5], 0.4, 0.5);
            if viz.paperStyle(), popLC = laserCol; else, popLC = 'k'; end     % paper: colored laser mean line (green PVA / blue PVI)
            viz.plots.V01util.plotSE(ax, X, mean(Ml,2,'omitnan'), std(Ml,0,2,'omitnan')/sqrt(nG), popLC, laserCol, 0.4, 0.5);
            ax.YLimMode = 'auto'; yl = ylim(ax); d = .05*(yl(2)-yl(1)); ylim(ax,[yl(1)-d yl(2)+d]);   % V01: re-auto before padding
            xlim(ax,[0 360]); xticks(ax,obj.ANGLESS);
            if viz.paperStyle(), xticklabels(ax,{'-180','-90','0','90','180'});    % paper: curves are peak-centered (peak at 180) -> angle from peak
            else,                xticklabels(ax,{'\rightarrow','\uparrow','\leftarrow','\downarrow','\rightarrow'}); end
            hold(ax,'off');
        end

        % ---- I{i,8} population delta (red) + ratio (cyan) dual -------- %
        function drawPopDeltaRatio(obj, ax, D, rep, isE, showLabel)
            if nargin < 6 || isempty(showLabel), showLabel = true; end     % Mean RT/dT labels once (leftmost column)
            if ~isfield(D,'Delta_tun_nc') || isempty(rep), return; end
            % Under Mixed-effects collapse each neuron's curves first (aggCols) so the
            % mean +/- SE is over NEURONS; identity (no-op) in other modes.
            [~, gi, nG] = obj.neurGroups(rep);
            Dl = obj.aggCols(D.Delta_tun_nc(:,rep), gi, nG);
            Rt = obj.aggCols(D.Ratio_tun(:,rep), gi, nG); X = (1:size(Dl,1))';
            grp = obj.groupDD.Value;
            try
                % right axis: delta (red). V01 pad PVE +/-5%*range, PVI +/-20%*range
                yyaxis(ax,'right');
                if viz.paperStyle(), ax.YColor = [1 0 0]; else, ax.YColor = [1 .4 .4]; end
                if viz.paperStyle(), dLC = [1 0 0]; dLW = 0.75; else, dLC = 'k'; dLW = 0.5; end   % paper (PDF-measured): pure-red line 0.75pt, light-red shade
                viz.plots.V01util.plotSE(ax, X, mean(Dl,2,'omitnan'), std(Dl,0,2,'omitnan')/sqrt(nG), dLC, [1 .4 .4], 0.4, dLW);
                ax.YLimMode = 'auto'; yl = ylim(ax); r = yl(2)-yl(1);   % V01: re-auto before padding
                if isE, pad = 0.05*r; else, pad = 0.20*r; end
                ylim(ax,[yl(1)-pad yl(2)+pad]);
                % left axis: ratio (cyan). V01: PVE always pads (+/-0.2, NL +/-0.1);
                % PVI only pads for MD (+/-0.2) / NL (asymmetric [-0.1, 0]); else auto.
                yyaxis(ax,'left'); ax.YColor = [0 1 1];
                if viz.paperStyle(), rLC = [0 1 1]; rLW = 0.75; else, rLC = 'k'; rLW = 0.5; end   % paper (PDF-measured): cyan line 0.75pt
                viz.plots.V01util.plotSE(ax, X, mean(Rt,2,'omitnan'), std(Rt,0,2,'omitnan')/sqrt(nG), rLC, [0 1 1], 0.4, rLW);
                ax.YLimMode = 'auto'; yl = ylim(ax);                    % V01: re-auto before padding
                if isE
                    aY = 0; if strcmp(grp,'ORI_NON_PV_NL'), aY = -0.1; end
                    ylim(ax,[yl(1)-(0.2+aY) yl(2)+(0.2+aY)]);
                else
                    switch grp
                        case 'ORI_NON_PV_MD', ylim(ax,[yl(1)-0.2 yl(2)+0.2]);
                        case 'ORI_NON_PV_NL', ylim(ax,[yl(1)-0.1 yl(2)]);   % asymmetric
                    end
                end
                xlim(ax,[0 360]);
                if viz.paperStyle()                                          % paper Fig 1: peak-centered pop curves -> angle-from-peak numbers (like the pop mean tuning)
                    xticks(ax, obj.ANGLESS); xticklabels(ax, {'-180','-90','0','90','180'}); xtickangle(ax,0);
                else, ax.XTick = []; ax.XTickLabel = []; end
                if viz.paperStyle() && showLabel                             % paper: axis labels Mean RT (cyan) / Mean dT (red), once
                    ylabel(ax, 'Mean RT', 'Color', viz.Colors.Ratio);
                    yyaxis(ax,'right'); ylabel(ax, 'Mean \DeltaT', 'Color', viz.Colors.Delta); yyaxis(ax,'left');
                end
            catch
            end
        end

        % ---- Ax_r{1} linear-threshold fit (sloped only) -------------- %
        function drawIO(obj, D, eRep, iRep)
            ax = obj.axIO; hold(ax,'on');
            if isfield(D,'fit_mid_nc_NL') && isfield(D,'LTM_slope')
                obj.ioUnitLines(ax, D, eRep, true,  obj.COL_E);
                plot(ax, 100*[-1 2], 100*[-1 2], 'k', 'LineWidth', 1);   % V01 z-order: identity after E, before I + red averages
                obj.ioUnitLines(ax, D, iRep, false, obj.COL_I);
                obj.ioAvg(ax, D, eRep, true);
                obj.ioAvg(ax, D, iRep, false);
            else
                plot(ax, 100*[-1 2], 100*[-1 2], 'k', 'LineWidth', 1);
            end
            xlim(ax, 100*[-.2 1.2]); ylim(ax, 100*[-.2 2]);
            xlabel(ax,'Cell response, Control (%)'); ylabel(ax,'Cell response, Laser ON (%)'); title(ax,'Linear Threshold Fit'); hold(ax,'off');
        end
        function ioUnitLines(obj, ax, D, reps, isE, col)
            sl = obj.colv(D,'LTM_slope', obj.nU(D)); ic = obj.colv(D,'LTM_intercept', obj.nU(D)); bpv = obj.colv(D,'LTM_breakpoint', obj.nU(D));
            % Under Mixed-effects draw ONE faint line per neuron: average its control
            % curve + its slope/intercept/breakpoint; one line per obs in other modes.
            [~, gi, nG] = obj.neurGroups(reps);
            Cnl = obj.aggCols(D.fit_mid_nc_NL(:,reps), gi, nG);
            slN = obj.aggVec(sl(reps), gi, nG); icN = obj.aggVec(ic(reps), gi, nG); bpN = obj.aggVec(bpv(reps), gi, nG);
            for j = 1:nG
                x = 100*Cnl(:,j);
                if isE, m = x > bpN(j); else, m = true(size(x)); end
                xs = x(m); if numel(xs) < 2, continue; end
                ys = icN(j) + slN(j)*xs;
                plot(ax, sort(xs), sort(ys), 'Color', [col 0.2], 'LineWidth', 0.1);
            end
        end
        function ioAvg(obj, ax, D, reps, isE)
            if isempty(reps), return; end
            % Under Mixed-effects average each neuron's curves first, so the red
            % population average is over NEURONS; identity in other modes.
            [~, gi, nG] = obj.neurGroups(reps);
            xc = mean(obj.aggCols(100*D.fit_mid_nc_NL(:,reps), gi, nG),2,'omitnan');
            yc = mean(obj.aggCols(100*D.fit_mid_nc_L(:,reps),  gi, nG),2,'omitnan');
            if isE
                f = obj.fitPiecewise(xc, yc);
                if ~isempty(f.upperX), plot(ax, sort(f.upperX), sort(f.upperY), 'Color',[1 0 0 0.5], 'LineWidth', 3); end
            else
                ok = isfinite(xc)&isfinite(yc); if nnz(ok)<2, return; end
                p = polyfit(xc(ok), yc(ok), 1); plot(ax, sort(xc(ok)), sort(polyval(p, xc(ok))), 'Color',[1 0 0 0.5], 'LineWidth', 3);
            end
        end
        function f = fitPiecewise(~, x, y)
            x=x(:); y=y(:); ok=isfinite(x)&isfinite(y); x=x(ok); y=y(ok);
            f.floor=NaN; f.slope=NaN; f.bp=NaN; f.upperX=[]; f.upperY=[];
            if numel(x) < 4, return; end
            pf = @(p,xx) (xx<=p(3)).*p(1) + (xx>p(3)).*(p(1)+p(2)*(xx-p(3)));
            obj0 = @(p) sum((y - pf(p,x)).^2);
            try
                bp = fminsearch(obj0, [mean(y(1:round(end/2))), 1, mean(x)]);
                f.floor=bp(1); f.slope=bp(2); f.bp=bp(3);
                f.upperX = x(x>f.bp); f.upperY = f.floor + f.slope*(f.upperX - f.bp);
            catch
            end
        end

        % ---- Ax_r{2} slope distribution (linear-threshold) ----------- %
        function drawSlope(obj, D, eRep, iRep)
            ax = obj.axSlope; hold(ax,'on');
            if ~isfield(D,'LTM_slope'), title(ax,'Fit Slope distribution'); return; end
            mode = obj.repDD.Value;
            uu = obj.colv(D,'U_unity', obj.nU(D));
            sv = obj.colv(D,'LTM_slope', obj.nU(D));
            % observation-level slopes + neuron/penetration ids (kept aligned
            % through the SAME isfinite filter) -> feed the E-vs-I star below.
            pk = viz.plots.V01util.penKey(D);
            se = sv(eRep); ne = uu(eRep); fe = isfinite(se); se = se(fe); ne = ne(fe); penE = pk(eRep(fe));
            si = sv(iRep); ni = uu(iRep); fi = isfinite(si); si = si(fi); ni = ni(fi); penI = pk(iRep(fi));
            % DISPLAY: under Mixed-effects show one per-neuron mean slope (histogram +
            % median marker) so the picture matches the per-neuron rank-sum; other
            % modes show the observations.
            if obj.aggLme()
                seD = viz.plots.V01util.aggNeuronScalar(se, ne);
                siD = viz.plots.V01util.aggNeuronScalar(si, ni);
            else
                seD = se; siD = si;
            end
            if ~isempty(seD), histogram(ax, seD, 'BinWidth',0.05, 'FaceColor', obj.COL_E, 'FaceAlpha', 0.3); end
            if ~isempty(siD), histogram(ax, siD, 'BinWidth',0.05, 'FaceColor', obj.COL_I, 'FaceAlpha', 0.3); end
            xlim(ax,[0 2]); ylim(ax,[0 50]); ax.YLim(2) = 1.1*ax.YLim(2); yl = ylim(ax);   % V01: YLim(2)*1.1 before markers/text
            if ~isempty(seD), scatter(ax, median(seD), 0.9*yl(2), 4*obj.SZ, obj.COL_E, 'v','filled','MarkerFaceAlpha',0.3); end
            if ~isempty(siD), scatter(ax, median(siD), 0.9*yl(2), 4*obj.SZ, obj.COL_I, 'v','filled','MarkerFaceAlpha',0.3); end
            if ~isempty(se) && ~isempty(si)
                xl = xlim(ax);
                % between-group E-vs-I star: LME on the observations under
                % Mixed-effects (v ~ grp + (1|pen) + (1|pen:neuron), same as the
                % stats report), classic rank-sum otherwise.
                if strcmp(mode, 'lme')
                    [p, isRed] = viz.plots.V01util.smBetweenMM(se, si, ne, ni, penE, penI);
                elseif strcmp(mode, 'mean')     % rank-sum of the shown per-neuron means
                    [p, isRed] = viz.plots.V01util.smBetween(seD, siD, [], [], mode);
                else
                    [p, isRed] = viz.plots.V01util.smBetween(se, si, ne, ni, mode);
                end
                viz.plots.V01util.drawSig(ax, 0.8*xl(2), 0.9*yl(2), p, isRed, 'left');
            end
            xlabel(ax,'Slope'); ylabel(ax,'Count'); title(ax,'Fit Slope distribution'); hold(ax,'off');
        end

        % ---- a2{11} LTM -------------------------------------------- %
        function drawLTM(obj, D, eRep, iRep)
            ax = obj.axLTM; hold(ax,'on');
            if ~isfield(D,'LTM_slope') || ~isfield(D,'LTM_intercept'), title(ax,'LTM Parameters'); return; end
            sl = obj.colv(D,'LTM_slope', obj.nU(D)); ic = obj.colv(D,'LTM_intercept', obj.nU(D)); LGn = obj.layerNum(D);
            % Under Mixed-effects plot one point per NEURON per layer (per-neuron mean
            % intercept / slope); one point per obs in other modes (aggVec no-op).
            for L = 1:3
                ci = iRep(LGn(iRep)==L); ce = eRep(LGn(eRep)==L);
                [~, giI, nGI] = obj.neurGroups(ci); icI = obj.aggVec(ic(ci), giI, nGI); slI = obj.aggVec(sl(ci), giI, nGI);
                [~, giE, nGE] = obj.neurGroups(ce); icE = obj.aggVec(ic(ce), giE, nGE); slE = obj.aggVec(sl(ce), giE, nGE);
                if ~isempty(icI), scatter(ax, icI, slI, 10, 'Marker','o','MarkerEdgeColor','none','MarkerFaceColor',obj.COLORS_NL{L},'MarkerFaceAlpha',0.5); end
                if ~isempty(icE), scatter(ax, icE, slE, 10, 'Marker','^','MarkerEdgeColor','none','MarkerFaceColor',obj.COLORS_NL{L},'MarkerFaceAlpha',0.5); end
            end
            xline(ax,0); yline(ax,1); xlim(ax,[-150 200]); ylim(ax,[0 2]);
            xlabel(ax,'Y intercept (Spikes)'); ylabel(ax,'Line Slope'); title(ax,'LTM Parameters'); hold(ax,'off');
        end

        % ---- per-unit dual sets (left = E/green, right = I/blue) ------- %
        function syncSelection(obj)
            obj.CurrentSet = [obj.ERep(:); obj.IRep(:)];
            if ~ismember(obj.SecondUnit, obj.ERep)        % LEFT example = E
                if ~isempty(obj.ERep), obj.SecondUnit = obj.ERep(1); else, obj.SecondUnit = NaN; end
            end
            if ~ismember(obj.SelectedUnit, obj.IRep)      % RIGHT example = I
                if ~isempty(obj.IRep), obj.SelectedUnit = obj.IRep(1); else, obj.SelectedUnit = NaN; end
            end
            obj.onCondSwitch();                           % sync slider range/value to the active condition
        end
        function drawPerUnit(obj, D)
            obj.drawUnitSet(D, 1, obj.SecondUnit,   obj.COL_E);   % LEFT  (E, green)
            obj.drawUnitSet(D, 2, obj.SelectedUnit, obj.COL_I);   % RIGHT (I, blue)
        end
        function updateUnitLabel(obj)
            obj.unitLabel.Text = sprintf('unit: E #%d  /  I #%d', obj.SecondUnit, obj.SelectedUnit);
        end
        % redraw ONLY the 6 per-unit panels of one slot (slider/click; not population)
        function redrawUnit(obj, slot)
            D = obj.LastD;
            if isempty(D) || isempty(obj.PlotFig) || ~isvalid(obj.PlotFig), return; end
            for h = [obj.uRasL(slot) obj.uRasNL(slot) obj.uTun(slot) obj.uIO(slot)]
                if isvalid(h{1}), cla(h{1}); end
            end
            try, cla(obj.uPolar{slot}); catch, end %#ok<CTCH>
            obj.clearYY(obj.uDratio{slot});
            if slot == 1, u = obj.SecondUnit; Cc = obj.COL_E; else, u = obj.SelectedUnit; Cc = obj.COL_I; end
            if isfinite(u), obj.drawUnitSet(D, slot, u, Cc); end
            obj.matchPlotWidths();
            obj.updateUnitLabel();
        end
        % equalize the DATA-area width of the tuning/delta-ratio panels (V01 TightInset
        % trick): I{i,3}==I{i,7} and I{i,6}==I{i,8} share a common inner width so the
        % stacked curves line up on x for comparison.
        function matchPlotWidths(obj)
            if isempty(obj.PlotFig) || ~isvalid(obj.PlotFig), return; end
            W = obj.PlotFig.Position(3); inner = 0.08 * W;
            % per-unit tuning / delta-ratio: equalize the DATA area via TightInset.
            grp = [obj.uTun, obj.uDratio];
            for k = 1:numel(grp)
                ax = grp{k}; if isempty(ax) || ~isvalid(ax), continue; end
                try
                    ti = ax.TightInset; p = ax.Position;
                    ax.Position = [p(1), p(2), inner + ti(1) + ti(3), p(4)];
                catch
                end
            end
            % population panels (Fig 1D): force EQUAL plot boxes via InnerPosition (the
            % delta/ratio yyaxis makes TightInset under-count, so its box came out
            % narrower). uPop6{i}/uPop8{i} share one plot-box x per column so the mean-
            % tuning and delta/ratio line up; in paper mode nudge the PVE (i=2) column
            % LEFT so the two delta/ratio panels' yyaxis labels don't overlap.
            popW = 0.07 * W;
            for i = 1:2
                a6 = obj.uPop6{i}; a8 = obj.uPop8{i};
                if isempty(a6) || ~isvalid(a6), continue; end
                ip6 = a6.InnerPosition; x = ip6(1);
                if viz.paperStyle() && i == 2, x = x - 0.033 * W; end
                try, a6.InnerPosition = [x, ip6(2), popW, ip6(4)]; catch, end %#ok<CTCH>
                if ~isempty(a8) && isvalid(a8)
                    ip8 = a8.InnerPosition;
                    try, a8.InnerPosition = [x, ip8(2), popW, ip8(4)]; catch, end %#ok<CTCH>
                end
            end
        end
        function drawUnitSet(obj, D, i, u, Cc)
            if ~isfinite(u), return; end
            oriN = 24; if isfield(D,'Ori_N'), v=double(D.Ori_N(u)); if isfinite(v)&&v>=2, oriN=round(v); end, end
            timing = [-0.5 1 2];                          % fallback = old default raster timing
            if isfield(D,'Rast_time'), tt = D.Rast_time(u,:); if numel(tt)>=3 && all(isfinite(tt)), timing = tt; end, end
            obj.drawRasterInto(obj.uRasL{i},  rasOf(D,'RasL',u),  oriN, true,  timing, Cc);   % laser
            obj.drawRasterInto(obj.uRasNL{i}, rasOf(D,'RasNL',u), oriN, false, timing, Cc);   % no laser
            obj.drawTunInto(obj.uTun{i}, D, u, Cc, i==1);   % legend once, on the leftmost (E) column
            obj.drawPolarInto(obj.uPolar{i}, D, u, Cc);
            obj.drawIOInto(obj.uIO{i}, D, u);
            obj.drawDratioInto(obj.uDratio{i}, D, u, i==1);   % RT/dT labels once, leftmost column
        end
        % I{i,1}/I{i,2} rasters: spikes + stim-onset line, laser bars, cyan ori ticks,
        % seconds x-axis, direction-arrow y-ticks (V01 Plot_Tuning8_01:124-211). Stim
        % onset/offset (tsS/tsE) come from the unit's Rast_time, not a fixed .5/1.5.
        function drawRasterInto(~, ax, R, oriN, isLaser, timing, Cc)
            if isempty(R), return; end
            if nargin < 6 || isempty(timing) || numel(timing) < 2 || ~all(isfinite(timing(1:2)))
                tsS = 0.5; tsE = 1.5;                          % fallback: old default timing
            else
                tsS = -timing(1);                             % stim onset (s) = pre-stim baseline
                tsE = -timing(1) + timing(2);                 % stim offset (s)
            end
            if nargin < 7 || isempty(Cc), Cc = viz.Colors.PVI; end   % laser photostim-bar color (green PVA / blue PVI)
            R = double(R); nT = size(R,1); W = size(R,2);
            [s, t] = find(R == 1);
            scatter(ax, t, s, 0.4, 'k', 'filled'); hold(ax,'on');
            if viz.paperStyle()
                % PAPER (Fig 1 B/C): SOLID red lines at stimulus onset AND offset in both
                % rows; the laser row carries a green (PVA) / blue (PVI) photostim bar
                % across the top spanning onset->offset.
                xline(ax, 1+1000*tsS, 'Color', viz.Colors.StimLine, 'LineWidth', 0.5);    % stim onset (paper: pure-red 0.5pt)
                xline(ax, 1+1000*tsE, 'Color', viz.Colors.StimLine, 'LineWidth', 0.5);    % stim offset
                if isLaser
                    plot(ax, 1000*[tsS tsE], [2+nT 2+nT], 'Color', Cc, 'LineWidth', 1);   % photostim bar (paper: 1.0pt)
                    topY = nT + 3;
                else
                    topY = nT + 1;
                end
            else
                % ORIGINAL (pre-paper port): dashed red onset line + tan visual-stim bar
                % (both rows) + a dark-red laser bar at the top.
                xline(ax, 1+1000*tsS, '--r', 'LineWidth', 0.5);                           % stim onset
                plot(ax, 1000*[tsS tsE], [1+nT 1+nT], 'Color',[215 185 121]/255, 'LineWidth',0.5);
                if isLaser
                    plot(ax, 1000*[tsS tsE], [3+nT 3+nT], 'Color',[139 36 51]/255, 'LineWidth',0.5);
                    topY = nT + 3;
                else
                    topY = nT + 1;
                end
            end
            OrRip = nT / max(oriN,1);
            for i = 1:oriN, scatter(ax, 1, i*OrRip, 1, '_', 'MarkerEdgeColor', viz.Colors.OriTick); end   % orientation-block ticks
            xlim(ax, [0 W-500]); ylim(ax, [0 topY]);
            xt = 0:500:max(W-500,0); ax.XTick = xt; ax.XTickLabel = xt/1000 - tsS;          % seconds
            arrowPos = [1 : nT/4 : nT, nT];
            ax.YTick = arrowPos; ax.YTickLabel = {'\rightarrow','\uparrow','\leftarrow','\downarrow','\rightarrow'};
            ytickangle(ax, 0); xtickangle(ax, 0); hold(ax,'off');
        end
        % I{i,3}: per-orientation measured means +/- SE (S markers), laser fit peak-centered
        % (Circ_center2), control fit raw, red spontaneous-mean line (V01 err_type==2 branch).
        function drawTunInto(obj, ax, D, u, Cc, showLegend)
            if nargin < 6 || isempty(showLegend), showLegend = true; end   % legend once (leftmost column)
            hold(ax,'on'); fnl = D.fit_NL(:,u); fl = D.fit_L(:,u); N = numel(fnl);
            s = obj.unitRates(D, u); oriN = s.oriN; if ~isfinite(oriN), oriN = 24; end
            Xv = (1:oriN)'; Xfit = 1 + (0:N-1)'*(oriN/N);
            [~, idL] = obj.circCenter(fnl, fl); flc = circshift(fl, round(.5*N - idL));   % center laser fit
            lw = 0.5; if viz.paperStyle(), lw = 0.75; end                                 % paper: tuning fit curves 0.75pt
            if ~isempty(s.RasL_m)
                e1 = errorbar(ax, Xv, s.RasL_m(:), s.RasL_se(:), 'S', 'MarkerSize',1, 'Color',Cc,       'LineWidth',0.5); cap = e1.CapSize; e1.CapSize = cap/2;
                plot(ax, Xfit, flc, 'Color', Cc, 'LineWidth',lw);
                e2 = errorbar(ax, Xv, s.RasNL_m(:), s.RasNL_se(:), 'S', 'MarkerSize',1, 'Color',[0 0 0], 'LineWidth',0.5); e2.CapSize = cap/2;
                plot(ax, Xfit, fnl, 'Color', [0 0 0], 'LineWidth',lw);
                if isfinite(s.baseMean)
                    if viz.paperStyle(), yline(ax, s.baseMean, '--', 'Color', [.294 .294 .294], 'Alpha',1, 'LineWidth',0.7);  % paper: dark-gray #4B4B4B dashed 0.7pt
                    else,                yline(ax, s.baseMean, '--', 'Color',[1 0 0], 'Alpha',0.5, 'LineWidth',0.2); end        % original: red
                end
            else
                plot(ax, Xfit, flc, 'Color', Cc, 'LineWidth',lw); plot(ax, Xfit, fnl, 'Color', [0 0 0], 'LineWidth',lw);
            end
            xlim(ax, [1 oriN]); ylim(ax, 'auto');                                          % auto-scale y
            arrowPos = [1 : oriN/4 : oriN, oriN];
            xticks(ax, arrowPos); xticklabels(ax, {'\rightarrow','\uparrow','\leftarrow','\downarrow','\rightarrow'}); xtickangle(ax,0);
            if viz.paperStyle() && showLegend                              % paper: control / PVA / PVI legend across the top (once, leftmost column)
                fs = ax.FontSize;
                text(ax, 0.00, 1.06, 'control', 'Units','normalized', 'Color',[0 0 0],       'FontSize',fs, 'VerticalAlignment','bottom', 'Clipping','off');
                text(ax, 0.44, 1.06, 'PVA',     'Units','normalized', 'Color',viz.Colors.PVA, 'FontSize',fs, 'VerticalAlignment','bottom', 'Clipping','off');
                text(ax, 0.72, 1.06, 'PVI',     'Units','normalized', 'Color',viz.Colors.PVI, 'FontSize',fs, 'VerticalAlignment','bottom', 'Clipping','off');
            end
            hold(ax,'off');
        end
        % I{i,4}: measured per-direction polar (NOr points) with 50-segment SE shading,
        % red spontaneous-mean ring, square vertices (V01 Plot_Tuning8_01:449-503).
        function drawPolarInto(obj, ax, D, u, Cc)
            try
                s = obj.unitRates(D, u); if isempty(s.RasL_m), return; end
                oriN = s.oriN; theta = linspace(0, 2*pi, oriN+1);
                OL = s.RasL_m(:); ONL = s.RasNL_m(:);
                hold(ax,'on');
                if isfinite(s.baseMean), polarplot(ax, theta, s.baseMean*ones(1,numel(theta)), 'Color',[1 0 0 0.5]); end
                polarplot(ax, theta, [OL; OL(1)], 'Marker','square', 'MarkerSize',1, 'Color',[Cc 0.5]);
                obj.polarBand(ax, OL - s.RasL_se(:), OL + s.RasL_se(:), Cc);
                polarplot(ax, theta, [ONL; ONL(1)], 'Marker','square', 'MarkerSize',1, 'Color',[0 0 0 0.5]);
                obj.polarBand(ax, ONL - s.RasNL_se(:), ONL + s.RasNL_se(:), [0 0 0]);
                ax.ThetaTick = [0 90 180 270]; ax.ThetaTickLabel = {'0','90','180','270'}; hold(ax,'off');
            catch
            end
        end
        % I{i,5}: control-vs-laser I/O scatter (subsample THEN sort), live piecewise (E) /
        % linear (I) fit on the 36-pt subsample, exp-model overlay swapped per E/I (V01:551-666).
        function drawIOInto(obj, ax, D, u)
            hold(ax,'on');
            if ~isfield(D,'fit_mid_nc_NL'), return; end
            x = 100*D.fit_mid_nc_NL(:,u); y = 100*D.fit_mid_nc_L(:,u);                       % control / laser (ctrl-peak %)
            x360 = sort(x); y360 = sort(y);
            xs = sort(x(1:10:end)); ys = sort(y(1:10:end));                                  % subsample THEN sort (36 pts)
            if viz.paperStyle(), ioDot = [0 0 0]; else, ioDot = [.3 .3 .3]; end   % paper: black open circles
            scatter(ax, xs, ys, obj.SZ/2, ioDot, 'o');
            isE = ~obj.isInhibUnit(D, u);
            thrLW = 1; thrA = 0.4; modA = 0.4;                                              % threshold-linear + I/O-model line style
            if viz.paperStyle(), thrLW = 1.4; thrA = 1; modA = 1; end                       % paper: 1.4pt SOLID fit, solid red model
            if isE
                f = obj.fitPiecewise36(xs, ys);                                              % live fminsearch on 36 pts
                if ~isempty(f)
                    x1 = xs(xs<=f.bp); x2 = xs(xs>f.bp);
                    if ~isempty(x1), plot(ax, sort(x1), f.floor*ones(size(x1)), 'Color',[0 1 0 thrA], 'LineWidth',thrLW); end
                    if ~isempty(x2), plot(ax, sort(x2), sort(f.floor + f.slope*(x2 - f.bp)), 'Color',[0 1 0 thrA], 'LineWidth',thrLW); end
                end
                if isfield(D,'ExpM_fit'), plot(ax, x360, 100*sort(D.ExpM_fit(:,u)), 'Color',[1 0 0 modA], 'LineWidth',0.5); end
                ylim(ax, 100*[-.2 1.2]);
            else
                p = polyfit(xs, ys, 1);
                plot(ax, sort(xs), sort(polyval(p, xs)), 'Color',[0 0 1 thrA], 'LineWidth',thrLW);
                if isfield(D,'ExpM_fit'), plot(ax, 100*sort(D.ExpM_fit(:,u)), y360, 'Color',[1 0 0 modA], 'LineWidth',0.6); end  % axes swapped for I
                ylim(ax, 100*[-.2 2.6]);
            end
            if viz.paperStyle(), plot(ax, 100*[-1 2], 100*[-1 2], '--', 'Color',[0 0 0], 'LineWidth',0.75);   % paper: dashed unity
            else,                plot(ax, 100*[-1 2], 100*[-1 2], 'k', 'LineWidth',1); end
            xlim(ax, 100*[-.2 1.2]); hold(ax,'off');
        end
        % I{i,7}: right=delta (centered laser fit - raw control fit), left=ratio; E/I sign
        % flip; both axes XTick/XTickLabel cleared; right axis +/-5% pad (V01:323-412).
        function drawDratioInto(obj, ax, D, u, showLabel)
            if nargin < 5 || isempty(showLabel), showLabel = true; end     % RT/dT labels once (leftmost column)
            fnl = D.fit_NL(:,u); fl = D.fit_L(:,u); N = numel(fnl);
            [~, idL] = obj.circCenter(fnl, fl); flc = circshift(fl, round(.5*N - idL));
            x = (1:N)';
            if obj.isInhibUnit(D, u), delta = -(flc - fnl); ratio = fnl ./ flc;
            else,                     delta =  (flc - fnl); ratio = flc ./ fnl; end
            try
                dCol = [1 .1 .1]; rCol = [0 1 1]; lw = 0.5;
                if viz.paperStyle(), dCol = [1 0 0]; lw = 0.75; end                             % paper: pure-red dT, cyan RT, 0.75pt
                yyaxis(ax,'right'); ax.YColor = dCol; line(ax, x, delta, 'Color',dCol, 'LineWidth',lw);
                ylim(ax,'auto'); xlim(ax,[x(1) x(end)]); ax.XTick = []; ax.XTickLabel = [];   % delta auto-scales
                yyaxis(ax,'left'); ax.YColor = rCol; line(ax, x, ratio, 'Color',rCol, 'LineWidth',lw);
                ylim(ax,[0 1]); xlim(ax,[x(1) x(end)]); ax.XTick = []; ax.XTickLabel = [];     % ratio fixed [0 1]
                if viz.paperStyle() && showLabel                             % paper: axis labels RT (cyan) / dT (red), once
                    ylabel(ax, 'RT', 'Color', viz.Colors.Ratio);
                    yyaxis(ax,'right'); ylabel(ax, '\DeltaT', 'Color', viz.Colors.Delta); yyaxis(ax,'left');
                end
                if viz.paperStyle()                                          % paper Fig 1: drift-direction arrows on x (match the tuning above)
                    apos = [1, round(N/4), round(N/2), round(3*N/4), N];
                    xticks(ax, apos); xticklabels(ax, {'\rightarrow','\uparrow','\leftarrow','\downarrow','\rightarrow'}); xtickangle(ax,0);
                end
            catch
                cla(ax); plot(ax, x, delta, 'Color',[1 .1 .1]); hold(ax,'on'); plot(ax, x, ratio, 'Color',[0 1 1]); xlim(ax,[x(1) x(end)]); ax.XTick = []; hold(ax,'off');
            end
        end
        % per-unit raster helpers: measured per-orientation tuning + baseline. Base/stim
        % windows come from the unit's Rast_time via analysis.windows (matches computeMetrics);
        % for the old [-0.5 1 2] timing this is exactly the old fixed 1:500 / 501:1500.
        function s = unitRates(obj, D, u)
            s = struct('oriN',NaN,'RasL_m',[],'RasNL_m',[],'RasL_se',[],'RasNL_se',[],'baseMean',NaN);
            RL = rasOf(D,'RasL',u); RNL = rasOf(D,'RasNL',u);
            if isempty(RL) || isempty(RNL), return; end
            RL = double(RL); RNL = double(RNL);
            oriN = 24; if isfield(D,'Ori_N'), v=double(D.Ori_N(u)); if isfinite(v)&&v>=2, oriN=round(v); end, end
            s.oriN = oriN; W = min(size(RL,2), size(RNL,2));
            timing = [-0.5 1 2];                              % fallback = old default raster timing
            if isfield(D,'Rast_time'), tt = D.Rast_time(u,:); if numel(tt)>=3 && all(isfinite(tt)), timing = tt; end, end
            [bW, sW] = analysis.windows(timing, 0);          % timing-aware base/stim sample windows
            sIdx = max(1,sW(1)):min(sW(2),W); bIdx = max(1,bW(1)):min(bW(2),W);
            [s.RasL_m,  s.RasL_se]  = obj.oriMeanSE(RL,  oriN, sIdx);
            [s.RasNL_m, s.RasNL_se] = obj.oriMeanSE(RNL, oriN, sIdx);
            s.baseMean = mean([1000*mean(mean(RL(:,bIdx))), 1000*mean(mean(RNL(:,bIdx)))]);
        end
        function [m, se] = oriMeanSE(~, R, oriN, sIdx)
            m = nan(1,oriN); se = nan(1,oriN); ntr = floor(size(R,1)/oriN);
            if ntr < 1, return; end
            for i = 1:oriN
                blk = R((1+(i-1)*ntr):(i*ntr), sIdx);
                m(i) = 1000*mean(blk(:)); se(i) = std(1000*mean(blk,2));
            end
            se = se / sqrt(oriN);                        % V01 quirk: RasL_se = std_RL / sqrt(NOr)
        end
        function [idC, idL] = circCenter(~, TC, TL)
            % port of Circ_center2: idC = control peak; idL = laser peak within the central
            % [3/8,5/8] window after shifting laser by the control peak.
            TC = TC(:); TL = TL(:); N = numel(TC);
            mc = find(TC == max(TC)); idC = mc(1);
            tmp = circshift(TL, round(.5*N - idC));
            w = round((3/8)*N):round((5/8)*N);
            ml = find(tmp == max(tmp(w))); idL = ml(1);
        end
        function polarBand(~, ax, lo, hi, col)
            % 50 interpolated rings between lo and hi at alpha 0.01 (closed)
            lo = lo(:); hi = hi(:); ns = 50; th = linspace(0, 2*pi, numel(lo)+1);
            for k = 1:ns
                ri = lo + (hi - lo)*(k/ns); polarplot(ax, th, [ri; ri(1)], 'LineWidth',1, 'Color',[col 0.01]);
            end
        end
        function f = fitPiecewise36(~, x, y)
            f = []; x=x(:); y=y(:); ok=isfinite(x)&isfinite(y); x=x(ok); y=y(ok);
            if numel(x) < 4, return; end
            pw = @(p,xx) (xx<=p(3)).*p(1) + (xx>p(3)).*(p(1)+p(2)*(xx-p(3)));
            try
                bp = fminsearch(@(p) sum((y - pw(p,x)).^2), [mean(y(1:round(end/2))), 1, mean(x)]);
                f.floor=bp(1); f.slope=bp(2); f.bp=bp(3);
            catch
                f = [];
            end
        end

        function onScatterClick(obj, ax, e, X, Y, reps)
            if isempty(reps), return; end
            try, pt = e.IntersectionPoint(1:2); catch, return; end
            dx = X - pt(1); dy = 100*(Y - pt(2));        % V01 PlotRast08: raw Euclidean, y weighted x100
            [~, k] = min(dx.^2 + dy.^2); u = reps(k);
            if obj.isInhibUnit(obj.LastD, u)              % I -> RIGHT slot; E -> LEFT slot
                obj.SelectedUnit = u; obj.condSwitch.Value = 'I'; slot = 2;
            else
                obj.SecondUnit   = u; obj.condSwitch.Value = 'E'; slot = 1;
            end
            obj.onCondSwitch(); obj.redrawUnit(slot);     % only redraw that example
            % ring the just-clicked point (this scatter axes is NOT redrawn here)
            viz.plots.V01util.highlightUnits(ax, X, Y, reps, [obj.SecondUnit obj.SelectedUnit]);
            obj.inspectPick(u);                           % open/update the unit-inspector popup
            obj.trackPick(u);                             % ring it across every plot if tracking
        end
        function onCondSwitch(obj)
            % point the slider at the active condition's rep list + current selection
            if strcmp(obj.condSwitch.Value, 'I'), lst = obj.IRep; cur = obj.SelectedUnit;
            else,                                  lst = obj.ERep; cur = obj.SecondUnit; end
            n = numel(lst); obj.unitSlider.Limits = [1 max(2,n)];
            k = find(lst == cur, 1); if isempty(k), k = 1; end
            obj.unitSlider.Value = min(max(k,1), max(2,n));
        end
        function onUnitSlider(obj)
            % moves only the example selected by the switch; redraws ONLY its 6 panels
            if strcmp(obj.condSwitch.Value, 'I'), lst = obj.IRep; slot = 2; else, lst = obj.ERep; slot = 1; end
            if isempty(lst), return; end
            k = min(max(round(obj.unitSlider.Value),1), numel(lst));
            if slot == 1, obj.SecondUnit = lst(k); else, obj.SelectedUnit = lst(k); end
            obj.redrawUnit(slot);
        end
        function stepUnit(obj, d)
            % +/- buttons: nudge the slider by d and redraw only the selected example
            lim = obj.unitSlider.Limits;
            obj.unitSlider.Value = min(max(obj.unitSlider.Value + d, lim(1)), lim(2));
            obj.onUnitSlider();
        end

        function v = layerNum(obj, D)
            N = obj.nU(D); v = nan(N,1);
            if ~isfield(D,'LG'), return; end
            map = {'SG',1,'G',2,'IG',3,'Deep',4};
            for k = 1:N, s = char(strtrim(string(D.LG(k)))); idx = find(strcmpi(map(1:2:end), s),1); if ~isempty(idx), v(k) = map{2*idx}; end, end
        end
    end
end

% ----------------------------------------------------------------------- %
function R = rasOf(D, field, u)
    R = [];
    if isfield(D, field) && numel(D.(field)) >= u, R = D.(field){u}; end
end
function s = ternaryS(cond, a, b)
    if cond, s = a; else, s = b; end
end
