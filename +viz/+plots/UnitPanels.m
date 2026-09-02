classdef UnitPanels
%UNITPANELS  Per-unit panel drawers shared by the click-to-inspect popup.
%
%   A faithful port of Visualizer_01's per-unit example panels (the same code
%   that Dashboard01Tab draws into its I{i,*} axes): raster laser / raster
%   control, the center-shifted tuning curves (laser + control), the circular
%   (polar) tuning, and the delta/ratio dual-axis panel. Collected here as
%   static, side-effect-free drawers (they only draw into the axes you pass) so
%   viz.plots.UnitInspector can show ANY clicked unit EXACTLY as the dashboard's
%   example panels do.
%
%   drawAll(...) is the single entry point used by the inspector; the individual
%   drawers and helpers mirror Dashboard01Tab's private methods one-to-one.
%
%   See also: viz.plots.UnitInspector, viz.plots.Dashboard01Tab, analysis.windows

    properties (Constant)
        SZ = 16.5;                 % marker size (V01 fonts*1.5), matches the dashboard
    end

    methods (Static)
        % ------------------------------------------------------------- %
        function drawAll(axRasL, axRasNL, axTun, axPolar, axDR, D, u, Cc, showLabel)
            %DRAWALL  Draw the full per-unit set for unit `u` (a D row index).
            %   axRasL/axRasNL = laser / no-laser rasters; axTun = center-shifted
            %   tuning; axPolar = polar tuning; axDR = delta/ratio. Cc is the
            %   per-condition color (green for E, blue for I). showLabel=false
            %   suppresses the paper-mode tuning legend / RT-dT labels, so a multi-unit
            %   layout draws them once (on its leftmost column).
            if nargin < 8 || isempty(Cc), Cc = [0 0 1]; end
            if nargin < 9 || isempty(showLabel), showLabel = true; end
            if isempty(D) || isempty(u) || ~isfinite(u), return; end
            oriN = 24;
            if isfield(D,'Ori_N'), v = double(D.Ori_N(u)); if isfinite(v) && v >= 2, oriN = round(v); end, end
            timing = [-0.5 1 2];                          % fallback = old default raster timing
            if isfield(D,'Rast_time'), tt = D.Rast_time(u,:); if numel(tt) >= 3 && all(isfinite(tt)), timing = tt; end, end
            if ~isempty(axRasL)  && isgraphics(axRasL),  viz.plots.UnitPanels.raster(axRasL,  viz.plots.UnitPanels.rasOf(D,'RasL',u),  oriN, true,  timing, [], Cc); end
            if ~isempty(axRasNL) && isgraphics(axRasNL), viz.plots.UnitPanels.raster(axRasNL, viz.plots.UnitPanels.rasOf(D,'RasNL',u), oriN, false, timing, [], Cc); end
            if ~isempty(axTun)   && isgraphics(axTun),   viz.plots.UnitPanels.tuning(axTun, D, u, Cc, showLabel); end
            if ~isempty(axPolar) && isgraphics(axPolar), viz.plots.UnitPanels.polar(axPolar, D, u, Cc); end
            if ~isempty(axDR)    && isgraphics(axDR),    viz.plots.UnitPanels.deltaRatio(axDR, D, u, showLabel); end
        end

        % ------------------------------------------------------------- %
        % I{i,1}/I{i,2} rasters: spikes + stim-onset line, laser bars, cyan ori
        % ticks, seconds x-axis, direction-arrow y-ticks (V01 Plot_Tuning8_01:124-211).
        function raster(ax, R, oriN, isLaser, timing, sz, Cc)
            % sz = spike-dot SizeData (optional; default 0.4, the V01/dashboard
            % value). Callers that want bigger dots (e.g. the tuning fitter) pass
            % a larger value; omitting it preserves the original appearance.
            % Cc = laser photostim-bar color (green E / blue I); defaults to blue.
            if isempty(R), return; end
            if nargin < 5 || isempty(timing) || numel(timing) < 2 || ~all(isfinite(timing(1:2)))
                tsS = 0.5; tsE = 1.5;                          % fallback: old default timing
            else
                tsS = -timing(1);                             % stim onset (s) = pre-stim baseline
                tsE = -timing(1) + timing(2);                 % stim offset (s)
            end
            if nargin < 6 || isempty(sz), sz = 0.4; end
            if nargin < 7 || isempty(Cc), Cc = viz.Colors.PVI; end
            R = double(R); nT = size(R,1); W = size(R,2);
            [s, t] = find(R == 1);
            scatter(ax, t, s, sz, 'k', 'filled'); hold(ax,'on');
            if viz.paperStyle()
                % PAPER (Fig 1 B/C): SOLID red lines at stimulus onset AND offset in both
                % rows; the laser row carries a green (PVA) / blue (PVI) photostim bar
                % across the top spanning onset->offset.
                xline(ax, 1+1000*tsS, 'Color', viz.Colors.StimLine, 'LineWidth', 0.5);    % stim onset (paper: pure-red 0.5pt)
                xline(ax, 1+1000*tsE, 'Color', viz.Colors.StimLine, 'LineWidth', 0.5);    % stim offset
                if isLaser
                    plot(ax, 1000*[tsS tsE], [2+nT 2+nT], 'Color', Cc, 'LineWidth', 1);   % photostim bar (paper: 1.0pt)
                    topY = nT + 3;
                else
                    topY = nT + 1;
                end
            else
                % ORIGINAL (pre-paper port): dashed red onset line + tan visual-stim bar
                % (both rows) + a dark-red laser bar at the top.
                xline(ax, 1+1000*tsS, '--r', 'LineWidth', 0.5);                           % stim onset
                plot(ax, 1000*[tsS tsE], [1+nT 1+nT], 'Color',[215 185 121]/255, 'LineWidth',0.5);
                if isLaser
                    plot(ax, 1000*[tsS tsE], [3+nT 3+nT], 'Color',[139 36 51]/255, 'LineWidth',0.5);
                    topY = nT + 3;
                else
                    topY = nT + 1;
                end
            end
            OrRip = nT / max(oriN,1);
            for i = 1:oriN, scatter(ax, 1, i*OrRip, 1, '_', 'MarkerEdgeColor', viz.Colors.OriTick); end   % orientation-block ticks
            xlim(ax, [0 W-500]); ylim(ax, [0 topY]);
            xt = 0:500:max(W-500,0); ax.XTick = xt; ax.XTickLabel = xt/1000 - tsS;          % seconds
            arrowPos = [1 : nT/4 : nT, nT];
            ax.YTick = arrowPos; ax.YTickLabel = {'\rightarrow','\uparrow','\leftarrow','\downarrow','\rightarrow'};
            ytickangle(ax, 0); xtickangle(ax, 0); hold(ax,'off');
        end

        % I{i,3}: per-orientation measured means +/- SE (S markers), laser fit
        % peak-centered (Circ_center2), control fit raw, red spontaneous-mean line.
        function tuning(ax, D, u, Cc, showLegend)
            if nargin < 5 || isempty(showLegend), showLegend = true; end   % legend once (leftmost column)
            hold(ax,'on'); fnl = D.fit_NL(:,u); fl = D.fit_L(:,u); N = numel(fnl);
            s = viz.plots.UnitPanels.unitRates(D, u); oriN = s.oriN; if ~isfinite(oriN), oriN = 24; end
            Xv = (1:oriN)'; Xfit = 1 + (0:N-1)'*(oriN/N);
            [~, idL] = viz.plots.UnitPanels.circCenter(fnl, fl); flc = circshift(fl, round(.5*N - idL));   % center laser fit
            lw = 0.5; if viz.paperStyle(), lw = 0.75; end                                 % paper: tuning fit curves 0.75pt
            if ~isempty(s.RasL_m)
                e1 = errorbar(ax, Xv, s.RasL_m(:), s.RasL_se(:), 'S', 'MarkerSize',1, 'Color',Cc,       'LineWidth',0.5); cap = e1.CapSize; e1.CapSize = cap/2;
                plot(ax, Xfit, flc, 'Color', Cc, 'LineWidth',lw);
                e2 = errorbar(ax, Xv, s.RasNL_m(:), s.RasNL_se(:), 'S', 'MarkerSize',1, 'Color',[0 0 0], 'LineWidth',0.5); e2.CapSize = cap/2;
                plot(ax, Xfit, fnl, 'Color', [0 0 0], 'LineWidth',lw);
                if isfinite(s.baseMean)
                    if viz.paperStyle(), yline(ax, s.baseMean, '--', 'Color', [.294 .294 .294], 'Alpha',1, 'LineWidth',0.7);  % paper: dark-gray #4B4B4B dashed 0.7pt
                    else,                yline(ax, s.baseMean, '--', 'Color',[1 0 0], 'Alpha',0.5, 'LineWidth',0.2); end        % original: red
                end
            else
                plot(ax, Xfit, flc, 'Color', Cc, 'LineWidth',lw); plot(ax, Xfit, fnl, 'Color', [0 0 0], 'LineWidth',lw);
            end
            xlim(ax, [1 oriN]); ylim(ax, 'auto');                                          % auto-scale y
            arrowPos = [1 : oriN/4 : oriN, oriN];
            xticks(ax, arrowPos); xticklabels(ax, {'\rightarrow','\uparrow','\leftarrow','\downarrow','\rightarrow'}); xtickangle(ax,0);
            if viz.paperStyle() && showLegend                              % paper: control / PVA / PVI legend across the top (once, leftmost column)
                fs = ax.FontSize;
                text(ax, 0.00, 1.06, 'control', 'Units','normalized', 'Color',[0 0 0],       'FontSize',fs, 'VerticalAlignment','bottom', 'Clipping','off');
                text(ax, 0.44, 1.06, 'PVA',     'Units','normalized', 'Color',viz.Colors.PVA, 'FontSize',fs, 'VerticalAlignment','bottom', 'Clipping','off');
                text(ax, 0.72, 1.06, 'PVI',     'Units','normalized', 'Color',viz.Colors.PVI, 'FontSize',fs, 'VerticalAlignment','bottom', 'Clipping','off');
            end
            hold(ax,'off');
        end

        % I{i,4}: measured per-direction polar (NOr points) with 50-segment SE
        % shading, red spontaneous-mean ring, square vertices.
        function polar(ax, D, u, Cc)
            try
                s = viz.plots.UnitPanels.unitRates(D, u); if isempty(s.RasL_m), return; end
                oriN = s.oriN; theta = linspace(0, 2*pi, oriN+1);
                OL = s.RasL_m(:); ONL = s.RasNL_m(:);
                hold(ax,'on');
                if isfinite(s.baseMean), polarplot(ax, theta, s.baseMean*ones(1,numel(theta)), 'Color',[1 0 0 0.5]); end
                polarplot(ax, theta, [OL; OL(1)], 'Marker','square', 'MarkerSize',1, 'Color',[Cc 0.5]);
                viz.plots.UnitPanels.polarBand(ax, OL - s.RasL_se(:), OL + s.RasL_se(:), Cc);
                polarplot(ax, theta, [ONL; ONL(1)], 'Marker','square', 'MarkerSize',1, 'Color',[0 0 0 0.5]);
                viz.plots.UnitPanels.polarBand(ax, ONL - s.RasNL_se(:), ONL + s.RasNL_se(:), [0 0 0]);
                ax.ThetaTick = [0 90 180 270]; ax.ThetaTickLabel = {'0','90','180','270'}; hold(ax,'off');
            catch
            end
        end

        % I{i,7}: right=delta (centered laser fit - raw control fit), left=ratio;
        % E/I sign flip; both axes XTick/XTickLabel cleared.
        function deltaRatio(ax, D, u, showLabel)
            if nargin < 4 || isempty(showLabel), showLabel = true; end     % RT/dT labels once (leftmost column)
            fnl = D.fit_NL(:,u); fl = D.fit_L(:,u); N = numel(fnl);
            [~, idL] = viz.plots.UnitPanels.circCenter(fnl, fl); flc = circshift(fl, round(.5*N - idL));
            x = (1:N)';
            if viz.plots.UnitPanels.isInhibUnit(D, u), delta = -(flc - fnl); ratio = fnl ./ flc;
            else,                                       delta =  (flc - fnl); ratio = flc ./ fnl; end
            try
                dCol = [1 .1 .1]; rCol = [0 1 1]; lw = 0.5;
                if viz.paperStyle(), dCol = [1 0 0]; lw = 0.75; end                             % paper: pure-red dT, cyan RT, 0.75pt
                yyaxis(ax,'right'); ax.YColor = dCol; line(ax, x, delta, 'Color',dCol, 'LineWidth',lw);
                ylim(ax,'auto'); xlim(ax,[x(1) x(end)]); ax.XTick = []; ax.XTickLabel = [];   % delta auto-scales
                yyaxis(ax,'left'); ax.YColor = rCol; line(ax, x, ratio, 'Color',rCol, 'LineWidth',lw);
                ylim(ax,[0 1]); xlim(ax,[x(1) x(end)]); ax.XTick = []; ax.XTickLabel = [];     % ratio fixed [0 1]
                if viz.paperStyle() && showLabel                             % paper: axis labels RT (cyan) / dT (red), once
                    ylabel(ax, 'RT', 'Color', viz.Colors.Ratio);
                    yyaxis(ax,'right'); ylabel(ax, '\DeltaT', 'Color', viz.Colors.Delta); yyaxis(ax,'left');
                end
                if viz.paperStyle()                                          % paper Fig 1: drift-direction arrows on x (match the tuning above)
                    apos = [1, round(N/4), round(N/2), round(3*N/4), N];
                    xticks(ax, apos); xticklabels(ax, {'\rightarrow','\uparrow','\leftarrow','\downarrow','\rightarrow'}); xtickangle(ax,0);
                end
            catch
                cla(ax); plot(ax, x, delta, 'Color',[1 .1 .1]); hold(ax,'on'); plot(ax, x, ratio, 'Color',[0 1 1]); xlim(ax,[x(1) x(end)]); ax.XTick = []; hold(ax,'off');
            end
        end

        % ------------------------------------------------------------- %
        %  per-unit helpers (verbatim from Dashboard01Tab)
        % ------------------------------------------------------------- %
        function s = unitRates(D, u)
            % measured per-orientation tuning + baseline. Base/stim windows come
            % from the unit's Rast_time via analysis.windows (matches computeMetrics).
            s = struct('oriN',NaN,'RasL_m',[],'RasNL_m',[],'RasL_se',[],'RasNL_se',[],'baseMean',NaN);
            RL = viz.plots.UnitPanels.rasOf(D,'RasL',u); RNL = viz.plots.UnitPanels.rasOf(D,'RasNL',u);
            if isempty(RL) || isempty(RNL), return; end
            RL = double(RL); RNL = double(RNL);
            oriN = 24; if isfield(D,'Ori_N'), v=double(D.Ori_N(u)); if isfinite(v)&&v>=2, oriN=round(v); end, end
            s.oriN = oriN; W = min(size(RL,2), size(RNL,2));
            timing = [-0.5 1 2];                              % fallback = old default raster timing
            if isfield(D,'Rast_time'), tt = D.Rast_time(u,:); if numel(tt)>=3 && all(isfinite(tt)), timing = tt; end, end
            [bW, sW] = analysis.windows(timing, 0);          % timing-aware base/stim sample windows
            sIdx = max(1,sW(1)):min(sW(2),W); bIdx = max(1,bW(1)):min(bW(2),W);
            [s.RasL_m,  s.RasL_se]  = viz.plots.UnitPanels.oriMeanSE(RL,  oriN, sIdx);
            [s.RasNL_m, s.RasNL_se] = viz.plots.UnitPanels.oriMeanSE(RNL, oriN, sIdx);
            s.baseMean = mean([1000*mean(mean(RL(:,bIdx))), 1000*mean(mean(RNL(:,bIdx)))]);
        end

        function [m, se] = oriMeanSE(R, oriN, sIdx)
            m = nan(1,oriN); se = nan(1,oriN); ntr = floor(size(R,1)/oriN);
            if ntr < 1, return; end
            for i = 1:oriN
                blk = R((1+(i-1)*ntr):(i*ntr), sIdx);
                m(i) = 1000*mean(blk(:)); se(i) = std(1000*mean(blk,2));
            end
            se = se / sqrt(oriN);                        % V01 quirk: RasL_se = std_RL / sqrt(NOr)
        end

        function [idC, idL] = circCenter(TC, TL)
            % port of Circ_center2: idC = control peak; idL = laser peak within the
            % central [3/8,5/8] window after shifting laser by the control peak.
            TC = TC(:); TL = TL(:); N = numel(TC);
            mc = find(TC == max(TC)); idC = mc(1);
            tmp = circshift(TL, round(.5*N - idC));
            w = round((3/8)*N):round((5/8)*N);
            ml = find(tmp == max(tmp(w))); idL = ml(1);
        end

        function polarBand(ax, lo, hi, col)
            % 50 interpolated rings between lo and hi at alpha 0.01 (closed)
            lo = lo(:); hi = hi(:); ns = 50; th = linspace(0, 2*pi, numel(lo)+1);
            for k = 1:ns
                ri = lo + (hi - lo)*(k/ns); polarplot(ax, th, [ri; ri(1)], 'LineWidth',1, 'Color',[col 0.01]);
            end
        end

        function tf = isInhibUnit(D, u)
            tf = isfield(D,'EI') && strcmpi(strtrim(string(D.EI(u))),"I");
        end

        % I{i,5}: control-vs-laser I/O scatter (subsample THEN sort), live piecewise
        % (E) / linear (I) fit on the 36-pt subsample, exp-model overlay swapped per
        % E/I (V01 Plot_Tuning8_01:551-666). A verbatim static copy of
        % Dashboard01Tab.drawIOInto so the 6th per-unit panel is drawable anywhere.
        function io(ax, D, u)
            if isempty(ax) || ~isgraphics(ax) || isempty(u) || ~isfinite(u), return; end
            if ~isfield(D,'fit_mid_nc_NL') || ~isfield(D,'fit_mid_nc_L'), return; end
            hold(ax,'on');
            x = 100*D.fit_mid_nc_NL(:,u); y = 100*D.fit_mid_nc_L(:,u);             % control / laser (ctrl-peak %)
            x360 = sort(x); y360 = sort(y);
            xs = sort(x(1:10:end)); ys = sort(y(1:10:end));                        % subsample THEN sort (36 pts)
            SZ = viz.plots.UnitPanels.SZ;
            if viz.paperStyle(), ioDot = [0 0 0]; else, ioDot = [.3 .3 .3]; end               % paper: black open circles
            scatter(ax, xs, ys, SZ/2, ioDot, 'o');
            isE = ~viz.plots.UnitPanels.isInhibUnit(D, u);
            thrLW = 1; thrA = 0.4; modA = 0.4;                                               % threshold-linear + I/O-model line style
            if viz.paperStyle(), thrLW = 1.4; thrA = 1; modA = 1; end                        % paper: 1.4pt SOLID fit, solid red model
            if isE
                f = viz.plots.UnitPanels.fitPiecewise36(xs, ys);                   % live fminsearch on 36 pts
                if ~isempty(f)
                    x1 = xs(xs<=f.bp); x2 = xs(xs>f.bp);
                    if ~isempty(x1), plot(ax, sort(x1), f.floor*ones(size(x1)), 'Color',[0 1 0 thrA], 'LineWidth',thrLW); end
                    if ~isempty(x2), plot(ax, sort(x2), sort(f.floor + f.slope*(x2 - f.bp)), 'Color',[0 1 0 thrA], 'LineWidth',thrLW); end
                end
                if isfield(D,'ExpM_fit'), plot(ax, x360, 100*sort(D.ExpM_fit(:,u)), 'Color',[1 0 0 modA], 'LineWidth',0.5); end
                ylim(ax, 100*[-.2 1.2]);
            else
                p = polyfit(xs, ys, 1);
                plot(ax, sort(xs), sort(polyval(p, xs)), 'Color',[0 0 1 thrA], 'LineWidth',thrLW);
                if isfield(D,'ExpM_fit'), plot(ax, 100*sort(D.ExpM_fit(:,u)), y360, 'Color',[1 0 0 modA], 'LineWidth',0.6); end  % axes swapped for I
                ylim(ax, 100*[-.2 2.6]);
            end
            if viz.paperStyle(), plot(ax, 100*[-1 2], 100*[-1 2], '--', 'Color',[0 0 0], 'LineWidth',0.75);   % paper: dashed unity
            else,                plot(ax, 100*[-1 2], 100*[-1 2], 'k', 'LineWidth',1); end
            xlim(ax, 100*[-.2 1.2]); hold(ax,'off');
        end

        function f = fitPiecewise36(x, y)
            % floor/slope/breakpoint of a 2-segment (flat then sloped) fit (V01).
            f = []; x=x(:); y=y(:); ok=isfinite(x)&isfinite(y); x=x(ok); y=y(ok);
            if numel(x) < 4, return; end
            pw = @(p,xx) (xx<=p(3)).*p(1) + (xx>p(3)).*(p(1)+p(2)*(xx-p(3)));
            try
                bp = fminsearch(@(p) sum((y - pw(p,x)).^2), [mean(y(1:round(end/2))), 1, mean(x)]);
                f.floor=bp(1); f.slope=bp(2); f.bp=bp(3);
            catch
                f = [];
            end
        end

        function R = rasOf(D, field, u)
            R = [];
            if isfield(D, field) && numel(D.(field)) >= u, R = D.(field){u}; end
        end
    end
end
