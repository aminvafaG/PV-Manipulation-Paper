classdef LaminarViewsTab < viz.PlotTab
%LAMINARVIEWSTAB  Multi-panel laminar "Laminar View" viewer (ported from the old
%   F2_5B_3.m lines 2371-2496) where each panel is one of two plot types:
%
%     TYPE 1  channel (y) vs penetration session (x). Each session is a column;
%        within a column points are spread horizontally by the firing-rate change
%        (x = sessionIndex - jitter*Delta_Fr). A faint vertical line spans
%        0..max(channel); LG layer borders are short horizontal ticks per column
%        (SG|G, G|IG black; IG|Deep red). "Median/ch" overlays a per-penetration
%        median of the (ΔFr-encoded) x at each channel.
%
%     TYPE 2  a per-unit value (y) vs cortical layer SG/G/IG/Deep (x), random
%        x-jitter, with a per-(layer,color) mean line. The y defaults to the old
%        sign-based DeltaFR_N (else a chosen metric).
%
%   PANELS (like viz.plots.LaminarTab / TuningTab). The left controls edit the
%   ACTIVE panel live. "Add" makes a new panel of the type chosen in "Add as plot
%   type"; "Remove" drops it; "Active panel" picks the target. Per panel you set
%   Animal / Penetration / Tasks ((all) = everything) -- for a TYPE-1 panel these
%   pick which sessions appear; for a TYPE-2 panel which units. "Plot -> active
%   panel" + "Hold" overlay another selection (different marker); "Clear" drops the
%   overlays; "Freeze" pins the panel's filter. X / Y limits are per panel.
%
%   COLOR / GROUP / JITTER / FLIP are global; "Color by = G_type" matches the
%   original figure. "Unit counts" opens a pop-up tabulating the units in each
%   panel by any category combination (obs + unique-neuron). Click near a point to
%   ring it. Switching tabs keeps the view (limits / pick survive).
%
%   See also: viz.PlotTab, viz.plots.LaminarTab, viz.plots.UnitCountsWindow,
%             viz.plots.V01util, analysis.tuningGroupMask

    properties
        % controls
        GroupDD; ColorByDD; AddTypeDD; ParamDD
        AnimalDD; PenDD; TaskLB
        JitterField; MedianChk; FlipYChk; HoldChk
        XLimField; YLimField; SmoothField
        PanelDD; FreezeBtn; statusLbl

        ParamKeys = {}
        Counts = []                    % viz.plots.UnitCountsWindow (lazy)

        % plot panels
        PanelGrid
        % type: 1|2 ; cfg: animal/pen/tasks/param/xlim/ylim ; overlays: extra cfgs
        % frozen/mask: pinned filter ; px/py/pidx: plotted points for click-picking
        Panels = struct('ax',{},'type',{},'cfg',{},'overlays',{},'frozen',{},'mask',{},'px',{},'py',{},'pidx',{})
        ActivePanel = 0
        SelectedUnit = NaN
        LastD = []; LastMask = []
        LastKey = ''
    end

    properties (Constant)
        MaxPanels   = 8
        GROUPS      = {'ALL_UNITS','NO_ORI_ON_PV','NO_ORI_NO_PV','ORI_ON_PV','ORI_NON_PV','ORI_NON_PV_MD','ORI_NON_PV_NL','ORI_NON_PV_U','OUTLIER'};
        COLOR_BY    = {'Layer','G_type','E/I','Animal','Penetration','Task'};
        LAYER_NAMES = {'SG','G','IG','Deep'};
        MARKER_SZ   = 26;
        OV_MARKERS  = {'s','^','d','v','p','h'};
        DFRN_LABEL  = 'DeltaFR_N (sign-based)';
        TYPE_ITEMS  = {'1: channel vs penetration','2: dFR vs layer'};
    end

    methods
        function obj = LaminarViewsTab()
            obj@viz.PlotTab('Laminar views');
        end

        % ================================================================= %
        function buildControls(obj, parent)
            obj.buildParamRegistry();

            g = uigridlayout(parent, [29 1]);
            g.RowHeight = {18,26, 18,26, 18,26, 18,26, 18,26, 18,90, 18,26, 18,26, 26, 28, 18,26, 18,26, 18,26, 18,26, 28, 28, 60};
            g.RowSpacing = 4; g.Padding = [8 8 8 8];
            try, g.Scrollable = 'on'; catch, end %#ok<CTCH>

            lab(g, 1, 'Unit group (TuningG)');
            obj.GroupDD = uidropdown(g, 'Items', obj.GROUPS, 'Value', 'ALL_UNITS', ...
                'Tooltip', 'Restrict to a Visualizer-01 TuningG unit group (intersected with the toolbar filters).', ...
                'ValueChangedFcn', @(s,e) obj.requestRefresh());
            obj.GroupDD.Layout.Row = 2;

            lab(g, 3, 'Color by');
            obj.ColorByDD = uidropdown(g, 'Items', obj.COLOR_BY, 'Value', 'Layer', ...
                'Tooltip', 'Feature used to color the points. Set to G_type to match the original figure.', ...
                'ValueChangedFcn', @(s,e) obj.requestRefresh());
            obj.ColorByDD.Layout.Row = 4;

            lab(g, 5, 'Add as plot type');
            obj.AddTypeDD = uidropdown(g, 'Items', obj.TYPE_ITEMS, 'ItemsData', {1, 2}, 'Value', 1, ...
                'Tooltip', 'Plot type used by the "Add" button when creating a new panel.');
            obj.AddTypeDD.Layout.Row = 6;

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
            obj.TaskLB = uilistbox(g, 'Items', obj.taskItems(items{1}, NaN), 'Multiselect','on', ...
                'Value', '(all tasks)', 'ValueChangedFcn', @(s,e) obj.applyToActive());
            obj.TaskLB.Layout.Row = 12;

            lab(g, 13, 'Layer-plot Y metric (type 2)');
            obj.ParamDD = uidropdown(g, 'Items', [{obj.DFRN_LABEL}, obj.ParamKeys], 'Value', obj.DFRN_LABEL, ...
                'Tooltip', 'Per-unit value plotted against layer in a TYPE-2 panel. Default = old sign-based DeltaFR_N.', ...
                'ValueChangedFcn', @(s,e) obj.applyToActive());
            obj.ParamDD.Layout.Row = 14;

            lab(g, 15, 'Jitter (type-1 x-spread)');
            obj.JitterField = uieditfield(g, 'numeric', 'Value', 0.3, 'Limits', [0 100], ...
                'Tooltip', 'Type-1 x = session - jitter*Delta_Fr; old code used 0.3.', ...
                'ValueChangedFcn', @(s,e) obj.requestRefresh());
            obj.JitterField.Layout.Row = 16;

            og = uigridlayout(g, [1 3], 'Padding',[0 0 0 0], 'ColumnSpacing',6);
            og.Layout.Row = 17;
            obj.MedianChk = uicheckbox(og, 'Text','Median/ch', 'Value', false, ...
                'Tooltip','Type-1: per-penetration median of the (Delta_Fr) x-position at each channel.', ...
                'ValueChangedFcn', @(s,e) obj.requestRefresh());
            obj.FlipYChk = uicheckbox(og, 'Text','Flip', 'Value', false, ...
                'Tooltip','Flip the depth axis: type-1 channel (y) and type-2 layer order (x).', ...
                'ValueChangedFcn', @(s,e) obj.requestRefresh());
            obj.HoldChk = uicheckbox(og, 'Text','Hold', 'Value', false, ...
                'Tooltip','When on, "Plot -> active panel" OVERLAYS the current selection (different marker).');

            pg = uigridlayout(g, [1 2], 'Padding',[0 0 0 0], 'ColumnSpacing',4);
            pg.Layout.Row = 18; pg.ColumnWidth = {'1x', 70};
            uibutton(pg, 'Text','Plot → active panel', 'FontWeight','bold', 'ButtonPushedFcn', @(s,e) obj.plotToActive());
            uibutton(pg, 'Text','Clear', 'ButtonPushedFcn', @(s,e) obj.clearActivePanel());

            lab(g, 19, 'X limit  [min max]  (blank = auto)');
            obj.XLimField = uieditfield(g, 'text', 'Value', '', 'Placeholder', 'e.g. 0.5 5', ...
                'Tooltip', 'X-axis limits for the ACTIVE panel; blank = auto.', ...
                'ValueChangedFcn', @(s,e) obj.applyToActive());
            obj.XLimField.Layout.Row = 20;

            lab(g, 21, 'Y limit  [min max]  (blank = auto)');
            obj.YLimField = uieditfield(g, 'text', 'Value', '', 'Placeholder', 'e.g. 1 384', ...
                'Tooltip', 'Y-axis limits for the ACTIVE panel (channel for type-1, metric for type-2); blank = auto.', ...
                'ValueChangedFcn', @(s,e) obj.applyToActive());
            obj.YLimField.Layout.Row = 22;

            lab(g, 23, 'Median smooth (span; 0 = off)');
            obj.SmoothField = uieditfield(g, 'numeric', 'Value', 0, 'Limits', [0 999], 'RoundFractionalValues','on', ...
                'Tooltip', 'movmedian window for the type-1 median line; 0/1 = raw median.', ...
                'ValueChangedFcn', @(s,e) obj.requestRefresh());
            obj.SmoothField.Layout.Row = 24;

            lab(g, 25, 'Active panel');
            obj.PanelDD = uidropdown(g, 'Items', {'1'}, 'Value', '1', 'ValueChangedFcn', @(s,e) obj.onPanelDD());
            obj.PanelDD.Layout.Row = 26;

            ag = uigridlayout(g, [1 3], 'Padding',[0 0 0 0], 'ColumnSpacing',4);
            ag.Layout.Row = 27;
            uibutton(ag, 'Text','Add', 'ButtonPushedFcn', @(s,e) obj.addPanel());
            obj.FreezeBtn = uibutton(ag, 'Text','Freeze', 'ButtonPushedFcn', @(s,e) obj.freezeActivePanel());
            uibutton(ag, 'Text','Remove', 'ButtonPushedFcn', @(s,e) obj.removeActivePanel());

            cb = uibutton(g, 'Text', sprintf('\x2630 Unit counts'), 'ButtonPushedFcn', @(s,e) obj.openCounts(), ...
                'Tooltip','Pop-up tabulating the units in each panel (obs + unique) by any category combination.');
            cb.Layout.Row = 28;

            obj.statusLbl = uilabel(g, 'Text','', 'WordWrap','on', 'VerticalAlignment','top');
            obj.statusLbl.Layout.Row = 29;

            obj.addInspectCheckbox(g);
        end

        function buildView(obj, parent)
            obj.PanelGrid = uigridlayout(parent, [1 1]);
            obj.PanelGrid.Padding = [4 4 4 4]; obj.PanelGrid.RowSpacing = 6; obj.PanelGrid.ColumnSpacing = 6;
            obj.Panels = struct('ax',{},'type',{},'cfg',{},'overlays',{},'frozen',{},'mask',{},'px',{},'py',{},'pidx',{});
            obj.createPanel(1, obj.defaultCfg());      % one of each, side by side (old look)
            obj.createPanel(2, obj.defaultCfg());
            obj.ActivePanel = 1;
            obj.relayoutPanels(); obj.refreshPanelDD(); obj.syncFreezeBtn(); obj.loadControlsFromActive();
        end

        % ================================================================= %
        function update(obj, D, mask)
            obj.LastD = D; obj.LastMask = logical(mask(:));
            drawMask = obj.LastMask & obj.groupMaskFor(D);
            key = obj.drawKey(drawMask);
            firstDraw = isempty(obj.LastKey);
            if strcmp(key, obj.LastKey) && ~firstDraw, return; end
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
            s = struct('group',obj.GroupDD.Value, 'colorBy',obj.ColorByDD.Value, 'addType',obj.AddTypeDD.Value, ...
                'jitter',obj.JitterField.Value, 'median',obj.MedianChk.Value, 'flipY',obj.FlipYChk.Value, ...
                'hold',obj.HoldChk.Value, 'smooth',obj.SmoothField.Value, 'active',obj.ActivePanel);
            panels = cell(1, numel(obj.Panels));
            for i = 1:numel(obj.Panels)
                panels{i} = struct('type',obj.Panels(i).type, 'cfg',obj.Panels(i).cfg, ...
                    'overlays',{obj.Panels(i).overlays}, 'frozen',obj.Panels(i).frozen, 'mask',obj.Panels(i).mask);
            end
            s.panels = panels;
        end

        function setControlState(obj, s)
            if isfield(s,'group'),   obj.setCtrl(obj.GroupDD,   s.group);   end
            if isfield(s,'colorBy'), obj.setCtrl(obj.ColorByDD, s.colorBy); end
            if isfield(s,'addType'), obj.setCtrl(obj.AddTypeDD, s.addType); end
            if isfield(s,'median') && ~isempty(obj.MedianChk), obj.MedianChk.Value = logical(s.median); end
            if isfield(s,'flipY')  && ~isempty(obj.FlipYChk),  obj.FlipYChk.Value  = logical(s.flipY);  end
            if isfield(s,'hold')   && ~isempty(obj.HoldChk),   obj.HoldChk.Value   = logical(s.hold);   end
            if isfield(s,'jitter') && ~isempty(obj.JitterField) && isnumeric(s.jitter) && isscalar(s.jitter) && isfinite(s.jitter)
                lim = obj.JitterField.Limits; obj.JitterField.Value = min(max(s.jitter, lim(1)), lim(2));
            end
            if isfield(s,'smooth') && ~isempty(obj.SmoothField) && isnumeric(s.smooth) && isscalar(s.smooth) && isfinite(s.smooth)
                lim = obj.SmoothField.Limits; obj.SmoothField.Value = min(max(round(s.smooth), lim(1)), lim(2));
            end
            if isfield(s,'panels') && ~isempty(s.panels), obj.rebuildPanels(s.panels); end
            if isfield(s,'active') && ~isempty(obj.Panels)
                obj.ActivePanel = min(max(1, round(s.active)), numel(obj.Panels));
            end
            obj.refreshPanelDD(); obj.syncFreezeBtn(); obj.loadControlsFromActive();
            obj.LastKey = '';
        end
    end

    % ===================================================================== %
    %  Panel actions + click handlers (public so they can be scripted/tested)
    % ===================================================================== %
    methods
        function addPanel(obj)
            if numel(obj.Panels) >= obj.MaxPanels
                uialert(obj.Viz.Fig, sprintf('At most %d panels.', obj.MaxPanels), 'Laminar views'); return;
            end
            obj.createPanel(obj.AddTypeDD.Value, obj.readCfg());
            obj.ActivePanel = numel(obj.Panels);
            obj.relayoutPanels(); obj.refreshPanelDD(); obj.syncFreezeBtn(); obj.loadControlsFromActive();
            obj.requestRefresh();
        end

        function removeActivePanel(obj)
            if numel(obj.Panels) <= 1, return; end
            i = obj.ActivePanel;
            try, delete(obj.Panels(i).ax); catch, end %#ok<CTCH>
            obj.Panels(i) = [];
            obj.ActivePanel = min(i, numel(obj.Panels));
            obj.relayoutPanels(); obj.refreshPanelDD(); obj.syncFreezeBtn(); obj.loadControlsFromActive();
            obj.requestRefresh();
        end

        function plotToActive(obj)
            if isempty(obj.Panels), obj.addPanel(); return; end
            ap = obj.ActivePanel;
            if obj.holdOn()
                obj.Panels(ap).overlays{end+1} = obj.readCfg();
            else
                obj.Panels(ap).overlays = {}; obj.Panels(ap).cfg = obj.readCfg();
            end
            obj.requestRefresh();
        end

        function clearActivePanel(obj)
            if isempty(obj.Panels), return; end
            obj.Panels(obj.ActivePanel).overlays = {};
            obj.requestRefresh();
        end

        function freezeActivePanel(obj)
            %FREEZEACTIVEPANEL  Freezing is a pure snapshot: the panel keeps EXACTLY
            %   what it shows (data + axes/zoom) and is skipped by later redraws, so
            %   neither it nor the other panels are replotted. Unfreezing makes it
            %   live again and redraws just that panel.
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
                obj.Panels(ap).mask = obj.LastMask & obj.groupMaskFor(obj.LastD);
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
            %REFRESHFROZENTITLE  Re-title panel i in place (add/remove frozen mark) without replotting.
            if i < 1 || i > numel(obj.Panels), return; end
            P = obj.Panels(i);
            if isempty(P.ax) || ~isvalid(P.ax), return; end
            obj.finishPanel(P.ax, i, P);
        end

        function onPanelDD(obj)
            v = str2double(obj.PanelDD.Value);
            if isfinite(v), obj.ActivePanel = min(max(1, v), numel(obj.Panels)); end
            obj.syncFreezeBtn(); obj.loadControlsFromActive(); obj.requestRefresh();
        end

        function onAnimal(obj)
            a = obj.AnimalDD.Value;
            pitems = obj.penItems(a);
            obj.PenDD.Items = pitems; obj.PenDD.Value = pitems{1};
            obj.TaskLB.Items = obj.taskItems(a, obj.penVal(pitems{1}));
            obj.TaskLB.Value = '(all tasks)';
            obj.applyToActive();
        end

        function onPen(obj)
            obj.TaskLB.Items = obj.taskItems(obj.AnimalDD.Value, obj.penVal(obj.PenDD.Value));
            obj.TaskLB.Value = '(all tasks)';
            obj.applyToActive();
        end

        function applyToActive(obj)
            if isempty(obj.Panels), return; end
            obj.Panels(obj.ActivePanel).cfg = obj.readCfg();
            obj.requestRefresh();
        end

        function onPanelClick(obj, i, ax, e)
            if i < 1 || i > numel(obj.Panels), return; end
            P = obj.Panels(i);
            if isempty(P.pidx), return; end
            try, pt = e.IntersectionPoint(1:2); catch, return; end %#ok<CTCH>
            u = viz.plots.V01util.nearestUnit(ax, P.px, P.py, P.pidx, pt);
            if ~isfinite(u), return; end
            obj.SelectedUnit = u;
            for j = 1:numel(obj.Panels)        % ring it in every panel that shows it
                Pj = obj.Panels(j);
                viz.plots.V01util.ringUnit(Pj.ax, Pj.px, Pj.py, Pj.pidx, u, sprintf('#%d', u));
            end
            obj.showPickedUnit(u);
            obj.inspectPick(u);                 % open/update the unit-inspector popup
            obj.trackPick(u);                   % ring across every plot if tracking
        end

        function openCounts(obj)
            if isempty(obj.Counts) || ~isvalid(obj.Counts.Fig)
                obj.Counts = viz.plots.UnitCountsWindow(obj.LastD);
            end
            obj.Counts.show(obj.LastD, obj.countsPanels());
        end

        function panels = countsPanels(obj)
            panels = struct('label',{},'idx',{});
            for i = 1:numel(obj.Panels)
                if obj.Panels(i).type == 1, t = 'ch'; else, t = 'lay'; end
                % unique row indices: overlapping overlays draw a row twice, but it is
                % ONE observation (obs counts distinct rows incl. laser-power repeats).
                panels(end+1) = struct('label', sprintf('P%d:%s', i, t), 'idx', unique(obj.Panels(i).pidx(:))); %#ok<AGROW>
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
            if isempty(obj.ParamKeys), obj.ParamKeys = names(strcmp(types, 'numeric')); end
        end

        function items = animalItems(obj)
            D = obj.Viz.D;
            if isfield(D, 'Animal')
                a = unique(string(D.Animal(:)), 'stable'); a(ismissing(a) | a == "") = []; items = cellstr(a(:)');
            elseif isfield(D, 'Dataset')
                u = unique(double(D.Dataset(:))); u = u(isfinite(u)); items = arrayfun(@num2str, u(:)', 'UniformOutput', false);
            else
                items = {};
            end
            items = [{'(all)'}, items];
        end

        function items = penItems(obj, animal)
            D = obj.Viz.D; m = obj.animalMask(D, animal);
            if isfield(D, 'Penetration')
                p = unique(double(D.Penetration(m))); p = p(isfinite(p)); items = arrayfun(@num2str, p(:)', 'UniformOutput', false);
            else
                items = {};
            end
            items = [{'(all)'}, items];
        end

        function items = taskItems(obj, animal, pen)
            D = obj.Viz.D; m = obj.animalMask(D, animal);
            if isfield(D, 'Penetration') && ~isnan(pen), m = m & (double(D.Penetration(:)) == pen); end
            tk = {};
            if isfield(D, 'Tasknumb')
                t = unique(string(D.Tasknumb(m)), 'stable'); t(ismissing(t) | t == "") = []; tk = cellstr(t(:)');
            end
            items = [{'(all tasks)'}, tk];
        end

        function m = animalMask(obj, D, animal)
            N = obj.Viz.N;
            if strcmp(char(string(animal)), '(all)'), m = true(N,1); return; end
            if isfield(D, 'Animal'),       m = (string(D.Animal(:)) == string(animal));
            elseif isfield(D, 'Dataset'),  m = (double(D.Dataset(:)) == str2double(string(animal)));
            else,                          m = true(N, 1);
            end
        end

        function p = penVal(~, s)
            if strcmp(char(string(s)), '(all)'), p = NaN; else, p = str2double(string(s)); end
        end

        % ----- control <-> cfg -------------------------------------------- %
        function cfg = defaultCfg(obj)
            cfg = struct('animal','(all)', 'pen','(all)', 'tasks',{{}}, 'param',obj.DFRN_LABEL, 'xlim','', 'ylim','');
        end

        function cfg = readCfg(obj)
            cfg.animal = obj.AnimalDD.Value;
            cfg.pen    = obj.PenDD.Value;
            v = obj.TaskLB.Value; if ischar(v), v = {v}; elseif isstring(v), v = cellstr(v); end
            if isempty(v) || any(strcmp(v, '(all tasks)')), cfg.tasks = {}; else, cfg.tasks = v(:)'; end
            cfg.param = obj.ParamDD.Value;
            cfg.xlim  = obj.XLimField.Value;
            cfg.ylim  = obj.YLimField.Value;
        end

        function loadControlsFromActive(obj)
            if isempty(obj.Panels), return; end
            cfg = obj.normalizeCfg(obj.Panels(obj.ActivePanel).cfg);
            obj.setCtrl(obj.AnimalDD, char(string(cfg.animal)));
            obj.PenDD.Items = obj.penItems(cfg.animal);
            obj.setCtrl(obj.PenDD, char(string(cfg.pen)));
            obj.TaskLB.Items = obj.taskItems(cfg.animal, obj.penVal(cfg.pen));
            if isempty(cfg.tasks)
                obj.TaskLB.Value = '(all tasks)';
            else
                valid = cfg.tasks(ismember(cfg.tasks, obj.TaskLB.Items));
                if isempty(valid), obj.TaskLB.Value = '(all tasks)'; else, obj.TaskLB.Value = valid; end
            end
            obj.setCtrl(obj.ParamDD, cfg.param);
            obj.XLimField.Value = char(string(cfg.xlim));
            obj.YLimField.Value = char(string(cfg.ylim));
        end

        function c = normalizeCfg(obj, c)
            if ~isstruct(c), c = struct(); end
            if ~isfield(c,'animal') || isempty(c.animal), c.animal = '(all)'; end
            if ~isfield(c,'pen')    || isempty(c.pen),    c.pen    = '(all)'; end
            if ~isfield(c,'tasks')  || ~iscell(c.tasks),  c.tasks  = {}; end
            if ~isfield(c,'param')  || isempty(c.param),  c.param  = obj.DFRN_LABEL; end
            if ~isfield(c,'xlim'),  c.xlim = ''; end
            if ~isfield(c,'ylim'),  c.ylim = ''; end
        end

        function tf = holdOn(obj),    tf = ~isempty(obj.HoldChk) && isvalid(obj.HoldChk) && obj.HoldChk.Value; end
        function tf = flipDepth(obj), tf = ~isempty(obj.FlipYChk) && isvalid(obj.FlipYChk) && obj.FlipYChk.Value; end

        % ----- panel management ------------------------------------------- %
        function createPanel(obj, type, cfg)
            p.ax = uiaxes(obj.PanelGrid);
            p.type = type; p.cfg = obj.normalizeCfg(cfg);
            p.overlays = {}; p.frozen = false; p.mask = [];
            p.px = []; p.py = []; p.pidx = [];
            obj.Panels(end+1) = p;
        end

        function rebuildPanels(obj, panels)
            for i = 1:numel(obj.Panels), try, delete(obj.Panels(i).ax); catch, end, end %#ok<CTCH>
            obj.Panels = struct('ax',{},'type',{},'cfg',{},'overlays',{},'frozen',{},'mask',{},'px',{},'py',{},'pidx',{});
            if iscell(panels)
                for i = 1:numel(panels)
                    e = panels{i};
                    if ~isstruct(e), continue; end
                    ty = 1; if isfield(e,'type') && ~isempty(e.type), ty = e.type; end
                    cf = obj.defaultCfg(); if isfield(e,'cfg'), cf = obj.normalizeCfg(e.cfg); end
                    obj.createPanel(ty, cf);
                    if isfield(e,'overlays') && iscell(e.overlays)
                        obj.Panels(end).overlays = cellfun(@(c) obj.normalizeCfg(c), e.overlays, 'UniformOutput', false);
                    end
                    if isfield(e,'frozen') && logical(e.frozen) && isfield(e,'mask') && numel(e.mask)==obj.Viz.N
                        obj.Panels(end).frozen = true; obj.Panels(end).mask = logical(e.mask(:));
                    end
                end
            end
            if isempty(obj.Panels), obj.createPanel(1, obj.defaultCfg()); obj.createPanel(2, obj.defaultCfg()); end
            obj.ActivePanel = 1; obj.relayoutPanels();
        end

        function relayoutPanels(obj)
            P = numel(obj.Panels); if P == 0, return; end
            cols = min(P, 2); rows = ceil(P / cols);
            obj.PanelGrid.RowHeight = repmat({'1x'}, 1, rows);
            obj.PanelGrid.ColumnWidth = repmat({'1x'}, 1, cols);
            for i = 1:P
                r = ceil(i / cols); c = i - (r-1)*cols;
                obj.Panels(i).ax.Layout.Row = r; obj.Panels(i).ax.Layout.Column = c;
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
            obj.statusLbl.Text = sprintf(['%d panel(s). Add makes the chosen plot type; Animal/Pen pick what ' ...
                'a panel shows. Click near a point to ring it; "Unit counts" tabulates per panel.'], numel(obj.Panels));
        end

        function showPickedUnit(obj, u)
            if isempty(obj.statusLbl) || ~isvalid(obj.statusLbl), return; end
            D = obj.LastD; uu = NaN; extra = '';
            if isfield(D,'U_unity'), uu = double(D.U_unity(u)); end
            if isfield(D,'LG'), extra = sprintf('  LG=%s', char(string(D.LG(u)))); end
            obj.statusLbl.Text = sprintf('picked unit #%d  (U_unity %g)%s', u, uu, extra);
        end

        % ----- selection + drawing ---------------------------------------- %
        function m = cfgMask(obj, D, drawMask, cfg)
            cfg = obj.normalizeCfg(cfg);
            m = drawMask(:) & obj.animalMask(D, cfg.animal);
            pv = obj.penVal(cfg.pen);
            if isfield(D,'Penetration') && ~isnan(pv), m = m & (double(D.Penetration(:)) == pv); end
            if isfield(D,'Tasknumb') && ~isempty(cfg.tasks), m = m & ismember(string(D.Tasknumb(:)), string(cfg.tasks)); end
        end

        function drawPanel(obj, i, D, drawMask)
            P = obj.Panels(i); ax = P.ax; cla(ax, 'reset'); grid(ax,'on'); box(ax,'on');
            ax.ButtonDownFcn = @(s,e) obj.onPanelClick(i, s, e);
            obj.Panels(i).px = []; obj.Panels(i).py = []; obj.Panels(i).pidx = [];
            dMask = drawMask;
            if P.frozen && numel(P.mask) == numel(drawMask), dMask = logical(P.mask(:)); end
            if P.type == 1
                [px, py, pidx] = obj.drawPenPanel(ax, D, dMask, P);
            else
                [px, py, pidx] = obj.drawLayerPanel(ax, D, dMask, P);
            end
            obj.Panels(i).px = px; obj.Panels(i).py = py; obj.Panels(i).pidx = pidx;
            obj.registerRing(ax, px, py, pidx);   % track unit across plots

            cfg = obj.normalizeCfg(P.cfg);
            xl = obj.parseLimStr(cfg.xlim); if ~isempty(xl), xlim(ax, xl); end
            yl = obj.parseLimStr(cfg.ylim); if ~isempty(yl), ylim(ax, yl); end
            if P.type == 1
                if obj.flipDepth(), ax.YDir = 'reverse'; else, ax.YDir = 'normal'; end
            else
                if obj.flipDepth(), ax.XDir = 'reverse'; else, ax.XDir = 'normal'; end
            end
            if isfinite(obj.SelectedUnit)
                viz.plots.V01util.ringUnit(ax, px, py, pidx, obj.SelectedUnit, sprintf('#%d', obj.SelectedUnit));
            end
            obj.drawOverlayLegend(ax, P);
            obj.finishPanel(ax, i, P);
        end

        function [px, py, pidx] = drawPenPanel(obj, ax, D, dMask, P)
            px = []; py = []; pidx = [];
            xlabel(ax, 'Penetration (session)'); ylabel(ax, 'Channel');
            if ~isfield(D, 'ch'), return; end
            N = viz.plots.V01util.nU(D);
            ch  = viz.plots.V01util.colv(D, 'ch', N);
            dFr = viz.plots.V01util.colv(D, 'Delta_Fr', N);
            ds  = viz.plots.V01util.colv(D, 'Dataset', N);
            pen = viz.plots.V01util.colv(D, 'Penetration', N);
            layer = viz.plots.V01util.layerNum(D);
            sk = ds*1000 + pen;
            jit = obj.jitterScale(); key = obj.ColorByDD.Value;
            layers = [{P.cfg}, P.overlays];
            sel = cell(1, numel(layers)); uni = [];
            for li = 1:numel(layers)
                m = obj.cfgMask(D, dMask, layers{li}) & isfinite(ch) & isfinite(sk);
                sel{li} = find(m); uni = [uni; sel{li}]; %#ok<AGROW>
            end
            uni = unique(uni);
            if isempty(uni), return; end
            sess = unique(sk(uni)); nS = numel(sess);
            allSess = isfinite(ch) & isfinite(sk);
            markers = [{'o'}, obj.OV_MARKERS];
            hold(ax, 'on');
            lpx = []; lpy = []; lpsess = [];   % live-layer points only (for the median line)
            for li = 1:numel(layers)
                u = sel{li}; if isempty(u), continue; end
                mk = markers{min(li, numel(markers))};
                [~, colIdx] = ismember(sk(u), sess);
                xj = colIdx - jit * dFr(u); bad = ~isfinite(xj); xj(bad) = colIdx(bad);
                [ci, pal] = viz.plots.V01util.colorBy(D, u, key);
                scatter(ax, xj, ch(u), obj.MARKER_SZ, pal(ci, :), 'filled', 'Marker', mk, ...
                    'MarkerFaceAlpha', 0.10, 'MarkerEdgeColor', 'flat', 'LineWidth', 0.5, 'PickableParts', 'none');
                px = [px; xj]; py = [py; ch(u)]; pidx = [pidx; u(:)]; %#ok<AGROW>
                if li == 1, lpx = xj; lpy = ch(u); lpsess = colIdx(:); end
            end
            for s = 1:nS
                memAll = find(allSess & sk == sess(s));
                ymax = max(ch(memAll)); if ~isfinite(ymax), ymax = 0; end
                plot(ax, [s s], [0 ymax], 'Color', [0.1 0.1 0.1 0.2], 'PickableParts', 'none');
                [bc, bl] = obj.borderChannels(layer(memAll), ch(memAll));
                for b = 1:numel(bc)
                    if bl(b) == 3, lc = [1 0 0]; else, lc = [0 0 0]; end
                    plot(ax, [s-0.25 s+0.25], [bc(b) bc(b)], '-', 'Color', lc, 'LineWidth', 1, 'PickableParts', 'none');
                end
            end
            if obj.MedianChk.Value && ~isempty(lpx)    % per-penetration median of x at each channel (live layer only)
                span = obj.smoothSpan();
                for s = 1:nS
                    k = find(lpsess == s); if isempty(k), continue; end
                    cc = lpy(k); xx = lpx(k); uch = unique(cc);
                    med = arrayfun(@(c) median(xx(cc == c), 'omitnan'), uch);
                    if span >= 2, med = movmedian(med, span, 'omitnan'); end
                    plot(ax, med, uch, '-', 'Color', [0 0 0], 'LineWidth', 1.0, 'PickableParts', 'none');
                end
            end
            xlim(ax, [0.5 nS+0.5]); ax.XTick = 1:nS; ax.XTickLabel = obj.sessionLabels(D, sess); ax.XTickLabelRotation = 45;
            hold(ax, 'off');
        end

        function [px, py, pidx] = drawLayerPanel(obj, ax, D, dMask, P)
            px = []; py = []; pidx = [];
            xlabel(ax, 'Layers'); ylabel(ax, obj.layerYLabel(P.cfg));
            N = viz.plots.V01util.nU(D);
            layer = viz.plots.V01util.layerNum(D);
            key = obj.ColorByDD.Value;
            layers = [{P.cfg}, P.overlays];
            markers = [{'o'}, obj.OV_MARKERS];
            hold(ax, 'on');
            zl = yline(ax, 0, '-', 'Color', [0.82 0.82 0.82]); zl.PickableParts = 'none';
            for li = 1:numel(layers)
                cfg = obj.normalizeCfg(layers{li});
                yv = obj.layerY(D, cfg.param, N);
                u = find(obj.cfgMask(D, dMask, cfg) & isfinite(yv) & isfinite(layer));
                if isempty(u), continue; end
                mk = markers{min(li, numel(markers))};
                [ci, pal, clabels, ccounts] = viz.plots.V01util.colorBy(D, u, key);
                Lv = layer(u); yvv = yv(u); nC = size(pal, 1);
                for L = 1:4
                    for c = 1:nC
                        mm = (Lv == L) & (ci == c);
                        if ~any(mm), continue; end
                        xj = L + 0.1 * randn(sum(mm), 1);
                        scatter(ax, xj, yvv(mm), obj.MARKER_SZ, pal(c, :), 'filled', 'Marker', mk, ...
                            'MarkerFaceAlpha', 0.10, 'MarkerEdgeColor', pal(c, :), 'LineWidth', 0.5, 'PickableParts', 'none');
                        px = [px; xj]; py = [py; yvv(mm)]; pidx = [pidx; u(mm)]; %#ok<AGROW>
                        if li == 1 && c < nC
                            mu = mean(yvv(mm), 'omitnan');
                            plot(ax, [L-0.25 L+0.25], [mu mu], '-', 'Color', pal(c, :), 'LineWidth', 1.4, 'PickableParts', 'none');
                        end
                    end
                end
                if li == 1 && ~strcmpi(key, 'Layer')
                    yc = 0.98;
                    for k = 1:numel(clabels)
                        if ccounts(k) == 0, continue; end
                        text(ax, 0.02, yc, sprintf('%s (%d)', clabels{k}, ccounts(k)), 'Units','normalized', ...
                            'HorizontalAlignment','left', 'VerticalAlignment','top', 'FontSize',7, 'Interpreter','none', ...
                            'FontWeight','bold', 'Color', pal(k,:), 'PickableParts','none');
                        yc = yc - 0.055;
                    end
                end
            end
            xlim(ax, [0.5 4.5]); ax.XTick = 1:4; ax.XTickLabel = obj.LAYER_NAMES; ax.XTickLabelRotation = 0;
            hold(ax, 'off');
        end

        function drawOverlayLegend(obj, ax, P)
            if isempty(P.overlays), return; end
            lines = {sprintf('live(o): %s', obj.shortCfg(P.cfg))};
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
            s = sprintf('%s/P%s/%s', char(string(cfg.animal)), char(string(cfg.pen)), tstr);
        end

        function v = layerY(obj, D, param, N)
            if nargin < 4 || isempty(N), N = viz.plots.V01util.nU(D); end
            if strcmp(param, obj.DFRN_LABEL)
                if isfield(D, 'Delta_FR_N') && ~isempty(D.Delta_FR_N)
                    v = viz.plots.V01util.colv(D, 'Delta_FR_N', N);
                else
                    dE = viz.plots.V01util.colv(D, 'Delta_Fr', N);
                    dI = viz.plots.V01util.colv(D, 'Delta_Fr_I', N);
                    v = dE; pos = dE > 0; v(pos) = dI(pos);
                end
            else
                v = viz.plots.V01util.colv(D, param, N);
            end
        end

        function s = layerYLabel(obj, cfg)
            cfg = obj.normalizeCfg(cfg);
            if strcmp(cfg.param, obj.DFRN_LABEL), s = 'Delta Fr (sign-based)'; else, s = cfg.param; end
        end

        function [bc, bl] = borderChannels(~, layer, ch)
            bc = []; bl = [];
            for L = 1:3
                gA = ch(layer == L); gB = ch(layer == L+1);
                if isempty(gA) || isempty(gB), continue; end
                if median(gA) > median(gB), b = (min(gA) + max(gB)) / 2; else, b = (max(gA) + min(gB)) / 2; end
                bc(end+1) = b; bl(end+1) = L; %#ok<AGROW>
            end
        end

        function lbls = sessionLabels(~, D, sess)
            lbls = cell(1, numel(sess));
            hasA = isfield(D, 'Animal') && isfield(D, 'Dataset');
            if hasA, dsAll = double(D.Dataset(:)); aStr = string(D.Animal(:)); end
            for s = 1:numel(sess)
                ds = floor(sess(s)/1000); pen = sess(s) - ds*1000; an = num2str(ds);
                if hasA
                    k = find(dsAll == ds & ~ismissing(aStr), 1);
                    if ~isempty(k), an = char(aStr(k)); end
                end
                lbls{s} = sprintf('%s P%g', an, pen);
            end
        end

        function lim = parseLimStr(~, s)
            lim = [];
            s = strtrim(char(string(s)));
            if isempty(s), return; end
            v = sscanf(regexprep(s, '[\[\],]', ' '), '%g');
            if numel(v) >= 2 && isfinite(v(1)) && isfinite(v(2)) && v(1) < v(2), lim = [v(1) v(2)]; end
        end

        function gm = groupMaskFor(obj, D)
            N = obj.Viz.N; gm = true(N,1);
            if isempty(obj.GroupDD) || ~isvalid(obj.GroupDD), return; end
            g = obj.GroupDD.Value;
            if strcmpi(g, 'ALL_UNITS'), return; end
            try, gm = logical(analysis.tuningGroupMask(D, g)); catch, gm = true(N,1); end %#ok<CTCH>
            gm = gm(:);
        end

        function j = jitterScale(obj)
            j = 0.3;
            if ~isempty(obj.JitterField) && isvalid(obj.JitterField)
                v = obj.JitterField.Value; if isnumeric(v) && isscalar(v) && isfinite(v), j = max(0, v); end
            end
        end

        function n = smoothSpan(obj)
            n = 0;
            if isempty(obj.SmoothField) || ~isvalid(obj.SmoothField), return; end
            v = obj.SmoothField.Value; if isnumeric(v) && isscalar(v) && isfinite(v), n = max(0, round(v)); end
        end

        function k = drawKey(obj, drawMask)
            s = struct();
            s.group = obj.GroupDD.Value; s.color = obj.ColorByDD.Value;
            s.jit = obj.jitterScale(); s.med = obj.MedianChk.Value; s.flip = obj.flipDepth(); s.sm = obj.SmoothField.Value;
            s.active = obj.ActivePanel; s.np = numel(obj.Panels);
            ps = cell(1, numel(obj.Panels));
            for i = 1:numel(obj.Panels)
                P = obj.Panels(i);
                ov = cellfun(@(c) obj.cfgStr(c), P.overlays, 'UniformOutput', false);
                fm = ''; if P.frozen, fm = sprintf('F%d:%d', nnz(P.mask), mod(sum(find(P.mask)), 1e9)); end
                ps{i} = sprintf('t%d|%s|%s|%s', P.type, obj.cfgStr(P.cfg), strjoin(ov, ';'), fm);
            end
            s.panels = strjoin(ps, '##');
            s.mask = sprintf('%d:%d', nnz(drawMask), mod(sum(find(drawMask)), 1e9));
            k = jsonencode(s);
        end

        function s = cfgStr(obj, cfg)
            cfg = obj.normalizeCfg(cfg);
            s = sprintf('%s|%s|%s|%s|%s|%s', char(string(cfg.animal)), char(string(cfg.pen)), ...
                strjoin(cfg.tasks, ','), char(string(cfg.param)), char(string(cfg.xlim)), char(string(cfg.ylim)));
        end

        function finishPanel(obj, ax, i, P)
            cfg = obj.normalizeCfg(P.cfg);
            if P.type == 1, tname = 'ch-vs-pen'; else, tname = [obj.layerYLabel(cfg) '-vs-layer']; end
            extra = sprintf('%s \x00b7 %s', tname, obj.shortCfg(cfg));
            mark = ''; col = [0 0 0];
            if i == obj.ActivePanel, mark = '  \x25cf active'; col = [0 0 0.65]; end
            if P.frozen, mark = [mark '  \x2744 frozen']; col = [0 0.45 0.74]; end
            title(ax, sprintf(['P%d \x2014 %s' mark], i, extra), 'Color', col, 'Interpreter', 'none');
        end
    end
end

% ----------------------------------------------------------------------- %
function h = lab(g, row, txt)
%LAB  A left-aligned label placed on row ROW of grid G.
    h = uilabel(g, 'Text', txt);
    h.Layout.Row = row; h.Layout.Column = 1;
end
