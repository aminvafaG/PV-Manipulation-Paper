classdef FilterPanel < handle
%FILTERPANEL  The global, normally-hidden filter & control panel.
%
%   One instance lives in the Visualizer and is shown/hidden from the toolbar
%   (accessible from any tab). It lets you:
%     * pick a variable, operator and value(s),
%     * optionally put the rule in a named GROUP -- rules in the same group are
%       combined by that group's mode (AND by default, or OR) and the groups are
%       ORed together, so you can express e.g. "E cells with CV in [a b]  OR
%       I cells with CV in [c d]" (give the E rules group "E" and the I rules
%       group "I"); ungrouped rules stay always-on baseline constraints,
%     * OR (or AND) any pair/set of rules in one click: select them in the
%       active-rules table and press "OR selected" / "AND selected" (or
%       "Ungroup" to send them back to the baseline),
%     * choose whether the rule is GLOBAL (all tabs) or LOCAL (current tab),
%     * add the rule,
%     * see every active rule (variable, type, operator, value/limits, group,
%       scope) in one table, toggle/remove them, and reset, and
%     * save the current global filters as a NAMED set and reload it later.
%
%   It edits two things owned elsewhere:
%       obj.Viz.GlobalFilters         (a filter.FilterSet shared by all tabs)
%       obj.Viz.currentTab.LocalFilters (that tab's own filter.FilterSet)
%   and asks the Visualizer to redraw after any change.
%
%   See also: viz.Visualizer, viz.PlotTab, filter.FilterSet, filter.FilterRule

    properties
        Viz                      % back-reference to the viz.Visualizer
        Panel                    % the uipanel we build into
        VarDD                    % variable dropdown
        OpDD                     % operator dropdown
        ValField                 % value edit field
        ExcludeField             % "exclude units by #" edit field
        TrackScopeField          % "track click scope" numeric field (0 = clicked sample only)
        GroupDD                  % group label (editable: type a new one or pick)
        ScopeDD                  % 'Global' | 'Local'
        RulesTable               % active-rules display (uitable)
        PresetDD                 % saved filter-set names (editable dropdown)
        SummaryArea              % read-only text summary
        VarNames = {}            % cached filterable variable names
        VarTypes = {}            % matching types
        RowMap   = struct('scope',{},'idx',{})  % table row -> (set, index)
    end

    properties (Constant)
        ExcludeVar = 'UnitIndex'  % per-unit number the "Exclude units" box drops
    end

    methods
        function obj = FilterPanel(vizApp)
            obj.Viz = vizApp;
        end

        function build(obj, parent)
            %BUILD  Create all controls inside the host panel `parent`.
            obj.Panel = parent;
            g = uigridlayout(parent, [20 2]);
            g.RowHeight   = {22, 26, 26, 26, 26, 26, 30, ...
                             22, 30, ...                       % Exclude units
                             20, '1x', 28, ...                 % rules table + combine row
                             28, 28, 28, 22, 26, 28, ...
                             26, 60};                          % Track scope + summary
            g.ColumnWidth = {'fit','1x'};
            g.RowSpacing  = 6;
            g.Padding     = [8 8 8 8];

            h = uilabel(g, 'Text', 'Add / edit rule', 'FontWeight', 'bold');
            h.Layout.Row = 1; h.Layout.Column = [1 2];

            lb = uilabel(g, 'Text', 'Variable'); lb.Layout.Row = 2; lb.Layout.Column = 1;
            obj.VarDD = uidropdown(g, 'ValueChangedFcn', @(s,e) obj.onVarChanged());
            obj.VarDD.Layout.Row = 2; obj.VarDD.Layout.Column = 2;

            lb = uilabel(g, 'Text', 'Operator'); lb.Layout.Row = 3; lb.Layout.Column = 1;
            obj.OpDD  = uidropdown(g);
            obj.OpDD.Layout.Row = 3; obj.OpDD.Layout.Column = 2;

            lb = uilabel(g, 'Text', 'Value'); lb.Layout.Row = 4; lb.Layout.Column = 1;
            obj.ValField = uieditfield(g, 'text', ...
                'Tooltip', ['number(s) for numeric (use "lo, hi" for between; ' ...
                            '"a, b, c" for in / notIn); label(s) for text; ignored for logical']);
            obj.ValField.Layout.Row = 4; obj.ValField.Layout.Column = 2;

            lb = uilabel(g, 'Text', 'Group'); lb.Layout.Row = 5; lb.Layout.Column = 1;
            obj.GroupDD = uidropdown(g, 'Editable', 'on', ...
                'Items', {'(none)'}, 'Value', '(none)', ...
                'Tooltip', ['Type a name to group rules. Rules sharing a group are ' ...
                            'combined by that group''s mode (AND default, or OR -- ' ...
                            'set via the OR/AND-selected buttons below); different ' ...
                            'groups are ORed. Leave "(none)" for an always-on filter.']);
            obj.GroupDD.Layout.Row = 5; obj.GroupDD.Layout.Column = 2;

            lb = uilabel(g, 'Text', 'Scope'); lb.Layout.Row = 6; lb.Layout.Column = 1;
            obj.ScopeDD = uidropdown(g, 'Items', {'Global','Local'}, 'Value', 'Global', ...
                'ValueChangedFcn', @(s,e) obj.refreshGroupChoices());
            obj.ScopeDD.Layout.Row = 6; obj.ScopeDD.Layout.Column = 2;

            addBtn = uibutton(g, 'Text', 'Add rule', ...
                'ButtonPushedFcn', @(s,e) obj.onAdd());
            addBtn.Layout.Row = 7; addBtn.Layout.Column = [1 2];

            % ---- exclude outlier units by their number -------------------
            h = uilabel(g, 'Text', 'Exclude units  (outliers)', 'FontWeight', 'bold');
            h.Layout.Row = 8; h.Layout.Column = [1 2];

            eg = uigridlayout(g, [1 3], 'Padding', [0 0 0 0], 'ColumnSpacing', 4);
            eg.ColumnWidth = {'1x', 70, 60};
            eg.Layout.Row = 9; eg.Layout.Column = [1 2];
            obj.ExcludeField = uieditfield(eg, 'text', ...
                'Tooltip', ['Unit numbers to drop from EVERY tab, e.g. "3, 17, 42" ' ...
                            '(the "unit N" shown by the sliders / titles). Adds one ' ...
                            'global rule: UnitIndex notIn [...].']);
            obj.ExcludeField.Layout.Column = 1;
            uibutton(eg, 'Text', 'Exclude', 'ButtonPushedFcn', @(s,e) obj.onExclude());
            uibutton(eg, 'Text', 'Clear',   'ButtonPushedFcn', @(s,e) obj.onClearExclude());

            h = uilabel(g, 'Text', 'Active rules  (global + current tab)', ...
                'FontWeight', 'bold');
            h.Layout.Row = 10; h.Layout.Column = [1 2];

            obj.RulesTable = uitable(g, ...
                'ColumnName',     {'Variable','Type','Operator','Value','Group','Scope','On'}, ...
                'ColumnEditable', [false false false false false false true], ...
                'SelectionType',  'row', ...
                'CellEditCallback', @(s,e) obj.onToggle(e));
            obj.RulesTable.Layout.Row = 11; obj.RulesTable.Layout.Column = [1 2];

            % ---- combine selected rules within a group (AND / OR) ------------
            cg = uigridlayout(g, [1 3], 'Padding', [0 0 0 0], 'ColumnSpacing', 4);
            cg.Layout.Row = 12; cg.Layout.Column = [1 2];
            uibutton(cg, 'Text', 'OR selected', ...
                'ButtonPushedFcn', @(s,e) obj.onCombineSelected('or'), ...
                'Tooltip', ['Put the selected rules (2+, same scope) in ONE group ' ...
                            'ORed together. Groups OR across each other; ungrouped ' ...
                            'rules stay an always-on AND baseline.']);
            uibutton(cg, 'Text', 'AND selected', ...
                'ButtonPushedFcn', @(s,e) obj.onCombineSelected('and'), ...
                'Tooltip', 'Put the selected rules (2+, same scope) in one group ANDed together.');
            uibutton(cg, 'Text', 'Ungroup', ...
                'ButtonPushedFcn', @(s,e) obj.onUngroupSelected(), ...
                'Tooltip', 'Remove the selected rules from their group (back to the AND baseline).');

            rmBtn = uibutton(g, 'Text', 'Remove selected', ...
                'ButtonPushedFcn', @(s,e) obj.onRemove());
            rmBtn.Layout.Row = 13; rmBtn.Layout.Column = 1;
            apBtn = uibutton(g, 'Text', 'Apply', ...
                'ButtonPushedFcn', @(s,e) obj.Viz.refreshAll());
            apBtn.Layout.Row = 13; apBtn.Layout.Column = 2;

            rtBtn = uibutton(g, 'Text', 'Reset tab', ...
                'ButtonPushedFcn', @(s,e) obj.Viz.resetTabToDefault(obj.Viz.currentTab()));
            rtBtn.Layout.Row = 14; rtBtn.Layout.Column = 1;
            raBtn = uibutton(g, 'Text', 'Reset to default', ...
                'ButtonPushedFcn', @(s,e) obj.Viz.resetToDefault());
            raBtn.Layout.Row = 14; raBtn.Layout.Column = 2;

            sdBtn = uibutton(g, 'Text', 'Set current view as default', ...
                'ButtonPushedFcn', @(s,e) obj.onSetDefault());
            sdBtn.Layout.Row = 15; sdBtn.Layout.Column = [1 2];

            % ---- saved filter sets (named presets of the global filters) ----
            h = uilabel(g, 'Text', 'Saved filter sets  (global)', 'FontWeight', 'bold');
            h.Layout.Row = 16; h.Layout.Column = [1 2];

            obj.PresetDD = uidropdown(g, 'Editable', 'on', ...
                'Items', {'(no saved sets)'}, 'Value', '(no saved sets)', ...
                'Tooltip', 'Type a name to save the current global filters; pick one to load/delete.');
            obj.PresetDD.Layout.Row = 17; obj.PresetDD.Layout.Column = [1 2];

            pg = uigridlayout(g, [1 3], 'Padding', [0 0 0 0], 'ColumnSpacing', 4);
            pg.Layout.Row = 18; pg.Layout.Column = [1 2];
            uibutton(pg, 'Text', 'Save',   'ButtonPushedFcn', @(s,e) obj.onSavePreset());
            uibutton(pg, 'Text', 'Load',   'ButtonPushedFcn', @(s,e) obj.onLoadPreset());
            uibutton(pg, 'Text', 'Delete', 'ButtonPushedFcn', @(s,e) obj.onDeletePreset());

            % ---- unit-tracking ring scope (global; applies to every tab) -----
            lb = uilabel(g, 'Text', 'Track scope'); lb.Layout.Row = 19; lb.Layout.Column = 1;
            obj.TrackScopeField = uieditfield(g, 'numeric', ...
                'Value', 0, 'Limits', [0 Inf], 'RoundFractionalValues', 'on', ...
                'Tooltip', ['How "Track unit on click" rings units across all plots. ' ...
                            '0 (the default) = ring ONLY the clicked sample. ' ...
                            'Any other number (e.g. 5) = ring EVERY recorded sample of that ' ...
                            'neuron, i.e. all of its laser intensities. Has no visible effect ' ...
                            'unless "Track unit on click" is ticked on a tab.'], ...
                'ValueChangedFcn', @(s,e) obj.onTrackScopeChanged());
            obj.TrackScopeField.Layout.Row = 19; obj.TrackScopeField.Layout.Column = 2;

            obj.SummaryArea = uitextarea(g, 'Editable', 'off');
            obj.SummaryArea.Layout.Row = 20; obj.SummaryArea.Layout.Column = [1 2];

            obj.populateVariables();
            obj.refresh();
        end

        function populateVariables(obj)
            %POPULATEVARIABLES  Fill the variable dropdown from D.
            [obj.VarNames, obj.VarTypes] = filter.filterableVars(obj.Viz.D, obj.Viz.N);
            if isempty(obj.VarNames)
                obj.VarDD.Items = {'(no filterable variables)'};
                obj.OpDD.Items  = {};
            else
                obj.VarDD.Items = obj.VarNames;
                obj.VarDD.Value = obj.VarNames{1};
                obj.onVarChanged();
            end
        end

        function onVarChanged(obj)
            %ONVARCHANGED  Refresh the operator list for the chosen variable.
            t = obj.typeOf(obj.VarDD.Value);
            ops = filter.FilterRule.operatorsFor(t);
            obj.OpDD.Items = ops;
            if ~isempty(ops), obj.OpDD.Value = ops{1}; end
        end

        function onAdd(obj)
            %ONADD  Build a rule from the editors and add it to the right set.
            if isempty(obj.VarNames), return; end
            var   = obj.VarDD.Value;
            type  = obj.typeOf(var);
            op    = obj.OpDD.Value;
            scope = lower(obj.ScopeDD.Value);
            grp   = strtrim(obj.GroupDD.Value);
            if strcmp(grp, '(none)'), grp = ''; end
            try
                val = filter.FilterRule.parseValue(type, op, obj.ValField.Value);
            catch err
                uialert(obj.Viz.Fig, err.message, 'Invalid value');
                return;
            end
            rule = filter.FilterRule(var, type, op, val, scope, grp);

            if strcmp(scope, 'global')
                % keep a group's mode consistent: inherit it if the group exists
                if ~isempty(grp), rule.GroupCombine = obj.Viz.GlobalFilters.groupCombine(grp); end
                obj.Viz.GlobalFilters.add(rule);
                obj.Viz.refreshAll();
            else
                tab = obj.Viz.currentTab();
                if isempty(tab)
                    uialert(obj.Viz.Fig, 'No active tab for a local rule.', 'Filter');
                    return;
                end
                if ~isempty(grp), rule.GroupCombine = tab.LocalFilters.groupCombine(grp); end
                tab.LocalFilters.add(rule);
                obj.Viz.refresh();
            end
            obj.refresh();
        end

        function onExclude(obj)
            %ONEXCLUDE  Drop the typed unit numbers from every tab.
            %   Parses the "Exclude units" field and (re)creates a single GLOBAL
            %   rule  UnitIndex notIn [list]  so those units fail the filter on
            %   all tabs. Re-running replaces the previous exclusion list.
            [nums, bad] = filter.FilterPanel.parseUnitList(obj.ExcludeField.Value);
            nums = unique(round(nums));
            N    = obj.Viz.N;
            oor  = nums(nums < 1 | nums > N);     % out-of-range entries
            nums = nums(nums >= 1 & nums <= N);

            obj.removeExcludeRule();              % clear any previous exclusion
            if ~isempty(nums)
                rule = filter.FilterRule(obj.ExcludeVar, 'numeric', 'notIn', ...
                                         nums(:)', 'global');
                obj.Viz.GlobalFilters.add(rule);
            end
            obj.Viz.refreshAll();
            obj.refresh();

            if bad || ~isempty(oor)
                msg = 'Excluded the valid unit numbers.';
                if ~isempty(oor)
                    msg = sprintf('%s\nIgnored out-of-range (1..%d): %s', ...
                        msg, N, strjoin(string(oor(:))', ', '));
                end
                if bad
                    msg = sprintf('%s\nIgnored entries that were not numbers.', msg);
                end
                uialert(obj.Viz.Fig, msg, 'Exclude units', 'Icon', 'warning');
            end
        end

        function onClearExclude(obj)
            %ONCLEAREXCLUDE  Remove the unit-exclusion rule (re-include all).
            obj.removeExcludeRule();
            obj.ExcludeField.Value = '';
            obj.Viz.refreshAll();
            obj.refresh();
        end

        function onTrackScopeChanged(obj)
            %ONTRACKSCOPECHANGED  Apply the "Track scope" box: 0 -> ring only the
            %   clicked sample; any other value -> ring every recorded sample of the
            %   neuron (the default). Re-rings immediately via the Visualizer.
            obj.Viz.setTrackWholeUnit(obj.TrackScopeField.Value ~= 0);
        end

        function onRemove(obj)
            %ONREMOVE  Drop the selected rows from their owning sets.
            rows = obj.RulesTable.Selection;
            if isempty(rows), return; end
            % Split selected rows by owning set; remove high indices first so
            % the remaining indices stay valid.
            gIdx = []; lIdx = [];
            for k = 1:numel(rows)
                m = obj.RowMap(rows(k));
                if strcmp(m.scope,'global'), gIdx(end+1)=m.idx; else, lIdx(end+1)=m.idx; end %#ok<AGROW>
            end
            for i = sort(gIdx,'descend'), obj.Viz.GlobalFilters.removeAt(i); end
            tab = obj.Viz.currentTab();
            if ~isempty(tab)
                for i = sort(lIdx,'descend'), tab.LocalFilters.removeAt(i); end
            end
            obj.redrawForScope(~isempty(gIdx));   % global change -> all tabs; local-only -> this tab
            obj.refresh();
        end

        function onCombineSelected(obj, mode)
            %ONCOMBINESELECTED  Put the selected rules in one group, combined by
            %   MODE ('and'|'or'). The selection must be 2+ rules of the SAME
            %   scope (global filters and a tab's local filters are always ANDed
            %   together, so they cannot be combined with each other). The new
            %   group ORs against other groups; ungrouped rules stay AND baseline.
            rows = obj.RulesTable.Selection;
            if numel(rows) < 2
                uialert(obj.Viz.Fig, 'Select at least two rules (same scope) to combine.', ...
                    'Combine rules');
                return;
            end
            scopes = arrayfun(@(rr) string(obj.RowMap(rr).scope), rows(:));
            if numel(unique(scopes)) > 1
                uialert(obj.Viz.Fig, ['Select rules of the SAME scope. Global and ' ...
                    'local filters are always ANDed, so they cannot be ORed together.'], ...
                    'Combine rules');
                return;
            end
            fset = obj.setForScope(char(scopes(1)));
            if isempty(fset), return; end
            idxs  = arrayfun(@(rr) obj.RowMap(rr).idx, rows);
            label = obj.freshGroupLabel(fset, mode);
            for k = 1:numel(idxs)
                r = fset.Rules(idxs(k));
                r.Group = label; r.GroupCombine = mode;
                fset.Rules(idxs(k)) = r;
            end
            obj.redrawForScope(strcmpi(char(scopes(1)),'global'));
            obj.refresh();
        end

        function onUngroupSelected(obj)
            %ONUNGROUPSELECTED  Send the selected rules back to the AND baseline
            %   (Group = '') in their respective sets. Works across scopes.
            rows = obj.RulesTable.Selection;
            if isempty(rows), return; end
            anyGlobal = false;
            for k = 1:numel(rows)
                m    = obj.RowMap(rows(k));
                if strcmp(m.scope,'global'), anyGlobal = true; end
                fset = obj.setForScope(m.scope);
                if isempty(fset), continue; end
                r = fset.Rules(m.idx);
                r.Group = ''; r.GroupCombine = 'and';
                fset.Rules(m.idx) = r;
            end
            obj.redrawForScope(anyGlobal);
            obj.refresh();
        end

        function onToggle(obj, e)
            %ONTOGGLE  Enable/disable a rule from the table's "On" checkbox.
            row = e.Indices(1);
            m   = obj.RowMap(row);
            newVal = logical(e.NewData);
            if strcmp(m.scope,'global')
                fset = obj.Viz.GlobalFilters;
            else
                tab = obj.Viz.currentTab();
                if isempty(tab), return; end
                fset = tab.LocalFilters;
            end
            r = fset.Rules(m.idx); r.Enabled = newVal; fset.Rules(m.idx) = r;
            obj.redrawForScope(strcmp(m.scope,'global'));
            obj.refresh();
        end

        function onSetDefault(obj)
            %ONSETDEFAULT  Save the current view (all tabs + filters) as default.
            obj.Viz.setDefault();
            uialert(obj.Viz.Fig, ...
                'Current view (filters + panel controls for all tabs) saved as the default. "Reset to default" restores it.', ...
                'Default saved', 'Icon', 'success');
        end

        function refresh(obj)
            %REFRESH  Rebuild the active-rules table + summary for the current tab.
            gset = obj.Viz.GlobalFilters;
            tab  = obj.Viz.currentTab();

            map = struct('scope',{},'idx',{});
            for i = 1:gset.count, map(end+1) = struct('scope','global','idx',i); end %#ok<AGROW>
            T = gset.toTable();
            if ~isempty(tab)
                for i = 1:tab.LocalFilters.count
                    map(end+1) = struct('scope','local','idx',i); %#ok<AGROW>
                end
                T = [T; tab.LocalFilters.toTable()];
            end
            obj.RowMap = map;
            obj.RulesTable.Data = T;
            obj.SummaryArea.Value = obj.summaryText(tab);
            obj.refreshGroupChoices();
            obj.refreshExcludeField();
            obj.refreshTrackScope();
            obj.refreshPresets();
        end

        function refreshTrackScope(obj)
            %REFRESHTRACKSCOPE  Mirror the Visualizer's track-ring scope into the box
            %   (after a session restore or programmatic change). Only writes when
            %   inconsistent, so it never clobbers a user-typed non-zero value.
            if isempty(obj.TrackScopeField) || ~isvalid(obj.TrackScopeField), return; end
            if obj.Viz.TrackWholeUnit
                if obj.TrackScopeField.Value == 0, obj.TrackScopeField.Value = 5; end
            else
                obj.TrackScopeField.Value = 0;
            end
        end

        function refreshExcludeField(obj)
            %REFRESHEXCLUDEFIELD  Mirror the current exclusion rule into the box.
            idx = obj.excludeRuleIndex();
            if isempty(idx)
                obj.ExcludeField.Value = '';
            else
                v = sort(obj.Viz.GlobalFilters.Rules(idx).Value(:))';
                obj.ExcludeField.Value = char(strjoin(string(v), ', '));
            end
        end

        function refreshGroupChoices(obj)
            %REFRESHGROUPCHOICES  Offer existing group labels for the chosen scope.
            fset = obj.scopeSet();
            if isempty(fset), names = {}; else, names = fset.groupNames(); end
            cur = obj.GroupDD.Value;
            obj.GroupDD.Items = [{'(none)'}, names];
            if isempty(cur), obj.GroupDD.Value = '(none)'; end   % keep typed value
        end

        function refreshPresets(obj)
            %REFRESHPRESETS  Sync the saved-filter-set dropdown with disk.
            names = obj.Viz.presetNames();
            cur   = obj.PresetDD.Value;
            if isempty(names)
                obj.PresetDD.Items = {'(no saved sets)'};
                obj.PresetDD.Value = '(no saved sets)';
            else
                obj.PresetDD.Items = names;
                if isempty(cur) || strcmp(cur, '(no saved sets)')
                    obj.PresetDD.Value = names{1};
                end
            end
        end

        % --------------------------------------------------------------- %
        %  Saved filter-set handlers
        % --------------------------------------------------------------- %
        function onSavePreset(obj)
            %ONSAVEPRESET  Save the current global filters under the typed name.
            name = strtrim(obj.PresetDD.Value);
            if isempty(name) || strcmp(name, '(no saved sets)')
                uialert(obj.Viz.Fig, ...
                    'Type a name for the filter set, then click Save.', 'Save filter set');
                return;
            end
            try
                obj.Viz.savePreset(name);
            catch err
                uialert(obj.Viz.Fig, err.message, 'Save filter set');
                return;
            end
            obj.refreshPresets();
            obj.PresetDD.Value = name;
            uialert(obj.Viz.Fig, sprintf('Saved global filter set "%s".', name), ...
                'Saved', 'Icon', 'success');
        end

        function onLoadPreset(obj)
            %ONLOADPRESET  Replace the global filters with the selected preset.
            name = strtrim(obj.PresetDD.Value);
            if isempty(name) || strcmp(name, '(no saved sets)'), return; end
            if ~obj.Viz.loadPreset(name)
                uialert(obj.Viz.Fig, sprintf('No saved filter set named "%s".', name), ...
                    'Load filter set');
                return;
            end
            obj.refresh();
        end

        function onDeletePreset(obj)
            %ONDELETEPRESET  Delete the selected saved filter set (with confirm).
            name = strtrim(obj.PresetDD.Value);
            if isempty(name) || strcmp(name, '(no saved sets)'), return; end
            sel = uiconfirm(obj.Viz.Fig, ...
                sprintf('Delete saved filter set "%s"?', name), 'Delete', ...
                'Options', {'Delete','Cancel'}, ...
                'DefaultOption', 2, 'CancelOption', 2);
            if ~strcmp(sel, 'Delete'), return; end
            obj.Viz.deletePreset(name);
            obj.refreshPresets();
        end
    end

    methods (Access = private)
        function redrawForScope(obj, touchedGlobal)
            %REDRAWFORSCOPE  Redraw the minimum needed after a rule change:
            %   a GLOBAL change affects every tab (refreshAll); a LOCAL-only change
            %   affects just the current tab and its open figure window (refresh).
            if touchedGlobal, obj.Viz.refreshAll(); else, obj.Viz.refresh(); end
        end

        function t = typeOf(obj, var)
            k = find(strcmp(obj.VarNames, var), 1);
            if isempty(k), t = 'numeric'; else, t = obj.VarTypes{k}; end
        end

        function idx = excludeRuleIndex(obj)
            %EXCLUDERULEINDEX  Index of the unit-exclusion rule in GlobalFilters.
            %   The exclusion is the single global  ExcludeVar notIn [...]  rule
            %   created by onExclude ([] if none exists yet).
            idx  = [];
            gset = obj.Viz.GlobalFilters;
            for i = 1:gset.count
                r = gset.Rules(i);
                if strcmp(r.Variable, obj.ExcludeVar) && strcmp(r.Operator, 'notIn')
                    idx = i; return;
                end
            end
        end

        function removeExcludeRule(obj)
            %REMOVEEXCLUDERULE  Drop the unit-exclusion rule if present.
            idx = obj.excludeRuleIndex();
            if ~isempty(idx), obj.Viz.GlobalFilters.removeAt(idx); end
        end

        function fset = scopeSet(obj)
            %SCOPESET  The FilterSet targeted by the current Scope dropdown.
            fset = obj.setForScope(obj.ScopeDD.Value);
        end

        function fset = setForScope(obj, scope)
            %SETFORSCOPE  The FilterSet for 'global' or 'local' ([] if no tab).
            if strcmpi(scope, 'global')
                fset = obj.Viz.GlobalFilters;
            else
                tab = obj.Viz.currentTab();
                if isempty(tab), fset = []; else, fset = tab.LocalFilters; end
            end
        end

        function label = freshGroupLabel(~, fset, mode)
            %FRESHGROUPLABEL  A group label not already used in FSET, prefixed by
            %   the mode (e.g. 'or1', 'and2') so the table reads sensibly.
            existing = fset.groupNames();
            k = 1;
            while true
                label = sprintf('%s%d', lower(char(mode)), k);
                if ~any(strcmp(existing, label)), return; end
                k = k + 1;
            end
        end

        function lines = summaryText(obj, tab)
            %SUMMARYTEXT  Plain-language list of active limits + match count.
            D = obj.Viz.D; N = obj.Viz.N;
            lines = {};
            if isempty(tab)
                tabName = '(none)'; lmask = true(N,1); lset_count = 0;
            else
                tabName = tab.Name;
                lmask = tab.LocalFilters.apply(D, N);
                lset_count = tab.LocalFilters.count;
            end
            gmask = obj.Viz.GlobalFilters.apply(D, N);
            mask  = gmask & lmask;
            lines{end+1} = sprintf('Tab: %s', tabName);
            lines{end+1} = sprintf('Global rules: %d   Local rules: %d', ...
                obj.Viz.GlobalFilters.count, lset_count);
            gd = groupDescr(obj.Viz.GlobalFilters);
            if ~isempty(tab), gd = [gd, groupDescr(tab.LocalFilters)]; end
            if ~isempty(gd)
                lines{end+1} = sprintf('Groups (within as shown, ORed across): %s', ...
                    strjoin(gd, ', '));
            end
            lines{end+1} = sprintf('Units passing: %d / %d', nnz(mask), N);
        end
    end

    methods (Static)
        function [nums, bad] = parseUnitList(raw)
            %PARSEUNITLIST  Parse a free-typed unit list into a numeric row.
            %   Accepts numbers separated by commas, spaces, semicolons or
            %   newlines (e.g. "3, 17 42; 108"). NUMS is a 1xK double row of the
            %   numbers found; BAD is true if any non-empty token was not a
            %   number (so the caller can warn).
            nums = [];
            bad  = false;
            raw  = strtrim(char(string(raw)));
            if isempty(raw), return; end
            parts = regexp(raw, '[\s,;]+', 'split');
            parts = parts(~cellfun(@isempty, parts));
            vals  = str2double(parts);
            bad   = any(isnan(vals));
            nums  = vals(~isnan(vals));
            nums  = nums(:)';
        end
    end
end

% ----------------------------------------------------------------------- %
function d = groupDescr(fset)
%GROUPDESCR  Cellstr of "label[MODE]" for each group in FSET (for the summary).
    names = fset.groupNames();
    d = cell(1, numel(names));
    for i = 1:numel(names)
        d{i} = sprintf('%s[%s]', names{i}, upper(fset.groupCombine(names{i})));
    end
end
