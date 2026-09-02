classdef PlotTab < handle
%PLOTTAB  Base class for one page (tab) of the visualizer.
%
%   A plot page is a self-contained module: its own controls (sliders,
%   dropdowns, switches), its own view (axes), and its own default LOCAL
%   filter condition. To add a new page you subclass PlotTab and implement
%   three methods -- everything else (layout, filter wiring, refresh) is
%   handled for you.
%
%   IMPLEMENT IN A SUBCLASS
%       buildControls(obj, parent)   create your controls inside `parent`
%                                    (a uigridlayout). Hook each control's
%                                    callback to  obj.requestRefresh().
%       buildView(obj, parent)       create your axes/visuals inside `parent`.
%       update(obj, D, mask)         (re)draw using D and the logical Nx1
%                                    `mask` of units that pass the filters.
%
%   OPTIONAL
%       defaultFilters(obj)          return a filter.FilterRule array to use
%                                    as this tab's default LOCAL condition.
%
%   The Visualizer calls update() with the right mask whenever filters change
%   or the user touches one of your controls. Read your own control state from
%   properties you stored in buildControls.
%
%   See also: viz.Visualizer, viz.plots.ScatterTab, filter.FilterSet

    properties
        Name         char = 'Tab'   % tab title
        Viz                         % back-reference to viz.Visualizer
        Tab                         % the uitab handle
        ControlPanel                % uipanel hosting the controls (left)
        ViewPanel                   % uipanel hosting the view   (right)
        LocalFilters                % filter.FilterSet for this tab only
        ControlWidth double = 230   % px width of the control strip (set 0 in a
                                    % subclass for a full-width view + own controls)
        % --- in-tab statistics report (shared; opt in via the helpers below) ---
        Report                      % viz.plots.StatsReport for this tab ([] if none)
        ShowReport   logical = false% is the in-tab stats report visible?
        reportBtn                   % the "Stats report" toggle button
        instrHost                   % uipanel holding the tab's instructions (hidden when report on)
        inspectChk                  % the "Inspect unit on click" checkbox (see addInspectCheckbox)
        trackChk                    % the "Track unit on click" checkbox (see addTrackCheckbox)
        % --- per-tab Animal / Penetration / Task data selection (addDataSelectors) ---
        animalSelDD                 % animal dropdown ([] if the tab has no selectors)
        penSelDD                    % penetration dropdown
        taskSelLB                   % task listbox (multi-select)
        DataSel = struct('animal','(all)','pen','(all)','tasks',{{}})   % current selection
    end

    methods (Abstract)
        buildControls(obj, parent)
        buildView(obj, parent)
        update(obj, D, mask)
    end

    methods
        function obj = PlotTab(name)
            if nargin >= 1 && ~isempty(name), obj.Name = char(name); end
            obj.LocalFilters = filter.FilterSet();
            obj.applyDefaultFilters();
        end

        function f = defaultFilters(~)
            %DEFAULTFILTERS  Override to give this tab a default LOCAL condition.
            %   Return a filter.FilterRule array (use scope 'local').
            f = filter.FilterRule.empty(1, 0);
        end

        function applyDefaultFilters(obj)
            %APPLYDEFAULTFILTERS  Load the tab's default rules into LocalFilters.
            rules = obj.defaultFilters();
            for i = 1:numel(rules)
                r = rules(i); r.Scope = 'local';
                obj.LocalFilters.add(r);
            end
        end

        function attachTo(obj, vizApp, tabgroup)
            %ATTACHTO  Create the uitab and let the subclass fill it. Called by
            %          viz.Visualizer.addTab -- you don't call this yourself.
            obj.Viz = vizApp;
            obj.Tab = uitab(tabgroup, 'Title', obj.Name);

            g = uigridlayout(obj.Tab, [1 2]);
            g.ColumnWidth = {obj.ControlWidth, '1x'};
            g.RowHeight   = {'1x'};
            g.Padding     = [6 6 6 6];

            obj.ControlPanel = uipanel(g, 'Title', 'Controls');
            obj.ControlPanel.Layout.Column = 1;
            obj.ViewPanel = uipanel(g, 'BorderType', 'none');
            obj.ViewPanel.Layout.Column = 2;

            % Subclasses receive the host panels and lay out their own grids.
            obj.buildControls(obj.ControlPanel);
            obj.buildView(obj.ViewPanel);
        end

        function requestRefresh(obj)
            %REQUESTREFRESH  Call from a control callback to redraw this tab.
            if ~isempty(obj.Viz), obj.Viz.refresh(); end
        end

        function h = exportTarget(obj)
            %EXPORTTARGET  Graphics handle for the toolbar's "Save PDF" to capture.
            %   Default: a figure tab (one that owns a pop-out PlotFig window)
            %   returns that window, opening + drawing it first if it is closed so
            %   there is always a figure to save; every other tab (tables / inline
            %   axes drawn in the tab body) returns the whole app window. Override in
            %   a subclass only for a special export target. See
            %   viz.Visualizer.exportCurrentPDF.
            h = [];
            if isprop(obj, 'PlotFig')
                if isempty(obj.PlotFig) || ~isvalid(obj.PlotFig)
                    try, obj.openFigure(); drawnow; catch, end %#ok<CTCH>
                end
                if ~isempty(obj.PlotFig) && isvalid(obj.PlotFig)
                    h = obj.PlotFig; return;
                end
            end
            if ~isempty(obj.Viz) && ~isempty(obj.Viz.Fig) && isvalid(obj.Viz.Fig)
                h = obj.Viz.Fig;                 % table / inline-axes tabs: capture the app window
            end
        end

        function nudgeSlider(obj, slider, step)
            %NUDGESLIDER  Step a slider by `step` (clamped to its Limits) and
            %   redraw. Wire the tab's +/- buttons to this, e.g.
            %     uibutton(...,'ButtonPushedFcn',@(s,e) obj.nudgeSlider(sld,+1))
            if isempty(slider) || ~isvalid(slider), return; end
            lim = slider.Limits;
            v   = min(max(slider.Value + step, lim(1)), lim(2));
            slider.Value = v;
            obj.requestRefresh();
        end

        function holder = addStepButtons(obj, parent, slider, step)
            %ADDSTEPBUTTONS  Put a [ - | + ] button pair into `parent` (a
            %   uigridlayout) wired to nudge `slider` by -/+ `step`. Returns the
            %   1x2 sub-grid so the caller can place it (holder.Layout.Row = ...).
            holder = uigridlayout(parent, [1 2], 'Padding', [0 0 0 0], 'ColumnSpacing', 4);
            uibutton(holder, 'Text', '−', 'ButtonPushedFcn', @(s,e) obj.nudgeSlider(slider, -step));
            uibutton(holder, 'Text', '+', 'ButtonPushedFcn', @(s,e) obj.nudgeSlider(slider, +step));
        end

        % --------------------------------------------------------------- %
        %  Click-to-inspect a single unit (shared popup; see viz.plots.UnitInspector)
        %  A tab opts in with two one-liners:
        %    buildControls : obj.addInspectCheckbox(g)   % at the END of the grid
        %    pick handler  : obj.inspectPick(u)          % after it resolves unit u
        %  The checkbox toggles a GLOBAL flag (shared by every tab); a pick only
        %  opens/updates the popup when that flag is on.
        % --------------------------------------------------------------- %
        function chk = addInspectCheckbox(obj, grid, txt)
            %ADDINSPECTCHECKBOX  Add the "Inspect unit on click" checkbox to a
            %   single-column controls uigridlayout. Pins itself to a new bottom
            %   row (explicit Layout) so it never collides with existing controls.
            if nargin < 3 || isempty(txt), txt = 'Inspect unit on click'; end
            chk = uicheckbox(grid, 'Text', txt, 'Tooltip', ...
                'Click near a unit in any scatter to open its raster / tuning / polar / delta-ratio panels.', ...
                'ValueChangedFcn', @(s,e) obj.onInspectToggle());
            try
                if isa(grid, 'matlab.ui.container.GridLayout')
                    nRows = numel(grid.RowHeight);
                    grid.RowHeight{nRows+1} = 22;        % add a fixed-height bottom row
                    chk.Layout.Row = nRows + 1; chk.Layout.Column = 1;
                end
            catch
            end
            obj.inspectChk = chk;
            if ~isempty(obj.Viz), obj.Viz.registerInspectCheck(chk); end
            obj.addTrackCheckbox(grid);          % "Track unit on click" sits right below
        end

        function onInspectToggle(obj)
            %ONINSPECTTOGGLE  Push this checkbox's state to the global flag (which
            %   syncs every other tab's checkbox).
            if ~isempty(obj.Viz) && ~isempty(obj.inspectChk) && isvalid(obj.inspectChk)
                obj.Viz.setInspectEnabled(obj.inspectChk.Value);
            end
        end

        function inspectPick(obj, u)
            %INSPECTPICK  Route a picked unit `u` (D row index) to the shared
            %   inspector popup. No-op unless the feature is toggled on.
            if ~isempty(obj.Viz), obj.Viz.inspectUnit(u); end
        end

        % ---- global "track unit on click" (ring one unit across all plots) ---- %
        function chk = addTrackCheckbox(obj, grid, txt)
            %ADDTRACKCHECKBOX  Add the "Track unit on click" checkbox (a new bottom
            %   row). When on, a pick rings that unit in EVERY scatter/box plot across
            %   all tabs (see viz.Visualizer.trackUnit). Added automatically by
            %   addInspectCheckbox, so it sits just below "Inspect unit on click".
            if nargin < 3 || isempty(txt), txt = 'Track unit on click (all plots)'; end
            chk = uicheckbox(grid, 'Text', txt, 'Tooltip', ...
                'Click near a unit in any scatter or box plot to ring it in every plot across all tabs, to follow one unit.', ...
                'ValueChangedFcn', @(s,e) obj.onTrackToggle());
            try
                if isa(grid, 'matlab.ui.container.GridLayout')
                    nRows = numel(grid.RowHeight);
                    grid.RowHeight{nRows+1} = 22;        % add a fixed-height bottom row
                    chk.Layout.Row = nRows + 1; chk.Layout.Column = 1;
                end
            catch
            end
            obj.trackChk = chk;
            if ~isempty(obj.Viz), obj.Viz.registerTrackCheck(chk); end
        end

        function onTrackToggle(obj)
            %ONTRACKTOGGLE  Push this checkbox's state to the global track flag.
            if ~isempty(obj.Viz) && ~isempty(obj.trackChk) && isvalid(obj.trackChk)
                obj.Viz.setTrackEnabled(obj.trackChk.Value);
            end
        end

        function trackPick(obj, u)
            %TRACKPICK  Route a picked unit `u` to the global tracker (rings it on
            %   every registered plot). No-op unless tracking is toggled on.
            if ~isempty(obj.Viz), obj.Viz.trackUnit(u); end
        end

        function registerRing(obj, ax, X, Y, reps)
            %REGISTERRING  Register a pick-enabled axes so the tracked unit can be
            %   ringed on it. Call right where the axes' pick ButtonDownFcn is wired
            %   (X/Y parallel to reps, the plotted D row indices).
            if ~isempty(obj.Viz), obj.Viz.registerRingAxes(ax, X, Y, reps); end
        end

        function enableDotPick(obj, ax, X, Y, reps)
            %ENABLEDOTPICK  Make the dots at (X,Y)<->reps in `ax` clickable: a click
            %   rings the nearest dot and routes its unit to the shared inspector.
            %   Use for box-plot / scatter dot clouds where each dot is one unit
            %   (X,Y parallel to `reps`, the D row indices). Safe to call on every
            %   redraw; rings nothing until a click. No-op for empty input.
            if isempty(ax) || ~isgraphics(ax) || isempty(reps), return; end
            X = X(:); Y = Y(:); reps = reps(:);
            n = min([numel(X) numel(Y) numel(reps)]);
            if n == 0, return; end
            X = X(1:n); Y = Y(1:n); reps = reps(1:n);
            ax.ButtonDownFcn = @(s,e) obj.dotPick(s, e, X, Y, reps);
            obj.registerRing(ax, X, Y, reps);    % so the tracked unit can ring here too
        end

        function dotPick(obj, ax, e, X, Y, reps)
            %DOTPICK  ButtonDownFcn target for enableDotPick: ring + inspect + track nearest.
            try, pt = e.IntersectionPoint(1:2); catch, return; end %#ok<CTCH>
            u = viz.plots.V01util.nearestUnit(ax, X, Y, reps, pt);
            if ~isfinite(u), return; end
            viz.plots.V01util.highlightUnits(ax, X, Y, reps, u);
            obj.inspectPick(u);
            obj.trackPick(u);
        end

        % --------------------------------------------------------------- %
        %  Per-tab Animal / Penetration / Task data selection
        %  Mirrors the Laminar tabs' selectors, but for ANY tab: opt in with one
        %  call at the END of buildControls -- obj.addDataSelectors(g) -- and the
        %  selection is ANDed into this tab's mask by viz.Visualizer.maskFor (via
        %  selectionMask). It is LOCAL: changing it only redraws THIS tab.
        % --------------------------------------------------------------- %
        function addDataSelectors(obj, grid)
            %ADDDATASELECTORS  Append Animal / Penetration / Task selectors to a
            %   controls uigridlayout (only those whose fields exist in D). Each
            %   control pins itself to a fresh bottom row.
            if isempty(obj.Viz) || ~isa(grid, 'matlab.ui.container.GridLayout'), return; end
            D = obj.Viz.D;
            hasAnimal = isfield(D,'Animal') || isfield(D,'Dataset');
            hasPen    = isfield(D,'Penetration');
            hasTask   = isfield(D,'Tasknumb');
            if ~(hasAnimal || hasPen || hasTask), return; end
            try, grid.Scrollable = 'on'; catch, end %#ok<CTCH>
            obj.dsAddRow(grid, 18, uilabel(grid, 'Text','Data selection (this tab)', 'FontWeight','bold'));
            if hasAnimal
                items = viz.plots.V01util.dsAnimalItems(D); obj.DataSel.animal = items{1};
                obj.animalSelDD = uidropdown(grid, 'Items', items, 'Value', items{1}, ...
                    'Tooltip','Restrict THIS tab to one animal.', 'ValueChangedFcn', @(s,e) obj.onDataSelAnimal());
                obj.dsAddRow(grid, 24, obj.animalSelDD);
            end
            if hasPen
                pit = viz.plots.V01util.dsPenItems(D, obj.DataSel.animal); obj.DataSel.pen = pit{1};
                obj.penSelDD = uidropdown(grid, 'Items', pit, 'Value', pit{1}, ...
                    'Tooltip','Restrict THIS tab to one penetration.', 'ValueChangedFcn', @(s,e) obj.onDataSelPen());
                obj.dsAddRow(grid, 24, obj.penSelDD);
            end
            if hasTask
                tit = viz.plots.V01util.dsTaskItems(D, obj.DataSel.animal, obj.DataSel.pen);
                obj.taskSelLB = uilistbox(grid, 'Items', tit, 'Multiselect','on', 'Value','(all tasks)', ...
                    'Tooltip','Restrict THIS tab to one or more tasks ((all tasks) = no restriction).', ...
                    'ValueChangedFcn', @(s,e) obj.onDataSelTask());
                obj.dsAddRow(grid, 64, obj.taskSelLB);
            end
        end

        function m = selectionMask(obj, D, N)
            %SELECTIONMASK  This tab's Animal/Pen/Task restriction (true(N,1) if the
            %   tab has no selectors or everything is '(all)'). ANDed in by maskFor.
            if isempty(obj.animalSelDD) && isempty(obj.penSelDD) && isempty(obj.taskSelLB)
                m = true(N,1); return;
            end
            m = viz.plots.V01util.dsSelectionMask(D, N, obj.DataSel.animal, obj.DataSel.pen, obj.DataSel.tasks);
        end

        function onDataSelAnimal(obj)
            obj.DataSel.animal = obj.animalSelDD.Value;
            if ~isempty(obj.penSelDD) && isvalid(obj.penSelDD)        % cascade penetration list
                pit = viz.plots.V01util.dsPenItems(obj.Viz.D, obj.DataSel.animal);
                obj.penSelDD.Items = pit; obj.penSelDD.Value = pit{1}; obj.DataSel.pen = pit{1};
            end
            obj.dsCascadeTasks();
            obj.requestRefresh();
        end
        function onDataSelPen(obj)
            obj.DataSel.pen = obj.penSelDD.Value;
            obj.dsCascadeTasks();
            obj.requestRefresh();
        end
        function onDataSelTask(obj)
            v = obj.taskSelLB.Value;
            if ischar(v), v = {v}; elseif isstring(v), v = cellstr(v); end
            if isempty(v) || any(strcmp(v,'(all tasks)')), obj.DataSel.tasks = {}; else, obj.DataSel.tasks = v(:)'; end
            obj.requestRefresh();
        end
        function dsAddRow(~, grid, h, ctrl)
            %DSADDROW  Append a fixed-height bottom row and place `ctrl` across it.
            r = numel(grid.RowHeight) + 1; grid.RowHeight{r} = h;
            ctrl.Layout.Row = r;
            nc = max(1, numel(grid.ColumnWidth));
            if nc == 1, ctrl.Layout.Column = 1; else, ctrl.Layout.Column = [1 nc]; end
        end
        function dsCascadeTasks(obj)
            %DSCASCADETASKS  Refresh the task list for the current animal/pen + reset.
            if isempty(obj.taskSelLB) || ~isvalid(obj.taskSelLB), return; end
            tit = viz.plots.V01util.dsTaskItems(obj.Viz.D, obj.DataSel.animal, obj.DataSel.pen);
            obj.taskSelLB.Items = tit; obj.taskSelLB.Value = '(all tasks)'; obj.DataSel.tasks = {};
        end
        function applyDataSel(obj, ds)
            %APPLYDATASEL  Restore a saved Animal/Pen/Task selection onto the controls.
            if ~isstruct(ds), return; end
            if ~isempty(obj.animalSelDD) && isvalid(obj.animalSelDD) && isfield(ds,'animal')
                obj.setCtrl(obj.animalSelDD, char(string(ds.animal)));
                obj.DataSel.animal = obj.animalSelDD.Value;
                if ~isempty(obj.penSelDD) && isvalid(obj.penSelDD)
                    obj.penSelDD.Items = viz.plots.V01util.dsPenItems(obj.Viz.D, obj.DataSel.animal);
                end
            end
            if ~isempty(obj.penSelDD) && isvalid(obj.penSelDD) && isfield(ds,'pen')
                obj.setCtrl(obj.penSelDD, char(string(ds.pen)));
                obj.DataSel.pen = obj.penSelDD.Value;
            end
            if ~isempty(obj.taskSelLB) && isvalid(obj.taskSelLB)
                obj.taskSelLB.Items = viz.plots.V01util.dsTaskItems(obj.Viz.D, obj.DataSel.animal, obj.DataSel.pen);
                tk = {}; if isfield(ds,'tasks'), tk = ds.tasks; end
                valid = {}; if ~isempty(tk), valid = tk(ismember(tk, obj.taskSelLB.Items)); end
                if isempty(valid)
                    obj.taskSelLB.Value = '(all tasks)'; obj.DataSel.tasks = {};
                else
                    obj.taskSelLB.Value = valid; obj.DataSel.tasks = valid(:)';
                end
            end
        end

        % --------------------------------------------------------------- %
        %  In-tab statistics report (shared scaffold for the figure tabs)
        %  The plot opens in its own window, so the tab body is free to host a
        %  toggle-able stats table. A subclass opts in with three calls:
        %    buildControls : obj.addReportButton(grid)
        %    buildView     : obj.buildReportView(parent, instructionsText)
        %    update        : if obj.ShowReport, obj.refreshReport(); end
        %  and overrides reportSpec() to say WHAT to compute. Persist the toggle
        %  by adding 'showReport' to get/setControlState (see applyReportState).
        % --------------------------------------------------------------- %
        function addReportButton(obj, parent, txt)
            %ADDREPORTBUTTON  Add the "Stats report" toggle to a controls grid.
            if nargin < 3 || isempty(txt), txt = 'Stats report: OFF'; end
            obj.reportBtn = uibutton(parent, 'Text', txt, ...
                'ButtonPushedFcn', @(s,e) obj.toggleReport());
        end

        function host = buildReportView(obj, parent, instructionsText)
            %BUILDREPORTVIEW  Overlay the tab's instructions + a StatsReport in
            %   one cell; toggleReport() flips which is visible.
            host = uigridlayout(parent, [1 1]); host.Padding = [0 0 0 0];
            obj.instrHost = uipanel(host, 'BorderType', 'none');
            obj.instrHost.Layout.Row = 1; obj.instrHost.Layout.Column = 1;
            ig = uigridlayout(obj.instrHost, [1 1]); ig.Padding = [20 20 20 20];
            uilabel(ig, 'Text', instructionsText, 'HorizontalAlignment', 'center', ...
                'WordWrap', 'on', 'FontSize', 13);
            obj.Report = viz.plots.StatsReport(host);
            obj.Report.Panel.Layout.Row = 1; obj.Report.Panel.Layout.Column = 1;
        end

        function ig = buildReportInstr(obj, parent)
            %BUILDREPORTINSTR  Like buildReportView, but returns the instructions
            %   grid so the caller adds its OWN instructions label. Lets a tab
            %   keep its existing buildView text with a single-line change:
            %     gg = obj.buildReportInstr(parent);   % then uilabel(gg, ...)
            host = uigridlayout(parent, [1 1]); host.Padding = [0 0 0 0];
            obj.instrHost = uipanel(host, 'BorderType', 'none');
            obj.instrHost.Layout.Row = 1; obj.instrHost.Layout.Column = 1;
            ig = uigridlayout(obj.instrHost, [1 1]); ig.Padding = [20 20 20 20];
            obj.Report = viz.plots.StatsReport(host);
            obj.Report.Panel.Layout.Row = 1; obj.Report.Panel.Layout.Column = 1;
        end

        function toggleReport(obj)
            obj.ShowReport = ~obj.ShowReport; obj.syncReport();
        end

        function syncReport(obj)
            on = obj.ShowReport;
            if ~isempty(obj.reportBtn) && isvalid(obj.reportBtn)
                if on, obj.reportBtn.Text = 'Stats report: ON'; else, obj.reportBtn.Text = 'Stats report: OFF'; end
            end
            if ~isempty(obj.instrHost) && isvalid(obj.instrHost)
                if on, obj.instrHost.Visible = 'off'; else, obj.instrHost.Visible = 'on'; end
            end
            if ~isempty(obj.Report), obj.Report.setVisible(on); end
            if on, obj.refreshReport(); end
        end

        function refreshReport(obj)
            %REFRESHREPORT  Recompute + render the report from reportSpec().
            if ~obj.ShowReport || isempty(obj.Report), return; end
            rs = obj.reportSpec();
            if isempty(rs), return; end
            hdr = ''; if isfield(rs,'header'), hdr = rs.header; end
            if isfield(rs,'out') && ~isempty(rs.out)   % tab supplied a precomputed table
                obj.Report.update(rs.out, hdr); return;
            end
            try
                specs = analysis.stats.figureCatalog(rs.figKey, rs.state);
                out   = analysis.stats.compute(rs.D, rs.state, specs);
                obj.Report.update(out, hdr);
            catch err
                obj.Report.update(struct('ColumnName', {{'error'}}, 'Data', {{err.message}}, 'modes', {{}}));
            end
        end

        function rs = reportSpec(~)
            %REPORTSPEC  Override: return struct('figKey',c,'state',s,'D',D,'header',h)
            %   or [] to leave the report empty. `state` must carry the same group/
            %   E-I/mask selection the figure draws, plus state.mask (logical Nx1).
            rs = [];
        end

        function [out, hdr] = computeReport(obj)
            %COMPUTEREPORT  Return the report as a struct with .ColumnName (1xC
            %   cellstr) and .Data (RxC cell of char) + header string, WITHOUT a
            %   report widget -- so a caller (e.g. the paper-figure builder) can
            %   render the table as exportable graphics. [] if the tab has no report.
            out = []; hdr = '';
            rs = obj.reportSpec();
            if isempty(rs), return; end
            if isfield(rs,'header'), hdr = rs.header; end
            if isfield(rs,'out') && ~isempty(rs.out), out = rs.out; return; end
            try
                specs = analysis.stats.figureCatalog(rs.figKey, rs.state);
                out   = analysis.stats.compute(rs.D, rs.state, specs);
            catch err
                out = struct('ColumnName', {{'error'}}, 'Data', {{err.message}});
            end
        end

        function applyReportState(obj, s)
            %APPLYREPORTSTATE  Restore the toggle from a saved control state.
            if isstruct(s) && isfield(s,'showReport')
                obj.ShowReport = logical(s.showReport); obj.syncReport();
            end
        end

        % --------------------------------------------------------------- %
        %  Persistence (session memory + per-tab defaults)
        % --------------------------------------------------------------- %
        function s = getState(obj)
            %GETSTATE  Serializable snapshot of this tab (filters + controls).
            s.filters  = obj.LocalFilters.toStruct();
            s.controls = obj.getControlState();
            if ~isempty(obj.reportBtn)            % persist the report toggle generically
                s.controls.showReport = obj.ShowReport;
            end
            if ~isempty(obj.animalSelDD) || ~isempty(obj.penSelDD) || ~isempty(obj.taskSelLB)
                s.controls.dataSel = obj.DataSel; % persist the Animal/Pen/Task selection
            end
        end

        function setState(obj, s)
            %SETSTATE  Restore a snapshot produced by getState().
            if isfield(s, 'filters')
                obj.LocalFilters = filter.FilterSet.fromStruct(s.filters);
            end
            if isfield(s, 'controls')
                try, obj.setControlState(s.controls); catch, end %#ok<CTCH>
                obj.applyReportState(s.controls);
                if isfield(s.controls, 'dataSel')
                    try, obj.applyDataSel(s.controls.dataSel); catch, end %#ok<CTCH>
                end
            end
        end

        function s = getControlState(~)
            %GETCONTROLSTATE  Override in a subclass to persist its controls.
            %   Return a struct of plain values (slider/dropdown/switch states).
            s = struct();
        end

        function setControlState(~, ~)
            %SETCONTROLSTATE  Override in a subclass to restore its controls.
            %   Guard each field (items/limits may have changed since saving).
        end

        function closePopouts(~)
            %CLOSEPOPOUTS  Override in a subclass to close any pop-out figures it
            %   owns when the app closes. Default: nothing to close. Called for every
            %   tab by viz.Visualizer.onClose (after the session is saved).
        end
    end

    methods (Static, Access = protected)
        function setCtrl(ctrl, val)
            %SETCTRL  Safely restore a saved value onto a uicontrol.
            %   Handles dropdowns (Items / ItemsData), switches, and sliders
            %   (clamps / widens limits). No-ops if the value is no longer valid.
            if isempty(ctrl) || ~isvalid(ctrl), return; end
            try
                if isprop(ctrl,'ItemsData') && ~isempty(ctrl.ItemsData)
                    id = ctrl.ItemsData;
                    ok = (isnumeric(id) && any(id == val)) || ...
                         (iscell(id) && any(cellfun(@(x) isequal(x,val), id)));
                    if ok, ctrl.Value = val; end
                elseif isprop(ctrl,'Items') && ~isempty(ctrl.Items)
                    if any(strcmp(ctrl.Items, val)), ctrl.Value = val; end
                elseif isprop(ctrl,'Limits') && isnumeric(val) && isscalar(val)
                    lim = ctrl.Limits;
                    if val > lim(2), ctrl.Limits = [lim(1) val]; lim = ctrl.Limits; end
                    ctrl.Value = min(max(val, lim(1)), lim(2));
                else
                    ctrl.Value = val;
                end
            catch
            end
        end
    end
end
