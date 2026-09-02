classdef Model_APP_01 < handle
    % MODEL_APP_01
    %
    % User-friendly interactive app for the simple PV+ model used for Fig.
    % 6. in: "Laminar-specific control of response gain and orientation-tuning
    % by parvalbumin-expressing inhibitory interneurons in primate visual
    % cortex" https://doi.org/10.64898/2025.12.23.696300
    %
    % REQUIREMENTS
    %   - MATLAB with UI components (uifigure/uigridlayout/uiaxes, etc.)
    %
    % RUN
    %   app = Model_APP_01();

    properties
        % ---- UI ----
        Fig
        MainGrid
        ControlsPanel
        ControlsGrid
        PlotGrid
        ParamsPanel
        ParamsGrid

        Axes

        ParameterDropdown
        ParameterHelpButton
        ResetButton

        Slider
        ValueEdit
        MinEdit
        MaxEdit

        StateSwitch   % ToggleSwitch

        ParamsTable
        AboutButton

        % ---- Model parameters ----
        ParamMeta
        Params
        DefaultSets   % struct with two parameter presets (Non-granular / Granular)
        SelectedKey
        IsGranular = false

        % If true, flipping the StateSwitch immediately loads the
        % corresponding preset values (acts like a "preset selector").
        AutoLoadPresetOnToggle = true

        % ---- Plot handles (for fast updates) ----
        PlotH

        % ---- Internal state ----
        IsUpdating = false
    end

    methods
        function obj = Model_APP_01()
            obj.ParamMeta = obj.buildParameterMeta();
            % Two presets (Non-granular vs Granular)
            obj.DefaultSets = obj.buildDefaultSets(obj.ParamMeta);

            obj.buildUI();

            % Choose the preset based on the current switch value (this is
            % the app's "start point").
            obj.IsGranular = strcmpi(obj.StateSwitch.Value, 'Granular');
            obj.Params     = obj.sanitizeParamsAgainstMeta(obj.getDefaultsForState(obj.StateSwitch.Value));

            obj.initializePlots();

            obj.SelectedKey = "manipulationIOFThreshold";
            obj.syncControlsToSelectedParameter();
            obj.updatePlots();
        end
    end

    methods (Access = private)

        % =================================================================
        % UI BUILD
        % =================================================================
        function buildUI(obj)
            initialMonitorBounds = obj.getTargetMonitorBounds();
            initialFigurePosition = obj.getMonitorRelativeFigurePosition(initialMonitorBounds);

            obj.Fig = uifigure( ...
                'Name', 'PV+ tuning model (Fig. 6) - Model_APP_01', ...
                'Color', 'w', ...
                'Position', initialFigurePosition, ...
                'WindowKeyPressFcn', @(s,e)obj.onWindowKeyPress(e));

            % Main layout: controls (top) + plots (left) + table (right)
            obj.MainGrid = uigridlayout(obj.Fig, [2 2]);
            obj.MainGrid.RowHeight     = {130, '1x'};
            obj.MainGrid.ColumnWidth   = {'3x', '1x'};
            obj.MainGrid.Padding       = [10 10 10 10];
            obj.MainGrid.RowSpacing    = 10;
            obj.MainGrid.ColumnSpacing = 10;

            % ---------------- Controls panel (spans both columns) ----------------
            obj.ControlsPanel = uipanel(obj.MainGrid, 'Title', 'Controls');
            obj.ControlsPanel.Layout.Row = 1;
            obj.ControlsPanel.Layout.Column = [1 2];

            % Keep controls compact so the state switch is always visible
            % even on narrower screens (the previous 12-column grid could
            % clip right-side widgets on some displays).
            obj.ControlsGrid = uigridlayout(obj.ControlsPanel, [3 8]);
            obj.ControlsGrid.RowHeight     = {28, 28, 28};
            obj.ControlsGrid.ColumnWidth   = {90, 260, 40, 90, 90, 140, 90, '1x'};
            obj.ControlsGrid.Padding       = [10 10 10 10];
            obj.ControlsGrid.RowSpacing    = 8;
            obj.ControlsGrid.ColumnSpacing = 8;

            % Row 1: Parameter selection + help + reset + color scheme
            lbl = uilabel(obj.ControlsGrid, 'Text', 'Parameter:', 'HorizontalAlignment','right');
            lbl.Layout.Row = 1; lbl.Layout.Column = 1;

            labels = string({obj.ParamMeta.Label});
            keys   = string({obj.ParamMeta.Key});
            obj.ParameterDropdown = uidropdown(obj.ControlsGrid, ...
                'Items', cellstr(labels), ...
                'ItemsData', cellstr(keys), ...
                'ValueChangedFcn', @(s,e)obj.onParameterSelectionChanged(), ...
                'Tooltip', 'Choose a model parameter to modify.');
            obj.ParameterDropdown.Layout.Row = 1;
            obj.ParameterDropdown.Layout.Column = 2;

            obj.ParameterHelpButton = uibutton(obj.ControlsGrid, 'Text', '?', ...
                'ButtonPushedFcn', @(s,e)obj.showSelectedParameterHelp(), ...
                'Tooltip', 'Show short explanation for the selected parameter.');
            obj.ParameterHelpButton.Layout.Row = 1;
            obj.ParameterHelpButton.Layout.Column = 3;

            obj.ResetButton = uibutton(obj.ControlsGrid, 'Text', 'Reset', ...
                'ButtonPushedFcn', @(s,e)obj.resetToDefaults(), ...
                'Tooltip', 'Reset all parameters to their defaults.');
            obj.ResetButton.Layout.Row = 1;
            obj.ResetButton.Layout.Column = 4;

            % lbl = uilabel(obj.ControlsGrid, 'Text', 'Model state:', 'HorizontalAlignment','right');
            % lbl.Layout.Row = 1; lbl.Layout.Column = 5;

            obj.StateSwitch = uiswitch(obj.MainGrid, 'toggle');
            obj.StateSwitch.Items = {'Non-granular','Granular'};
            obj.StateSwitch.Value = 'Non-granular';
            obj.StateSwitch.ValueChangedFcn = @(s,e)obj.onStateChanged();
            obj.StateSwitch.Tooltip = 'Toggle between Non-granular vs Granular state (affects control/manip colors).';
            obj.StateSwitch.Layout.Row = 1;
            obj.StateSwitch.Layout.Column = 2;

            % Row 2: Slider + value entry

            lbl = uilabel(obj.ControlsGrid, 'Text', 'Value:', 'HorizontalAlignment','right');
            lbl.Layout.Row = 2; lbl.Layout.Column = 1;

            obj.Slider = uislider(obj.ControlsGrid, ...
                'ValueChangingFcn', @(s,e)obj.onSliderChanging(e.Value), ...
                'ValueChangedFcn',  @(s,e)obj.onSliderChanged(), ...
                'Tooltip', 'Drag to update the selected parameter (continuous).');
            obj.Slider.Layout.Row = 2;
            obj.Slider.Layout.Column = [2 6];

            obj.ValueEdit = uieditfield(obj.ControlsGrid, 'numeric', ...
                'ValueChangedFcn', @(s,e)obj.onValueEditChanged(), ...
                'Tooltip', 'Type a numeric value and press Enter.');
            obj.ValueEdit.Layout.Row = 2;
            obj.ValueEdit.Layout.Column = 7;

            % Row 3: slider range controls
            lbl = uilabel(obj.ControlsGrid, 'Text', 'Min:', 'HorizontalAlignment','right');
            lbl.Layout.Row = 3; lbl.Layout.Column = 1;

            obj.MinEdit = uieditfield(obj.ControlsGrid, 'numeric', ...
                'ValueChangedFcn', @(s,e)obj.onRangeChanged(), ...
                'Tooltip', 'Slider minimum (you can change it).');
            obj.MinEdit.Layout.Row = 3;
            obj.MinEdit.Layout.Column = 2;

            lbl = uilabel(obj.ControlsGrid, 'Text', 'Max:', 'HorizontalAlignment','right');
            lbl.Layout.Row = 3; lbl.Layout.Column = 3;

            obj.MaxEdit = uieditfield(obj.ControlsGrid, 'numeric', ...
                'ValueChangedFcn', @(s,e)obj.onRangeChanged(), ...
                'Tooltip', 'Slider maximum (you can change it).');
            obj.MaxEdit.Layout.Row = 3;
            obj.MaxEdit.Layout.Column = 4;

            % ---------------- Plots grid ----------------
            obj.PlotGrid = uigridlayout(obj.MainGrid, [2 3]);
            obj.PlotGrid.Layout.Row = 2;
            obj.PlotGrid.Layout.Column = 1;
            obj.PlotGrid.RowHeight = {'1x','1x'};
            obj.PlotGrid.ColumnWidth = {'1x','1x','1x'};
            obj.PlotGrid.RowSpacing = 10;
            obj.PlotGrid.ColumnSpacing = 10;

            obj.Axes = gobjects(1,6);
            for k = 1:6
                obj.Axes(k) = uiaxes(obj.PlotGrid);
                obj.Axes(k).FontSize = 11;
                obj.Axes(k).LineWidth = 1;
                grid(obj.Axes(k), 'on');
                box(obj.Axes(k), 'on');
            end
            obj.Axes(1).Layout.Row = 1; obj.Axes(1).Layout.Column = 1;
            obj.Axes(2).Layout.Row = 1; obj.Axes(2).Layout.Column = 2;
            obj.Axes(3).Layout.Row = 1; obj.Axes(3).Layout.Column = 3;
            obj.Axes(4).Layout.Row = 2; obj.Axes(4).Layout.Column = 1;
            obj.Axes(5).Layout.Row = 2; obj.Axes(5).Layout.Column = 2;
            obj.Axes(6).Layout.Row = 2; obj.Axes(6).Layout.Column = 3;

            % ---------------- Parameters panel (table + about) ----------------
            obj.ParamsPanel = uipanel(obj.MainGrid, 'Title', 'Current parameter values');
            obj.ParamsPanel.Layout.Row = 2;
            obj.ParamsPanel.Layout.Column = 2;

            obj.ParamsGrid = uigridlayout(obj.ParamsPanel, [2 1]);
            obj.ParamsGrid.RowHeight = {'1x', 40};
            obj.ParamsGrid.Padding = [10 10 10 10];

            obj.ParamsTable = uitable(obj.ParamsGrid, ...
                'ColumnName', {'Parameter', 'Value'}, ...
                'ColumnEditable', [false false], ...
                'RowName', {});
            obj.ParamsTable.Layout.Row = 1;

            obj.AboutButton = uibutton(obj.ParamsGrid, 'Text', 'About / How to use', ...
                'ButtonPushedFcn', @(s,e)obj.showAboutDialog(), ...
                'Tooltip', 'Shows a short description of the model and usage tips.');
            obj.AboutButton.Layout.Row = 2;

            % Initialize dropdown selection to first item
            obj.ParameterDropdown.Value = obj.ParameterDropdown.ItemsData{1};

            drawnow;
            obj.applyResponsiveLayout();
            obj.Fig.SizeChangedFcn = @(s,e)obj.onFigureSizeChanged();
        end

        function onFigureSizeChanged(obj)
            if isempty(obj.Fig) || ~isvalid(obj.Fig) || isempty(obj.MainGrid) || ~isvalid(obj.MainGrid)
                return;
            end

            obj.applyResponsiveLayout();
        end

        function applyResponsiveLayout(obj)
            if isempty(obj.Fig) || ~isvalid(obj.Fig)
                return;
            end

            figSize = max(round(obj.Fig.Position(3:4)), [720 540]);
            refFigureSize = [1840 1000];

            mainPaddingX = obj.scalePixelValue(10, figSize(1), refFigureSize(1), 6, 24);
            mainPaddingY = obj.scalePixelValue(10, figSize(2), refFigureSize(2), 6, 24);
            mainRowHeight = obj.scalePixelValue(130, figSize(2), refFigureSize(2), 110, 220);
            mainRowSpacing = obj.scalePixelValue(10, figSize(2), refFigureSize(2), 6, 20);
            mainColumnSpacing = obj.scalePixelValue(10, figSize(1), refFigureSize(1), 6, 20);

            controlRowHeight = obj.scalePixelValue(28, figSize(2), refFigureSize(2), 24, 42);
            controlPaddingX = obj.scalePixelValue(10, figSize(1), refFigureSize(1), 6, 20);
            controlPaddingY = obj.scalePixelValue(10, figSize(2), refFigureSize(2), 6, 20);
            controlRowSpacing = obj.scalePixelValue(8, figSize(2), refFigureSize(2), 6, 16);
            controlColumnSpacing = obj.scalePixelValue(8, figSize(1), refFigureSize(1), 6, 16);

            controlColumnWidths = { ...
                obj.scalePixelValue(90,  figSize(1), refFigureSize(1), 72, 140), ...
                obj.scalePixelValue(260, figSize(1), refFigureSize(1), 190, 420), ...
                obj.scalePixelValue(40,  figSize(1), refFigureSize(1), 32, 60), ...
                obj.scalePixelValue(90,  figSize(1), refFigureSize(1), 72, 140), ...
                obj.scalePixelValue(90,  figSize(1), refFigureSize(1), 72, 140), ...
                obj.scalePixelValue(140, figSize(1), refFigureSize(1), 110, 220), ...
                obj.scalePixelValue(90,  figSize(1), refFigureSize(1), 72, 140), ...
                '1x'};

            plotSpacingX = obj.scalePixelValue(10, figSize(1), refFigureSize(1), 6, 20);
            plotSpacingY = obj.scalePixelValue(10, figSize(2), refFigureSize(2), 6, 20);
            paramsButtonHeight = obj.scalePixelValue(40, figSize(2), refFigureSize(2), 34, 56);

            fontScale = min(figSize(1) / refFigureSize(1), figSize(2) / refFigureSize(2));
            controlFontSize = max(10, min(15, round(11 * fontScale)));
            panelFontSize = max(10, min(16, round(12 * fontScale)));
            axesFontSize = max(9, min(15, round(11 * fontScale)));
            tableFontSize = max(9, min(14, round(10 * fontScale)));

            obj.MainGrid.RowHeight = {mainRowHeight, '1x'};
            obj.MainGrid.Padding = [mainPaddingX mainPaddingY mainPaddingX mainPaddingY];
            obj.MainGrid.RowSpacing = mainRowSpacing;
            obj.MainGrid.ColumnSpacing = mainColumnSpacing;

            obj.ControlsGrid.RowHeight = {controlRowHeight, controlRowHeight, controlRowHeight};
            obj.ControlsGrid.ColumnWidth = controlColumnWidths;
            obj.ControlsGrid.Padding = [controlPaddingX controlPaddingY controlPaddingX controlPaddingY];
            obj.ControlsGrid.RowSpacing = controlRowSpacing;
            obj.ControlsGrid.ColumnSpacing = controlColumnSpacing;

            obj.PlotGrid.RowSpacing = plotSpacingY;
            obj.PlotGrid.ColumnSpacing = plotSpacingX;

            obj.ParamsGrid.RowHeight = {'1x', paramsButtonHeight};
            obj.ParamsGrid.Padding = [controlPaddingX controlPaddingY controlPaddingX controlPaddingY];

            obj.applyFontSizeToChildren(obj.ControlsGrid, controlFontSize);
            obj.applyFontSizeToChildren(obj.ParamsGrid, controlFontSize);

            obj.ControlsPanel.FontSize = panelFontSize;
            obj.ParamsPanel.FontSize = panelFontSize;
            obj.AboutButton.FontSize = controlFontSize;
            obj.ParamsTable.FontSize = tableFontSize;
            if isprop(obj.StateSwitch, 'FontSize')
                obj.StateSwitch.FontSize = controlFontSize;
            end

            for k = 1:numel(obj.Axes)
                if isgraphics(obj.Axes(k))
                    obj.Axes(k).FontSize = axesFontSize;
                end
            end
        end

        function applyFontSizeToChildren(~, parentHandle, fontSize)
            if isempty(parentHandle) || ~isvalid(parentHandle)
                return;
            end

            childHandles = parentHandle.Children;
            for k = 1:numel(childHandles)
                if isprop(childHandles(k), 'FontSize')
                    childHandles(k).FontSize = fontSize;
                end
            end
        end

        function monitorBounds = getTargetMonitorBounds(~)
            try
                monitorPositions = get(groot, 'MonitorPositions');
                if isempty(monitorPositions)
                    monitorBounds = get(groot, 'ScreenSize');
                    return;
                end

                pointerLocation = get(groot, 'PointerLocation');
                if isempty(pointerLocation) || any(~isfinite(pointerLocation))
                    monitorBounds = monitorPositions(1,:);
                    return;
                end

                monitorBounds = monitorPositions(1,:);
                for k = 1:size(monitorPositions, 1)
                    pos = monitorPositions(k,:);
                    xInMonitor = pointerLocation(1) >= pos(1) && pointerLocation(1) <= (pos(1) + pos(3));
                    yInMonitor = pointerLocation(2) >= pos(2) && pointerLocation(2) <= (pos(2) + pos(4));

                    if xInMonitor && yInMonitor
                        monitorBounds = pos;
                        return;
                    end
                end
            catch
                monitorBounds = get(groot, 'ScreenSize');
            end
        end

        function figPosition = getMonitorRelativeFigurePosition(~, monitorBounds)
            leftMargin = max(20, round(0.02 * monitorBounds(3)));
            rightMargin = max(20, round(0.02 * monitorBounds(3)));
            bottomMargin = max(20, round(0.04 * monitorBounds(4)));
            topMargin = max(20, round(0.04 * monitorBounds(4)));

            figWidth = max(600, monitorBounds(3) - leftMargin - rightMargin);
            figHeight = max(500, monitorBounds(4) - bottomMargin - topMargin);

            figWidth = min(figWidth, monitorBounds(3) - leftMargin);
            figHeight = min(figHeight, monitorBounds(4) - bottomMargin);

            figPosition = [ ...
                monitorBounds(1) + leftMargin, ...
                monitorBounds(2) + bottomMargin, ...
                figWidth, ...
                figHeight];
        end

        function pixelValue = scalePixelValue(~, basePixels, currentPixels, referencePixels, minValue, maxValue)
            pixelValue = round(basePixels * (currentPixels / referencePixels));

            if nargin >= 5 && ~isempty(minValue)
                pixelValue = max(minValue, pixelValue);
            end

            if nargin >= 6 && ~isempty(maxValue)
                pixelValue = min(maxValue, pixelValue);
            end
        end

        function initializePlots(obj)
            % --- FIX: pre-create nested struct fields before dot assignment ---
            obj.PlotH = struct();
            obj.PlotH.in    = struct();
            obj.PlotH.v     = struct();
            obj.PlotH.iof   = struct();
            obj.PlotH.out   = struct();
            obj.PlotH.deriv = struct();
            % ------------------------------------------------------------------

            [cControl, cManip] = obj.getConditionColors();

            % Axis 1: Input tuning
            ax = obj.Axes(1);
            hold(ax,'on');
            obj.PlotH.in.raw    = plot(ax, nan, nan, 'LineWidth', 2, 'Color', cManip);
            obj.PlotH.in.scaled = plot(ax, nan, nan, 'LineWidth', 2, 'Color', cControl);
            hold(ax,'off');
            ax.XLim = [0 360];

            % Axis 2: FR->V
            ax = obj.Axes(2);
            obj.PlotH.revIOF = plot(ax, nan, nan, 'LineWidth', 2, 'Color', cControl);
            ax.XLim = [0 1];

            % Axis 3: V tuning
            ax = obj.Axes(3);
            hold(ax,'on');
            obj.PlotH.v.control = plot(ax, nan, nan, 'LineStyle',':','LineWidth', 2, 'Color', cControl);
            obj.PlotH.v.manip   = plot(ax, nan, nan, 'LineStyle','--','LineWidth', 2, 'Color', cManip);
            hold(ax,'off');
            ax.XLim = [0 360];

            % Axis 4: V->FR
            ax = obj.Axes(4);
            hold(ax,'on');
            obj.PlotH.iof.control = plot(ax, nan, nan, 'LineWidth', 2, 'Color', cControl);
            obj.PlotH.iof.manip   = plot(ax, nan, nan, 'LineWidth', 2, 'Color', cManip);
            obj.PlotH.iof.x0 = xline(ax, 0, ':', 'Color', [0 0 0]);
            obj.PlotH.iof.y1 = yline(ax, 1, ':', 'Color', [0 0 0]);
            hold(ax,'off');
            ax.XLim = [-3 1];

            % Axis 5: Output tuning + diff/ratio
            ax = obj.Axes(5);
            hold(ax,'on');
            obj.PlotH.out.control = plot(ax, nan, nan, 'LineWidth', 2, 'Color', cControl);
            obj.PlotH.out.manip   = plot(ax, nan, nan, 'LineWidth', 2, 'Color', cManip);
            obj.PlotH.out.diff    = plot(ax, nan, nan, ':', 'LineWidth', 1, 'Color', [1 0 0]);
            obj.PlotH.out.ratio   = plot(ax, nan, nan, ':', 'LineWidth', 1, 'Color', [0 1 1]);
            obj.PlotH.out.peak    = plot(ax, nan, nan, 'o', 'MarkerSize', 6, ...
                'MarkerFaceColor', [1 0 0], 'MarkerEdgeColor', [0 0 0]);
            hold(ax,'off');
            ax.XLim = [0 360];

            legend(obj.Axes(5), {'Control','PV manipulation','Difference (manip-control)','Ratio (manip/control)','Control peak'}, ...
                'Location','northwest', 'AutoUpdate','off');

            % Axis 6: 2nd vs 4th derivative point
            ax = obj.Axes(6);
            hold(ax,'on');
            obj.PlotH.deriv.pt = plot(ax, nan, nan, 'o', 'MarkerSize', 8, ...
                'MarkerFaceColor', [0 0 0], 'MarkerEdgeColor', [0 0 0]);
            obj.PlotH.deriv.x0 = xline(ax, 0, ':', 'Color', [0 0 0]);
            obj.PlotH.deriv.y0 = yline(ax, 0, ':', 'Color', [0 0 0]);
            hold(ax,'off');
            axis(ax,'square');

            obj.refreshParamsTable();
        end

        % =================================================================
        % PARAMETER META / DEFAULTS
        % =================================================================
        function meta = buildParameterMeta(~)
            meta = struct('Key', {}, 'Label', {}, 'Description', {}, 'Default', {}, 'Limits', {}, 'Format', {});
            add = @(key,label,desc,def,lim,fmt) struct( ...
                'Key',key,'Label',label,'Description',desc,'Default',def,'Limits',lim,'Format',fmt);

            meta(end+1) = add('baselineFR', 'Baseline firing rate (a0)', ...
                ['Constant offset added to the *input* tuning curve before any transforms. ' ...
                'Keeps the curve strictly positive (required for log).'], ...
                0.20, [0 1], '%.3g');

            meta(end+1) = add('prefAmplitude', 'Preferred peak amplitude (a1)', ...
                'Amplitude of the Gaussian centered at the preferred direction.', ...
                0.50, [0 2], '%.3g');

            meta(end+1) = add('nullAmplitude', 'Opposite-direction amplitude (b1)', ...
                'Amplitude of the Gaussian centered at preferred direction + 180° (captures direction asymmetry).', ...
                0.80, [0 2], '%.3g');

            meta(end+1) = add('preferredDirectionDeg', 'Preferred direction (c1, deg)', ...
                'Center (in degrees) of the preferred-direction Gaussian.', ...
                90, [0 359], '%.0f');

            meta(end+1) = add('tuningSigmaDeg', 'Tuning width σ (d1, deg)', ...
                'Width (σ) of the Gaussians in degrees. Larger values broaden tuning.', ...
                30, [1 180], '%.0f');

            meta(end+1) = add('inputGainTR', 'Input gain (TR)', ...
                ['Multiplicative scaling applied to the *input* tuning curve before the linear transform ' ...
                '(used here to emulate gain changes at the input stage).'], ...
                1.0, [0 3], '%.3g');

            meta(end+1) = add('frToVoltageScale', 'FR→V scale (a40)', ...
                ['Scale parameter in the log transform mapping firing rate to an intracellular-like variable: ' ...
                'V = log(FR)/a40 + b40.'], ...
                1.0, [0.05 5], '%.3g');

            meta(end+1) = add('frToVoltageOffset', 'FR→V offset (b40)', ...
                'Offset parameter in the FR→V mapping: V = log(FR)/a40 + b40.', ...
                0.0, [-5 5], '%.3g');

            meta(end+1) = add('manipulationSynapticGain', 'Manipulation: synaptic gain (a3)', ...
                ['Linear scaling applied to the transformed input in the "manipulation" condition: ' ...
                'V_{manip} = a3*V(input*TR) + b3.'], ...
                0.50, [0 2], '%.3g');

            meta(end+1) = add('manipulationSynapticOffset', 'Manipulation: synaptic offset (b3)', ...
                'Additive offset applied to V_{manip} = a3*V(input*TR) + b3.', ...
                -1.35, [-5 5], '%.3g');

            meta(end+1) = add('controlIOFSlope', 'Control I/O-F slope (β)', ...
                'Slope in the exponential I/O-F: FR = exp(a*(V - b)). Control condition.', ...
                1.0, [0 10], '%.3g');

            meta(end+1) = add('controlIOFThreshold', 'Control I/O-F threshold (ϑ)', ...
                'Threshold/shift in the exponential I/O-F: FR = exp(a*(V - b)). Control condition.', ...
                0.0, [-5 5], '%.3g');

            meta(end+1) = add('manipulationIOFSlope', 'Manipulation I/O-F slope (β)', ...
                'Slope in the exponential I/O-F for the manipulation condition.', ...
                1.0, [0 10], '%.3g');

            meta(end+1) = add('manipulationIOFThreshold', 'Manipulation I/O-F threshold (ϑ)', ...
                ['Threshold/shift in the exponential I/O-F for the manipulation condition. ' ...
                'Changing this often behaves like changing spiking threshold.'], ...
                0.0, [-5 5], '%.3g');
        end

        function params = defaultsFromMeta(~, meta)
            params = struct();
            for k = 1:numel(meta)
                params.(meta(k).Key) = meta(k).Default;
            end
        end

        function sets = buildDefaultSets(obj, meta)
            % Build two independent "initial value" presets. Edit the values
            % in the marked blocks below to define your two start points.
            %
            % By default, both presets start from ParamMeta.Default.

            base = obj.defaultsFromMeta(meta);

            sets = struct();
            sets.NonGranular = base;
            sets.Granular    = base;

            % =============================================================
            % EDIT HERE: Non-granular preset overrides
            % =============================================================
            sets.NonGranular.manipulationIOFThreshold = -1.25;
            sets.NonGranular.manipulationIOFSlope = 5;
            % 
            % % =============================================================
            % % EDIT HERE: Granular preset overrides
            % % =============================================================
            sets.Granular.manipulationSynapticGain           = 1;
            sets.Granular.manipulationSynapticOffset        = 0;
            sets.Granular.manipulationIOFThreshold = 1;

        end

        function p = getDefaultsForState(obj, stateValue)
            % Map the UI switch value to one of the preset structs.
            if isstring(stateValue) || ischar(stateValue)
                v = lower(strtrim(char(stateValue)));
            else
                v = 'non-granular';
            end

            if contains(v, 'granular') && ~contains(v, 'non')
                p = obj.DefaultSets.Granular;
            else
                p = obj.DefaultSets.NonGranular;
            end
        end

        function pOut = sanitizeParamsAgainstMeta(obj, pIn)
            % Ensures all parameter keys exist and clamps to meta limits.
            pOut = struct();
            for k = 1:numel(obj.ParamMeta)
                m = obj.ParamMeta(k);
                key = m.Key;

                if isstruct(pIn) && isfield(pIn, key)
                    v = pIn.(key);
                else
                    v = m.Default;
                end

                if ~isfinite(v)
                    v = m.Default;
                end

                if ~isempty(m.Limits) && numel(m.Limits) == 2
                    v = min(max(v, m.Limits(1)), m.Limits(2));
                end

                pOut.(key) = v;
            end
        end

        function m = getMetaForKey(obj, key)
            idx = find(string({obj.ParamMeta.Key}) == string(key), 1, 'first');
            if isempty(idx), error('Unknown parameter key: %s', key); end
            m = obj.ParamMeta(idx);
        end

        % =================================================================
        % CALLBACKS
        % =================================================================
        function onParameterSelectionChanged(obj)
            if obj.IsUpdating, return; end
            obj.SelectedKey = string(obj.ParameterDropdown.Value);
            obj.syncControlsToSelectedParameter();
        end

        function onSliderChanging(obj, newValue)
            if obj.IsUpdating, return; end
            obj.setParamValue(obj.SelectedKey, newValue);
            obj.ValueEdit.Value = obj.Params.(obj.SelectedKey);
            obj.updatePlots();
        end

        function onSliderChanged(obj)
            if obj.IsUpdating, return; end
            obj.setParamValue(obj.SelectedKey, obj.Slider.Value);
            obj.ValueEdit.Value = obj.Params.(obj.SelectedKey);
            obj.updatePlots();
        end

        function onValueEditChanged(obj)
            if obj.IsUpdating, return; end
            obj.setParamValue(obj.SelectedKey, obj.ValueEdit.Value);
            obj.Slider.Value = obj.Params.(obj.SelectedKey);
            obj.updatePlots();
        end

        function onRangeChanged(obj)
            if obj.IsUpdating, return; end
            mn = obj.MinEdit.Value;
            mx = obj.MaxEdit.Value;
            if ~isfinite(mn) || ~isfinite(mx), return; end
            if mn == mx, mx = mn + 1; end
            if mn > mx
                t = mn; mn = mx; mx = t;
                obj.IsUpdating = true;
                obj.MinEdit.Value = mn;
                obj.MaxEdit.Value = mx;
                obj.IsUpdating = false;
            end

            obj.Slider.Limits = [mn mx];

            v = obj.Params.(obj.SelectedKey);
            v = min(max(v, mn), mx);
            obj.setParamValue(obj.SelectedKey, v);

            obj.IsUpdating = true;
            obj.Slider.Value = v;
            obj.ValueEdit.Value = v;
            obj.IsUpdating = false;

            obj.updatePlots();
        end

        function onStateChanged(obj)
            if obj.IsUpdating, return; end

            % Granular <-> Non-granular state (mirrors old Col_Mx_M switch behavior)
            obj.IsGranular = strcmpi(obj.StateSwitch.Value, 'Granular');

            % If you want the toggle to behave like a "preset selector",
            % immediately load the corresponding default parameter set.
            if obj.AutoLoadPresetOnToggle
                obj.applyPresetForCurrentState();
                return;
            end

            % Otherwise: only recolor and update table state row.
            obj.updateConditionColors();
            obj.refreshStateRowOnly();
        end

        function applyPresetForCurrentState(obj)
            % Load preset values based on the current StateSwitch position.
            % This is used at startup, on toggle (if enabled), and by reset.
            obj.Params = obj.sanitizeParamsAgainstMeta(obj.getDefaultsForState(obj.StateSwitch.Value));
            obj.IsGranular = strcmpi(obj.StateSwitch.Value, 'Granular');

            obj.syncControlsToSelectedParameter();
            obj.updatePlots();
        end

        function onWindowKeyPress(obj, e)
            % Keyboard shortcuts
            %   r : reset to the active preset
            %   Esc : close window
            if isempty(e) || ~isprop(e,'Key')
                return;
            end

            k = lower(string(e.Key));
            if k == "r"
                obj.resetToDefaults();
            elseif k == "escape"
                try
                    close(obj.Fig);
                catch
                end
            end
        end


        function resetToDefaults(obj)
            % Reset parameters to the active preset (as selected by the toggle).
            obj.Params = obj.sanitizeParamsAgainstMeta(obj.getDefaultsForState(obj.StateSwitch.Value));

            % Keep the current state switch as-is (but keep IsGranular consistent)
            obj.IsGranular = strcmpi(obj.StateSwitch.Value, 'Granular');

            obj.syncControlsToSelectedParameter();
            obj.updatePlots();
        end

        % =================================================================
        % CONTROL SYNC / HELP
        % =================================================================
        function syncControlsToSelectedParameter(obj)
            obj.IsUpdating = true;

            obj.ParameterDropdown.Value = char(obj.SelectedKey);
            m = obj.getMetaForKey(obj.SelectedKey);

            obj.MinEdit.Value = m.Limits(1);
            obj.MaxEdit.Value = m.Limits(2);
            obj.Slider.Limits = [m.Limits(1), m.Limits(2)];

            v = obj.Params.(obj.SelectedKey);
            v = min(max(v, obj.Slider.Limits(1)), obj.Slider.Limits(2));
            obj.Params.(obj.SelectedKey) = v;

            obj.Slider.Value    = v;
            obj.ValueEdit.Value = v;

            obj.IsUpdating = false;
        end

        function showSelectedParameterHelp(obj)
            m = obj.getMetaForKey(obj.SelectedKey);
            dNG = obj.DefaultSets.NonGranular.(m.Key);
            dG  = obj.DefaultSets.Granular.(m.Key);
            dActive = obj.getDefaultsForState(obj.StateSwitch.Value).(m.Key);
            msg = sprintf(['%s\n\n' ...
                'Key: %s\n' ...
                'Default (ParamMeta): %g\n' ...
                'Default (Non-granular preset): %g\n' ...
                'Default (Granular preset): %g\n' ...
                'Default (Active preset): %g\n' ...
                'Recommended slider range: [%g, %g]\n\n' ...
                '%s'], ...
                m.Label, m.Key, m.Default, dNG, dG, dActive, m.Limits(1), m.Limits(2), m.Description);
            uialert(obj.Fig, msg, 'Parameter help');
        end

        function showAboutDialog(obj)
            msg = [ ...
                "This app implements a compact, illustrative model used to visualize how PV+ related changes can affect orientation tuning (Fig. 6)." newline newline ...
                "Workflow (conceptually):" newline ...
                "  1) Build an input tuning curve (two Gaussians + baseline)." newline ...
                "  2) Map firing-rate → intracellular-like variable via a log transform." newline ...
                "  3) Apply a linear transform for the 'manipulation' condition." newline ...
                "  4) Map intracellular variable → firing-rate using an exponential I/O-F." newline newline ...
                "Tips:" newline ...
                "  • Use the Parameter dropdown + slider to explore." newline ...
                "  • Click '?' for short definitions and intuition." newline ...
                "  • 'Manipulation I/O-F threshold' often behaves like changing spiking threshold." newline ...
                "  • 'Tuning width σ' broadens/narrows the input curve." newline newline ...
                "Dependency: you need Matlab to run." ...
                ];

            % convert non-scalar string array -> single string scalar
            if isstring(msg) && ~isscalar(msg)
                msg = join(msg,"");
            end

            uialert(obj.Fig, char(msg), 'About / How to use');
        end


        % =================================================================
        % PARAM SETTERS / TABLE
        % =================================================================
        function setParamValue(obj, key, value)
            key = string(key);
            if ~isfield(obj.Params, key), error('Unknown parameter key: %s', key); end
            if ~isfinite(value), return; end
            obj.Params.(key) = value;
        end

        function refreshParamsTable(obj)
            % Robust: always create an (N x 2) cell array for uitable.Data
            n = numel(obj.ParamMeta);
            data = cell(n+1, 2);

            for k = 1:n
                m = obj.ParamMeta(k);
                data{k,1} = m.Label;  % char/string is fine
                try
                    data{k,2} = sprintf(m.Format, obj.Params.(m.Key));
                catch
                    % fallback if formatting fails
                    data{k,2} = num2str(obj.Params.(m.Key));
                end
            end

            data{n+1,1} = 'Model state';
            if ~isempty(obj.StateSwitch) && isvalid(obj.StateSwitch)
                data{n+1,2} = char(obj.StateSwitch.Value);
            else
                data{n+1,2} = '';
            end

            obj.ParamsTable.Data = data;
        end

        % =================================================================
        % MODEL + PLOTTING
        % =================================================================
        function updatePlots(obj)
            p = obj.Params;
            [cControl, cManip] = obj.getConditionColors();

            xDeg = 0:359;

            inputFR = p.baselineFR + ...
                p.prefAmplitude .* exp(-((xDeg - p.preferredDirectionDeg) ./ p.tuningSigmaDeg).^2) + ...
                p.nullAmplitude .* exp(-((xDeg - (p.preferredDirectionDeg + 180)) ./ p.tuningSigmaDeg).^2);

            inputFR_scaled = inputFR .* p.inputGainTR;

            inputFR        = max(inputFR,        eps);
            inputFR_scaled = max(inputFR_scaled, eps);

            frToV = @(fr) (log(fr) ./ p.frToVoltageScale) + p.frToVoltageOffset;

            xFR01 = linspace(eps, 1, 1000);
            vMap  = frToV(xFR01);

            vControl = frToV(inputFR);
            vManip   = p.manipulationSynapticGain .* frToV(inputFR_scaled) + p.manipulationSynapticOffset;

            vAxis = linspace(-3, 1, 1000);
            iofControl = exp(p.controlIOFSlope .* (vAxis - p.controlIOFThreshold));
            iofManip   = exp(p.manipulationIOFSlope .* (vAxis - p.manipulationIOFThreshold));

            outControl = exp(p.controlIOFSlope .* (vControl - p.controlIOFThreshold));
            outManip   = exp(p.manipulationIOFSlope .* (vManip   - p.manipulationIOFThreshold));

            diffCurve  = outManip - outControl;
            ratioCurve = outManip ./ max(outControl, eps);

            [~, idxPeak] = max(outControl);
            nPts = numel(diffCurve);
            wrap = @(k) mod(k-1, nPts) + 1;
            dx = 1;

            d2 = ( diffCurve(wrap(idxPeak+1)) - 2*diffCurve(idxPeak) + diffCurve(wrap(idxPeak-1)) ) / (dx^2);
            d4 = ( diffCurve(wrap(idxPeak-2)) - 4*diffCurve(wrap(idxPeak-1)) + 6*diffCurve(idxPeak) ...
                - 4*diffCurve(wrap(idxPeak+1)) + diffCurve(wrap(idxPeak+2)) ) / (dx^4);

            % Axis 1 & 2 should follow the state switch color scheme too
            set(obj.PlotH.in.scaled, 'XData', xDeg,  'YData', inputFR_scaled, 'Color', cManip);
            set(obj.PlotH.in.raw,    'XData', xDeg,  'YData', inputFR,        'Color', cControl);
            uistack(obj.PlotH.in.raw, 'top');

            set(obj.PlotH.revIOF, 'XData', xFR01, 'YData', vMap, 'Color', cControl);

            set(obj.PlotH.v.control, 'XData', xDeg, 'YData', vControl, 'Color', cControl);
            set(obj.PlotH.v.manip,   'XData', xDeg, 'YData', vManip,   'Color', cManip);

            set(obj.PlotH.iof.control, 'XData', vAxis, 'YData', iofControl, 'Color', cControl);
            set(obj.PlotH.iof.manip,   'XData', vAxis, 'YData', iofManip,   'Color', cManip);

            set(obj.PlotH.out.control, 'XData', xDeg, 'YData', outControl, 'Color', cControl);
            set(obj.PlotH.out.manip,   'XData', xDeg, 'YData', outManip,   'Color', cManip);
            set(obj.PlotH.out.diff,    'XData', xDeg, 'YData', diffCurve);
            set(obj.PlotH.out.ratio,   'XData', xDeg, 'YData', ratioCurve);
            set(obj.PlotH.out.peak,    'XData', xDeg(idxPeak), 'YData', outControl(idxPeak));

            set(obj.PlotH.deriv.pt, 'XData', d2, 'YData', d4);

            obj.Axes(1).Title.String  = sprintf('Input tuning (HBW=%g°)', obj.HBWF(inputFR));
            obj.Axes(1).XLabel.String = 'Drift direction (deg)';
            obj.Axes(1).YLabel.String = 'Normalized firing rate';
            obj.Axes(1).YLim = [-0.25, 1.5];

            obj.Axes(2).Title.String  = 'Reversed I/O-F (FR \rightarrow V)';
            obj.Axes(2).XLabel.String = 'Normalized firing rate';
            obj.Axes(2).YLabel.String = 'Intracellular-like variable (V)';
            obj.Axes(2).YLim = [min(vMap)-0.5, max(vMap)+0.5];

            obj.Axes(3).Title.String  = sprintf('Intracellular tuning (HBW control=%g°, manip=%g°)', obj.HBWF(vControl), obj.HBWF(vManip));
            obj.Axes(3).XLabel.String = 'Drift direction (deg)';
            obj.Axes(3).YLabel.String = 'V (a.u.)';
            obj.Axes(3).YLim = [min([vControl vManip])-0.5, max([vControl vManip])+0.5];

            obj.Axes(4).Title.String  = 'I/O-F (V \rightarrow FR)';
            obj.Axes(4).XLabel.String = 'V (a.u.)';
            obj.Axes(4).YLabel.String = 'Firing rate (a.u.)';
            obj.Axes(4).XLim = [-3 1];
            % obj.Axes(4).YLim = [0, max([iofControl iofManip])*1.05];
            obj.Axes(4).YLim = [0, max([iofControl])*1.05];


            obj.Axes(5).Title.String  = sprintf('Output tuning (HBW control=%g°, manip=%g°)', obj.HBWF(outControl), obj.HBWF(outManip));
            obj.Axes(5).XLabel.String = 'Drift direction (deg)';
            obj.Axes(5).YLabel.String = 'Firing rate (a.u.)';
            obj.Axes(5).YLim = [-0.75, max([outControl outManip])*1.1];

            obj.Axes(6).Title.String  = '2nd vs 4th derivative of (manip-control) at control peak';
            obj.Axes(6).XLabel.String = '2nd derivative';
            obj.Axes(6).YLabel.String = '4th derivative';

            maxAbs = max([abs(d2), abs(d4), 1e-12]);
            obj.Axes(6).XLim = [-1.2*maxAbs, 1.2*maxAbs];
            obj.Axes(6).YLim = [-1.2*maxAbs, 1.2*maxAbs];

            obj.refreshParamsTable();
            drawnow limitrate
        end

        function [cControl, cManip] = getConditionColors(obj)
            % Color mapping mirrors the old Col_Mx_M toggle in CurveApp_06:
            %   Granular      (Col_Mx_M == 1): Control=gray, Manip=black
            %   Non-granular  (Col_Mx_M ~= 1): Control=yellow, Manip=dark-yellow
            if obj.IsGranular
                cControl = [0.5 0.5 0.5];
                cManip   = [0 1 0];
            else
                y = [253 219 85]/255;
                yDark = max(y - 70/255, 0);
                cControl = y;
                % cManip   = yDark;
                cManip   = [0 1 0];

            end
        end


        function updateConditionColors(obj)
            [cControl, cManip] = obj.getConditionColors();

            if isempty(obj.PlotH) || ~isstruct(obj.PlotH)
                return;
            end

            if isfield(obj.PlotH,'v')
                if isfield(obj.PlotH.v,'control'), obj.safeSetLineColor(obj.PlotH.v.control, cControl); end
                if isfield(obj.PlotH.v,'manip'),   obj.safeSetLineColor(obj.PlotH.v.manip,   cManip);   end
            end

            % Axis 1: input tuning (raw vs scaled)
            if isfield(obj.PlotH,'in')
                if isfield(obj.PlotH.in,'raw'),    obj.safeSetLineColor(obj.PlotH.in.raw,    cManip);   end
                if isfield(obj.PlotH.in,'scaled'), obj.safeSetLineColor(obj.PlotH.in.scaled, cControl); end
            end

            % Axis 2: reversed I/O-F curve
            if isfield(obj.PlotH,'revIOF')
                obj.safeSetLineColor(obj.PlotH.revIOF, cControl);
            end

            if isfield(obj.PlotH,'iof')
                if isfield(obj.PlotH.iof,'control'), obj.safeSetLineColor(obj.PlotH.iof.control, cControl); end
                if isfield(obj.PlotH.iof,'manip'),   obj.safeSetLineColor(obj.PlotH.iof.manip,   cManip);   end
            end

            if isfield(obj.PlotH,'out')
                if isfield(obj.PlotH.out,'control'), obj.safeSetLineColor(obj.PlotH.out.control, cControl); end
                if isfield(obj.PlotH.out,'manip'),   obj.safeSetLineColor(obj.PlotH.out.manip,   cManip);   end
            end
        end

        function safeSetLineColor(obj, h, c)
            if isempty(h), return; end
            try
                if all(isgraphics(h))
                    set(h,'Color',c);
                end
            catch
            end
        end




        % =================================================================
        % table update without touching other rows
        % =================================================================
        function refreshStateRowOnly(obj)
            if isempty(obj.ParamsTable) || ~isvalid(obj.ParamsTable)
                return;
            end
            data = obj.ParamsTable.Data;
            if isempty(data) || size(data,2) < 2
                return;
            end

            % Find the "Model state" row
            rowIdx = [];
            for r = 1:size(data,1)
                if ischar(data{r,1}) || isstring(data{r,1})
                    if strcmpi(strtrim(char(data{r,1})), 'Model state')
                        rowIdx = r;
                        break;
                    end
                end
            end

            if ~isempty(rowIdx)
                data{rowIdx,2} = char(obj.StateSwitch.Value);
                obj.ParamsTable.Data = data;
            end
        end

        % =================================================================
        % HBW Calculation
        % =================================================================

        function HBW = HBWF(obj,Curve)

            midx = .5*size(Curve,2);

            maxtun =  find(Curve == max(Curve )) ;
            maxId  = maxtun(1);
            Curve  = circshift(Curve, ( midx - maxId));

            mintun =  find(Curve == min(Curve )) ;
            minId  = mintun(1);

            H0 =  Curve(minId) + (  ( Curve(midx) - Curve(minId) ) / (2^.5)  );

            HI01 = find(diff (Curve > H0) == 1);
            HI02 = find(diff (Curve > H0) == -1);
            HI12 = [HI01 HI02];   % if error try  HI12 = [HI01 HI02];

            try
                if minId<midx
                    Hpnt =  HI12( HI12>minId & HI12<midx);
                    Hpnt =  min(abs(Hpnt-midx));
                    HBW = Hpnt;

                elseif minId>midx
                    Hpnt =  HI12( HI12<minId & HI12>midx);
                    Hpnt =  min(abs(Hpnt-midx));
                    HBW = Hpnt;
                else
                    HBW =180;
                end

            catch
                HBW =180;
            end

        end








    end
end
