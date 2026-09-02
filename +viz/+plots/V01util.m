classdef V01util
%V01UTIL  Shared static helpers for the ported Visualizer_01 tabs (f / f06 / f07 / f05).
%
%   Collects the per-neuron reduction (repeated-measures handling by U_unity /
%   LPow), small field accessors, an error-band plotter and a significance
%   formatter so the Dashboard01Tab / Categorization06Tab / ... tabs share one
%   implementation. All methods are static and side-effect free (except the
%   plotting ones, which draw into the axes you pass).
%
%   See also: viz.plots.Dashboard01Tab, analysis.tuningGroupMask

    methods (Static)
        % ---- unit count / field access -------------------------------- %
        function n = nU(D)
            try
                n = filter.unitCount(D);
            catch
                if isfield(D,'EI'),         n = numel(D.EI);
                elseif isfield(D,'fit_NL'), n = size(D.fit_NL, 2);
                else,                       n = 0;
                end
            end
        end

        function v = colv(D, name, N)
            if nargin < 3, N = viz.plots.V01util.nU(D); end
            if isfield(D, name) && ~isempty(D.(name))
                v = double(D.(name)(:));
            else
                v = nan(N,1);
            end
        end

        function isI = isInhib(D)
            N = viz.plots.V01util.nU(D);
            isI = false(N,1);
            if isfield(D,'EI')
                for k = 1:N, isI(k) = strcmpi(strtrim(string(D.EI(k))), "I"); end
            end
        end

        function v = layerNum(D)
            N = viz.plots.V01util.nU(D); v = nan(N,1);
            if ~isfield(D,'LG'), return; end
            map = {'SG',1,'G',2,'IG',3,'Deep',4};
            for k = 1:N
                s = char(strtrim(string(D.LG(k))));
                idx = find(strcmpi(map(1:2:end), s), 1);
                if ~isempty(idx), v(k) = map{2*idx}; end
            end
        end

        % ---- per-point color assignment (laminar tabs) ---------------- %
        function [ci, pal, labels, counts] = colorBy(D, idx, key)
            %COLORBY  Color assignment for the units `idx` (rows of D) by feature.
            %   ci     : numel(idx)x1 integer index into pal for each point
            %   pal    : Kx3 RGB palette (LAST row = gray "n/a")
            %   labels : 1xK cellstr category labels (LAST = '(n/a)')
            %   counts : 1xK count of `idx` points falling in each category
            %   key (case-insensitive): 'Layer' (LG SG/G/IG/Deep), 'G_type'
            %   (Linear/Non-linear/Unknown), 'E/I', 'Animal', 'Penetration',
            %   'Task' (Tasknumb). Unknown -> generic categorical over D.(key).
            N   = viz.plots.V01util.nU(D);
            idx = idx(:);
            GRAY = [0.6 0.6 0.6];
            switch lower(strtrim(char(key)))
                case 'layer'
                    val   = viz.plots.V01util.layerNum(D);                 % 1..4 / NaN
                    base  = [0 0.45 0.74; 0.85 0.33 0.10; 0.47 0.67 0.19; 0.49 0.18 0.56];
                    names = {'SG','G','IG','Deep'};
                case {'g_type','gtype'}
                    val   = viz.plots.V01util.colv(D, 'G_type', N);
                    % old F2_5B_3 laminar plots: Colorss{2..4} = black / Cyellow / red
                    % (Cyellow = [253 219 85]/255), keyed by Type 2/3/4 == G_type 1/2/3.
                    base  = [0 0 0; 253 219 85; 255 0 0] / 255;            % Linear / Non-linear / Unknown
                    names = {'Linear','Non-linear','Unknown'};
                case {'ei','e/i'}
                    isI = viz.plots.V01util.isInhib(D);                    % missing EI -> E
                    val = ones(N,1); val(isI) = 2;
                    base  = [0 0.7 0; 0 0 1];
                    names = {'E','I'};
                otherwise
                    [val, names] = viz.plots.V01util.catCode(D, key, N);
                    base = viz.plots.V01util.distinctColors(numel(names));
            end
            K   = numel(names);
            pal = [base; GRAY];
            ci  = round(val(idx));
            bad = ~isfinite(ci) | ci < 1 | ci > K;
            ci(bad) = K + 1;
            labels = [names, {'(n/a)'}];
            counts = zeros(1, K + 1);
            for k = 1:K + 1, counts(k) = sum(ci == k); end
        end

        function [code, labels] = catCode(D, key, N)
            %CATCODE  Map each unit to a category code 1..K over a categorical field.
            %   Empty/missing values -> NaN (so colorBy paints them gray). Returns
            %   the per-unit code (Nx1) and the 1xK label list (first-appearance order).
            if nargin < 3 || isempty(N), N = viz.plots.V01util.nU(D); end
            switch lower(strtrim(char(key)))
                case 'animal'
                    if     isfield(D,'Animal'),  raw = string(D.Animal(:));
                    elseif isfield(D,'Dataset'), raw = string(D.Dataset(:));
                    else,                         raw = strings(N,1); end
                case 'penetration'
                    if isfield(D,'Penetration'), raw = string(D.Penetration(:)); else, raw = strings(N,1); end
                case {'task','tasknumb'}
                    if isfield(D,'Tasknumb'), raw = string(D.Tasknumb(:)); else, raw = strings(N,1); end
                otherwise
                    if isfield(D, char(key)), raw = string(D.(char(key))(:)); else, raw = strings(N,1); end
            end
            if numel(raw) ~= N, raw = strings(N,1); end
            raw(ismissing(raw)) = "";
            u = unique(raw, 'stable'); u(u == "") = [];
            labels = cellstr(reshape(u, 1, []));
            code = zeros(N,1);
            for k = 1:numel(u), code(raw == u(k)) = k; end
            code(code == 0) = NaN;                                  % empties -> '(n/a)'
        end

        function C = distinctColors(K)
            %DISTINCTCOLORS  Kx3 palette of reasonably distinct colors.
            if K <= 0,      C = zeros(0,3);
            elseif K <= 7,  C = lines(K);
            else,           C = hsv(K);
            end
        end

        % ---- per-neuron reduction (repeated-measures handling) -------- %
        function R = reducer(D, idx, mode)
            %REDUCER  Build a plan to collapse rows of `idx` per neuron (U_unity).
            %   mode: 'all'/'lme' = identity; 'first'/'maxpow' = one row per
            %   neuron (first occurrence / max LPow); 'mean' = per-neuron average.
            %   'maxpow' falls back to 'first' when D has no LPow field (LPow is
            %   no longer loaded by loadData -- it was all zeros).
            idx = idx(:);
            R.mode = mode; R.idx = idx;
            n = numel(idx);
            if n == 0, R.g = []; R.nG = 0; R.repsel = []; return; end
            if isfield(D,'U_unity'), uu = double(D.U_unity(idx)); else, uu = (1:n)'; end
            [u,~,g] = unique(uu(:), 'stable');
            R.g = g; R.nG = numel(u);
            if any(strcmp(mode, {'all','lme'}))
                R.repsel = (1:n)';
            else
                repsel = zeros(R.nG,1);
                useP = strcmp(mode,'maxpow') && isfield(D,'LPow');
                if useP, lp = double(D.LPow(idx)); end
                for j = 1:R.nG
                    mm = find(g == j);
                    if useP, [~,a] = max(lp(mm)); repsel(j) = mm(a);
                    else,    repsel(j) = mm(1);
                    end
                end
                R.repsel = repsel;
            end
        end

        function out = redVec(R, v)
            if isempty(R.idx), out = []; return; end
            if strcmp(R.mode,'mean')
                out = accumarray(R.g, v(:), [], @(z) mean(z,'omitnan'));
            else
                out = v(R.repsel);
            end
        end

        function out = redCols(R, M)
            if isempty(R.idx), out = zeros(size(M,1),0); return; end
            if strcmp(R.mode,'mean')
                out = zeros(size(M,1), R.nG);
                for j = 1:R.nG, out(:,j) = mean(M(:, R.g==j), 2, 'omitnan'); end
            else
                out = M(:, R.repsel);
            end
        end

        function out = redIdx(R)
            if isempty(R.idx), out = []; else, out = R.idx(R.repsel); end
        end

        % ---- per-neuron -> single (dominant) cortical layer ----------- %
        function repByLayer = layerReps(D, selIdx, LGn, repMode, layers)
            %LAYERREPS  Representative observation rows grouped by cortical layer.
            %   repByLayer{k} lists the selected rows assigned to layers(k) (default
            %   layers = 1:3 = SG/G/IG).
            %     'all'/'lme'  : observation-level -- every selected obs sits in its
            %                    own layer, no dedup (the old pooled-by-layer figures).
            %     per-neuron   : each neuron (U_unity) is assigned to ONE layer =
            %     ('first'/      mode(LG over its selected obs), matching Visualizer_03
            %      'maxpow'/     / GainLaminar03 lamComposition, and its representative
            %      'mean')       is drawn from that dominant layer. A neuron spanning
            %                    two layers is thus counted ONCE (in its dominant
            %                    layer), not once per layer.
            if nargin < 5 || isempty(layers), layers = 1:3; end
            nL = numel(layers);
            repByLayer = cell(1, nL);
            selIdx = selIdx(:);
            if isempty(selIdx), return; end
            if any(strcmp(repMode, {'all','lme'}))
                for k = 1:nL, repByLayer{k} = selIdx(LGn(selIdx) == layers(k)); end
                return;
            end
            UU = viz.plots.V01util.colv(D, 'U_unity');
            [u,~,gi] = unique(UU(selIdx), 'stable');
            reps = zeros(numel(u),1); lays = zeros(numel(u),1); m = 0;
            for j = 1:numel(u)
                oi = selIdx(gi == j);
                Lv = LGn(oi); Lv = Lv(isfinite(Lv));
                if isempty(Lv), continue; end
                domL = mode(Lv);                          % most-common layer (ties -> lowest)
                k = find(layers == domL, 1);
                if isempty(k), continue; end              % dominant layer not shown -> drop
                R = viz.plots.V01util.reducer(D, oi(LGn(oi) == domL), repMode);
                m = m + 1; reps(m) = viz.plots.V01util.redIdx(R); lays(m) = k;
            end
            reps = reps(1:m); lays = lays(1:m);
            for k = 1:nL, repByLayer{k} = reps(lays == k); end
        end

        % ---- mixed-effects population tuning (repeated-obs correction) ---- %
        %  Two ways to turn per-OBSERVATION tuning curves into a population mean
        %  that respects the repeated recordings of a neuron (U_unity). See
        %  STATS_MIXED_EFFECTS.md sec 3e.
        function An = aggNeuronCurves(A, neur)
            %AGGNEURONCURVES  Average each neuron's observation curves ("per-neuron"
            %   mixed-effects tuning). A: [d1 x d2 x P x K] per-observation curves;
            %   neur: K-vector of neuron ids. Returns An: [d1 x d2 x P x G], G =
            %   #distinct neurons ('stable' order), each slice = mean over that
            %   neuron's observations -> downstream mean/SEM is then over NEURONS.
            neur = neur(:);
            if isempty(A) || size(A,4) ~= numel(neur), An = A; return; end
            [~, ~, gi] = unique(neur, 'stable'); G = max(gi);
            sz = size(A);
            An = zeros(sz(1), sz(2), sz(3), G);
            for j = 1:G, An(:,:,:,j) = mean(A(:,:,:,gi == j), 4); end
        end

        function v2 = avgIntoReps(v, obsRows, UU)
            %AVGINTOREPS  Display copy of a per-observation vector where EVERY
            %   observation row of a neuron holds that neuron's MEAN over obsRows.
            %   Indexing the copy at one representative row per neuron then yields
            %   per-neuron means -- this drives the 'mean'/'lme' per-neuron scatter
            %   and histogram displays without changing any panel code.
            v2 = v; obsRows = obsRows(:);
            if isempty(obsRows), return; end
            [~, ~, g] = unique(UU(obsRows), 'stable');
            m = accumarray(g, v(obsRows), [], @(z) mean(z, 'omitnan'));
            v2(obsRows) = m(g);
        end

        function [av, an, arep] = aggNeuronScalar(v, neur, rows)
            %AGGNEURONSCALAR  Per-neuron mean of a scalar observation vector -- the
            %   scalar analogue of aggNeuronCurves, for the Mixed-effects DISPLAY of
            %   the box / paired / change-distribution panels: each neuron (U_unity)
            %   contributes ONE value = the mean of its finite observations, so a cell
            %   recorded at several intensities is plotted once instead of once per
            %   intensity. v and neur are parallel K-vectors; `rows` (optional) the
            %   parallel D row indices. Returns av (G per-neuron means in 'stable'
            %   neuron order), an (the G distinct neuron ids) and arep (a
            %   representative row per neuron = its first occurrence, for click /
            %   inspect). A neuron whose observations are all non-finite yields NaN
            %   (dropped downstream by the isfinite guards, like Align_bad HBW units).
            %   See STATS_MIXED_EFFECTS.md sec 3e.
            v = v(:); neur = neur(:);
            if isempty(neur), av = zeros(0,1); an = zeros(0,1); arep = zeros(0,1); return; end
            [an, ~, gi] = unique(neur, 'stable');
            av = accumarray(gi, v, [], @(z) mean(z, 'omitnan'));
            if nargin >= 3 && ~isempty(rows)
                rows = rows(:); arep = accumarray(gi, rows, [], @(z) z(1));
            else
                arep = an;
            end
        end

        function [mu, se] = lmePerAngle(M, neur)
            %LMEPERANGLE  Per-row random-intercept mixed model y ~ 1 + (1|neuron):
            %   the literal "mixed-effect model" tuning. M: [P x K] (P rows e.g.
            %   angles, K observations); neur: K-vector neuron ids. For each row
            %   returns the fixed-intercept estimate (population mean) and its model
            %   SE. Rows with <2 neurons or a fitlme failure fall back to mean +/-
            %   SEM. SLOW (one fitlme per row) -- aggNeuronCurves is the fast default.
            P = size(M,1); K = size(M,2); mu = nan(P,1); se = nan(P,1);
            neur = neur(:); if numel(neur) ~= K, neur = (1:K)'; end
            if K == 0, return; end
            g = categorical(neur);
            for a = 1:P
                y = M(a,:).'; ok = isfinite(y); yy = y(ok); gg = g(ok);
                if numel(yy) < 2
                    if ~isempty(yy)
                        mu(a) = mean(yy); se(a) = 0;
                    end
                    continue;
                end
                if numel(unique(gg)) < 2                 % single neuron -> no random effect
                    mu(a) = mean(yy); se(a) = std(yy)/sqrt(numel(yy)); continue;
                end
                try
                    L = fitlme(table(yy, gg, 'VariableNames', {'y','neur'}), 'y ~ 1 + (1|neur)');
                    mu(a) = L.Coefficients.Estimate(1); se(a) = L.Coefficients.SE(1);
                catch
                    mu(a) = mean(yy); se(a) = std(yy)/sqrt(numel(yy));
                end
            end
        end

        % ---- plotting / formatting ------------------------------------ %
        function plotSE(ax, X, Y, SE, lineCol, faceCol, faceAlpha, lineWidth)
            if nargin < 8 || isempty(lineWidth), lineWidth = 1.4; end
            X = X(:); Y = Y(:); SE = SE(:);
            ok = isfinite(Y) & isfinite(SE) & isfinite(X);
            X = X(ok); Y = Y(ok); SE = SE(ok);
            if isempty(X), return; end
            ylo = Y - SE; yhi = Y + SE;
            patch(ax, [X; flipud(X)], [ylo; flipud(yhi)], faceCol, ...
                'FaceAlpha', faceAlpha, 'EdgeColor', 'none');
            line(ax, X, Y, 'Color', lineCol, 'LineWidth', lineWidth);
        end

        % ---- click-to-pick selection ring ----------------------------- %
        function highlightUnits(ax, X, Y, reps, sels)
            %HIGHLIGHTUNITS  Ring the picked unit(s) with a tiny black circle so the
            %   user can confirm the right point was clicked. X/Y are parallel to
            %   `reps` (the unit ids drawn on `ax`); `sels` is one or more unit ids
            %   to ring. Any previous ring on `ax` (Tag 'selRing') is removed first,
            %   so calling this on every redraw keeps exactly the current selection
            %   ringed (pass a NaN/absent sel to just clear it). The ring ignores
            %   mouse picks and is kept out of legends.
            if isempty(ax) || ~isgraphics(ax), return; end
            delete(findobj(ax, 'Tag', 'selRing'));
            if nargin < 5 || isempty(sels) || isempty(reps), return; end
            reps = reps(:);
            wasHeld = ishold(ax); hold(ax, 'on');
            for s = reshape(sels, 1, [])
                if ~isfinite(s), continue; end
                k = find(reps == s, 1);
                if isempty(k) || k > numel(X) || k > numel(Y), continue; end
                if ~isfinite(X(k)) || ~isfinite(Y(k)), continue; end
                h = plot(ax, X(k), Y(k), 'o', 'MarkerEdgeColor', 'k', ...
                    'MarkerFaceColor', 'none', 'MarkerSize', 10, 'LineWidth', 1.2, ...
                    'Tag', 'selRing', 'HitTest', 'off', 'PickableParts', 'none');
                try, h.Annotation.LegendInformation.IconDisplayStyle = 'off'; catch, end %#ok<CTCH>
            end
            if ~wasHeld, hold(ax, 'off'); end
        end

        function highlightTracked(ax, X, Y, reps, sels)
            %HIGHLIGHTTRACKED  Like highlightUnits, but for the GLOBAL "track unit"
            %   ring (Tag 'trackRing') that viz.Visualizer paints on EVERY plot for
            %   the one tracked unit. Drawn as a bigger, thicker black circle so it
            %   stands out from (and is independent of) the transient per-plot
            %   'selRing'. Pass empty/NaN sels to clear it. Ignores mouse picks.
            if isempty(ax) || ~isgraphics(ax), return; end
            delete(findobj(ax, 'Tag', 'trackRing'));
            if nargin < 5 || isempty(sels) || isempty(reps), return; end
            reps = reps(:);
            wasHeld = ishold(ax); hold(ax, 'on');
            for s = reshape(sels, 1, [])
                if ~isfinite(s), continue; end
                k = find(reps == s, 1);
                if isempty(k) || k > numel(X) || k > numel(Y), continue; end
                if ~isfinite(X(k)) || ~isfinite(Y(k)), continue; end
                h = plot(ax, X(k), Y(k), 'o', 'MarkerEdgeColor', 'k', ...
                    'MarkerFaceColor', 'none', 'MarkerSize', 14, 'LineWidth', 1.6, ...
                    'Tag', 'trackRing', 'HitTest', 'off', 'PickableParts', 'none');
                try, h.Annotation.LegendInformation.IconDisplayStyle = 'off'; catch, end %#ok<CTCH>
            end
            if ~wasHeld, hold(ax, 'off'); end
        end

        function ringUnit(ax, X, Y, reps, u, labelTxt)
            %RINGUNIT  Ring unit `u` among the plotted points (X,Y parallel to
            %   `reps`) with a black circle and, if labelTxt is given, a small text
            %   label next to it. Any previous ring/label (Tags 'selRing'/'selNum')
            %   is removed first, so calling this on every redraw keeps exactly the
            %   current pick marked. The ring/label ignore mouse picks.
            if isempty(ax) || ~isgraphics(ax), return; end
            delete(findobj(ax, 'Tag', 'selRing'));
            delete(findobj(ax, 'Tag', 'selNum'));
            if nargin < 5 || isempty(u) || ~isfinite(u) || isempty(reps), return; end
            reps = reps(:); X = X(:); Y = Y(:);
            k = find(reps == u, 1);
            if isempty(k) || k > numel(X) || k > numel(Y), return; end
            if ~isfinite(X(k)) || ~isfinite(Y(k)), return; end
            wasHeld = ishold(ax); hold(ax, 'on');
            h = plot(ax, X(k), Y(k), 'o', 'MarkerEdgeColor','k', 'MarkerFaceColor','none', ...
                'MarkerSize', 11, 'LineWidth', 1.4, 'Tag','selRing', 'HitTest','off', 'PickableParts','none');
            try, h.Annotation.LegendInformation.IconDisplayStyle = 'off'; catch, end %#ok<CTCH>
            if nargin >= 6 && ~isempty(labelTxt)
                text(ax, X(k), Y(k), ['  ' char(labelTxt)], 'Color','k', 'FontSize',8, 'FontWeight','bold', ...
                    'Tag','selNum', 'HitTest','off', 'PickableParts','none', 'Clipping','on', ...
                    'VerticalAlignment','middle', 'Interpreter','none');
            end
            if ~wasHeld, hold(ax, 'off'); end
        end

        function u = nearestUnit(ax, X, Y, reps, pt)
            %NEARESTUNIT  The rep in `reps` whose plotted (X,Y) is visually closest
            %   to the click point `pt` ([x y]). Distances are normalized by the
            %   current axis ranges so x and y count equally regardless of scale.
            %   Returns NaN when there is nothing to pick.
            u = NaN;
            if isempty(reps) || nargin < 5 || numel(pt) < 2, return; end
            X = X(:); Y = Y(:); reps = reps(:);
            n = min([numel(X) numel(Y) numel(reps)]);
            if n == 0, return; end
            X = X(1:n); Y = Y(1:n); reps = reps(1:n);
            rx = 1; ry = 1;
            try, xl = ax.XLim; yl = ax.YLim; rx = max(xl(2)-xl(1), eps); ry = max(yl(2)-yl(1), eps); catch, end %#ok<CTCH>
            d = ((X - pt(1))/rx).^2 + ((Y - pt(2))/ry).^2;
            [~, k] = min(d);
            if ~isempty(k), u = reps(k); end
        end

        function jx = boxJitterX(x0, n, amount)
            %BOXJITTERX  The actual x positions of n dots horizontally jittered
            %   about x0 -- a uniform spread in [x0-amount, x0+amount], the same
            %   look as scatter(...,'jitter','on','jitterAmount',amount). Unlike the
            %   built-in option (which leaves XData un-jittered, so dots sharing a y
            %   value pile onto one point that a click cannot tell apart), this hands
            %   the positions back, so the dots can be picked and ringed exactly where
            %   they are drawn. Returns a column vector; empty for n<=0.
            if nargin < 3 || isempty(amount), amount = 0.15; end
            n = round(n);
            if n <= 0, jx = zeros(0,1); return; end
            jx = x0 + amount * (2*rand(n,1) - 1);
        end

        function s = sigStars(p)
            if ischar(p), s = p; return; end
            if ~isfinite(p),    s = 'ns';
            elseif p < 0.001,   s = '***';
            elseif p < 0.01,    s = '**';
            elseif p < 0.05,    s = '*';
            else,               s = 'ns';
            end
        end

        function d = wrap180(d)
            %WRAP180  Wrap an orientation difference (deg) to [-90, 90).
            d = mod(d + 90, 180) - 90;
        end

        % ---- significance under a repeated-obs mode (mirrors analysis.stats) ---- %
        %  These make the figure-window stars compute significance the SAME way the
        %  stats report does, so the two never disagree. Each returns the p for the
        %  selected `mode` plus isRed = (mode is 'lme' AND its significance level
        %  differs from the All/old-code method), used to draw the star in red.
        %  See STATS_MIXED_EFFECTS.md.
        function [p, isRed] = smPaired(a, b, neur, mode, pen)
            %SMPAIRED  Paired Control-vs-Laser p (signrank, or LME for 'lme').
            %   Optional 5th arg `pen` (penetration id per pair, aligned with a/b):
            %   under 'lme' the model becomes
            %       resp ~ cond + (1|pen) + (1|pen:neur)     (Satterthwaite df)
            %   so neurons sharing a penetration share an intercept; without pen
            %   (or if that fit fails) it falls back to resp ~ cond + (1|neur).
            if nargin < 4 || isempty(mode), mode = 'all'; end
            a = a(:); b = b(:); ok = isfinite(a) & isfinite(b);
            if nargin < 3 || isempty(neur), neur = []; else, neur = neur(:); end
            if nargin < 5 || isempty(pen),  pen  = []; else, pen  = pen(:);  end
            if numel(neur) == numel(ok), neur = neur(ok); else, neur = []; end
            if numel(pen)  == numel(ok), pen  = pen(ok);  else, pen  = []; end
            a = a(ok); b = b(ok);
            p = NaN; isRed = false;
            if numel(a) < 2, return; end
            pAll = NaN; try, pAll = signrank(a, b); catch, end %#ok<CTCH>
            if strcmp(mode,'lme') && ~isempty(neur) && numel(unique(neur)) >= 2
                p = pAll;
                resp = [a; b]; cond = categorical([ones(numel(a),1); 2*ones(numel(b),1)]);
                nn   = categorical([neur; neur]);
                forms = {};
                if ~isempty(pen) && all(isfinite(pen)) && numel(unique(pen)) >= 2
                    pp = categorical([pen; pen]);
                    tt = table(resp, cond, nn, pp, 'VariableNames', {'resp','cond','neur','pen'});
                    forms{end+1} = 'resp ~ cond + (1|pen) + (1|pen:neur)';
                else
                    tt = table(resp, cond, nn, 'VariableNames', {'resp','cond','neur'});
                end
                forms{end+1} = 'resp ~ cond + (1|neur)';
                for k = 1:numel(forms)
                    try
                        L = fitlme(tt, forms{k});
                        try, [~, ~, C] = fixedEffects(L, 'DFMethod', 'satterthwaite');
                        catch, C = L.Coefficients; end %#ok<CTCH>
                        r = find(~strcmp(C.Name, '(Intercept)'), 1);
                        if isempty(r), continue; end
                        p = C.pValue(r); break;
                    catch, end %#ok<CTCH>
                end
                isRed = isfinite(p) && isfinite(pAll) && ...
                    ~strcmp(viz.plots.V01util.sigStars(p), viz.plots.V01util.sigStars(pAll));
            else
                p = pAll;
            end
        end

        function [p, isRed] = smBetween(ga, gb, na, nb, mode)
            %SMBETWEEN  Between-group p (ranksum). 'lme' aggregates per neuron first
            %   (disjoint groups -> no nested random intercept; see plan sec 8).
            if nargin < 5 || isempty(mode), mode = 'all'; end
            ga = ga(:); gb = gb(:); oa = isfinite(ga); ob = isfinite(gb); ga = ga(oa); gb = gb(ob);
            if nargin >= 3 && ~isempty(na), na = na(:); na = na(oa); else, na = []; end
            if nargin >= 4 && ~isempty(nb), nb = nb(:); nb = nb(ob); else, nb = []; end
            p = NaN; isRed = false;
            if isempty(ga) || isempty(gb), return; end
            pAll = NaN; try, pAll = ranksum(ga, gb); catch, end %#ok<CTCH>
            if strcmp(mode,'lme') && ~isempty(na) && ~isempty(nb)
                p = pAll;
                try, p = ranksum(viz.plots.V01util.aggMean(ga,na), viz.plots.V01util.aggMean(gb,nb)); catch, end %#ok<CTCH>
                isRed = isfinite(p) && isfinite(pAll) && ...
                    ~strcmp(viz.plots.V01util.sigStars(p), viz.plots.V01util.sigStars(pAll));
            else
                p = pAll;
            end
        end

        function Gc = classPerNeuron(G, UU, rows)
            %CLASSPERNEURON  Resolve a PER-OBSERVATION class label (G_type) to ONE
            %   class per neuron, using the MANUSCRIPT's rule: the neuron takes the
            %   class (NL = G_type 2, D/M = G_type 1) it showed at the MAJORITY of
            %   its laser intensities; with EQUAL NL and D/M evidence it is the
            %   paper's "Mix" group and belongs to NEITHER (Gc = 0, so every
            %   G==1 / G==2 selection drops it); with no NL or D/M evidence at all
            %   it stays Unclassified (Gc = 3).
            %
            %   G_type is assigned per observation, so a neuron can come out D/M at
            %   one laser intensity and NL at another (~14% of PVA neurons). A
            %   per-neuron view must not put such a neuron in BOTH groups, and a
            %   mixed model must not turn part of a between-class contrast into a
            %   WITHIN-neuron comparison. Reproduces the published clustering
            %   (NL 271, Mix 29, Uct 54) and the Fig. 3E per-cell means.
            %   Shared by Stability07/Categorization06/GainLaminar03/Composition03
            %   and analysis.stats.figureCatalog.
            Gc = G;
            rows = rows(:); rows = rows(isfinite(G(rows)));
            if isempty(rows), return; end
            [u, ~, g] = unique(UU(rows), 'stable');
            for j = 1:numel(u)
                rr  = rows(g == j);
                cls = G(rr); cls = cls(isfinite(cls));
                if isempty(cls), continue; end
                a = sum(cls == 2); b = sum(cls == 1);    % NL vs D/M evidence
                if     a > b, Gc(rr) = 2;
                elseif b > a, Gc(rr) = 1;
                elseif a > 0, Gc(rr) = 0;                % Mix -> in neither group
                else,         Gc(rr) = 3;                % Unclassified
                end
            end
        end

        function ex = noiseMask(D)
            %NOISEMASK  Nx1 true for the RECORDINGS the published analysis
            %   discarded as noise (visual-responsiveness screen): D-rows 417,
            %   1026, 1065, 1283, 1565. These are unit x laser-intensity SAMPLES,
            %   not whole neurons -- a neuron keeps every other intensity at which
            %   it was recorded (e.g. row 1026's neuron has 10 recordings; only
            %   that one is dropped). Excluding these 5 rows reproduces the
            %   published Table 1 sample counts exactly (PVA 200/62/327).
            %   Applied once, in viz.Visualizer.maskFor, so every tab and every
            %   stats report sees the population the manuscript reports.
            N = viz.plots.V01util.nU(D);
            rows = [417 1026 1065 1283 1565];
            ex = ismember((1:N)', rows(rows <= N));
            ex = ex(:);
        end

        function pk = penKey(D)
            %PENKEY  Nx1 penetration identity = animal x penetration x hemisphere.
            %   DS (Dataset) = animal, P (Penetration) = the penetration index
            %   inside it and EI = hemisphere, so the composite counts the 11
            %   distinct recording sites. NaN(N,1) when those ids are not loaded.
            %   Same key viz.plots.EffectSizeTab builds for its site counts.
            N = viz.plots.V01util.nU(D);
            if ~isfield(D,'Dataset') || ~isfield(D,'Penetration'), pk = nan(N,1); return; end
            isI = viz.plots.V01util.isInhib(D); isI = isI(:);
            ds  = viz.plots.V01util.colv(D, 'Dataset');
            pp  = viz.plots.V01util.colv(D, 'Penetration');
            pk  = (ds*100 + pp)*10 + double(isI);
        end

        function [p, isRed, note] = smBetweenMM(va, vb, ida, idb, pena, penb)
            %SMBETWEENMM  Between-group p from a MIXED-EFFECTS MODEL on the
            %   OBSERVATIONS, rather than rank-summing a per-neuron aggregate:
            %       v ~ grp + (1|pen) + (1|pen:unit)      (Satterthwaite df)
            %   so a neuron recorded at several laser intensities is not counted
            %   as several independent samples, and neurons sharing a penetration
            %   share an intercept (Reviewer #1's request; STATS_MIXED_EFFECTS.md).
            %   A neuron contributing observations to BOTH groups keeps ONE random
            %   intercept -- ids are deliberately not made unique per group.
            %   Falls back to (1|unit) alone, then to a per-neuron rank-sum, if the
            %   model will not fit. `note` names the model actually used. isRed
            %   flags a significance level differing from the pooled-observation
            %   rank-sum, exactly as smPaired / smBetween do.
            p = NaN; isRed = false; note = '';
            va = va(:); vb = vb(:);
            ka = isfinite(va); kb = isfinite(vb);
            ida  = i_pick(ida,  ka, numel(va));  idb  = i_pick(idb,  kb, numel(vb));
            pena = i_pick(pena, ka, numel(va));  penb = i_pick(penb, kb, numel(vb));
            va = va(ka); vb = vb(kb);
            if isempty(va) || isempty(vb), return; end
            if isempty(ida), ida = (1:numel(va))'; end
            if isempty(idb), idb = numel(va) + (1:numel(vb))'; end

            pAll = NaN; try, pAll = ranksum(va, vb); catch, end %#ok<CTCH>

            v    = [va; vb];
            grp  = categorical([ones(numel(va),1); 2*ones(numel(vb),1)]);
            unit = categorical([ida(:); idb(:)]);
            pen  = [pena(:); penb(:)];
            forms = {};
            if numel(pen) == numel(v) && all(isfinite(pen)) && numel(unique(pen)) >= 2
                tt = table(v, grp, unit, categorical(pen), ...
                           'VariableNames', {'v','grp','unit','pen'});
                forms{end+1} = 'v ~ grp + (1|pen) + (1|pen:unit)';
            else
                tt = table(v, grp, unit, 'VariableNames', {'v','grp','unit'});
            end
            forms{end+1} = 'v ~ grp + (1|unit)';
            for k = 1:numel(forms)
                try
                    L = fitlme(tt, forms{k});
                    % Satterthwaite df is an option of fixedEffects, NOT of fitlme
                    % (passing it to fitlme errors); fall back to the model's own
                    % residual-df coefficients if that call is unavailable.
                    C = []; df = 'satterthwaite';
                    try, [~, ~, C] = fixedEffects(L, 'DFMethod', 'satterthwaite');
                    catch, C = L.Coefficients; df = 'residual'; end %#ok<CTCH>
                    r = find(~strcmp(C.Name, '(Intercept)'), 1);
                    if isempty(r), continue; end
                    p = C.pValue(r); note = sprintf('%s [%s df]', forms{k}, df); break;
                catch, end %#ok<CTCH>
            end
            if ~isfinite(p)
                try
                    p = ranksum(viz.plots.V01util.aggMean(va, ida), ...
                                viz.plots.V01util.aggMean(vb, idb));
                    note = 'per-neuron rank-sum (model would not fit)';
                catch, end %#ok<CTCH>
            end
            isRed = isfinite(p) && isfinite(pAll) && ...
                ~strcmp(viz.plots.V01util.sigStars(p), viz.plots.V01util.sigStars(pAll));
        end

        function m = aggMean(v, g)
            %AGGMEAN  Per-neuron mean of v grouped by identity g.
            v = v(:); g = g(:);
            [~, ~, gi] = unique(g, 'stable');
            m = accumarray(gi, v, [], @(z) mean(z, 'omitnan'));
        end

        function h = drawSig(ax, x, y, p, isRed, align)
            %DRAWSIG  Draw a significance star; RED+bold when isRed (mixed-effects
            %   significance differs from the All method), else black.
            if nargin < 6 || isempty(align), align = 'center'; end
            if isRed, col = [0.8 0 0]; fw = 'bold'; else, col = [0 0 0]; fw = 'normal'; end
            h = text(ax, x, y, viz.plots.V01util.sigStars(p), ...
                'HorizontalAlignment', align, 'Color', col, 'FontWeight', fw);
        end

        % ---- shared panel drawers (used by the ported V02/V03 tabs) ---- %
        function sz = paperDotArea(ax, ratio)
            %PAPERDOTAREA  scatter SizeData (pt^2, area) for a 2-D SCATTER dot whose
            %   DIAMETER is a fixed fraction of the axes plot-box SMALLER dimension, so
            %   dots scale WITH the panel and keep the paper's dot:plot ratio. PDF: Fig2
            %   scatter 3.2pt on the 97pt (smaller) side of a 201x97 box = 3.3%.
            %   (Box/strip plots use paperDotAreaBox instead -- see below.)
            if nargin < 2 || isempty(ratio), ratio = 0.033; end
            d = 3.2;                                      % fallback diameter (pt)
            try
                u = ax.Units; ax.Units = 'points'; p = ax.Position; ax.Units = u;
                if numel(p) == 4
                    m = min(p(3), p(4));
                    if m > 4, d = ratio * m; end
                end
            catch
            end
            sz = pi/4 * d^2;                              % marker area = pi/4 * diameter^2
        end
        function sz = paperDotAreaBox(ax, xrange, ratio)
            %PAPERDOTAREABOX  scatter SizeData (pt^2) for BOX/STRIP dots, sized to the
            %   group-COLUMN width (one x-data-unit) rather than plot height, so dots
            %   don't blob in narrow jitter columns. PDF-measured ~6% of the group
            %   spacing (Fig4: 2.3pt dot on a 2-group plot ~78pt wide -> 39pt/group).
            %   xrange = the axes' final x-data range (diff of xlim).
            if nargin < 3 || isempty(ratio), ratio = 0.06; end
            d = 2.5;                                      % fallback diameter (pt)
            try
                u = ax.Units; ax.Units = 'points'; p = ax.Position; ax.Units = u;
                if numel(p) == 4 && p(3) > 4 && xrange > 0
                    d = ratio * (p(3) / xrange);          % ~6% of one x-data-unit (group spacing)
                end
            catch
            end
            sz = pi/4 * d^2;
        end
        function jitX = drawBox(ax, groups, data, colors, ylab, ttl, dotSz, boxRatio)
            %DRAWBOX  Box plot (per group) + jittered scatter + zero line.
            %   Returns jitX, a 1xnGroups cell of the ACTUAL (jittered) x position of
            %   every dot (parallel to data{i}), so a caller can make the dots
            %   clickable at their true on-screen location -- see enableDotPick and
            %   viz.plots.V01util.boxJitterX.
            %   boxRatio (optional): paper-mode dot dia as a fraction of group-column
            %   width. Default = paperDotAreaBox's own 0.06 (Fig 4/5 style); the
            %   Dashboard passes the larger Fig 2/3 value (~0.105).
            if nargin < 7, dotSz = 9; end
            if nargin < 8, boxRatio = []; end
            % paper dots: scatter's 4th arg is AREA (pt^2); dotSz~8 => ~3.2pt diameter,
            % which matches the published dots. (The old 0.63x shrink made them ~2.6pt
            % with no room for a ring -- dropped.)
            hold(ax,'on');
            vals = []; grp = {};
            for i = 1:numel(groups)
                d = data{i}; if isempty(d), d = NaN; end
                vals = [vals; d(:)]; %#ok<AGROW>
                grp  = [grp; repmat(groups(i), numel(d), 1)]; %#ok<AGROW>
            end
            try
                hbp = boxplot(ax, vals, grp, 'Colors','k', 'Symbol','', ...
                    'GroupOrder', groups, 'Positions', 1:numel(groups), 'Widths', 0.5);
                set(hbp, 'PickableParts','none');               % box lines must not swallow clicks on interior dots
                h = findobj(ax, 'Tag', 'Box');
                for j = 1:numel(h)
                    patch(ax, get(h(j),'XData'), get(h(j),'YData'), ...
                        colors{numel(h)-j+1}, 'FaceAlpha', 0.05, 'PickableParts','none');   % FaceAlpha .05; click-through
                end
            catch
            end
            if viz.paperStyle()                                 % paper: RED median line
                try, set(findobj(ax,'Tag','Median'), 'Color', [1 0 0], 'LineWidth', 1); catch, end
            end
            edg = {};
            if viz.paperStyle()
                edg = {'MarkerEdgeColor','w', 'LineWidth',0.75};        % white ring per dot (paper=0.25pt; 0.75pt so it reads on screen)
                dotSz = viz.plots.V01util.paperDotAreaBox(ax, numel(groups), boxRatio);   % paper: dot dia = boxRatio of group-column width (default 6%; Fig 2/3 = ~10.5%)
            end
            jitX = cell(1, numel(groups));
            for i = 1:numel(groups)
                d = data{i};
                jx = viz.plots.V01util.boxJitterX(i, numel(d), 0.15);   % own jitter -> known positions
                jitX{i} = jx;
                if ~isempty(d)
                    scatter(ax, jx, d(:), dotSz, colors{i}, 'filled', edg{:}, 'PickableParts','none');
                end
            end
            ng = numel(groups);
            xlim(ax, [0.5 ng+0.5]);
            line(ax, xlim(ax), [0 0], 'Color',[0 0 0 0.3], 'LineStyle','--', 'PickableParts','none');   % zero line spans XLim; click-through
            isBand = all(cellfun(@(g) ~isempty(regexp(g, '^PV[EI][-\s]', 'once')), groups));
            if viz.paperStyle() && isBand                       % paper (dFr-band box): short colored labels H/M/L/...
                set(ax, 'XTick', 1:ng, 'XTickLabel', repmat({''},1,ng));
                for i = 1:ng
                    short = regexprep(groups{i}, '^PV[EI][-\s]?', ''); short = strrep(short, 'extra-H', 'XH');
                    text(ax, (i-0.5)/ng, -0.055, short, 'Units','normalized', 'Color', colors{i}, ...
                        'HorizontalAlignment','center', 'VerticalAlignment','top', 'FontWeight','bold', 'Clipping','off');
                end
            elseif viz.paperStyle()                             % paper (other box tabs): horizontal labels, no rotation
                set(ax, 'XTick', 1:ng, 'XTickLabel', groups, 'XTickLabelRotation', 0);
            else
                set(ax, 'XTick', 1:ng, 'XTickLabel', groups, 'XTickLabelRotation', 30);
            end
            ylabel(ax, ylab); title(ax, ttl);
            viz.plots.V01util.medianOnTop(ax);          % red median line ABOVE the dots
            hold(ax,'off');
        end

        function medianOnTop(ax)
            %MEDIANONTOP  Make the box-plot median line(s) sit ON TOP of the scatter
            %   dots. boxplot nests its lines in an hggroup, so `uistack` can only
            %   reorder them WITHIN that group -- it cannot lift the median above the
            %   dots (a sibling of the group). Instead RE-DRAW each median as a fresh
            %   line: added last, it renders on top in both the live uiaxes and the PDF.
            %   PickableParts/HitTest off so it never swallows a click on an interior dot.
            try
                med = findobj(ax, 'Tag', 'Median');
                for k = 1:numel(med)
                    m = med(k); xd = get(m,'XData'); yd = get(m,'YData');
                    if isempty(xd), continue; end
                    line(ax, xd, yd, 'Color', get(m,'Color'), 'LineWidth', get(m,'LineWidth'), ...
                        'LineStyle', get(m,'LineStyle'), 'Tag','MedianTop', ...
                        'PickableParts','none', 'HitTest','off');
                end
            catch
            end
        end

        function p = drawPairHist(ax, ctrlVals, laserVals, ctrlCol, laserCol, bw, ttl)
            %DRAWPAIRHIST  Control(black) vs laser overlaid histogram + medians +
            %   signrank marker. ctrlVals/laserVals are paired per unit. Returns p.
            hold(ax,'on');
            ok = isfinite(ctrlVals) & isfinite(laserVals);
            a = ctrlVals(ok); b = laserVals(ok);
            args = {}; if ~isempty(bw), args = {'BinWidth', bw}; end
            if ~isempty(a), histogram(ax, a, args{:}, 'FaceColor', ctrlCol,  'FaceAlpha', 0.3); end
            if ~isempty(b), histogram(ax, b, args{:}, 'FaceColor', laserCol, 'FaceAlpha', 0.3); end
            p = NaN; try, p = signrank(a, b); catch, end
            yl = ylim(ax);
            if ~isempty(a), scatter(ax, median(a), 0.92*yl(2), 24, ctrlCol,  'v', 'filled', 'MarkerFaceAlpha', 0.5); end
            if ~isempty(b), scatter(ax, median(b), 0.84*yl(2), 24, laserCol, 'v', 'filled', 'MarkerFaceAlpha', 0.6); end
            title(ax, sprintf('%s %s', ttl, viz.plots.V01util.sigStars(p)));
            ylabel(ax,'count'); hold(ax,'off');
        end

        function drawSelScatter(ax, x, y, cdata, lims, ttl, xlab, ylab, clab)
            %DRAWSELSCATTER  x-vs-y scatter colored by cdata, with identity line.
            hold(ax,'on');
            ok = isfinite(x) & isfinite(y); x=x(ok); y=y(ok); c=cdata(ok);
            if ~isempty(x)
                scatter(ax, x, y, 18, c, 'filled', 'MarkerFaceAlpha', 0.6);
                try, colormap(ax,'turbo'); cb = colorbar(ax); cb.Label.String = clab; clim(ax,[-100 100]); catch, end
            end
            if ~isempty(lims), plot(ax, lims, lims, 'k-'); xlim(ax,lims); ylim(ax,lims); end
            xlabel(ax,xlab); ylabel(ax,ylab); title(ax, ttl); hold(ax,'off');
        end

        function drawPaired(ax, ctrl, laser, x0, col)
            %DRAWPAIRED  Paired control->laser dots joined by faint lines at
            %   x = x0 (control) and x0+0.8 (laser), with mean+/-SEM crossbars.
            ok = isfinite(ctrl) & isfinite(laser); a = ctrl(ok); b = laser(ok);
            if isempty(a), return; end
            hold(ax,'on');
            xa = x0; xb = x0 + 0.8;
            for k = 1:numel(a)
                plot(ax, [xa xb], [a(k) b(k)], '-', 'Color', [col 0.25], 'LineWidth', 0.3);
            end
            scatter(ax, xa*ones(numel(a),1), a, 10, [0 0 0], 'filled', 'MarkerFaceAlpha',0.5);
            scatter(ax, xb*ones(numel(b),1), b, 10, col,     'filled', 'MarkerFaceAlpha',0.5);
            plot(ax, [xa xb], [mean(a) mean(b)], '-', 'Color', [0.85 0 0], 'LineWidth', 2);
        end

        function drawLaminarBars(ax, M, catLabels, layerLabels, colors, ylab, ttl)
            %DRAWLAMINARBARS  Grouped %-bars: M is [nCat x nLayer] counts, shown as
            %   percentage within each layer. One bar group per layer, one colored
            %   bar per category; N counts labeled above each layer.
            hold(ax,'on');
            colsum = sum(M, 1); colsum(colsum == 0) = NaN;
            P = 100 * M ./ colsum;                 % nCat x nLayer
            hb = bar(ax, P');                      % nLayer groups, nCat series
            for k = 1:min(numel(hb), numel(colors))
                hb(k).FaceColor = colors{k}; hb(k).FaceAlpha = 0.4;
            end
            for L = 1:size(M,2)
                n = sum(M(:,L));
                if isfinite(n)
                    text(ax, L, 5, sprintf('n=%d', n), 'HorizontalAlignment','center', 'FontSize', 7);
                end
            end
            set(ax, 'XTick', 1:numel(layerLabels), 'XTickLabel', layerLabels);
            ylabel(ax, ylab); title(ax, ttl);
            try, legend(ax, catLabels, 'Location','northeast', 'Box','off', 'FontSize', 7); catch, end
            hold(ax,'off');
        end

        function drawPopMean(ax, M, lineCol, faceCol, win, ttl, ylab)
            %DRAWPOPMEAN  Mean +/- SEM of the columns of M over rows `win`,
            %   x = (win-180) deg from peak. M is 360xK (peak-centered at 180).
            if isempty(M) || size(M,2)==0, title(ax, sprintf('%s (n=0)', ttl)); return; end
            x = (win(:) - 180);
            Mw = M(win, :);
            Y  = mean(Mw, 2, 'omitnan');
            SE = std(Mw, 0, 2, 'omitnan') / sqrt(size(Mw,2));
            viz.plots.V01util.plotSE(ax, x, Y, SE, lineCol, faceCol, 0.15);
            xlim(ax, [x(1) x(end)]);
            if nargin >= 7 && ~isempty(ylab), ylabel(ax, ylab); end
            title(ax, sprintf('%s (n=%d)', ttl, size(M,2)));
        end

        % ---- Animal / Penetration / Task data-selection (shared by PlotTab) ---- %
        %  Mirror the LaminarViewsTab selectors so every tab can restrict itself to
        %  one animal / penetration / task subset. All return '(all)'-prefixed item
        %  lists or a logical Nx1 mask (true where the unit passes the selection).
        function items = dsAnimalItems(D)
            if isfield(D, 'Animal')
                a = unique(string(D.Animal(:)), 'stable'); a(ismissing(a) | a == "") = []; items = cellstr(a(:)');
            elseif isfield(D, 'Dataset')
                u = unique(double(D.Dataset(:))); u = u(isfinite(u)); items = arrayfun(@num2str, u(:)', 'UniformOutput', false);
            else
                items = {};
            end
            items = [{'(all)'}, items];
        end

        function m = dsAnimalMask(D, N, animal)
            if nargin < 2 || isempty(N), N = viz.plots.V01util.nU(D); end
            if strcmp(char(string(animal)), '(all)'), m = true(N,1); return; end
            if isfield(D,'Animal'),       m = (string(D.Animal(:)) == string(animal));
            elseif isfield(D,'Dataset'),  m = (double(D.Dataset(:)) == str2double(string(animal)));
            else,                         m = true(N,1);
            end
            m = m(:);
        end

        function items = dsPenItems(D, animal)
            N = viz.plots.V01util.nU(D); m = viz.plots.V01util.dsAnimalMask(D, N, animal);
            if isfield(D,'Penetration')
                p = unique(double(D.Penetration(m))); p = p(isfinite(p)); items = arrayfun(@num2str, p(:)', 'UniformOutput', false);
            else
                items = {};
            end
            items = [{'(all)'}, items];
        end

        function items = dsTaskItems(D, animal, pen)
            N = viz.plots.V01util.nU(D); m = viz.plots.V01util.dsAnimalMask(D, N, animal);
            pv = NaN; if nargin >= 3, pv = viz.plots.V01util.dsPenVal(pen); end
            if isfield(D,'Penetration') && ~isnan(pv), m = m & (double(D.Penetration(:)) == pv); end
            tk = {};
            if isfield(D,'Tasknumb')
                t = unique(string(D.Tasknumb(m)), 'stable'); t(ismissing(t) | t == "") = []; tk = cellstr(t(:)');
            end
            items = [{'(all tasks)'}, tk];
        end

        function p = dsPenVal(s)
            if strcmp(char(string(s)), '(all)'), p = NaN; else, p = str2double(string(s)); end
        end

        function m = dsSelectionMask(D, N, animal, pen, tasks)
            %DSSELECTIONMASK  Nx1 logical: units passing animal AND pen AND task(s).
            %   '(all)' / '(all tasks)' / empty tasks impose no constraint.
            if nargin < 2 || isempty(N), N = viz.plots.V01util.nU(D); end
            m = viz.plots.V01util.dsAnimalMask(D, N, animal);
            pv = viz.plots.V01util.dsPenVal(pen);
            if isfield(D,'Penetration') && ~isnan(pv), m = m & (double(D.Penetration(:)) == pv); end
            useTasks = ~isempty(tasks) && ~(numel(tasks)==1 && any(strcmp(tasks,'(all tasks)')));
            if isfield(D,'Tasknumb') && useTasks
                m = m & ismember(string(D.Tasknumb(:)), string(tasks));
            end
            m = m(:);
        end
    end
end

% ----------------------------------------------------------------------- %
function out = i_pick(v, keep, n)
%I_PICK  v(keep) when v is per-observation, [] when it is absent/mismatched.
    if isempty(v) || numel(v) ~= n, out = []; else, v = v(:); out = v(keep); end
end
