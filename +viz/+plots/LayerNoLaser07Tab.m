classdef LayerNoLaser07Tab < viz.PlotTab
%LAYERNOLASER07TAB  Controls for Visualizer_01's F27_5_3 `f2` window (the
%   "Extended Fig 2 / Fig 7" no-laser-by-layer figure); the actual figure opens
%   in its OWN maximized uifigure, built with the literal old pixel positions,
%   fonts (11 pt) and colors so it is 1:1 with the old window.
%
%   This is the window F27_5_3.m builds (called from F2_5B_3.m under the
%   "%% Fig 7" comment) -- a SEPARATE uifigure from the f07 spread histograms
%   (see viz.plots.Stability07Tab). Reproduces:
%       * b1{1..3} : OSI / CV / HBW No-Laser box plots across cortical layers
%                    (SG/G/IG, pooled E+I), one-way ANOVA + Tukey-Kramer pairwise
%                    significance lines, layer colors colorsNL.
%       * T11..T13 : per-metric stats tables (UnitN, Mean, Std, Ste, p=Tukey).
%       * c2{1}    : No-Laser tuning by layer, self-peak normalized (fit_mid_self_NL).
%       * c2{2}    : No-Laser tuning by layer, absolute (fit_mid_NL).
%       * T1/T2/T3/T4 : floating labels (A-D, per-layer N, SG/G/IG, angle axis).
%
%   Layer metrics use the FITTED OSI/CV/HBW (fitOSI_NL/fitCV_NL/fitHBW_NL); the
%   old window read Unit.Si/Cv/HBW (measured CV in particular is not loaded into
%   D -- same data-layer note as LayerSelectivity02Tab/the Dashboard). Tuning
%   curves are peak-centered at 180 deg; the window 91:270 shows -90..90 deg.
%
%   CONTROLS: unit group (TuningG) + repeated-obs handling. The old window
%   applied no dedup and pooled all selected E+I units; choose group=ALL_UNITS +
%   repeated-obs=All to reproduce the old population.
%
%   See also: viz.plots.LayerSelectivity02Tab, viz.plots.V01util, analysis.tuningGroupMask

    properties
        groupDD; repDD; statusLbl; infoLabel
        PlotFig
        boxAx = {}        % 1x3 OSI/CV/HBW box plots
        tunAx = {}        % 1x2 normalized / absolute tuning
        tbl   = {}        % 1x3 stats tables (uitable handles)
        t2Text = {}       % 1x3 floating per-layer N-count text handles
        LayoutSpec = {}
        LastD = []; LastMask = []
    end

    properties (Constant)
        GROUPS = {'ALL_UNITS','NO_ORI_ON_PV','NO_ORI_NO_PV','ORI_ON_PV','ORI_NON_PV','ORI_NON_PV_MD','ORI_NON_PV_NL','ORI_NON_PV_U','OUTLIER'};
        REP_ITEMS = {'All (match old code)','First per neuron','Max laser power', ...
                     'Mean per neuron','Mixed-effects (stats)'};
        REP_DATA  = {'all','first','maxpow','mean','lme'};
        COLORS_NL = {[254 141 165]/255, [255 173 72]/255, [67 183 194]/255};  % SG / G / IG
        ERRTH   = [0.001 0.01 0.05];
        LAYERS  = [1 2 3];
        GROUP_LAB = {'Layer SG','Layer G','Layer IG'};
        LAYER_LAB = {'SG','G','IG'};
        MET     = {'OSI','CV','HBW'};
        MET_NL  = {'fitOSI_NL','fitCV_NL','fitHBW_NL'};
        MET_YLIM = {[0 1.1], [0 1.1], [0 70]};
        FONT = 11; LW = 1; SZ = 16.5;
    end

    methods
        function obj = LayerNoLaser07Tab()
            obj@viz.PlotTab('No-laser layers (V07b)');
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
            obj.addInspectCheckbox(g);     % + "Track unit on click" (box dots are clickable)
            obj.addDataSelectors(g);
        end

        function buildView(obj, parent)
            gg = obj.buildReportInstr(parent);
            uilabel(gg, 'Text', sprintf(['The "no-laser by layer" window ' ...
                'opens in its own maximized window (1:1 with the old figure).\n\nUse the controls on ' ...
                'the left (and the toolbar Filters) \x2014 the window refreshes live.']), ...
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
            hdr = sprintf(['Visualizer-01 no-laser by layer (F27) \x2014 group %s.  ANOVA + Tukey-Kramer ' ...
                'across SG/G/IG for no-laser OSI/CV/HBW + baseline firing.'], obj.groupDD.Value);
            rs = struct('figKey','F27', 'state',state, 'D',obj.LastD, 'header',hdr);
        end

        function openFigure(obj)
            if ~isempty(obj.PlotFig) && isvalid(obj.PlotFig)
                figure(obj.PlotFig); obj.drawFigure(); obj.refreshStatus(); return;
            end
            ss = get(0,'screensize'); Mx = ss(3); My = ss(4);
            obj.PlotFig = uifigure('Name','No-laser OSI / CV / HBW by layer', 'Color','w', ...
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

        function c = layerCol(obj, i)
            %LAYERCOL  Cortical-layer colour, matching the control colours of the
            %   Layer-selectivity (V02) tab: paper style = saturated SG magenta / G
            %   orange / IG cyan; original style = the muted COLORS_NL.
            if viz.paperStyle()
                p = {[1 0 1], [1 0.5 0], [0 1 1]}; c = p{min(max(i,1),3)};
            else
                c = obj.COLORS_NL{i};
            end
        end

        function createPanels(obj)
            obj.boxAx = {obj.addAx(.02,.50,.30,.40), ...   % b1{1} OSI
                         obj.addAx(.40,.50,.30,.40), ...   % b1{2} CV
                         obj.addAx(.40,.05,.30,.40)};      % b1{3} HBW
            obj.tunAx = {obj.addAx(.02,.22,.15,.19), ...   % c2{1} normalized tuning
                         obj.addAx(.20,.22,.15,.19)};      % c2{2} absolute tuning
            obj.tbl = {obj.addTablePanel(.73,.70,.25,.15), ... % T11 OSI
                       obj.addTablePanel(.73,.50,.25,.15), ... % T12 CV
                       obj.addTablePanel(.73,.30,.25,.15)};    % T13 HBW
            obj.createLabels();
        end

        function ax = addAx(obj, fx, fy, fw, fh)
            ax = uiaxes(obj.PlotFig); ax.Units = 'pixels'; ax.FontUnits = 'points';
            ax.FontSize = obj.FONT; ax.LineWidth = obj.LW; ax.XTickLabelRotation = 0;
            obj.LayoutSpec{end+1} = {ax, [fx fy fw fh]};
        end

        function tb = addTablePanel(obj, fx, fy, fw, fh)
            % uitable cannot take Units='normalized'; wrap it in a pixel-positioned
            % uipanel + uigridlayout (registered in LayoutSpec like the axes).
            p = uipanel(obj.PlotFig, 'BorderType','none'); p.Units = 'pixels';
            gl = uigridlayout(p, [1 1]); gl.Padding = [0 0 0 0];
            tb = uitable(gl); tb.FontSize = 8;
            obj.LayoutSpec{end+1} = {p, [fx fy fw fh]};
        end

        function h = addLabel(obj, fx, fy, fw, fh, txt, rot, col, fsz)
            if nargin < 8 || isempty(col), col = 'k'; end
            if nargin < 9 || isempty(fsz), fsz = obj.FONT; end
            ax = uiaxes(obj.PlotFig); ax.Units = 'pixels'; ax.Visible = 'off';
            h = text(ax, 0, 0, txt, 'Color', col, 'Rotation', rot, ...
                'FontUnits','points', 'FontSize', fsz);
            obj.LayoutSpec{end+1} = {ax, [fx fy fw fh]};
        end

        function createLabels(obj)
            % T1 panel letters A-D (2x font)
            locs = {[0 .9 .1 .1], [.39 .9 .1 .1], [0 .45 .1 .1], [.39 .45 .1 .1]};
            abcs = {'A','B','C','D'};
            for i = 1:4, obj.addLabel(locs{i}(1),locs{i}(2),locs{i}(3),locs{i}(4), abcs{i}, 0, 'k', obj.FONT*2); end
            % T2 per-layer N counts (text updated each draw)
            obj.t2Text = cell(1,3);
            for i = 1:3
                obj.t2Text{i} = obj.addLabel((.36+i*.09), .35, .05, .05, 'N = ', 0);
            end
            % T3 SG / G / IG in layer colors
            for i = 1:3
                obj.addLabel(.315, (.38-0.03*i), .05, .05, obj.LAYER_LAB{i}, 0, obj.layerCol(i));
            end
            % T4 angle-from-peak axis label (bold)
            h = obj.addLabel(.15, .17, .20, .05, ['Angle from peak ( ' char(176) ' )'], 0);
            try, h.FontWeight = 'bold'; catch, end
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
            if ~isfield(D,'fitOSI_NL') || ~isfield(D,'fit_mid_NL')
                title(obj.boxAx{1}, 'Missing fitOSI_NL / fit_mid_NL'); return;
            end
            try, grpMask = analysis.tuningGroupMask(D, obj.groupDD.Value);
            catch err, title(obj.boxAx{1}, ['Group error: ' err.message]); return; end

            LGn = viz.plots.V01util.layerNum(D);
            sel = mask(:) & grpMask(:);                 % pool E+I (old Allselected = [I_ext I_inh])
            % Per-neuron modes ('first'/'maxpow'/'mean') assign each neuron to ONE
            % layer = the mode of its selected-obs layers (as in Visualizer_03 /
            % GainLaminar03 lamComposition), so a neuron spanning two layers is
            % counted once in its dominant layer -- not once per layer. 'all'/'lme'
            % stay observation-level (old F27_5_3 applied no dedup).
            repByLayer = viz.plots.V01util.layerReps(D, find(sel), LGn, obj.repDD.Value, obj.LAYERS);
            if strcmp(obj.repDD.Value, 'mean')
                % 'Mean per neuron': keep the dominant-layer assignment but hand the
                % boxes ALL of each neuron's rows IN that layer -- layerReps' 'mean'
                % representative is the FIRST row, so values there would be firsts.
                UUv = viz.plots.V01util.colv(D, 'U_unity');
                for li = 1:numel(repByLayer)
                    rows = find(sel & LGn(:) == obj.LAYERS(li) & ismember(UUv, UUv(repByLayer{li})));
                    repByLayer{li} = rows(:);
                end
            end

            % ---- box plots + ANOVA/Tukey + stats tables --------------------
            for mi = 1:3
                obj.drawMetricBox(obj.boxAx{mi}, obj.tbl{mi}, obj.MET_NL{mi}, ...
                    obj.MET{mi}, obj.MET_YLIM{mi}, repByLayer, mi);
            end

            % ---- no-laser tuning by layer ----------------------------------
            % Population tuning curves honor the stat option like the stats/box path:
            % 'mean' and 'lme' need EVERY observation per neuron (layerReps collapses
            % 'mean' to first-obs, so re-derive all-obs rows) and drawLayerTun then
            % averages each neuron's curves (per-neuron mean) before the population
            % mean/SEM. 'first'/'maxpow'/'all' reuse repByLayer as-is.
            if any(strcmp(obj.repDD.Value, {'mean','lme'}))
                tunRep = viz.plots.V01util.layerReps(D, find(sel), LGn, 'all', obj.LAYERS);
            else
                tunRep = repByLayer;
            end
            obj.drawLayerTun(obj.tunAx{1}, 'fit_mid_self_NL', tunRep, 'Normalized firing rate');
            obj.drawLayerTun(obj.tunAx{2}, 'fit_mid_NL',      tunRep, 'Absolut firing rate (sp/s)');

            obj.infoLabel.Text = sprintf(['group %s   layer N (SG/G/IG): %d/%d/%d   (pooled E+I)\n' ...
                'ALL_UNITS + All reproduces the old window. OSI/CV/HBW are FITTED values.'], ...
                obj.groupDD.Value, numel(repByLayer{1}), numel(repByLayer{2}), numel(repByLayer{3}));
        end

        function clearAll(obj)
            for k = 1:numel(obj.boxAx), if isvalid(obj.boxAx{k}), cla(obj.boxAx{k}); end, end
            for k = 1:numel(obj.tunAx), if isvalid(obj.tunAx{k}), cla(obj.tunAx{k}); end, end
        end

        % per-metric box plot: 3 layer boxes (No-Laser) + ANOVA/Tukey sig lines + table
        function drawMetricBox(obj, ax, tb, fieldNL, metName, yl, repByLayer, mi)
            v = viz.plots.V01util.colv(obj.LastD, fieldNL);
            if strcmpi(metName,'HBW')                        % drop not-aligned units (was fitHBW<0)
                badU = viz.plots.V01util.colv(obj.LastD, 'Align_bad') == 1;
                v(badU) = NaN;
            end
            mode = obj.repDD.Value;
            UU = viz.plots.V01util.colv(obj.LastD, 'U_unity');
            data = cell(1,3); neur = cell(1,3); rep = cell(1,3); n = zeros(1,3);
            for li = 1:3
                rows = repByLayer{li};
                d = v(rows); nu = UU(rows);
                ok = isfinite(d); d = d(ok); nu = nu(ok); rr = rows(ok);   % keep neur/rep aligned with d
                data{li} = d; neur{li} = nu; rep{li} = rr; n(li) = numel(d);
            end
            % Per-neuron modes: the box shows ONE dot per neuron (the mean of its
            % rows); rawData keeps the observations for the All-method red flag.
            rawData = data;
            if any(strcmp(mode, {'mean','lme'}))
                for li = 1:3
                    [data{li}, ~, rep{li}] = viz.plots.V01util.aggNeuronScalar(data{li}, neur{li}, rep{li});
                    n(li) = numel(data{li});
                end
            end
            boxColors = {obj.layerCol(1), obj.layerCol(2), obj.layerCol(3)};   % match V02 control colours
            jitX = viz.plots.V01util.drawBox(ax, obj.GROUP_LAB, data, boxColors, metName, ['No-Laser ' metName], obj.SZ/2);
            % box-plot dots clickable -> unit inspector (x = jittered layer position)
            bx = []; by = []; brep = [];
            for li = 1:3
                d = data{li}(:); r = rep{li}(:); jx = jitX{li}(:);
                if isempty(d), continue; end
                m = min([numel(d) numel(r) numel(jx)]);
                bx = [bx; jx(1:m)]; by = [by; d(1:m)]; brep = [brep; r(1:m)]; %#ok<AGROW>
            end
            obj.enableDotPick(ax, bx, by, brep);
            if ~isempty(yl), ylim(ax, yl); end

            % one-way ANOVA across layers + Tukey-Kramer pairwise p. Under the
            % per-neuron modes ('mean'/'lme') `data` is already one value per
            % neuron, so the drawn/tabled p matches the displayed dots; the red
            % flag compares against the un-aggregated (All-method) p. The report's
            % Mixed-effects column additionally fits the full LME.
            PAsi = obj.tukeyPairs(data);                  % p drawn / tabled (per-neuron under mean/lme)
            PAll = obj.tukeyPairs(rawData);               % un-aggregated All-method p for the red flag
            isRed = false(1,3);
            if strcmp(mode,'lme')
                for i = 1:3
                    isRed(i) = ~strcmp(viz.plots.V01util.sigStars(PAsi(i)), ...
                                       viz.plots.V01util.sigStars(PAll(i)));
                end
            end

            % significance lines (gcs pairs) + stars (RED when lme sig differs from All)
            gcs = {[1 2],[1 3],[2 3]};
            hold(ax,'on'); yMax = max(ylim(ax));
            for i = 1:3
                yy = yMax - .04*i*yMax;
                line(ax, gcs{i}, [yy yy], 'Color','k', 'LineStyle','-.');
                viz.plots.V01util.drawSig(ax, mean(gcs{i}), yy + .01*yMax, PAsi(i), isRed(i), 'center');
            end
            hold(ax,'off');

            % per-layer N counts floating label (only the OSI metric drives T2, like old)
            if mi == 1
                for li = 1:3
                    if isvalid(obj.t2Text{li}), obj.t2Text{li}.String = sprintf('N = %d', n(li)); end
                end
            end

            % stats table: UnitN, Mean, Std, Ste, p (Tukey pairwise p per group, old behavior)
            UnitN = n(:); Mean = nan(3,1); Std = nan(3,1); Ste = nan(3,1);
            for li = 1:3
                d = data{li};
                if ~isempty(d)
                    Mean(li) = round(mean(d),3); Std(li) = round(std(d),3);
                    Ste(li)  = round(std(d)/sqrt(numel(d)),3);
                end
            end
            p = round(PAsi(:),4);
            T = table(UnitN, Mean, Std, Ste, p);
            try, tb.Data = T; catch, end
        end

        % anova1 + Tukey-Kramer pairwise p for 3 layer groups; rows align with
        % gcs = {[1 2],[1 3],[2 3]} (multcompare's natural pair order for 3 groups).
        function PAsi = tukeyPairs(~, data)
            PAsi = [NaN NaN NaN];
            try
                ANdata = []; grp = {};
                for li = 1:3
                    d = data{li}(:);
                    ANdata = [ANdata; d]; %#ok<AGROW>
                    grp = [grp; repmat({sprintf('G%d',li)}, numel(d), 1)]; %#ok<AGROW>
                end
                [pA,~,stats] = anova1(ANdata, grp, 'off'); %#ok<ASGLU>
                c = multcompare(stats, 'CType','tukey-kramer', 'Display','off');
                PAsi = c(:,end);
            catch
            end
        end

        function s = anovaStar(obj, p)
            if ~isfinite(p),            s = 'ns';
            elseif p < obj.ERRTH(1),    s = '***';
            elseif p < obj.ERRTH(2),    s = '**';
            elseif p < obj.ERRTH(3),    s = '*';
            else,                       s = 'ns';
            end
        end

        % No-Laser tuning by layer: mean +/- SE (std w=1) over the centered window
        function drawLayerTun(obj, ax, field, repByLayer, ylab)
            if ~isfield(obj.LastD, field), title(ax,'No Laser'); return; end
            win = (91:270)'; x = win - 180;             % -89..90 deg from peak
            aggPN = any(strcmp(obj.repDD.Value, {'mean','lme'}));   % collapse each neuron's curves to its mean first
            hold(ax,'on');
            for li = 3:-1:1                              % IG, G, SG (SG drawn last/on top, old order)
                rp = repByLayer{li};
                if isempty(rp), continue; end
                Mw = obj.LastD.(field)(win, rp);
                if aggPN                                 % per-neuron mean curves (matches the stats/box per-neuron reduction)
                    R  = viz.plots.V01util.reducer(obj.LastD, rp, 'mean');
                    Mw = viz.plots.V01util.redCols(R, Mw);
                end
                K = size(Mw, 2);
                Y  = mean(Mw, 2, 'omitnan');
                SE = std(Mw, 1, 2, 'omitnan') / sqrt(K);
                col = obj.layerCol(li);
                viz.plots.V01util.plotSE(ax, x, Y, SE, col, col, 0.4);
            end
            xlim(ax, [-90 90]); xticks(ax, [-90 0 90]);
            title(ax, 'No Laser'); ylabel(ax, ylab);
            hold(ax,'off');
        end
    end
end
