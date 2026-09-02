classdef Composition03Tab < viz.PlotTab
%COMPOSITION03TAB  Controls for Visualizer_03.m's SECOND window (f2); the actual
%   figure opens in its OWN maximized uifigure, built with the literal old pixel
%   positions, fonts (11 pt) and colors so it is 1:1 with the old V03 fig 2.
%
%   The TAB shows only the controls; the global filter panel is in the toolbar.
%   Panels are placed in PIXELS at the exact old monitor fractions (old fig spans
%   [0 .03 1 .95] of screen, y/height /0.95), recomputed on resize.
%
%   The old f2 window holds 12 axes a20{1..12} at the SAME positions as fig 1's
%   a2{1..12}, but only THREE are ever drawn (a20{1..9} are created empty):
%     a20{10}: per-neuron laminar composition, MXH / MUL / (MXH-MUL+UCT) % by
%              layer  (the 3-category MERGE of fig 1's 4-category a2{10}).
%     a20{11}: MXH vs MUL only, % by layer (identical to fig 1's a2{11}).
%     a20{12}: global composition across all layers, MXH / MUL / (MXH-MUL+UCT).
%
%   The composition is the old UU_A_M_34: each unique neuron (U_unity) is tallied
%   over its observations as MXH(G_type 2) vs MUL(G_type 1); a tie (>0 each) is
%   MXH-MUL, both-zero is UCT; the neuron is placed in its dominant layer
%   (mode of LG). f2 folds MXH-MUL into UCT for the 3-category panels. This is
%   per-neuron and so is INDEPENDENT of any repeated-obs reduction.
%
%   Gain class = G_type: 1=Mlt/MUL (multiplicative, black), 2=MXH (additive,
%   yellow), 3=UCT (red). No new computeMetrics fields are needed.
%
%   CONTROLS: unit group (TuningG); layers (3 or 4). The old script used
%   TuningG='ORI_NON_PV' and laminar_N=4, so group=ORI_NON_PV + layers=4
%   reproduces the old f2.
%
%   See also: analysis.tuningGroupMask, viz.plots.V01util, viz.plots.GainLaminar03Tab

    properties
        groupDD; laminarDD; repDD; statusLbl; infoLabel
        PlotFig
        a20 = {}                % 1x12 axes (only 10/11/12 populated; 1-9 empty)
        LayoutSpec = {}
        LastD = []; LastMask = []
    end

    properties (Constant)
        GROUPS = {'ALL_UNITS','NO_ORI_ON_PV','NO_ORI_NO_PV','ORI_ON_PV','ORI_NON_PV','ORI_NON_PV_MD','ORI_NON_PV_NL','ORI_NON_PV_U','OUTLIER'};
        REP_ITEMS = {'All (match old code)','First per neuron','Max laser power', ...
                     'Mean per neuron','Mixed-effects (stats)'};
        REP_DATA  = {'all','first','maxpow','mean','lme'};
        COL_E = [0 1 0];                 % PVE green (old [0 1 0])
        COL_I = [0 0 1];                 % PVI blue
        C_MXH = [253 219 85]/255;        % additive / MXH (old Cyellow)
        C_MLT = [0 0 0];                 % multiplicative / MUL (old black)
        C_UCT = [1 0 0];                 % unclassified / UCT (old red)
        LAYER_LAB = {'SG','G','IG','Deep'};
        FONT = 11; LW = 1; SZ = 7.7;     % fonts = 11, sz = fonts*.7
    end

    methods
        function obj = Composition03Tab()
            obj@viz.PlotTab('Population composition (V03b)');
        end

        % --------------------------------------------------------------- %
        function buildControls(obj, parent)
            g = uigridlayout(parent, [11 1]);
            g.RowHeight = repmat({'fit'}, 1, 11); g.RowHeight{end} = '1x';
            g.RowSpacing = 4; g.Padding = [8 8 8 8];
            uilabel(g, 'Text', 'Unit group (TuningG)');
            obj.groupDD = uidropdown(g, 'Items', obj.GROUPS, 'Value', 'ORI_NON_PV', ...
                'ValueChangedFcn', @(s,e) obj.requestRefresh());
            uilabel(g, 'Text', 'Layers');
            obj.laminarDD = uidropdown(g, 'Items', {'3 (SG/G/IG)','4 (+Deep)'}, ...
                'ItemsData', [3 4], 'Value', 4, 'ValueChangedFcn', @(s,e) obj.requestRefresh());
            uilabel(g, 'Text', 'Repeated obs');
            obj.repDD = uidropdown(g, 'Items', obj.REP_ITEMS, 'ItemsData', obj.REP_DATA, ...
                'Value', 'lme', 'ValueChangedFcn', @(s,e) obj.requestRefresh());
            uilabel(g, 'Text', '');
            uibutton(g, 'Text', 'Open figure window', 'ButtonPushedFcn', @(s,e) obj.openFigure());
            obj.addReportButton(g);
            obj.statusLbl = uilabel(g, 'Text', '', 'WordWrap', 'on', 'VerticalAlignment','top');
            obj.infoLabel = uilabel(g, 'Text', '', 'WordWrap', 'on', 'VerticalAlignment','top');
            obj.addDataSelectors(g);
        end

        function buildView(obj, parent)
            gg = obj.buildReportInstr(parent);
            uilabel(gg, 'Text', sprintf(['The Visualizer-03 "Population composition" (fig 2) window ' ...
                'opens in its own maximized window (1:1 with the old figure: 12 axes, only the three ' ...
                'composition panels drawn).\n\nUse the controls on the left (and the toolbar Filters) ' ...
                '\x2014 the window refreshes live.']), ...
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
            % Composition has no inferential tests (rep-independent per-neuron
            % tallies) -> build the table directly and pass it as rs.out.
            if isempty(obj.LastD), rs = []; return; end
            D = obj.LastD; mask = obj.LastMask;
            if isempty(mask), mask = true(viz.plots.V01util.nU(D),1); end
            colv = @viz.plots.V01util.colv;
            grpMask = analysis.tuningGroupMask(D, obj.groupDD.Value);
            sel = mask(:) & grpMask(:);
            G = colv(D,'G_type'); LGn = viz.plots.V01util.layerNum(D); UU = colv(D,'U_unity');
            nL = obj.laminarDD.Value;
            M = obj.lamComposition(UU, G, LGn, find(sel), nL);   % 4 x nL [MXH;MUL;MXH-MUL;UCT]
            merged = [M(1,:); M(2,:); M(3,:)+M(4,:)];            % MXH / MUL / UCT
            layNames = {'SG','G','IG','Deep'}; cats = {'MXH','MUL','UCT'};
            colN = [{'Category'}, layNames(1:nL), {'Global %','N'}];
            Data = cell(3, numel(colN)); tot = sum(merged,2); gtot = sum(tot); dash = sprintf('\x2014');
            for r = 1:3
                Data{r,1} = cats{r};
                for L = 1:nL
                    cs = sum(merged(:,L));
                    if cs > 0, Data{r,1+L} = sprintf('%.1f%% (%d)', 100*merged(r,L)/cs, merged(r,L)); else, Data{r,1+L} = dash; end
                end
                if gtot > 0, Data{r,1+nL+1} = sprintf('%.1f%%', 100*tot(r)/gtot); else, Data{r,1+nL+1} = dash; end
                Data{r,1+nL+2} = sprintf('%d', round(tot(r)));
            end
            out = struct('ColumnName',{colN}, 'Data',{Data}, 'modes',{{}});
            hdr = sprintf(['Visualizer-03 population composition (f2) \x2014 group %s, %d layers.  ' ...
                'Per-neuron gain-class composition (descriptive; repeat-independent).'], obj.groupDD.Value, nL);
            rs = struct('figKey','V03f2', 'state',struct(), 'D',D, 'header',hdr, 'out',out);
        end

        function openFigure(obj)
            if ~isempty(obj.PlotFig) && isvalid(obj.PlotFig)
                figure(obj.PlotFig); obj.drawFigure(); obj.refreshStatus(); return;
            end
            ss = get(0,'screensize'); Mx = ss(3); My = ss(4);
            obj.PlotFig = uifigure('Name','Visualizer 03 - Population composition (fig 2)', 'Color','w', ...
                'Position', [0, round(.03*My), Mx, round(.95*My)]);
            obj.PlotFig.CloseRequestFcn = @(s,e) delete(s);
            obj.LayoutSpec = {};
            obj.createPanels();
            try, obj.PlotFig.AutoResizeChildren = 'off'; catch, end %#ok<CTCH>
            obj.PlotFig.SizeChangedFcn = @(s,e) obj.relayout();
            obj.relayout(); obj.drawFigure(); obj.refreshStatus();
        end

        function s = getControlState(obj)
            s = struct('group', obj.groupDD.Value, 'rep', obj.repDD.Value, 'lam', obj.laminarDD.Value);
        end
        function setControlState(obj, s)
            if isfield(s,'group'), obj.setCtrl(obj.groupDD, s.group); end
            if isfield(s,'rep'),   obj.setCtrl(obj.repDD,   s.rep);   end
            if isfield(s,'lam'),   obj.setCtrl(obj.laminarDD,s.lam);  end
        end
    end

    % =================================================================== %
    methods (Access = private)
        function refreshStatus(obj)
            isOpen = ~isempty(obj.PlotFig) && isvalid(obj.PlotFig);
            if isOpen, obj.statusLbl.Text = 'window: open'; else, obj.statusLbl.Text = 'window: closed (click Open)'; end
        end

        % ---- panel construction --------------------------------------- %
        function createPanels(obj)
            % Paper Fig 4 layout: A/PVA column (OSI/CV/HBW boxes = a20{1..3}),
            % B/PVI column (a20{4..6}), C = "% of layer count" a20{11}. a20{10}/{12}
            % (the composition bars) are moved far right; a20{7..9} parked off-screen.
            pa2 = {[.06 .70 .13 .235],[.06 .40 .13 .235],[.06 .10 .13 .235], ...
                   [.21 .70 .13 .235],[.21 .40 .13 .235],[.21 .10 .13 .235], ...
                   [1.2 1.2 .01 .01],[1.2 1.2 .01 .01],[1.2 1.2 .01 .01], ...
                   [.70 .55 .22 .20],[.42 .40 .22 .22],[.70 .18 .16 .20]};
            obj.a20 = cell(1,12);
            for k = 1:12, obj.a20{k} = obj.addAx(pa2{k}(1),pa2{k}(2),pa2{k}(3),pa2{k}(4)); end
            % panel letters + column headers (titles won't show: classBox blanks them in paper mode).
            % NOTE: relayout maps fy -> fy/0.95, so the visible-top targets are pre-scaled by 0.95.
            obj.addLabel(.05, .917, .05, .10, 'A',   obj.FONT+3);   % visual y ~ .965
            obj.addLabel(.20, .917, .05, .10, 'B',   obj.FONT+3);
            obj.addLabel(.41, .635, .05, .10, 'C',   obj.FONT+3);   % visual y ~ .668 (just above panel C)
            obj.addLabel(.10, .917, .06, .10, 'PVA', obj.FONT+1);
            obj.addLabel(.25, .917, .06, .10, 'PVI', obj.FONT+1);
        end

        function addLabel(obj, fx, fy, fw, fh, txt, fsz, col)
            if nargin < 7 || isempty(fsz), fsz = obj.FONT; end
            if nargin < 8 || isempty(col), col = 'k'; end
            ax = uiaxes(obj.PlotFig); ax.Units = 'pixels'; ax.Visible = 'off';
            text(ax, 0, 0, txt, 'Color', col, 'FontUnits','points', 'FontSize', fsz, 'FontWeight','bold');
            obj.LayoutSpec{end+1} = {ax, [fx fy fw fh]};
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
            obj.relayout(); obj.clearAll();
            need = {'G_type','U_unity','LG','fitOSI_NL','fitCV_NL','fitHBW_NL'};
            for q = 1:numel(need)
                if ~isfield(D, need{q}), title(obj.a20{10}, ['Missing ' need{q}]); return; end
            end
            try, grpMask = analysis.tuningGroupMask(D, obj.groupDD.Value);
            catch err, title(obj.a20{10}, ['Group error: ' err.message]); return; end

            colv = @viz.plots.V01util.colv;
            G   = colv(D,'G_type');
            LGn = viz.plots.V01util.layerNum(D);
            UU  = colv(D,'U_unity');
            sel = mask(:) & grpMask(:);
            nL  = obj.laminarDD.Value;

            % ---- paper Fig 4 A/B : OSI/CV/HBW box plots, PVA (E) & PVI (I) ----
            isI  = viz.plots.V01util.isInhib(D);
            mode = obj.repDD.Value;
            eObs = find(sel & ~isI); iObs = find(sel & isI);
            Re = viz.plots.V01util.reducer(D, eObs, mode); eRep = viz.plots.V01util.redIdx(Re);
            Ri = viz.plots.V01util.reducer(D, iObs, mode); iRep = viz.plots.V01util.redIdx(Ri);
            PK = viz.plots.V01util.penKey(D);
            % class boxes: one MXH/Mlt/UCT class per neuron for every per-neuron
            % view, and 'mean'/'lme' feed ALL observations (collapsed per neuron
            % inside classBox) so 'mean' truly averages instead of keeping the
            % first recording per neuron.
            Gc = G;
            if ~strcmp(mode, 'all'), Gc = viz.plots.V01util.classPerNeuron(G, UU, [eObs; iObs]); end
            if any(strcmp(mode, {'mean','lme'})), eCls = eObs; iCls = iObs; else, eCls = eRep; iCls = iRep; end
            osiNL = viz.plots.V01util.colv(D,'fitOSI_NL');
            cvNL  = viz.plots.V01util.colv(D,'fitCV_NL');
            hbwNL = viz.plots.V01util.colv(D,'fitHBW_NL');
            badU  = viz.plots.V01util.colv(D,'Align_bad') == 1; hbwNL(badU)=NaN;
            mets = {osiNL,'OSI',[0 1.1]; cvNL,'CV',[0 1.1]; hbwNL,'HBW',[0 50]};
            for k = 1:3
                obj.classBox(obj.a20{k},   mets{k,1}, eCls, Gc, ['PVA - ' mets{k,2}], mets{k,2}, mets{k,3}, UU, PK, mode);
                obj.classBox(obj.a20{k+3}, mets{k,1}, iCls, Gc, ['PVI - ' mets{k,2}], mets{k,2}, mets{k,3}, UU, PK, mode);
            end

            % old UU_A_M_34: 4 x nL rows [MXH; MUL; MXH-MUL(tie); UCT]
            M = obj.lamComposition(UU, G, LGn, find(sel), nL);
            merged = [M(1,:); M(2,:); M(3,:)+M(4,:)];     % f2 folds MXH-MUL into UCT

            % a20{11} : MXH vs MUL (NL vs D/M) % by layer  =  paper Fig 4 C
            obj.lamGrouped(obj.a20{11}, M(1:2,:), {'MXH','MUL'}, ...
                {obj.C_MXH,obj.C_MLT}, nL, [0 90]);
            % a20{10}/a20{12} are the EXTRA composition views (3-category grouped + global
            % single bars) that are NOT part of paper Fig 4. Hide them in paper mode so the
            % tab reads as a clean Fig 4 (A/B boxes + C); show them in Original style.
            if viz.paperStyle()
                for kk = [10 12], cla(obj.a20{kk}); set(obj.a20{kk}, 'Visible','off'); end
            else
                set(obj.a20{10}, 'Visible','on'); set(obj.a20{12}, 'Visible','on');
                obj.lamGrouped(obj.a20{10}, merged, {'MXH','MUL','UCT'}, ...     % 3-cat % by layer
                    {obj.C_MXH,obj.C_MLT,obj.C_UCT}, nL, [0 80]);
                obj.lamGlobalSum(obj.a20{12}, merged, {'MXH','MUL','UCT'}, ...   % global single bars
                    {obj.C_MXH,obj.C_MLT,obj.C_UCT}, [0 65]);
            end

            tot = sum(merged, 2);
            obj.infoLabel.Text = sprintf(['group %s   neurons=%d   MXH/MUL/UCT=%d/%d/%d\n' ...
                'Per-unique-neuron composition (old UU_A_M_34); MXH-MUL folded into UCT. ' ...
                'ORI_NON_PV + 4 layers reproduces the old f2. Independent of repeated-obs.'], ...
                obj.groupDD.Value, sum(tot), tot(1), tot(2), tot(3));
        end

        function clearAll(obj)
            for k = 1:numel(obj.a20)
                if ~isempty(obj.a20{k}) && isgraphics(obj.a20{k}), cla(obj.a20{k}); end
            end
        end

        % ---- a20{10}/a20{11} : grouped laminar composition ------------- %
        function lamGrouped(obj, ax, M, cats, colors, nL, ylimv)
            paper = viz.paperStyle();
            pp2 = paper && numel(colors) == 2;      % paper Fig 4C  = 2-category NL/D-M panel
            pp4 = paper && numel(colors) == 4;      % paper Fig S5C = 4-category NL/D-M/Mix/Uct panel
            pp  = pp2 || pp4;
            if pp2                                  % NL yellow / D/M gray bars, opaque, clean
                cats = {'NL','D/M'}; colors = {[232 229 0]/255, [.366 .366 .366]}; ylimv = [0 80];
            elseif pp4                              % NL yellow / D/M gray / Mix white / Uct red
                cats = {'NL','D/M','Mix','Uct'}; ylimv = [0 80];
                colors = {[232 229 0]/255, [.366 .366 .366], [1 1 1], [1 0 0]};
            end
            colsum = sum(M,1); colsum(colsum==0) = NaN;
            P = 100 * M ./ colsum;                 % nCat x nL, % within layer
            data = P';                             % nL x nCat
            hold(ax,'on');
            h = bar(ax, data, 'grouped');
            for m = 1:numel(h)
                h(m).FaceColor = colors{m}; h(m).FaceAlpha = 0.3 + 0.7*pp;   % opaque in paper mode
                if pp4, h(m).EdgeColor = [0 0 0]; h(m).LineWidth = 0.5; end  % edge so the white Mix bar is visible
            end
            set(ax, 'XTick', 1:nL, 'XTickLabel', obj.LAYER_LAB(1:nL));
            ylim(ax, ylimv);
            if pp2
                ylabel(ax, '% of layer count');
                text(ax, 1.00, 1.00, cats{1}, 'Units','normalized', 'Color',colors{1}, 'FontWeight','bold', 'FontSize',obj.FONT+1, 'VerticalAlignment','top', 'HorizontalAlignment','right');
                text(ax, 1.00, 0.83, cats{2}, 'Units','normalized', 'Color',colors{2}, 'FontWeight','bold', 'FontSize',obj.FONT+1, 'VerticalAlignment','top', 'HorizontalAlignment','right');
            elseif pp4
                ylabel(ax, '% of layer count');
                try, legend(ax, h, cats, 'Box','off', 'Location','northeast'); catch, end %#ok<CTCH>
            else
                title(ax,'Laminar distribution'); ylabel(ax,'Unit Count %');
                try, legend(ax, cats); catch, end %#ok<CTCH>     % old: default box-on, 11pt, auto-located
                ax.YLimMode = 'auto';              % read fresh auto range (old ran once on fresh axes)
            end
            for k = 1:nL                            % N/n labels
                if pp, yText = 0.90*ylimv(2); fmt = 'n=%d'; fw = 'normal'; fs = obj.FONT+1;
                else,  yMax = max(data(k,:)); yText = yMax + 0.05*range(ax.YLim); fmt = 'N = %d'; fw = 'bold'; fs = obj.FONT; end
                text(ax, k, yText, sprintf(fmt, sum(M(:,k))), 'HorizontalAlignment','center', ...
                    'VerticalAlignment','bottom', 'FontSize',fs, 'FontWeight',fw);
            end
            if ~pp, grid(ax,'on'); end
            hold(ax,'off');
        end

        % ---- a20{12} : global composition (single bars) ---------------- %
        function lamGlobalSum(obj, ax, M, cats, colors, ylimv)
            tot = sum(M,2); pct = 100 * tot / max(sum(tot), eps);
            hold(ax,'on');
            hb = gobjects(1,numel(cats));
            for m = 1:numel(cats)
                hb(m) = bar(ax, m, pct(m), 'FaceColor', colors{m}, 'FaceAlpha', 0.3, 'BarWidth', 0.5);
            end
            xl = arrayfun(@(z) sprintf('%d',z), 1:numel(cats), 'UniformOutput', false);
            set(ax,'XTick',1:numel(cats),'XTickLabel',xl);
            title(ax,'Laminar distribution'); ylabel(ax,'Unit Count %'); ylim(ax, ylimv);
            try, legend(ax, hb, cats); catch, end %#ok<CTCH>     % old: default box-on, 11pt, auto-located
            for k = 1:numel(cats)                   % old sets YLim before this loop -> range is manual
                yText = pct(k) + 0.05*range(ax.YLim);
                text(ax, k, yText, sprintf('N = %d', tot(k)), 'HorizontalAlignment','center', ...
                    'VerticalAlignment','bottom', 'FontSize',obj.FONT, 'FontWeight','bold');
            end
            grid(ax,'on'); hold(ax,'off');
        end

        % ---- old UU_A_M_34 : per-neuron MXH/MUL/MXH-MUL/UCT by layer ---- %
        function M = lamComposition(~, UU, G, LGn, pop, nL)
            %LAMCOMPOSITION  M = 4 x nL, rows [MXH; MUL; MXH-MUL; UCT]. Per unique
            %   U_unity neuron: mxh=#obs(G==2), mlt=#obs(G==1); both-zero=UCT,
            %   tie(>0)=MXH-MUL, else dominant class; placed in mode(layer).
            M = zeros(4, nL);
            if isempty(pop), return; end
            uu = UU(pop);
            [u,~,gi] = unique(uu(:), 'stable');
            for j = 1:numel(u)
                obsIdx = pop(gi==j);
                mxh = sum(G(obsIdx)==2); mlt = sum(G(obsIdx)==1);
                Lvals = LGn(obsIdx); Lvals = Lvals(isfinite(Lvals));
                if isempty(Lvals), continue; end
                domL = mode(Lvals);
                if domL < 1 || domL > nL, continue; end
                if      mxh==0 && mlt==0, r = 4;        % UCT
                elseif  mxh==mlt,         r = 3;        % MXH-MUL (tie, both > 0)
                elseif  mxh> mlt,         r = 1;        % MXH
                else,                     r = 2;        % MUL
                end
                M(r,domL) = M(r,domL) + 1;
            end
        end

        % ---- OSI/CV/HBW box plot over MXH/Mlt/UCT (paper Fig 4 A/B) ---- %
        function classBox(obj, ax, vals, reps, G, ttl, ylab, ylimv, UU, PK, mode)
            % Observation-level group values (+ aligned U_unity ids + D rows). The
            % star below is an LME on these observations under Mixed-effects, a
            % rank-sum of the displayed per-neuron means under Mean/neuron, and the
            % classic rank-sum otherwise. `reps` is ALL observations for the
            % per-neuron modes (collapsed below), representatives otherwise.
            rMXH = reps(G(reps)==2); gMXH = vals(rMXH); okMXH = isfinite(gMXH); gMXH = gMXH(okMXH); rMXHf = rMXH(okMXH);
            rMlt = reps(G(reps)==1); gMlt = vals(rMlt); okMlt = isfinite(gMlt); gMlt = gMlt(okMlt); rMltf = rMlt(okMlt);
            rUCT = reps(G(reps)==3); gUCT = vals(rUCT); okUCT = isfinite(gUCT); gUCT = gUCT(okUCT); rUCTf = rUCT(okUCT);
            nMXH = UU(rMXH); nMXH = nMXH(okMXH);          % U_unity aligned with gMXH (same rows+filter)
            nMlt = UU(rMlt); nMlt = nMlt(okMlt);          % U_unity aligned with gMlt
            nUCT = UU(rUCT); nUCT = nUCT(okUCT);          % U_unity aligned with gUCT
            % DISPLAY data: under Mean/neuron AND Mixed-effects, collapse each gain
            % class to ONE per-neuron mean (each neuron once within its class) so
            % the dots/boxes match the reported statistic; other modes plot the
            % observations unchanged. The ORIGINAL observation rows (rMXHf/rMltf)
            % are kept for the LME star below. See STATS_MIXED_EFFECTS.md 3e.
            rMXHd = rMXHf; rMltd = rMltf; rUCTd = rUCTf;
            if any(strcmp(mode, {'mean','lme'}))
                [gMXHd, ~, rMXHd] = viz.plots.V01util.aggNeuronScalar(gMXH, nMXH, rMXHf);
                [gMltd, ~, rMltd] = viz.plots.V01util.aggNeuronScalar(gMlt, nMlt, rMltf);
                [gUCTd, ~, rUCTd] = viz.plots.V01util.aggNeuronScalar(gUCT, nUCT, rUCTf);
            else
                gMXHd = gMXH; gMltd = gMlt; gUCTd = gUCT;
            end
            if viz.paperStyle()                            % paper Fig 4: NL(MXH) vs D/M(Mlt) only, yellow / gray (PDF-measured)
                data = {gMXHd(:), gMltd(:)};
                repByGrp = {rMXHd(:), rMltd(:)};
                colors = {[184 182 0]/255, [.366 .366 .366]};   % NL olive-yellow, D/M gray
                glab = {'NL','D/M'};
            else
                data = {gMXHd(:), gMltd(:), gUCTd(:)};
                repByGrp = {rMXHd(:), rMltd(:), rUCTd(:)};    % D row index per plotted dot (per group)
                colors = {obj.C_MXH, obj.C_MLT, obj.C_UCT};
                glab = {'MXH','Multiplicative ','ucl'};
            end
            nG = numel(data);
            vals2 = []; grp = {};
            for i = 1:nG
                d = data{i}; if isempty(d), d = 0; end
                vals2 = [vals2; d]; grp = [grp; repmat(glab(i), numel(d), 1)]; %#ok<AGROW>
            end
            hold(ax,'on');
            try
                hbp = boxplot(ax, vals2, grp, 'Colors','k', 'Symbol','', ...
                    'GroupOrder', glab, 'Positions', 1:nG, 'Widths', 0.5);
                set(hbp, 'PickableParts','none');               % box lines must not swallow clicks on interior dots
                h = findobj(ax, 'Tag', 'Box');
                for j = 1:numel(h)
                    patch(ax, get(h(j),'XData'), get(h(j),'YData'), colors{numel(h)-j+1}, 'FaceAlpha', .05, 'PickableParts','none');
                end
                if viz.paperStyle(), set(findobj(ax,'Tag','Median'), 'Color',[1 0 0], 'LineWidth',1); end   % paper: red median
            catch
            end
            edg = {}; dsz = obj.SZ/2;
            if viz.paperStyle()
                edg = {'MarkerEdgeColor','w', 'LineWidth',0.75};      % paper: visible white ring per dot
                dsz = viz.plots.V01util.paperDotAreaBox(ax, nG);     % paper: dot dia = ~6% of group-column width
            end
            jitX = cell(1,nG);
            for i = 1:nG
                d = data{i};
                if isempty(d), d = 0; end          % old Box_plot_02: empty group -> stray point at y=0
                d = d(:);
                jx = viz.plots.V01util.boxJitterX(i, numel(d), 0.15);   % known jittered x
                jitX{i} = jx;
                scatter(ax, jx, d, dsz, colors{i}, 'filled', edg{:}, 'PickableParts','none');
            end
            % box-plot dots clickable -> unit inspector (x = jittered group position)
            bx = []; by = []; brep = [];
            for i = 1:nG
                d = data{i}(:); r = repByGrp{i}(:); jx = jitX{i}(:);
                if isempty(d), continue; end
                m = min([numel(d) numel(r) numel(jx)]);
                bx = [bx; jx(1:m)]; by = [by; d(1:m)]; brep = [brep; r(1:m)]; %#ok<AGROW>
            end
            obj.enableDotPick(ax, bx, by, brep);
            viz.plots.V01util.medianOnTop(ax);          % red median line ABOVE the dots
            ylabel(ax, ylab); xlim(ax, [0.5 nG+0.5]);
            line(ax, xlim(ax), [0 0], 'Color',[0 0 0 .3], 'LineStyle','--', 'PickableParts','none');
            if viz.paperStyle()                            % paper: colored NL/D-M x labels, keep metric ylabel, drop title
                set(ax, 'XTick', 1:nG, 'XTickLabel', repmat({''},1,nG));
                for i = 1:nG
                    text(ax, (i-0.5)/nG, -0.04, glab{i}, 'Units','normalized', 'Color', colors{i}, ...
                        'HorizontalAlignment','center', 'VerticalAlignment','top', 'FontWeight','bold', 'Clipping','off');
                end
                title(ax, '');
            else
                title(ax, ttl);
            end
            ylim(ax, ylimv);
            % MXH-vs-Mlt star: LME on the observations under Mixed-effects (same
            % model as the stats report), rank-sum of the displayed per-neuron
            % means under Mean/neuron, classic rank-sum otherwise.
            if strcmp(mode, 'lme')
                [p, isRed] = viz.plots.V01util.smBetweenMM(gMXH, gMlt, nMXH, nMlt, PK(rMXHf), PK(rMltf));
            elseif strcmp(mode, 'mean')
                [p, isRed] = viz.plots.V01util.smBetween(gMXHd, gMltd, [], [], mode);
            else
                [p, isRed] = viz.plots.V01util.smBetween(gMXH, gMlt, nMXH, nMlt, mode);
            end
            yMax = max(ylim(ax));
            brLS = '-.'; if viz.paperStyle(), brLS = '-'; end   % paper: solid significance bracket
            line(ax, [1 2], [yMax yMax]-.04*yMax, 'Color','k', 'LineStyle',brLS);
            viz.plots.V01util.drawSig(ax, 1.5, yMax-.04*yMax+.01*yMax, p, isRed, 'center');
            hold(ax,'off');
        end
    end
end
