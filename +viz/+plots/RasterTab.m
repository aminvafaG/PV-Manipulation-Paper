classdef RasterTab < viz.PlotTab
%RASTERTAB  Spike raster for one (filtered) unit.
%
%   Demonstrates: a SWITCH (laser / no-laser) + a SLIDER stepping through the
%   units that pass the active filter, and how to plot cell-array data (rasters)
%   rather than scalar metrics.

    properties
        Ax
        CondSwitch     % Laser / No-laser
        UnitSlider
        UnitLabel
    end

    methods
        function obj = RasterTab()
            obj@viz.PlotTab('Raster');
        end

        function buildControls(obj, parent)
            g = uigridlayout(parent, [7 1]);
            g.RowHeight = {20,40, 20,40, 24, 20, '1x'};
            g.RowSpacing = 4; g.Padding = [8 8 8 8];

            uilabel(g, 'Text', 'Condition');
            obj.CondSwitch = uiswitch(g, 'Items', {'Laser','No-laser'}, ...
                'Value', 'Laser', 'ValueChangedFcn', @(s,e) obj.requestRefresh());

            uilabel(g, 'Text', 'Unit (within filter)');
            obj.UnitSlider = uislider(g, 'Limits', [1 2], 'Value', 1, ...
                'ValueChangedFcn', @(s,e) obj.requestRefresh());

            obj.addStepButtons(g, obj.UnitSlider, 1);   % [ - | + ] for the unit slider

            obj.UnitLabel = uilabel(g, 'Text', 'unit: -');
            obj.addDataSelectors(g);
        end

        function buildView(obj, parent)
            g = uigridlayout(parent, [1 1]); g.Padding = [4 4 4 4];
            obj.Ax = uiaxes(g);
        end

        function update(obj, D, mask)
            cla(obj.Ax);
            idx = find(mask);
            obj.setSliderRange(numel(idx));
            if isempty(idx), title(obj.Ax, 'No units pass the filter'); return; end

            k    = min(max(round(obj.UnitSlider.Value), 1), numel(idx));
            unit = idx(k);
            obj.UnitLabel.Text = sprintf('unit: %d  (%d/%d)', unit, k, numel(idx));

            if strcmp(obj.CondSwitch.Value, 'Laser'), ras = D.RasL; else, ras = D.RasNL; end
            r = ras{unit};                              % trials x timebins

            % === CUSTOMISE YOUR PLOT HERE ===============================
            % Simple spike scatter (trial vs time bin). Replace with PSTH, etc.
            [tr, t] = find(r);
            plot(obj.Ax, t, tr, '.', 'MarkerSize', 4);
            xlabel(obj.Ax, 'time bin'); ylabel(obj.Ax, 'trial');
            if ~isempty(r), ylim(obj.Ax, [0 size(r,1)+1]); end
            title(obj.Ax, sprintf('%s raster -- unit %d', obj.CondSwitch.Value, unit));
            % ============================================================
        end

        function s = getControlState(obj)
            s = struct('cond', obj.CondSwitch.Value, 'unit', obj.UnitSlider.Value);
        end

        function setControlState(obj, s)
            if isfield(s,'cond'), obj.setCtrl(obj.CondSwitch, s.cond); end
            if isfield(s,'unit'), obj.setCtrl(obj.UnitSlider, s.unit); end
        end
    end

    methods (Access = private)
        function setSliderRange(obj, n)
            obj.UnitSlider.Limits = [1, max(2, n)];
            if obj.UnitSlider.Value > max(2, n)
                obj.UnitSlider.Value = 1;
            end
        end
    end
end
