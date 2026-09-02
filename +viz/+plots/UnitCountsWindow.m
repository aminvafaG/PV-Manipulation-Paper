classdef UnitCountsWindow < handle
%UNITCOUNTSWINDOW  Pop-up unit-count breakdown for the laminar tabs.
%
%   A standalone uifigure that tabulates, for the units currently shown in each
%   plot/panel, how many fall in each category (or CROSS of categories) -- both
%   the observation count (with laser-power repeats) and the UNIQUE-neuron count
%   (deduplicated by U_unity).
%
%   USAGE (from a tab)
%       obj.Counts = viz.plots.UnitCountsWindow(D);     % once
%       obj.Counts.show(D, panels);                     % panels: struct('label','idx')
%   where panels(k).idx is the row indices of the units drawn in panel k.
%
%   The "Group by" list (multi-select) chooses the breakdown dimension(s):
%   Layer / G_type / E/I / Animal / Penetration / Task. Pick several to cross
%   them (e.g. Layer + G_type -> one row per (layer, G_type) combination). The
%   table has, per panel, an "obs" column (rows = observations) and a "uniq"
%   column (distinct U_unity), plus a TOTAL row.
%
%   See also: viz.plots.LaminarTab, viz.plots.LaminarViewsTab, viz.plots.V01util

    properties
        Fig
        GroupLB                 % multi-select "group by" listbox
        Table                   % uitable of the counts
        D = []                  % data struct
        Panels = struct('label',{},'idx',{})   % per-panel unit indices
    end

    properties (Constant)
        DIMS = {'Layer','G_type','E/I','Animal','Penetration','Task'};
    end

    methods
        function obj = UnitCountsWindow(D)
            if nargin >= 1, obj.D = D; end
            obj.build();
        end

        function build(obj)
            obj.Fig = uifigure('Name','Unit counts', 'Position',[140 140 760 520], 'Color','w');
            g = uigridlayout(obj.Fig, [1 2]);
            g.ColumnWidth = {200, '1x'}; g.RowHeight = {'1x'}; g.Padding = [8 8 8 8]; g.ColumnSpacing = 8;

            left = uigridlayout(g, [4 1]); left.Layout.Column = 1;
            left.RowHeight = {18, '1x', 18, 'fit'}; left.RowSpacing = 4; left.Padding = [0 0 0 0];
            uilabel(left, 'Text', 'Group by (multi-select):', 'FontWeight','bold');
            obj.GroupLB = uilistbox(left, 'Items', obj.DIMS, 'Multiselect','on', 'Value', {'Layer'}, ...
                'ValueChangedFcn', @(s,e) obj.refresh());
            uilabel(left, 'Text', 'obs = observations (with repeats)', 'FontSize', 10);
            uilabel(left, 'Text', 'uniq = distinct neurons (U_unity)', 'FontSize', 10, 'WordWrap','on');

            obj.Table = uitable(g); obj.Table.Layout.Column = 2;
        end

        function show(obj, D, panels)
            %SHOW  Bring the window up for the given data + panels and refresh.
            if nargin >= 2 && ~isempty(D), obj.D = D; end
            if nargin >= 3, obj.Panels = obj.normalizePanels(panels); end
            if isempty(obj.Fig) || ~isvalid(obj.Fig), obj.build(); end
            figure(obj.Fig);
            obj.refresh();
        end

        function refresh(obj)
            if isempty(obj.Table) || ~isvalid(obj.Table), return; end
            D = obj.D; P = obj.Panels;
            if isempty(D) || isempty(P)
                obj.Table.ColumnName = {'Group'}; obj.Table.Data = {'(no data)'}; return;
            end
            N = viz.plots.V01util.nU(D);
            dims = obj.GroupLB.Value; if ischar(dims), dims = {dims}; end

            % per-unit combo label over the selected dimension(s)
            if isempty(dims)
                combo = repmat("All", N, 1);
            else
                parts = strings(N, numel(dims));
                for d = 1:numel(dims), parts(:,d) = viz.plots.UnitCountsWindow.dimLabels(D, dims{d}); end
                if numel(dims) == 1, combo = parts(:,1); else, combo = join(parts, " | ", 2); end
            end
            UU = viz.plots.V01util.colv(D, 'U_unity', N);

            % rows = combos present across any panel (sorted), + TOTAL on top
            allIdx = [];
            for k = 1:numel(P), allIdx = [allIdx; P(k).idx(:)]; end %#ok<AGROW>
            allIdx = unique(allIdx);
            rows = unique(combo(allIdx)); rows = sort(rows);

            nP = numel(P);
            data = cell(numel(rows) + 1, 1 + 2*nP);
            % TOTAL row
            data{1,1} = 'TOTAL';
            for p = 1:nP
                idx = P(p).idx(:);
                data{1, 2*p}   = numel(idx);
                data{1, 2*p+1} = numel(unique(UU(idx)));
            end
            % per-combo rows
            for r = 1:numel(rows)
                data{r+1, 1} = char(rows(r));
                for p = 1:nP
                    idx = P(p).idx(:);
                    inRow = idx(combo(idx) == rows(r));
                    data{r+1, 2*p}   = numel(inRow);
                    data{r+1, 2*p+1} = numel(unique(UU(inRow)));
                end
            end

            cn = cell(1, 1 + 2*nP); cn{1} = 'Group';
            for p = 1:nP
                cn{2*p}   = [P(p).label ' obs'];
                cn{2*p+1} = [P(p).label ' uniq'];
            end
            obj.Table.ColumnName = cn;
            obj.Table.Data = data;
        end
    end

    methods (Static)
        function P = normalizePanels(panels)
            %NORMALIZEPANELS  Coerce to a struct array with fields label,idx.
            P = struct('label',{},'idx',{});
            if isempty(panels), return; end
            for k = 1:numel(panels)
                e = panels(k);
                lab = sprintf('P%d', k); if isfield(e,'label') && ~isempty(e.label), lab = char(e.label); end
                idx = []; if isfield(e,'idx'), idx = e.idx(:); end
                P(end+1) = struct('label', lab, 'idx', idx); %#ok<AGROW>
            end
        end

        function lab = dimLabels(D, dim)
            %DIMLABELS  Nx1 string of the category value of each unit for `dim`.
            N = viz.plots.V01util.nU(D);
            lab = strings(N,1);
            switch lower(strtrim(char(dim)))
                case 'layer'
                    v = viz.plots.V01util.layerNum(D);
                    names = ["SG","G","IG","Deep"]; lab(:) = "(n/a)";
                    ok = isfinite(v); vv = min(max(round(v(ok)),1),4); lab(ok) = names(vv);
                case {'g_type','gtype'}
                    v = viz.plots.V01util.colv(D,'G_type',N);
                    names = ["Linear","Non-linear","Unknown"]; lab(:) = "(n/a)";
                    ok = isfinite(v) & v >= 1 & v <= 3; lab(ok) = names(round(v(ok)));
                case {'e/i','ei'}
                    isI = viz.plots.V01util.isInhib(D); lab(:) = "E"; lab(isI) = "I";
                case 'animal'
                    if isfield(D,'Animal'),       lab = string(D.Animal(:));
                    elseif isfield(D,'Dataset'),  lab = "DS" + string(D.Dataset(:));
                    end
                case 'penetration'
                    if isfield(D,'Penetration'),  lab = "P" + string(D.Penetration(:)); end
                case {'task','tasknumb'}
                    if isfield(D,'Tasknumb'),     lab = string(D.Tasknumb(:)); end
            end
            if numel(lab) ~= N, lab = strings(N,1); end
            lab(ismissing(lab) | lab == "") = "(n/a)";
        end
    end
end
