classdef LaminarTab < viz.PlotTab
%LAMINARTAB  Laminar scatter viewer: a selectable parameter vs recording channel.
%
%   In-tab multi-panel viewer (laid out like viz.plots.TuningTab) that ports the
%   look of DG_L_laminarScatter_viewer_02: each panel is a scatter of one
%   per-unit PARAMETER (x) against CHANNEL/depth (y), the points colored by a
%   selectable feature (default the recording layer group LG), with the layer
%   borders drawn as horizontal lines and an optional median-per-channel line.
%
%   EACH PANEL is configured INDEPENDENTLY:
%       * Parameter : any per-unit scalar metric (Delta_Fr, fitOSI_*, ...).
%       * Animal / Penetration / Tasks : the selection drawn in that panel.
%   The toolbar Filters + the TuningG unit-group dropdown apply on top.
%
%   PANELS (like viz.plots.TuningTab).  The left controls edit the ACTIVE panel
%   live. "Add" clones it, "Remove" drops it, "Active panel" picks the target.
%   "Plot -> active panel" pins the current selection: with "Hold" OFF it just
%   shows the live selection; with "Hold" ON it OVERLAYS the current selection as
%   an extra layer (drawn with a different marker) so you can compare e.g. two
%   penetrations in one panel. "Clear" drops the overlaid layers. "Freeze" pins a
%   panel to the filter it currently shows so later filter changes leave it alone.
%
%   PICK.  Click near a point to ring it and show its unit number (like the
%   Visualizer-01 dashboard). The pick survives redraws and tab switches.
%
%   Switching tabs does NOT reset the axes (zoom / limits are kept): a panel is
%   only redrawn when its data, filter or controls actually change.
%
%   See also: viz.PlotTab, viz.plots.TuningTab, viz.plots.V01util,
%             analysis.computeMetrics, DG_L_laminarScatter_viewer_02

    properties
        % controls (edit the active panel)
        ParamDD; AnimalDD; PenDD; TaskLB
        GroupDD; ColorByDD             % global: TuningG unit-group + color-by feature
        MedianChk; FlipYChk; HoldChk   % global display options + overlay-hold
        YLimField; XLimField; SmoothField  % global: y-/x-limit [min max] text + median-smoothing span
        PanelDD; FreezeBtn; statusLbl

        % parameter registry (numeric per-unit scalars)
        ParamKeys = {}

        % plot panels
        PanelGrid
        % cfg: param/animal/pen/tasks ; overlays: extra cfgs ; frozen/mask: pinned
        % filter ; px/py/pidx: plotted points for click-picking
        Panels = struct('ax',{},'cfg',{},'overlays',{},'frozen',{},'mask',{},'px',{},'py',{},'pidx',{},'titleExtra',{})
        ActivePanel = 0
        SelectedUnit = NaN             % last clicked unit (ringed across redraws)
        Counts = []                    % viz.plots.UnitCountsWindow (lazy)
        LastD = []; LastMask = []
        LastKey = ''                   % draw-state signature (skip redraw if unchanged)
    end

    properties (Constant)
        MaxPanels    = 8
        LAYER_NAMES  = {'SG','G','IG','Deep'}
        LAYER_COLORS = [0 0.45 0.74; 0.85 0.33 0.10; 0.47 0.67 0.19; 0.49 0.18 0.56];
        UNASSIGNED   = [0.6 0.6 0.6]
        MARKER_SZ    = 26
        OV_MARKERS   = {'s','^','d','v','p','h'}     % overlay-layer marker shapes
        GROUPS   = {'ALL_UNITS','NO_ORI_ON_PV','NO_ORI_NO_PV','ORI_ON_PV','ORI_NON_PV','ORI_NON_PV_MD','ORI_NON_PV_NL','ORI_NON_PV_U','OUTLIER'};
        COLOR_BY = {'Layer','G_type','E/I','Animal','Penetration','Task'};
    end

    methods
        function obj = LaminarTab()
            obj@viz.PlotTab('Laminar viewer');
        end

        % ================================================================= %
        function buildControls(obj, parent)
            obj.buildParamRegistry();

            g = uigridlayout(parent, [25 1]);
            g.RowHeight = {18,26, 18,26, 18,26, 18,26, 18,26, 18,110, 26, 28, 18,26, 18,26, 18,26, 18,26, 28, 28, '1x'};
            g.RowSpacing = 4; g.Padding = [8 8 8 8];

            lab(g, 1, 'Unit group (TuningG)');
            obj.GroupDD = uidropdown(g, 'Items', obj.GROUPS, 'Value', 'ALL_UNITS', ...
                'Tooltip', 'Restrict to a Visualizer-01 TuningG unit group (intersected with the toolbar filters).', ...
                'ValueChangedFcn', @(s,e) obj.requestRefresh());
            obj.GroupDD.Layout.Row = 2;

            lab(g, 3, 'Parameter (x-axis)');
            if isempty(obj.ParamKeys)
                obj.ParamDD = uidropdown(g, 'Items', {'(no metrics)'}, 'Enable','off');
            else
                obj.ParamDD = uidropdown(g, 'Items', obj.ParamKeys, ...
                    'Value', obj.defaultParam(), 'ValueChangedFcn', @(s,e) obj.applyToActive());
            end
            obj.ParamDD.Layout.Row = 4;

            lab(g, 5, 'Color by');
            obj.ColorByDD = uidropdown(g, 'Items', obj.COLOR_BY, 'Value', 'Layer', ...
                'Tooltip', 'Feature used to color the points (Layer = LG, the default). Borders/counts stay LG-based.', ...
                'ValueChangedFcn', @(s,e) obj.requestRefresh());
            obj.ColorByDD.Layout.Row = 6;

            lab(g, 7, 'Animal');
            items = obj.animalItems();
            obj.AnimalDD = uidropdown(g, 'Items', items, 'Value', items{1}, ...
                'ValueChangedFcn', @(s,e) obj.onAnimal());
            obj.AnimalDD.Layout.Row = 8;

            lab(g, 9, 'Penetration');
            pitems = obj.penItems(items{1});
            obj.PenDD = uidropdown(g, 'Items', pitems, 'Value', pitems{1}, ...
                'ValueChangedFcn', @(s,e) obj.onPen());
            obj.PenDD.Layout.Row = 10;

            lab(g, 11, 'Tasks (combine; (all) = every task)');
            obj.TaskLB = uilistbox(g, 'Items', obj.taskItems(items{1}, str2double(pitems{1})), ...
                'Multiselect', 'on', 'Value', '(all tasks)', ...
                'Tooltip', 'Select one or more task numbers to combine into this panel; (all tasks) uses every task of this penetration.', ...
                'ValueChangedFcn', @(s,e) obj.applyToActive());
            obj.TaskLB.Layout.Row = 12;

            og = uigridlayout(g, [1 3], 'Padding',[0 0 0 0], 'ColumnSpacing',6);
            og.Layout.Row = 13;
            obj.MedianChk = uicheckbox(og, 'Text','Median/ch', 'Value', true, ...
                'Tooltip','Overlay the median parameter value per channel', ...
                'ValueChangedFcn', @(s,e) obj.requestRefresh());
            obj.FlipYChk = uicheckbox(og, 'Text','Flip', 'Value', false, ...
                'Tooltip','Flip the channel (depth) axis', ...
                'ValueChangedFcn', @(s,e) obj.requestRefresh());
            obj.HoldChk = uicheckbox(og, 'Text','Hold', 'Value', false, ...
                'Tooltip','When on, "Plot -> active panel" OVERLAYS the current selection as an extra layer (different marker).');

            pg = uigridlayout(g, [1 2], 'Padding',[0 0 0 0], 'ColumnSpacing',4);
            pg.Layout.Row = 14; pg.ColumnWidth = {'1x', 70};
            uibutton(pg, 'Text','Plot → active panel', 'FontWeight','bold', ...
                'ButtonPushedFcn', @(s,e) obj.plotToActive());
            uibutton(pg, 'Text','Clear', 'ButtonPushedFcn', @(s,e) obj.clearActivePanel());

            lab(g, 15, 'X limit  [min max]  (blank = auto)');
            obj.XLimField = uieditfield(g, 'text', 'Value', '', 'Placeholder', 'e.g. -1 2', ...
                'Tooltip', 'Parameter (x) axis limits applied to EVERY plot; leave blank for auto.', ...
                'ValueChangedFcn', @(s,e) obj.requestRefresh());
            obj.XLimField.Layout.Row = 16;

            lab(g, 17, 'Y limit  [min max]  (blank = auto)');
            obj.YLimField = uieditfield(g, 'text', 'Value', '', 'Placeholder', 'e.g. 1 384', ...
                'Tooltip', 'Channel (y) axis limits applied to EVERY plot; leave blank for auto.', ...
                'ValueChangedFcn', @(s,e) obj.requestRefresh());
            obj.YLimField.Layout.Row = 18;

            lab(g, 19, 'Median smooth (span; 0 = off)');
            obj.SmoothField = uieditfield(g, 'numeric', 'Value', 0, 'Limits', [0 999], ...
                'RoundFractionalValues', 'on', ...
                'Tooltip', 'movmedian window (in channels) for the black median line; 0/1 = raw median.', ...
                'ValueChangedFcn', @(s,e) obj.requestRefresh());
            obj.SmoothField.Layout.Row = 20;

            lab(g, 21, 'Active panel');
            obj.PanelDD = uidropdown(g, 'Items', {'1'}, 'Value', '1', ...
                'ValueChangedFcn', @(s,e) obj.onPanelDD());
            obj.PanelDD.Layout.Row = 22;

            ag = uigridlayout(g, [1 3], 'Padding',[0 0 0 0], 'ColumnSpacing',4);
            ag.Layout.Row = 23;
            uibutton(ag, 'Text','Add',    'ButtonPushedFcn', @(s,e) obj.addPanel());
            obj.FreezeBtn = uibutton(ag, 'Text','Freeze', 'ButtonPushedFcn', @(s,e) obj.freezeActivePanel());
            uibutton(ag, 'Text','Remove', 'ButtonPushedFcn', @(s,e) obj.removeActivePanel());

            cb = uibutton(g, 'Text', sprintf('\x2630 Unit counts'), 'ButtonPushedFcn', @(s,e) obj.openCounts(), ...
                'Tooltip','Open a pop-up tabulating the unit counts per panel (obs + unique) by any category combination.');
            cb.Layout.Row = 24;

            obj.statusLbl = uilabel(g, 'Text','', 'WordWrap','on', 'VerticalAlignment','top');
            obj.statusLbl.Layout.Row = 25;

            obj.addInspectCheckbox(g);
        end

        function buildView(obj, parent)
            obj.PanelGrid = uigridlayout(parent, [1 1]);
            obj.PanelGrid.Padding = [4 4 4 4];
            obj.PanelGrid.RowSpacing = 6; obj.PanelGrid.ColumnSpacing = 6;
            obj.Panels = struct('ax',{},'cfg',{},'overlays',{},'frozen',{},'mask',{},'px',{},'py',{},'pidx',{},'titleExtra',{});
            obj.createPanel(obj.readCfg());     % first panel from the default controls
            obj.ActivePanel = 1;
            obj.relayoutPanels();
            obj.refreshPanelDD();
            obj.syncFreezeBtn();
        end

        % ================================================================= %
        function update(obj, D, mask)
            obj.LastD = D; obj.LastMask = logical(mask(:));
            drawMask = obj.LastMask & obj.groupMaskFor(D);   % intersect the TuningG unit group
            key = obj.drawKey(drawMask);
            firstDraw = isempty(obj.LastKey);
            if strcmp(key, obj.LastKey) && ~firstDraw
                return;   % nothing changed (e.g. a tab switch) -> keep the view (zoom/limits/pick)
            end
            obj.LastKey = key;
            for i = 1:numel(obj.Panels)
                % frozen panels are a snapshot: keep their exact render (incl. zoom),
                % except on the very first draw (e.g. a restored session) so they appear.
                if obj.Panels(i).frozen && ~firstDraw, continue; end
                obj.drawPanel(i, D, drawMask);
            end
            obj.refreshStatus();
            if ~isempty(obj.Counts) && isvalid(obj.Counts.Fig)   % keep an open counts window in sync
                obj.Counts.show(D, obj.countsPanels());
            end
        end

        % ----- persistence ------------------------------------------------ %
        function s = getControlState(obj)
            s = struct();
            s.group   = obj.GroupDD.Value;
            s.colorBy = obj.ColorByDD.Value;
            s.median = obj.MedianChk.Value;
            s.flipY  = obj.FlipYChk.Value;
            s.hold   = obj.HoldChk.Value;
            s.xlim   = obj.XLimField.Value;
            s.ylim   = obj.YLimField.Value;
            s.smooth = obj.SmoothField.Value;
            s.active = obj.ActivePanel;
            panels = cell(1, numel(obj.Panels));
            for i = 1:numel(obj.Panels)
                panels{i} = struct('cfg', obj.Panels(i).cfg, 'overlays', {obj.Panels(i).overlays}, ...
                                   'frozen', obj.Panels(i).frozen, 'mask', obj.Panels(i).mask);
            end
            s.panels = panels;
        end

        function setControlState(obj, s)
            if isfield(s,'group'),   obj.setCtrl(obj.GroupDD,   s.group);   end
            if isfield(s,'colorBy'), obj.setCtrl(obj.ColorByDD, s.colorBy); end
            if isfield(s,'median') && ~isempty(obj.MedianChk), obj.MedianChk.Value = logical(s.median); end
            if isfield(s,'flipY')  && ~isempty(obj.FlipYChk),  obj.FlipYChk.Value  = logical(s.flipY);  end
            if isfield(s,'hold')   && ~isempty(obj.HoldChk),   obj.HoldChk.Value   = logical(s.hold);   end
            if isfield(s,'xlim')   && ~isempty(obj.XLimField), try, obj.XLimField.Value = char(string(s.xlim)); catch, end, end %#ok<CTCH>
            if isfield(s,'ylim')   && ~isempty(obj.YLimField), try, obj.YLimField.Value = char(string(s.ylim)); catch, end, end %#ok<CTCH>
            if isfield(s,'smooth') && ~isempty(obj.SmoothField) && isnumeric(s.smooth) && isscalar(s.smooth) && isfinite(s.smooth)
                lim = obj.SmoothField.Limits;            % clamp to Limits so an out-of-range saved state can't throw
                obj.SmoothField.Value = min(max(round(s.smooth), lim(1)), lim(2));
            end
            if isfield(s,'panels') && ~isempty(s.panels), obj.rebuildPanels(s.panels); end
            if isfield(s,'active') && ~isempty(obj.Panels)
                obj.ActivePanel = min(max(1, round(s.active)), numel(obj.Panels));
            end
            obj.refreshPanelDD();
            obj.syncFreezeBtn();
            obj.loadControlsFromActive();
            obj.LastKey = '';   % force a redraw on the next update (state changed)
        end
    end

    % ===================================================================== %
    %  Panel actions (wired to the buttons / dropdowns)
    % ===================================================================== %
    methods
        function addPanel(obj)
            %ADDPANEL  Clone the active panel's config into a new panel.
            if numel(obj.Panels) >= obj.MaxPanels
                uialert(obj.Viz.Fig, sprintf('At most %d panels.', obj.MaxPanels), 'Laminar viewer');
                return;
            end
            if isempty(obj.Panels), cfg = obj.readCfg(); else, cfg = obj.Panels(obj.ActivePanel).cfg; end
            obj.createPanel(cfg);
            obj.ActivePanel = numel(obj.Panels);
            obj.relayoutPanels(); obj.refreshPanelDD(); obj.syncFreezeBtn(); obj.loadControlsFromActive();
            obj.requestRefresh();
        end

        function removeActivePanel(obj)
            %REMOVEACTIVEPANEL  Delete the active panel (always keeps one).
            if numel(obj.Panels) <= 1, return; end
            i = obj.ActivePanel;
            try, delete(obj.Panels(i).ax); catch, end %#ok<CTCH>
            obj.Panels(i) = [];
            obj.ActivePanel = min(i, numel(obj.Panels));
            obj.relayoutPanels(); obj.refreshPanelDD(); obj.syncFreezeBtn(); obj.loadControlsFromActive();
            obj.requestRefresh();
        end

        function plotToActive(obj)
            %PLOTTOACTIVE  Pin the current selection to the active panel. Hold OFF
            %   just shows the live selection (drops overlays); Hold ON appends it
            %   as an extra overlaid layer (different marker) for side-by-side compare.
            if isempty(obj.Panels), obj.addPanel(); end
            ap = obj.ActivePanel;
            if obj.holdOn()
                obj.Panels(ap).overlays{end+1} = obj.readCfg();
            else
                obj.Panels(ap).overlays = {};
                obj.Panels(ap).cfg = obj.readCfg();
            end
            obj.requestRefresh();
        end

        function clearActivePanel(obj)
            %CLEARACTIVEPANEL  Drop the overlaid layers from the active panel.
            if isempty(obj.Panels), return; end
            obj.Panels(obj.ActivePanel).overlays = {};
            obj.requestRefresh();
        end

        function freezeActivePanel(obj)
            %FREEZEACTIVEPANEL  Toggle freeze on the active panel. Freezing is a pure
            %   snapshot: the panel keeps EXACTLY what it shows (data + axes/zoom) and
            %   is skipped by later redraws, so neither it nor the other panels are
            %   replotted. Unfreezing makes it live again and redraws just that panel.
            if isempty(obj.Panels), return; end
            ap = obj.ActivePanel;
            if obj.Panels(ap).frozen
                obj.Panels(ap).frozen = false; obj.Panels(ap).mask = [];
                obj.syncFreezeBtn();
                if ~isempty(obj.LastD)        % became live -> refresh just this panel
                    obj.drawPanel(ap, obj.LastD, obj.LastMask & obj.groupMaskFor(obj.LastD));
                end
            else
                obj.Panels(ap).frozen = true;
                obj.Panels(ap).mask = obj.LastMask & obj.groupMaskFor(obj.LastD);   % pin current filter+group
                obj.syncFreezeBtn();
                obj.refreshFrozenTitle(ap);   % just mark the title; do NOT replot (keep the view as-is)
            end
            if ~isempty(obj.LastD)
                obj.LastKey = obj.drawKey(obj.LastMask & obj.groupMaskFor(obj.LastD));
            end
            if ~isempty(obj.Counts) && isvalid(obj.Counts.Fig)
                obj.Counts.show(obj.LastD, obj.countsPanels());
            end
        end

        function refreshFrozenTitle(obj, i)
            %REFRESHFROZENTITLE  Re-title panel i in place (to add/remove the frozen
            %   mark) without replotting it.
            if i < 1 || i > numel(obj.Panels), return; end
            P = obj.Panels(i);
            if isempty(P.ax) || ~isvalid(P.ax), return; end
            obj.finishPanel(P.ax, i, i == obj.ActivePanel, P.titleExtra, P.frozen);
        end

        function onPanelDD(obj)
            v = str2double(obj.PanelDD.Value);
            if isfinite(v), obj.ActivePanel = min(max(1, v), numel(obj.Panels)); end
            obj.syncFreezeBtn();
            obj.loadControlsFromActive();
            obj.requestRefresh();
        end

        function onAnimal(obj)
            %ONANIMAL  Animal changed: cascade penetration + task lists, then apply.
            a = obj.AnimalDD.Value;
            pitems = obj.penItems(a);
            obj.PenDD.Items = pitems; obj.PenDD.Value = pitems{1};
            obj.TaskLB.Items = obj.taskItems(a, str2double(pitems{1}));
            obj.TaskLB.Value = '(all tasks)';
            obj.applyToActive();
        end

        function onPen(obj)
            %ONPEN  Penetration changed: cascade the task list, then apply.
            obj.TaskLB.Items = obj.taskItems(obj.AnimalDD.Value, str2double(obj.PenDD.Value));
            obj.TaskLB.Value = '(all tasks)';
            obj.applyToActive();
        end

        function applyToActive(obj)
            %APPLYTOACTIVE  Store the current controls onto the active panel + redraw.
            if isempty(obj.Panels), return; end
            obj.Panels(obj.ActivePanel).cfg = obj.readCfg();
            obj.requestRefresh();
        end

        function onPanelClick(obj, i, ax, e)
            %ONPANELCLICK  Ring the unit nearest the click in panel i + show its number.
            if i < 1 || i > numel(obj.Panels), return; end
            P = obj.Panels(i);
            if isempty(P.pidx), return; end
            try, pt = e.IntersectionPoint(1:2); catch, return; end %#ok<CTCH>
            u = viz.plots.V01util.nearestUnit(ax, P.px, P.py, P.pidx, pt);
            if ~isfinite(u), return; end
            obj.SelectedUnit = u;
            viz.plots.V01util.ringUnit(ax, P.px, P.py, P.pidx, u, sprintf('#%d', u));
            obj.showPickedUnit(u);
            obj.inspectPick(u);                 % open/update the unit-inspector popup
            obj.trackPick(u);                   % ring across every plot if tracking
        end

        function openCounts(obj)
            %OPENCOUNTS  Open/refresh the unit-count breakdown window (per panel).
            if isempty(obj.Counts) || ~isvalid(obj.Counts.Fig)
                obj.Counts = viz.plots.UnitCountsWindow(obj.LastD);
            end
            obj.Counts.show(obj.LastD, obj.countsPanels());
        end

        function panels = countsPanels(obj)
            %COUNTSPANELS  Per-panel {label, plotted unit indices} for the counts window.
            panels = struct('label',{},'idx',{});
            for i = 1:numel(obj.Panels)
                cfg = obj.normalizeCfg(obj.Panels(i).cfg);
                lab = sprintf('P%d(%s)', i, char(string(cfg.animal)));
                % unique row indices: overlapping overlays draw a row twice, but it is
                % ONE observation (obs counts distinct rows incl. laser-power repeats).
                panels(end+1) = struct('label', lab, 'idx', unique(obj.Panels(i).pidx(:))); %#ok<AGROW>
            end
        end
    end

    % ===================================================================== %
    methods (Access = private)
        % ----- registry / item lists -------------------------------------- %
        function buildParamRegistry(obj)
            D = obj.Viz.D; N = obj.Viz.N;
            [names, types] = filter.filterableVars(D, N);
            exclude = {'ch','Penetration','Dataset','U_unity','PairID','Tasknumb','Animal','EI','LG'};
            keep = strcmp(types, 'numeric') & ~ismember(names, exclude);
            obj.ParamKeys = names(keep);
            if isempty(obj.ParamKeys)               % fall back to any numeric field
                obj.ParamKeys = names(strcmp(types, 'numeric'));
            end
        end

        function p = defaultParam(obj)
            if any(strcmp(obj.ParamKeys, 'Delta_Fr')), p = 'Delta_Fr';
            else, p = obj.ParamKeys{1}; end
        end

        function items = animalItems(obj)
            D = obj.Viz.D;
            if isfield(D, 'Animal')
                a = unique(string(D.Animal(:)), 'stable'); a(ismissing(a) | a == "") = [];
                items = cellstr(a);
            elseif isfield(D, 'Dataset')
                u = unique(double(D.Dataset(:))); u = u(isfinite(u));
                items = arrayfun(@num2str, u, 'UniformOutput', false);
            else
                items = {'(all)'};
            end
            if isempty(items), items = {'(all)'}; end
        end

        function items = penItems(obj, animal)
            D = obj.Viz.D; m = obj.animalMask(D, animal);
            if isfield(D, 'Penetration')
                p = unique(double(D.Penetration(m))); p = p(isfinite(p));
                items = arrayfun(@num2str, p(:)', 'UniformOutput', false);
            else
                items = {};
            end
            if isempty(items), items = {'(all)'}; end
        end

        function items = taskItems(obj, animal, pen)
            D = obj.Viz.D; m = obj.animalMask(D, animal);
            if isfield(D, 'Penetration') && ~isnan(pen)
                m = m & (double(D.Penetration(:)) == pen);
            end
            tk = {};
            if isfield(D, 'Tasknumb')
                t = unique(string(D.Tasknumb(m)), 'stable'); t(ismissing(t) | t == "") = [];
                tk = cellstr(t(:)');
            end
            items = [{'(all tasks)'}, tk];
        end

        function m = animalMask(obj, D, animal)
            N = obj.Viz.N;
            if isfield(D, 'Animal')
                m = (string(D.Animal(:)) == string(animal));
            elseif isfield(D, 'Dataset')
                m = (double(D.Dataset(:)) == str2double(string(animal)));
            else
                m = true(N, 1);
            end
        end

        % ----- control <-> cfg -------------------------------------------- %
        function cfg = readCfg(obj)
            cfg.param  = obj.ParamDD.Value;
            cfg.animal = obj.AnimalDD.Value;
            cfg.pen    = str2double(obj.PenDD.Value);     % NaN for '(all)'
            v = obj.TaskLB.Value;
            if ischar(v), v = {v}; elseif isstring(v), v = cellstr(v); end
            if isempty(v) || any(strcmp(v, '(all tasks)'))
                cfg.tasks = {};
            else
                cfg.tasks = v(:)';
            end
        end

        function loadControlsFromActive(obj)
            if isempty(obj.Panels), return; end
            cfg = obj.Panels(obj.ActivePanel).cfg;
            obj.setCtrl(obj.ParamDD, cfg.param);
            obj.setCtrl(obj.AnimalDD, char(string(cfg.animal)));
            obj.PenDD.Items = obj.penItems(cfg.animal);
            obj.setCtrl(obj.PenDD, num2str(cfg.pen));
            obj.TaskLB.Items = obj.taskItems(cfg.animal, cfg.pen);
            if isempty(cfg.tasks)
                obj.TaskLB.Value = '(all tasks)';
            else
                valid = cfg.tasks(ismember(cfg.tasks, obj.TaskLB.Items));
                if isempty(valid), obj.TaskLB.Value = '(all tasks)'; else, obj.TaskLB.Value = valid; end
            end
        end

        function tf = holdOn(obj)
            tf = ~isempty(obj.HoldChk) && isvalid(obj.HoldChk) && obj.HoldChk.Value;
        end

        % ----- panel management ------------------------------------------- %
        function createPanel(obj, cfg)
            p.ax  = uiaxes(obj.PanelGrid);
            p.cfg = cfg;
            p.overlays = {}; p.frozen = false; p.mask = [];
            p.px = []; p.py = []; p.pidx = []; p.titleExtra = '';
            obj.Panels(end+1) = p;
        end

        function rebuildPanels(obj, panels)
            for i = 1:numel(obj.Panels)
                try, delete(obj.Panels(i).ax); catch, end %#ok<CTCH>
            end
            obj.Panels = struct('ax',{},'cfg',{},'overlays',{},'frozen',{},'mask',{},'px',{},'py',{},'pidx',{},'titleExtra',{});
            if iscell(panels)
                for i = 1:numel(panels)
                    e = panels{i};
                    if isstruct(e) && isfield(e,'cfg')               % new format {cfg,overlays,frozen,mask}
                        obj.createPanel(obj.normalizeCfg(e.cfg));
                        if isfield(e,'overlays') && iscell(e.overlays)
                            obj.Panels(end).overlays = cellfun(@(c) obj.normalizeCfg(c), e.overlays, 'UniformOutput', false);
                        end
                        if isfield(e,'frozen') && logical(e.frozen) && isfield(e,'mask') && numel(e.mask)==obj.Viz.N
                            obj.Panels(end).frozen = true;
                            obj.Panels(end).mask   = logical(e.mask(:));
                        end
                    elseif isstruct(e) && isfield(e,'param')         % old format: bare cfg
                        obj.createPanel(obj.normalizeCfg(e));
                    end
                end
            end
            if isempty(obj.Panels), obj.createPanel(obj.readCfg()); end
            obj.ActivePanel = 1;
            obj.relayoutPanels();
        end

        function c = normalizeCfg(obj, c)
            if ~isstruct(c), c = struct(); end
            if ~isfield(c,'param')  || isempty(c.param),  c.param  = obj.defaultParam(); end
            if ~isfield(c,'animal'), c.animal = obj.AnimalDD.Value; end
            if ~isfield(c,'pen'),    c.pen    = NaN; end
            if ~isfield(c,'tasks') || ~iscell(c.tasks), c.tasks = {}; end
        end

        function relayoutPanels(obj)
            P = numel(obj.Panels);
            if P == 0, return; end
            cols = min(P, 2); rows = ceil(P / cols);
            obj.PanelGrid.RowHeight   = repmat({'1x'}, 1, rows);
            obj.PanelGrid.ColumnWidth = repmat({'1x'}, 1, cols);
            for i = 1:P
                r = ceil(i / cols); c = i - (r-1)*cols;
                obj.Panels(i).ax.Layout.Row = r;
                obj.Panels(i).ax.Layout.Column = c;
            end
        end

        function refreshPanelDD(obj)
            P = max(numel(obj.Panels), 1);
            obj.PanelDD.Items = arrayfun(@num2str, 1:P, 'UniformOutput', false);
            obj.PanelDD.Value = num2str(min(max(1, obj.ActivePanel), P));
        end

        function syncFreezeBtn(obj)
            if isempty(obj.FreezeBtn) || ~isvalid(obj.FreezeBtn), return; end
            if ~isempty(obj.Panels) && obj.ActivePanel >= 1 && obj.ActivePanel <= numel(obj.Panels) ...
                    && obj.Panels(obj.ActivePanel).frozen
                obj.FreezeBtn.Text = 'Unfreeze';
            else
                obj.FreezeBtn.Text = 'Freeze';
            end
        end

        function refreshStatus(obj)
            if isempty(obj.statusLbl) || ~isvalid(obj.statusLbl), return; end
            obj.statusLbl.Text = sprintf(['%d panel(s).  Click near a point to ring it. ' ...
                'Hold + "Plot → active panel" overlays a selection; Freeze pins the filter.'], numel(obj.Panels));
        end

        function showPickedUnit(obj, u)
            if isempty(obj.statusLbl) || ~isvalid(obj.statusLbl), return; end
            D = obj.LastD; uu = NaN; extra = '';
            if isfield(D,'U_unity'), uu = double(D.U_unity(u)); end
            if isfield(D,'LG'), extra = sprintf('  LG=%s', char(string(D.LG(u)))); end
            obj.statusLbl.Text = sprintf('picked unit #%d  (U_unity %g)%s', u, uu, extra);
        end

        % ----- selection + drawing ---------------------------------------- %
        function idx = selIdx(obj, D, mask, cfg)
            sel = mask(:);
            sel = sel & obj.animalMask(D, cfg.animal);
            if isfield(D, 'Penetration') && ~isnan(cfg.pen)
                sel = sel & (double(D.Penetration(:)) == cfg.pen);
            end
            if isfield(D, 'Tasknumb') && ~isempty(cfg.tasks)
                sel = sel & ismember(string(D.Tasknumb(:)), string(cfg.tasks));
            end
            idx = find(sel);
        end

        function drawPanel(obj, i, D, mask)
            ax = obj.Panels(i).ax; cla(ax, 'reset');
            P = obj.Panels(i);
            cfg = obj.normalizeCfg(P.cfg);
            isActive = (i == obj.ActivePanel);
            grid(ax, 'on'); box(ax, 'on');
            ylabel(ax, 'channel');
            xlabel(ax, cfg.param, 'Interpreter', 'none');

            if ~isfield(D, 'ch')
                obj.Panels(i).px = []; obj.Panels(i).py = []; obj.Panels(i).pidx = [];
                obj.finishPanel(ax, i, isActive, 'no "ch" field in data', P.frozen); return;
            end
            if isempty(cfg.param) || ~isfield(D, cfg.param)
                obj.Panels(i).px = []; obj.Panels(i).py = []; obj.Panels(i).pidx = [];
                obj.finishPanel(ax, i, isActive, '(pick a parameter)', P.frozen); return;
            end

            drawMask = mask;
            if P.frozen && numel(P.mask) == numel(mask), drawMask = logical(P.mask(:)); end   % pinned filter

            key = obj.ColorByDD.Value;
            hold(ax, 'on');
            allX = []; allY = []; allIdx = [];
            [x0, y0, id0] = obj.drawLayer(ax, D, drawMask, cfg, 'o', key, true);   % live (primary) layer
            allX = [allX; x0(:)]; allY = [allY; y0(:)]; allIdx = [allIdx; id0(:)];
            for j = 1:numel(P.overlays)
                mk = obj.OV_MARKERS{mod(j-1, numel(obj.OV_MARKERS)) + 1};
                [xo, yo, ido] = obj.drawLayer(ax, D, drawMask, P.overlays{j}, mk, key, false);
                allX = [allX; xo(:)]; allY = [allY; yo(:)]; allIdx = [allIdx; ido(:)]; %#ok<AGROW>
            end
            hold(ax, 'off');
            obj.Panels(i).px = allX; obj.Panels(i).py = allY; obj.Panels(i).pidx = allIdx;

            if obj.FlipYChk.Value, ax.YDir = 'reverse'; else, ax.YDir = 'normal'; end
            yl = obj.parseLimField(obj.YLimField);
            if ~isempty(yl), ylim(ax, yl); end          % blank field -> auto
            xl = obj.parseLimField(obj.XLimField);
            if ~isempty(xl), xlim(ax, xl); end          % blank field -> auto

            ax.ButtonDownFcn = @(s,e) obj.onPanelClick(i, s, e);
            obj.registerRing(ax, allX, allY, allIdx);   % track unit across plots
            if isfinite(obj.SelectedUnit)               % re-ring the pick (survives redraws)
                viz.plots.V01util.ringUnit(ax, allX, allY, allIdx, obj.SelectedUnit, sprintf('#%d', obj.SelectedUnit));
            end
            obj.drawOverlayLegend(ax, P, cfg);

            obj.finishPanel(ax, i, isActive, obj.titleStr(cfg, numel(id0)), P.frozen);
        end

        function [px, py, pidx] = drawLayer(obj, ax, D, mask, cfg, marker, key, isPrimary)
            %DRAWLAYER  Draw one selection (cfg) as a scatter with the given marker.
            %   Returns the plotted (param,channel,unit-index) for click-picking.
            %   The primary layer also draws the LG borders, zero line, median line
            %   and the per-layer count / color legend.
            px = []; py = []; pidx = [];
            cfg = obj.normalizeCfg(cfg);
            if isempty(cfg.param) || ~isfield(D, cfg.param), return; end
            idx   = obj.selIdx(D, mask, cfg);
            ch    = double(D.ch(:));
            x     = double(D.(cfg.param)(:));
            layer = viz.plots.V01util.layerNum(D);     % 1..4 (NaN if LG unassigned)
            xx = x(idx); yy = ch(idx); ll = layer(idx);
            ok = isfinite(xx) & isfinite(yy);
            xx = xx(ok); yy = yy(ok); ll = ll(ok); idxk = idx(ok);
            if isempty(xx), return; end

            [ci, pal, clabels, ccounts] = viz.plots.V01util.colorBy(D, idxk, key);
            scatter(ax, xx, yy, obj.MARKER_SZ, pal(ci, :), 'filled', 'Marker', marker, ...
                'MarkerFaceAlpha', 0.7, 'MarkerEdgeColor', 'none', 'PickableParts', 'none');
            px = xx; py = yy; pidx = idxk;
            if ~isPrimary, return; end

            % layer borders derived from LG (line between each adjacent pair present)
            [bc, labs] = obj.borderChannels(ll, yy);
            for b = 1:numel(bc)
                yl = yline(ax, bc(b), '-', labs{b});
                yl.Color = [0.4 0.4 0.4]; yl.FontSize = 7;
                yl.LabelHorizontalAlignment = 'left'; yl.LabelVerticalAlignment = 'bottom';
                yl.PickableParts = 'none';
            end
            xl0 = xline(ax, 0, '-', 'Color', [0.82 0.82 0.82]); xl0.PickableParts = 'none';   % zero reference

            if obj.MedianChk.Value
                uch = unique(yy);
                med = arrayfun(@(c) median(xx(yy == c), 'omitnan'), uch);
                span = obj.smoothSpan();
                if span >= 2, med = movmedian(med, span, 'omitnan'); end
                ph = plot(ax, med, uch, '-', 'Color', [0 0 0], 'LineWidth', 1.3); ph.PickableParts = 'none';
            end

            cnt = arrayfun(@(L) sum(ll == L), 1:4);
            text(ax, 0.98, 0.98, sprintf('SG=%d  G=%d\nIG=%d  Deep=%d', cnt(1), cnt(2), cnt(3), cnt(4)), ...
                'Units', 'normalized', 'HorizontalAlignment', 'right', 'VerticalAlignment', 'top', ...
                'FontSize', 7, 'Interpreter', 'none', 'Color', [0.25 0.25 0.25], 'PickableParts', 'none');

            if ~strcmpi(key, 'Layer')          % color legend (top-left) when not coloring by layer
                yc = 0.98;
                for k = 1:numel(clabels)
                    if ccounts(k) == 0, continue; end
                    text(ax, 0.02, yc, sprintf('%s (%d)', clabels{k}, ccounts(k)), ...
                        'Units','normalized', 'HorizontalAlignment','left', 'VerticalAlignment','top', ...
                        'FontSize', 7, 'Interpreter','none', 'FontWeight','bold', 'Color', pal(k,:), 'PickableParts','none');
                    yc = yc - 0.055;
                end
            end
        end

        function drawOverlayLegend(obj, ax, P, cfg)
            %DRAWOVERLAYLEGEND  When a panel has overlaid layers, list which marker
            %   shows which selection (live = circle, ov1 = square, ...), bottom-left.
            if isempty(P.overlays), return; end
            lines = {sprintf('live(o): %s', obj.shortCfg(cfg))};
            for j = 1:numel(P.overlays)
                mk = obj.OV_MARKERS{mod(j-1, numel(obj.OV_MARKERS)) + 1};
                lines{end+1} = sprintf('ov%d(%s): %s', j, mk, obj.shortCfg(P.overlays{j})); %#ok<AGROW>
            end
            yc = 0.02 + 0.05*(numel(lines)-1);
            for k = 1:numel(lines)
                text(ax, 0.02, yc, lines{k}, 'Units','normalized', 'FontSize',7, 'Interpreter','none', ...
                    'VerticalAlignment','bottom', 'HorizontalAlignment','left', 'Color',[0.2 0.2 0.2], 'PickableParts','none');
                yc = yc - 0.05;
            end
        end

        function s = shortCfg(obj, cfg)
            cfg = obj.normalizeCfg(cfg);
            if isempty(cfg.tasks), tstr = 'all'; else, tstr = strjoin(cfg.tasks, ','); end
            if isnan(cfg.pen), pstr = '?'; else, pstr = num2str(cfg.pen); end
            s = sprintf('%s P%s %s [%s]', char(string(cfg.animal)), pstr, tstr, cfg.param);
        end

        function [bc, labs] = borderChannels(obj, layer, ch)
            %BORDERCHANNELS  Boundary channel between each pair of adjacent layers
            %   present among the plotted points. Orientation-robust: places the
            %   line midway between the two layers' nearest channels.
            bc = []; labs = {};
            names = obj.LAYER_NAMES;
            for L = 1:3
                gA = ch(layer == L); gB = ch(layer == L+1);
                if isempty(gA) || isempty(gB), continue; end
                if median(gA) > median(gB), b = (min(gA) + max(gB)) / 2;
                else,                        b = (max(gA) + min(gB)) / 2;
                end
                bc(end+1)   = b;                                  %#ok<AGROW>
                labs{end+1} = sprintf('%s|%s', names{L}, names{L+1}); %#ok<AGROW>
            end
        end

        function lim = parseLimField(~, field)
            %PARSELIMFIELD  [min max] parsed from a limit edit-field, or [] when it
            %   is blank/invalid (-> auto). Accepts "1 384", "[1,384]", "-1 2", ...
            lim = [];
            if isempty(field) || ~isvalid(field), return; end
            s = strtrim(field.Value);
            if isempty(s), return; end
            v = sscanf(regexprep(s, '[\[\],]', ' '), '%g');
            if numel(v) >= 2 && isfinite(v(1)) && isfinite(v(2)) && v(1) < v(2)
                lim = [v(1) v(2)];
            end
        end

        function gm = groupMaskFor(obj, D)
            %GROUPMASKFOR  Logical Nx1 TuningG unit-group mask for GroupDD (all-true
            %   for ALL_UNITS / on error). Intersected with the toolbar filters.
            N = obj.Viz.N; gm = true(N,1);
            if isempty(obj.GroupDD) || ~isvalid(obj.GroupDD), return; end
            g = obj.GroupDD.Value;
            if strcmpi(g, 'ALL_UNITS'), return; end
            try, gm = logical(analysis.tuningGroupMask(D, g)); catch, gm = true(N,1); end %#ok<CTCH>
            gm = gm(:);
        end

        function k = drawKey(obj, drawMask)
            %DRAWKEY  Signature of everything that affects the drawing, so update()
            %   can skip a redraw (and keep the user's zoom/limits/pick) when a mere
            %   tab switch fires it with no real change. SelectedUnit is intentionally
            %   excluded (clicks ring without a redraw).
            s = struct();
            s.group = obj.GroupDD.Value; s.color = obj.ColorByDD.Value;
            s.med = obj.MedianChk.Value; s.flip = obj.FlipYChk.Value;
            s.xl = obj.XLimField.Value;  s.yl = obj.YLimField.Value; s.sm = obj.SmoothField.Value;
            s.active = obj.ActivePanel;  s.np = numel(obj.Panels);
            ps = cell(1, numel(obj.Panels));
            for i = 1:numel(obj.Panels)
                P = obj.Panels(i);
                ov = cellfun(@(c) obj.cfgStr(c), P.overlays, 'UniformOutput', false);
                fm = '';
                if P.frozen, fm = sprintf('F%d:%d', nnz(P.mask), mod(sum(find(P.mask)), 1e9)); end
                ps{i} = sprintf('%s||%s||%s', obj.cfgStr(P.cfg), strjoin(ov, ';'), fm);
            end
            s.panels = strjoin(ps, '##');
            s.mask = sprintf('%d:%d', nnz(drawMask), mod(sum(find(drawMask)), 1e9));
            k = jsonencode(s);
        end

        function s = cfgStr(obj, cfg)
            cfg = obj.normalizeCfg(cfg);
            if isnan(cfg.pen), pstr = ''; else, pstr = num2str(cfg.pen); end
            s = sprintf('%s|%s|%s|%s', char(string(cfg.param)), char(string(cfg.animal)), ...
                pstr, strjoin(cfg.tasks, ','));
        end

        function n = smoothSpan(obj)
            %SMOOTHSPAN  Median-line movmedian window (0 if the field is empty/invalid).
            n = 0;
            if isempty(obj.SmoothField) || ~isvalid(obj.SmoothField), return; end
            v = obj.SmoothField.Value;
            if isnumeric(v) && isscalar(v) && isfinite(v), n = max(0, round(v)); end
        end

        function s = titleStr(obj, cfg, N)
            if isempty(cfg.tasks), tstr = 'all tasks'; else, tstr = strjoin(cfg.tasks, ','); end
            if isnan(cfg.pen), pstr = '?'; else, pstr = num2str(cfg.pen); end
            s = sprintf('%s \x00b7 P%s \x00b7 %s  (N=%d)', char(string(cfg.animal)), pstr, tstr, N);
        end

        function finishPanel(obj, ax, i, isActive, extra, frozen)
            if i >= 1 && i <= numel(obj.Panels), obj.Panels(i).titleExtra = extra; end  % for in-place re-title
            mark = ''; col = [0 0 0];
            if isActive, mark = '  \x25cf active'; col = [0 0 0.65]; end
            if nargin >= 6 && frozen, mark = [mark '  \x2744 frozen']; col = [0 0.45 0.74]; end
            % sprintf resolves the \x escapes to real chars; 'none' renders them
            % literally (and won't treat '_' in metric names as a subscript).
            title(ax, sprintf(['Panel %d \x2014 %s' mark], i, extra), ...
                  'Color', col, 'Interpreter', 'none');
        end
    end
end

% ----------------------------------------------------------------------- %
function h = lab(g, row, txt)
%LAB  A left-aligned label placed on row ROW of grid G.
    h = uilabel(g, 'Text', txt);
    h.Layout.Row = row; h.Layout.Column = 1;
end
