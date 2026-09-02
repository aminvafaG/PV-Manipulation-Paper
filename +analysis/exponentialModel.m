function M = exponentialModel(startCurve, targetCurve, opts)
%EXPONENTIALMODEL  Exponential tuning-transformation model (start -> target).
%
%   M = analysis.exponentialModel(startCurve, targetCurve)
%   M = analysis.exponentialModel(..., 'dFR',d, 'cratio',c, 'SPlus',s)
%
%   Ported (cleaned) from Visualizer_01 + Sin5_3. Per unit it models how a START
%   tuning curve is transformed into a TARGET tuning curve. The caller assigns
%   start/target by experiment type (this is the E/I comparison convention):
%       E : start = control (fit_mid_nc_NL),  target = laser   (fit_mid_nc_L)
%       I : start = laser   (fit_mid_nc_L),   target = control (fit_mid_nc_NL)
%
%   MODEL (2 free parameters; floor 0, Lambda 1 as in the original):
%
%       target / max(start)  ~  exp( exponent * x  -  offset )
%
%   where x is the Sin5_3 transform of the start curve, normalized to its own
%   peak (start_n = start/max(start)):
%
%       x = log(start_n) * (1 + dFR*cratio)  +  SPlus * (dFR*cratio)
%
%   With dFR = cratio = 0 this is x = log(start_n), so the model reduces to a
%   power law  target ~ start^exponent  (the exponent is the headline parameter
%   to compare between E and I). dFR (firing-rate change), cratio (layer-group
%   ratio) and SPlus (= -log spontaneous/max) warp the input per the original.
%
%   FITTING  Same objective and bounds as F2_5_3 (lsqcurvefit, trust-region-
%   reflective, offset in [-70,20], exponent in [-10,25]; floor b1 locked to 0),
%   but keeps the best resnorm over a DETERMINISTIC set of starts (the log-linear
%   seed + a spread across the box) instead of the original 5 RANDOM restarts. So
%   the global optimum is found REPRODUCIBLY -- identical inputs give identical
%   results, with no random failures. The seed alone reproduces the old fit on
%   well-posed units; the spread recovers the ~600 degenerate units where the
%   old random restarts railed at a bound. The original initialParams ([-1 5 5]
%   for E, [-1 1 1] for I) is dead code there and unused here.
%
%   GOODNESS OF FIT  On the FULL curve, predicted vs actual target (same control-
%   peak-normalized units as the inputs):
%       SSE, RMSE = sqrt(SSE/n), R2 = 1-SSE/SST, adjusted R2 (p = 2).
%
%   Inputs are the paired control-peak-normalized curves for ONE unit (already
%   assigned to start/target). They must be the same length.
%
%   Output struct M:
%     .exponent   fitted exponent (x coefficient; the power-law exponent)
%     .offset     fitted offset    (subtracted in the exponent)
%     .scale      exp(-offset): predicted target at the start peak (x ~ 0)
%     .predicted  1xM predicted TARGET curve (control-peak-normalized; overlays
%                 fit_mid_nc_L for E, fit_mid_nc_NL for I), NaN where undefined
%     .SSE .RMSE .R2 .R2adj   goodness of fit
%     .n          number of finite samples used
%     .ok         true if a fit was produced
%
%   See also: analysis.linearThresholdModel, analysis.alignTunings, analysis.computeMetrics

    arguments
        startCurve  double
        targetCurve double
        opts.dFR    (1,1) double = 0
        opts.cratio (1,1) double = 0
        opts.SPlus  (1,1) double = 0
        opts.offsetBounds   (1,2) double = [-70 20]
        opts.exponentBounds (1,2) double = [-10 25]
        opts.minPoints (1,1) double {mustBePositive, mustBeInteger} = 8
        opts.floorPos  (1,1) double {mustBePositive} = 1e-6
        % --- constraint toggles (defaults reproduce the validated fit exactly) ---
        %   Algorithm  'trust-region-reflective' (honors bounds) | 'levenberg-marquardt'
        %              (ignores bounds: when chosen, the fit is run UNBOUNDED).
        %   multiStart true = deterministic 7-start spread; false = log-linear seed only.
        %   freeFloor  false = 2-param exp(b*x-off) (floor locked at 0);
        %              true  = 3-param  floor + exp(b*x-off) (adds an additive floor).
        %   To remove the BOUNDS, set offsetBounds/exponentBounds to [-Inf Inf].
        opts.Algorithm  (1,1) string  = "trust-region-reflective"
        opts.multiStart (1,1) logical = true
        opts.freeFloor  (1,1) logical = false
    end

    s   = startCurve(:).';
    t   = targetCurve(:).';
    len = numel(t);
    M   = emptyOut(len);
    if numel(s) ~= len
        error('exponentialModel:size','startCurve and targetCurve must be the same length.');
    end

    sMax = max(s);
    if ~isfinite(sMax) || sMax <= 0, return; end     % degenerate start curve

    startN  = s / sMax;                              % self-peak normalized (peak ~1)
    targetN = t / sMax;                              % target on the same scale

    % --- Sin5_3 input transform ----------------------------------------------
    c = opts.dFR * opts.cratio;
    if ~isfinite(c), c = 0; end                      % no firing-rate correction
    To = max(startN, opts.floorPos);                 % keep log finite
    x  = log(To) * (1 + c) + opts.SPlus * c;

    good = isfinite(x) & isfinite(targetN);
    if nnz(good) < opts.minPoints, return; end
    xg = x(good); yg = targetN(good);

    % --- log-linear seed:  log(targetN) = exponent*x - offset ----------------
    %     Data-driven start; on well-posed curves it lands at the global optimum
    %     directly. Also the fallback if every restart below fails.
    pos = good & (targetN > 0);
    if nnz(pos) >= 2
        X = x(pos).'; Y = log(targetN(pos)).';
        coef  = [X, ones(numel(X),1)] \ Y;           % [slope; intercept]
        expo0 = clampv(coef(1),  opts.exponentBounds);
        off0  = clampv(-coef(2), opts.offsetBounds);
    else
        expo0 = 1; off0 = 0;
    end

    % --- fit  targetN ~ exp(exponent*x - offset)  with the F2_5_3 objective and
    %     bounds (lb=[0 -70 -10], ub=[0 20 25]; floor b1 locked to 0, so here
    %     offset=b2 in [-70,20], exponent=b3 in [-10,25]). The original used 5
    %     RANDOM restarts; we instead keep the best resnorm over a DETERMINISTIC
    %     set of starts (the log-linear seed + a spread across the box). This
    %     finds the same global optimum REPRODUCIBLY -- identical inputs give
    %     identical results, with no random failures. The seed alone reproduces
    %     the old fit on well-posed units; the spread recovers the degenerate
    %     units where 5 random starts railed at a bound (~600 of them).
    %   The constraint toggles below all DEFAULT to the validated behavior, so
    %   analysis.exponentialModel(s,t) is byte-identical to before; flip them to
    %   compare against the unconstrained / single-seed / free-floor variants.
    if opts.freeFloor
        modelFun = @(p, xd) p(3) + exp(p(2)*xd - p(1)); % p = [offset exponent floor]
        lb = [opts.offsetBounds(1), opts.exponentBounds(1), -0.5];
        ub = [opts.offsetBounds(2), opts.exponentBounds(2),  1.5];
    else
        modelFun = @(p, xd) exp(p(2)*xd - p(1));        % p = [offset exponent]
        lb = [opts.offsetBounds(1), opts.exponentBounds(1)];
        ub = [opts.offsetBounds(2), opts.exponentBounds(2)];
    end

    % start set: deterministic 7-start spread, or the log-linear seed alone
    starts = [off0, expo0;  0, 1;  1, 2.8;  5, 5;  -1, 0.4;  3, 10;  10, 0.2];
    if ~opts.multiStart, starts = starts(1,:); end
    if opts.freeFloor,   starts = [starts, zeros(size(starts,1),1)]; end

    % Levenberg-Marquardt does NOT honor bound constraints (it warns and ignores
    % them); when selected we therefore run the fit UNBOUNDED (lbF/ubF empty).
    isLM = startsWith(lower(opts.Algorithm), "levenberg");
    fopts = optimoptions('lsqcurvefit', 'Algorithm', char(opts.Algorithm), 'Display','off');
    if isLM, lbF = []; ubF = []; else, lbF = lb; ubF = ub; end

    sseFun  = @(p) sum( (modelFun(p, xg) - yg).^2 );
    bestP   = starts(1,:);  bestErr = sseFun(bestP);
    for k = 1:size(starts,1)
        try
            [p, rn] = lsqcurvefit(modelFun, starts(k,:), xg, yg, lbF, ubF, fopts);
            if isfinite(rn) && rn < bestErr
                bestErr = rn; bestP = p;
            end
        catch
        end
    end
    offset = bestP(1); exponent = bestP(2);
    floorV = 0; if opts.freeFloor, floorV = bestP(3); end

    % --- predicted target curve (control-peak-normalized) --------------------
    yhatN = floorV + exp(exponent * x - offset);     % floorV==0 -> original model
    predicted = max(0, yhatN) * sMax;                % overlays the actual target
    predicted(~isfinite(yhatN)) = NaN;

    % --- goodness of fit: predicted vs actual target (full curve) ------------
    gd  = isfinite(predicted) & isfinite(t);
    nG  = nnz(gd);
    res = predicted(gd) - t(gd);
    sse = sum(res.^2);
    sst = sum( (t(gd) - mean(t(gd))).^2 );
    p   = 2 + double(opts.freeFloor);                % free floor adds a parameter

    M.exponent  = exponent;
    M.offset    = offset;
    M.floor     = floorV;                            % 0 unless opts.freeFloor
    M.scale     = exp(-offset);
    M.predicted = predicted;
    M.SSE       = sse;
    M.RMSE      = sqrt(sse / max(nG,1));
    if sst > 0
        M.R2 = 1 - sse/sst;
        if nG > p, M.R2adj = 1 - (sse/(nG-p)) / (sst/(nG-1)); end
    end
    M.n  = nG;
    M.ok = true;
end

% ======================================================================= %
function v = clampv(v, b)
    v = min(max(v, b(1)), b(2));
end

function M = emptyOut(len)
    M = struct('exponent',NaN, 'offset',NaN, 'floor',NaN, 'scale',NaN, ...
        'predicted',nan(1, max(len,0)), 'SSE',NaN, 'RMSE',NaN, ...
        'R2',NaN, 'R2adj',NaN, 'n',0, 'ok',false);
end
