classdef Colors
%COLORS  Central color table for every visualizer figure / tab.
%
%   ONE place to change any color used across the app. Reference a color as
%   viz.Colors.<name> (each is a 1x3 RGB in [0 1]). To recolor an element
%   everywhere it appears, edit its value here -- nothing else to touch.
%
%   Names are SEMANTIC (what the color means), not literal ("green"), so a
%   later change of, say, the PVA color to teal is a one-line edit that flows
%   to every raster bar, tuning curve and scatter that uses viz.Colors.PVA.
%
%   Grouped by where they are used. As we port each paper figure, move its
%   hard-coded colors here and point the drawing code at these constants.
%
%   See also: viz.plots.Dashboard01Tab, viz.plots.UnitPanels

    properties (Constant)
        % --- condition / manipulation (PVA = PV+ activation, PVI = inactivation) ---
        PVA      = [0 1 0]        % PV+ activation  (E units): laser tuning + photostim bar
        PVI      = [0 0 1]        % PV+ inactivation (I units): laser tuning + photostim bar
        Control  = [0 0 0]        % control / no-laser condition

        % --- raster annotations (Figure 1 B/C) ---
        StimLine = [1 0 0]        % red vertical lines: stimulus onset & offset
        Baseline = [0 0 0]        % dashed line: baseline / spontaneous activity (paper: black)
        OriTick  = [0 1 1]        % cyan orientation-block ticks at the left of the raster

        % --- tuning delta / ratio panel (Figure 1, 4th row) ---
        Ratio    = [0 1 1]        % RT (ratio) curve  (cyan)
        Delta    = [1 0 0]        % dT (difference) curve (pure red; PDF-measured paper value #ff0000)

        % --- I/O panel (Figure 1, 5th row) ---
        IOModel  = [1 0 0]        % I/O (exponential) model-fit overlay (red)
        Unity    = [0 0 0]        % unity line (black)
    end

    methods (Static)
        function c = condition(isInhib)
            %CONDITION  The manipulation color for a unit: PVI (blue) if inhibitory,
            %   else PVA (green). `isInhib` is logical (e.g. UnitPanels.isInhibUnit).
            if nargin >= 1 && isInhib, c = viz.Colors.PVI; else, c = viz.Colors.PVA; end
        end
    end
end
