classdef ScatterTab < viz.PlotTab
%SCATTERTAB  Scatter any numeric per-unit metric against another.
%
%   Demonstrates: dropdown controls + a slider, and how update() honours the
%   active filter mask. Copy this file as a template for new plot pages.

    properties
        Ax            % uiaxes
        XDD           % X-variable dropdown
        YDD           % Y-variable dropdown
        SizeSlider    % marker-size slider
        NumVars = {}  % cached numeric variable names
        SelectedUnit = NaN   % last clicked unit (ringed across redraws / sent to the inspector)
    end

    methods
        function obj = ScatterTab()
            obj@viz.PlotTab('Scatter');
        end

        % --- OPTIONAL: a default LOCAL filter just for this tab -----------
        % function f = defaultFilters(~)
        %     f = filter.FilterRule('FR_L','numeric','>',0,'local');
        % end

        function buildControls(obj, parent)
            [names, types] = filter.filterableVars(obj.Viz.D, obj.Viz.N);
            obj.NumVars = names(strcmp(types, 'numeric'));
            if isempty(obj.NumVars), obj.NumVars = {'(none)'}; end

            g = uigridlayout(parent, [8 1]);
            g.RowHeight = {20,28, 20,28, 20,40, 24, '1x'};
            g.RowSpacing = 4; g.Padding = [8 8 8 8];

            uilabel(g, 'Text', 'X variable');
            obj.XDD = uidropdown(g, 'Items', obj.NumVars, ...
                'ValueChangedFcn', @(s,e) obj.requestRefresh());
            uilabel(g, 'Text', 'Y variable');
            obj.YDD = uidropdown(g, 'Items', obj.NumVars, ...
                'Value', obj.NumVars{min(2,end)}, ...
                'ValueChangedFcn', @(s,e) obj.requestRefresh());
            uilabel(g, 'Text', 'Marker size');
            obj.SizeSlider = uislider(g, 'Limits', [4 60], 'Value', 18, ...
                'ValueChangedFcn', @(s,e) obj.requestRefresh());
            obj.addStepButtons(g, obj.SizeSlider, 2);   % [ - | + ] for marker size
            obj.addInspectCheckbox(g);
            obj.addDataSelectors(g);
        end

        function buildView(obj, parent)
            g = uigridlayout(parent, [1 1]); g.Padding = [4 4 4 4];
            obj.Ax = uiaxes(g);
        end

        function update(obj, D, mask)
            xn = obj.XDD.Value; yn = obj.YDD.Value;
            cla(obj.Ax);
            if ~isfield(D, xn) || ~isfield(D, yn), return; end

            % === CUSTOMISE YOUR PLOT HERE ===============================
            x = D.(xn); y = D.(yn);
            reps = find(mask(:));                 % unit (D row) index of each plotted point
            xp = double(x(mask)); yp = double(y(mask));
            % PickableParts 'none' so every click (even on a marker) reaches the
            % axes ButtonDownFcn -> "click near a unit" picking below.
            scatter(obj.Ax, xp, yp, obj.SizeSlider.Value, 'filled', 'PickableParts','none');
            xlabel(obj.Ax, xn, 'Interpreter', 'none');
            ylabel(obj.Ax, yn, 'Interpreter', 'none');
            title(obj.Ax, sprintf('%d / %d units', nnz(mask), numel(mask)));
            grid(obj.Ax, 'on');
            obj.Ax.ButtonDownFcn = @(s,e) obj.onScatterPick(s, e, xp(:), yp(:), reps);
            obj.registerRing(obj.Ax, xp(:), yp(:), reps);   % track unit across plots
            viz.plots.V01util.highlightUnits(obj.Ax, xp(:), yp(:), reps, obj.SelectedUnit);
            % ============================================================
        end

        function onScatterPick(obj, ax, e, X, Y, reps)
            %ONSCATTERPICK  Ring the unit nearest the click and send it to the
            %   shared unit-inspector popup (no-op unless inspect-on-click is on).
            if isempty(reps), return; end
            try, pt = e.IntersectionPoint(1:2); catch, return; end %#ok<CTCH>
            u = viz.plots.V01util.nearestUnit(ax, X, Y, reps, pt);
            if ~isfinite(u), return; end
            obj.SelectedUnit = u;
            viz.plots.V01util.highlightUnits(ax, X, Y, reps, u);
            obj.inspectPick(u);
            obj.trackPick(u);
        end

        function s = getControlState(obj)
            s = struct('X', obj.XDD.Value, 'Y', obj.YDD.Value, ...
                       'size', obj.SizeSlider.Value);
        end

        function setControlState(obj, s)
            if isfield(s,'X'),    obj.setCtrl(obj.XDD, s.X); end
            if isfield(s,'Y'),    obj.setCtrl(obj.YDD, s.Y); end
            if isfield(s,'size'), obj.setCtrl(obj.SizeSlider, s.size); end
        end
    end
end
