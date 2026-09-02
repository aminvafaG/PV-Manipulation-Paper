classdef Stability07Tab < viz.PlotTab
%STABILITY07TAB  Controls for Visualizer_01's f07 window ("new_delta_features");
%   the actual figure opens in its OWN maximized uifigure, built with the literal
%   old pixel positions, fonts (11 pt) and colors so it is 1:1 with the old f07.
%
%   The TAB shows only the controls; the global filter panel is in the toolbar.
%   Panels are placed in PIXELS at the exact old monitor fractions (old fig spans
%   [0 .03 1 .95] of screen, y/height /0.95), recomputed on resize.
%
%   Reproduces the old F2_5B_3 f07 window: TWELVE histograms in three spatial
%   blocks of 2x2, comparing Linear (old Type 2 == G_type 1, black) vs Non-linear
%   (old Type 3 == G_type 2, Cyellow) units on three per-unit spread metrics of
%   the delta / ratio tuning curve:
%       f7a (left,  top   , x .05/.25, y .65/.80) : SD/mean = std(c)/|mean(c)|   (kept < 1.1)
%       f7b (right, top   , x .55/.75, y .65/.80) : diff    = sum(|diff(c)|)     (kept < 1)
%       f7c (left,  bottom, x .05/.25, y .15/.30) : PP      = max(|c|) - min(|c|) (kept < 1)
%   In every block the columns are PVE (E units, left) and PVI (I units, right),
%   and the rows are the Delta curve (lower) and the Ratio curve (upper):
%       i=1 PVE-Delta   i=2 PVE-Ratio   i=3 PVI-Delta   i=4 PVI-Ratio
%   Each curve is kept only if |mean(curve)| < 10 (old good_v_th). Each panel shows
%   the two distributions (BinWidth .05, FaceAlpha .3), their medians (filled 'v'
%   markers at .9*ymax, size 4*sz) and a ranksum significance marker drawn as
%   in-axes text at (.05*xmax, .9*ymax).
%
%   Curves: Delta_tun_nc / Ratio_tun (E/I-flipped in computeMetrics). These spread
%   metrics are magnitude-based, so the E/I flip does not affect them.
%
%   CONTROLS: unit group (TuningG) + repeated-obs handling, shared with the other
%   ported tabs. The old f07 applied NO TuningG filter and no dedup; choose
%   group=ALL_UNITS + repeated-obs=All to reproduce the old population exactly.
%
%   REPEATED OBSERVATIONS -- the dropdown drives the DATA, not just the star:
%     All            every neuron x laser intensity is one sample (old f07 /
%                    the published numbers).
%     First / Max    one representative recording per neuron.
%     Mean/neuron    each neuron collapses to the MEAN of its spread values;
%                    p = rank-sum on those per-neuron means.
%     Mixed-effects  histograms/medians are the same per-neuron means, but the
%                    p comes from a model fitted to EVERY observation,
%                        v ~ class + (1|penetration) + (1|penetration:neuron)
%                    (viz.plots.V01util.smBetweenMM).
%   The panels themselves carry only the significance star (nothing is written
%   over the plots); the p, n and group means live in the "Stats report" panel
%   in the tab body, which shows every mode side by side.
%   The per-neuron collapse happens AFTER the good_v / dist gates, so a curve a
%   gate drops does not drag its whole neuron out of the population.
%   (NOTE: F27_5_3's f2 OSI/CV/HBW-by-layer figure is a SEPARATE window, not f07.)
%
%   See also: analysis.tuningGroupMask, viz.plots.V01util, viz.plots.Categorization06Tab

    properties
        groupDD; repDD; statusLbl; infoLabel
        PlotFig
        ax = {}              % 1x12 uiaxes (block order: f7a 1..4, f7b 1..4, f7c 1..4)
        LayoutSpec = {}
        LastD = []; LastMask = []
    end

    properties (Constant)
        GROUPS = {'ALL_UNITS','NO_ORI_ON_PV','NO_ORI_NO_PV','ORI_ON_PV','ORI_NON_PV','ORI_NON_PV_MD','ORI_NON_PV_NL','ORI_NON_PV_U','OUTLIER'};
        REP_ITEMS = {'All (match old code)','First per neuron','Max laser power', ...
                     'Mean per neuron','Mixed-effects (stats)'};
        REP_DATA  = {'all','first','maxpow','mean','lme'};
        GOOD_V_TH = 10;                    % old good_v_th: keep curves with |mean| < 10
        C_LIN   = [0 0 0];                 % Linear (G_type 1) histogram + median = Colorss{2}
        CYELLOW = [253 219 85]/255;        % Non-linear (G_type 2) histogram + median = Colorss{3}
        FONT = 11; LW = 1; SZ = 16.5;      % fonts=11, LWidth=1, sz=fonts*1.5
    end

    methods
        function obj = Stability07Tab()
            obj@viz.PlotTab('Stability (V07)');
        end

        % --------------------------------------------------------------- %
        function buildControls(obj, parent)
            g = uigridlayout(parent, [10 1]);
            g.RowHeight = repmat({'fit'}, 1, 10); g.RowHeight{end} = '1x';
            g.RowSpacing = 4; g.Padding = [8 8 8 8];
            uilabel(g, 'Text', 'Unit group (TuningG)');
            obj.groupDD = uidropdown(g, 'Items', obj.GROUPS, 'Value', 'ORI_NON_PV', ...
                'ValueChangedFcn', @(s,e) obj.requestRefresh());
            uilabel(g, 'Text', 'Repeated obs (per neuron)');
            obj.repDD = uidropdown(g, 'Items', obj.REP_ITEMS, 'ItemsData', obj.REP_DATA, ...
                'Value', 'all', 'ValueChangedFcn', @(s,e) obj.requestRefresh());
            uilabel(g, 'Text', '');
            uibutton(g, 'Text', 'Open figure window', 'ButtonPushedFcn', @(s,e) obj.openFigure());
            obj.addReportButton(g);
            obj.statusLbl = uilabel(g, 'Text', '', 'WordWrap', 'on', 'VerticalAlignment','top');
            obj.infoLabel = uilabel(g, 'Text', '', 'WordWrap', 'on', 'VerticalAlignment','top');
            obj.addDataSelectors(g);
        end

        function buildView(obj, parent)
            gg = obj.buildReportInstr(parent);
            uilabel(gg, 'Text', sprintf(['The Visualizer-01 "Stability" (f07) window opens in its ' ...
                'own maximized window (1:1 with the old figure).\n\nUse the controls on the left ' ...
                '(and the toolbar Filters) \x2014 the window refreshes live.']), ...
                'HorizontalAlignment','center', 'WordWrap','on', 'FontSize', 13);
        end

        % --------------------------------------------------------------- %
        function update(obj, D, mask)
            obj.LastD = D; obj.LastMask = mask;
            % NOTE: the figure window opens ONLY when the user clicks "Open figure
            % window" (obj.openFigure); selecting/refreshing the tab never auto-opens.
            if ~isempty(obj.PlotFig) && isvalid(obj.PlotFig), obj.drawFigure(); end
            if obj.ShowReport, obj.refreshReport(); end
            obj.refreshStatus();
        end

        function rs = reportSpec(obj)
            if isempty(obj.LastD), rs = []; return; end
            mask = obj.LastMask; if isempty(mask), mask = true(viz.plots.V01util.nU(obj.LastD),1); end
            state = struct('group', obj.groupDD.Value, 'mask', mask(:));
            hdr = sprintf(['Visualizer-01 stability (f07) \x2014 group %s.  12 tuning-spread tests ' ...
                '(SD/mean, diff, peak-to-peak), Linear vs Non-linear, PVE & PVI.\n' ...
                'All / First / Mean columns are rank-sums; the Mixed-effects column fits ' ...
                'v ~ class + (1|penetration) + (1|penetration:neuron) to every observation ' ...
                '(Satterthwaite df), while the means beside it are per neuron.\n' ...
                'Figure is currently drawn as \x2014 %s'], obj.groupDD.Value, ...
                obj.modeBlurb(obj.repDD.Value));
            rs = struct('figKey','f07', 'state',state, 'D',obj.LastD, 'header',hdr);
        end

        function openFigure(obj)
            if ~isempty(obj.PlotFig) && isvalid(obj.PlotFig)
                figure(obj.PlotFig); obj.drawFigure(); obj.refreshStatus(); return;
            end
            ss = get(0,'screensize'); Mx = ss(3); My = ss(4);
            obj.PlotFig = uifigure('Name','Visualizer 01 - Stability (f07)', 'Color','w', ...
                'Position', [0, round(.03*My), Mx, round(.95*My)]);
            obj.PlotFig.CloseRequestFcn = @(s,e) delete(s);
            obj.LayoutSpec = {};
            obj.createPanels();
            try, obj.PlotFig.AutoResizeChildren = 'off'; catch, end %#ok<CTCH>
            obj.PlotFig.SizeChangedFcn = @(s,e) obj.relayout();
            obj.relayout(); obj.drawFigure(); obj.refreshStatus();
        end

        function s = getControlState(obj)
            s = struct('group', obj.groupDD.Value, 'rep', obj.repDD.Value);
        end
        function setControlState(obj, s)
            if isfield(s,'group'), obj.setCtrl(obj.groupDD, s.group); end
            if isfield(s,'rep'),   obj.setCtrl(obj.repDD,   s.rep);   end
        end
    end

    % =================================================================== %
    methods (Access = private)
        function refreshStatus(obj)
            isOpen = ~isempty(obj.PlotFig) && isvalid(obj.PlotFig);
            if isOpen, obj.statusLbl.Text = 'window: open'; else, obj.statusLbl.Text = 'window: closed (click Open)'; end
        end

        function S = panelSpec(~)
            %PANELSPEC  The 12 f07 panels: fx fy metric field isI distTh xlabel title.
            %   3 blocks of 2x2; within each, col = PVE(E)/PVI(I), row = Delta(low)/Ratio(high).
            %   i=1 PVE-Delta, i=2 PVE-Ratio, i=3 PVI-Delta, i=4 PVI-Ratio.
            C = { ...
                ... % --- f7a : SD/mean (left, top) , dist_th 1.1 ------------------
                .05 .65 'sdmean' 'Delta_tun_nc' false 1.1 'SD/mean' 'PVE-SD/mean Delta Tuning L-vs-NL'; ...
                .05 .80 'sdmean' 'Ratio_tun'    false 1.1 'SD/mean' 'PVE-SD/mean Ratio Tuning L-vs-NL'; ...
                .25 .65 'sdmean' 'Delta_tun_nc' true  1.1 'SD/mean' 'PVI-SD/mean Delta Tuning L-vs-NL'; ...
                .25 .80 'sdmean' 'Ratio_tun'    true  1.1 'SD/mean' 'PVI-SD/mean Ratio Tuning L-vs-NL'; ...
                ... % --- f7b : diff (right, top) , dist_th 1 ----------------------
                .55 .65 'diff'   'Delta_tun_nc' false 1   'diff'    'PVE-diff Delta Tuning L-vs-NL'; ...
                .55 .80 'diff'   'Ratio_tun'    false 1   'diff'    'PVE-diff Ratio Tuning L-vs-NL'; ...
                .75 .65 'diff'   'Delta_tun_nc' true  1   'diff'    'PVI-diff Delta Tuning L-vs-NL'; ...
                .75 .80 'diff'   'Ratio_tun'    true  1   'diff'    'PVI-diff Ratio Tuning L-vs-NL'; ...
                ... % --- f7c : PP = peak-to-min (left, bottom) , dist_th 1 --------
                .05 .15 'p2m'    'Delta_tun_nc' false 1   'PP'      'PVE-PP Delta Tuning L-vs-NL'; ...
                .05 .30 'p2m'    'Ratio_tun'    false 1   'PP'      'PVE-PP Ratio Tuning L-vs-NL'; ...
                .25 .15 'p2m'    'Delta_tun_nc' true  1   'PP'      'PVI-PP Delta Tuning L-vs-NL'; ...
                .25 .30 'p2m'    'Ratio_tun'    true  1   'PP'      'PVI-PP Ratio Tuning L-vs-NL'; ...
            };
            S = struct('pos',{},'metric',{},'field',{},'isI',{},'distTh',{},'xlab',{},'ttl',{});
            for k = 1:size(C,1)
                S(k).pos    = [C{k,1} C{k,2} .15 .15];
                S(k).metric = C{k,3}; S(k).field = C{k,4}; S(k).isI = C{k,5};
                S(k).distTh = C{k,6}; S(k).xlab  = C{k,7}; S(k).ttl  = C{k,8};
            end
        end

        function createPanels(obj)
            S = obj.panelSpec();
            obj.ax = cell(1, numel(S));
            for k = 1:numel(S)
                obj.ax{k} = obj.addAx(S(k).pos(1), S(k).pos(2), S(k).pos(3), S(k).pos(4));
            end
        end

        function ax = addAx(obj, fx, fy, fw, fh)
            ax = uiaxes(obj.PlotFig); ax.Units = 'pixels'; ax.FontUnits = 'points';
            ax.FontSize = obj.FONT; ax.LineWidth = obj.LW; ax.XTickLabelRotation = 0;
            obj.LayoutSpec{end+1} = {ax, [fx fy fw fh]};
        end

        function relayout(obj)
            if isempty(obj.PlotFig) || ~isvalid(obj.PlotFig), return; end
            pos = obj.PlotFig.Position; W = pos(3); H = pos(4);
            if W < 30 || H < 30, return; end
            for k = 1:numel(obj.LayoutSpec)
                h = obj.LayoutSpec{k}{1}; fr = obj.LayoutSpec{k}{2};
                if ~isvalid(h), continue; end
                try, h.Position = [fr(1)*W, (fr(2)/0.95)*H, max(2,fr(3)*W), max(2,(fr(4)/0.95)*H)]; catch, end %#ok<CTCH>
            end
        end

        % ---- main draw ------------------------------------------------ %
        function drawFigure(obj)
            D = obj.LastD; mask = obj.LastMask;
            if isempty(D) || isempty(obj.PlotFig) || ~isvalid(obj.PlotFig), return; end
            obj.relayout();
            for k = 1:numel(obj.ax), if isvalid(obj.ax{k}), cla(obj.ax{k}); end, end
            if ~isfield(D,'G_type') || ~isfield(D,'Delta_tun_nc')
                title(obj.ax{1}, 'Missing G_type / Delta_tun_nc'); return;
            end
            try, grpMask = analysis.tuningGroupMask(D, obj.groupDD.Value);
            catch err, title(obj.ax{1}, ['Group error: ' err.message]); return; end

            isI = viz.plots.V01util.isInhib(D);
            G   = viz.plots.V01util.colv(D, 'G_type');
            UU  = viz.plots.V01util.colv(D, 'U_unity');   % neuron id per D-row
            PK  = viz.plots.V01util.penKey(D);            % penetration id per D-row
            sel = mask(:) & grpMask(:);
            mode = obj.repDD.Value;
            selE = find(sel & ~isI); selI = find(sel & isI);
            % EVERY per-neuron view needs one class per neuron, and the majority
            % has to be taken over ALL of that neuron's observations -- not over
            % the representative row, which would see only one and decide nothing.
            Gc = G;
            if ~strcmp(mode, 'all')
                Gc = obj.classPerNeuron(G, UU, [selE; selI]);
            end
            % 'mean'/'lme' must collapse per neuron AFTER the good_v / dist gates,
            % so they keep every observation here and reduce inside panelStats.
            if obj.perCellMode(mode)
                eRep = selE; iRep = selI;
            else
                Re = viz.plots.V01util.reducer(D, selE, mode); eRep = viz.plots.V01util.redIdx(Re);
                Ri = viz.plots.V01util.reducer(D, selI, mode); iRep = viz.plots.V01util.redIdx(Ri);
            end

            S = obj.panelSpec();
            sd = find(strcmp({S.metric},'sdmean')); legPanel = 0;   % top-left SD/mean panel gets the NL/D/M legend
            if ~isempty(sd)
                yy = arrayfun(@(s) s.pos(2), S(sd)); xx = arrayfun(@(s) s.pos(1), S(sd));
                [~,o] = sortrows([-yy(:) xx(:)]); legPanel = sd(o(1));
            end
            for k = 1:numel(S)
                if S(k).isI, reps = iRep; else, reps = eRep; end
                [M1, c1] = obj.curvesFor(D, S(k).field, reps, Gc, 1);  % Linear   (old group1, Type 2)
                [M2, c2] = obj.curvesFor(D, S(k).field, reps, Gc, 2);  % Non-lin. (old group2, Type 3)
                [v1, r1] = obj.stabMetric(M1, S(k).metric, S(k).distTh, c1);   % r1/r2 = surviving D-rows
                [v2, r2] = obj.stabMetric(M2, S(k).metric, S(k).distTh, c2);
                st = obj.panelStats(v1, r1, v2, r2, mode, UU, PK);
                obj.drawHist(obj.ax{k}, st, mode, S(k), k==legPanel);
            end

            obj.infoLabel.Text = sprintf(['group %s   E=%d obs / %d cells   I=%d obs / %d cells\n' ...
                '(black=Linear  yellow=Non-linear)\n%s\n' ...
                'ALL_UNITS + All reproduces the old f07 exactly.'], ...
                obj.groupDD.Value, numel(eRep), numel(unique(UU(eRep))), ...
                numel(iRep), numel(unique(UU(iRep))), obj.modeBlurb(mode));
        end

        function [M, cols] = curvesFor(~, D, field, reps, G, t)
            %CURVESFOR  360xK matrix of `field` for reps whose G_type == t.
            %   Also returns `cols` = the D-row index of each column (for U_unity).
            cols = reps(G(reps) == t); cols = cols(:);
            if ~isfield(D, field), M = []; cols = zeros(0,1); return; end
            if isempty(cols), M = zeros(size(D.(field),1), 0); cols = zeros(0,1); return; end
            M = D.(field)(:, cols);
        end

        function [v, vid] = stabMetric(obj, M, which, th, colIds)
            %STABMETRIC  Per-column spread metric over good_v columns, kept < th.
            %   Matches old f07: good_v = |column mean| < good_v_th, then keep < dist_th.
            %   `colIds` (optional) is a per-column id -- pass the D-ROW indices and
            %   `vid` returns the rows that survived, filtered through the SAME two
            %   masks as v, so U_unity / penetration can be read off them.
            if nargin < 5, colIds = []; end
            colIds = colIds(:);
            if isempty(M) || size(M,2) == 0, v = []; vid = []; return; end
            mu   = mean(M, 1, 'omitnan');
            keep1 = mu > -obj.GOOD_V_TH & mu < obj.GOOD_V_TH;
            Mg   = M(:, keep1);
            if numel(colIds) == numel(keep1), id1 = colIds(keep1(:)); else, id1 = []; end
            if isempty(Mg) || size(Mg,2) == 0, v = []; vid = []; return; end
            switch which
                case 'sdmean', v = std(Mg,0,1,'omitnan') ./ abs(mean(Mg,1,'omitnan'));
                case 'diff',   v = sum(abs(diff(Mg,1,1)), 1, 'omitnan');
                case 'p2m',    v = max(abs(Mg),[],1) - min(abs(Mg),[],1);
                otherwise,     v = []; vid = []; return;
            end
            keep2 = isfinite(v) & v < th;
            v = v(keep2);
            if numel(id1) == numel(keep2), vid = id1(keep2(:)); else, vid = []; end
        end

        function tf = perCellMode(~, mode)
            %PERCELLMODE  Modes whose population is ONE value per neuron.
            tf = any(strcmp(mode, {'mean','lme'}));
        end

        function Gc = classPerNeuron(~, G, UU, rows)
            %CLASSPERNEURON  One class per neuron (majority; ties -> first
            %   recording). Shared rule: viz.plots.V01util.classPerNeuron.
            Gc = viz.plots.V01util.classPerNeuron(G, UU, rows);
        end

        function [m, u] = byNeuron(~, v, id)
            %BYNEURON  Collapse to one value per neuron = the mean of its values.
            v = v(:); id = id(:);
            if isempty(v), m = []; u = []; return; end
            [u, ~, g] = unique(id, 'stable');
            m = accumarray(g, v, [], @(z) mean(z, 'omitnan'));
        end

        function st = panelStats(obj, v1, r1, v2, r2, mode, UU, PK)
            %PANELSTATS  One panel's plotted distribution AND its significance.
            %   v1/v2 = surviving spread values (Linear / Non-linear), r1/r2 their
            %   D-rows. Under 'mean'/'lme' each neuron collapses to the mean of its
            %   values FIRST, so the histogram shows exactly what the test uses.
            id1 = UU(r1); id2 = UU(r2);
            if obj.perCellMode(mode)
                [x1, c1] = obj.byNeuron(v1, id1);
                [x2, c2] = obj.byNeuron(v2, id2);
            else
                x1 = v1(:); c1 = id1(:); x2 = v2(:); c2 = id2(:);
            end
            st = struct('x1',x1, 'x2',x2, 'nObs1',numel(v1), 'nObs2',numel(v2), ...
                        'm1',NaN, 's1',NaN, 'm2',NaN, 's2',NaN, ...
                        'p',NaN, 'isRed',false, 'note','');
            if ~isempty(x1), st.m1 = mean(x1); st.s1 = std(x1)/sqrt(numel(x1)); end
            if ~isempty(x2), st.m2 = mean(x2); st.s2 = std(x2)/sqrt(numel(x2)); end
            if strcmp(mode, 'lme')
                % model on EVERY observation; the histogram stays per neuron
                [st.p, st.isRed, st.note] = viz.plots.V01util.smBetweenMM( ...
                    v1, v2, id1, id2, PK(r1), PK(r2));
            else
                [st.p, st.isRed] = viz.plots.V01util.smBetween(x1, x2, c1, c2, mode);
            end
        end

        function s = modeBlurb(~, mode)
            switch mode
                case 'lme'
                    s = ['Mixed-effects: histograms = one MEAN value per neuron; p from ' ...
                         'v ~ class + (1|penetration) + (1|penetration:neuron) on all observations.'];
                case 'mean'
                    s = 'Mean/neuron: histograms = one mean value per neuron; p = rank-sum on those.';
                case 'all'
                    s = 'All: every neuron x laser intensity is one sample (old f07 / published numbers).';
                otherwise
                    s = 'One representative recording per neuron; p = rank-sum.';
            end
        end

        function drawHist(obj, ax, st, mode, S, addLeg)
            if nargin < 6, addLeg = false; end
            v1 = st.x1; v2 = st.x2;
            hold(ax,'on');
            paper = viz.paperStyle() && strcmp(S.metric,'sdmean');       % paper S2-D style ONLY for the SD/mean (CoV) histograms
            bw = 0.05;
            if paper, cLin=[.294 .294 .294]; cNL=[.886 .890 0]; fa=0.55;  % D/M gray, NL yellow (PDF-sampled)
            else,     cLin=obj.C_LIN;        cNL=obj.CYELLOW;   fa=0.30; end
            if ~isempty(v1), histogram(ax, v1, 'BinWidth', bw, 'FaceColor', cLin, 'FaceAlpha', fa); end  % Linear / D/M
            if ~isempty(v2), histogram(ax, v2, 'BinWidth', bw, 'FaceColor', cNL,  'FaceAlpha', fa); end  % Non-linear / NL
            xlim(ax, [-0.03 1]);
            yl = ylim(ax);                                                   % read after histograms (auto)
            ma = 0.3; if paper, ma = 0.7; end
            if ~isempty(v1), scatter(ax, median(v1), 0.9*yl(2), 4*obj.SZ, cLin, 'v', 'filled', 'MarkerFaceAlpha', ma); end
            if ~isempty(v2), scatter(ax, median(v2), 0.9*yl(2), 4*obj.SZ, cNL,  'v', 'filled', 'MarkerFaceAlpha', ma); end
            xl = xlim(ax);
            % between-group (Linear vs Non-linear) star, computed in panelStats
            % under the selected mode; red when it disagrees with the All result.
            if isfinite(st.p)                                                % old: stars drawn only if the test succeeds
                viz.plots.V01util.drawSig(ax, 0.05*xl(2), 0.9*yl(2), st.p, st.isRed, 'left');
            end
            if paper                                                        % paper S2-D writings
                ylabel(ax, 'Cell count');
                met = 'RT'; if contains(S.field,'Delta'), met = '\DeltaT'; end   % Delta_tun_nc -> ΔT, Ratio_tun -> RT
                xlabel(ax, ['SD/mean ' met]); title(ax, '');
                cc = [0 0.75 0]; lbl = 'PVA'; if S.isI, cc = [0 0 1]; lbl = 'PVI'; end
                text(ax, 0.97, 0.96, lbl, 'Units','normalized', 'Color', cc, 'FontWeight','bold', ...
                    'HorizontalAlignment','right', 'VerticalAlignment','top', 'FontSize', obj.FONT);
                if addLeg, obj.dmNlLegend(ax, cLin, cNL); end
            else
                ylabel(ax, 'Count'); xlabel(ax, S.xlab); title(ax, S.ttl);
            end
            hold(ax,'off');
        end

        function dmNlLegend(obj, ax, cLin, cNL)
            %DMNLLEGEND  Paper S2-D "NL / D/M" legend (colored swatches, horizontal).
            hNL = plot(ax, nan, nan, 's', 'MarkerFaceColor',cNL,  'MarkerEdgeColor','none', 'MarkerSize',7);
            hDM = plot(ax, nan, nan, 's', 'MarkerFaceColor',cLin, 'MarkerEdgeColor','none', 'MarkerSize',7);
            try, legend(ax, [hNL hDM], {'NL','D/M'}, 'Location','north', 'Orientation','horizontal', ...
                    'Box','off', 'FontSize',obj.FONT-2); catch, end %#ok<CTCH>
        end
    end
end
