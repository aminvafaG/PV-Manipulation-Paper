function res = runTest(spec, D, state, mode)
%RUNTEST  Run one statistic spec under one repeated-observation mode.
%
%   res = analysis.stats.runTest(spec, D, state, mode)
%
%   This is the compute core for the statistical reporting feature
%   (STATS_REPORTING_PLAN.md). It is UI-free and deterministic so it can be
%   unit-tested headless and reused identically by every figure report and by
%   the Paper Stats tab.
%
%   spec  : one entry from analysis.stats.figureCatalog. The
%           selection + per-mode reduction live in spec.build (a closure), so
%           this function only owns the TEST MATH. Fields:
%             .kind   'paired'|'between'|'corr'|'anova'|'descriptive'
%             .build  @(D,state,mode) -> a data struct shaped for the kind:
%                       paired : .a (laser) .b (control) .neur (U_unity)
%                       between: .ga .gb [.neur]            (build already reduced)
%                                OPTIONALLY .obsA/.obsB (observation-level
%                                values) + .idA/.idB (U_unity) + .penA/.penB
%                                (penetration): when present, the 'lme' mode
%                                fits a mixed model to those instead of
%                                rank-summing the per-neuron aggregate.
%                       corr   : .x .y .neur
%                       anova  : .groups {1xK} .labels {1xK} [.neur]
%                       descriptive: .groups {1xK} .labels {1xK}
%           build returns data ALREADY reduced for `mode` (all=obs-level,
%           first/mean=per-neuron, lme=obs-level for paired/corr). The engine
%           only switches signrank<->fitlme (paired) and fitlm<->fitlme (corr);
%           for between/anova, lme == mean (per-neuron aggregate then classic
%           test), so build returns the aggregate for both. See plan sec 8.
%   mode  : 'all'|'first'|'mean'|'lme'
%
%   res fields: n, neurons, stat, p, mA, mB, meanA, meanB, seA, seB, descr,
%           nObs, ok, note.
%           For 'between' mA/mB are the two group MEDIANS (what ranksum ranks)
%           and meanA/meanB +/- seA/seB the matching group means; for 'paired'
%           mA/mB are already the laser/control means.
%           `descr` is THIS mode's descriptive statistics as a compact
%           mean +/- s.e.m. string, built here so the per-mode columns and the
%           Effect column of analysis.stats.compute cannot drift apart in
%           format: every mode shows its OWN mean +/- s.e.m., not the All-mode
%           one. Quote it straight into a manuscript.
%           est/estSE/tStat/df/ciLo/ciHi/model are the mixed model's FIXED-EFFECT
%           estimate and its 95%% CI, signed as A-minus-B (paired: laser minus
%           control), filled only when a model was actually fitted. They are what
%           a Nature-style statistics table needs; analysis.stats.fig2Table
%           assembles them so the table and the report come from ONE fit.
%
%   See also: analysis.stats.compute, analysis.stats.figureCatalog

    res = struct('n',0,'neurons',NaN,'stat',NaN,'p',NaN, ...
                 'mA',NaN,'mB',NaN,'meanA',NaN,'meanB',NaN, ...
                 'seA',NaN,'seB',NaN,'nObs',NaN,'descr','','ok',false,'note','', ...
                 'est',NaN,'estSE',NaN,'tStat',NaN,'df',NaN,'ciLo',NaN,'ciHi',NaN, ...
                 'model','');
    if isempty(spec) || ~isfield(spec,'build') || isempty(spec.build)
        res.note = 'no build fn'; return;
    end
    try
        data = spec.build(D, state, mode);
    catch e
        res.note = ['build: ' e.message]; return;
    end
    % the spec names the two sides of a paired row; the build only knows values
    if isstruct(data) && isfield(spec,'pairLabels') && numel(spec.pairLabels) == 2
        data.pairLabels = spec.pairLabels;
    end
    switch lower(spec.kind)
        case 'paired',               res = i_paired(data, mode, res);
        case 'between',              res = i_between(data, mode, res);
        case {'corr','regression'},  res = i_corr(data, mode, res);
        case 'anova',                res = i_anova(data, mode, res);
        case 'descriptive',          res = i_descr(data, res);
        otherwise,                   res.note = ['unknown kind ' char(spec.kind)];
    end
end

% ===================================================================== %
function res = i_paired(data, mode, res)
    a = data.a(:); b = data.b(:);
    neur = []; pen = [];
    if isfield(data,'neur'), neur = data.neur(:); end
    if isfield(data,'pen'),  pen  = data.pen(:);  end
    ok = isfinite(a) & isfinite(b); a = a(ok); b = b(ok);
    if numel(neur) == numel(ok), neur = neur(ok); else, neur = []; end
    if numel(pen)  == numel(ok), pen  = pen(ok);  else, pen  = []; end
    res.n = numel(a);
    if ~isempty(neur), res.neurons = numel(unique(neur)); else, res.neurons = res.n; end
    if isempty(a), return; end
    res.mA = mean(a,'omitnan'); res.mB = mean(b,'omitnan');
    res.seA = std(a,'omitnan')/sqrt(numel(a)); res.seB = std(b,'omitnan')/sqrt(numel(b));
    res.meanA = res.mA; res.meanB = res.mB;               % paired: mA/mB ARE the means
    lab = {'laser','ctrl'};                               % {a, b}; spec may rename
    if isfield(data,'pairLabels') && numel(data.pairLabels) == 2, lab = data.pairLabels; end
    res.descr = sprintf('%s %s -> %s %s', lab{2}, i_ms(res.mB, res.seB), lab{1}, i_ms(res.mA, res.seA));
    res.stat = median(a - b, 'omitnan');                  % median paired delta
    if numel(a) < 2, res.note = 'n<2'; return; end
    if strcmp(mode,'lme')
        if isempty(neur) || numel(unique(neur)) < 2
            try, res.p = signrank(a,b); res.ok = true; res.note = 'lme: no repeats -> signrank'; catch, end %#ok<CTCH>
            return;
        end
        % Model: resp ~ cond + (1|pen) + (1|pen:neur) on the observations when a
        % penetration id came with the build (Satterthwaite df), else (1|neur);
        % final fallback is the plain signrank.
        resp = [a; b];
        cond = categorical([ones(numel(a),1); 2*ones(numel(b),1)]);
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
                lme = fitlme(tt, forms{k});
                try, [~, ~, C] = fixedEffects(lme, 'DFMethod', 'satterthwaite'); df = 'satterthwaite';
                catch, C = lme.Coefficients; df = 'residual'; end %#ok<CTCH>
                r = find(~strcmp(C.Name, '(Intercept)'), 1);
                if isempty(r), continue; end
                res.p = C.pValue(r); res.ok = true;
                res.note = sprintf('%s [%s df]', forms{k}, df);
                % cond level 1 = a (laser), level 2 = b (control), so the fitted
                % coefficient is control-minus-laser; negate it (and swap/negate
                % the CI, negate t) to report laser-minus-control, matching the
                % mA/mB and descr convention above.
                res.model = forms{k};
                try
                    res.est   = -C.Estimate(r); res.estSE = C.SE(r);
                    res.tStat = -C.tStat(r);    res.df    = C.DF(r);
                    res.ciLo  = -C.Upper(r);    res.ciHi  = -C.Lower(r);
                catch, end %#ok<CTCH>
                return;
            catch, end %#ok<CTCH>
        end
        try, res.p = signrank(a,b); res.ok = true; res.note = 'lme failed -> signrank'; ...
        catch e, res.note = ['lme: ' e.message]; end %#ok<CTCH>
    else
        try, res.p = signrank(a,b); res.ok = true; catch e, res.note = e.message; end %#ok<CTCH>
    end
end

% ===================================================================== %
function res = i_between(data, mode, res)
    ga = data.ga(:); gb = data.gb(:);
    ga = ga(isfinite(ga)); gb = gb(isfinite(gb));
    res.n = numel(ga) + numel(gb);
    if isfield(data,'neur') && ~isempty(data.neur), res.neurons = numel(unique(data.neur)); end
    % Per-group descriptives: the MEDIAN (what the ranksum ranks, and what the
    % figures mark) plus the MEAN +/- s.e.m. Filled per group so a one-sided
    % selection still reports the side that exists.
    if ~isempty(ga)
        res.mA = median(ga); res.meanA = mean(ga); res.seA = std(ga)/sqrt(numel(ga));
    end
    if ~isempty(gb)
        res.mB = median(gb); res.meanB = mean(gb); res.seB = std(gb)/sqrt(numel(gb));
    end
    res.descr = sprintf('%s vs %s', i_ms(res.meanA, res.seA), i_ms(res.meanB, res.seB));
    if isempty(ga) || isempty(gb), return; end
    res.stat = res.mA - res.mB;
    % Mixed-effects: when the build supplied OBSERVATION-level values with unit
    % and penetration ids, fit  v ~ grp + (1|pen) + (1|pen:unit)  to those rather
    % than rank-summing the per-neuron aggregate (the descriptives above stay per
    % neuron, which is the level the effect is reported at). Builds that do not
    % supply them keep the classic rank-sum in every mode.
    if strcmp(mode,'lme') && isfield(data,'obsA') && ~isempty(data.obsA) ...
            && isfield(data,'obsB') && ~isempty(data.obsB)
        [pm, ~, nt] = viz.plots.V01util.smBetweenMM(data.obsA, data.obsB, ...
            data.idA, data.idB, data.penA, data.penB);
        if isfinite(pm)
            res.p = pm; res.ok = true;
            res.nObs = numel(data.obsA) + numel(data.obsB);   % n the MODEL used
            res.note = sprintf('%s  (%d obs)', nt, res.nObs);
            return;
        end
    end
    try, res.p = ranksum(ga, gb); res.ok = true; catch e, res.note = e.message; end %#ok<CTCH>
end

% ===================================================================== %
function res = i_corr(data, mode, res)
%I_CORR  Correlation / regression row.
%   A build may ask for the estimator its PANEL draws, so the report and the
%   figure cannot print different numbers for the same fit:
%     data.fitKind  'ols' (default) or 'exp' -- y = a*exp(b*x) via fitnlm, p on
%                   b, which is what the f05 gain-beta panels plot and print.
%                   The 'lme' mode linearizes it as log(y) ~ x.
%     data.fitMask  logical over x/y: the points the FIT uses (e.g. the gain
%                   panels' y < 17 cutoff). r and the descriptives still cover
%                   every point, again matching the panel.
%     data.showSlope  add the panel's "s =" (mean slope of the drawn curve over
%                   the same x grid) to the descriptive, so a gain row reads
%                   like the s / r / p the panel prints. Not shown for 'lme',
%                   whose cell reports the mixed model on the OBSERVATIONS (the
%                   report-wide convention) rather than the per-neuron fit the
%                   panel draws in that mode -- read Mean/neuron for the latter.
    x = data.x(:); y = data.y(:);
    neur = []; pen = []; fm = true(numel(x),1);
    if isfield(data,'neur'), neur = data.neur(:); end
    if isfield(data,'pen'),  pen  = data.pen(:);  end
    if isfield(data,'fitMask') && numel(data.fitMask) == numel(x), fm = logical(data.fitMask(:)); end
    fk = 'ols';
    if isfield(data,'fitKind') && ~isempty(data.fitKind), fk = lower(char(data.fitKind)); end
    ok = isfinite(x) & isfinite(y); x = x(ok); y = y(ok); fm = fm(ok);
    if numel(neur) == numel(ok), neur = neur(ok); else, neur = []; end
    if numel(pen)  == numel(ok), pen  = pen(ok);  else, pen  = []; end
    res.n = numel(x);
    if ~isempty(neur), res.neurons = numel(unique(neur)); else, res.neurons = res.n; end
    res.mA = mean(y,'omitnan'); res.mB = mean(x,'omitnan');
    if numel(x) < 3, res.note = 'n<3'; return; end
    r = NaN; try, R = corrcoef(x,y); r = R(1,2); catch, end %#ok<CTCH>
    res.stat = r;                                          % keep r in the stat column (comparable)
    res.meanA = mean(y,'omitnan'); res.seA = std(y,'omitnan')/sqrt(numel(y));
    res.meanB = mean(x,'omitnan'); res.seB = std(x,'omitnan')/sqrt(numel(x));
    res.descr = sprintf('r=%.3g; y %s', r, i_ms(res.meanA, res.seA));
    isExp = strcmp(fk,'exp');
    wantS = isfield(data,'showSlope') && ~isempty(data.showSlope) && data.showSlope;
    if strcmp(mode,'lme')
        % Model: y ~ x + (1|pen) + (1|pen:neur) when a penetration id came with
        % the build (Satterthwaite df), else (1|neur); final fallback plain OLS.
        % For an exponential panel fit the response is log(y) (y>0 only), i.e.
        % the same model the panel draws, linearized so it can carry the random
        % effects.
        yy = y; xx = x; nn = neur; pp = pen; resp = 'y';
        if isExp
            q = fm & y > 0; yy = log(y(q)); xx = x(q); resp = 'log(y)';
            if ~isempty(nn), nn = nn(q); end
            if ~isempty(pp), pp = pp(q); end
        end
        if numel(xx) < 3 || isempty(nn) || numel(unique(nn)) < 2
            try
                m = fitlm(xx, yy); res.p = m.Coefficients.pValue(2); res.ok = true;
                res.note = sprintf('lme: no repeats -> OLS on %s', resp);
            catch, end %#ok<CTCH>
            return;
        end
        forms = {};
        if ~isempty(pp) && all(isfinite(pp)) && numel(unique(pp)) >= 2
            tt = table(yy, xx, categorical(nn), categorical(pp), ...
                       'VariableNames', {'y','x','neur','pen'});
            forms{end+1} = 'y ~ x + (1|pen) + (1|pen:neur)';
        else
            tt = table(yy, xx, categorical(nn), 'VariableNames', {'y','x','neur'});
        end
        forms{end+1} = 'y ~ x + (1|neur)';
        for k = 1:numel(forms)
            try
                lme = fitlme(tt, forms{k});
                try, [~, ~, C] = fixedEffects(lme, 'DFMethod', 'satterthwaite'); df = 'satterthwaite';
                catch, C = lme.Coefficients; df = 'residual'; end %#ok<CTCH>
                ri = find(strcmp(C.Name,'x'), 1); if isempty(ri), ri = 2; end
                res.p = C.pValue(ri); res.ok = true;
                res.model = strrep(forms{k}, 'y ~', [resp ' ~']);
                res.note = sprintf('%s [%s df]', res.model, df);
                try
                    res.est = C.Estimate(ri); res.estSE = C.SE(ri);
                    res.tStat = C.tStat(ri);  res.df = C.DF(ri);
                    res.ciLo = C.Lower(ri);   res.ciHi = C.Upper(ri);
                catch, end %#ok<CTCH>
                return;
            catch, end %#ok<CTCH>
        end
        try, m = fitlm(xx,yy); res.p = m.Coefficients.pValue(2); res.ok = true; res.note = 'lme failed -> OLS'; ...
        catch e, res.note = ['lme: ' e.message]; end %#ok<CTCH>
    elseif isExp
        % the panel's own fit: y = a*exp(b*x) on the masked points, p on b
        try
            mdl = fitnlm(x(fm), y(fm), @(b,xx) b(1).*exp(b(2).*xx), [1 -0.1]);
            res.p = mdl.Coefficients.pValue(min(2,end)); res.ok = true;
            res.note = sprintf('y = a*exp(b*x) (fitnlm), p on b; fit n=%d of %d', sum(fm), numel(x));
            if wantS
                sl = i_expSlope(mdl, x);
                if ~isempty(sl), res.descr = sprintf('%s; %s', sl, res.descr); end
            end
        catch e
            try, m = fitlm(x,y); res.p = m.Coefficients.pValue(2); res.ok = true; ...
                 res.note = ['exp fit failed -> OLS: ' e.message];
            catch, res.note = e.message; end %#ok<CTCH>
        end
    else
        try
            m = fitlm(x,y); res.p = m.Coefficients.pValue(2); res.ok = true;
            if wantS
                sl = i_expSlope(m, x);
                if ~isempty(sl), res.descr = sprintf('%s; %s', sl, res.descr); end
            end
        catch e, res.note = e.message; end %#ok<CTCH>
    end
end

% ===================================================================== %
function res = i_anova(data, mode, res)
    groups = data.groups; labels = data.labels;
    % per-group mean +/- s.e.m. of THIS mode's groups (e.g. "SG 0.5+/-0.02 / ...")
    parts = cell(1, numel(groups));
    for q = 1:numel(groups)
        d = groups{q}(:); d = d(isfinite(d));
        if isempty(d), parts{q} = sprintf('%s -', labels{q});
        else, parts{q} = sprintf('%s %s', labels{q}, i_ms(mean(d), std(d)/sqrt(numel(d))));
        end
    end
    res.descr = strjoin(parts, ' / ');
    % Mixed-effects: when the build supplied observation-level values with layer,
    % unit and penetration ids, fit  v ~ layer + (1|pen) + (1|pen:unit)  and test
    % the layer effect jointly (Satterthwaite F). Descriptive n stays the
    % aggregated count; nObs records what the model used.
    if strcmp(mode,'lme') && isfield(data,'obsVals') && ~isempty(data.obsVals)
        try
            v   = data.obsVals(:); lay = data.obsLayer(:);
            un  = data.obsId(:);   pen = data.obsPen(:);
            ok  = isfinite(v); v = v(ok); lay = lay(ok); un = un(ok); pen = pen(ok);
            if numel(unique(lay)) >= 2
                if all(isfinite(pen)) && numel(unique(pen)) >= 2
                    tt = table(v, categorical(lay), categorical(un), categorical(pen), ...
                               'VariableNames', {'v','lay','un','pen'});
                    form = 'v ~ lay + (1|pen) + (1|pen:un)';
                else
                    tt = table(v, categorical(lay), categorical(un), ...
                               'VariableNames', {'v','lay','un'});
                    form = 'v ~ lay + (1|un)';
                end
                L = fitlme(tt, form);
                k = numel(L.CoefficientNames);
                H = [zeros(k-1,1), eye(k-1)];
                try, [pJ, F] = coefTest(L, H, zeros(k-1,1), 'DFMethod', 'satterthwaite'); df = 'satterthwaite';
                catch, [pJ, F] = coefTest(L); df = 'residual'; end %#ok<CTCH>
                res.p = pJ; res.stat = F; res.ok = true; res.nObs = numel(v);
                try, [~, ~, C] = fixedEffects(L, 'DFMethod', 'satterthwaite'); catch, C = L.Coefficients; end %#ok<CTCH>
                parts = {};
                for r = 1:numel(C.Name)
                    if strcmp(C.Name{r}, '(Intercept)'), continue; end
                    parts{end+1} = sprintf('%s p=%.3g', strrep(C.Name{r},'lay_',''), C.pValue(r)); %#ok<AGROW>
                end
                res.note = sprintf('%s [%s df]; %s', form, df, strjoin(parts, '; '));
                nn = 0;
                for k2 = 1:numel(groups)
                    d = groups{k2}(:); nn = nn + sum(isfinite(d));
                end
                res.n = nn;
                if isfield(data,'neur') && ~isempty(data.neur), res.neurons = numel(unique(data.neur)); end
                return;
            end
        catch
            % fall through to the classic anova below
        end
    end
    vals = []; grp = {}; nn = 0;
    for k = 1:numel(groups)
        d = groups{k}(:); d = d(isfinite(d));
        vals = [vals; d]; grp = [grp; repmat(labels(k), numel(d), 1)]; nn = nn + numel(d); %#ok<AGROW>
    end
    res.n = nn;
    if isfield(data,'neur') && ~isempty(data.neur), res.neurons = numel(unique(data.neur)); end
    if numel(unique(grp)) < 2, res.note = 'need >=2 groups'; return; end
    try
        [p, tbl, st] = anova1(vals, grp, 'off'); res.p = p; res.ok = true;
        try, res.stat = tbl{2,5}; catch, end %#ok<CTCH>      % F statistic
        try
            c = multcompare(st, 'CType', 'tukey-kramer', 'Display', 'off');
            gn = unique(grp,'stable');
            parts = cell(1,size(c,1));
            for r = 1:size(c,1)
                parts{r} = sprintf('%s-%s p=%.3g', char(gn{c(r,1)}), char(gn{c(r,2)}), c(r,6));
            end
            res.note = strjoin(parts, '; ');
        catch, end %#ok<CTCH>
    catch e
        res.note = e.message;
    end
end

% ===================================================================== %
function res = i_descr(data, res)
    d = data.groups{1}(:); d = d(isfinite(d));
    res.n = numel(d); res.neurons = res.n;
    if ~isempty(d)
        res.mA = mean(d); res.seA = std(d)/sqrt(numel(d)); res.stat = res.mA;
        res.meanA = res.mA; res.descr = i_ms(res.mA, res.seA);
    end
    res.ok = true;
end

% ===================================================================== %
function s = i_ms(m, se)
%I_MS  "mean+/-s.e.m." in the one format the whole report uses.
    if ~isfinite(m),      s = '-';
    elseif ~isfinite(se), s = sprintf('%.3g', m);
    else,                 s = sprintf('%.3g+/-%.2g', m, se);
    end
end

% ===================================================================== %
function s = i_expSlope(mdl, x)
%I_EXPSLOPE  The "s = ..." the f05 gain panels print: the average slope of the
%   drawn curve, over the same x grid drawGainPanel plots it on.
    s = '';
    try
        xes = (0:-.05:min(x))';
        if numel(xes) < 2, return; end
        ply = predict(mdl, xes);
        s = sprintf('s=%.3g', (ply(end)-ply(1)) / (xes(end)-xes(1)));
    catch %#ok<CTCH>
    end
end
