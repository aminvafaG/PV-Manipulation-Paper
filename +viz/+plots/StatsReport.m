classdef StatsReport < handle
%STATSREPORT  Shared, toggle-able stats report panel for a figure tab.
%
%   r = viz.plots.StatsReport(parent)   create (hidden) inside `parent`
%   r.update(out, headerTxt)            fill from analysis.stats.compute output
%   r.setVisible(tf)                    show / hide
%
%   The figures open in their own windows, so each figure tab's body is free to
%   host this report (STATS_REPORTING_PLAN.md decision D4). It renders the
%   compute() result -- one row per statistic, one column per repeated-obs mode
%   (All / First / Mean / Mixed-effects) so they read side-by-side -- plus a
%   header line and a Copy button.
%
%   See also: analysis.stats.compute, viz.plots.LayerSelectivity02Tab

    properties
        Panel; Grid; Header; Table; CopyBtn; Legend
        LastCols = {}; LastData = {}
    end

    methods
        function obj = StatsReport(parent)
            obj.Panel = uipanel(parent, 'BorderType', 'none', 'Visible', 'off');
            obj.Grid  = uigridlayout(obj.Panel, [3 1]);
            obj.Grid.RowHeight = {'fit', '1x', 'fit'};
            obj.Grid.Padding   = [6 6 6 6];
            obj.Grid.RowSpacing = 4;

            obj.Header = uilabel(obj.Grid, 'Text', 'Statistics report', ...
                'FontWeight', 'bold', 'WordWrap', 'on');
            obj.Header.Layout.Row = 1;

            obj.Table = uitable(obj.Grid);
            obj.Table.Layout.Row = 2;
            try, obj.Table.FontName = 'Consolas'; catch, end %#ok<CTCH>
            obj.Table.RowName = {};

            btnRow = uigridlayout(obj.Grid, [1 2]);
            btnRow.Layout.Row  = 3;
            btnRow.ColumnWidth = {160, '1x'};
            btnRow.Padding     = [0 0 0 0];
            obj.CopyBtn = uibutton(btnRow, 'Text', 'Copy to clipboard', ...
                'ButtonPushedFcn', @(s,e) obj.copy());
            obj.Legend = uilabel(btnRow, 'Text', obj.defaultLegend(), ...
                'FontSize', 10, 'FontColor', [.4 .4 .4]);
        end

        function update(obj, out, headerTxt)
            if nargin >= 3 && ~isempty(headerTxt), obj.Header.Text = headerTxt; end
            obj.Table.ColumnName = out.ColumnName(:)';
            obj.Table.Data       = out.Data;
            obj.LastCols = out.ColumnName; obj.LastData = out.Data;
            % A descriptive table (e.g. Supplementary Table 1) may carry its own
            % footer legend; otherwise restore the default p-value legend.
            if isfield(out,'legend') && ~isempty(out.legend), obj.setLegend(out.legend);
            else, obj.setLegend(obj.defaultLegend()); end
            % Red where the mixed-effects significance differs from the All method.
            try, removeStyle(obj.Table); catch, end %#ok<CTCH>
            if isfield(out,'highlightRows') && ~isempty(out.highlightRows) && ...
                    isfield(out,'lmeCol') && ~isempty(out.lmeCol)
                try
                    stl = uistyle('FontColor', [0.80 0 0], 'FontWeight', 'bold');
                    rc  = [out.highlightRows(:), repmat(out.lmeCol, numel(out.highlightRows), 1)];
                    addStyle(obj.Table, stl, 'cell', rc);
                catch
                end
            end
        end

        function setVisible(obj, tf)
            if tf, obj.Panel.Visible = 'on'; else, obj.Panel.Visible = 'off'; end
        end

        function txt = defaultLegend(~)
            %DEFAULTLEGEND  The p-value footer used by the per-test reports.
            txt = ['*** p<.001   ** p<.01   * p<.05.   ' ...
                'N = observations / distinct neurons (All mode).   ' ...
                'Every mode cell shows that mode''s OWN mean +/- s.e.m. in parentheses ' ...
                '(paired: ctrl -> laser; between: group A vs B; ANOVA: per group); read ' ...
                'per-cell values off Mean/neuron or Mixed-effects.  Effect repeats the ' ...
                'All-mode descriptives (+ medians / effect size).   ' ...
                'LME p(BH) = Benjamini-Hochberg-adjusted Mixed-effects p across this report''s tests.   ' ...
                'RED Mixed-effects cell = significance differs from All (repeated-recording effect).'];
        end

        function setLegend(obj, txt)
            %SETLEGEND  Replace the footer legend (e.g. for non-p-value tables).
            if ~isempty(obj.Legend) && isvalid(obj.Legend), obj.Legend.Text = txt; end
        end

        function copy(obj)
            if isempty(obj.LastData), return; end
            txt = strjoin(cellfun(@i_str, obj.LastCols(:)', 'UniformOutput', false), sprintf('\t'));
            for i = 1:size(obj.LastData, 1)
                row = cellfun(@i_str, obj.LastData(i,:), 'UniformOutput', false);
                txt = [txt, newline, strjoin(row, sprintf('\t'))]; %#ok<AGROW>
            end
            try, clipboard('copy', txt); catch, end %#ok<CTCH>
        end
    end
end

function s = i_str(v)
    if ischar(v), s = v;
    elseif isstring(v), s = char(v);
    elseif isnumeric(v) && isscalar(v), s = num2str(v);
    else, s = ''; end
end
