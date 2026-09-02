classdef ExampleUnitsTab < viz.PlotTab
%EXAMPLEUNITSTAB  Three example units, each shown with the FULL V01 per-unit
%   panel set (raster control, raster laser, polar tuning, centered tuning
%   curve, delta/ratio, control-vs-laser I/O scatter) drawn EXACTLY as the V01
%   dashboard draws them -- shared code in viz.plots.UnitPanels, and each panel
%   sized 1:1 with Dashboard01Tab (same pixel-fraction sizes). The three columns
%   are cleanly aligned rather than copying the dashboard's tiny per-column x
%   quirks (its .11*i vs .12*i offsets), so SIZES match but placement is tidied.
%
%   The TAB holds only the controls; the figure opens in its OWN maximized
%   uifigure (3 columns x 6 panels) and refreshes live.
%
%   CONTROLS
%     * Unit group (TuningG)  -- scopes the selectable units to a group.
%     * Layer(s)              -- restrict to one or more cortical layers (LG).
%     * Animal / Penetration  -- same item names as the V01 dashboard (V01util).
%     * Active plot (1/2/3)   -- which column the Unit dropdown drives.
%     * Unit                  -- the single picker; sets the active column's unit.
%
%   See also: viz.plots.UnitPanels, viz.plots.Dashboard01Tab, viz.plots.V01util

    properties
        groupDD; layerLB; frLB; animalDD; penDD; activeDD; unitDD
        freezeChk = {}                       % 1x3 per-column "freeze" checkboxes
        openBtn; statusLbl
        PlotFig                              % the pop-out figure (empty/invalid when closed)
        LayoutSpec = {}                      % {handle, [fx fy fw fh]} placed in pixels on resize
        colTitles = {}                       % 1x3 per-column unit-id labels
        colDeltas = {}                       % 1x3 per-column dHBW/dOSI/dCV value labels
        rowLblH   = {}                       % 1x6 row-label handles (Control..I/O), repositioned per paper-style
        axLbls    = {}                       % per-panel x/y axis labels (Dashboard V01 wording, dual-mode)
        axRasC = {}; axRasL = {}; axPolar = {}; axTun = {}; axDR = {}; axIO = {}   % 1x3 each
        Pool       double = []               % selectable D row indices (mask & group & layer & animal & pen)
        PoolLabels cell   = {}               % labels parallel to Pool (the unit dropdown Items)
        Slots      double = nan(1,6)         % chosen unit per column (D row index; NaN = empty)
        Active     double = 1                % which column the Unit dropdown drives (1..6)
        Frozen     logical = false(1,6)      % per-column lock: ignore filter/dropdown changes
        Layers     double = []               % selected layer numbers (1..4); [] = all
        FrGroups   cell   = {}               % selected dFr-change group keys (FR_KEYS); {} = all
        % NOTE: animal/pen selection lives in the INHERITED viz.PlotTab.DataSel
        % (struct with animal/pen/tasks) -- do not redeclare it here (name clash).
        LastD = []; LastMask = []
        WantReopen logical = false           % restore-time one-shot: reopen the pop-out figure once the pool is rebuilt
    end

    properties (Constant)
        GROUPS      = {'ALL_UNITS','NO_ORI_ON_PV','NO_ORI_NO_PV','ORI_ON_PV','ORI_NON_PV','ORI_NON_PV_MD','ORI_NON_PV_NL','ORI_NON_PV_U','OUTLIER'};
        LAYER_NAMES = {'SG','G','IG','Deep'};      % maps to V01util.layerNum 1..4
        % dFr-change (laser firing-rate change %) groups. E (suppressed, dFr<0) has 3;
        % I (facilitated, dFr>0) has 4. Bands mirror Dashboard01Tab.drawBoxAndStats.
        FR_ITEMS    = {'(all groups)','E: low','E: medium','E: high','I: low','I: medium','I: high','I: extra high'};
        FR_KEYS     = {'all','E:low','E:medium','E:high','I:low','I:medium','I:high','I:xhigh'};
        ROWLABELS   = {'Control','Laser ON','Polar','Delta / Ratio','Tuning','I/O'};
        COL_E = [0 1 0]; COL_I = [0 0 1];          % per-condition example colors (match V01)
        COLORS_NL = {[254 141 165]/255, [255 173 72]/255, [67 183 194]/255};   % SG/G/IG layer colors,
                                                   % SAME palette as LayerSelectivityChange02Tab (title + writings)
        FONT = 11; LW = 1;              % axis TICK font (already ~matches paper Fig 1's relative size)
        LBLFONT = 13;                   % descriptive writings (axis labels / row labels / column titles):
                                        % BOLD + a bit bigger than the ticks, to match paper Fig 1's label prominence (~1.2x ticks; 15 was too big)
        % per-unit panel positions [fx fy fw fh] AS FRACTIONS OF SCREEN -- the exact
        % Dashboard01Tab.createPanels sizes (same maximized figure + same relayout math),
        % so every plot is the same pixel SIZE as the dashboard's. Only fx changes per column.
        Y_RASC = .80; Y_RASL = .67; Y_POL = .52; Y_DR = .42; Y_TUN = .30; Y_IO = .13;
        W_RAS = .10; H_RAS = .11; W_POL = .08; H_POL = .08;
        W_DR  = .10; H_DR  = .05; W_TUN = .10; H_TUN = .10; W_IO = .10; H_IO = .12;
        COLX  = [.14 .28 .42 .56 .70 .84];         % 6 columns (was 3 at [.40 .60 .80]): the units are
                                                   % shifted LEFT + packed tighter (step .14) so 3 more fit
                                                   % on the right; polar sits at x+.01. NCOL = numel(COLX).
    end

    methods
        function obj = ExampleUnitsTab()
            obj@viz.PlotTab('Example units');
        end

        % --------------------------------------------------------------- %
        function buildControls(obj, parent)
            D = []; if ~isempty(obj.Viz), D = obj.Viz.D; end
            g = uigridlayout(parent, [19 1]);
            g.RowHeight = repmat({'fit'}, 1, 19);
            g.RowHeight{4} = 90; g.RowHeight{6} = 140;     % layer + dFr listboxes
            g.RowHeight{16} = 52; g.RowHeight{19} = '1x';  % freeze checkbox rows (2x3 for 6 plots)
            g.RowSpacing = 4; g.Padding = [8 8 8 8];
            try, g.Scrollable = 'on'; catch, end %#ok<CTCH>

            uilabel(g, 'Text', 'Unit group (TuningG)');
            obj.groupDD = uidropdown(g, 'Items', obj.GROUPS, 'Value', 'ALL_UNITS', ...
                'Tooltip', 'Scope the selectable units to a TuningG group.', ...
                'ValueChangedFcn', @(s,e) obj.onGroupChanged());

            uilabel(g, 'Text', 'Layer(s)');
            obj.layerLB = uilistbox(g, 'Items', obj.layerItems(D), 'Multiselect', 'on', ...
                'Value', '(all layers)', 'Tooltip', 'Restrict selectable units to one or more cortical layers.', ...
                'ValueChangedFcn', @(s,e) obj.onLayerChanged());

            uilabel(g, 'Text', 'dFr change group(s)');
            obj.frLB = uilistbox(g, 'Items', obj.FR_ITEMS, 'Multiselect', 'on', 'Value', '(all groups)', ...
                'Tooltip', sprintf(['Restrict selectable units by laser firing-rate change (%%).\n' ...
                    'E (suppressed):  0-33 low,  33-66 medium,  66-100 high.\n' ...
                    'I (facilitated):  0-33 low,  33-66 medium,  66-100 high,  >100 extra high.\n' ...
                    'Select any combination.']), ...
                'ValueChangedFcn', @(s,e) obj.onFrChanged());

            uilabel(g, 'Text', 'Animal');
            obj.animalDD = uidropdown(g, 'Items', viz.plots.V01util.dsAnimalItems(D), 'Value', '(all)', ...
                'Tooltip', 'Restrict selectable units to one animal (same names as the V01 dashboard).', ...
                'ValueChangedFcn', @(s,e) obj.onAnimalChanged());

            uilabel(g, 'Text', 'Penetration');
            obj.penDD = uidropdown(g, 'Items', viz.plots.V01util.dsPenItems(D, '(all)'), 'Value', '(all)', ...
                'Tooltip', 'Restrict selectable units to one penetration of the chosen animal.', ...
                'ValueChangedFcn', @(s,e) obj.onPenChanged());

            uilabel(g, 'Text', 'Active plot');
            obj.activeDD = uidropdown(g, 'Items', {'Plot 1','Plot 2','Plot 3','Plot 4','Plot 5','Plot 6'}, ...
                'ItemsData', [1 2 3 4 5 6], ...
                'Value', 1, 'Tooltip', 'Which of the six columns the Unit dropdown below controls.', ...
                'ValueChangedFcn', @(s,e) obj.onActiveChanged());

            uilabel(g, 'Text', 'Unit (for active plot)');
            obj.unitDD = uidropdown(g, 'Items', {'(none)'}, 'Value', '(none)', ...
                'Tooltip', 'Sets the unit shown in the active column.', ...
                'ValueChangedFcn', @(s,e) obj.onUnitChanged());

            uilabel(g, 'Text', 'Freeze plot (lock vs filter/dropdown changes)');
            fz = uigridlayout(g, [2 3], 'Padding', [0 0 0 0], 'ColumnSpacing', 4, 'RowSpacing', 2);
            obj.freezeChk = cell(1,6);
            for i = 1:6
                obj.freezeChk{i} = uicheckbox(fz, 'Text', sprintf('Plot %d', i), ...
                    'Tooltip', 'When checked, this column keeps its unit and is NOT redrawn when you change filters/dropdowns. Uncheck to edit it again.', ...
                    'ValueChangedFcn', @(s,e) obj.onFreezeChanged(i));
            end

            obj.openBtn = uibutton(g, 'Text', 'Open figure window', ...
                'ButtonPushedFcn', @(s,e) obj.openFigure());
            obj.statusLbl = uilabel(g, 'Text', '', 'WordWrap', 'on', 'VerticalAlignment', 'top');
        end

        function buildView(obj, parent)
            gg = uigridlayout(parent, [1 1]); gg.Padding = [20 20 20 20];
            q1 = char(8220); q2 = char(8221); em = char(8212); en = char(8211);   % curly quotes + em/en dashes as vars, so a following hex char is not eaten by the \x escape
            uilabel(gg, 'Text', sprintf(['Choose up to six units with the controls on the left ' ...
                '(group / layer / dFr-change / animal / penetration narrow the list), then click ' ...
                q1 'Open figure window' q2 '.\n\nPick the ' q1 'Active plot' q2 ' (1' en '6), ' ...
                'then a ' q1 'Unit' q2 ', to fill that column. Each column shows the full V01 panel ' ...
                'set ' em ' rasters (control / laser), centered tuning, polar, delta/ratio and the ' ...
                'I/O scatter ' em ' at the SAME plot sizes as the V01 dashboard.']), ...
                'HorizontalAlignment', 'center', 'WordWrap', 'on', 'FontSize', 13);
        end

        % --------------------------------------------------------------- %
        function update(obj, D, mask)
            obj.LastD = D; obj.LastMask = mask;
            obj.refreshPool();                       % recompute pool + the unit picker
            obj.redrawIfOpen();
            obj.maybeReopen();                       % honor a restored "figure was open" session (one-shot)
            obj.refreshStatus();
        end

        function closePopouts(obj)
            %CLOSEPOPOUTS  Close the pop-out figure when the app closes, so it does
            %   not orphan and a restored session reopens a single fresh one. The
            %   session is saved BEFORE this runs (Visualizer.onClose), so figOpen is
            %   already recorded. Overrides the no-op viz.PlotTab.closePopouts.
            if ~isempty(obj.PlotFig) && isvalid(obj.PlotFig)
                try, delete(obj.PlotFig); catch, end %#ok<CTCH>
            end
            obj.PlotFig = [];
        end

        % ---- persistence ---------------------------------------------- %
        function s = getControlState(obj)
            % `slots` are D row indices (like Dashboard01Tab's persisted example
            % unit); valid within an unchanged dataset, and any row no longer in the
            % pool is reseeded to a default on restore (refreshUnitPicker).
            % `figOpen` records whether the pop-out figure was SHOWING so the next
            % session reopens it automatically (see setControlState / maybeReopen).
            figOpen = ~isempty(obj.PlotFig) && isvalid(obj.PlotFig);
            s = struct('group', obj.groupDD.Value, 'layers', obj.Layers, 'frGroups', {obj.FrGroups}, ...
                'animal', obj.DataSel.animal, 'pen', obj.DataSel.pen, ...
                'active', obj.Active, 'slots', obj.Slots, 'frozen', obj.Frozen, ...
                'figOpen', figOpen);
        end
        function setControlState(obj, s)
            % Arm the pop-out reopen FIRST, before any restore step that could throw
            % (PlotTab.setState wraps this whole method in try/catch). We do NOT open
            % the figure here -- the pool/slots are not rebuilt yet; update() ->
            % maybeReopen() reopens it once everything is in place. See maybeReopen().
            if isfield(s, 'figOpen'), obj.WantReopen = logical(s.figOpen); end
            if isfield(s, 'group'),  obj.setCtrl(obj.groupDD, s.group); end
            if isfield(s, 'layers'), obj.Layers = double(s.layers(:)'); obj.applyLayersToLB(); end
            if isfield(s, 'frGroups'), obj.FrGroups = s.frGroups; obj.applyFrToLB(); end
            if isfield(s, 'animal'), obj.DataSel.animal = char(string(s.animal)); end
            if isfield(s, 'pen'),    obj.DataSel.pen    = char(string(s.pen)); end
            if isfield(s, 'active') && isscalar(s.active) && s.active >= 1 && s.active <= 6
                obj.Active = double(s.active);
            end
            if isfield(s, 'slots') && ~isempty(s.slots)     % copy up to 6 (older 3-slot saves fill cols 1-3)
                n = min(numel(s.slots), 6); obj.Slots(1:n) = double(s.slots(1:n));
            end
            if isfield(s, 'frozen') && ~isempty(s.frozen)
                n = min(numel(s.frozen), 6); obj.Frozen(1:n) = logical(s.frozen(1:n));
                for i = 1:6
                    if ~isempty(obj.freezeChk{i}) && isvalid(obj.freezeChk{i}), obj.freezeChk{i}.Value = obj.Frozen(i); end
                end
            end
            % reflect the restored animal/pen/active onto the controls (+ cascade pen items)
            if ~isempty(obj.animalDD) && isvalid(obj.animalDD), obj.setCtrl(obj.animalDD, obj.DataSel.animal); end
            if ~isempty(obj.penDD) && isvalid(obj.penDD)
                obj.penDD.Items = viz.plots.V01util.dsPenItems(obj.Viz.D, obj.DataSel.animal);
                obj.setCtrl(obj.penDD, obj.DataSel.pen);
            end
            if ~isempty(obj.activeDD) && isvalid(obj.activeDD), obj.setCtrl(obj.activeDD, obj.Active); end
        end

        % ---- paper-figure tool hooks: native (vector) redraw of the yyaxis --- %
        % delta/ratio (RT/dT) panels. copyobj can't clone a 2-ruler axes, so without
        % these the paper tool snapshots them as a uiimage that exportgraphics drops
        % from vector PDFs (the "3A single-unit delta/ratio missing from PDF" bug).
        function [kind, slot] = specForAxes(obj, ax)
            kind = ''; slot = 0;
            for i = 1:numel(obj.axDR)
                if ~isempty(obj.axDR{i}) && isvalid(obj.axDR{i}) && isequal(ax, obj.axDR{i})
                    kind = 'dr'; slot = i; return;
                end
            end
        end
        function paperDraw(obj, ax, kind, slot)
            %PAPERDRAW  Redraw the delta/ratio panel for column SLOT into external AX.
            if ~strcmp(kind, 'dr') || isempty(obj.LastD), return; end
            if slot < 1 || slot > numel(obj.Slots), return; end
            u = obj.Slots(slot);
            if isempty(u) || ~isfinite(u) || u < 1 || u > viz.plots.V01util.nU(obj.LastD), return; end
            viz.plots.UnitPanels.deltaRatio(ax, obj.LastD, u, slot == 1);   % RT/dT labels on the first column
        end
    end

    % =================================================================== %
    methods (Access = private)
        function refreshStatus(obj)
            isOpen = ~isempty(obj.PlotFig) && isvalid(obj.PlotFig);
            if isOpen, obj.statusLbl.Text = 'window: open'; else, obj.statusLbl.Text = 'window: closed (click Open)'; end
        end
        function redrawIfOpen(obj)
            if ~isempty(obj.PlotFig) && isvalid(obj.PlotFig), obj.drawFigure(); end
        end
        function maybeReopen(obj)
            %MAYBEREOPEN  One-shot: if a restored session had the pop-out figure
            %   open (WantReopen, armed by setControlState), reopen it now that the
            %   pool/slots are rebuilt. The flag is consumed only ONCE the figure is
            %   actually open, so a transient first-pass draw error can still be
            %   retried by the next update() pass; once consumed, normal redraws and
            %   a user's manual close are never overridden. Guarded so a restore can
            %   never break the app launch.
            if ~obj.WantReopen, return; end
            if isempty(obj.LastD), return; end                       % not ready yet -> keep the flag for the next pass
            if ~isempty(obj.PlotFig) && isvalid(obj.PlotFig)
                obj.WantReopen = false; return;                      % already open -> just consume the flag
            end
            try
                obj.openFigure();
                obj.WantReopen = false;                              % consume only after it actually opened
            catch
            end
        end

        % ---- layer / animal / penetration filtering ------------------- %
        function items = layerItems(obj, D)
            present = {};
            if ~isempty(D) && isfield(D, 'LG')
                ln = viz.plots.V01util.layerNum(D);
                for k = 1:numel(obj.LAYER_NAMES)
                    if any(ln == k), present{end+1} = obj.LAYER_NAMES{k}; end %#ok<AGROW>
                end
            end
            items = [{'(all layers)'}, present];
        end
        function m = layerMask(obj, D, N)
            if isempty(obj.Layers), m = true(N,1); return; end
            m = ismember(viz.plots.V01util.layerNum(D), obj.Layers); m = m(:);
        end
        function applyLayersToLB(obj)
            if isempty(obj.layerLB) || ~isvalid(obj.layerLB), return; end
            sel = obj.Layers(obj.Layers >= 1 & obj.Layers <= 4);
            names = obj.LAYER_NAMES(sel);
            names = names(ismember(names, obj.layerLB.Items));
            if isempty(names), obj.layerLB.Value = '(all layers)'; obj.Layers = [];
            else,              obj.layerLB.Value = names; end
        end
        function onLayerChanged(obj)
            v = obj.layerLB.Value;
            if ischar(v), v = {v}; elseif isstring(v), v = cellstr(v); end
            if isempty(v) || any(strcmp(v, '(all layers)'))
                obj.Layers = [];
            else
                nums = [];
                for k = 1:numel(v)
                    idx = find(strcmp(obj.LAYER_NAMES, v{k}), 1);
                    if ~isempty(idx), nums(end+1) = idx; end %#ok<AGROW>
                end
                obj.Layers = nums;
            end
            obj.resetUnfrozenSlots();               % pool changed -> reseed the columns
            obj.refreshPool(); obj.redrawIfOpen();
        end

        % ---- dFr-change group filtering (E: 3 bands, I: 4 bands) ------- %
        function m = frGroupMask(obj, D, N)
            if isempty(obj.FrGroups), m = true(N,1); return; end
            dfr = 100 * viz.plots.V01util.colv(D, 'Delta_Fr', N);   % laser FR change (%)
            isI = viz.plots.V01util.isInhib(D);
            m = false(N,1);
            for k = 1:numel(obj.FrGroups)
                switch obj.FrGroups{k}                              % bands mirror the dashboard box groups
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
        function onFrChanged(obj)
            v = obj.frLB.Value;
            if ischar(v), v = {v}; elseif isstring(v), v = cellstr(v); end
            if isempty(v) || any(strcmp(v, '(all groups)'))
                obj.FrGroups = {};
            else
                keys = {};
                for k = 1:numel(v)
                    idx = find(strcmp(obj.FR_ITEMS, v{k}), 1);    % display label -> key (idx 1 = '(all groups)')
                    if ~isempty(idx) && idx >= 2, keys{end+1} = obj.FR_KEYS{idx}; end %#ok<AGROW>
                end
                obj.FrGroups = keys;
            end
            obj.resetUnfrozenSlots();
            obj.refreshPool(); obj.redrawIfOpen();
        end
        function onAnimalChanged(obj)
            obj.DataSel.animal = obj.animalDD.Value;
            if ~isempty(obj.penDD) && isvalid(obj.penDD)   % cascade the penetration list
                obj.penDD.Items = viz.plots.V01util.dsPenItems(obj.Viz.D, obj.DataSel.animal);
                obj.penDD.Value = '(all)'; obj.DataSel.pen = '(all)';
            end
            obj.resetUnfrozenSlots();
            obj.refreshPool(); obj.redrawIfOpen();
        end
        function onPenChanged(obj)
            obj.DataSel.pen = obj.penDD.Value;
            obj.resetUnfrozenSlots();
            obj.refreshPool(); obj.redrawIfOpen();
        end
        function onGroupChanged(obj)
            obj.resetUnfrozenSlots();
            obj.refreshPool(); obj.redrawIfOpen();
        end

        % ---- selectable pool + the single unit picker ----------------- %
        function refreshPool(obj)
            D = obj.LastD; mask = obj.LastMask;
            if isempty(D), obj.Pool = []; obj.refreshUnitPicker(); return; end
            N = viz.plots.V01util.nU(D);
            if isempty(mask), mask = true(N,1); end
            try, grpMask = analysis.tuningGroupMask(D, obj.groupDD.Value);
            catch, grpMask = true(N,1); end %#ok<CTCH>
            lay = obj.layerMask(D, N);
            fr  = obj.frGroupMask(D, N);
            am  = viz.plots.V01util.dsAnimalMask(D, N, obj.DataSel.animal);
            pm  = true(N,1); pv = viz.plots.V01util.dsPenVal(obj.DataSel.pen);
            if isfield(D, 'Penetration') && ~isnan(pv), pm = (double(D.Penetration(:)) == pv); end
            obj.Pool = find(mask(:) & grpMask(:) & lay(:) & fr(:) & am(:) & pm(:));
            obj.refreshUnitPicker();
        end
        function refreshUnitPicker(obj)
            D = obj.LastD; pool = obj.Pool(:)';
            if isempty(pool)
                obj.PoolLabels = {}; obj.Slots(~obj.Frozen) = NaN;   % keep frozen units
                obj.syncUnitDD();
                return;
            end
            obj.PoolLabels = arrayfun(@(u) obj.unitLabel(D, u), pool, 'UniformOutput', false);
            for i = 1:6                               % reseed any invalid (non-frozen) slot to a default
                if obj.Frozen(i), continue; end       % frozen columns keep their unit regardless of the pool
                if isempty(obj.Slots(i)) || ~ismember(obj.Slots(i), pool)
                    obj.Slots(i) = pool(min(i, numel(pool)));
                end
            end
            obj.syncUnitDD();
        end
        function syncUnitDD(obj)
            if isempty(obj.unitDD) || ~isvalid(obj.unitDD), return; end
            a = obj.Active; pool = obj.Pool(:)';
            if obj.Frozen(a)                          % locked column: show its unit, picker disabled
                u = obj.Slots(a);
                if isfinite(u), lbl = obj.unitLabel(obj.LastD, u); else, lbl = '(none)'; end
                obj.unitDD.Items = {lbl}; obj.unitDD.Value = lbl; obj.unitDD.Enable = 'off';
                return;
            end
            obj.unitDD.Enable = 'on';
            if isempty(pool), obj.unitDD.Items = {'(none)'}; obj.unitDD.Value = '(none)'; return; end
            k = find(pool == obj.Slots(a), 1);
            if isempty(k), k = 1; obj.Slots(a) = pool(1); end
            obj.unitDD.Items = obj.PoolLabels; obj.unitDD.Value = obj.PoolLabels{k};
        end
        function onActiveChanged(obj)
            obj.Active = obj.activeDD.Value;          % numeric 1..3 (ItemsData)
            before = obj.Slots(obj.Active); obj.syncUnitDD();   % show the active column's unit (+ frozen/enable)
            if ~isequaln(obj.Slots(obj.Active), before)
                obj.redrawColumnIfOpen(obj.Active);   % syncUnitDD snapped a stale slot -> keep figure in step
            end
        end
        function onFreezeChanged(obj, i)
            obj.Frozen(i) = logical(obj.freezeChk{i}.Value);
            if ~obj.Frozen(i)                         % just unfroze column i: reconcile its slot to the pool
                before = obj.Slots(i); pool = obj.Pool(:)';
                if ~ismember(obj.Slots(i), pool)      % its unit may have left the pool while frozen
                    if ~isempty(pool), obj.Slots(i) = pool(min(i, numel(pool))); else, obj.Slots(i) = NaN; end
                end
                if ~isequaln(obj.Slots(i), before), obj.redrawColumnIfOpen(i); end
            end
            if i == obj.Active, obj.syncUnitDD(); end  % refresh the picker enable/label for the active column
        end
        function resetUnfrozenSlots(obj)
            obj.Slots(~obj.Frozen) = NaN;             % a filter change reseeds only the unfrozen columns
        end
        function onUnitChanged(obj)
            if obj.Frozen(obj.Active), return; end     % frozen column ignores the picker (it is also disabled)
            pool = obj.Pool(:)';
            k = find(strcmp(obj.unitDD.Items, obj.unitDD.Value), 1);   % label -> pool index -> unit
            if isempty(k) || isempty(pool) || k > numel(pool), return; end
            obj.Slots(obj.Active) = pool(k);
            obj.redrawColumnIfOpen(obj.Active);       % only the active column changed
        end

    end

    methods   % PUBLIC: openFigure is exposed (like the other figure tabs) so the
              % toolbar's "Save PDF" can open + draw the pop-out before capturing it.
        % ---- the pop-out figure (dashboard-exact pixel layout) -------- %
        function openFigure(obj)
            if ~isempty(obj.PlotFig) && isvalid(obj.PlotFig)
                figure(obj.PlotFig); obj.drawFigure(); obj.refreshStatus(); return;
            end
            obj.PlotFig = uifigure('Name', 'Example units - V01 panels', 'Color', 'w', ...
                'Position', obj.defaultFigPos());
            obj.PlotFig.CloseRequestFcn = @(s,e) delete(s);
            obj.LayoutSpec = {};
            obj.createPanels();
            try, obj.PlotFig.AutoResizeChildren = 'off'; catch, end %#ok<CTCH>
            obj.PlotFig.SizeChangedFcn = @(s,e) obj.relayout();
            obj.relayout(); obj.drawFigure(true); obj.refreshStatus();   % first draw: every column, even frozen
        end
    end

    methods (Access = private)
        function pos = defaultFigPos(~)
            ss = get(0, 'screensize');               % maximized like the V01 dashboard figure f
            pos = [0, round(.03*ss(4)), ss(3), round(.95*ss(4))];
        end
        function createPanels(obj)
            nc = numel(obj.COLX);
            obj.colTitles = cell(1,nc); obj.colDeltas = cell(1,nc);
            obj.axRasC = cell(1,nc); obj.axRasL = cell(1,nc); obj.axPolar = cell(1,nc);
            obj.axTun  = cell(1,nc); obj.axDR   = cell(1,nc); obj.axIO    = cell(1,nc);
            for i = 1:nc
                x = obj.COLX(i);
                obj.axRasC{i}  = obj.addAx(x,       obj.Y_RASC, obj.W_RAS, obj.H_RAS);   % control raster
                obj.axRasL{i}  = obj.addAx(x,       obj.Y_RASL, obj.W_RAS, obj.H_RAS);   % laser raster
                obj.axPolar{i} = obj.addPolar(x+.01, obj.Y_POL, obj.W_POL, obj.H_POL);   % polar (centered)
                obj.axDR{i}    = obj.addAx(x,       obj.Y_DR,  obj.W_DR,  obj.H_DR);     % delta/ratio
                obj.axTun{i}   = obj.addAx(x,       obj.Y_TUN, obj.W_TUN, obj.H_TUN);    % tuning
                obj.axIO{i}    = obj.addAx(x,       obj.Y_IO,  obj.W_IO,  obj.H_IO);     % I/O
                % title sits in the .915-.945 band (just above the .91 raster top); keep
                % fy+fh <= .95 so relayout never pushes it past the figure top edge.
                obj.colTitles{i} = obj.addLabel(x, .915, .13, .03, '(none)', 'center', obj.LBLFONT, true);
                % dHBW/dOSI/dCV values just below the I/O panel (bottom of the column),
                % colored per LAYER like LayerSelectivityChange02Tab.
                obj.colDeltas{i} = obj.addLabel(x, .005, .13, .115, '', 'left', obj.FONT-1, false);
                obj.colDeltas{i}.VerticalAlignment = 'top';
            end
            obj.createRowLabels();
            obj.createAxisLabels();
        end
        function createAxisLabels(obj)
            %CREATEAXISLABELS  Per-panel x/y axis labels with the Dashboard V01 wording,
            %   dual-mode (original text <-> paper text via the master style key), so the
            %   Example-units figure carries the same writings. Rotated y-labels sit just
            %   left of column 1; x-labels are centred under the 3 columns. Positioned +
            %   retuned in applyLayout. Each is a text in an invisible uiaxes (so it
            %   rotates and is captured by exportgraphics, unlike a uilabel).
            %   spec cols: {panelKey, isY, origText, paperText, hideInPaper}
            S = { ...
              'ras', true,  'Drift Direction',                 'Trials/drift direction',       false; ...
              'ras', false, 'Time(s)',                         'Time from stimulus onset (s)', false; ...
              'tun', true,  'Firing Rate (spk/s)',             'Response (spk/s)',             false; ...
              'tun', false, 'Drift Direction',                 'Drift direction',              false; ...
              'io',  true,  'Pyr Cell response, Laser ON (%)', 'Response (%) laser',           false; ...
              'io',  false, 'Pyr Cell response, Control (%)',  'Response (%) Control',         false; ...
              'dr',  true,  'Ratio Delta',                     '',                             true  ...
            };
            obj.axLbls = cell(1, size(S,1));
            for k = 1:size(S,1)
                isY = S{k,2}; rot = 0; if isY, rot = 90; end
                ax = uiaxes(obj.PlotFig); ax.Units = 'pixels'; ax.Visible = 'off';
                th = text(ax, 0.5, 0.5, S{k,3}, 'Units','normalized', 'Rotation',rot, ...
                    'FontUnits','points', 'FontSize',obj.LBLFONT, 'FontWeight','bold', ...
                    'HorizontalAlignment','center', ...
                    'VerticalAlignment','middle', 'Interpreter','none', 'Color','k');
                obj.axLbls{k} = struct('ax',ax, 't',th, 'panel',S{k,1}, 'isY',isY, ...
                    'orig',S{k,3}, 'paper',S{k,4}, 'hide',S{k,5});
            end
        end
        function createRowLabels(obj)
            ys = [obj.Y_RASC obj.Y_RASL obj.Y_POL obj.Y_DR obj.Y_TUN obj.Y_IO];
            hs = [obj.H_RAS  obj.H_RAS  obj.H_POL obj.H_DR obj.H_TUN obj.H_IO];
            lx = 0.002;                                % row labels sit in the far-left margin (repositioned in applyLayout)
            obj.rowLblH = cell(1, numel(obj.ROWLABELS));
            for r = 1:numel(obj.ROWLABELS)            % vertically centered against each panel
                obj.rowLblH{r} = obj.addLabel(lx, ys(r), .14, hs(r), obj.ROWLABELS{r}, 'right', obj.LBLFONT, true);
            end
        end
        function y = rowYs(obj)
            %ROWYS  Per-panel bottom-y (screen fraction) for the current style. PAPER
            %   mode = paper Fig 1 per-unit order (rasters, tuning, RT/dT, I/O, then the
            %   circular/polar tuning at the bottom); otherwise the ORIGINAL layout so
            %   the non-paper appearance is unchanged.
            if viz.paperStyle()
                y = struct('rasC',.80, 'rasL',.68, 'tun',.55, 'dr',.47, 'io',.31, 'pol',.16);
            else
                y = struct('rasC',obj.Y_RASC, 'rasL',obj.Y_RASL, 'pol',obj.Y_POL, ...
                           'dr',obj.Y_DR, 'tun',obj.Y_TUN, 'io',obj.Y_IO);
            end
        end
        function applyLayout(obj)
            %APPLYLAYOUT  Position the per-column panels + row labels for the current
            %   paper-style (rowYs). Runs every relayout, so toggling the master key
            %   re-arranges the columns live. Sizes (w,h) are the same in both modes.
            if isempty(obj.PlotFig) || ~isvalid(obj.PlotFig), return; end
            pos = obj.PlotFig.Position; W = pos(3); H = pos(4);
            if W < 30 || H < 30, return; end
            y = obj.rowYs();
            place = @(h, fx, fy, fw, fh) set(h, 'Position', ...
                [fx*W, (fy/0.95)*H, max(2, fw*W), max(2, (fh/0.95)*H)]);
            for i = 1:numel(obj.COLX)
                x = obj.COLX(i);
                if ~isempty(obj.axRasC{i})  && isvalid(obj.axRasC{i}),  place(obj.axRasC{i},  x,      y.rasC, obj.W_RAS, obj.H_RAS); end
                if ~isempty(obj.axRasL{i})  && isvalid(obj.axRasL{i}),  place(obj.axRasL{i},  x,      y.rasL, obj.W_RAS, obj.H_RAS); end
                if ~isempty(obj.axPolar{i}) && isvalid(obj.axPolar{i}), place(obj.axPolar{i}, x+.01,  y.pol,  obj.W_POL, obj.H_POL); end
                if ~isempty(obj.axDR{i})    && isvalid(obj.axDR{i})
                    drH = obj.H_DR; drY = y.dr;
                    if viz.paperStyle(), drH = obj.H_DR*1.3; drY = y.dr - 0.5*(drH-obj.H_DR); end   % paper: delta/ratio 1.3x taller (x-arrows made it look short), centred
                    place(obj.axDR{i}, x, drY, obj.W_DR, drH);
                end
                if ~isempty(obj.axTun{i})   && isvalid(obj.axTun{i}),   place(obj.axTun{i},   x,      y.tun,  obj.W_TUN, obj.H_TUN); end
                if ~isempty(obj.axIO{i})    && isvalid(obj.axIO{i}),    place(obj.axIO{i},    x,      y.io,   obj.W_IO,  obj.H_IO); end
            end
            lx = 0.002;                                       % row TAGS at the far-left margin (6-col layout leaves little room)
            keys = {'rasC','rasL','pol','dr','tun','io'};     % parallel to ROWLABELS
            hs   = [obj.H_RAS obj.H_RAS obj.H_POL obj.H_DR obj.H_TUN obj.H_IO];
            for r = 1:numel(obj.rowLblH)
                h = obj.rowLblH{r}; if isempty(h) || ~isvalid(h), continue; end
                place(h, lx, y.(keys{r}), .075, hs(r));       % right edge ~.077, just left of the y-axis labels (.095)
            end
            obj.placeAxisLabels(y, place);                    % Dashboard-matching x/y axis labels
        end
        function placeAxisLabels(obj, y, place)
            %PLACEAXISLABELS  Position + retune the per-panel x/y axis labels (axLbls) for
            %   the current style. y-labels rotated just left of column 1; x-labels
            %   centred under the 3 columns, below their panel. Text follows the master
            %   key (paper wording in paper style; hidden if hide=true, e.g. Ratio Delta).
            paper = viz.paperStyle();
            lyx = obj.COLX(1) - 0.045;                                  % y-labels just left of column 1
            cx0 = obj.COLX(1); cxw = obj.COLX(end) + obj.W_IO - obj.COLX(1);   % x-labels span all columns
            for k = 1:numel(obj.axLbls)
                s = obj.axLbls{k}; if isempty(s) || ~isvalid(s.ax) || ~isvalid(s.t), continue; end
                if paper && s.hide, s.t.Visible = 'off'; continue; end
                s.t.Visible = 'on';
                s.t.String = s.orig; if paper, s.t.String = s.paper; end
                switch s.panel                                          % panel geometry per style (rowYs)
                    case 'ras', pfy = y.rasL; pfh = (y.rasC + obj.H_RAS) - y.rasL; xfy = y.rasL - 0.035;
                    case 'tun', pfy = y.tun;  pfh = obj.H_TUN;  xfy = y.tun - 0.025;
                    case 'io',  pfy = y.io;   pfh = obj.H_IO;   xfy = y.io  - 0.035;
                    case 'dr',  pfy = y.dr;   pfh = obj.H_DR;   xfy = y.dr  - 0.02;
                    otherwise,  pfy = 0.5; pfh = 0.1; xfy = 0.4;
                end
                if s.isY, place(s.ax, lyx, pfy, 0.04, pfh);             % rotated y-label left of col 1
                else,     place(s.ax, cx0, xfy, cxw,  0.025); end       % x-label centred under the columns
            end
        end
        function ax = addAx(obj, fx, fy, fw, fh)
            ax = uiaxes(obj.PlotFig); ax.Units = 'pixels'; ax.FontUnits = 'points';
            ax.FontSize = obj.FONT; ax.LineWidth = obj.LW;
            obj.LayoutSpec{end+1} = {ax, [fx fy fw fh]};
        end
        function ax = addPolar(obj, fx, fy, fw, fh)
            ax = polaraxes(obj.PlotFig); ax.Units = 'pixels'; ax.FontUnits = 'points';
            ax.FontSize = obj.FONT; ax.LineWidth = obj.LW;
            obj.LayoutSpec{end+1} = {ax, [fx fy fw fh]};
        end
        function lbl = addLabel(obj, fx, fy, fw, fh, txt, halign, fsz, bold)
            lbl = uilabel(obj.PlotFig, 'Text', txt, 'HorizontalAlignment', halign, ...
                'VerticalAlignment', 'center', 'Interpreter', 'none', 'FontSize', fsz);
            if bold, lbl.FontWeight = 'bold'; end
            obj.LayoutSpec{end+1} = {lbl, [fx fy fw fh]};
        end
        function relayout(obj)
            if isempty(obj.PlotFig) || ~isvalid(obj.PlotFig), return; end
            pos = obj.PlotFig.Position; W = pos(3); H = pos(4);
            if W < 30 || H < 30, return; end
            for k = 1:numel(obj.LayoutSpec)
                h = obj.LayoutSpec{k}{1}; fr = obj.LayoutSpec{k}{2};
                if isempty(h) || ~isvalid(h), continue; end
                try, h.Position = [fr(1)*W, (fr(2)/0.95)*H, max(2,fr(3)*W), max(2,(fr(4)/0.95)*H)]; catch, end %#ok<CTCH>
            end
            obj.applyLayout();   % paper-style panel/row-label positions override the LayoutSpec defaults
        end
        % equalize the DATA-area width of tuning / delta-ratio (V01 matchPlotWidths
        % TightInset trick) so the stacked curves line up on x, exactly like the dashboard.
        function matchPlotWidths(obj)
            if isempty(obj.PlotFig) || ~isvalid(obj.PlotFig), return; end
            inner = 0.08 * obj.PlotFig.Position(3);
            grp = [obj.axTun, obj.axDR];
            for k = 1:numel(grp)
                ax = grp{k}; if isempty(ax) || ~isvalid(ax), continue; end
                try, ti = ax.TightInset; p = ax.Position; ax.Position = [p(1), p(2), inner + ti(1) + ti(3), p(4)]; catch, end %#ok<CTCH>
            end
        end

        % ---- drawing -------------------------------------------------- %
        function drawFigure(obj, force)
            % force=true draws every column (used on first open); otherwise FROZEN
            % columns are left exactly as they are (the freeze feature).
            if nargin < 2 || isempty(force), force = false; end
            D = obj.LastD;
            if isempty(D) || isempty(obj.PlotFig) || ~isvalid(obj.PlotFig), return; end
            obj.relayout();
            for i = 1:numel(obj.COLX)
                if ~force && obj.Frozen(i), continue; end
                obj.drawColumn(D, i, obj.Slots(i));
            end
            obj.matchPlotWidths();
        end
        function redrawColumnIfOpen(obj, slot)
            if isempty(obj.PlotFig) || ~isvalid(obj.PlotFig), return; end
            obj.drawColumn(obj.LastD, slot, obj.Slots(slot));
            obj.matchPlotWidths();
        end
        function drawColumn(obj, D, i, u)
            obj.clearCol(i);
            % Treat an out-of-range row like empty: a FROZEN slot keeps its saved
            % D-row index without pool validation, so a session restored against a
            % smaller dataset could otherwise index past D's per-unit arrays.
            if isempty(u) || ~isfinite(u) || u < 1 || u > viz.plots.V01util.nU(D)
                if ~isempty(obj.colTitles{i}) && isvalid(obj.colTitles{i})
                    obj.colTitles{i}.Text = sprintf('Plot %d: (none)', i); obj.colTitles{i}.FontColor = [0 0 0];
                end
                if ~isempty(obj.colDeltas{i}) && isvalid(obj.colDeltas{i}), obj.colDeltas{i}.Text = ''; end
                return;
            end
            if viz.plots.UnitPanels.isInhibUnit(D, u), Cc = obj.COL_I; else, Cc = obj.COL_E; end
            % drawAll(axLaser, axControl, axTun, axPolar, axDR, D, u, Cc) -- the 5 tuning panels
            viz.plots.UnitPanels.drawAll(obj.axRasL{i}, obj.axRasC{i}, obj.axTun{i}, ...
                obj.axPolar{i}, obj.axDR{i}, D, u, Cc, i==1);   % legend / RT-dT labels once, on column 1
            viz.plots.UnitPanels.io(obj.axIO{i}, D, u);                            % the 6th panel (io() guards internally)
            cLayer = obj.layerColor(D, u);     % layer color (LayerSelectivityChange palette) for title + dFr writings
            if ~isempty(obj.colTitles{i}) && isvalid(obj.colTitles{i})
                obj.colTitles{i}.Text = obj.unitLabel(D, u); obj.colTitles{i}.FontColor = cLayer;
            end
            if ~isempty(obj.colDeltas{i}) && isvalid(obj.colDeltas{i})
                obj.colDeltas{i}.Text = obj.deltaText(D, u); obj.colDeltas{i}.FontColor = cLayer;
            end
        end
        function clearCol(obj, i)
            for ax = [obj.axRasC(i) obj.axRasL(i) obj.axTun(i) obj.axIO(i)]
                if ~isempty(ax{1}) && isvalid(ax{1}), cla(ax{1}); end
            end
            try, cla(obj.axPolar{i}); catch, end %#ok<CTCH>
            try                                            % delta/ratio uses yyaxis -> clear both sides
                yyaxis(obj.axDR{i}, 'left');  cla(obj.axDR{i});
                yyaxis(obj.axDR{i}, 'right'); cla(obj.axDR{i});
            catch
                try, cla(obj.axDR{i}); catch, end %#ok<CTCH>
            end
        end
        function s = unitLabel(~, D, u)
            uu = NaN; if isfield(D,'U_unity') && numel(D.U_unity) >= u, uu = double(D.U_unity(u)); end
            ei = '';  if isfield(D,'EI') && numel(D.EI) >= u, ei = char(strtrim(string(D.EI(u)))); end
            lg = '';  if isfield(D,'LG') && numel(D.LG) >= u, lg = char(strtrim(string(D.LG(u)))); end
            s = sprintf('#%d   U=%g   %s   %s', u, uu, ei, lg);
        end
        function c = layerColor(obj, D, u)
            %LAYERCOLOR  Per-LAYER color (SG/G/IG = LayerSelectivityChange02Tab's
            %   COLORS_NL); Deep / unknown layer falls back to near-black.
            ln = NaN;
            if isfield(D,'LG') && numel(D.LG) >= u
                idx = find(strcmpi({'SG','G','IG','Deep'}, char(strtrim(string(D.LG(u))))), 1);
                if ~isempty(idx), ln = idx; end
            end
            if isfinite(ln) && ln <= 3, c = obj.COLORS_NL{ln}; else, c = [0.15 0.15 0.15]; end
        end
        function txt = deltaText(~, D, u)
            %DELTATEXT  3-line dHBW/dOSI/dCV readout for unit u ('-' for missing).
            DD = char(916);                                  % Greek capital delta
            f  = @viz.plots.ExampleUnitsTab.fieldAt;
            fm = @viz.plots.ExampleUnitsTab.fmt;
            txt = sprintf('%sHBW = %s\n%sOSI = %s\n%sCV = %s', ...
                DD, fm(f(D,'Delta_HBW',u),1), DD, fm(f(D,'Delta_OSI',u),3), DD, fm(f(D,'Delta_CV',u),3));
        end
    end

    methods (Static, Access = private)
        function v = fieldAt(D, name, u)
            v = NaN; if isfield(D,name) && numel(D.(name)) >= u, v = double(D.(name)(u)); end
        end
        function s = fmt(x, dec)
            if isempty(x) || ~isfinite(x), s = '-'; else, s = sprintf('%.*f', dec, x); end
        end
    end
end
