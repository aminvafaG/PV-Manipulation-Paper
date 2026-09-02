function N = unitCount(D)
%UNITCOUNT  Number of units represented in a project struct D.
%
%   N = filter.unitCount(D)
%
%   Inferred from the first per-unit field found: a column vector or an Nx1
%   cell array (e.g. ch, EI, RasL, ...). Fields like fit_L (360 x N) or Meta
%   are ignored. Errors if no per-unit field is present.

    fn = fieldnames(D);
    for i = 1:numel(fn)
        if strcmp(fn{i}, 'Meta'), continue; end
        x = D.(fn{i});
        if iscell(x) && iscolumn(x)
            N = numel(x); return;
        end
        if (isnumeric(x) || islogical(x) || isstring(x) || iscategorical(x)) ...
                && iscolumn(x) && numel(x) > 1
            N = numel(x); return;
        end
    end
    error('filter:unitCount:none', ...
        ['Could not infer the unit count from D. Make sure D contains at ' ...
         'least one per-unit field (a column vector or Nx1 cell), e.g. ch.']);
end
