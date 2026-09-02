classdef UnitInspector < handle
%UNITINSPECTOR  Floating window that shows ONE selected unit's V01 panels.
%
%   Clicking near a unit in any scatter plot (in any tab, or in a tab's "Open
%   figure window" popup) opens this window -- or updates it in place if it is
%   already open -- with that single unit's:
%       * raster, laser   * raster, control
%       * center-shifted tuning curves (laser + control)
%       * circular (polar) tuning
%       * delta / ratio tuning
%   drawn EXACTLY as Dashboard01Tab's per-unit example panels (shared code in
%   viz.plots.UnitPanels). Close it and click another unit and it re-opens.
%
%   A single shared instance lives on the viz.Visualizer (obj.UnitInspector);
%   every tab routes its picks through viz.Visualizer.inspectUnit.
%
%   See also: viz.plots.UnitPanels, viz.Visualizer.inspectUnit

    properties
        Fig                                   % the uifigure (empty/invalid when closed)
        axRasL; axRasC; axTun; axPolar; axDR  % the five panels
        titleLbl                              % header label (unit id / U_unity / E-I / layer)
        metricsTbl                            % SI / HBW / CV (control vs laser vs delta) readout
        CurrentUnit = NaN                     % last unit drawn (D row index)
    end

    properties (Constant)
        COL_E = [0 1 0];   COL_I = [0 0 1];    % per-condition example colors (match V01)
    end

    methods
        function tf = isOpen(obj)
            tf = ~isempty(obj.Fig) && isvalid(obj.Fig);
        end

        function show(obj, D, u)
            %SHOW  Open (if needed) and draw unit `u`; bring the window to front.
            if isempty(u) || ~isfinite(u), return; end
            if isempty(D), return; end
            if ~obj.isOpen(), obj.build(); end
            obj.CurrentUnit = u;
            obj.draw(D, u);
            try, figure(obj.Fig); catch, end %#ok<CTCH>
        end

        function close(obj)
            if obj.isOpen(), delete(obj.Fig); end
        end
    end

    methods (Access = private)
        function build(obj)
            obj.Fig = uifigure('Name','Unit inspector', 'Color','w', ...
                'Position', [140 90 800 760]);
            g = uigridlayout(obj.Fig, [5 2]);
            g.RowHeight    = {24, 108, '1x', '1x', '1x'};
            g.ColumnWidth  = {'1x','1x'};
            g.RowSpacing   = 6; g.ColumnSpacing = 8; g.Padding = [10 10 10 10];

            obj.titleLbl = uilabel(g, 'Text','(no unit)', 'FontWeight','bold', ...
                'HorizontalAlignment','center', 'FontSize',13, 'Interpreter','none');
            obj.titleLbl.Layout.Row = 1; obj.titleLbl.Layout.Column = [1 2];

            % SI / HBW / CV fitted tuning metrics for control vs laser (+ laser-effect delta)
            obj.metricsTbl = uitable(g, 'RowName', {'SI','HBW (deg)','CV'}, ...
                'ColumnName', {'Control','Laser','L - NL'}, ...
                'ColumnWidth', {90, 90, 90}, 'RowStriping','off', ...
                'Tooltip', ['Fitted orientation metrics for this unit.  ' ...
                    'SI = orientation selectivity (fitOSI),  HBW = half-bandwidth (deg),  ' ...
                    'CV = circular variance.  L - NL = laser minus control.']);
            obj.metricsTbl.Layout.Row = 2; obj.metricsTbl.Layout.Column = [1 2];

            obj.axRasC = uiaxes(g); obj.axRasC.Layout.Row = 3; obj.axRasC.Layout.Column = 1;  % control raster
            obj.axRasL = uiaxes(g); obj.axRasL.Layout.Row = 3; obj.axRasL.Layout.Column = 2;  % laser raster
            obj.axTun  = uiaxes(g); obj.axTun.Layout.Row  = 4; obj.axTun.Layout.Column  = 1;  % tuning curves

            % polaraxes can be finicky inside a grid cell -> host it in a panel.
            pPol = uipanel(g, 'BorderType','none');
            pPol.Layout.Row = 4; pPol.Layout.Column = 2;
            obj.axPolar = polaraxes(pPol);
            obj.axPolar.Units = 'normalized'; obj.axPolar.Position = [0.12 0.10 0.80 0.82];

            obj.axDR = uiaxes(g); obj.axDR.Layout.Row = 5; obj.axDR.Layout.Column = [1 2];    % delta/ratio
        end

        function draw(obj, D, u)
            if ~obj.isOpen(), return; end
            obj.clearAxes();
            if viz.plots.UnitPanels.isInhibUnit(D, u), Cc = obj.COL_I; else, Cc = obj.COL_E; end
            % drawAll(axLaser, axControl, axTun, axPolar, axDR, ...)
            viz.plots.UnitPanels.drawAll(obj.axRasL, obj.axRasC, obj.axTun, obj.axPolar, obj.axDR, D, u, Cc);
            title(obj.axRasC, 'Raster - Control');
            title(obj.axRasL, 'Raster - Laser ON');
            title(obj.axTun,  'Tuning (centered): Laser vs Control');
            title(obj.axPolar,'Circular tuning');
            title(obj.axDR,   'Delta (red) / Ratio (cyan)');
            obj.titleLbl.Text = obj.makeTitle(D, u);
            obj.updateMetrics(D, u);
        end

        function updateMetrics(obj, D, u)
            %UPDATEMETRICS  Fill the SI/HBW/CV table for unit `u`: control, laser,
            %   and the laser-effect delta (L - NL). A missing/failed fit shows '-'.
            if isempty(obj.metricsTbl) || ~isvalid(obj.metricsTbl), return; end
            siC  = obj.fieldAt(D,'fitOSI_NL',u); siL  = obj.fieldAt(D,'fitOSI_L',u);
            hbwC = obj.fieldAt(D,'fitHBW_NL',u); hbwL = obj.fieldAt(D,'fitHBW_L',u);
            cvC  = obj.fieldAt(D,'fitCV_NL', u); cvL  = obj.fieldAt(D,'fitCV_L', u);
            obj.metricsTbl.Data = { ...
                obj.fmtNum(siC),  obj.fmtNum(siL),  obj.fmtNum(siL  - siC); ...
                obj.fmtNum(hbwC), obj.fmtNum(hbwL), obj.fmtNum(hbwL - hbwC); ...
                obj.fmtNum(cvC),  obj.fmtNum(cvL),  obj.fmtNum(cvL  - cvC) };
        end

        function clearAxes(obj)
            for ax = {obj.axRasC, obj.axRasL, obj.axTun}
                if ~isempty(ax{1}) && isvalid(ax{1}), cla(ax{1}); end
            end
            try, cla(obj.axPolar); catch, end %#ok<CTCH>
            % delta/ratio uses yyaxis -> clear both sides
            try
                yyaxis(obj.axDR,'left');  cla(obj.axDR);
                yyaxis(obj.axDR,'right'); cla(obj.axDR);
            catch
                try, cla(obj.axDR); catch, end %#ok<CTCH>
            end
        end

        function s = makeTitle(~, D, u)
            uu = NaN; if isfield(D,'U_unity') && numel(D.U_unity) >= u, uu = double(D.U_unity(u)); end
            ei = ''; if isfield(D,'EI') && numel(D.EI) >= u, ei = char(strtrim(string(D.EI(u)))); end
            lg = ''; if isfield(D,'LG') && numel(D.LG) >= u, lg = char(strtrim(string(D.LG(u)))); end
            s = sprintf('Unit #%d    U_unity %g    E/I %s    Layer %s', u, uu, ei, lg);
            % animal / penetration / task number -- shown when the dataset carries them
            extra = {};
            if isfield(D,'Animal') && numel(D.Animal) >= u
                a = char(strtrim(string(D.Animal(u))));
                if isempty(a) && isfield(D,'Dataset') && numel(D.Dataset) >= u, a = num2str(D.Dataset(u)); end
                if ~isempty(a), extra{end+1} = ['Animal ' a]; end
            elseif isfield(D,'Dataset') && numel(D.Dataset) >= u
                extra{end+1} = ['Animal ' num2str(D.Dataset(u))];
            end
            if isfield(D,'Penetration') && numel(D.Penetration) >= u
                extra{end+1} = ['Pen ' char(string(D.Penetration(u)))];
            end
            if isfield(D,'Tasknumb') && numel(D.Tasknumb) >= u
                tk = char(strtrim(string(D.Tasknumb(u))));
                if ~isempty(tk), extra{end+1} = ['Task ' tk]; end
            end
            if ~isempty(extra), s = sprintf('%s    |    %s', s, strjoin(extra, '   ')); end
        end
    end

    methods (Static, Access = private)
        function v = fieldAt(D, name, u)
            %FIELDAT  D.(name)(u) as a double, or NaN if the field/row is absent.
            v = NaN;
            if isfield(D, name) && numel(D.(name)) >= u, v = double(D.(name)(u)); end
        end
        function s = fmtNum(x)
            %FMTNUM  Compact metric string ('-' for NaN/empty, else 3 sig figs).
            if isempty(x) || ~isfinite(x), s = '-'; else, s = sprintf('%.3g', x); end
        end
    end
end
