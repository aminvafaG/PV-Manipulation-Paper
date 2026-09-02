classdef Visualizer < handle
%VISUALIZER  Multi-tab data explorer with a global, per-tab filtering system.
%
%   app = viz.Visualizer(D)        build the window for project struct D
%   app.addTab( viz.plots.XxxTab() )   register a plot page (any number)
%   app.show()                     bring to front + initial draw
%
%   LAYOUT
%       [ toolbar: ☰ Filters | title | unit count                  ]
%       [ tab group (browser-style tabs)        | filter panel(hide)]
%
%   FILTERING MODEL
%     * GlobalFilters : one filter.FilterSet applied to EVERY tab.
%     * Each tab owns LocalFilters : a filter.FilterSet applied to that tab only.
%     * The mask a tab is drawn with = GlobalFilters AND that tab's LocalFilters.
%     * The filter panel (normally hidden, toggled from the toolbar) edits both,
%       shows the active rules for the current tab, and lets you choose per rule
%       whether it is global or local. Switching tabs shows that tab's rules.
%
%   See also: viz.PlotTab, filter.FilterPanel, filter.FilterSet

    properties
        D                       % project data struct (from loadData/computeMetrics)
        N        double         % number of units
        Fig                     % uifigure
        TabGroup                % uitabgroup
        Tabs     cell = {}      % cell array of viz.PlotTab
        GlobalFilters           % filter.FilterSet (shared by all tabs)
        FilterPanelObj          % filter.FilterPanel
        Body                    % inner grid holding [tabgroup | filterHost]
        FilterHost              % uipanel that hosts the filter panel
        FilterVisible logical = false
        DefaultState = []       % saved "default" snapshot (Reset restores this)
        % --- click-to-inspect a single unit (shared popup across all tabs) ---
        InspectEnabled logical = false   % is "inspect unit on click" turned on?
        InspectorObj            % viz.plots.UnitInspector (lazy; shared by every tab)
        InspectChecks cell = {} % the per-tab "Inspect unit on click" checkboxes (kept in sync)
        % --- global "track unit on click": ring ONE unit across EVERY plot/tab ---
        TrackEnabled logical = false   % is "track unit on click" turned on?
        TrackedUnit double = NaN       % the D row index currently tracked (NaN = none)
        TrackWholeUnit logical = false % ring scope: false (default) = ring only the
                                       %   clicked sample; true = every recorded sample of
                                       %   the neuron (same U_unity). Set from the filter
                                       %   panel's "Track scope" box (0 = clicked sample).
        TrackChecks cell = {}          % the per-tab "Track unit on click" checkboxes (synced)
        RingReg cell = {}              % registry of pick axes {ax,X,Y,reps} to (re)ring on track
        % --- app identity: lets a SECOND, independent Visualizer window coexist ---
        AppTitle      char = 'PV Manipulation Visualizer'  % window + toolbar title
        StateBaseName char = 'viz_state'                   % <name>.mat session/default/presets store
        % --- paper-figure controller (a SECOND window that composes THIS app's plots) --
        PaperMode logical = false   % true = this app is a paper-figure controller (paper pages only)
        SourceViz = []              % (paper controller) the source app whose tabs the boxes clone from
        PaperApps cell = {}         % (source app) paper controllers spawned from this app, for live updates
        % --- I/O-model fitting option (global; refits ALL units on change) ----
        %   Picks the analysis.exponentialModel setting used for every ExpM_*
        %   metric (and the I/O-model figures). Changing it re-runs the per-unit
        %   fit and redraws every tab. Persisted with the session.
        FitOption   char = 'No bounds + single seed'   % active I/O fit (= DefaultFitOption; a fitOptionLabels entry)
        FitDropdown                                    % toolbar uidropdown handle (I/O)
        LTMOption   char = 'PVA floor = 0 (2-param)'   % active LTM fit (= DefaultLTMOption; a ltmOptionLabels entry)
        LTMDropdown                                    % toolbar uidropdown handle (LTM)
        % --- paper-figure modifications master key (viz.paperStyle) ------------
        %   ON = original pre-paper-port look, OFF = match the published figures.
        OrigStyleChk                                   % toolbar "Original style" checkbox handle
    end

    properties (Constant)
        FilterWidth = 340       % px width of the side filter panel when shown
        % Startup default fit options (must match the FitOption/LTMOption property
        % defaults above). defaultCacheArgs() turns these into computeMetrics args
        % so launchers compute the cache with exactly what the toolbar will show.
        DefaultFitOption = 'No bounds + single seed'
        DefaultLTMOption = 'PVA floor = 0 (2-param)'
    end

    methods
        function obj = Visualizer(D, varargin)
            % viz.Visualizer(D) builds the standard app. Pass
            %   ...,'Title',t,'StateName',s  to spin up a SECOND, independent
            % window (its own title + its own <s>.mat session store) so the two
            % apps never clobber each other's saved session/defaults/presets.
            p = inputParser; p.KeepUnmatched = true;
            p.addParameter('Title',     obj.AppTitle,      @(x) ischar(x) || isstring(x));
            p.addParameter('StateName', obj.StateBaseName, @(x) ischar(x) || isstring(x));
            p.addParameter('PaperMode', false,             @(x) islogical(x) || isnumeric(x));
            p.parse(varargin{:});
            obj.AppTitle      = char(p.Results.Title);
            obj.StateBaseName = char(p.Results.StateName);
            obj.PaperMode     = logical(p.Results.PaperMode);
            obj.D = D;
            obj.N = filter.unitCount(D);
            % UnitIndex (1..N) is the per-unit number the tabs display as
            % "unit N". Guaranteeing it here makes units filterable/excludable
            % by that number (see the filter panel's "Exclude units" box),
            % regardless of how D was built.
            if ~isfield(obj.D, 'UnitIndex')
                obj.D.UnitIndex = (1:obj.N)';
            end
            obj.GlobalFilters = filter.FilterSet();
            obj.buildUI();
        end

        function buildUI(obj)
            obj.Fig = uifigure('Name', obj.AppTitle, ...
                'Position', [80 80 1280 780], 'Visible', 'off', ...
                'CloseRequestFcn', @(s,e) obj.onClose());

            root = uigridlayout(obj.Fig, [2 1]);
            root.RowHeight   = {38, '1x'};
            root.ColumnWidth = {'1x'};
            root.RowSpacing  = 4;

            % ---- toolbar --------------------------------------------------
            styleTip = ['Master key for every paper-figure modification (lines, bars, ' ...
                        'writing and their colors). OFF (default) = plots match the published ' ...
                        'paper figures; ON = the original appearance from before the ' ...
                        'paper-matching edits. Applies to every tab and figure.'];
            pdfTip = ['Save the current tab as a PDF (or PNG/JPEG). Figure tabs export ' ...
                      'their pop-out plot window as VECTOR graphics (opened first if it is ' ...
                      'closed); table / inline tabs export a raster snapshot of the app window.'];
            if obj.PaperMode
                % paper-figure controller: Filters button kept so the panel's "Set
                % current view as default" save button stays reachable.
                tb = uigridlayout(root, [1 5]); tb.Layout.Row = 1;
                tb.ColumnWidth = {120, 130, 130, '1x', 120}; tb.Padding = [6 4 6 4]; tb.ColumnSpacing = 6;
                uibutton(tb, 'Text', '☰ Save/Reset', 'Tooltip', 'Open the panel with "Set current view as default" to save this paper controller.', ...
                    'ButtonPushedFcn', @(s,e) obj.toggleFilterPanel());
                uibutton(tb, 'Text', '⤓ Save PDF', 'Tooltip', pdfTip, 'ButtonPushedFcn', @(s,e) obj.exportCurrentPDF());
                obj.OrigStyleChk = uicheckbox(tb, 'Text', 'Original style', 'Value', ~viz.paperStyle(), ...
                    'Tooltip', styleTip, 'ValueChangedFcn', @(s,e) obj.setOriginalStyle(s.Value));
                uilabel(tb, 'Text', obj.AppTitle, 'FontWeight','bold', 'HorizontalAlignment','center');
                uilabel(tb, 'Text', sprintf('%d units', obj.N), 'HorizontalAlignment','right');
            else
                tb = uigridlayout(root, [1 10]); tb.Layout.Row = 1;
                tb.ColumnWidth = {120, 110, 140, 130, '1x', 50, 175, 52, 170, 120};
                tb.Padding = [6 4 6 4]; tb.ColumnSpacing = 6;
                uibutton(tb, 'Text', '☰ Filters', 'ButtonPushedFcn', @(s,e) obj.toggleFilterPanel());
                uibutton(tb, 'Text', '⤓ Save PDF', 'Tooltip', pdfTip, 'ButtonPushedFcn', @(s,e) obj.exportCurrentPDF());
                uibutton(tb, 'Text', '📄 Paper figures', ...
                    'Tooltip', 'Open the paper-figure controller window (composes this app''s plots into paper pages).', ...
                    'ButtonPushedFcn', @(s,e) obj.openPaperFigures());
                obj.OrigStyleChk = uicheckbox(tb, 'Text', 'Original style', 'Value', ~viz.paperStyle(), ...
                    'Tooltip', styleTip, 'ValueChangedFcn', @(s,e) obj.setOriginalStyle(s.Value));
                uilabel(tb, 'Text', obj.AppTitle, 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
                uilabel(tb, 'Text', 'I/O fit:', 'HorizontalAlignment', 'right');
                obj.FitDropdown = uidropdown(tb, 'Items', obj.fitOptionLabels(), 'Value', obj.FitOption, ...
                    'Tooltip', ['I/O-model fitting option (analysis.exponentialModel). ' ...
                                'Refits all units and redraws every tab.'], ...
                    'ValueChangedFcn', @(s,e) obj.setFitOption(s.Value));
                uilabel(tb, 'Text', 'LTM fit:', 'HorizontalAlignment', 'right');
                obj.LTMDropdown = uidropdown(tb, 'Items', obj.ltmOptionLabels(), 'Value', obj.LTMOption, ...
                    'Tooltip', ['Threshold-linear-model fitting option ' ...
                                '(analysis.linearThresholdModel). ''PVA floor = 0'' locks ' ...
                                'the PVA floor for a 2-vs-2 match with the I/O model.'], ...
                    'ValueChangedFcn', @(s,e) obj.setLTMOption(s.Value));
                uilabel(tb, 'Text', sprintf('%d units', obj.N), 'HorizontalAlignment', 'right');
            end

            % ---- body: tab group + (hidden) filter panel ------------------
            obj.Body = uigridlayout(root, [1 2]);
            obj.Body.Layout.Row = 2;
            obj.Body.ColumnWidth = {'1x', 0};      % filter column collapsed
            obj.Body.ColumnSpacing = 4;
            obj.Body.Padding = [4 4 4 4];

            obj.TabGroup = uitabgroup(obj.Body, ...
                'SelectionChangedFcn', @(s,e) obj.onTabChanged());
            obj.TabGroup.Layout.Column = 1;

            obj.FilterHost = uipanel(obj.Body, 'Title', 'Filter & Control Panel', ...
                'Visible', 'off');
            obj.FilterHost.Layout.Column = 2;

            obj.FilterPanelObj = filter.FilterPanel(obj);
            obj.FilterPanelObj.build(obj.FilterHost);
        end

        function tab = addTab(obj, plotTab)
            %ADDTAB  Register and build a plot page. Returns the page object.
            plotTab.attachTo(obj, obj.TabGroup);
            obj.Tabs{end+1} = plotTab;
            obj.drawTab(plotTab);                 % initial draw
            tab = plotTab;
        end

        function show(obj)
            %SHOW  Reveal the window, restore the last session, draw.
            obj.Fig.Visible = 'on';
            figure(obj.Fig);
            if ~isempty(obj.Tabs)
                obj.TabGroup.SelectedTab = obj.Tabs{1}.Tab;
            end
            obj.loadSession();      % restore previous session (or saved default)
            obj.refresh();
        end

        % --------------------------------------------------------------- %
        %  Paper-figure controller (a SECOND window that composes THIS app's plots)
        % --------------------------------------------------------------- %
        function paper = openPaperFigures(obj)
            %OPENPAPERFIGURES  Open (or focus) the separate paper-figure controller.
            %   Its boxes clone plots from THIS app's tabs (via SourceViz); pages are
            %   persisted in a dedicated paper_figures.mat (survives app development).
            for k = 1:numel(obj.PaperApps)                 % reuse a live controller if open
                pk = obj.PaperApps{k};
                if isa(pk,'viz.Visualizer') && isvalid(pk) && ~isempty(pk.Fig) && isvalid(pk.Fig)
                    figure(pk.Fig); paper = pk; return;
                end
            end
            paper = viz.Visualizer(obj.D, 'Title','Paper Figures', 'StateName','viz_paper_figures', 'PaperMode', true);
            paper.SourceViz = obj;
            obj.PaperApps{end+1} = paper;
            if ~paper.loadPaperPages()                     % rebuild saved pages, else one blank page
                paper.addPaperPage('Figure 1', 4);
            end
            paper.show();
        end

        function tab = addPaperPage(obj, name, nBoxes)
            %ADDPAPERPAGE  Create a new paper page (a PaperFig01Tab) at runtime.
            if nargin < 2 || isempty(name),   name   = 'Figure'; end
            if nargin < 3 || isempty(nBoxes), nBoxes = 4; end
            name = obj.uniquePageName(name);
            tab  = obj.addTab(viz.plots.PaperFig01Tab(name, nBoxes));
            if ~isempty(tab.Tab) && isvalid(tab.Tab), obj.TabGroup.SelectedTab = tab.Tab; end
        end

        function tab = duplicatePaperPage(obj, srcTab)
            %DUPLICATEPAPERPAGE  New page reusing srcTab's whole box structure AND its
            %   cloned content: setControlState copies every box recipe (source region,
            %   zoom, labels, stat tables), then the copy's figure is opened so it
            %   re-clones the same objects into its boxes (ready to edit/remove/extend).
            if isempty(srcTab) || ~isa(srcTab,'viz.plots.PaperFig01Tab'), tab = []; return; end
            tab = obj.addPaperPage([srcTab.Name ' copy'], 1);
            try, tab.setControlState(srcTab.getControlState()); catch, end %#ok<CTCH>
            obj.drawTab(tab);
            if ~isempty(srcTab.PlotFig) && isvalid(srcTab.PlotFig)          % mirror the source: open the copy so it carries the objects
                try, tab.openFigure(); catch, end %#ok<CTCH>
            end
        end

        function removePaperPage(obj, tab)
            %REMOVEPAPERPAGE  Delete a paper page (keep at least one).
            if isempty(tab), return; end
            idx = find(cellfun(@(t) t == tab, obj.Tabs), 1);
            if isempty(idx) || numel(obj.Tabs) <= 1, return; end
            try, tab.closePopouts(); catch, end %#ok<CTCH>
            try, delete(tab.Tab); catch, end %#ok<CTCH>
            obj.Tabs(idx) = [];
            if ~isempty(obj.Tabs)
                sel = obj.Tabs{max(1, idx-1)};
                if ~isempty(sel.Tab) && isvalid(sel.Tab), obj.TabGroup.SelectedTab = sel.Tab; end
            end
        end

        function nm = uniquePageName(obj, base)
            %UNIQUEPAGENAME  Unique tab name (state keys collide on duplicates).
            base = char(base); nm = base; i = 1;
            existing = cellfun(@(t) t.Name, obj.Tabs, 'UniformOutput', false);
            while any(strcmp(existing, nm)), i = i + 1; nm = sprintf('%s %d', base, i); end
        end

        function notifyPaperApps(obj)
            %NOTIFYPAPERAPPS  Tell spawned paper controllers the source changed, so
            %   their non-frozen boxes re-clone (live update).
            keep = {};
            for k = 1:numel(obj.PaperApps)
                pk = obj.PaperApps{k};
                if ~(isa(pk,'viz.Visualizer') && isvalid(pk)), continue; end
                keep{end+1} = pk; %#ok<AGROW>
                for i = 1:numel(pk.Tabs)
                    t = pk.Tabs{i};
                    if ismethod(t, 'replotLive'), try, t.replotLive(); catch, end, end %#ok<CTCH>
                end
            end
            obj.PaperApps = keep;
        end

        function p = paperPagesFilePath(obj)
            here = fileparts(mfilename('fullpath'));               % .../+viz
            p = fullfile(fileparts(here), 'paper_figures.mat');    % dedicated, dev-robust
        end

        function savePaperPages(obj)
            %SAVEPAPERPAGES  Persist every paper page (name + box recipe) to the
            %   dedicated paper_figures.mat (independent of the session format).
            if ~obj.PaperMode, return; end
            pages = struct('name', {}, 'controls', {});
            for i = 1:numel(obj.Tabs)
                t = obj.Tabs{i};
                if ~isa(t,'viz.plots.PaperFig01Tab'), continue; end
                pages(end+1) = struct('name', t.Name, 'controls', t.getControlState()); %#ok<AGROW>
            end
            try, save(obj.paperPagesFilePath(), 'pages'); catch err
                warning('viz:Visualizer:paperSave', 'Could not save paper pages: %s', err.message);
            end
        end

        function ok = loadPaperPages(obj)
            %LOADPAPERPAGES  Rebuild paper pages from paper_figures.mat. Returns
            %   false if nothing was restored (caller then adds a blank page).
            ok = false; f = obj.paperPagesFilePath();
            if exist(f,'file') ~= 2, return; end
            try, S = load(f); catch, return; end
            if ~isfield(S,'pages') || isempty(S.pages), return; end
            for i = 1:numel(S.pages)
                pg = S.pages(i);
                nm = 'Figure'; if isfield(pg,'name') && ~isempty(pg.name), nm = char(pg.name); end
                t = obj.addPaperPage(nm, 1);
                if isfield(pg,'controls') && ~isempty(pg.controls)
                    try, t.setControlState(pg.controls); catch, end %#ok<CTCH>
                end
            end
            ok = ~isempty(obj.Tabs);
        end

        function redrawTab(obj, tab)
            %REDRAWTAB  Public hook: redraw ONE tab with the app's current data +
            %   filter mask. Used by a paper controller to re-render a frozen box's
            %   SOURCE tab after temporarily applying the freeze-time control state.
            if isempty(tab) || ~isvalid(tab), return; end
            try, obj.drawTab(tab); catch, end %#ok<CTCH>
        end

        % --------------------------------------------------------------- %
        %  Filtering / refresh
        % --------------------------------------------------------------- %
        function m = maskFor(obj, tab)
            %MASKFOR  Combined mask for a tab: global AND that tab's local AND that
            %   tab's own Animal/Penetration/Task data selection (see PlotTab).
            g = obj.GlobalFilters.apply(obj.D, obj.N);
            l = tab.LocalFilters.apply(obj.D, obj.N);
            m = g & l;
            % Units the published analysis discarded as noise are excluded here,
            % once, so every tab and stats report matches the manuscript's
            % population (viz.plots.V01util.noiseMask).
            try, m = m & ~viz.plots.V01util.noiseMask(obj.D); catch, end %#ok<CTCH>
            try
                sm = tab.selectionMask(obj.D, obj.N);
                if ~isempty(sm), m = m & sm(:); end
            catch
            end
        end

        function refresh(obj)
            %REFRESH  Redraw the current tab and update the filter panel display.
            tab = obj.currentTab();
            if ~isempty(tab), obj.drawTab(tab); end
            if obj.FilterVisible, obj.FilterPanelObj.refresh(); end
            obj.notifyPaperApps();       % source changed -> live paper boxes track it
        end

        function refreshAll(obj)
            %REFRESHALL  Redraw every tab (use after a global-filter change).
            for i = 1:numel(obj.Tabs)
                obj.drawTab(obj.Tabs{i});
            end
            if obj.FilterVisible, obj.FilterPanelObj.refresh(); end
            obj.notifyPaperApps();       % source changed -> live paper boxes track it
        end

        % --------------------------------------------------------------- %
        %  Model-fitting options (global): refit all units, redraw all tabs
        %  Two independent menus -- the I/O model (analysis.exponentialModel,
        %  drives the ExpM_* fields) and the threshold-linear model
        %  (analysis.linearThresholdModel, drives the LTM_* fields). A change to
        %  either re-runs analysis.computeMetrics once with BOTH option sets.
        %  The menu lists + arg mappers (fitOptionLabels/expmArgsFor/
        %  ltmOptionLabels/ltmArgsFor) and the startup defaults (defaultCacheArgs)
        %  are STATIC methods (see the methods(Static) block near the end), so a
        %  launcher can pre-compute the cache with exactly the settings the toolbar
        %  will show -- and the window then opens with no refit.
        % --------------------------------------------------------------- %
        function setFitOption(obj, label)
            %SETFITOPTION  Change the I/O-model fitting option (keeps the LTM one).
            obj.applyFitState(char(label), obj.LTMOption);
        end

        function setLTMOption(obj, label)
            %SETLTMOPTION  Change the LTM fitting option (keeps the I/O one).
            obj.applyFitState(obj.FitOption, char(label));
        end

        function applyFitState(obj, fitOpt, ltmOpt)
            %APPLYFITSTATE  Recompute metrics with the given I/O + LTM fitting
            %   options, commit them and redraw on success, or revert the menus and
            %   alert on failure. No-op when both already match the current state.
            fitOpt = char(fitOpt); ltmOpt = char(ltmOpt);
            if strcmp(fitOpt, obj.FitOption) && strcmp(ltmOpt, obj.LTMOption), return; end
            dlg = [];
            try
                dlg = uiprogressdlg(obj.Fig, 'Title', 'Refitting models', ...
                    'Message', sprintf('I/O: %s   |   LTM: %s ...', fitOpt, ltmOpt), ...
                    'Indeterminate', 'on');
            catch
            end
            try
                obj.D = analysis.computeMetrics(obj.D, [], ...
                            'ExpMArgs', obj.expmArgsFor(fitOpt), ...
                            'LTMArgs',  obj.ltmArgsFor(ltmOpt));
                obj.FitOption = fitOpt; obj.LTMOption = ltmOpt;
                obj.syncFitMenus();
                obj.refreshAll();
            catch
                obj.syncFitMenus();          % revert menus to the committed values
                try
                    uialert(obj.Fig, ['Could not recompute the fits. The fitting ' ...
                        'options need the full dataset (launch via loadData + ' ...
                        'computeMetrics). The previous fit was kept.'], ...
                        'Model fit', 'Icon', 'error');
                catch
                end
            end
            try, if ~isempty(dlg) && isvalid(dlg), close(dlg); end, catch, end %#ok<CTCH>
        end

        function syncFitMenus(obj)
            %SYNCFITMENUS  Push the committed FitOption/LTMOption onto the menus.
            if ~isempty(obj.FitDropdown) && isvalid(obj.FitDropdown)
                obj.FitDropdown.Value = obj.FitOption;
            end
            if ~isempty(obj.LTMDropdown) && isvalid(obj.LTMDropdown)
                obj.LTMDropdown.Value = obj.LTMOption;
            end
        end

        function tab = currentTab(obj)
            %CURRENTTAB  The PlotTab object for the selected uitab ([] if none).
            tab = [];
            if isempty(obj.Tabs), return; end
            sel = obj.TabGroup.SelectedTab;
            for i = 1:numel(obj.Tabs)
                if obj.Tabs{i}.Tab == sel, tab = obj.Tabs{i}; return; end
            end
            tab = obj.Tabs{1};
        end

        % --------------------------------------------------------------- %
        %  UI callbacks
        % --------------------------------------------------------------- %
        function toggleFilterPanel(obj)
            obj.setFilterVisible(~obj.FilterVisible);
        end

        function setFilterVisible(obj, tf)
            %SETFILTERVISIBLE  Show/hide the side filter panel.
            obj.FilterVisible = logical(tf);
            if obj.FilterVisible
                obj.Body.ColumnWidth = {'1x', obj.FilterWidth};
                obj.FilterHost.Visible = 'on';
                obj.FilterPanelObj.refresh();
            else
                obj.Body.ColumnWidth = {'1x', 0};
                obj.FilterHost.Visible = 'off';
            end
        end

        function onTabChanged(obj)
            %ONTABCHANGED  Show the new tab's filters and (re)draw it.
            obj.refresh();
        end

        function setOriginalStyle(obj, tf)
            %SETORIGINALSTYLE  Master key for the paper-figure modifications.
            %   tf = true  -> ORIGINAL pre-paper-port appearance (checkbox ON)
            %   tf = false -> match the published paper figures (checkbox OFF)
            %   Flips the global viz.paperStyle flag and redraws every tab so the
            %   whole app (lines, bars, writing and their colors) switches at once.
            viz.paperStyle(~logical(tf));
            if ~isempty(obj.OrigStyleChk) && isvalid(obj.OrigStyleChk)
                obj.OrigStyleChk.Value = logical(tf);
            end
            obj.refreshAll();
        end

        function exportCurrentPDF(obj)
            %EXPORTCURRENTPDF  Save the current tab to a PDF (or PNG/JPEG) file.
            %   Asks the tab for its export target (viz.PlotTab.exportTarget): a
            %   figure tab returns its pop-out plot window -- opened + drawn on
            %   demand if it was closed -- while a table / inline tab returns the
            %   whole app window. A pop-out plot window is written as TRUE VECTOR
            %   graphics (exportgraphics); the app window is a raster snapshot
            %   (exportapp), as its tables / controls have no vector form. See
            %   writeGraphicsFile.
            tab = obj.currentTab();
            if isempty(tab)
                try, uialert(obj.Fig, 'No tab is open to export.', 'Save PDF'); catch, end %#ok<CTCH>
                return;
            end
            % Default file stem from the tab title (kept filesystem-safe).
            stem = regexprep(char(tab.Name), '[^\w\-]+', '_');
            if isempty(stem), stem = 'view'; end
            [fn, pth] = uiputfile({'*.pdf', 'PDF document (*.pdf)'; ...
                                   '*.png', 'PNG image (*.png)'; ...
                                   '*.jpg', 'JPEG image (*.jpg)'}, ...
                                  'Save current view as', [stem '.pdf']);
            if isequal(fn, 0) || isequal(pth, 0), return; end     % user cancelled
            outFile = fullfile(pth, fn);
            target = [];
            try, target = tab.exportTarget(); catch, end %#ok<CTCH>
            if isempty(target) || ~isgraphics(target)
                try, uialert(obj.Fig, 'Nothing to export for this tab.', 'Save PDF'); catch, end %#ok<CTCH>
                return;
            end
            drawnow;                                              % ensure the target is fully rendered
            dlg = [];                                             % busy indicator (vector writes can be slow)
            try, dlg = uiprogressdlg(obj.Fig, 'Title', 'Save PDF', ...
                    'Message', 'Rendering and writing the file ...', 'Indeterminate', 'on'); catch, end %#ok<CTCH>
            try
                mode = obj.writeGraphicsFile(target, outFile);
                try, if ~isempty(dlg) && isvalid(dlg), close(dlg); end, catch, end %#ok<CTCH>
                try, uialert(obj.Fig, sprintf('Saved (%s):\n%s', mode, outFile), ...
                        'Save PDF', 'Icon', 'success'); catch, end %#ok<CTCH>
            catch err
                try, if ~isempty(dlg) && isvalid(dlg), close(dlg); end, catch, end %#ok<CTCH>
                try, uialert(obj.Fig, sprintf('Could not save the file:\n%s', err.message), ...
                        'Save PDF', 'Icon', 'error'); catch, end %#ok<CTCH>
            end
        end

        % --------------------------------------------------------------- %
        %  Click-to-inspect a single unit (shared popup window)
        % --------------------------------------------------------------- %
        function insp = unitInspector(obj)
            %UNITINSPECTOR  The shared viz.plots.UnitInspector (created on demand).
            if isempty(obj.InspectorObj) || ~isa(obj.InspectorObj,'viz.plots.UnitInspector')
                obj.InspectorObj = viz.plots.UnitInspector();
            end
            insp = obj.InspectorObj;
        end

        function inspectUnit(obj, u)
            %INSPECTUNIT  Open/update the unit-inspector popup for unit `u`
            %   (a D row index). No-op unless the feature is toggled on. Called by
            %   every tab's scatter-pick handler via PlotTab.inspectPick.
            if ~obj.InspectEnabled, return; end
            if isempty(u) || ~all(isfinite(u)), return; end
            obj.unitInspector().show(obj.D, u(1));
        end

        function registerInspectCheck(obj, chk)
            %REGISTERINSPECTCHECK  Track a tab's checkbox so all stay in sync, and
            %   seed it with the current global state.
            if isempty(chk) || ~isvalid(chk), return; end
            obj.InspectChecks{end+1} = chk;
            chk.Value = obj.InspectEnabled;
        end

        function setInspectEnabled(obj, tf)
            %SETINSPECTENABLED  Flip the global "inspect on click" flag and mirror
            %   it onto every registered checkbox (so all tabs agree).
            obj.InspectEnabled = logical(tf);
            keep = {};
            for i = 1:numel(obj.InspectChecks)
                c = obj.InspectChecks{i};
                if ~isempty(c) && isvalid(c)
                    c.Value = obj.InspectEnabled; keep{end+1} = c; %#ok<AGROW>
                end
            end
            obj.InspectChecks = keep;     % drop stale (deleted) checkbox handles
            if ~obj.InspectEnabled && ~isempty(obj.InspectorObj) ...
                    && isa(obj.InspectorObj,'viz.plots.UnitInspector') && obj.InspectorObj.isOpen()
                obj.InspectorObj.close();  % turning it off closes the popup
            end
        end

        % --------------------------------------------------------------- %
        %  Global "track unit on click": ring ONE unit across every plot/tab
        %  Every pick-enabled axes registers its (ax,X,Y,reps) when it draws
        %  (PlotTab.registerRing). A pick routes through trackUnit, which rings
        %  the tracked neuron on ALL registered axes -- overlay only, no data
        %  redraw -- so the unit can be followed across scatter/box plots and tabs.
        % --------------------------------------------------------------- %
        function registerTrackCheck(obj, chk)
            %REGISTERTRACKCHECK  Track a tab's "Track unit on click" checkbox so all
            %   stay in sync, and seed it with the current global state.
            if isempty(chk) || ~isvalid(chk), return; end
            obj.TrackChecks{end+1} = chk;
            chk.Value = obj.TrackEnabled;
        end

        function setTrackEnabled(obj, tf)
            %SETTRACKENABLED  Flip the global "track unit on click" flag, mirror it
            %   onto every registered checkbox, and (when turning off) clear the
            %   tracked unit and every track ring.
            obj.TrackEnabled = logical(tf);
            keep = {};
            for i = 1:numel(obj.TrackChecks)
                c = obj.TrackChecks{i};
                if ~isempty(c) && isvalid(c), c.Value = obj.TrackEnabled; keep{end+1} = c; end %#ok<AGROW>
            end
            obj.TrackChecks = keep;
            if ~obj.TrackEnabled
                obj.TrackedUnit = NaN; obj.reringAll();   % clear all track rings
            end
        end

        function trackUnit(obj, u)
            %TRACKUNIT  Set the globally tracked unit `u` (a D row index) and ring it
            %   on every registered plot. No-op unless tracking is on.
            if ~obj.TrackEnabled, return; end
            if isempty(u) || ~all(isfinite(u)), return; end
            obj.TrackedUnit = u(1);
            obj.reringAll();
        end

        function setTrackWholeUnit(obj, tf)
            %SETTRACKWHOLEUNIT  Choose what "track unit on click" rings: true = every
            %   recorded sample of the neuron (all rows with the same U_unity, the
            %   default); false = only the exact clicked observation. Re-rings now so
            %   the change is visible immediately, and mirrors the filter-panel box.
            obj.TrackWholeUnit = logical(tf);
            if ~isempty(obj.FilterPanelObj)
                try, obj.FilterPanelObj.refreshTrackScope(); catch, end %#ok<CTCH>
            end
            obj.reringAll();
        end

        function registerRingAxes(obj, ax, X, Y, reps)
            %REGISTERRINGAXES  Record a pick-enabled axes (and its plotted X/Y<->reps)
            %   so the tracked unit can be ringed on it later. Replaces any prior
            %   entry for the same axes and prunes dead ones. If a unit is already
            %   tracked, rings it on this freshly-drawn axes right away.
            if isempty(ax) || ~isgraphics(ax) || isempty(reps), return; end
            X = X(:); Y = Y(:); reps = reps(:);
            n = min([numel(X) numel(Y) numel(reps)]);
            if n == 0, return; end
            e = struct('ax', ax, 'X', X(1:n), 'Y', Y(1:n), 'reps', reps(1:n));
            keep = {e};
            for i = 1:numel(obj.RingReg)
                ee = obj.RingReg{i};
                if isempty(ee.ax) || ~isgraphics(ee.ax) || ee.ax == ax, continue; end
                keep{end+1} = ee; %#ok<AGROW>
            end
            obj.RingReg = keep;
            if obj.TrackEnabled && isfinite(obj.TrackedUnit)
                try, viz.plots.V01util.highlightTracked(ax, e.X, e.Y, e.reps, obj.trackedSelsFor(e.reps)); catch, end %#ok<CTCH>
            end
        end

        function reringAll(obj)
            %RERINGALL  (Re)paint the tracked unit's ring on every registered axes;
            %   prunes dead axes. With TrackedUnit = NaN this clears all track rings.
            keep = {};
            for i = 1:numel(obj.RingReg)
                e = obj.RingReg{i};
                if isempty(e.ax) || ~isgraphics(e.ax), continue; end
                try, viz.plots.V01util.highlightTracked(e.ax, e.X, e.Y, e.reps, obj.trackedSelsFor(e.reps)); catch, end %#ok<CTCH>
                keep{end+1} = e; %#ok<AGROW>
            end
            obj.RingReg = keep;
        end

        function sels = trackedSelsFor(obj, reps)
            %TRACKEDSELSFOR  The rep value(s) in `reps` to ring for the tracked unit.
            %   Whole-unit scope (default): every observation of its NEURON (same
            %   U_unity), so the unit is found even in tabs that drew a different
            %   representative row of it. Sample scope (TrackWholeUnit=false): ONLY the
            %   exact clicked row -- so a plot that drew a different sample of the same
            %   neuron rings nothing. [] when nothing is tracked.
            sels = [];
            u = obj.TrackedUnit;
            if isempty(u) || ~isfinite(u), return; end
            reps = reps(:);
            if ~obj.TrackWholeUnit
                sels = reps(reps == u);     % sample scope: just the clicked observation
                return;
            end
            if isfield(obj.D, 'U_unity') && u <= numel(obj.D.U_unity)
                uu = double(obj.D.U_unity);
                sels = reps(ismember(uu(reps), uu(u)));
                if isempty(sels), sels = u; end
            else
                sels = u;
            end
        end

        % --------------------------------------------------------------- %
        %  Persistence: session memory + user-set default
        % --------------------------------------------------------------- %
        function s = getState(obj)
            %GETSTATE  Snapshot of the whole app: global filters, every tab's
            %          filters + controls, active tab, filter-panel visibility.
            s = struct();
            s.global        = obj.GlobalFilters.toStruct();
            s.filterVisible = obj.FilterVisible;
            s.inspectEnabled = obj.InspectEnabled;
            s.trackEnabled  = obj.TrackEnabled;
            s.trackWholeUnit = obj.TrackWholeUnit;
            s.fitOption     = obj.FitOption;
            s.ltmOption     = obj.LTMOption;
            s.originalStyle = ~viz.paperStyle();     % paper-modifications master key
            s.activeTab     = '';
            ct = obj.currentTab();
            if ~isempty(ct), s.activeTab = ct.Name; end
            s.tabs = struct();
            for i = 1:numel(obj.Tabs)
                s.tabs.(matlab.lang.makeValidName(obj.Tabs{i}.Name)) = obj.Tabs{i}.getState();
            end
        end

        function setState(obj, s)
            %SETSTATE  Restore a snapshot produced by getState().
            if isempty(s) || ~isstruct(s), return; end
            if isfield(s,'global')
                obj.GlobalFilters = filter.FilterSet.fromStruct(s.global);
            end
            if isfield(s,'tabs')
                for i = 1:numel(obj.Tabs)
                    key = matlab.lang.makeValidName(obj.Tabs{i}.Name);
                    if isfield(s.tabs, key)
                        obj.Tabs{i}.setState(s.tabs.(key));
                    end
                end
            end
            if isfield(s,'activeTab') && ~isempty(s.activeTab)
                for i = 1:numel(obj.Tabs)
                    if strcmp(obj.Tabs{i}.Name, s.activeTab)
                        obj.TabGroup.SelectedTab = obj.Tabs{i}.Tab; break;
                    end
                end
            end
            if isfield(s,'filterVisible')
                obj.setFilterVisible(logical(s.filterVisible));
            end
            if isfield(s,'inspectEnabled')
                obj.setInspectEnabled(logical(s.inspectEnabled));
            end
            if isfield(s,'trackEnabled')
                obj.setTrackEnabled(logical(s.trackEnabled));
            end
            if isfield(s,'trackWholeUnit')
                obj.setTrackWholeUnit(logical(s.trackWholeUnit));
            end
            if isfield(s,'originalStyle')
                viz.paperStyle(~logical(s.originalStyle));
                if ~isempty(obj.OrigStyleChk) && isvalid(obj.OrigStyleChk)
                    obj.OrigStyleChk.Value = logical(s.originalStyle);
                end
            end
            sFit = obj.FitOption;  sLTM = obj.LTMOption;
            if isfield(s,'fitOption') && ~isempty(s.fitOption), sFit = char(s.fitOption); end
            if isfield(s,'ltmOption') && ~isempty(s.ltmOption), sLTM = char(s.ltmOption); end
            obj.applyFitState(sFit, sLTM);    % refits if either differs; no-op otherwise
            obj.refreshAll();
        end

        function setDefault(obj)
            %SETDEFAULT  Save the current view as the default (Reset restores it).
            obj.DefaultState = obj.getState();
            obj.writeStateField('default', obj.DefaultState);
            if obj.PaperMode, obj.savePaperPages(); end   % same button also saves the paper pages
        end

        function resetToDefault(obj)
            %RESETTODEFAULT  Restore the saved default (or code defaults if none).
            if ~isempty(obj.DefaultState)
                obj.setState(obj.DefaultState);
            else
                obj.GlobalFilters.clear();
                for i = 1:numel(obj.Tabs)
                    obj.Tabs{i}.LocalFilters.clear();
                    obj.Tabs{i}.applyDefaultFilters();
                end
                obj.refreshAll();
            end
            if obj.FilterVisible, obj.FilterPanelObj.refresh(); end
        end

        function resetTabToDefault(obj, tab)
            %RESETTABTODEFAULT  Restore one tab (filters + controls) to default.
            if isempty(tab), return; end
            key = matlab.lang.makeValidName(tab.Name);
            if ~isempty(obj.DefaultState) && isfield(obj.DefaultState,'tabs') ...
                    && isfield(obj.DefaultState.tabs, key)
                tab.setState(obj.DefaultState.tabs.(key));
            else
                tab.LocalFilters.clear();
                tab.applyDefaultFilters();
            end
            obj.refresh();
            if obj.FilterVisible, obj.FilterPanelObj.refresh(); end
        end

        function saveSession(obj)
            %SAVESESSION  Persist the current view as the session (auto on close).
            obj.writeStateField('session', obj.getState());
        end

        function loaded = loadSession(obj)
            %LOADSESSION  Restore the last session (or the default) from disk.
            loaded = false;
            S = obj.readStateFile();
            if isfield(S,'default'), obj.DefaultState = S.default; end
            if isfield(S,'session') && ~isempty(S.session)
                obj.setState(S.session); loaded = true;
            elseif isfield(S,'default') && ~isempty(S.default)
                obj.setState(S.default); loaded = true;
            end
        end

        function onClose(obj)
            %ONCLOSE  Save the session, then close the window (and any tab pop-outs).
            try, obj.saveSession(); catch, end %#ok<CTCH>
            if obj.PaperMode, try, obj.savePaperPages(); catch, end, end %#ok<CTCH>
            for i = 1:numel(obj.Tabs)              % close tab-owned pop-out figures (no-op for most tabs)
                try, obj.Tabs{i}.closePopouts(); catch, end %#ok<CTCH>
            end
            if ~isempty(obj.InspectorObj) && isa(obj.InspectorObj,'viz.plots.UnitInspector')
                try, obj.InspectorObj.close(); catch, end %#ok<CTCH>
            end
            delete(obj.Fig);
        end

        % --------------------------------------------------------------- %
        %  Named filter-set presets (save the global filter set by name)
        % --------------------------------------------------------------- %
        function names = presetNames(obj)
            %PRESETNAMES  Names of all saved filter-set presets (cellstr).
            P = obj.readPresets();
            if isempty(P), names = {}; else, names = {P.name}; end
        end

        function savePreset(obj, name)
            %SAVEPRESET  Save the current GLOBAL filter set under `name`.
            %   Overwrites a preset of the same name. The compound rules
            %   (groups) are captured along with every rule's enabled state.
            name = strtrim(char(name));
            if isempty(name)
                error('viz:Visualizer:preset', 'Preset name cannot be empty.');
            end
            P     = obj.readPresets();
            entry = struct('name', name, 'data', obj.GlobalFilters.toStruct());
            idx   = obj.presetIndex(P, name);
            if isempty(idx), P(end+1) = entry; else, P(idx) = entry; end
            obj.writeStateField('presets', P);
        end

        function tf = loadPreset(obj, name)
            %LOADPRESET  Replace the GLOBAL filter set with saved preset `name`.
            tf  = false;
            P   = obj.readPresets();
            idx = obj.presetIndex(P, char(name));
            if isempty(idx), return; end
            obj.GlobalFilters = filter.FilterSet.fromStruct(P(idx).data);
            obj.refreshAll();
            if obj.FilterVisible, obj.FilterPanelObj.refresh(); end
            tf = true;
        end

        function deletePreset(obj, name)
            %DELETEPRESET  Remove the saved preset named `name` (if present).
            P   = obj.readPresets();
            idx = obj.presetIndex(P, char(name));
            if ~isempty(idx)
                P(idx) = [];
                obj.writeStateField('presets', P);
            end
        end
    end

    methods (Access = private)
        function drawTab(obj, tab)
            tab.update(obj.D, obj.maskFor(tab));
        end

        function mode = writeGraphicsFile(obj, target, outFile)
            %WRITEGRAPHICSFILE  Save `target` to `outFile`, choosing the best format.
            %   A pop-out plot window is written as TRUE VECTOR graphics
            %   (exportgraphics 'ContentType','vector') for .pdf/.eps/.emf, else a
            %   300-dpi image. exportgraphics drops UI components in vector mode, so
            %   any uilabel annotations the window carries (e.g. the Example-units
            %   row / column / delta labels) are first mirrored as vector `text`
            %   (overlayLabelsAsText) and removed again after the write. The whole
            %   app window -- returned for table / inline tabs -- is captured with
            %   exportapp instead: its uitables and uicontrols are UI components with
            %   no vector representation. Returns a short mode string for the dialog.
            [~, ~, ext] = fileparts(outFile);
            if isa(target, 'matlab.ui.Figure') && isequal(target, obj.Fig)
                exportapp(target, outFile);                  % app window: UI components -> raster snapshot
                mode = 'window snapshot'; return;
            end
            ov = obj.overlayLabelsAsText(target);            % vectorize any uilabels first (ExampleUnitsTab)
            oc = onCleanup(@() delete(ov(isgraphics(ov))));  % remove the overlay after the write
            drawnow;
            % Quiet two exportgraphics notes for the duration of the write, restoring
            % the prior state afterwards: (1) "UI components dropped in vector mode" --
            % moot here, the overlay puts the labels back as graphics; (2) the
            % "vector content may be slow" performance suggestion -- vector is the
            % point of this path.
            wstate = warning;                                % snapshot all warning states
            oc2 = onCleanup(@() warning(wstate));            % restore on exit
            warning('off', 'MATLAB:print:ExportappForUIFigureWithUIControl');
            warning('off', 'MATLAB:print:ContentTypeImageSuggested');
            if any(strcmpi(ext, {'.pdf', '.eps', '.emf'}))
                exportgraphics(target, outFile, 'ContentType', 'vector', 'BackgroundColor', 'white');
                mode = 'vector';
            else
                exportgraphics(target, outFile, 'Resolution', 300, 'BackgroundColor', 'white');
                mode = 'image 300 dpi';
            end
        end

        function axo = overlayLabelsAsText(~, fig)
            %OVERLAYLABELSASTEXT  Mirror every uilabel in `fig` as vector `text` on a
            %   transparent full-figure overlay axes, so exportgraphics (which omits
            %   UI components in vector mode) still renders those annotations. Returns
            %   the overlay axes (empty gobjects if the figure has none) for the
            %   caller to delete once the export is written. Best-effort: a label it
            %   cannot reproduce is skipped, never erroring the export.
            axo = gobjects(0);
            L = findall(fig, '-isa', 'matlab.ui.control.Label');
            if isempty(L), return; end
            W = fig.Position(3); H = fig.Position(4);
            if W < 2 || H < 2, return; end
            ax = uiaxes(fig, 'Units', 'pixels', 'Position', [0 0 W H]);
            ax.XLim = [0 W]; ax.YLim = [0 H];
            ax.Color = 'none'; ax.XColor = 'none'; ax.YColor = 'none';
            ax.XTick = []; ax.YTick = []; ax.Box = 'off';
            try, ax.Toolbar.Visible = 'off'; catch, end %#ok<CTCH>
            try, disableDefaultInteractivity(ax); catch, end %#ok<CTCH>
            hold(ax, 'on');
            for i = 1:numel(L)
                Li = L(i);
                if ~isvalid(Li) || strcmp(Li.Visible, 'off'), continue; end
                s = Li.Text;
                if isstring(s), s = cellstr(s); end
                if ischar(s) && any(s == newline), s = strsplit(s, newline); end   % multi-line label
                if ischar(s), isBlank = isempty(strtrim(s));
                else,         isBlank = all(cellfun(@(x) isempty(strtrim(char(x))), s)); end
                if isBlank, continue; end
                p = Li.Position;                                  % [x y w h] px, bottom-left origin
                switch lower(char(Li.HorizontalAlignment))
                    case 'center', tx = p(1) + p(3)/2; ha = 'center';
                    case 'right',  tx = p(1) + p(3);   ha = 'right';
                    otherwise,     tx = p(1);          ha = 'left';
                end
                switch lower(char(Li.VerticalAlignment))
                    case 'top',    ty = p(2) + p(4);   va = 'top';
                    case 'bottom', ty = p(2);          va = 'bottom';
                    otherwise,     ty = p(2) + p(4)/2; va = 'middle';
                end
                try
                    text(ax, tx, ty, s, 'Color', Li.FontColor, 'FontSize', Li.FontSize, ...
                        'FontWeight', Li.FontWeight, 'HorizontalAlignment', ha, ...
                        'VerticalAlignment', va, 'Interpreter', 'none');
                catch
                end
            end
            axo = ax;
        end

        function p = stateFilePath(obj)
            %STATEFILEPATH  Where this app's session/default snapshots live. Keyed
            %   by StateBaseName so a second app (different name) uses its own file.
            here = fileparts(mfilename('fullpath'));   % .../+viz
            p = fullfile(fileparts(here), [obj.StateBaseName '.mat']);   % project root
        end

        function S = readStateFile(obj)
            S = struct();
            p = obj.stateFilePath();
            if exist(p, 'file') == 2
                try, S = load(p); catch, S = struct(); end %#ok<CTCH>
            end
        end

        function writeStateField(obj, field, value)
            %WRITESTATEFIELD  Update one field (session/default) in the state file.
            try
                S = obj.readStateFile();
                S.(field) = value;
                save(obj.stateFilePath(), '-struct', 'S');
            catch err
                warning('viz:Visualizer:save', 'Could not save %s state: %s', field, err.message);
            end
        end

        function P = readPresets(obj)
            %READPRESETS  Load the saved-preset array from the state file.
            %   Always returns a struct array with fields name,data (0x0 if none).
            S = obj.readStateFile();
            if isfield(S, 'presets') && ~isempty(S.presets) ...
                    && isfield(S.presets, 'name')
                P = S.presets;
            else
                P = struct('name', {}, 'data', {});
            end
        end
    end

    methods (Static)
        % Menu lists, label->args mappers, and the startup defaults. Static so a
        % launcher can build the cache args (defaultCacheArgs) before any instance
        % exists; instance code calls them via obj.* exactly as before.
        function L = fitOptionLabels()
            %FITOPTIONLABELS  The selectable analysis.exponentialModel settings.
            %   'No bounds + single seed' matches the LTM's own optimization
            %   (unconstrained, single start point) for a like-for-like comparison.
            L = {'Default (validated)', 'Free floor (3-param)', 'No bounds', ...
                 'Single seed (no multistart)', 'No bounds + single seed', ...
                 'Levenberg-Marquardt'};
        end

        function args = expmArgsFor(label)
            %EXPMARGSFOR  Name/value pairs forwarded to analysis.exponentialModel
            %   (via analysis.computeMetrics 'ExpMArgs') for each I/O menu label.
            switch char(label)
                case 'Free floor (3-param)'
                    args = {'freeFloor', true};
                case 'No bounds'
                    args = {'offsetBounds', [-Inf Inf], 'exponentBounds', [-Inf Inf]};
                case 'Single seed (no multistart)'
                    args = {'multiStart', false};
                case 'No bounds + single seed'      % matches the LTM's unconstrained single-start fit
                    args = {'offsetBounds', [-Inf Inf], 'exponentBounds', [-Inf Inf], 'multiStart', false};
                case 'Levenberg-Marquardt'
                    args = {'Algorithm', 'levenberg-marquardt'};
                otherwise          % 'Default (validated)' and any unknown
                    args = {};
            end
        end

        function L = ltmOptionLabels()
            %LTMOPTIONLABELS  The selectable analysis.linearThresholdModel settings.
            L = {'Default (free floor)', 'PVA floor = 0 (2-param)'};
        end

        function args = ltmArgsFor(label)
            %LTMARGSFOR  Name/value pairs forwarded to analysis.linearThresholdModel
            %   (via analysis.computeMetrics 'LTMArgs') for each LTM menu label.
            switch char(label)
                case 'PVA floor = 0 (2-param)'
                    args = {'floorAtZero', true};
                otherwise          % 'Default (free floor)' and any unknown
                    args = {};
            end
        end

        function args = defaultCacheArgs()
            %DEFAULTCACHEARGS  computeMetrics / computeMetricsCached name/value args
            %   for the STARTUP default fit settings (DefaultFitOption +
            %   DefaultLTMOption). Launchers pass these so the cached metrics match
            %   the toolbar dropdowns and NO refit runs when the window opens:
            %     a = viz.Visualizer.defaultCacheArgs();
            %     D = analysis.computeMetricsCached(D, dm, a{:});
            %   Single source of truth for the startup defaults.
            args = {'ExpMArgs', viz.Visualizer.expmArgsFor(viz.Visualizer.DefaultFitOption), ...
                    'LTMArgs',  viz.Visualizer.ltmArgsFor(viz.Visualizer.DefaultLTMOption)};
        end
    end

    methods (Static, Access = private)
        function idx = presetIndex(P, name)
            %PRESETINDEX  Index of the preset named `name` in P ([] if absent).
            idx = [];
            if isempty(P), return; end
            idx = find(strcmp({P.name}, name), 1);
        end
    end

end
