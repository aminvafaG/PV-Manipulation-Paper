function S = tuningMetrics(grid, curve, opts)
%TUNINGMETRICS  Peak-centered orientation tuning metrics from a fitted curve.
%
%   S = analysis.tuningMetrics(grid, curve)
%   S = analysis.tuningMetrics(grid, curve, 'CV_def',"orientation", ...)
%
%   Ported from Compute_Tuning_Metrics_05 (ComputeSideMetrics + helpers).
%   grid/curve are the fitted tuning curve (e.g. 0:359 deg and D.fit_L(:,i)).
%
%   Name-Value options:
%     CV_def        "orientation" (2*theta) | "direction" (1*theta)   [default "orientation"]
%     OSI_def       "vector" | "pref_ortho" | "pref_Nonpref"          [default "pref_Nonpref"]
%     HBW_level     fraction of peak for half-bandwidth               [default 1/sqrt(2)]
%     target_center desired peak-center angle for the shifted curve   [default 180]
%                   (set 179 to center on sample index 180, Visualizer_01-style)
%     HBWQuantize   false = interpolate threshold crossings (sub-degree);
%                   true  = integer-sample crossings, no interp (Visualizer_01) [default false]
%
%   Output struct S:
%     .grid/.curve            cleaned, sorted input
%     .grid_shift/.curve_shift curve shifted so its peak sits at target_center
%     .max/.min/.max2         struct('value',..,'ori',..)  (on original curve)
%     .CV  circular variance        .OSI orientation selectivity
%     .HBW half-bandwidth (deg)     .FWHM half-width at half-max (deg)
%     .prefOri  preferred angle (deg)   .peak  peak response
%
%   Returns NaN-filled fields if the curve is empty/degenerate.

    arguments
        grid double
        curve double
        opts.CV_def (1,1) string {mustBeMember(opts.CV_def,["orientation","direction"])} = "orientation"
        opts.OSI_def (1,1) string {mustBeMember(opts.OSI_def,["vector","pref_ortho","pref_Nonpref"])} = "pref_Nonpref"
        opts.HBW_level (1,1) double {mustBePositive} = 1/sqrt(2)
        opts.target_center (1,1) double = 180
        opts.HBWQuantize (1,1) logical = false   % true = integer-sample crossings (Visualizer_01)
    end

    S = struct('grid',[], 'curve',[], 'grid_shift',[], 'curve_shift',[], ...
        'max',  struct('value',NaN,'ori',NaN), ...
        'min',  struct('value',NaN,'ori',NaN), ...
        'max2', struct('value',NaN,'ori',NaN), ...
        'CV',NaN, 'OSI',NaN, 'HBW',NaN, 'FWHM',NaN, 'prefOri',NaN, 'peak',NaN);

    x = grid(:)'; y = curve(:)';
    m = isfinite(x) & isfinite(y);
    x = x(m); y = y(m);
    if numel(y) < 2, return; end
    [x, ord] = sort(x); y = y(ord);
    S.grid = x; S.curve = y;

    % peak-centered (shifted) curve
    [xS, yS, center] = shiftToCenter(x, y, opts.target_center);
    S.grid_shift = xS; S.curve_shift = yS;

    % extrema on the original curve
    [vmax, imax] = max(y);
    [vmin, imin] = min(y);
    S.max = struct('value', vmax, 'ori', x(imax));
    S.min = struct('value', vmin, 'ori', x(imin));
    [imax2, vmax2] = secondPeakIndex(y, imax, imin);
    S.max2 = struct('value', vmax2, 'ori', x(imax2));
    S.prefOri = x(imax);
    S.peak    = vmax;

    % selectivity / bandwidth on the shifted curve (peak at center)
    S.CV  = computeCV(xS, yS, opts.CV_def);
    S.OSI = computeOSI(xS, yS, opts.OSI_def);
    [S.HBW, S.FWHM] = computeHBW(xS, yS, center, opts.HBW_level, opts.HBWQuantize);
end

% ===================== orientation metric helpers ======================
function cv = computeCV(thetaDeg, r, def)
    theta = deg2rad(thetaDeg(:)); r = r(:);
    switch string(def)
        case "orientation", z = r .* exp(1i*2*theta);
        case "direction",   z = r .* exp(1i*theta);
    end
    R  = sum(z) / max(sum(r), eps);
    cv = 1 - abs(R);
end

function osi = computeOSI(thetaDeg, r, def)
    theta = deg2rad(thetaDeg(:)); r = r(:);
    switch string(def)
        case "vector"
            z = r .* exp(1i*2*theta);
            osi = abs(sum(z)) / max(sum(r), eps);
        case "pref_ortho"
            [~, imax] = max(r);
            pref  = thetaDeg(imax);
            ortho = mod(pref + 90, 360);
            Rpref  = r(imax);
            Rortho = interp1_periodic(thetaDeg(:)', r(:)', ortho, thetaDeg(1), 360);
            osi = (Rpref - Rortho) / max(Rpref + Rortho, eps);
        case "pref_Nonpref"
            Rpref  = max(r);
            Rortho = min(r);
            osi = (Rpref - Rortho) / max(Rpref + Rortho, eps);
    end
end

function [HBW, FWHM] = computeHBW(thetaDeg, curve, center, level, quantize)
%COMPUTEHBW  One-sided half-widths about `center` (Visualizer_01 style):
%   distance from the peak (at center) to the nearest threshold crossing on the
%   side toward the curve minimum. Thresholds are a fraction of (peak - min):
%   HBW uses `level` (1/sqrt(2) by default); FWHM uses 0.5.
    th = thetaDeg(:)';
    span = max(th) - min(th);
    if isfinite(span) && span > 300 && span < 380, period = 360; else, period = span; end
    if ~isfinite(period) || period <= 0, period = 360; end
    if nargin < 5, quantize = false; end
    HBW  = hbwAboutCenter(th, curve, center, level, period, quantize);
    FWHM = hbwAboutCenter(th, curve, center, 0.5,   period, quantize);
end

function hbw = hbwAboutCenter(x, y, center, level, period, quantize)
    x = x(:)'; y = y(:)';
    hbw = NaN;
    if numel(y) < 2, return; end
    Pc = interp1_periodic(x, y, center, min(x), period);
    [minVal, iMin] = min(y);
    minOri = x(iMin);
    if ~isfinite(Pc) || ~isfinite(minVal) || Pc <= minVal, return; end
    H0 = minVal + (Pc - minVal) * level;
    cr = thresholdCrossings(x, y, H0, period, quantize);
    if isempty(cr), return; end
    if minOri < center
        sel = cr(cr > minOri & cr < center);
    elseif minOri > center
        sel = cr(cr < minOri & cr > center);
    else
        hbw = period/2; return;
    end
    if isempty(sel), return; end
    hbw = min(abs(sel - center));
end

function cr = thresholdCrossings(x, y, level, period, quantize)
    x = x(:)'; y = y(:)';
    xE = [x, x(1)+period]; yE = [y, y(1)];
    above = yE > level;
    idx = find(diff(above) ~= 0);
    cr = zeros(1, numel(idx));
    for k = 1:numel(idx)
        i1 = idx(k); i2 = idx(k)+1;
        if quantize
            cr(k) = xE(i1);    % integer-sample crossing (Visualizer_01, no interp)
        else
            cr(k) = linCross(xE(i1), yE(i1), xE(i2), yE(i2), level);
        end
    end
    cr = mod(cr - min(x), period) + min(x);
end

function [imax2, vmax2] = secondPeakIndex(yS, imax1, imin)
    N0 = numel(yS);
    imax2 = imin; vmax2 = yS(imin);
    if N0 < 3, return; end
    slope_sign = diff([yS(end) yS]) > 0;
    ds = diff([slope_sign slope_sign(1)]);
    cand = find(ds == -1);
    cand(cand == imax1) = [];
    if isempty(cand), return; end
    [~, k] = max(yS(cand));
    imax2 = cand(k); vmax2 = yS(imax2);
end

% ===================== periodic / geometry helpers =====================
function [xS, yS, tgt] = shiftToCenter(x, y, targetCenterPref)
    x = x(:)'; y = y(:)';
    span = max(x) - min(x);
    is360 = isfinite(span) && span > 300 && span < 380;
    if is360
        tgt = targetCenterPref; base = 0; full = 360;
    else
        base = min(x); full = span; tgt = base + full/2;
    end
    [~, imax] = max(y);
    [xS, yS] = applyCircularShift(x, y, tgt - x(imax), base, full);
end

function [xS, yS] = applyCircularShift(x, y, shiftDeg, base, period)
    x = x(:)'; y = y(:)';
    xS = mod((x - base) + shiftDeg, period) + base;
    [xS, ord] = sort(xS); yS = y(ord);
end

function yq = interp1_periodic(x, y, xq, base, period)
    x = x(:)'; y = y(:)'; xq = xq(:)';
    m = isfinite(x) & isfinite(y); x = x(m); y = y(m);
    if numel(x) < 2, yq = NaN(size(xq)); return; end
    [x, ord] = sort(x); y = y(ord);
    xE = [x, x(1)+period]; yE = [y, y(1)];
    yq = interp1(xE, yE, base + mod(xq - base, period), 'linear');
end

function tc = linCross(t1, y1, t2, y2, level)
    if y2 == y1
        tc = t1;
    else
        a = max(min((level - y1) / (y2 - y1), 1), 0);
        tc = t1 + a*(t2 - t1);
    end
end
