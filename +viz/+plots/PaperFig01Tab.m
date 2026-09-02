classdef PaperFig01Tab < viz.PlotTab
%PAPERFIG01TAB  Paper Figure 1 builder (live).
%   1) BOXES: add/remove/edit/select square windows on this tab (centre + size,
%      drawn as non-limiting guide rectangles). Starts arranged like paper Fig 1.
%   2) SELECT: pick a source tab (its figure open), "Select from source", and DRAG
%      a box over anything visible in it (axes, curves, titles, labels). "Replot
%      into box" clones the selection EXACTLY, centred on the box (may overflow).
%   3) LIVE: an unfrozen box RE-PLOTS whenever the source updates (on refresh); a
%      frozen box is locked.
%   4) LABEL: type text, "Add to box" writes it (TeX; size/colour/90-deg options)
%      at the selected box's centre; drag it anywhere. Labels ride with their box.
%   5) SAVE: the box layout + each box's source/selection recipe + its labels persist
%      with the app session (the filter Save), so reopening the app restores it all.
%
%   Clone = copyobj (vector, not a snapshot); a yyaxis panel (which copyobj can't
%   clone) is native-redrawn if the source tab recognises it (Dashboard.specForAxes).
%
%   See also: viz.PlotTab, viz.plots.Dashboard01Tab

    properties
        PlotFig
        GuideAx
        LabelAx                     % pickable overlay holding the user-written labels
        StatAx                      % pickable overlay holding the rendered stat tables
        Boxes = struct([])          % name,cx,cy,w,h,ratio,frozen,srcTab,srcRegion,labels,stats
        ShowGuides logical = true
        SelLabel = []               % [boxIdx labelIdx] of the currently selected label
        SelStat  = []               % [boxIdx statIdx] of the currently selected stat table
        DragInfo = []               % transient drag state
        % controls
        pageNameEd; boxCountEd; newPageBtn; dupPageBtn; remPageBtn      % page management
        openBtn; guideChk; refreshBtn; boxDD; edName; edCx; edCy; edW; edH; edRatio
        addBtn; dupBtn; remBtn; srcTabDD; selectBtn; polyBtn; replotBtn; clearBtn; freezeChk; statusLbl
        edLabelText; edLabelSize; ddLabelColor; chkLabelRot; addLabelBtn; remLabelBtn
        statSrcDD; addStatBtn; remStatBtn                              % stat-table controls
    end

    methods
        function obj = PaperFig01Tab(name, nBoxes)
            if nargin < 1 || isempty(name), name = 'Paper Fig 1'; end
            obj@viz.PlotTab(name);
            if nargin < 2 || isempty(nBoxes), nBoxes = 4; end
            obj.Boxes = obj.defaultBoxes(nBoxes);
        end

        function replotLive(obj)
            %REPLOTLIVE  Public hook: re-clone non-frozen boxes (called by the source
            %   app when its plots change, for live cross-app updates).
            if ~isempty(obj.PlotFig) && isvalid(obj.PlotFig), obj.replotAll(true, false); end
        end

        function buildControls(obj, parent)
            g = uigridlayout(parent, [1 1]); g.Padding = [6 6 6 6];
            sp = uipanel(g, 'BorderType','none'); sp.Scrollable = 'on';
            gg = uigridlayout(sp, [40 1]);
            gg.RowHeight = repmat({'fit'}, 1, 40); gg.RowHeight{40} = '1x';
            gg.RowSpacing = 3; gg.Padding = [2 2 2 2];
            % ---- Pages (add / duplicate / remove this paper page) --------------
            uilabel(gg, 'Text', [char(8212) ' Pages ' char(8212)], 'FontWeight','bold', 'Interpreter','none');
            ng = uigridlayout(gg, [1 4]); ng.Padding = [0 0 0 0]; ng.ColumnSpacing = 3;
            ng.ColumnWidth = {'fit','1x','fit','0.6x'};
            uilabel(ng, 'Text', 'name'); obj.pageNameEd = uieditfield(ng, 'text', 'Value', 'Figure');
            uilabel(ng, 'Text', 'boxes'); obj.boxCountEd = uieditfield(ng, 'numeric', 'Limits', [1 24], ...
                'Value', 4, 'RoundFractionalValues', 'on', 'ValueDisplayFormat', '%g');
            pgb = uigridlayout(gg, [1 3]); pgb.Padding = [0 0 0 0]; pgb.ColumnSpacing = 3;
            obj.newPageBtn = uibutton(pgb, 'Text', 'New page', ...
                'Tooltip', 'Add a new paper page with the name + box count above.', ...
                'ButtonPushedFcn', @(s,e) obj.onNewPage());
            obj.dupPageBtn = uibutton(pgb, 'Text', 'Duplicate', ...
                'Tooltip', 'New page reusing THIS page''s full box structure.', ...
                'ButtonPushedFcn', @(s,e) obj.onDupPage());
            obj.remPageBtn = uibutton(pgb, 'Text', 'Remove page', ...
                'Tooltip', 'Delete this paper page (at least one page is kept).', ...
                'ButtonPushedFcn', @(s,e) obj.onRemPage());
            uilabel(gg, 'Text', [char(8212) ' Figure ' char(8212)], 'FontWeight','bold', 'Interpreter','none');
            obj.openBtn    = uibutton(gg, 'Text', 'Open paper figure', 'ButtonPushedFcn', @(s,e) obj.openFigure());
            obj.refreshBtn = uibutton(gg, 'Text', 'Re-plot live boxes', ...
                'Tooltip', 'Re-clone every non-frozen box from its source (do this after the source changes).', ...
                'ButtonPushedFcn', @(s,e) obj.replotAll(true, false));
            obj.guideChk = uicheckbox(gg, 'Text', 'Show layout guides', 'Value', true, ...
                'ValueChangedFcn', @(s,e) obj.onGuideToggle());
            uilabel(gg, 'Text', [char(8212) ' Box & position ' char(8212)], 'FontWeight','bold', 'Interpreter','none');
            obj.boxDD  = uidropdown(gg, 'Items', obj.boxNames(), 'ValueChangedFcn', @(s,e) obj.onBoxSel());
            obj.edName = uieditfield(gg, 'text', 'ValueChangedFcn', @(s,e) obj.onName());
            pg = uigridlayout(gg, [2 4]); pg.Padding = [0 0 0 0]; pg.ColumnSpacing = 3; pg.RowSpacing = 2;
            pg.ColumnWidth = {'fit','1x','fit','1x'};
            uilabel(pg, 'Text', 'cx'); obj.edCx = obj.num(pg);
            uilabel(pg, 'Text', 'cy'); obj.edCy = obj.num(pg);
            uilabel(pg, 'Text', 'w');  obj.edW  = obj.num(pg);
            uilabel(pg, 'Text', 'h');  obj.edH  = obj.num(pg);
            rg = uigridlayout(gg, [1 2]); rg.Padding = [0 0 0 0]; rg.ColumnSpacing = 3;
            rg.ColumnWidth = {'fit','1x'};
            uilabel(rg, 'Text', 'plot size ratio (zoom)');
            obj.edRatio = uieditfield(rg, 'numeric', 'Limits', [0.1 2], 'Value', 1, ...
                'ValueDisplayFormat', '%.2f', ...
                'Tooltip', 'Scale (0.1-2) of the cloned source in this box, about the box centre, keeping all relative sizes.', ...
                'ValueChangedFcn', @(s,e) obj.onRatio());
            bg = uigridlayout(gg, [1 3]); bg.Padding = [0 0 0 0]; bg.ColumnSpacing = 3;
            obj.addBtn = uibutton(bg, 'Text', 'Add',       'ButtonPushedFcn', @(s,e) obj.addBox());
            obj.dupBtn = uibutton(bg, 'Text', 'Duplicate', 'ButtonPushedFcn', @(s,e) obj.dupBox());
            obj.remBtn = uibutton(bg, 'Text', 'Remove',    'ButtonPushedFcn', @(s,e) obj.removeBox());
            uilabel(gg, 'Text', [char(8212) ' Source & re-plot ' char(8212)], 'FontWeight','bold', 'Interpreter','none');
            uilabel(gg, 'Text', 'Source tab (open its figure first)');
            obj.srcTabDD = uidropdown(gg, 'Items', obj.srcTabNames());
            sg = uigridlayout(gg, [1 2]); sg.Padding = [0 0 0 0]; sg.ColumnSpacing = 3;
            obj.selectBtn = uibutton(sg, 'Text', 'Select: box', ...
                'Tooltip', 'Drag a rectangle over the source objects.', ...
                'ButtonPushedFcn', @(s,e) obj.onSelect('rect'));
            obj.polyBtn = uibutton(sg, 'Text', 'Select: polygon', ...
                'Tooltip', 'Click points to draw a free polygon; double-click to finish.', ...
                'ButtonPushedFcn', @(s,e) obj.onSelect('poly'));
            cg = uigridlayout(gg, [1 2]); cg.Padding = [0 0 0 0]; cg.ColumnSpacing = 3;
            obj.replotBtn = uibutton(cg, 'Text', 'Replot into box', 'ButtonPushedFcn', @(s,e) obj.onReplot());
            obj.clearBtn  = uibutton(cg, 'Text', 'Clear box', ...
                'Tooltip', 'Empty this box: remove its cloned plot and its stat table (labels are kept).', ...
                'ButtonPushedFcn', @(s,e) obj.onClear());
            obj.freezeChk = uicheckbox(gg, 'Text', 'Freeze this box (stop live update)', ...
                'ValueChangedFcn', @(s,e) obj.onFreeze());
            uilabel(gg, 'Text', [char(8212) ' Label / writing ' char(8212)], 'FontWeight','bold', 'Interpreter','none');
            obj.edLabelText = uieditfield(gg, 'text', 'Placeholder', 'label text (TeX, e.g. Response (%) \circ)', ...
                'Tooltip', 'Text to write into the selected box. TeX interpreter (\circ, \Delta, _sub, ^sup).');
            lg = uigridlayout(gg, [1 4]); lg.Padding = [0 0 0 0]; lg.ColumnSpacing = 3; lg.RowSpacing = 2;
            lg.ColumnWidth = {'fit','1x','fit','1.2x'};
            uilabel(lg, 'Text', 'size'); obj.edLabelSize = uieditfield(lg, 'numeric', 'Limits', [4 96], ...
                'Value', 11, 'ValueDisplayFormat', '%g', 'RoundFractionalValues', 'on');
            uilabel(lg, 'Text', 'colour');
            obj.ddLabelColor = uidropdown(lg, 'Items', {'black','red','green','blue','gray','cyan','magenta','orange'});
            obj.chkLabelRot = uicheckbox(gg, 'Text', ['Rotate 90' char(176) ' (vertical)']);
            lbg = uigridlayout(gg, [1 2]); lbg.Padding = [0 0 0 0]; lbg.ColumnSpacing = 3;
            obj.addLabelBtn = uibutton(lbg, 'Text', 'Add to box', ...
                'Tooltip', 'Place the text at the selected box''s centre, then drag it to position.', ...
                'ButtonPushedFcn', @(s,e) obj.onAddLabel());
            obj.remLabelBtn = uibutton(lbg, 'Text', 'Remove selected', ...
                'Tooltip', 'Remove the clicked label, or (if none is clicked) the last label of the box chosen in the Box dropdown.', ...
                'ButtonPushedFcn', @(s,e) obj.onRemoveLabel());
            uilabel(gg, 'Text', [char(8212) ' Stat table ' char(8212)], 'FontWeight','bold', 'Interpreter','none');
            uilabel(gg, 'Text', 'Source tab (its Stats report)');
            obj.statSrcDD = uidropdown(gg, 'Items', obj.srcTabNames());
            stg = uigridlayout(gg, [1 2]); stg.Padding = [0 0 0 0]; stg.ColumnSpacing = 3;
            obj.addStatBtn = uibutton(stg, 'Text', 'Add stat table', ...
                'Tooltip', 'Render the chosen tab''s Stats report as a table in the selected box (exports to PDF); drag to position.', ...
                'ButtonPushedFcn', @(s,e) obj.onAddStat());
            obj.remStatBtn = uibutton(stg, 'Text', 'Remove selected', ...
                'Tooltip', 'Remove the clicked stat table, or (if none is clicked) the stat table of the box chosen in the Box dropdown. (Clear box also removes it.)', ...
                'ButtonPushedFcn', @(s,e) obj.onRemoveStat());
            obj.statusLbl = uilabel(gg, 'Text', 'Figure not open.', 'WordWrap','on', 'VerticalAlignment','top');
            obj.syncFields();
        end

        function buildView(obj, parent)
            gg = uigridlayout(parent, [1 1]); gg.Padding = [20 20 20 20];
            uilabel(gg, 'Text', sprintf(['Paper Figure 1 builder.\n\nOpen the figure, arrange the boxes, then pick ' ...
                'a source tab (open its figure), press \x201CSelect from source\x201D and DRAG a box over anything ' ...
                'in it \x2014 \x201CReplot into box\x201D clones it, centred on the box. Non-frozen boxes re-plot when ' ...
                'the source changes; freeze to lock. The layout + selections are saved with the app session.']), ...
                'HorizontalAlignment', 'center', 'WordWrap', 'on', 'FontSize', 13);
        end

        function update(obj, ~, ~)
            if ~isempty(obj.srcTabDD)  && isvalid(obj.srcTabDD),  obj.setDDItems(obj.srcTabDD,  obj.srcTabNames()); end
            if ~isempty(obj.statSrcDD) && isvalid(obj.statSrcDD), obj.setDDItems(obj.statSrcDD, obj.srcTabNames()); end
            if ~isempty(obj.PlotFig) && isvalid(obj.PlotFig), obj.replotAll(true, false); end   % LIVE: non-frozen boxes track the source
        end

        function capture(obj, boxName, srcTabName, region)
            %CAPTURE  Scriptable Select+Replot: set box BOXNAME's recipe to REGION of tab
            %   SRCTABNAME and plot it. REGION is a rect [x y w h] OR an Nx2 polygon
            %   (figure-normalised). The source tab's figure must be open.
            if isempty(obj.PlotFig) || ~isvalid(obj.PlotFig), obj.openFigure(); end
            si = obj.boxIndex(boxName); if isempty(si), return; end
            if size(region,2) ~= 2, region = rectToPoly(region(:)'); end     % [x y w h] -> polygon
            obj.Boxes(si).srcTab = srcTabName; obj.Boxes(si).srcRegion = region;
            obj.replotBox(si, true); obj.drawGuides(); obj.refreshStatus();
        end

        function s = getControlState(obj)
            n = numel(obj.Boxes); c = cell(1, n);
            for i = 1:n
                b = obj.Boxes(i);
                labs = obj.emptyLabels(); if isfield(b,'labels'), labs = b.labels; end
                sts  = obj.emptyStats();  if isfield(b,'stats'),  sts  = b.stats;  end
                rt = 1; if isfield(b,'ratio') && ~isempty(b.ratio), rt = b.ratio; end
                ss = []; if isfield(b,'srcState'), ss = b.srcState; end   % freeze-time source-tab settings
                c{i} = struct('name',b.name, 'cx',b.cx, 'cy',b.cy, 'w',b.w, 'h',b.h, 'ratio',rt, ...
                              'frozen',b.frozen, 'srcTab',b.srcTab, 'srcRegion',b.srcRegion, 'srcState',{ss}, ...
                              'labels',{labs}, 'stats',{sts});   % cell-wrap so struct-arrays stay one field value
            end
            s = struct('boxes', {c}, 'showGuides', obj.ShowGuides);
        end
        function setControlState(obj, s)
            if isstruct(s) && isfield(s,'boxes') && ~isempty(s.boxes)
                bx = s.boxes; if ~iscell(bx), bx = num2cell(bx); end
                obj.Boxes = struct([]);
                for i = 1:numel(bx)
                    e = obj.mkBox(bx{i}.name, bx{i}.cx, bx{i}.cy, bx{i}.w, bx{i}.h);
                    if isfield(bx{i},'ratio') && ~isempty(bx{i}.ratio), e.ratio = bx{i}.ratio; end
                    if isfield(bx{i},'frozen'),    e.frozen  = bx{i}.frozen;  end
                    if isfield(bx{i},'srcTab'),    e.srcTab  = bx{i}.srcTab;  end
                    if isfield(bx{i},'srcRegion') && ~isempty(bx{i}.srcRegion), e.srcRegion = bx{i}.srcRegion;
                    elseif isfield(bx{i},'srcRect') && ~isempty(bx{i}.srcRect), e.srcRegion = rectToPoly(bx{i}.srcRect); end
                    if isfield(bx{i},'srcState'), e.srcState = bx{i}.srcState; end   % freeze-time source-tab settings
                    if isfield(bx{i},'labels') && ~isempty(bx{i}.labels), e.labels = obj.normLabels(bx{i}.labels); end
                    if isfield(bx{i},'stats')  && ~isempty(bx{i}.stats),  e.stats  = obj.normStats(bx{i}.stats);  end
                    obj.Boxes = obj.pushBox(obj.Boxes, e);
                end
                if ~isempty(obj.boxDD) && isvalid(obj.boxDD), obj.refreshBoxList(); end
            end
            if isstruct(s) && isfield(s,'showGuides') && ~isempty(obj.guideChk) && isvalid(obj.guideChk)
                obj.guideChk.Value = logical(s.showGuides); obj.ShowGuides = logical(s.showGuides);
            end
        end

        function closePopouts(obj)
            if ~isempty(obj.PlotFig) && isvalid(obj.PlotFig), try, delete(obj.PlotFig); catch, end, end %#ok<CTCH>
            obj.PlotFig = []; obj.GuideAx = []; obj.LabelAx = []; obj.StatAx = []; obj.DragInfo = [];
        end
    end

    methods   % PUBLIC: openFigure is exposed (like the other figure tabs) so the
              % toolbar's Save-PDF (exportTarget) + the paper controller can open it.
        % ---- the paper figure ------------------------------------------- %
        function openFigure(obj)
            if ~isempty(obj.PlotFig) && isvalid(obj.PlotFig)
                figure(obj.PlotFig); obj.drawGuides(); obj.drawStatTables(); obj.drawLabels(); obj.refreshStatus(); return;
            end
            ss = get(0, 'screensize');
            pos = [0, round(.03*ss(4)), ss(3), round(.95*ss(4))];   % same size as the other tabs' figures
            obj.PlotFig = uifigure('Name', ['Paper figure - ' obj.Name], 'Color', 'w', 'Position', pos);
            obj.PlotFig.CloseRequestFcn = @(s,e) delete(s);
            obj.drawGuides();
            obj.replotAll(false, true);                             % reconstruct the saved figure (open sources if needed)
            obj.drawStatTables();                                   % render the saved stat tables
            obj.drawLabels();                                       % render the saved labels on top
            obj.refreshStatus();
        end
    end

    % =================================================================== %
    methods (Access = private)
        function ed = num(obj, parent)
            ed = uieditfield(parent, 'numeric', 'Limits', [0 1], 'ValueDisplayFormat', '%.3f', ...
                'ValueChangedFcn', @(s,e) obj.onField());
        end

        % ---- guide overlay ---------------------------------------------- %
        function drawGuides(obj)
            if isempty(obj.PlotFig) || ~isvalid(obj.PlotFig), return; end
            if ~isempty(obj.GuideAx) && isvalid(obj.GuideAx), delete(obj.GuideAx); end
            if ~obj.ShowGuides, return; end
            ax = uiaxes(obj.PlotFig, 'Units','normalized', 'Position',[0 0 1 1], 'Tag','paperGuide', ...
                'Color','none', 'XColor','none', 'YColor','none', 'HitTest','off', 'PickableParts','none');
            ax.XLim = [0 1]; ax.YLim = [0 1]; ax.XTick = []; ax.YTick = [];
            try, ax.Toolbar = []; disableDefaultInteractivity(ax); catch, end %#ok<CTCH>
            hold(ax, 'on');
            sel = obj.boxIndex(obj.boxDD.Value);
            for k = 1:numel(obj.Boxes)
                r = obj.boxRect(k); b = obj.Boxes(k);
                ec = [.35 .55 1]; lw = 0.75;
                if b.frozen, ec = [0 .6 0]; lw = 1.25; end
                if k == sel, ec = [.9 0 0]; lw = 1.75; end
                nm = b.name; if b.frozen, nm = ['[locked] ' nm]; end
                rectangle(ax, 'Position', r, 'EdgeColor', ec, 'LineWidth', lw, 'FaceColor', 'none');
                plot(ax, b.cx, b.cy, '+', 'Color', ec, 'MarkerSize', 9, 'LineWidth', lw);
                text(ax, r(1)+0.002, r(2)+r(4)-0.002, nm, 'FontSize', 7, 'Color', ec, ...
                    'VerticalAlignment', 'top', 'Interpreter', 'none', 'Clipping', 'on');
            end
            hold(ax, 'off');
            obj.GuideAx = ax;
        end
        function onGuideToggle(obj)
            obj.ShowGuides = obj.guideChk.Value; obj.drawGuides();
        end

        % ---- select a source region (mouse drag) ------------------------ %
        function onSelect(obj, mode)
            if nargin < 2, mode = 'rect'; end
            if isempty(obj.PlotFig) || ~isvalid(obj.PlotFig), obj.openFigure(); end
            si = obj.boxIndex(obj.boxDD.Value); if isempty(si), return; end
            if obj.Boxes(si).frozen, obj.setStatus('Box frozen - unfreeze to select.'); return; end
            t = obj.srcTabByName(obj.srcTabDD.Value);
            if isempty(t) || ~isprop(t,'PlotFig') || isempty(t.PlotFig) || ~isvalid(t.PlotFig)
                obj.setStatus('Open the source tab''s figure first, then Select.'); return;
            end
            if strcmp(mode,'poly'), obj.setStatus('Click points; double-click to close the polygon...');
            else,                   obj.setStatus('Drag a box over the objects...'); end
            drawnow;
            poly = obj.grabRegion(t.PlotFig, mode);
            if isempty(poly), obj.setStatus('Selection cancelled.'); return; end
            obj.Boxes(si).srcTab = t.Name; obj.Boxes(si).srcRegion = poly;   % remember the recipe
            obj.replotBox(si, false);                                        % show it now
            obj.refreshStatus();
            obj.setStatus(sprintf('Selected region of %s into \x201C%s\x201D.', t.Name, obj.Boxes(si).name));
        end
        function poly = grabRegion(~, srcFig, mode)
            %GRABREGION  Let the user draw a rectangle or a free POLYGON over the source
            %   figure; returns the region as Nx2 normalised vertices ([] if cancelled).
            poly = [];
            ov = uiaxes(srcFig, 'Units','normalized', 'Color','none', 'XColor','none', 'YColor','none');
            try, ov.InnerPosition = [0 0 1 1]; catch, ov.Position = [0 0 1 1]; end %#ok<CTCH>
            ov.XLim = [0 1]; ov.YLim = [0 1]; try, ov.Toolbar = []; catch, end %#ok<CTCH>
            try
                if strcmp(mode,'poly'), roi = drawpolygon(ov); else, roi = drawrectangle(ov); end
                if isvalid(roi) && ~isempty(roi.Position)
                    if strcmp(mode,'poly'), poly = roi.Position; else, poly = rectToPoly(roi.Position); end
                end
                delete(roi);
            catch
            end
            delete(ov);
        end
        function onReplot(obj)
            si = obj.boxIndex(obj.boxDD.Value); if isempty(si), return; end
            obj.replotBox(si, true); obj.refreshStatus();
        end

        % ---- (re)plot a box from its stored recipe ---------------------- %
        function replotAll(obj, onlyLive, autoOpen)
            if isempty(obj.PlotFig) || ~isvalid(obj.PlotFig), return; end
            for k = 1:numel(obj.Boxes)
                if onlyLive && obj.Boxes(k).frozen, continue; end
                obj.replotBox(k, autoOpen);
            end
            obj.drawGuides(); obj.drawStatTables(); obj.drawLabels();   % keep guides + stat tables + labels on top
        end
        function replotBox(obj, si, autoOpen)
            b = obj.Boxes(si);
            if isempty(b.srcTab) || isempty(b.srcRegion), return; end       % no recipe yet
            if isempty(obj.PlotFig) || ~isvalid(obj.PlotFig), return; end
            t = obj.srcTabByName(b.srcTab); if isempty(t) || ~isprop(t,'PlotFig'), return; end
            if isempty(t.PlotFig) || ~isvalid(t.PlotFig)
                if ~autoOpen || ~ismethod(t,'openFigure'), return; end      % source not open -> keep whatever is there
                try
                    t.openFigure(); drawnow;
                catch
                    return;
                end
            end
            % FROZEN box: temporarily re-apply the SOURCE-TAB settings captured at freeze
            % time so the clone reproduces the frozen appearance (not the source's current
            % live settings); the source is restored right after cloning.
            restore = obj.applyFrozenSrc(b, t);
            srcFig = t.PlotFig;                                            % (re-fetch after any source redraw)
            delete(findall(obj.PlotFig, 'Tag', obj.winTag(b.name)));        % replace old content
            s = 1; if isfield(b,'ratio') && ~isempty(b.ratio), s = b.ratio; end
            figPx = obj.PlotFig.Position(3:4);
            objs = obj.collectInRegion(srcFig, b.srcRegion);
            % Ground the placement on the LEFTMOST selected OBJECT (not the loose mouse
            % rectangle): map its left edge -> the box's left edge and its vertical
            % centre -> the box centre, so the clone is anchored by real content and
            % independent of how the selection was drawn. Fall back to the old
            % rectangle-centre behaviour when nothing was collected.
            boxC = [b.cx, b.cy]; selC = polyBBoxCenter(b.srcRegion); minx = inf;
            for k = 1:numel(objs)
                bb = objNormBBox(objs{k}, srcFig);
                if isempty(bb) || bb(1) >= minx, continue; end
                minx = bb(1); selC = [bb(1), bb(2)+bb(4)/2]; boxC = [b.cx - b.w/2, b.cy];
            end
            % Clone BACK-TO-FRONT: allchild is newest-first and copyobj puts each new
            % clone on TOP, which would REVERSE the source stacking -- landing an early-
            % created object (e.g. a box-plot axes with an opaque background) on top of
            % the later overlay objects and hiding them. Iterating in reverse preserves
            % the source z-order so small overlaid objects stay visible.
            for k = numel(objs):-1:1
                o = objs{k}; h = [];
                try, h = copyobj(o, obj.PlotFig); catch, h = []; end %#ok<CTCH>
                if isempty(h) || ~isgraphics(h), h = obj.captureFallback(o, t); end
                if isempty(h) || ~isgraphics(h), continue; end
                obj.offsetObject(h, boxC, selC, s, figPx);
                obj.scaleGraphics(h, s);       % faithful zoom: also scale fonts/lines/markers inside
                obj.cloneLegend(o, h, s, b.name);   % copyobj drops the axes' legend -> recreate it on the clone
                try, h.Tag = obj.winTag(b.name); catch, end %#ok<CTCH>
                try, set(findobj(h,'-property','ButtonDownFcn'), 'ButtonDownFcn', ''); catch, end %#ok<CTCH>
            end
            obj.restoreFrozenSrc(t, restore);                              % put the source tab back to its live settings
        end
        function restore = applyFrozenSrc(obj, b, t)
            %APPLYFROZENSRC  If box B is frozen and carries a freeze-time source-tab
            %   control state, apply it to source tab T (remembering T's current state
            %   for restoreFrozenSrc) and redraw T so the clone matches the frozen
            %   settings. Returns [] (nothing to restore) when not applicable.
            restore = [];
            if ~b.frozen || ~isfield(b,'srcState') || isempty(b.srcState), return; end
            if ~ismethod(t,'getControlState') || ~ismethod(t,'setControlState'), return; end
            try
                restore = t.getControlState();
                t.setControlState(b.srcState);
                obj.redrawSrc(t);
            catch
                restore = [];
            end
        end
        function restoreFrozenSrc(obj, t, restore)
            if isempty(restore) || ~ismethod(t,'setControlState'), return; end
            try, t.setControlState(restore); obj.redrawSrc(t); catch, end %#ok<CTCH>
        end
        function redrawSrc(obj, t)
            %REDRAWSRC  Redraw source tab T (so its figure reflects the just-applied
            %   control state) via the source app's public hook, then flush.
            sv = obj.sourceApp();
            if ~isempty(sv) && isvalid(sv) && ismethod(sv,'redrawTab'), try, sv.redrawTab(t); catch, end, end %#ok<CTCH>
            drawnow;
        end
        function objs = collectInRegion(~, srcFig, poly)
            objs = {};
            kids = allchild(srcFig);
            for i = 1:numel(kids)
                o = kids(i);
                if ~(isa(o,'matlab.ui.control.UIAxes') || isa(o,'matlab.graphics.axis.Axes') || ...
                     isa(o,'matlab.graphics.axis.PolarAxes') || isa(o,'matlab.ui.control.Label') || ...
                     isa(o,'matlab.ui.control.Image')), continue; end
                if isprop(o,'Tag') && strcmp(o.Tag,'paperGuide'), continue; end
                bb = objNormBBox(o, srcFig);
                if ~isempty(bb) && bboxHitsPoly(bb, poly), objs{end+1} = o; end %#ok<AGROW>
            end
        end
        function offsetObject(~, h, boxC, selC, s, figPx)
            %OFFSETOBJECT  Place clone H so the selection maps into the box, scaled by
            %   S about the box centre (keeps every relative size). S=1 reproduces the
            %   original pure translation exactly.
            if isa(h,'matlab.ui.control.Label') || isa(h,'matlab.ui.control.Image')
                bpx = boxC.*figPx; spx = selC.*figPx;  p = h.Position;   % pixel Position
                h.Position = [bpx + s*(p(1:2) - spx), s*p(3:4)];
            else
                try
                    h.Units = 'normalized';
                    try, h.PositionConstraint = 'innerposition'; catch, end   % hold the PLOT BOX, not the label-inclusive outer box
                    p = h.InnerPosition;                                      % a yyaxis panel's 2-sided labels would otherwise reflow the box narrower
                    h.InnerPosition = [boxC + s*(p(1:2) - selC), s*p(3:4)];
                catch
                end
            end
        end
        function scaleGraphics(~, h, s)
            %SCALEGRAPHICS  FAITHFUL zoom: multiply the point-based attributes of H and
            %   its descendants by S (fonts/linewidths/markers), so a scaled clone keeps
            %   the SAME relative writing/font sizes as the source (the axes Position is
            %   also scaled by S, so the font-to-plot proportion is preserved). No-op at
            %   S=1.
            if s == 1 || ~isgraphics(h), return; end
            hs = findall(h);
            % Capture ORIGINAL sizes for every object FIRST, then apply s*original.
            % Otherwise an axes FontSize change cascades to its auto YLabel/Title (the
            % axis labels), which the same loop then scales AGAIN -> s^2 (that shrank the
            % box/paired-plot y-labels). Scaling from the captured original avoids the
            % double-scaling regardless of cascade order.
            n = numel(hs); fs = nan(n,1); lw = nan(n,1); ms = nan(n,1); cs = nan(n,1); sd = cell(n,1);
            for k = 1:n
                o = hs(k);
                if isprop(o,'FontSize'),   fs(k) = o.FontSize;   end
                if isprop(o,'LineWidth'),  lw(k) = o.LineWidth;  end
                if isprop(o,'MarkerSize'), ms(k) = o.MarkerSize; end
                if isprop(o,'CapSize'),    cs(k) = o.CapSize;    end   % errorbar cap width (points)
                if isprop(o,'SizeData'),   sd{k} = o.SizeData;   end
            end
            for k = 1:n
                o = hs(k);
                if isfinite(fs(k)), try, o.FontSize   = s   * fs(k);        catch, end, end %#ok<CTCH>
                if isfinite(lw(k)), try, o.LineWidth  = max(0.05, s*lw(k)); catch, end, end %#ok<CTCH>
                if isfinite(ms(k)), try, o.MarkerSize = s   * ms(k);        catch, end, end %#ok<CTCH>
                if isfinite(cs(k)), try, o.CapSize    = s   * cs(k);        catch, end, end %#ok<CTCH>  % errorbar caps scale with the plot
                if ~isempty(sd{k}), try, o.SizeData   = s^2 * sd{k};        catch, end, end %#ok<CTCH>  % scatter area
            end
        end
        function h = captureFallback(obj, o, srcTab)
            h = [];
            isAx = isa(o,'matlab.ui.control.UIAxes') || isa(o,'matlab.graphics.axis.Axes');
            if isAx && ~isempty(srcTab) && ismethod(srcTab,'specForAxes') && ismethod(srcTab,'paperDraw')
                try
                    [kind, slot] = srcTab.specForAxes(o);
                    if ~isempty(kind)
                        u = o.Units; o.Units = 'normalized';
                        if isprop(o,'InnerPosition'), p = o.InnerPosition; else, p = o.Position; end  % PLOT BOX (a yyaxis Position returns the label-inclusive OUTER box)
                        o.Units = u;
                        h = uiaxes(obj.PlotFig, 'Units','normalized');
                        try, h.PositionConstraint = 'innerposition'; catch, end  % keep the source plot-box width; yyaxis labels grow OUTWARD
                        h.InnerPosition = p;
                        srcTab.paperDraw(h, kind, slot);
                        try, h.InnerPosition = p; catch, end                     % re-assert after the 2-sided yyaxis labels are added
                        return;
                    end
                catch
                end
            end
            if isAx
                try
                    u = o.Units; o.Units = 'normalized'; p = o.Position; o.Units = u;
                    tmp = [tempname '.png']; exportgraphics(o, tmp, 'Resolution', 200, 'BackgroundColor', 'white');
                    h = uiimage(obj.PlotFig, 'ImageSource', tmp, 'ScaleMethod', 'fit');
                    fp = obj.PlotFig.Position(3:4); h.Position = [p(1)*fp(1), p(2)*fp(2), p(3)*fp(1), p(4)*fp(2)];
                catch
                end
            end
        end
        function cloneLegend(obj, srcAx, h, s, boxName)
            %CLONELEGEND  copyobj drops an axes' legend (it is parented to the figure,
            %   not the axes), so a cloned panel loses its legend. Recreate it on the
            %   clone H from the source axes SRCAX's legend, mapping the legend entries
            %   to the cloned children by position so only the intended series (e.g. the
            %   B panel's Mix/Uct bars) are labelled. No-op for axes without a legend.
            isAx = @(x) isa(x,'matlab.graphics.axis.Axes') || isa(x,'matlab.ui.control.UIAxes');
            if ~isAx(srcAx) || ~isAx(h), return; end
            leg = []; try, leg = srcAx.Legend; catch, end %#ok<CTCH>
            if isempty(leg) || ~isvalid(leg), return; end
            try, if ~isempty(h.Legend) && isvalid(h.Legend), return; end, catch, end %#ok<CTCH>   % clone already drew one (native redraw)
            try
                srcKids = allchild(srcAx); hKids = allchild(h);
                if numel(srcKids) ~= numel(hKids), return; end          % copyobj preserves child order + count
                pc = leg.PlotChildren; idx = zeros(1, numel(pc));
                for i = 1:numel(pc)
                    j = find(srcKids == pc(i), 1);
                    if isempty(j), return; end
                    idx(i) = j;
                end
                nl = legend(h, hKids(idx), leg.String, 'Box', leg.Box, 'Location', leg.Location);
                try, nl.FontSize = max(1, s * leg.FontSize); catch, end %#ok<CTCH>
                try, nl.Tag = obj.winTag(boxName); catch, end %#ok<CTCH>   % tag so onClear/replot deletes it with the rest
            catch
            end
        end
        function onClear(obj)
            si = obj.boxIndex(obj.boxDD.Value); if isempty(si), return; end
            if obj.Boxes(si).frozen, obj.setStatus('Box frozen - unfreeze to clear.'); return; end
            delete(findall(obj.PlotFig, 'Tag', obj.winTag(obj.Boxes(si).name)));
            obj.Boxes(si).srcTab = ''; obj.Boxes(si).srcRegion = [];
            obj.Boxes(si).stats = obj.emptyStats();          % Clear box also removes the box's stat table(s)
            if ~isempty(obj.SelStat) && obj.SelStat(1) == si, obj.SelStat = []; end
            obj.drawGuides(); obj.drawStatTables(); obj.drawLabels(); obj.refreshStatus();
        end
        function t = winTag(~, name), t = ['pw:' name]; end

        % ---- labels / writing ------------------------------------------- %
        function onAddLabel(obj)
            si = obj.boxIndex(obj.boxDD.Value); if isempty(si), return; end
            txt = strtrim(obj.edLabelText.Value);
            if isempty(txt), obj.setStatus('Type the label text first, then Add to box.'); return; end
            if isempty(obj.PlotFig) || ~isvalid(obj.PlotFig), obj.openFigure(); end
            b = obj.Boxes(si);
            col = obj.colorRGB(obj.ddLabelColor.Value);
            rot = 90 * double(logical(obj.chkLabelRot.Value));
            lab = obj.mkLabel(txt, b.cx, b.cy, obj.edLabelSize.Value, col, rot);   % placed at the box centre
            if isempty(obj.Boxes(si).labels), obj.Boxes(si).labels = lab;
            else,                             obj.Boxes(si).labels(end+1) = lab; end
            obj.SelLabel = [si, numel(obj.Boxes(si).labels)];
            obj.drawLabels();
            obj.setStatus(sprintf('Added label to \x201C%s\x201D. Drag it to position; \x201CRemove selected\x201D deletes it.', b.name));
        end
        function onRemoveLabel(obj)
            key = obj.SelLabel;
            if isempty(key)                              % nothing clicked -> use the box picked in the controller
                si = obj.boxIndex(obj.boxDD.Value);
                if isempty(si) || isempty(obj.Boxes(si).labels)
                    obj.setStatus('Select a box that has a label (in the Box dropdown), then Remove selected.'); return;
                end
                key = [si, numel(obj.Boxes(si).labels)]; % its most-recently added label
            end
            bi = key(1); li = key(2);
            if bi <= numel(obj.Boxes) && li <= numel(obj.Boxes(bi).labels)
                obj.Boxes(bi).labels(li) = [];
            end
            obj.SelLabel = []; obj.drawLabels(); obj.refreshStatus();
        end
        function drawLabels(obj)
            if isempty(obj.PlotFig) || ~isvalid(obj.PlotFig), return; end
            if ~isempty(obj.LabelAx) && isvalid(obj.LabelAx), delete(obj.LabelAx); end
            ax = uiaxes(obj.PlotFig, 'Units','normalized', 'Position',[0 0 1 1], 'Tag','paperLabels', ...
                'Color','none', 'XColor','none', 'YColor','none', 'PickableParts','none');
            ax.XLim = [0 1]; ax.YLim = [0 1]; ax.XTick = []; ax.YTick = [];
            try, ax.Toolbar = []; disableDefaultInteractivity(ax); catch, end %#ok<CTCH>
            hold(ax, 'on');
            for bi = 1:numel(obj.Boxes)
                L = obj.Boxes(bi).labels;
                for li = 1:numel(L)
                    e = L(li); isSel = isequal(obj.SelLabel, [bi li]);
                    args = {'FontSize',e.size, 'Color',e.color, 'Rotation',e.rot, ...
                            'HorizontalAlignment','center', 'VerticalAlignment','middle', ...
                            'Interpreter','tex', 'Clipping','off'};
                    if isSel, args = [args, {'EdgeColor',[.9 0 0], 'LineWidth',0.75, 'Margin',2}]; end %#ok<AGROW>
                    th = text(ax, e.x, e.y, e.text, args{:});
                    th.UserData = [bi li];
                    th.ButtonDownFcn = @(s,ev) obj.startDragLabel(s);
                end
            end
            hold(ax, 'off');
            obj.LabelAx = ax;
        end
        function startDragLabel(obj, th)
            if ~isgraphics(th) || isempty(obj.PlotFig) || ~isvalid(obj.PlotFig), return; end
            obj.SelLabel = th.UserData; obj.DragInfo = struct('th', th);
            try, th.EdgeColor = [.9 0 0]; th.LineWidth = 0.75; th.Margin = 2; catch, end %#ok<CTCH>
            obj.PlotFig.WindowButtonMotionFcn = @(s,e) obj.dragLabelMove();
            obj.PlotFig.WindowButtonUpFcn     = @(s,e) obj.dragLabelEnd();
        end
        function dragLabelMove(obj)
            if isempty(obj.DragInfo) || ~isgraphics(obj.DragInfo.th), return; end
            cp = obj.PlotFig.CurrentPoint; fp = obj.PlotFig.Position(3:4);   % pixels -> figure fraction
            x = min(1, max(0, cp(1)/fp(1))); y = min(1, max(0, cp(2)/fp(2)));
            obj.DragInfo.th.Position = [x y 0];
            bi = obj.SelLabel(1); li = obj.SelLabel(2);
            if bi <= numel(obj.Boxes) && li <= numel(obj.Boxes(bi).labels)
                obj.Boxes(bi).labels(li).x = x; obj.Boxes(bi).labels(li).y = y;
            end
        end
        function dragLabelEnd(obj)
            if ~isempty(obj.PlotFig) && isvalid(obj.PlotFig)
                obj.PlotFig.WindowButtonMotionFcn = ''; obj.PlotFig.WindowButtonUpFcn = '';
            end
            obj.DragInfo = [];
        end
        function e = mkLabel(~, text, x, y, sz, color, rot)
            e = struct('text',text, 'x',x, 'y',y, 'size',sz, 'color',color, 'rot',rot);
        end
        function L = emptyLabels(~)
            L = struct('text',{},'x',{},'y',{},'size',{},'color',{},'rot',{});
        end
        function L = normLabels(obj, raw)
            L = obj.emptyLabels();
            if ~isstruct(raw), return; end
            for i = 1:numel(raw)
                r = raw(i);
                e = obj.mkLabel(obj.fld(r,'text',''), obj.fld(r,'x',0.5), obj.fld(r,'y',0.5), ...
                    obj.fld(r,'size',11), obj.fld(r,'color',[0 0 0]), obj.fld(r,'rot',0));
                if isempty(L), L = e; else, L(end+1) = e; end %#ok<AGROW>
            end
        end
        function v = fld(~, s, f, d)
            if isfield(s,f) && ~isempty(s.(f)), v = s.(f); else, v = d; end
        end
        function c = colorRGB(~, name)
            switch lower(name)
                case 'red',     c = [1 0 0];
                case 'green',   c = [0 0.6 0];
                case 'blue',    c = [0 0 1];
                case 'gray',    c = [.5 .5 .5];
                case 'cyan',    c = [0 1 1];
                case 'magenta', c = [1 0 1];
                case 'orange',  c = [1 0.5 0];
                otherwise,      c = [0 0 0];
            end
        end

        % ---- pages (add / duplicate / remove this paper page) ----------- %
        function onNewPage(obj)
            if isempty(obj.Viz) || ~ismethod(obj.Viz,'addPaperPage')
                obj.setStatus('Page management needs the paper-figure controller window.'); return;
            end
            nm = strtrim(obj.pageNameEd.Value); if isempty(nm), nm = 'Figure'; end
            nb = 4; if ~isempty(obj.boxCountEd) && isvalid(obj.boxCountEd), nb = obj.boxCountEd.Value; end
            obj.Viz.addPaperPage(nm, nb);
        end
        function onDupPage(obj)
            if ~isempty(obj.Viz) && ismethod(obj.Viz,'duplicatePaperPage'), obj.Viz.duplicatePaperPage(obj); end
        end
        function onRemPage(obj)
            if ~isempty(obj.Viz) && ismethod(obj.Viz,'removePaperPage'), obj.Viz.removePaperPage(obj); end
        end
        function setDDItems(~, dd, items)
            v = dd.Value; dd.Items = items;
            if any(strcmp(items, v)), dd.Value = v; elseif ~isempty(items), dd.Value = items{1}; end
        end

        % ---- stat tables (rendered as text -> export to PDF) ----------- %
        function onAddStat(obj)
            si = obj.boxIndex(obj.boxDD.Value); if isempty(si), return; end
            if isempty(obj.statSrcDD) || ~isvalid(obj.statSrcDD), return; end
            src = obj.statSrcDD.Value;
            if isempty(src) || strcmp(src,'(no source tabs)'), obj.setStatus('Pick a source tab for the stat table.'); return; end
            if isempty(obj.PlotFig) || ~isvalid(obj.PlotFig), obj.openFigure(); end
            b = obj.Boxes(si);
            st = obj.mkStat(src, b.cx, b.cy, 9);
            if b.frozen, st.data = obj.statOut(src); end       % box already frozen -> snapshot the report now
            if isempty(obj.Boxes(si).stats), obj.Boxes(si).stats = st; else, obj.Boxes(si).stats(end+1) = st; end
            obj.SelStat = [si, numel(obj.Boxes(si).stats)]; obj.SelLabel = [];
            obj.drawStatTables();
            obj.setStatus(sprintf('Added \x201C%s\x201D stat table. Drag to position; Remove selected deletes it.', src));
        end
        function onRemoveStat(obj)
            key = obj.SelStat;
            if isempty(key)                              % nothing clicked -> use the box picked in the controller
                si = obj.boxIndex(obj.boxDD.Value);
                if isempty(si) || isempty(obj.Boxes(si).stats)
                    obj.setStatus('Select a box that has a stat table (in the Box dropdown), then Remove selected.'); return;
                end
                key = [si, numel(obj.Boxes(si).stats)];  % its most-recently added stat table
            end
            bi = key(1); ki = key(2);
            if bi <= numel(obj.Boxes) && ki <= numel(obj.Boxes(bi).stats), obj.Boxes(bi).stats(ki) = []; end
            obj.SelStat = []; obj.drawStatTables(); obj.refreshStatus();
        end
        function out = statOut(obj, srcTabName)
            out = []; t = obj.srcTabByName(srcTabName);
            if isempty(t) || ~ismethod(t,'computeReport'), return; end
            try, out = t.computeReport(); catch, out = []; end %#ok<CTCH>
        end
        function drawStatTables(obj)
            if isempty(obj.PlotFig) || ~isvalid(obj.PlotFig), return; end
            if ~isempty(obj.StatAx) && isvalid(obj.StatAx), delete(obj.StatAx); end
            ax = uiaxes(obj.PlotFig, 'Units','normalized', 'Position',[0 0 1 1], 'Tag','paperStats', ...
                'Color','none', 'XColor','none', 'YColor','none', 'PickableParts','none');
            ax.XLim = [0 1]; ax.YLim = [0 1]; ax.XTick = []; ax.YTick = [];
            try, ax.Toolbar = []; disableDefaultInteractivity(ax); catch, end %#ok<CTCH>
            hold(ax, 'on');
            figPx = obj.PlotFig.Position(3:4);
            for bi = 1:numel(obj.Boxes)
                rt = 1; if isfield(obj.Boxes(bi),'ratio') && ~isempty(obj.Boxes(bi).ratio), rt = obj.Boxes(bi).ratio; end
                frz = obj.Boxes(bi).frozen;
                for ki = 1:numel(obj.Boxes(bi).stats)
                    e = obj.Boxes(bi).stats(ki);           % value copy -> scale the RENDER only, keep the stored size
                    e.size = max(2, e.size * rt);          % the stat table zooms WITH its box (the ratio control)
                    if frz && ~isempty(e.data), out = e.data;   % FROZEN box -> render the captured snapshot, not live data
                    else,                       out = obj.statOut(e.srcTab); end
                    obj.renderStatTable(ax, out, e, figPx, [bi ki], isequal(obj.SelStat,[bi ki]));
                end
            end
            hold(ax, 'off');
            obj.StatAx = ax;
        end
        function renderStatTable(obj, ax, out, e, figPx, key, isSel)
            if isempty(out) || ~isfield(out,'Data') || isempty(out.Data)
                th = text(ax, e.x, e.y, sprintf('(no stats report: %s)', e.srcTab), 'FontSize', e.size, ...
                    'Color',[.5 0 0], 'VerticalAlignment','top', 'Interpreter','none');
                th.UserData = key; th.ButtonDownFcn = @(s,ev) obj.startDragStat(key); return;
            end
            cn = out.ColumnName(:)'; grid = [cn; out.Data]; nRtot = size(grid,1); nC = numel(cn);
            fpx = 96/72;                                   % pt -> px @96dpi
            charW = 0.58 * e.size * fpx;                   % px per char
            rowH  = 1.7  * e.size * fpx / figPx(2);        % normalised row height
            colw = zeros(1,nC);
            for c = 1:nC
                mx = 3; for r = 1:nRtot, mx = max(mx, numel(char(string(grid{r,c})))); end
                colw(c) = (mx+1) * charW / figPx(1);
            end
            xL = cumsum([0 colw]); x0 = e.x; y0 = e.y; tableW = sum(colw); tableH = nRtot*rowH;
            ec = [.4 .4 .4]; lw = 0.5; if isSel, ec = [.9 0 0]; lw = 1; end
            pc = patch(ax, [x0 x0+tableW x0+tableW x0], [y0-tableH y0-tableH y0 y0], [1 1 1], ...
                'FaceAlpha', 0.9, 'EdgeColor', ec, 'LineWidth', lw, 'Clipping','off');
            pc.UserData = key; pc.ButtonDownFcn = @(s,ev) obj.startDragStat(key);
            plot(ax, [x0 x0+tableW], (y0-rowH)*[1 1], 'Color',[.4 .4 .4], 'LineWidth',0.5);   % header rule
            for r = 1:nRtot
                yc = y0 - (r-0.5)*rowH; fw = 'normal'; if r == 1, fw = 'bold'; end
                for c = 1:nC
                    tt = text(ax, x0+xL(c)+0.35*charW/figPx(1), yc, char(string(grid{r,c})), ...
                        'FontSize', e.size, 'FontWeight', fw, 'HorizontalAlignment','left', ...
                        'VerticalAlignment','middle', 'Interpreter','none', 'Clipping','off');
                    tt.UserData = key; tt.ButtonDownFcn = @(s,ev) obj.startDragStat(key);
                end
            end
        end
        function startDragStat(obj, key)
            if isempty(obj.PlotFig) || ~isvalid(obj.PlotFig), return; end
            obj.SelStat = key; obj.SelLabel = [];
            cp = obj.PlotFig.CurrentPoint; fp = obj.PlotFig.Position(3:4);
            bi = key(1); ki = key(2);
            obj.DragInfo = struct('kind','stat', 'ox', obj.Boxes(bi).stats(ki).x - cp(1)/fp(1), ...
                                                 'oy', obj.Boxes(bi).stats(ki).y - cp(2)/fp(2));
            obj.drawStatTables();
            obj.PlotFig.WindowButtonMotionFcn = @(s,e) obj.dragStatMove();
            obj.PlotFig.WindowButtonUpFcn     = @(s,e) obj.dragEnd();
        end
        function dragStatMove(obj)
            if isempty(obj.DragInfo) || ~isfield(obj.DragInfo,'kind') || ~strcmp(obj.DragInfo.kind,'stat') || isempty(obj.SelStat), return; end
            cp = obj.PlotFig.CurrentPoint; fp = obj.PlotFig.Position(3:4);
            x = min(1, max(0, cp(1)/fp(1) + obj.DragInfo.ox)); y = min(1, max(0, cp(2)/fp(2) + obj.DragInfo.oy));
            bi = obj.SelStat(1); ki = obj.SelStat(2);
            if bi <= numel(obj.Boxes) && ki <= numel(obj.Boxes(bi).stats)
                obj.Boxes(bi).stats(ki).x = x; obj.Boxes(bi).stats(ki).y = y;
            end
            obj.drawStatTables();
        end
        function dragEnd(obj)
            if ~isempty(obj.PlotFig) && isvalid(obj.PlotFig)
                obj.PlotFig.WindowButtonMotionFcn = ''; obj.PlotFig.WindowButtonUpFcn = '';
            end
            obj.DragInfo = [];
        end
        function e = mkStat(~, srcTab, x, y, sz)
            e = struct('srcTab',srcTab, 'x',x, 'y',y, 'size',sz, 'data',[]);   % data = frozen report snapshot ([] = fetch live)
        end
        function L = emptyStats(~)
            L = struct('srcTab',{},'x',{},'y',{},'size',{},'data',{});
        end
        function L = normStats(obj, raw)
            L = obj.emptyStats();
            if ~isstruct(raw), return; end
            for i = 1:numel(raw)
                r = raw(i);
                e = obj.mkStat(obj.fld(r,'srcTab',''), obj.fld(r,'x',0.5), obj.fld(r,'y',0.5), obj.fld(r,'size',9));
                if isfield(r,'data'), e.data = r.data; end     % carry the frozen snapshot across save/reload
                if isempty(L), L = e; else, L(end+1) = e; end %#ok<AGROW>
            end
        end

        % ---- box geometry edits ----------------------------------------- %
        function onField(obj)
            si = obj.boxIndex(obj.boxDD.Value); if isempty(si), return; end
            if obj.Boxes(si).frozen, obj.syncFields(); return; end
            old = [obj.Boxes(si).cx, obj.Boxes(si).cy];
            obj.Boxes(si).cx = obj.edCx.Value; obj.Boxes(si).cy = obj.edCy.Value;
            obj.Boxes(si).w  = max(0.01, obj.edW.Value); obj.Boxes(si).h = max(0.01, obj.edH.Value);
            d = [obj.Boxes(si).cx, obj.Boxes(si).cy] - old;                 % move captured content with the box
            if any(d) && ~isempty(obj.PlotFig) && isvalid(obj.PlotFig)
                hs = findall(obj.PlotFig, 'Tag', obj.winTag(obj.Boxes(si).name));
                for hi = 1:numel(hs), obj.translateObject(hs(hi), d, obj.PlotFig.Position(3:4)); end
            end
            if any(d)                                                       % labels + stat tables ride along with the box
                for li = 1:numel(obj.Boxes(si).labels)
                    obj.Boxes(si).labels(li).x = min(1, max(0, obj.Boxes(si).labels(li).x + d(1)));
                    obj.Boxes(si).labels(li).y = min(1, max(0, obj.Boxes(si).labels(li).y + d(2)));
                end
                for ki = 1:numel(obj.Boxes(si).stats)
                    obj.Boxes(si).stats(ki).x = min(1, max(0, obj.Boxes(si).stats(ki).x + d(1)));
                    obj.Boxes(si).stats(ki).y = min(1, max(0, obj.Boxes(si).stats(ki).y + d(2)));
                end
            end
            obj.drawGuides(); obj.drawStatTables(); obj.drawLabels();
        end
        function translateObject(~, h, d, figPx)
            %TRANSLATEOBJECT  Pure translation by normalised delta D (used on box move).
            if isa(h,'matlab.ui.control.Label') || isa(h,'matlab.ui.control.Image')
                p = h.Position; h.Position = [p(1)+d(1)*figPx(1), p(2)+d(2)*figPx(2), p(3), p(4)];
            else
                try, h.Units = 'normalized'; p = h.Position; h.Position = [p(1)+d(1), p(2)+d(2), p(3), p(4)]; catch, end %#ok<CTCH>
            end
        end
        function onRatio(obj)
            si = obj.boxIndex(obj.boxDD.Value); if isempty(si), return; end
            if obj.Boxes(si).frozen, obj.syncFields(); return; end
            obj.Boxes(si).ratio = obj.edRatio.Value;
            obj.replotBox(si, false); obj.drawGuides(); obj.drawStatTables(); obj.drawLabels();
        end
        function onName(obj)
            si = obj.boxIndex(obj.boxDD.Value); if isempty(si), return; end
            if obj.Boxes(si).frozen, obj.edName.Value = obj.Boxes(si).name; return; end
            nm = strtrim(obj.edName.Value);
            if isempty(nm) || any(strcmp({obj.Boxes.name},nm)), obj.edName.Value = obj.Boxes(si).name; return; end
            if ~isempty(obj.PlotFig) && isvalid(obj.PlotFig)
                set(findall(obj.PlotFig,'Tag',obj.winTag(obj.Boxes(si).name)), 'Tag', obj.winTag(nm));
            end
            obj.Boxes(si).name = nm; obj.refreshBoxList(nm); obj.drawGuides();
        end
        function onBoxSel(obj), obj.syncFields(); obj.drawGuides(); obj.drawStatTables(); obj.drawLabels(); end
        function syncFields(obj)
            si = obj.boxIndex(obj.boxDD.Value); if isempty(si), return; end
            b = obj.Boxes(si);
            obj.edName.Value = b.name; obj.edCx.Value = b.cx; obj.edCy.Value = b.cy; obj.edW.Value = b.w; obj.edH.Value = b.h;
            if ~isempty(obj.edRatio) && isvalid(obj.edRatio)
                rt = 1; if isfield(b,'ratio') && ~isempty(b.ratio), rt = b.ratio; end
                obj.edRatio.Value = min(2, max(0.1, rt));
            end
            if ~isempty(obj.freezeChk) && isvalid(obj.freezeChk), obj.freezeChk.Value = b.frozen; end
            if ~isempty(obj.srcTabDD) && isvalid(obj.srcTabDD) && ~isempty(b.srcTab) && any(strcmp(obj.srcTabDD.Items, b.srcTab))
                obj.srcTabDD.Value = b.srcTab;
            end
        end
        function addBox(obj)
            e = obj.mkBox(obj.uniqueName('box'), 0.5, 0.5, 0.12, 0.10);
            obj.Boxes = obj.pushBox(obj.Boxes, e); obj.refreshBoxList(e.name); obj.syncFields(); obj.drawGuides();
        end
        function dupBox(obj)
            si = obj.boxIndex(obj.boxDD.Value); if isempty(si), return; end
            b = obj.Boxes(si);
            e = obj.mkBox(obj.uniqueName([b.name '*']), min(1,b.cx+0.02), max(0,b.cy-0.02), b.w, b.h);
            if isfield(b,'ratio') && ~isempty(b.ratio), e.ratio = b.ratio; end
            e.srcTab = b.srcTab; e.srcRegion = b.srcRegion;                 % carry the cloned CONTENT recipe (source region + zoom)
            if isfield(b,'labels') && ~isempty(b.labels)                    % duplicate carries a nudged copy of the labels
                e.labels = b.labels;
                for li = 1:numel(e.labels)
                    e.labels(li).x = min(1, e.labels(li).x + 0.02); e.labels(li).y = max(0, e.labels(li).y - 0.02);
                end
            end
            if isfield(b,'stats') && ~isempty(b.stats)                      % and a nudged copy of the stat tables
                e.stats = b.stats;
                for ki = 1:numel(e.stats)
                    e.stats(ki).x = min(1, e.stats(ki).x + 0.02); e.stats(ki).y = max(0, e.stats(ki).y - 0.02);
                end
            end
            obj.Boxes = obj.pushBox(obj.Boxes, e); obj.refreshBoxList(e.name); obj.syncFields();
            ni = obj.boxIndex(e.name);                                      % actually clone the plot content into the new box
            if ~isempty(ni), obj.replotBox(ni, true); end
            obj.drawGuides(); obj.drawStatTables(); obj.drawLabels(); obj.refreshStatus();
        end
        function removeBox(obj)
            si = obj.boxIndex(obj.boxDD.Value); if isempty(si) || numel(obj.Boxes) <= 1, return; end
            if obj.Boxes(si).frozen, obj.setStatus('Box frozen - unfreeze to remove.'); return; end
            if ~isempty(obj.PlotFig) && isvalid(obj.PlotFig)
                delete(findall(obj.PlotFig, 'Tag', obj.winTag(obj.Boxes(si).name)));
            end
            obj.Boxes(si) = []; obj.SelLabel = []; obj.SelStat = [];
            obj.refreshBoxList(obj.Boxes(max(1,si-1)).name); obj.syncFields(); obj.drawGuides(); obj.drawStatTables(); obj.drawLabels(); obj.refreshStatus();
        end
        function nm = uniqueName(obj, base)
            nm = base; i = 1; ex = {obj.Boxes.name};
            while any(strcmp(ex, nm)), i = i + 1; nm = sprintf('%s %d', base, i); end
        end
        function refreshBoxList(obj, keep)
            if nargin < 2, keep = obj.boxDD.Value; end
            nm = obj.boxNames(); obj.boxDD.Items = nm;
            if any(strcmp(nm, keep)), obj.boxDD.Value = keep; elseif ~isempty(nm), obj.boxDD.Value = nm{1}; end
        end

        % ---- freeze ----------------------------------------------------- %
        function onFreeze(obj)
            si = obj.boxIndex(obj.boxDD.Value); if isempty(si), return; end
            obj.Boxes(si).frozen = obj.freezeChk.Value;
            if obj.Boxes(si).frozen                            % capture the SOURCE-TAB settings so a reopen reproduces the frozen plot
                t = obj.srcTabByName(obj.Boxes(si).srcTab);
                if ~isempty(t) && ismethod(t,'getControlState')
                    try, obj.Boxes(si).srcState = t.getControlState(); catch, obj.Boxes(si).srcState = []; end %#ok<CTCH>
                end
            else
                obj.Boxes(si).srcState = [];                   % live again
            end
            for ki = 1:numel(obj.Boxes(si).stats)              % freeze the stat-table DATA too (else it keeps re-fetching live)
                if obj.Boxes(si).frozen, obj.Boxes(si).stats(ki).data = obj.statOut(obj.Boxes(si).stats(ki).srcTab);   % snapshot
                else,                    obj.Boxes(si).stats(ki).data = []; end                                        % live again
            end
            obj.drawGuides(); obj.drawStatTables(); obj.refreshStatus();
        end

        % ---- source tabs (the SOURCE app's tabs -- SourceViz when set) --- %
        function v = sourceApp(obj)
            %SOURCEAPP  The Visualizer whose tabs the boxes clone from: the source
            %   app for a paper controller, else this app itself.
            v = obj.Viz;
            if ~isempty(obj.Viz) && isprop(obj.Viz,'SourceViz') && ~isempty(obj.Viz.SourceViz) ...
                    && isvalid(obj.Viz.SourceViz)
                v = obj.Viz.SourceViz;
            end
        end
        function names = srcTabNames(obj)
            names = {}; v = obj.sourceApp();
            if isempty(v), names = {'(no source tabs)'}; return; end
            for i = 1:numel(v.Tabs)
                t = v.Tabs{i};
                if t == obj || isa(t,'viz.plots.PaperFig01Tab'), continue; end
                names{end+1} = t.Name; %#ok<AGROW>
            end
            if isempty(names), names = {'(no source tabs)'}; end
        end
        function t = srcTabByName(obj, nm)
            t = []; v = obj.sourceApp();
            if isempty(v) || isempty(nm), return; end
            for i = 1:numel(v.Tabs)
                if strcmp(v.Tabs{i}.Name, nm), t = v.Tabs{i}; return; end
            end
        end

        % ---- default: N empty boxes (grid), editable ------------------ %
        function S = defaultBoxes(obj, nBoxes)
            if nargin < 2 || isempty(nBoxes), nBoxes = 4; end
            nBoxes = max(1, round(nBoxes));
            nc = ceil(sqrt(nBoxes)); nr = ceil(nBoxes/nc);       % near-square grid
            wI = min(0.24, 0.9/nc); hI = min(0.24, 0.9/nr);
            S = struct([]); k = 0;
            for r = 1:nr
                for c = 1:nc
                    k = k + 1; if k > nBoxes, break; end
                    cx = (c-0.5)/nc; cy = 1 - (r-0.5)/nr;         % top-to-bottom rows
                    S = obj.pushBox(S, obj.mkBox(sprintf('box %d', k), cx, cy, wI, hI));
                end
            end
        end
        function e = mkBox(~, name, cx, cy, w, h)
            e = struct('name',name, 'cx',cx, 'cy',cy, 'w',w, 'h',h, 'ratio',1, ...
                'frozen',false, 'srcTab','', 'srcRegion',[], 'srcState',[], ...
                'labels', struct('text',{},'x',{},'y',{},'size',{},'color',{},'rot',{}), ...
                'stats',  struct('srcTab',{},'x',{},'y',{},'size',{},'data',{}));
        end
        function S = pushBox(~, S, e)
            if isempty(S), S = e; else, S(end+1) = e; end
        end
        function r = boxRect(obj, si)
            b = obj.Boxes(si); r = [b.cx - b.w/2, b.cy - b.h/2, b.w, b.h];
        end
        function n = boxNames(obj), n = {obj.Boxes.name}; end
        function si = boxIndex(obj, nm), si = find(strcmp({obj.Boxes.name}, nm), 1); end

        function refreshStatus(obj)
            if isempty(obj.PlotFig) || ~isvalid(obj.PlotFig), obj.setStatus('Figure not open.'); return; end
            nfill = 0; nfroz = sum(arrayfun(@(b) b.frozen, obj.Boxes));
            for k = 1:numel(obj.Boxes)
                if ~isempty(findall(obj.PlotFig, 'Tag', obj.winTag(obj.Boxes(k).name))), nfill = nfill + 1; end
            end
            fr = ''; if nfroz > 0, fr = sprintf('  (%d locked)', nfroz); end
            obj.setStatus(sprintf('Open. %d / %d boxes filled.%s', nfill, numel(obj.Boxes), fr));
        end
        function setStatus(obj, t)
            if ~isempty(obj.statusLbl) && isvalid(obj.statusLbl), obj.statusLbl.Text = t; end
        end
    end
end

% ===================================================================== %
function bb = objNormBBox(o, srcFig)
    bb = [];
    try
        if isa(o,'matlab.ui.control.Label') || isa(o,'matlab.ui.control.Image')
            fp = srcFig.Position(3:4); p = o.Position;
            bb = [p(1)/fp(1), p(2)/fp(2), p(3)/fp(1), p(4)/fp(2)];
        else
            u = o.Units; o.Units = 'normalized'; p = o.Position; o.Units = u;   % OUTER (label-inclusive) box: anchors the clone so y-labels sit INSIDE the box, and keeps region collection inclusive
            bb = p;
        end
    catch
    end
end
function poly = rectToPoly(r)
    poly = [r(1) r(2); r(1)+r(3) r(2); r(1)+r(3) r(2)+r(4); r(1) r(2)+r(4)];
end
function c = polyBBoxCenter(poly)
    c = [(min(poly(:,1)) + max(poly(:,1)))/2, (min(poly(:,2)) + max(poly(:,2)))/2];
end
function tf = bboxHitsPoly(bb, poly)
    % bb = [x y w h]; poly = Nx2 vertices. True if the bbox overlaps the polygon.
    px = poly(:,1); py = poly(:,2);
    cx = [bb(1), bb(1)+bb(3), bb(1)+bb(3), bb(1)];
    cy = [bb(2), bb(2), bb(2)+bb(4), bb(2)+bb(4)];
    if any(inpolygon(cx, cy, px, py)), tf = true; return; end                          % a bbox corner is inside the polygon
    if any(px >= bb(1) & px <= bb(1)+bb(3) & py >= bb(2) & py <= bb(2)+bb(4)), tf = true; return; end  % a vertex is inside the bbox
    tf = inpolygon(bb(1)+bb(3)/2, bb(2)+bb(4)/2, px, py);                               % the bbox centre is inside the polygon
end
