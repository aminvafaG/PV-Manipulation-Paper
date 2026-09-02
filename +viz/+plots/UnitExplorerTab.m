classdef UnitExplorerTab < viz.PlotTab
%UNITEXPLORERTAB  Per-unit explorer: rasters + tuning + PSTH + population fits.
%
%   Port of Raster_viewer_08 into our filter-aware tab framework. A unit slider
%   steps through the units that pass the active filters; for the selected unit
%   it shows:
%       * spike rasters (control / laser / overlay)
%       * per-condition tuning (raster-derived dots) + the fitted curve
%       * combined normalized tuning
%       * PSTHs (control / laser / overlay)
%       * an "all fits" population overlay (every filtered unit, faint) with the
%         current unit highlighted
%       * a metrics readout (OSI/CV/HBW/... from analysis.computeMetrics)
%
%   Control = no-laser (RasNL / fit_NL);  Laser = RasL / fit_L.
%   The waveform panel from the old viewer is omitted (no waveforms in Units.mat).

    properties
        ax            % struct of uiaxes handles
        unitSlider
        unitLabel
        normSwitch    % combined-tuning normalization (1=self, 2=to control)
        popShow       % 'Fit' | 'Tuning'  -> source for the population overlay
        dotSize  = 2

        % population-overlay cache (rebuilt only when the filter mask changes)
        popMask  = []
        popMode  = ''
        hiC           % highlight line handle, control population
        hiL           % highlight line handle, laser population
        popGrid  = 0:359
    end

    methods
        function obj = UnitExplorerTab()
            obj@viz.PlotTab('Unit Explorer');
        end

        % --------------------------------------------------------------- %
        function buildControls(obj, parent)
            g = uigridlayout(parent, [8 2]);
            g.RowHeight = {20, 40, 28, 20, 30, 20, 30, '1x'};
            g.ColumnWidth = {'1x','1x'};
            g.RowSpacing = 5; g.Padding = [8 8 8 8];

            l = uilabel(g,'Text','Unit (within filter)'); l.Layout.Row=1; l.Layout.Column=[1 2];
            obj.unitSlider = uislider(g,'Limits',[1 2],'Value',1, ...
                'ValueChangedFcn', @(s,e) obj.requestRefresh());
            obj.unitSlider.Layout.Row = 2; obj.unitSlider.Layout.Column = [1 2];

            bMinus = uibutton(g,'Text','-','ButtonPushedFcn',@(s,e) obj.step(-1));
            bMinus.Layout.Row = 3; bMinus.Layout.Column = 1;
            bPlus  = uibutton(g,'Text','+','ButtonPushedFcn',@(s,e) obj.step(1));
            bPlus.Layout.Row = 3; bPlus.Layout.Column = 2;

            l = uilabel(g,'Text','Combined-tuning norm'); l.Layout.Row=4; l.Layout.Column=[1 2];
            obj.normSwitch = uidropdown(g,'Items',{'self (1)','to control (2)'}, ...
                'ItemsData',[1 2], 'Value',1, ...
                'ValueChangedFcn',@(s,e) obj.requestRefresh());
            obj.normSwitch.Layout.Row = 5; obj.normSwitch.Layout.Column = [1 2];

            l = uilabel(g,'Text','Population source'); l.Layout.Row=6; l.Layout.Column=[1 2];
            obj.popShow = uidropdown(g,'Items',{'Fit','Tuning'},'Value','Fit', ...
                'ValueChangedFcn',@(s,e) obj.onPopModeChanged());
            obj.popShow.Layout.Row = 7; obj.popShow.Layout.Column = [1 2];

            obj.unitLabel = uilabel(g,'Text','unit: -','FontWeight','bold');
            obj.unitLabel.Layout.Row = 8; obj.unitLabel.Layout.Column = [1 2];
            obj.addDataSelectors(g);
        end

        function buildView(obj, parent)
            % Single-condition PSTHs are intentionally omitted; only the
            % combined (control-vs-laser overlay) PSTH is shown.
            g = uigridlayout(parent, [3 4]);
            g.RowHeight   = {'1x','1x','1x'};
            g.ColumnWidth = {'1x','1x','1x','1x'};
            g.Padding = [6 6 6 6]; g.RowSpacing = 6; g.ColumnSpacing = 6;

            obj.ax.rasterC = obj.addAxes(g,1,1);  obj.ax.tunC = obj.addAxes(g,1,2);
            obj.ax.rasterL = obj.addAxes(g,1,3);  obj.ax.tunL = obj.addAxes(g,1,4);
            obj.ax.rasterO = obj.addAxes(g,2,1);  obj.ax.tunO = obj.addAxes(g,2,2);
            obj.ax.psthO   = obj.addAxes(g,2,[3 4]);
            obj.ax.popC    = obj.addAxes(g,3,1);  obj.ax.popL = obj.addAxes(g,3,2);

            % metrics readout lives in the view (wider than the control strip)
            p = uipanel(g,'Title','Unit metrics'); p.Layout.Row = 3; p.Layout.Column = [3 4];
            pg = uigridlayout(p,[1 1]); pg.Padding = [4 4 4 4];
            obj.metricsView = uitextarea(pg,'Editable','off','FontName','Consolas','FontSize',11);
        end

        % --------------------------------------------------------------- %
        function update(obj, D, mask)
            idx = find(mask);
            obj.setSliderRange(numel(idx));
            obj.clearAll();
            if isempty(idx)
                title(obj.ax.rasterC, 'No units pass the filter'); return;
            end
            k    = min(max(round(obj.unitSlider.Value), 1), numel(idx));
            unit = idx(k);
            obj.unitLabel.Text = sprintf('unit: %d  (%d/%d)', unit, k, numel(idx));

            % per-unit raster-derived tuning + PSTH (current unit only)
            [bW, sW] = analysis.windows(D.Rast_time(unit,:));
            oriN = D.Ori_N(unit);
            tc = analysis.tuningFromRaster(D.RasNL{unit}, sW, bW, oriN, 20);
            tl = analysis.tuningFromRaster(D.RasL{unit},  sW, bW, oriN, 20);

            % ---- rasters + per-condition tuning ----
            obj.drawRaster(obj.ax.rasterC, D.RasNL{unit}, [0 0 0], tc, sprintf('Control (RasNL) #%d',unit));
            obj.drawTuning(obj.ax.tunC, tc, D.fit_NL(:,unit), [0 0 0], 'Control tuning');
            obj.drawRaster(obj.ax.rasterL, D.RasL{unit}, [0.75 0 0], tl, sprintf('Laser (RasL) #%d',unit));
            obj.drawTuning(obj.ax.tunL, tl, D.fit_L(:,unit), [0.75 0 0], 'Laser tuning');
            obj.drawOverlayRaster(obj.ax.rasterO, D.RasNL{unit}, D.RasL{unit}, unit);
            obj.drawCombinedTuning(obj.ax.tunO, tc, tl, D.fit_NL(:,unit), D.fit_L(:,unit));

            % ---- PSTH (combined control-vs-laser overlay only) ----
            obj.drawPSTHoverlay(obj.ax.psthO, tc.PSTH, tl.PSTH, sW, bW);

            % ---- population overlay (rebuild only if mask/mode changed) ----
            obj.refreshPopulation(D, idx);
            obj.setHighlight(D, unit);

            % ---- metrics readout ----
            obj.metricsView.Value = obj.metricLines(D, unit);
        end

        function s = getControlState(obj)
            s = struct('unit', obj.unitSlider.Value, ...
                       'norm', obj.normSwitch.Value, ...
                       'pop',  obj.popShow.Value);
        end

        function setControlState(obj, s)
            if isfield(s,'norm'), obj.setCtrl(obj.normSwitch, s.norm); end
            if isfield(s,'pop'),  obj.setCtrl(obj.popShow,  s.pop);  end
            if isfield(s,'unit'), obj.setCtrl(obj.unitSlider, s.unit); end
            obj.popMask = [];   % force the population overlay to rebuild
        end
    end

    properties (Access = private)
        metricsView
    end

    methods (Access = private)
        function step(obj, d)
            obj.unitSlider.Value = min(max(obj.unitSlider.Value + d, obj.unitSlider.Limits(1)), obj.unitSlider.Limits(2));
            obj.requestRefresh();
        end

        function onPopModeChanged(obj)
            obj.popMask = [];   % force population rebuild
            obj.requestRefresh();
        end

        function setSliderRange(obj, n)
            obj.unitSlider.Limits = [1, max(2, n)];
            if obj.unitSlider.Value > max(2, n), obj.unitSlider.Value = 1; end
        end

        function aa = addAxes(~, g, r, c)
            aa = uiaxes(g);
            aa.Layout.Row = r; aa.Layout.Column = c;
        end

        function clearAll(obj)
            % Clear the per-unit panels only. The population overlays (popC,
            % popL) are persistent -- they are rebuilt by refreshPopulation
            % only when the filter mask or population source changes.
            perUnit = {'rasterC','tunC','rasterL','tunL', ...
                       'rasterO','tunO','psthO'};
            for i = 1:numel(perUnit), cla(obj.ax.(perUnit{i})); end
        end

        function drawRaster(obj, ax, R, col, tun, ttl)
            if isempty(R), title(ax, ttl); return; end
            [r,c] = find(R);
            scatter(ax, c, r, obj.dotSize, col, 'filled');
            ax.YDir = 'reverse';
            xlim(ax, [1 size(R,2)]); ylim(ax, [1 max(1,size(R,1))]);
            xlabel(ax,'Time (ms)'); ylabel(ax,'Trial #'); title(ax, ttl);
            % feature block separators + orientation labels
            tr = tun.trialRepeat; feats = tun.features;
            if isfinite(tr) && tr >= 1 && ~isempty(feats)
                hold(ax,'on');
                yv = (tr:tr:size(R,1)) + 0.5;
                for kk = 1:min(numel(yv), numel(feats))
                    yline(ax, yv(kk), 'Color',[.4 .4 .4 .4], 'LineWidth', 0.25);
                    text(ax, size(R,2), yv(kk), sprintf(' %g', feats(kk)), ...
                        'VerticalAlignment','bottom','HorizontalAlignment','left','FontSize',8);
                end
                hold(ax,'off');
            end
        end

        function drawTuning(obj, ax, tun, fitCurve, col, ttl)
            T = tun.T;
            if isempty(T) || ~any(isfinite(T)), title(ax, ttl); return; end
            n = numel(T);
            scatter(ax, T, 1:n, 10*obj.dotSize, col, 'filled'); hold(ax,'on');
            xline(ax, tun.baseHz, '--', 'Color', col);
            obj.overlayFitLine(ax, fitCurve, tun.features, col, false, []);
            set(ax,'YDir','reverse'); ylim(ax,[0 n+1.5]);
            xm = max([T(:); tun.baseHz; 0]); if ~isfinite(xm)||xm<=0, xm=1; end
            xlim(ax,[0 xm*1.1]);
            xlabel(ax,'Firing rate (Hz)'); ylabel(ax,'Ori #'); title(ax, ttl);
            hold(ax,'off');
        end

        function drawCombinedTuning(obj, ax, tc, tl, fitC, fitL)
            T1 = tc.T; T2 = tl.T;
            if isempty(T1) || ~any(isfinite(T1)), title(ax,'Combined tuning'); return; end
            mx1 = max(T1);
            if ~isfinite(mx1) || mx1 <= 0, title(ax,'Combined tuning'); return; end
            T1n = T1/mx1; scatter(ax, T1n, 1:numel(T1n), 22, 'k', 'filled'); hold(ax,'on');
            xline(ax, tc.baseHz/mx1, '--k');
            obj.overlayFitLine(ax, fitC, tc.features, 'k', true, mx1);
            if ~isempty(T2) && any(isfinite(T2)) && max(T2) > 0
                if obj.normSwitch.Value == 1, denom2 = max(T2); else, denom2 = mx1; end
                scatter(ax, T2/denom2, 1:numel(T2), 22, 'r', 'filled');
                xline(ax, tl.baseHz/denom2, '--r');
                obj.overlayFitLine(ax, fitL, tl.features, 'r', true, denom2);
            end
            set(ax,'YDir','reverse'); ylim(ax,[0 numel(T1)+1.5]); xlim(ax,[0 1.2]);
            xlabel(ax,'Norm. firing rate'); ylabel(ax,'Ori #'); title(ax,'Combined tuning');
            hold(ax,'off');
        end

        function overlayFitLine(~, ax, fitCurve, feats, col, doNorm, denom)
            % Map the 0:359 fitted curve onto the tuning axes' Ori# rows.
            y = fitCurve(:); if isempty(y) || ~any(isfinite(y)), return; end
            grid = (0:numel(y)-1)';
            if doNorm
                if isempty(denom) || denom <= 0, return; end
                y = y / denom;
            end
            n = numel(feats);
            rowIdx = interp1(feats(:), (1:n)', grid, 'linear', 'extrap');
            % NB: assume the caller holds the axes; do NOT turn hold off here,
            % or a scatter plotted after this (e.g. the laser curve in the
            % combined-tuning panel) would clear everything drawn before it.
            hold(ax,'on'); plot(ax, y, rowIdx, 'Color', col, 'LineWidth', 1.4);
        end

        function drawOverlayRaster(obj, ax, R1, R2, unit)
            if isempty(R1) && isempty(R2), title(ax,'Overlay'); return; end
            if ~isempty(R1), [r1,c1]=find(R1); scatter(ax,c1,r1,obj.dotSize,'k','filled'); end
            hold(ax,'on');
            if ~isempty(R2), [r2,c2]=find(R2); scatter(ax,c2,r2,obj.dotSize,'r','filled'); end
            ax.YDir='reverse';
            xlim(ax,[1 max(size(R1,2),size(R2,2))]); ylim(ax,[1 max([1 size(R1,1) size(R2,1)])]);
            xlabel(ax,'Time (ms)'); ylabel(ax,'Trial #'); title(ax,sprintf('Overlay #%d',unit));
            hold(ax,'off');
        end

        function drawPSTHoverlay(obj, ax, p1, p2, sW, bW)
            if isempty(p1) && isempty(p2), title(ax,'PSTH overlay'); return; end
            if ~isempty(p1), plot(ax,1:numel(p1),p1,'Color','k','LineWidth',1.2); end
            hold(ax,'on');
            if ~isempty(p2), plot(ax,1:numel(p2),p2,'Color','r','LineWidth',1.2); end
            n = max(numel(p1),numel(p2));
            xline(ax,bW(1),':','Color',[.4 .4 .4]); xline(ax,bW(2),':','Color',[.4 .4 .4]);
            xline(ax,sW(1),'--','Color',[.2 .2 .2]); xline(ax,sW(2),'--','Color',[.2 .2 .2]);
            if n>0, xlim(ax,[1 n]); end
            xlabel(ax,'Time (ms)'); ylabel(ax,'Rate'); ax.XGrid='on'; ax.YGrid='on';
            title(ax,'PSTH overlay (control vs laser)'); hold(ax,'off');
        end

        function refreshPopulation(obj, D, idx)
            mode = obj.popShow.Value;
            if isequal(obj.popMask, idx) && strcmp(obj.popMode, mode) ...
                    && ~isempty(obj.hiC) && isvalid(obj.hiC)
                return;   % nothing changed -> keep persistent faint curves
            end
            obj.popMask = idx; obj.popMode = mode;

            Mc = obj.popMatrix(D, idx, 'NL', mode);
            Ml = obj.popMatrix(D, idx, 'L',  mode);
            obj.hiC = obj.buildPop(obj.ax.popC, Mc, 'All control fits');
            obj.hiL = obj.buildPop(obj.ax.popL, Ml, 'All laser fits');
        end

        function M = popMatrix(obj, D, idx, which, mode)
            g = obj.popGrid;
            if strcmp(mode,'Fit')
                if strcmp(which,'NL'), M = D.fit_NL(:, idx); else, M = D.fit_L(:, idx); end
            else  % 'Tuning' -> per-unit raster tuning interpolated onto 0:359
                M = nan(numel(g), numel(idx));
                for j = 1:numel(idx)
                    u = idx(j);
                    [bW, sW] = analysis.windows(D.Rast_time(u,:));
                    if strcmp(which,'NL'), R = D.RasNL{u}; else, R = D.RasL{u}; end
                    t = analysis.tuningFromRaster(R, sW, bW, D.Ori_N(u));
                    if numel(t.T) >= 2
                        fe = [t.features, 360]; tt = [t.T, t.T(1)];
                        M(:,j) = interp1(fe, tt, mod(g,360), 'linear');
                    end
                end
            end
        end

        function hi = buildPop(obj, ax, M, ttl)
            cla(ax); g = obj.popGrid;
            if ~isempty(M)
                mx = max(M, [], 1);
                Mn = M ./ mx;                 % normalize each curve by its peak
                Mn(:, ~(mx > 0)) = NaN;
                k = size(Mn,2);
                xx = nan((numel(g)+1)*k, 1); yy = xx;
                for j = 1:k
                    rows = (j-1)*(numel(g)+1) + (1:numel(g));
                    xx(rows) = g; yy(rows) = Mn(:,j);
                end
                plot(ax, xx, yy, 'Color', [0.7 0.7 0.7], 'LineWidth', 0.5);
            end
            hold(ax,'on');
            hi = plot(ax, g, nan(size(g)), 'LineWidth', 2, 'Color', [0 0 0]);
            xlim(ax,[g(1) g(end)]); ylim(ax,[0 1.1]);
            xlabel(ax,'Orientation (deg)'); ylabel(ax,'Norm. rate');
            ax.XGrid='on'; ax.YGrid='on'; title(ax, ttl); hold(ax,'off');
        end

        function setHighlight(obj, D, unit)
            obj.setHi(obj.hiC, D, unit, 'NL', [0 0 0]);
            obj.setHi(obj.hiL, D, unit, 'L',  [0.75 0 0]);
        end

        function setHi(obj, hi, D, unit, which, col)
            if isempty(hi) || ~isvalid(hi), return; end
            M = obj.popMatrix(D, unit, which, obj.popShow.Value);
            y = M(:); mx = max(y);
            if isfinite(mx) && mx > 0, y = y / mx; else, y = nan(size(y)); end
            set(hi, 'XData', obj.popGrid, 'YData', y, 'Color', col);
        end

        function lines = metricLines(~, D, u)
            g = @(f) ternaryField(D, f, u);
            simp = g('Simp_Comp');
            if isfinite(simp), sc = ternaryStr(simp>0,'simple','complex'); else, sc = '-'; end
            lines = {
                sprintf('unit %d   ch %s   EI %s', u, num(g('ch')), str(D,'EI',u))
                sprintf('Ori_N %s   U_unity %s', num(g('Ori_N')), num(g('U_unity')))
                '                control    laser'
                sprintf('FrMean     %8s %8s', num(g('FrMean_NL')), num(g('FrMean_L')))
                sprintf('FrBase     %8s %8s', num(g('FrBase_NL')), num(g('FrBase_L')))
                sprintf('FrMax      %8s %8s', num(g('FrMax_NL')), num(g('FrMax_L')))
                sprintf('FrMin      %8s %8s', num(g('FrMin_NL')), num(g('FrMin_L')))
                sprintf('fitOSI     %8s %8s', num(g('fitOSI_NL')), num(g('fitOSI_L')))
                sprintf('fitCV      %8s %8s', num(g('fitCV_NL')), num(g('fitCV_L')))
                sprintf('fitHBW     %8s %8s', num(g('fitHBW_NL')), num(g('fitHBW_L')))
                sprintf('fitFWHM    %8s %8s', num(g('fitFWHM_NL')), num(g('fitFWHM_L')))
                sprintf('fitPeak1 ori/val   C %s/%s  L %s/%s', num(g('fitPrefOri1_NL')),num(g('fitMax1_NL')), num(g('fitPrefOri1_L')),num(g('fitMax1_L')))
                sprintf('fitPeak2 ori/val   C %s/%s  L %s/%s', num(g('fitPrefOri2_NL')),num(g('fitMax2_NL')), num(g('fitPrefOri2_L')),num(g('fitMax2_L')))
                sprintf('fitTrough1 ori/val C %s/%s  L %s/%s', num(g('fitMinOri1_NL')),num(g('fitMin1_NL')), num(g('fitMinOri1_L')),num(g('fitMin1_L')))
                sprintf('fitTrough2 ori/val C %s/%s  L %s/%s', num(g('fitMinOri2_NL')),num(g('fitMin2_NL')), num(g('fitMinOri2_L')),num(g('fitMin2_L')))
                sprintf('F1F0       %8s %8s', num(g('F1F0_NL')), num(g('F1F0_L')))
                sprintf('Rsq (gof)  %8s %8s', num(g('Rsq_NL')), num(g('Rsq_L')))
                ' '
                sprintf('Delta_Fr  %7s   Delta_Fr_I %7s', num(g('Delta_Fr')), num(g('Delta_Fr_I')))
                sprintf('Delta_OSI %7s   Delta_CV   %7s', num(g('Delta_OSI')), num(g('Delta_CV')))
                sprintf('Delta_HBW %7s   Delta_FWHM %7s', num(g('Delta_HBW')), num(g('Delta_FWHM')))
                sprintf('Simp/Comp: %s     G_type: %s', sc, num(g('G_type')))
                ' '
                sprintf('LTM slope %7s   intercept %7s   bp %7s', num(g('LTM_slope')), num(g('LTM_intercept')), num(g('LTM_breakpoint')))
                sprintf('LTM R2 %10s   R2adj %10s   RMSE %7s', num(g('LTM_R2')), num(g('LTM_R2adj')), num(g('LTM_RMSE')))
                ' '
                sprintf('Exp exponent %4s   offset %7s   dFR %7s', num(g('ExpM_exponent')), num(g('ExpM_offset')), num(g('ExpM_dFR')))
                sprintf('Exp R2 %10s   R2adj %10s   RMSE %7s', num(g('ExpM_R2')), num(g('ExpM_R2adj')), num(g('ExpM_RMSE')))
                sprintf('LTM dHBW %6s   dOSI %6s   dCV %6s', num(g('LTM_Delta_HBW')), num(g('LTM_Delta_OSI')), num(g('LTM_Delta_CV')))
                sprintf('Exp dHBW %6s   dOSI %6s   dCV %6s', num(g('ExpM_Delta_HBW')), num(g('ExpM_Delta_OSI')), num(g('ExpM_Delta_CV')))
                };
        end
    end
end

% ----------------------------------------------------------------------- %
function v = ternaryField(D, f, u)
    if isfield(D, f) && numel(D.(f)) >= u, v = D.(f)(u); else, v = NaN; end
end
function s = num(v)
    if isnumeric(v) && isscalar(v) && isfinite(v), s = sprintf('%.3g', v); else, s = '-'; end
end
function s = ternaryStr(cond, a, b)
    if cond, s = a; else, s = b; end
end
function s = str(D, f, u)
    s = '-';
    if isfield(D,f) && numel(D.(f)) >= u
        try, s = char(string(D.(f)(u))); catch, s = '-'; end
    end
end
