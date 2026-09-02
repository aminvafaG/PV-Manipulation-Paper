classdef TuningTab < viz.PlotTab
%TUNINGTAB  Configurable multi-panel tuning viewer.
%
%   A flexible page for overlaying any of the tuning curves produced by
%   analysis.computeMetrics (raw fits, center-shifted fits, the normalized
%   variants, the delta and ratio curves, the delta derivatives, ...) and for
%   comparing several plots side by side.
%
%   For each plot panel you choose:
%     * one or more CURVE TYPES to overlay (multi-select list), e.g. the
%       center-shifted control + laser, plus the delta and ratio curves;
%     * a MODE:
%         Single unit        - the curve(s) for the current unit (unit slider);
%         Population mean     - the mean curve(s) over the filtered units;
%         Population singles  - every filtered unit's curve(s), overlaid faint;
%     * an optional GROUP-BY variable (e.g. layer group LG, EI, G_type): in the
%       population modes the units are split by that variable and drawn per group
%       (mean = one styled line per group; singles = colored by group).
%
%   PLOTTING.  Pick curves + mode, then either move the unit slider (single
%   mode) or click "Plot -> active panel". By default each new plot REPLACES the
%   active panel. Tick "Hold" to OVERLAY instead, stacking plots on top of each
%   other (e.g. several single units, or different curve sets, to compare). In
%   single mode the slider replots the new unit automatically -- replace when
%   Hold is off, overlay (keeping the previous units) when Hold is on. "Clear"
%   wipes the active panel.
%
%   PANELS.  Start with one (empty) panel; "Add" creates more, "Remove" drops
%   the active one, and the "Active panel" dropdown picks which panel the
%   controls target. Each stacked layer is drawn with its own line style and a
%   legend tag (e.g. "#2·u10") so overlaid curves stay legible.
%
%   FREEZE.  Select a panel as active and click "Freeze" to PIN it to the filter
%   it currently shows: later filter changes redraw the other (live) panels but
%   leave the frozen one untouched, so you can compare one filtered set against
%   another side by side. Click "Unfreeze" to let it follow the live filter
%   again. Frozen panels are marked "❄ frozen" in their title.
%
%   See also: viz.PlotTab, analysis.computeMetrics, filter.filterableVars

    properties
        % controls
        CurveLB         % multi-select list of curve types
        ModeDD          % single | popmean | popsingles
        GroupDD         % group-by variable (population modes)
        UnitSlider      % steps through masked units (single mode)
        UnitLabel
        HoldChk         % keep previous plots (overlay) instead of replacing
        PanelDD         % active-panel selector
        FreezeBtn       % toggle freeze on the active panel

        % curve registry (aligned cellstr/char)
        CurveKeys   = {}    % D field names
        CurveLabels = {}    % friendly labels

        % plot panels
        PanelGrid           % uigridlayout holding the panel axes
        Panels  = struct('ax',{},'layers',{},'frozen',{},'mask',{})  % .ax .layers .frozen .mask
        ActivePanel = 0
        CurUnit = NaN       % last unit drawn (frozen into single-mode layers on Plot)
        LastIdx = []        % find(mask) from the last update (slider -> unit mapping)
        LastMask = []       % last filter mask (captured into a panel when frozen)
    end

    properties (Constant)
        Modes      = {'Single unit','Population mean','Population singles'}
        ModeKeys   = {'single','popmean','popsingles'}
        MaxPanels  = 6
    end

    methods
        function obj = TuningTab()
            obj@viz.PlotTab('Tuning');
        end

        % ================================================================= %
        function buildControls(obj, parent)
            obj.buildRegistry();

            g = uigridlayout(parent, [15 1]);
            g.RowHeight = {18, 150, 18, 26, 18, 26, 18, 34, 22, 22, 28, 18, 26, 28, '1x'};
            g.RowSpacing = 4; g.Padding = [8 8 8 8];

            lab(g, 1, 'Curves (multi-select)');
            if isempty(obj.CurveLabels)
                obj.CurveLB = uilistbox(g, 'Items', {'(no tuning curves)'}, 'Enable','off');
            else
                def = obj.defaultCurveSelection();
                obj.CurveLB = uilistbox(g, 'Items', obj.CurveLabels, ...
                    'Multiselect', 'on', 'Value', def);
            end
            obj.CurveLB.Layout.Row = 2;

            lab(g, 3, 'Mode');
            obj.ModeDD = uidropdown(g, 'Items', obj.Modes, 'ItemsData', obj.ModeKeys, ...
                'Value', 'single');
            obj.ModeDD.Layout.Row = 4;

            lab(g, 5, 'Group by (population)');
            obj.GroupDD = uidropdown(g, 'Items', obj.buildGroupVars(), 'Value', '(none)');
            obj.GroupDD.Layout.Row = 6;

            lab(g, 7, 'Unit (within filter)');
            obj.UnitSlider = uislider(g, 'Limits', [1 2], 'Value', 1, ...
                'ValueChangedFcn', @(s,e) obj.onUnitSlider());
            obj.UnitSlider.Layout.Row = 8;
            sb = uigridlayout(g, [1 2], 'Padding',[0 0 0 0], 'ColumnSpacing',4);
            sb.Layout.Row = 9;
            uibutton(sb, 'Text','−', 'ButtonPushedFcn', @(s,e) obj.nudgeUnit(-1));
            uibutton(sb, 'Text','+', 'ButtonPushedFcn', @(s,e) obj.nudgeUnit(+1));
            ug = uigridlayout(g, [1 2], 'Padding',[0 0 0 0], 'ColumnSpacing',4);
            ug.Layout.Row = 10; ug.ColumnWidth = {'1x', 96};
            obj.UnitLabel = uilabel(ug, 'Text', 'unit: -');
            obj.HoldChk = uicheckbox(ug, 'Text', 'Hold', 'Value', false, ...
                'Tooltip', 'Keep previous plots (overlay) when the slider or Plot changes, instead of replacing');

            pg = uigridlayout(g, [1 2], 'Padding',[0 0 0 0], 'ColumnSpacing',4);
            pg.Layout.Row = 11; pg.ColumnWidth = {'1x', 70};
            uibutton(pg, 'Text', 'Plot → active panel', 'FontWeight','bold', ...
                'ButtonPushedFcn', @(s,e) obj.plotToActive());
            uibutton(pg, 'Text', 'Clear', ...
                'ButtonPushedFcn', @(s,e) obj.clearActivePanel());

            lab(g, 12, 'Active panel');
            obj.PanelDD = uidropdown(g, 'Items', {'1'}, 'Value', '1', ...
                'ValueChangedFcn', @(s,e) obj.onPanelDD());
            obj.PanelDD.Layout.Row = 13;

            ag = uigridlayout(g, [1 3], 'Padding',[0 0 0 0], 'ColumnSpacing',4);
            ag.Layout.Row = 14;
            uibutton(ag, 'Text', 'Add',    'ButtonPushedFcn', @(s,e) obj.addPanel());
            obj.FreezeBtn = uibutton(ag, 'Text', 'Freeze', 'ButtonPushedFcn', @(s,e) obj.freezeActivePanel());
            uibutton(ag, 'Text', 'Remove', 'ButtonPushedFcn', @(s,e) obj.removeActivePanel());
            obj.addDataSelectors(g);
        end

        function buildView(obj, parent)
            obj.PanelGrid = uigridlayout(parent, [1 1]);
            obj.PanelGrid.Padding = [4 4 4 4];
            obj.PanelGrid.RowSpacing = 6; obj.PanelGrid.ColumnSpacing = 6;
            obj.Panels = struct('ax',{},'layers',{},'frozen',{},'mask',{});
            obj.createPanel();                        % first (empty) panel
            obj.ActivePanel = 1;
            obj.relayoutPanels();
            obj.refreshPanelDD();
            obj.syncFreezeBtn();
        end

        % ================================================================= %
        function update(obj, D, mask)
            idx = find(mask);
            obj.LastIdx = idx;
            obj.LastMask = mask;
            obj.setSliderRange(numel(idx));
            if isempty(idx)
                unit = NaN; obj.UnitLabel.Text = 'unit: -';
            else
                k = min(max(round(obj.UnitSlider.Value), 1), numel(idx));
                unit = idx(k);
                obj.UnitLabel.Text = sprintf('unit: %d  (%d/%d)', unit, k, numel(idx));
            end
            obj.CurUnit = unit;
            for i = 1:numel(obj.Panels)
                if obj.Panels(i).frozen && numel(obj.Panels(i).mask) == numel(mask)
                    obj.drawPanel(i, D, obj.Panels(i).mask, unit);   % pinned filter
                else
                    obj.drawPanel(i, D, mask, unit);
                end
            end
        end

        % ----- persistence ------------------------------------------------ %
        function s = getControlState(obj)
            s = struct();
            s.unit  = obj.UnitSlider.Value;
            s.sel   = obj.curveSelection();
            s.mode  = obj.ModeDD.Value;
            s.group = obj.GroupDD.Value;
            s.hold  = obj.HoldChk.Value;
            s.active = obj.ActivePanel;
            panels = cell(1, numel(obj.Panels));
            for i = 1:numel(obj.Panels)
                panels{i} = struct('layers', {obj.Panels(i).layers}, ...
                                   'frozen', obj.Panels(i).frozen, ...
                                   'mask',   obj.Panels(i).mask);
            end
            s.panels = panels;
        end

        function setControlState(obj, s)
            if isfield(s,'sel'),   obj.setCurveSelection(s.sel);  end
            if isfield(s,'mode'),  obj.setCtrl(obj.ModeDD,  s.mode);  end
            if isfield(s,'group'), obj.setCtrl(obj.GroupDD, s.group); end
            if isfield(s,'hold') && ~isempty(obj.HoldChk), obj.HoldChk.Value = logical(s.hold); end
            if isfield(s,'panels') && ~isempty(s.panels)
                obj.rebuildPanels(s.panels);
            end
            if isfield(s,'active') && ~isempty(obj.Panels)
                obj.ActivePanel = min(max(1, round(s.active)), numel(obj.Panels));
            end
            obj.refreshPanelDD();
            obj.syncFreezeBtn();
            if isfield(s,'unit'), obj.setCtrl(obj.UnitSlider, s.unit); end
        end
    end

    % ===================================================================== %
    %  Panel actions (wired to the buttons; public so they can be scripted)
    % ===================================================================== %
    methods
        function addPanel(obj)
            %ADDPANEL  Add a new (empty) plot panel and make it active.
            if numel(obj.Panels) >= obj.MaxPanels
                uialert(obj.Viz.Fig, sprintf('At most %d panels.', obj.MaxPanels), 'Tuning');
                return;
            end
            obj.createPanel();
            obj.ActivePanel = numel(obj.Panels);
            obj.relayoutPanels(); obj.refreshPanelDD(); obj.syncFreezeBtn();
            obj.requestRefresh();
        end

        function removeActivePanel(obj)
            %REMOVEACTIVEPANEL  Delete the active panel (always keeps one).
            if numel(obj.Panels) <= 1, return; end
            i = obj.ActivePanel;
            try, delete(obj.Panels(i).ax); catch, end %#ok<CTCH>
            obj.Panels(i) = [];
            obj.ActivePanel = min(i, numel(obj.Panels));
            obj.relayoutPanels(); obj.refreshPanelDD(); obj.syncFreezeBtn();
            obj.requestRefresh();
        end

        function freezeActivePanel(obj)
            %FREEZEACTIVEPANEL  Toggle freeze on the active panel. A frozen panel
            %   keeps the filter (mask) it had when frozen, so subsequent filter
            %   changes redraw the other panels but leave this one as a snapshot.
            if isempty(obj.Panels), return; end
            ap = obj.ActivePanel;
            if obj.Panels(ap).frozen
                obj.Panels(ap).frozen = false;
                obj.Panels(ap).mask   = [];
            else
                obj.Panels(ap).frozen = true;
                obj.Panels(ap).mask   = obj.LastMask;   % pin the current filter
            end
            obj.syncFreezeBtn();
            obj.requestRefresh();
        end

        function syncFreezeBtn(obj)
            %SYNCFREEZEBTN  Make the Freeze button reflect the active panel state.
            if isempty(obj.FreezeBtn) || ~isvalid(obj.FreezeBtn), return; end
            if ~isempty(obj.Panels) && obj.ActivePanel >= 1 ...
                    && obj.ActivePanel <= numel(obj.Panels) && obj.Panels(obj.ActivePanel).frozen
                obj.FreezeBtn.Text = 'Unfreeze';
            else
                obj.FreezeBtn.Text = 'Freeze';
            end
        end

        function plotToActive(obj)
            %PLOTTOACTIVE  Plot the current selections onto the active panel.
            %   Hold off REPLACES the panel; Hold on OVERLAYS as a new layer.
            obj.addOrReplaceLayer(obj.currentLayer());
            obj.requestRefresh();
        end

        function onUnitSlider(obj)
            %ONUNITSLIDER  Unit slider moved. In single mode, replot the new unit:
            %   Hold off replaces the active panel; Hold on overlays (keeps the
            %   previously plotted units). Other modes just redraw.
            if strcmp(obj.ModeDD.Value, 'single')
                if obj.holdOn()
                    obj.addOrReplaceLayer(obj.layerForUnit(obj.unitFromSlider()));
                else
                    obj.addOrReplaceLayer(obj.liveLayer());
                end
            end
            obj.requestRefresh();
        end

        function nudgeUnit(obj, step)
            %NUDGEUNIT  Step the unit slider by STEP, then replot (single mode).
            s = obj.UnitSlider;
            if isempty(s) || ~isvalid(s), return; end
            lim = s.Limits;
            s.Value = min(max(s.Value + step, lim(1)), lim(2));
            obj.onUnitSlider();
        end

        function clearActivePanel(obj)
            %CLEARACTIVEPANEL  Remove every plotted layer from the active panel.
            if isempty(obj.Panels), return; end
            obj.Panels(obj.ActivePanel).layers = {};
            obj.requestRefresh();
        end

        function onPanelDD(obj)
            %ONPANELDD  Make the panel chosen in the dropdown the active one.
            v = str2double(obj.PanelDD.Value);
            if isfinite(v), obj.ActivePanel = min(max(1, v), numel(obj.Panels)); end
            obj.syncFreezeBtn();
            obj.requestRefresh();
        end
    end

    % ===================================================================== %
    methods (Access = private)
        % ----- registry + control helpers -------------------------------- %
        function buildRegistry(obj)
            D = obj.Viz.D; N = obj.Viz.N;
            known = { ...
                'fit_mid_NL',      'Control (shifted)'; ...
                'fit_mid_L',       'Laser (shifted)'; ...
                'fit_mid_nc_NL',   'Control (shifted, ctrl-norm)'; ...
                'fit_mid_nc_L',    'Laser (shifted, ctrl-norm)'; ...
                'fit_mid_self_NL', 'Control (shifted, self-norm)'; ...
                'fit_mid_self_L',  'Laser (shifted, self-norm)'; ...
                'Delta_tun',       'Delta (L−NL, shifted)'; ...
                'Delta_tun_nc',    'Delta (normalized)'; ...
                'Ratio_tun',       'Ratio (L/NL, shifted)'; ...
                'LTM_fit_L',       'LTM laser fit (pred)'; ...
                'ExpM_fit',        'Exp model fit (pred target)'; ...
                'fit_NL',          'Control (raw fit)'; ...
                'fit_L',           'Laser (raw fit)'; ...
                'dTun_d1','Delta d1'; 'dTun_d2','Delta d2'; ...
                'dTun_d3','Delta d3'; 'dTun_d4','Delta d4' };
            keys = {}; labels = {};
            for i = 1:size(known,1)
                k = known{i,1};
                if isfield(D,k) && obj.isCurveField(D.(k), N)
                    keys{end+1} = k; labels{end+1} = known{i,2}; %#ok<AGROW>
                end
            end
            fn = fieldnames(D);                 % auto-include any other GxN curve
            for i = 1:numel(fn)
                k = fn{i};
                if ~strcmp(k,'Meta') && ~any(strcmp(keys,k)) && obj.isCurveField(D.(k), N)
                    keys{end+1} = k; labels{end+1} = k; %#ok<AGROW>
                end
            end
            obj.CurveKeys = keys; obj.CurveLabels = labels;
        end

        function tf = isCurveField(~, x, N)
            tf = isnumeric(x) && ismatrix(x) && size(x,2) == N ...
                 && size(x,1) >= 90 && size(x,1) <= 3600;
        end

        function def = defaultCurveSelection(obj)
            % default to control+laser shifted if present, else first one
            want = {'Control (shifted)','Laser (shifted)'};
            def  = obj.CurveLabels(ismember(obj.CurveLabels, want));
            if isempty(def), def = obj.CurveLabels(1); end
        end

        function vars = buildGroupVars(obj)
            [names, types] = filter.filterableVars(obj.Viz.D, obj.Viz.N);
            vars = {'(none)'};
            for i = 1:numel(names)
                t = types{i};
                if any(strcmp(t, {'string','categorical'}))
                    vars{end+1} = names{i}; %#ok<AGROW>
                elseif strcmp(t, 'numeric')
                    v = obj.Viz.D.(names{i}); u = unique(v(isfinite(v)));
                    if numel(u) >= 2 && numel(u) <= 12, vars{end+1} = names{i}; end %#ok<AGROW>
                end
            end
        end

        function sel = curveSelection(obj)
            sel = obj.CurveLB.Value;
            if ischar(sel), sel = {sel}; end
            if isstring(sel), sel = cellstr(sel); end
        end

        function setCurveSelection(obj, sel)
            if isempty(obj.CurveLabels) || isempty(sel), return; end
            if ischar(sel), sel = {sel}; end
            valid = sel(ismember(sel, obj.CurveLB.Items));
            if ~isempty(valid), obj.CurveLB.Value = valid; end
        end

        function keys = selectedKeys(obj)
            keys = obj.CurveKeys(ismember(obj.CurveLabels, obj.curveSelection()));
        end

        function tf = holdOn(obj)
            tf = ~isempty(obj.HoldChk) && isvalid(obj.HoldChk) && obj.HoldChk.Value;
        end

        function addOrReplaceLayer(obj, layer)
            %ADDORREPLACELAYER  Put LAYER on the active panel: overlay it (append)
            %   when Hold is on, otherwise replace whatever is there.
            if isempty(obj.Panels), obj.addPanel(); end
            ap = obj.ActivePanel;
            if obj.holdOn()
                obj.Panels(ap).layers{end+1} = layer;
            else
                obj.Panels(ap).layers = {layer};
            end
        end

        function L = layerForUnit(obj, u)
            %LAYERFORUNIT  A plot-layer snapshot of the current controls, with the
            %   single-mode unit set to U (NaN -> follow the slider live).
            L = struct('curves', {obj.selectedKeys()}, ...
                       'mode',    obj.ModeDD.Value, ...
                       'groupBy', obj.GroupDD.Value, ...
                       'unit',    u);
        end

        function L = liveLayer(obj),    L = obj.layerForUnit(NaN);          end
        function L = currentLayer(obj), L = obj.layerForUnit(obj.CurUnit);  end

        function u = unitFromSlider(obj)
            %UNITFROMSLIDER  Masked-unit index the slider currently points at.
            idx = obj.LastIdx;
            if isempty(idx), u = obj.CurUnit; return; end
            k = min(max(round(obj.UnitSlider.Value), 1), numel(idx));
            u = idx(k);
        end

        % ----- panel management ------------------------------------------ %
        function createPanel(obj, layer)
            p.ax = uiaxes(obj.PanelGrid);
            if nargin < 2 || isempty(layer), p.layers = {}; else, p.layers = {layer}; end
            p.frozen = false;
            p.mask   = [];
            obj.Panels(end+1) = p;
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
            items = arrayfun(@num2str, 1:P, 'UniformOutput', false);
            obj.PanelDD.Items = items;
            obj.PanelDD.Value = num2str(min(max(1, obj.ActivePanel), P));
        end

        function rebuildPanels(obj, panels)
            for i = 1:numel(obj.Panels)
                try, delete(obj.Panels(i).ax); catch, end %#ok<CTCH>
            end
            obj.Panels = struct('ax',{},'layers',{},'frozen',{},'mask',{});
            if iscell(panels)
                for i = 1:numel(panels)
                    obj.createPanel();
                    e = panels{i};
                    if isstruct(e) && isfield(e,'layers')        % current format
                        if iscell(e.layers), obj.Panels(end).layers = e.layers; end
                        if isfield(e,'frozen') && logical(e.frozen) ...
                                && isfield(e,'mask') && numel(e.mask)==obj.Viz.N
                            obj.Panels(end).frozen = true;
                            obj.Panels(end).mask   = logical(e.mask(:));
                        end
                    elseif iscell(e)                             % older: bare layer list
                        obj.Panels(end).layers = e;
                    end
                end
            elseif isstruct(panels)                              % oldest: one cfg per panel
                for i = 1:numel(panels), obj.createPanel(panels(i)); end
            end
            if isempty(obj.Panels), obj.createPanel(); end
            obj.ActivePanel = 1;
            obj.relayoutPanels();
        end

        % ----- drawing ---------------------------------------------------- %
        function drawPanel(obj, i, D, mask, unit)
            ax = obj.Panels(i).ax; cla(ax);
            delete(findall(ax, 'Type', 'line'));   % cla spares HandleVisibility='off'
            isActive = (i == obj.ActivePanel);      %   bundle lines (popsingles) -> nuke them too
            layers = obj.Panels(i).layers;
            xlabel(ax, 'orientation (deg)'); ylabel(ax, 'response'); grid(ax, 'on');
            if isempty(layers)
                obj.finishPanel(ax, i, isActive, '(empty — Plot → active panel)', false);
                return;
            end
            hold(ax, 'on'); Gmax = 1;
            for li = 1:numel(layers)
                Gmax = max(Gmax, obj.drawLayer(ax, layers{li}, li, numel(layers), D, mask, unit));
            end
            hold(ax, 'off');
            xlim(ax, [0 max(1,Gmax)]);
            obj.finishPanel(ax, i, isActive, obj.panelSubtitle(layers), true);
        end

        function gmax = drawLayer(obj, ax, layer, li, nLayers, D, mask, unit)
            %DRAWLAYER  Draw one plotted layer (curve set + mode) into ax. Each
            %   stacked layer gets its own line style so overlaid plots stay
            %   distinguishable; the legend label is tagged with the layer index.
            gmax    = 1;
            keys    = getfield2(layer, 'curves',  {});
            mode    = getfield2(layer, 'mode',    'single');
            groupBy = getfield2(layer, 'groupBy', '(none)');
            lu      = getfield2(layer, 'unit',    NaN);
            if isnan(lu), lu = unit; end            % unfrozen layer follows the slider
            if isempty(keys), return; end
            useGroup = ~strcmp(mode,'single') && ~isempty(groupBy) ...
                       && ~strcmp(groupBy,'(none)') && isfield(D, groupBy);
            if useGroup, [gMasks, gLabels] = obj.groupMasks(D, groupBy, mask); end
            lsty = obj.styleFor(li);
            tag  = '';
            if nLayers > 1
                if strcmp(mode,'single') && ~isnan(lu), tag = sprintf(' #%d·u%d', li, lu);
                else,                                    tag = sprintf(' #%d', li);   end
            end
            for ci = 1:numel(keys)
                key = keys{ci};
                if ~isfield(D, key) || ~obj.isCurveField(D.(key), obj.Viz.N), continue; end
                F = D.(key); xg = 0:size(F,1)-1; gmax = max(gmax, size(F,1)-1);
                base = obj.colorFor(key); lbl = [obj.labelFor(key) tag];
                switch mode
                    case 'single'
                        if ~isnan(lu) && lu >= 1 && lu <= size(F,2)
                            plot(ax, xg, F(:,lu), 'Color', base, 'LineStyle', lsty, ...
                                 'LineWidth', 1.6, 'DisplayName', lbl);
                        end
                    case 'popmean'
                        if ~useGroup
                            plot(ax, xg, mean(F(:,mask),2,'omitnan'), 'Color', base, ...
                                 'LineStyle', lsty, 'LineWidth', 2, 'DisplayName', lbl);
                        else
                            for gi = 1:numel(gLabels)
                                mm = gMasks{gi};
                                if ~any(mm), continue; end
                                plot(ax, xg, mean(F(:,mm),2,'omitnan'), 'Color', base, ...
                                     'LineStyle', obj.styleFor(gi), 'LineWidth', 2, ...
                                     'DisplayName', sprintf('%s · %s', lbl, gLabels{gi}));
                            end
                        end
                    case 'popsingles'
                        if ~useGroup
                            obj.plotBundle(ax, xg, F(:,mask), base);
                            plot(ax, NaN, NaN, 'Color', base, 'LineWidth', 1.5, ...
                                 'DisplayName', [lbl ' (each)']);
                        else
                            for gi = 1:numel(gLabels)
                                mm = gMasks{gi};
                                if ~any(mm), continue; end
                                gcol = obj.groupColor(gi);
                                obj.plotBundle(ax, xg, F(:,mm), gcol);
                                plot(ax, NaN, NaN, 'Color', gcol, 'LineWidth', 1.5, ...
                                     'DisplayName', sprintf('%s · %s', lbl, gLabels{gi}));
                            end
                        end
                end
            end
        end

        function s = panelSubtitle(obj, layers)
            %PANELSUBTITLE  Short panel title summarizing the stacked layers.
            last = layers{end};
            mode = getfield2(last, 'mode', 'single');
            mi = find(strcmp(obj.ModeKeys, mode), 1);
            if isempty(mi), mm = mode; else, mm = obj.Modes{mi}; end
            gb = getfield2(last, 'groupBy', '(none)');
            if ~strcmp(mode,'single') && ~strcmp(gb,'(none)'), mm = sprintf('%s · by %s', mm, gb); end
            if numel(layers) == 1, s = mm; else, s = sprintf('%d plots · %s', numel(layers), mm); end
        end

        function finishPanel(obj, ax, i, isActive, extra, showLegend)
            if showLegend
                lg = legend(ax, 'show'); lg.FontSize = 7;
                lg.Interpreter = 'none'; lg.Location = 'best';
            end
            mark = ''; col = [0 0 0];
            if isActive, mark = '  ● active'; col = [0 0 0.65]; end
            if i >= 1 && i <= numel(obj.Panels) && obj.Panels(i).frozen
                mark = [mark '  ❄ frozen']; col = [0 0.45 0.74];
            end
            title(ax, sprintf('Panel %d — %s%s', i, extra, mark), ...
                  'Color', col, 'Interpreter', 'none');
        end

        function plotBundle(~, ax, xg, M, col)
            %PLOTBUNDLE  All columns of M as one NaN-separated faint line.
            if isempty(M), return; end
            xg = xg(:); L = numel(xg); k = size(M,2);
            xx = nan((L+1)*k, 1); yy = xx;
            for j = 1:k
                r0 = (j-1)*(L+1);
                xx(r0+(1:L)) = xg; yy(r0+(1:L)) = M(:,j);
            end
            faint = col + (1-col)*0.55;        % lighten toward white
            plot(ax, xx, yy, 'Color', faint, 'LineWidth', 0.5, 'HandleVisibility', 'off');
        end

        function [masks, labels] = groupMasks(~, D, var, mask)
            mask = mask(:); v = D.(var);
            if isstring(v) || iscellstr(v) || iscategorical(v)
                vv = string(v(:));
                vals = unique(vv(mask)); vals(ismissing(vals) | vals=="") = [];
                labels = cellstr(vals);
                masks = cell(1, numel(labels));
                for i = 1:numel(labels), masks{i} = mask & (vv == string(labels{i})); end
            else
                vv = double(v(:));
                u = unique(vv(mask & isfinite(vv)));
                labels = cell(1, numel(u)); masks = cell(1, numel(u));
                for i = 1:numel(u)
                    labels{i} = sprintf('%s=%g', var, u(i));
                    masks{i}  = mask & (vv == u(i));
                end
            end
        end

        function setSliderRange(obj, n)
            obj.UnitSlider.Limits = [1, max(2, n)];
            if obj.UnitSlider.Value > max(2, n), obj.UnitSlider.Value = 1; end
        end

        function c = colorFor(~, key)
            nlSet = {'fit_NL','fit_mid_NL','fit_mid_nc_NL','fit_mid_self_NL'};
            lSet  = {'fit_L','fit_mid_L','fit_mid_nc_L','fit_mid_self_L'};
            if any(strcmp(key, nlSet)),                 c = [0 0 0];
            elseif any(strcmp(key, lSet)),              c = [0.75 0 0];
            elseif any(strcmp(key, {'Delta_tun','Delta_tun_nc'})), c = [0 0.35 0.85];
            elseif strcmp(key, 'Ratio_tun'),            c = [0.6 0 0.6];
            elseif strcmp(key, 'LTM_fit_L'),            c = [0.92 0.5 0.05];
            elseif strcmp(key, 'ExpM_fit'),             c = [0.20 0.6 0.55];
            elseif startsWith(key, 'dTun_d'),           c = [0 0.5 0.2];
            else,                                       c = [0.25 0.25 0.25];
            end
        end

        function lbl = labelFor(obj, key)
            k = find(strcmp(obj.CurveKeys, key), 1);
            if isempty(k), lbl = key; else, lbl = obj.CurveLabels{k}; end
        end

        function st = styleFor(~, gi)
            styles = {'-','--',':','-.'};
            st = styles{mod(gi-1, numel(styles)) + 1};
        end

        function c = groupColor(~, gi)
            pal = [0 0.45 0.74; 0.85 0.33 0.10; 0.49 0.18 0.56; 0.47 0.67 0.19; ...
                   0.30 0.75 0.93; 0.64 0.08 0.18; 0.5 0.5 0.5];
            c = pal(mod(gi-1, size(pal,1)) + 1, :);
        end
    end
end

% ----------------------------------------------------------------------- %
function h = lab(g, row, txt)
%LAB  A left-aligned label placed on row ROW of grid G (returns the handle).
    h = uilabel(g, 'Text', txt);
    h.Layout.Row = row; h.Layout.Column = 1;
end

% ----------------------------------------------------------------------- %
function v = getfield2(s, f, d)
%GETFIELD2  s.(f) if present and non-empty, else the default d.
    if isstruct(s) && isfield(s, f) && ~isempty(s.(f)), v = s.(f); else, v = d; end
end
