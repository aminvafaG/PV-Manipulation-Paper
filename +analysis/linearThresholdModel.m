function M = linearThresholdModel(controlCurve, laserCurve, opts)
%LINEARTHRESHOLDMODEL  Faithful re-implementation of the F2_5_3 (LTM) linear-
%   threshold fit relating a laser tuning curve to its control tuning curve.
%
%   M = analysis.linearThresholdModel(controlCurve, laserCurve)
%   M = analysis.linearThresholdModel(..., 'isInhibitory', true)
%
%   Reproduces Other project functions/F2_5_3.m exactly. Both curves are scaled
%   by 100 (percent of control peak): x = 100*control, y = 100*laser. The slope
%   is scale-invariant, so it is unchanged by the 100x; the intercept/floor/
%   breakpoint are in these 100x ("percent") units, as in F2_5_3.
%
%   EXCITATORY (default):  3-parameter piecewise threshold-linear with a FREE
%   floor, fit by fminsearch on the VERTICAL sum of squares (default options):
%       yhat = (x<=bp).*floor + (x>bp).*(floor + slope*(x-bp))
%       initial guess [mean(y(1:round(end/2))), 1, mean(x)]
%       slope -> Ma ;  intercept Mb = floor - bp*slope  (y-intercept of the ramp)
%
%   INHIBITORY ('isInhibitory',true):  plain straight line by polyfit (vertical
%   OLS):  slope -> Ma, intercept -> Mb. PLUS the reversed line (control vs
%   laser): slope_rev -> Mar, intercept_rev -> Mbr.
%
%   Inputs are the paired control-peak-normalized aligned curves for ONE unit
%   (e.g. A.control_nc and A.laser_nc, or D.fit_mid_nc_NL / D.fit_mid_nc_L). They
%   must be the same length; each orientation sample is one (control,laser) pair.
%
%   GOODNESS OF FIT (an addition over F2_5_3; does not affect the fit) on the
%   full curve, predicted vs actual laser (control-peak units): SSE, RMSE,
%   R2 = 1-SSE/SST, adjusted R2 (p = 3 for E piecewise, 2 for I linear).
%
%   Output struct M:
%     .slope .intercept          Ma, Mb (intercept in 100x / percent units)
%     .floor .breakpoint         E only (free floor, breakpoint; 100x units); NaN for I
%     .slope_rev .intercept_rev  I only (reversed-fit Mar, Mbr); NaN for E
%     .predicted                 predicted laser curve, control-peak units (Mb/100),
%                                full length / orientation order (overlays fit_mid_nc_L)
%     .SSE .RMSE .R2 .R2adj .n   goodness of fit (predicted vs laser)
%     .ok                        true if a fit was produced
%
%   See also: analysis.exponentialModel, analysis.alignTunings, analysis.computeMetrics

    arguments
        controlCurve double
        laserCurve   double
        opts.isInhibitory (1,1) logical = false
        opts.minPoints (1,1) double {mustBePositive, mustBeInteger} = 4
        % floorAtZero: PVA (excitatory) only. false (default) = 3-param piecewise
        % with a FREE floor (the validated F2_5_3 fit). true = LOCK the floor at 0,
        % giving a 2-param threshold-linear  yhat = (x>bp).*slope.*(x-bp)  for a
        % strict parameter-count match with the 2-param I/O model. No effect on the
        % PVI branch (already a 2-param line).
        opts.floorAtZero (1,1) logical = false
    end

    xc  = controlCurve(:).';
    yl  = laserCurve(:).';
    len = numel(yl);
    M   = emptyOut(len);
    if numel(xc) ~= len
        error('linearThresholdModel:size','controlCurve and laserCurve must be the same length.');
    end

    good = isfinite(xc) & isfinite(yl);
    if nnz(good) < opts.minPoints, return; end

    x  = 100 * xc;          % percent of control peak (F2_5_3 scaling)
    y  = 100 * yl;
    xg = x(good); yg = y(good);
    n  = numel(xg);

    if opts.isInhibitory
        % --- plain linear (vertical OLS), forward and reversed ---------------
        p  = polyfit(xg, yg, 1);            % laser  ~ control
        pr = polyfit(yg, xg, 1);            % control ~ laser   (reversed)
        M.slope     = p(1);   M.intercept     = p(2);
        M.slope_rev = pr(1);  M.intercept_rev = pr(2);
        yhat = polyval(p, x);               % predicted laser (100x), full grid
        nParam = 2;
    elseif opts.floorAtZero
        % --- 2-param threshold-linear, floor LOCKED at 0 (b = [slope breakpoint])
        %     yhat = (x>bp).*slope.*(x-bp). Same piecewise form as the free-floor
        %     fit with the floor fixed to 0, for a strict 2-vs-2 match with the I/O.
        pw  = @(b,xx) (xx>b(2)).*(b(1).*(xx - b(2)));
        obj = @(b) sum( (yg - pw(b, xg)).^2 );
        g0  = [1, mean(xg)];
        b   = fminsearch(obj, g0, optimset('Display','off'));   % default tolerances
        M.slope      = b(1);
        M.intercept  = -b(2)*b(1);                          % Mb (ramp y-intercept), floor 0
        M.floor      = 0;
        M.breakpoint = b(2);
        yhat = pw(b, x);                                    % predicted laser (100x), full grid
        nParam = 2;
    else
        % --- piecewise threshold-linear with a free floor (vertical fminsearch)
        pw  = @(b,xx) (xx<=b(3)).*b(1) + (xx>b(3)).*(b(1) + b(2)*(xx - b(3)));
        obj = @(b) sum( (yg - pw(b, xg)).^2 );
        g0  = [mean(yg(1:round(n/2))), 1, mean(xg)];        % F2_5_3 initial guess
        b   = fminsearch(obj, g0, optimset('Display','off'));   % default tolerances
        M.slope      = b(2);
        M.intercept  = b(1) - b(3)*b(2);                    % Mb (ramp y-intercept)
        M.floor      = b(1);
        M.breakpoint = b(3);
        yhat = pw(b, x);                                    % predicted laser (100x), full grid
        nParam = 3;
    end

    yhat(~isfinite(x)) = NaN;
    M.predicted = yhat / 100;               % back to control-peak units (no clipping; F2_5_3 LTM does not clip)

    % --- goodness of fit: predicted vs actual laser (full curve) -------------
    gd  = isfinite(M.predicted) & isfinite(yl);
    nG  = nnz(gd);
    res = M.predicted(gd) - yl(gd);
    sse = sum(res.^2);
    sst = sum( (yl(gd) - mean(yl(gd))).^2 );

    M.SSE  = sse;
    M.RMSE = sqrt(sse / max(nG,1));
    if sst > 0
        M.R2 = 1 - sse/sst;
        if nG > nParam, M.R2adj = 1 - (sse/(nG-nParam)) / (sst/(nG-1)); end
    end
    M.n  = nG;
    M.ok = true;
end

% ======================================================================= %
function M = emptyOut(len)
    M = struct('slope',NaN, 'intercept',NaN, 'floor',NaN, 'breakpoint',NaN, ...
        'slope_rev',NaN, 'intercept_rev',NaN, 'predicted',nan(1, max(len,0)), ...
        'SSE',NaN, 'RMSE',NaN, 'R2',NaN, 'R2adj',NaN, 'n',0, 'ok',false);
end
