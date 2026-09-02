classdef FilterRule
%FILTERRULE  One filtering condition on a single per-unit variable.
%
%   A rule maps a variable + operator + value(s) to a logical Nx1 mask over
%   units. Rules are *value* objects (cheap to copy/store); a FilterSet holds
%   an array of them and ANDs their masks together.
%
%   CONSTRUCT
%       r = filter.FilterRule('FR_L','numeric','between',[2 20],'global')
%       r = filter.FilterRule('EI','string','is',"E",'local')
%
%   APPLY
%       mask = r.apply(D, N)        % Nx1 logical
%
%   The set of valid operators per type lives in operatorsFor(); parseValue()
%   turns a typed-in string from the UI into the Value this class expects.
%
%   See also: filter.FilterSet, filter.FilterPanel, filter.inferType

    properties
        Variable char  = ''         % field name in D (a per-unit variable)
        Type     char  = 'numeric'  % numeric|logical|string|categorical
        Operator char  = 'between'  % see operatorsFor(Type)
        Value          = []         % scalar | [lo hi] | set (meaning per operator)
        Scope    char  = 'global'   % 'global' (all tabs) | 'local' (current tab)
        Group    char  = ''         % '' = loose (AND baseline); else group label
        GroupCombine char = 'and'   % how this group's rules combine: 'and' | 'or'
        Enabled  (1,1) logical = true
    end

    methods
        function obj = FilterRule(variable, type, operator, value, scope, group, groupCombine)
            if nargin >= 1, obj.Variable = char(variable); end
            if nargin >= 2, obj.Type     = char(type);     end
            if nargin >= 3, obj.Operator = char(operator); end
            if nargin >= 4, obj.Value    = value;          end
            if nargin >= 5, obj.Scope    = char(scope);    end
            if nargin >= 6, obj.Group    = char(group);    end
            if nargin >= 7, obj.GroupCombine = char(groupCombine); end
        end

        function m = apply(obj, D, N)
            %APPLY  Nx1 logical mask for this rule (all-true if not applicable).
            m = true(N, 1);
            if ~obj.Enabled || isempty(obj.Variable) || ~isfield(D, obj.Variable)
                return;
            end
            x = D.(obj.Variable);
            if numel(x) ~= N, return; end      % not a per-unit variable -> no-op
            x = x(:);

            switch obj.Type
                case {'numeric'}
                    m = applyNumeric(x, obj.Operator, obj.Value);
                case {'logical'}
                    m = applyLogical(logical(x), obj.Operator);
                case {'string','categorical'}
                    m = applyText(string(x), obj.Operator, obj.Value);
                otherwise
                    % unknown type -> no filtering
            end
            m = m(:);
        end

        function s = valueString(obj)
            %VALUESTRING  Human-readable value for the active-rules display.
            v = obj.Value;
            switch obj.Operator
                case {'isTrue','isFalse'}
                    s = '-';
                    return;
            end
            if isstring(v) || iscellstr(v) || ischar(v)
                s = strjoin(cellstr(string(v)), ', ');
            elseif isnumeric(v) || islogical(v)
                if numel(v) == 2 && strcmp(obj.Operator,'between')
                    s = sprintf('[%g, %g]', v(1), v(2));
                else
                    s = strjoin(string(v(:))', ', ');
                end
            else
                s = '?';
            end
        end

        function s = describe(obj)
            %DESCRIBE  One-line summary, e.g. "FR_L between [2, 20]  (global)".
            if isempty(obj.Group)
                grp = '';
            else
                grp = sprintf(' {%s:%s}', obj.Group, upper(obj.GroupCombine));
            end
            s = sprintf('%s %s %s%s  (%s)', obj.Variable, obj.Operator, ...
                        obj.valueString(), grp, obj.Scope);
        end

        function s = toStruct(obj)
            %TOSTRUCT  Plain struct for saving (struct -> .mat is round-trippable).
            s = struct('Variable',obj.Variable, 'Type',obj.Type, ...
                       'Operator',obj.Operator, 'Value',obj.Value, ...
                       'Scope',obj.Scope, 'Group',obj.Group, ...
                       'GroupCombine',obj.GroupCombine, 'Enabled',obj.Enabled);
        end
    end

    methods (Static)
        function r = fromStruct(s)
            %FROMSTRUCT  Rebuild a FilterRule from a toStruct() struct.
            r = filter.FilterRule(s.Variable, s.Type, s.Operator, s.Value, s.Scope);
            if isfield(s,'Group'),        r.Group        = char(s.Group);       end
            if isfield(s,'GroupCombine'), r.GroupCombine = char(s.GroupCombine); end
            if isfield(s,'Enabled'),      r.Enabled      = logical(s.Enabled);  end
        end

        function ops = operatorsFor(type)
            %OPERATORSFOR  Valid operators for a variable type (for UI menus).
            switch type
                case 'numeric'
                    ops = {'between','==','~=','>','>=','<','<=','in','notIn'};
                case 'logical'
                    ops = {'isTrue','isFalse'};
                case {'string','categorical'}
                    ops = {'is','isNot','contains','startsWith','in'};
                otherwise
                    ops = {};
            end
        end

        function val = parseValue(type, operator, raw)
            %PARSEVALUE  Turn a UI string into a Value of the right shape/type.
            %   raw is whatever the user typed in the value box.
            raw = strtrim(string(raw));
            switch operator
                case {'isTrue','isFalse'}
                    val = [];   return;
            end
            parts = strtrim(split(raw, ','));
            parts(parts == "") = [];
            switch type
                case 'numeric'
                    nums = str2double(parts);
                    if strcmp(operator,'between')
                        if numel(nums) ~= 2 || any(isnan(nums))
                            error('filter:FilterRule:between', ...
                                '"between" needs two numbers, e.g. 2, 20');
                        end
                        val = sort(nums(:))';
                    elseif strcmp(operator,'in') || strcmp(operator,'notIn')
                        val = nums(:)';
                    else
                        val = nums(1);
                    end
                otherwise   % string / categorical
                    val = parts(:)';     % string array of one or more labels
            end
        end
    end
end

% ----------------------------------------------------------------------- %
%  Per-type appliers (local functions: shared, no UI, easy to extend)
% ----------------------------------------------------------------------- %
function m = applyNumeric(x, op, v)
    switch op
        case 'between', m = x >= min(v) & x <= max(v);
        case '==',      m = x == v(1);
        case '~=',      m = x ~= v(1);
        case '>',       m = x >  v(1);
        case '>=',      m = x >= v(1);
        case '<',       m = x <  v(1);
        case '<=',      m = x <= v(1);
        case 'in',      m = ismember(x, v);
        case 'notIn',   m = ~ismember(x, v);   % keep everything except this set
        otherwise,      m = true(size(x));
    end
    if ~strcmp(op, 'notIn')
        m(isnan(x)) = false;      % NaNs never pass a numeric filter ...
    end                            % ... except "notIn": a NaN is not in the set
end

function m = applyLogical(x, op)
    switch op
        case 'isTrue',  m =  x;
        case 'isFalse', m = ~x;
        otherwise,      m = true(size(x));
    end
end

function m = applyText(x, op, v)
    v = string(v);
    switch op
        case 'is',         m = ismember(x, v);
        case 'isNot',      m = ~ismember(x, v);
        case 'in',         m = ismember(x, v);
        case 'contains',   m = contains(x, v(1));
        case 'startsWith', m = startsWith(x, v(1));
        otherwise,         m = true(size(x));
    end
end
