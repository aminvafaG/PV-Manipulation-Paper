classdef Categorization06Tab < viz.PlotTab
%CATEGORIZATION06TAB  Controls for Visualizer_01's f06 window (effect types); the
%   actual figure opens in its OWN maximized uifigure, built with the literal old
%   pixel positions, fonts (11 pt) and colors so it looks like the old f06 window.
%
%   The TAB shows only the controls; the global filter panel is in the toolbar.
%   Panels are placed in PIXELS at the exact old monitor fractions (old fig spans
%   [0 .03 1 .95] of screen, y/height /0.95), recomputed on resize.
%
%   Reproduces the old F2_5B_3 f06 window:
%       * f6a{1} : effect-categorization scatter -- per-unit 2nd vs 4th derivative
%                  of the (control-normalized) delta tuning at the peak, SCALED by
%                  10000 / 1000000 (= old f06_XX/f06_YY), colored by effect type
%                  (G_type 1=Linear black / 2=Non-linear yellow / 3=Unknown red),
%                  marker by experiment (o = excitation, ^ = inhibition), white
%                  edges, FaceAlpha .2, size 5*sz. "Mixed" neurons (laser-power
%                  repeats split evenly Linear/Non-linear) overlaid cyan '.'.
%       * f6b{1..4} : 4 histograms comparing per-unit STD of the delta / ratio
%                  tuning between Linear and Non-linear units (PVE row, PVI row).
%                  Linear = black, Non-linear = Cyellow [253 219 85]/255.
%       * f6c (12) : population mean (red, over faint per-unit curves) of the delta
%                  and ratio tuning, in two columns x three y-bands (Delta Lin/NL,
%                  Ratio Lin/NL, Delta/Ratio Non-Cat) with per-panel y-limits.
%       * T06    : 3 floating rotated labels ('Mean \DeltaT','Mean RT','Angle...').
%
%   old Unit.Type 2/3/4  ==  new G_type 1/2/3  (within the unit-group selection).
%   D.Delta_tun_nc / D.Ratio_tun are already E/I-flipped (computeMetrics), so they
%   are plotted DIRECTLY -- no extra negation (verified vs the old f6c draw loop).
%
%   CONTROLS: unit group (TuningG) and repeated-obs handling (per-neuron dedup).
%   The old f06 applied NO TuningG filter and no dedup; choose group=ALL_UNITS +
%   repeated-obs=All to reproduce the old population exactly.
%
%   See also: analysis.tuningGroupMask, viz.plots.V01util, viz.plots.Dashboard01Tab

    properties
        groupDD; repDD; statusLbl; infoLabel
        PlotFig
        axCateg
        stdAx = {}            % 1x4: PVE-Delta, PVE-Ratio, PVI-Delta, PVI-Ratio
        popAx = {}            % 1x12 population panels (see popLayout)
        LayoutSpec = {}
        LastD = []; LastMask = []
        SelectedUnit = NaN     % nearest unit from a categorization-scatter click
    end

    properties (Constant)
        GROUPS = {'ALL_UNITS','NO_ORI_ON_PV','NO_ORI_NO_PV','ORI_ON_PV','ORI_NON_PV','ORI_NON_PV_MD','ORI_NON_PV_NL','ORI_NON_PV_U','OUTLIER'};
        REP_ITEMS = {'All (match old code)','First per neuron','Max laser power', ...
                     'Mean per neuron','Mixed-effects (stats)'};
        REP_DATA  = {'all','first','maxpow','mean','lme'};
        GOOD_V_TH = 10;                                   % old good_v_th: keep curves with |mean| < 10
        C_TYPE  = {[0 0 0], [228 228 0]/255, [1 0 0]};    % f6a markers: Linear / Non-linear / Unknown
        CYELLOW = [253 219 85]/255;                       % f6b Non-linear histogram (Colorss{3})
        FACE_E  = [.4 1 .4];                              % f6c faint E curve (facecolorE)
        FACE_I  = [.4 .4 1];                              % f6c faint I curve (facecolorI)
        ANGLESS = [0 90 180 270 360];
        FONT = 11; LW = 1; SZ = 16.5;                     % fonts=11, LWidth=1, sz=fonts*1.5
    end

    methods
        function obj = Categorization06Tab()
            obj@viz.PlotTab('Effect types (V06)');
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
            obj.addInspectCheckbox(g);
            obj.addDataSelectors(g);
        end

        function buildView(obj, parent)
            gg = obj.buildReportInstr(parent);
            uilabel(gg, 'Text', sprintf(['The Visualizer-01 "Effect types" (f06) window opens in its ' ...
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
            hdr = sprintf(['Visualizer-01 effect types (f06) \x2014 group %s.  STD of Delta/Ratio tuning, ' ...
                'Linear vs Non-linear (rank-sum), PVE & PVI.'], obj.groupDD.Value);
            rs = struct('figKey','f06', 'state',state, 'D',obj.LastD, 'header',hdr);
        end

        function openFigure(obj)
            if ~isempty(obj.PlotFig) && isvalid(obj.PlotFig)
                figure(obj.PlotFig); obj.drawFigure(); obj.refreshStatus(); return;
            end
            ss = get(0,'screensize'); Mx = ss(3); My = ss(4);
            obj.PlotFig = uifigure('Name','Visualizer 01 - Effect types (f06)', 'Color','w', ...
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

        function createPanels(obj)
            % S2 arrangement: A = clustering scatter top-left (large); D = SD/mean
            % histograms right column; C = 12 tuning grids in the bottom band (popLayout).
            obj.axCateg = obj.addAx(.02, .52, .54, .45);          % A: scatter, top-left
            obj.stdAx = cell(1,4);
            ys = [.05 .28 .51 .74];                                % D: histograms, right column (4 stacked)
            for k = 1:4, obj.stdAx{k} = obj.addAx(.81, ys(k), .16, .18); end
            S = obj.popLayout();
            obj.popAx = cell(1, numel(S));
            for k = 1:numel(S)
                obj.popAx{k} = obj.addAx(S(k).pos(1), S(k).pos(2), S(k).pos(3), S(k).pos(4));
            end
            obj.createLabels();
        end

        function ax = addAx(obj, fx, fy, fw, fh)
            ax = uiaxes(obj.PlotFig); ax.Units = 'pixels'; ax.FontUnits = 'points';
            ax.FontSize = obj.FONT; ax.LineWidth = obj.LW; ax.XTickLabelRotation = 0;
            obj.LayoutSpec{end+1} = {ax, [fx fy fw fh]};
        end
        function addLabel(obj, fx, fy, fw, fh, txt, rot)
            % floating axis-label = invisible uiaxes holding one rotated text at (0,0),
            % positioned in figure fractions (old F2_5B_3 T06 labels, color 'k').
            ax = uiaxes(obj.PlotFig); ax.Units = 'pixels'; ax.Visible = 'off';
            text(ax, 0, 0, txt, 'Color','k', 'Rotation',rot, 'FontUnits','points', 'FontSize',obj.FONT);
            obj.LayoutSpec{end+1} = {ax, [fx fy fw fh]};
        end
        function createLabels(obj)
            obj.addLabel(.005, .35, .04, .16, 'Mean \DeltaT', 90);                % C: ΔT rows (top of the bottom band)
            obj.addLabel(.005, .16, .04, .16, 'Mean RT', 90);                     % C: RT rows
            obj.addLabel(.10, .00, .45, .035, ['Angle from peak(' char(176) ')'], 0); % C: x-label (under the band)
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
            obj.relayout(); obj.clearAll();
            if ~isfield(D,'G_type') || ~isfield(D,'Delta_tun_nc')
                title(obj.axCateg, 'Missing G_type / Delta_tun_nc'); return;
            end
            try, grpMask = analysis.tuningGroupMask(D, obj.groupDD.Value);
            catch err, title(obj.axCateg, ['Group error: ' err.message]); return; end

            isI = viz.plots.V01util.isInhib(D);
            G   = viz.plots.V01util.colv(D, 'G_type');
            UU  = viz.plots.V01util.colv(D, 'U_unity');
            PK  = viz.plots.V01util.penKey(D);
            sel = mask(:) & grpMask(:);
            eIdx = find(sel & ~isI); iIdx = find(sel & isI);
            mode = obj.repDD.Value;
            Re = viz.plots.V01util.reducer(D, eIdx, mode); eRep = viz.plots.V01util.redIdx(Re);
            Ri = viz.plots.V01util.reducer(D, iIdx, mode); iRep = viz.plots.V01util.redIdx(Ri);
            % f6b (the STD histograms) works per neuron under 'mean'/'lme': every
            % observation enters, the per-unit STD values collapse per neuron AFTER
            % the good_v gate, and G_type resolves to each neuron's majority class
            % (the V07 pattern; f6a/f6c keep the representative-row view).
            perCell = any(strcmp(mode, {'mean','lme'}));
            Gc = G;
            if ~strcmp(mode, 'all'), Gc = viz.plots.V01util.classPerNeuron(G, UU, [eIdx; iIdx]); end
            if perCell, eStd = eIdx; iStd = iIdx; else, eStd = eRep; iStd = iRep; end
            % f6a/f6c per-neuron reps: one row per neuron for the scatter dots and
            % population curves under 'mean'/'lme' (curves averaged per neuron).
            if perCell
                eCat = viz.plots.V01util.redIdx(viz.plots.V01util.reducer(D, eIdx, 'first'));
                iCat = viz.plots.V01util.redIdx(viz.plots.V01util.reducer(D, iIdx, 'first'));
            else
                eCat = eRep; iCat = iRep;
            end

            % ---- f6a categorization scatter --------------------------------
            obj.drawCateg(D, eCat, iCat, Gc, [eIdx; iIdx]);

            % ---- f6b STD histograms (Linear vs Non-linear) -----------------
            % Values + surviving rows come from ONE gate application (stdVals);
            % per-cell modes then collapse per neuron. Star: LME on observations
            % under Mixed-effects, rank-sum of the shown per-neuron means under
            % Mean/neuron, classic rank-sum otherwise -- same as the stats report.
            stdSpec = { 'Delta_tun_nc', 'PVE-STD Delta Tuning L-vs-NL', false, false; ...
                        'Ratio_tun',    'PVE-STD Ratio Tuning L-vs-NL', true,  false; ...   % PVE-Ratio xlim special
                        'Delta_tun_nc', 'PVI-STD Delta Tuning L-vs-NL', false, true;  ...
                        'Ratio_tun',    'PVI-STD Ratio Tuning L-vs-NL', false, true };
            for q = 1:size(stdSpec,1)
                if stdSpec{q,4}, reps = iStd; else, reps = eStd; end
                [v1, r1] = obj.stdVals(D, stdSpec{q,1}, reps, Gc, 1);
                [v2, r2] = obj.stdVals(D, stdSpec{q,1}, reps, Gc, 2);
                if perCell
                    x1 = viz.plots.V01util.aggNeuronScalar(v1, UU(r1));
                    x2 = viz.plots.V01util.aggNeuronScalar(v2, UU(r2));
                else
                    x1 = v1(:); x2 = v2(:);
                end
                if strcmp(mode, 'lme')
                    [p, isRed] = viz.plots.V01util.smBetweenMM(v1, v2, UU(r1), UU(r2), PK(r1), PK(r2));
                elseif strcmp(mode, 'mean')
                    [p, isRed] = viz.plots.V01util.smBetween(x1, x2, [], [], mode);
                else
                    [p, isRed] = viz.plots.V01util.smBetween(v1, v2, UU(r1), UU(r2), mode);
                end
                obj.drawStd(obj.stdAx{q}, x1, x2, stdSpec{q,2}, stdSpec{q,3}, p, isRed);
            end

            % ---- f6c population panels -------------------------------------
            % Per-neuron modes: every observation's curve enters, then each
            % neuron's curves average into one (aggNeuronCurves); class = Gc.
            S = obj.popLayout();
            for k = 1:numel(S)
                if S(k).isE, rp = eStd; else, rp = iStd; end
                cols = rp(Gc(rp) == S(k).t); cols = cols(:);
                if ~isfield(D, S(k).field) || isempty(cols)
                    M = zeros(360, 0);
                else
                    M = D.(S(k).field)(:, cols);
                    if perCell, M = viz.plots.V01util.aggNeuronCurves(M, UU(cols)); end
                end
                obj.drawPop(obj.popAx{k}, M, S(k).isE, [S(k).ylo S(k).yhi], S(k).ttl);
            end
            obj.matchPlotWidths();

            obj.infoLabel.Text = sprintf('group %s   E=%d  I=%d   (Lin/NL/Unk E: %d/%d/%d)', ...
                obj.groupDD.Value, numel(eRep), numel(iRep), ...
                sum(G(eRep)==1), sum(G(eRep)==2), sum(G(eRep)==3));
        end

        function clearAll(obj)
            if isvalid(obj.axCateg), cla(obj.axCateg); end
            for k = 1:numel(obj.stdAx), if isvalid(obj.stdAx{k}), cla(obj.stdAx{k}); end, end
            for k = 1:numel(obj.popAx), if isvalid(obj.popAx{k}), cla(obj.popAx{k}); end, end
        end

        % ---- f6a -------------------------------------------------------- %
        function drawCateg(obj, D, eRep, iRep, G, fullSel)
            ax = obj.axCateg; hold(ax,'on');
            x = 10000   * viz.plots.V01util.colv(D, 'dTun_d2_center');   % = old f06_XX
            y = 1000000 * viz.plots.V01util.colv(D, 'dTun_d4_center');   % = old f06_YY
            if any(strcmp(obj.repDD.Value, {'mean','lme'}))
                % per-neuron dots: each neuron's x/y = the mean over its selected
                % observations (reps carry one row per neuron in these modes)
                uuD = viz.plots.V01util.colv(D, 'U_unity');
                x = viz.plots.V01util.avgIntoReps(x, fullSel, uuD);
                y = viz.plots.V01util.avgIntoReps(y, fullSel, uuD);
            end
            sz5 = 5 * obj.SZ;                                            % 82.5
            elw = 0.2; fa = 0.2; cT = obj.C_TYPE;                        % types {D/M, NL, Uct}
            paper = viz.paperStyle();
            if paper                                                     % paper S2-A: ratio dots + PDF-sampled colors
                sz5 = viz.plots.V01util.paperDotArea(ax); elw = 0.5; fa = 0.6;
                cT = {[.294 .294 .294], [.886 .890 0], [1 0 0]};        % D/M gray, NL yellow, Uct red
            end
            mk = {'o','^'}; reps = {eRep, iRep};
            mx = obj.mixedNeurons(D, fullSel, G);                       % corrected per-neuron Lin/NL split
            for c = 1:2                                                 % E (o) then I (^)
                rp = reps{c};
                for t = 1:3
                    sub = rp(G(rp) == t);
                    if isempty(sub), continue; end
                    scatter(ax, x(sub), y(sub), sz5, 'Marker', mk{c}, ...
                        'MarkerFaceColor', cT{t}, 'MarkerEdgeColor',[1 1 1], ...
                        'LineWidth', elw, 'MarkerFaceAlpha', fa);
                end
                mxc = intersect(mx, rp);                               % mixed of this condition, drawn after its types
                if ~isempty(mxc)
                    if paper                                           % Mix = white OPEN marker (dark ring), per condition
                        scatter(ax, x(mxc), y(mxc), sz5, 'Marker', mk{c}, 'MarkerFaceColor','w', ...
                            'MarkerEdgeColor',[.15 .15 .15], 'LineWidth',0.5, 'MarkerFaceAlpha',1);
                    else
                        scatter(ax, x(mxc), y(mxc), sz5, '.', 'MarkerFaceColor',[0 1 1], ...
                            'MarkerEdgeColor',[0 1 1], 'LineWidth', elw, 'MarkerFaceAlpha', 0.2);
                    end
                end
            end
            xline(ax,0); yline(ax,0);
            xlim(ax,[-3.5 5.5]); ylim(ax,[-2 2]);
            if paper, title(ax,''); obj.categLegend(ax); else, title(ax,'Effect Categorization'); end
            if paper, yl4 = 'Fourth'; else, yl4 = 'Forth'; end          % paper spelling
            ylabel(ax,[yl4 ' differentiation  $(10^6)$ '], 'Interpreter', 'latex');
            xlabel(ax,'Second differentiation  $(10^4)$ ', 'Interpreter', 'latex');
            rr = [eRep(:); iRep(:)];
            ax.ButtonDownFcn = @(s,e) obj.onCategClick(s, e, x, y, rr);
            obj.registerRing(ax, x(rr), y(rr), rr);   % track unit across plots
            viz.plots.V01util.highlightUnits(ax, x(rr), y(rr), rr, obj.SelectedUnit);
            hold(ax,'off');
        end

        function categLegend(obj, ax)
            %CATEGLEGEND  Paper S2-A legend: NL / D/M / Uct / Mix (colored markers,
            %   horizontal, top). Off-screen dummy handles so all 4 entries always show.
            yNL=[.886 .890 0]; gDM=[.294 .294 .294]; red=[1 0 0];
            h1 = scatter(ax, nan, nan, 40, 'o', 'MarkerFaceColor',yNL, 'MarkerEdgeColor','w', 'MarkerFaceAlpha',0.6);
            h2 = scatter(ax, nan, nan, 40, 'o', 'MarkerFaceColor',gDM, 'MarkerEdgeColor','w', 'MarkerFaceAlpha',0.6);
            h3 = scatter(ax, nan, nan, 40, 'o', 'MarkerFaceColor',red, 'MarkerEdgeColor','w', 'MarkerFaceAlpha',0.6);
            h4 = scatter(ax, nan, nan, 40, 'o', 'MarkerFaceColor','w',  'MarkerEdgeColor',[.15 .15 .15]);
            try, legend(ax, [h1 h2 h3 h4], {'NL','D/M','Uct','Mix'}, 'Location','north', ...
                    'Orientation','horizontal', 'Box','off', 'FontSize',obj.FONT-1); catch, end %#ok<CTCH>
        end

        function mx = mixedNeurons(~, D, selIdx, G)
            % "mixed" = neurons whose laser-power repeats split evenly Linear/Non-linear.
            % (The old code's intersect(mixed_UU, I_ext) is a UU-number-as-index bug; this
            % is the corrected per-neuron version over U_unity within the current selection.)
            mx = [];
            if ~isfield(D,'U_unity') || isempty(selIdx), return; end
            uu = double(D.U_unity(selIdx));
            [u,~,grp] = unique(uu(:),'stable');
            for j = 1:numel(u)
                mem = selIdx(grp == j);
                n1 = sum(G(mem)==1); n2 = sum(G(mem)==2);
                if n1 == n2 && n1 ~= 0, mx = [mx; mem(:)]; end %#ok<AGROW>
            end
        end

        function onCategClick(obj, ax, e, X, Y, reps)
            % nearest unit (old PlotRast08 metric: raw Euclidean with y weighted x100).
            % The old window then drew rasters into the MAIN dashboard's per-unit panels
            % (cross-window) -- that is deferred; here we report the unit in the readout.
            if isempty(reps), return; end
            try, pt = e.IntersectionPoint(1:2); catch, return; end
            dx = X(reps) - pt(1); dy = 100*(Y(reps) - pt(2));
            [~, k] = min(dx.^2 + dy.^2); u = reps(k);
            obj.SelectedUnit = u;
            uu = NaN; if isfield(obj.LastD,'U_unity'), uu = double(obj.LastD.U_unity(u)); end
            gt = NaN; if isfield(obj.LastD,'G_type'),  gt = double(obj.LastD.G_type(u));  end
            obj.infoLabel.Text = sprintf('clicked unit #%d  (U_unity %g, G_type %g)', u, uu, gt);
            viz.plots.V01util.highlightUnits(ax, X(reps), Y(reps), reps, u);   % ring the picked point
            obj.inspectPick(u);                                               % open/update the inspector popup
            obj.trackPick(u);                                                 % ring across every plot if tracking
        end

        % ---- f6b -------------------------------------------------------- %
        function M = curvesFor(~, D, field, reps, G, t)
            %CURVESFOR  360xK matrix of `field` for reps whose G_type == t.
            if ~isfield(D, field), M = []; return; end
            cols = reps(G(reps) == t);
            if isempty(cols), M = zeros(size(D.(field),1), 0); return; end
            M = D.(field)(:, cols);
        end

        function [s, rows] = stdVals(obj, D, field, reps, G, t)
            %STDVALS  Per-unit tuning STD over good_v columns + surviving D-rows.
            %   One gate application yields BOTH the values and their rows, so the
            %   ids (U_unity / penetration) can never drift out of lock-step with
            %   the STDs (replaces the old curveStd / curveStdNeur pair).
            s = zeros(0,1); rows = zeros(0,1);
            if ~isfield(D, field), return; end
            cols = reps(G(reps) == t); cols = cols(:);
            if isempty(cols), return; end
            M    = D.(field)(:, cols);
            mu   = mean(M, 1, 'omitnan');
            good = mu > -obj.GOOD_V_TH & mu < obj.GOOD_V_TH;
            s    = std(M(:, good), 0, 1, 'omitnan'); s = s(:);
            rows = cols(good);
            keep = isfinite(s);
            s = s(keep); rows = rows(keep);
        end

        function drawStd(obj, ax, sLin, sNL, ttl, isPVERatio, p, isRed)
            hold(ax,'on');
            bw = [];
            if ~isempty(sLin)
                H1 = histogram(ax, sLin, 'FaceColor', obj.C_TYPE{1}, 'FaceAlpha', 0.3);  % Linear = black
                H1.BinWidth = H1.BinWidth / 2; bw = H1.BinWidth;                          % old halves the bin width
            end
            if ~isempty(sNL)
                if isempty(bw)
                    histogram(ax, sNL, 'FaceColor', obj.CYELLOW, 'FaceAlpha', 0.3);       % Non-linear = Cyellow
                else
                    histogram(ax, sNL, 'BinWidth', bw, 'FaceColor', obj.CYELLOW, 'FaceAlpha', 0.3);
                end
            end
            xlabel(ax,'STD'); ylabel(ax,'Count');
            if isPVERatio, XlimI = xlim(ax); xlim(ax, [.3*XlimI(1) .4]); end             % old i==2 special
            yl = ylim(ax); xl = xlim(ax);
            if ~isempty(sLin), scatter(ax, median(sLin), 0.9*yl(2), 4*obj.SZ, [0 .3 1], 'v','filled','MarkerFaceAlpha',0.3); end  % blue Lin median
            if ~isempty(sNL),  scatter(ax, median(sNL),  0.9*yl(2), 4*obj.SZ, [0 0 0],  'v','filled','MarkerFaceAlpha',0.3); end  % black NL median
            viz.plots.V01util.drawSig(ax, 0.05*xl(2), 0.9*yl(2), p, isRed, 'left');
            title(ax, ttl); hold(ax,'off');
        end

        % ---- f6c -------------------------------------------------------- %
        function S = popLayout(~)
            %POPLAYOUT  12 population panels: fx fy field G_type isE ylo yhi title.
            %   Two columns (Linear/Delta-NonCat x=.72; Non-linear/Ratio-NonCat x=.87),
            %   three y-bands; each E panel (lower) paired with its I panel (upper).
            C = { ...
                .72 .615 'Delta_tun_nc' 1 1 -1   .3  'Delta Tuning Linear'; ...
                .72 .765 'Delta_tun_nc' 1 0 -1.5 .3  'Delta Tuning Linear'; ...
                .87 .615 'Delta_tun_nc' 2 1 -1   .3  'Delta Tuning Non-Linear'; ...
                .87 .765 'Delta_tun_nc' 2 0 -1.5 .3  'Delta Tuning Non-Linear'; ...
                .72 .31  'Ratio_tun'    1 1 -.1  1.5 'Ratio Tuning Linear'; ...
                .72 .46  'Ratio_tun'    1 0 -.1  1.5 'Ratio Tuning Linear'; ...
                .87 .31  'Ratio_tun'    2 1 -.1  1.5 'Ratio Tuning Non-Linear'; ...
                .87 .46  'Ratio_tun'    2 0 -.1  1.5 'Ratio Tuning Non-Linear'; ...
                .72 .005 'Delta_tun_nc' 3 1 -1   0   'Delta Tuning Non-Cat'; ...
                .72 .155 'Delta_tun_nc' 3 0 -3   0   'Delta Tuning Non-Cat'; ...
                .87 .005 'Ratio_tun'    3 1  0   1.5 'Ratio Tuning Non-Cat'; ...
                .87 .155 'Ratio_tun'    3 0  0   1.5 'Ratio Tuning Non-Cat'; ...
            };
            S = struct('pos',{},'field',{},'t',{},'isE',{},'ylo',{},'yhi',{},'ttl',{});
            for k = 1:size(C,1)
                col = mod(k-1,4); row = floor((k-1)/4);            % S2-C: 4 cols x 3 rows, row-major, bottom band
                S(k).pos   = [.06 + col*.165, .35 - row*.165, .15, .145];
                S(k).field = C{k,3}; S(k).t = C{k,4}; S(k).isE = C{k,5};
                S(k).ylo   = C{k,6}; S(k).yhi = C{k,7}; S(k).ttl = C{k,8};
            end
        end

        function drawPop(obj, ax, M, isE, yl, ttl)
            hold(ax,'on');
            if isempty(M) || size(M,2) == 0, title(ax, ttl); hold(ax,'off'); return; end
            n = size(M,1); x = (1:n)';
            if isE, fc = obj.FACE_E; else, fc = obj.FACE_I; end
            plot(ax, x, M, 'Color', [fc 0.2]);                          % faint per-unit curves (ALL columns)
            mu = mean(M, 1);
            good = mu > -obj.GOOD_V_TH & mu < obj.GOOD_V_TH;
            if any(good), plot(ax, x, mean(M(:, good), 2), 'Color', [1 0 0 0.5]); end   % red mean (good_v only)
            xlim(ax, [0 360]); ylim(ax, yl);
            xticks(ax, obj.ANGLESS); xticklabels(ax, string(obj.ANGLESS - 180)); xtickangle(ax, 0);
            title(ax, ttl); hold(ax,'off');
        end

        % equalize the DATA-area width of the f6c panels (old TightInset trick):
        % inner width = .08*figW + the axis TightInset, so stacked curves line up on x.
        function matchPlotWidths(obj)
            if isempty(obj.PlotFig) || ~isvalid(obj.PlotFig), return; end
            inner = 0.08 * obj.PlotFig.Position(3);
            for k = 1:numel(obj.popAx)
                ax = obj.popAx{k}; if isempty(ax) || ~isvalid(ax), continue; end
                try
                    ti = ax.TightInset; p = ax.Position;
                    ax.Position = [p(1), p(2), inner + ti(1) + ti(3), p(4)];
                catch
                end
            end
        end
    end
end
