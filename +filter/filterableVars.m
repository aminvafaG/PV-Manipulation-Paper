function [names, types] = filterableVars(D, N)
%FILTERABLEVARS  Names of D fields that can be used as filter variables.
%
%   [names, types] = filter.filterableVars(D)
%   [names, types] = filter.filterableVars(D, N)
%
%   A field is "filterable" when it holds exactly one value per unit and that
%   value is a scalar-ish type (numeric / logical / string / categorical):
%   i.e. an Nx1 column vector or an Nx1 string/categorical array. Multi-column
%   fields (e.g. Fr = [L NL]), stacked curves (fit_L = 360xN), raw cells
%   (rasters) and Meta are excluded -- derive a scalar metric in
%   analysis.computeMetrics if you want to filter on them.
%
%   names  1xK cellstr of field names
%   types  1xK cellstr of the matching filter.inferType result
%
%   See also: filter.inferType, filter.unitCount, analysis.computeMetrics

    if nargin < 2 || isempty(N)
        N = filter.unitCount(D);
    end

    fn    = fieldnames(D);
    names = {};
    types = {};
    for i = 1:numel(fn)
        nm = fn{i};
        if strcmp(nm, 'Meta'), continue; end
        x = D.(nm);
        if iscell(x), continue; end                 % rasters etc. -> not scalar
        if numel(x) ~= N || ~iscolumn(x), continue; end
        t = filter.inferType(x);
        if strcmp(t, 'other'), continue; end
        names{end+1} = nm;   %#ok<AGROW>
        types{end+1} = t;    %#ok<AGROW>
    end
end
