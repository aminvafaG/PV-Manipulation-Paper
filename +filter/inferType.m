function t = inferType(value)
%INFERTYPE  Classify a per-unit variable for filtering/UI purposes.
%
%   t = filter.inferType(value)   value is the array stored in D.(name)
%
%   Returns one of:
%       'logical'      true/false per unit
%       'numeric'      double/single/integer per unit
%       'categorical'  MATLAB categorical per unit
%       'string'       string / char / cellstr (names, labels, text)
%       'other'        anything not directly filterable (cells, matrices, ...)
%
%   The filter engine and FilterPanel use this to pick valid operators and the
%   right value editor for each variable.

    if islogical(value)
        t = 'logical';
    elseif iscategorical(value)
        t = 'categorical';
    elseif isstring(value) || ischar(value) || iscellstr(value)
        t = 'string';
    elseif isnumeric(value)
        t = 'numeric';
    else
        t = 'other';
    end
end
