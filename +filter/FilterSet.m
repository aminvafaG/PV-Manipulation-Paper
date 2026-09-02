classdef FilterSet < handle
%FILTERSET  An ordered collection of FilterRules combined into one mask.
%
%   A handle object so a tab (or the visualizer's global set) can hold a live,
%   editable reference. Rules carry an optional Group label, which lets one
%   set express a compound, "OR of AND-groups" condition:
%
%     * LOOSE rules (Group = '')  are baseline constraints, combined with each
%       other by obj.Combine ('and' by default) and ALWAYS applied.
%     * GROUPED rules (same non-empty Group label) are combined WITHIN the group
%       by that group's own mode (FilterRule.GroupCombine: 'and' default, or
%       'or'); the different groups are then ORed (a unit passes if it matches
%       ANY group). All rules in a group share one GroupCombine mode.
%     * Final mask = looseMask  AND  (group1 OR group2 OR ...).
%
%   So  "E cells with CV in [a b]  OR  I cells with CV in [c d]"  is two groups
%   "E" {EI is E, CV between a b} and "I" {EI is I, CV between c d}, with no
%   loose rules. A plain set with no groups behaves exactly as a flat AND/OR.
%
%   USE
%       fs = filter.FilterSet();
%       fs.add( filter.FilterRule('FR_L','numeric','>',5,'local') );
%       fs.add( filter.FilterRule('EI','string','is',"E",'global','E') );
%       fs.add( filter.FilterRule('fitCV_NL','numeric','between',[0 .3],'global','E') );
%       mask = fs.apply(D, N);        % Nx1 logical
%       T    = fs.toTable();          % tabular view for the panel display
%
%   See also: filter.FilterRule, filter.FilterPanel

    properties
        Rules                          % 1xK filter.FilterRule array
        Combine char = 'and'           % 'and' (default) | 'or'  -- how rules join
    end

    methods
        function obj = FilterSet()
            obj.Rules = filter.FilterRule.empty(1, 0);
        end

        function add(obj, rule)
            obj.Rules(end+1) = rule;
        end

        function removeAt(obj, idx)
            obj.Rules(idx) = [];
        end

        function clear(obj)
            obj.Rules = filter.FilterRule.empty(1, 0);
        end

        function n = count(obj)
            n = numel(obj.Rules);
        end

        function m = apply(obj, D, N)
            %APPLY  Combine all enabled rules into one Nx1 logical mask.
            %   Loose rules (no Group) are combined by obj.Combine and always
            %   applied; grouped rules are ANDed within a group and ORed across
            %   groups; the two parts are ANDed: loose AND (g1 OR g2 OR ...).
            m = true(N, 1);
            if obj.count == 0, return; end
            enabled = obj.Rules(arrayfun(@(r) r.Enabled, obj.Rules));
            if isempty(enabled), return; end

            grp     = arrayfun(@(r) string(r.Group), enabled);
            isLoose = (grp == "") | ismissing(grp);

            % --- loose baseline (combined by obj.Combine) ---
            loose = enabled(isLoose);
            if isempty(loose)
                looseMask = true(N, 1);
            else
                looseMask = combineRules(loose, D, N, obj.Combine);
            end

            % --- groups: combine within by each group's mode, OR across ---
            grouped = enabled(~isLoose);
            gLabels = grp(~isLoose);
            if isempty(grouped)
                groupsMask = true(N, 1);
            else
                gnames     = unique(gLabels, 'stable');
                groupsMask = false(N, 1);
                for i = 1:numel(gnames)
                    gi = grouped(gLabels == gnames(i));
                    groupsMask = groupsMask | combineRules(gi, D, N, modeOf(gi));
                end
            end

            m = looseMask & groupsMask;
            m = m(:);
        end

        function names = groupNames(obj)
            %GROUPNAMES  Unique non-empty group labels in this set (cellstr).
            names = {};
            for i = 1:obj.count
                g = obj.Rules(i).Group;
                if ~isempty(g) && ~any(strcmp(names, g))
                    names{end+1} = g; %#ok<AGROW>
                end
            end
        end

        function mode = groupCombine(obj, label)
            %GROUPCOMBINE  Within-group combine mode ('and'|'or') for a group
            %   label ('and' if the label is empty or not found). All rules in a
            %   group share this; the value is read from the first matching rule.
            mode  = 'and';
            label = char(label);
            if isempty(label), return; end
            for i = 1:obj.count
                if strcmp(obj.Rules(i).Group, label)
                    m = lower(char(obj.Rules(i).GroupCombine));
                    if ismember(m, {'and','or'}), mode = m; end
                    return;
                end
            end
        end

        function s = toStruct(obj)
            %TOSTRUCT  Serializable snapshot: combine mode + rules.
            rules = struct('Variable',{},'Type',{},'Operator',{}, ...
                           'Value',{},'Scope',{},'Group',{}, ...
                           'GroupCombine',{},'Enabled',{});
            for i = 1:obj.count
                rules(i) = obj.Rules(i).toStruct();
            end
            s = struct('combine', obj.Combine, 'rules', rules);
        end

        function T = toTable(obj)
            %TOTABLE  Rule list as a table for the active-rules display.
            n = obj.count;
            [vr, ty, op, va, gr, sc] = deal(strings(n,1));
            en = false(n,1);
            for i = 1:n
                r = obj.Rules(i);
                vr(i) = string(r.Variable);
                ty(i) = string(r.Type);
                op(i) = string(r.Operator);
                va(i) = string(r.valueString());
                if isempty(r.Group)
                    gr(i) = "";
                else
                    gr(i) = string(r.Group) + " (" + upper(string(r.GroupCombine)) + ")";
                end
                en(i) = r.Enabled;
                sc(i) = string(r.Scope);
            end
            gr(gr == "") = "—";
            T = table(vr, ty, op, va, gr, sc, en, 'VariableNames', ...
                {'Variable','Type','Operator','Value','Group','Scope','Enabled'});
        end
    end

    methods (Static)
        function obj = fromStruct(s)
            %FROMSTRUCT  Rebuild a FilterSet from a toStruct() snapshot.
            obj = filter.FilterSet();
            if nargin < 1 || isempty(s), return; end
            if isfield(s,'combine') && ~isempty(s.combine), obj.Combine = char(s.combine); end
            if isfield(s,'rules')
                for i = 1:numel(s.rules)
                    obj.add(filter.FilterRule.fromStruct(s.rules(i)));
                end
            end
        end
    end
end

% ----------------------------------------------------------------------- %
function m = combineRules(rules, D, N, mode)
%COMBINERULES  AND/OR the masks of a FilterRule array into one Nx1 logical.
    if strcmpi(mode, 'or')
        m = false(N, 1);
        for i = 1:numel(rules), m = m | rules(i).apply(D, N); end
    else
        m = true(N, 1);
        for i = 1:numel(rules), m = m & rules(i).apply(D, N); end
    end
    m = m(:);
end

% ----------------------------------------------------------------------- %
function mode = modeOf(rules)
%MODEOF  Within-group combine mode of a FilterRule array ('and' default).
%   All rules in a group share GroupCombine; read it from the first one.
    mode = 'and';
    if isempty(rules), return; end
    m = lower(char(rules(1).GroupCombine));
    if ismember(m, {'and','or'}), mode = m; end
end
