function A = alignTunings(grid, laserCurve, controlCurve, opts)
%ALIGNTUNINGS  Control-aligned laser/control tuning curves + delta / ratio / HBW.
%
%   A = analysis.alignTunings(grid, laserCurve, controlCurve)
%   A = analysis.alignTunings(..., 'peak0WindowDeg',45, 'HBW_level',1/sqrt(2))
%
%   Implements the alignment used in Visualizer_01 (laser = 1st curve, control
%   = 2nd):
%     1. Shift the CONTROL so its peak sits at the center (target_center deg).
%     2. Shift the LASER by the SAME amount (so it stays comparable to control).
%     3. Find the laser peak ("peak0") within center +/- peak0WindowDeg and
%        shift the laser again so peak0 sits at the center.
%     4. If |peak0 - center| falls inside (badLoDeg, badHiDeg) the unit is
%        flagged BAD (A.bad). HBW/FWHM stay POSITIVE; the validity flags
%        A.HBW_pair_ok / A.HBW_L_nan / A.HBW_NL_nan record whether a clean,
%        aligned HBW pair was obtained.
%
%   Unlike a per-side "center on the curve's own global peak", this anchors the
%   laser to the control's preferred orientation, so HBW (and the delta/ratio
%   curves) are measured around the same reference for both conditions.
%
%   grid/laserCurve/controlCurve are the fitted curves (e.g. 0:359 deg with
%   D.fit_L(:,i) and D.fit_NL(:,i)). grid is shared by both curves.
%
%   Output struct A (curves are 1xM row vectors on the centered grid A.grid):
%     .grid              centered grid (sorted; control peak at center)
%     .laser .control    shifted curves (raw units)
%     .delta             laser - control
%     .laser_nc .control_nc   shifted curves normalized to the CONTROL peak
%     .delta_nc          laser_nc - control_nc
%     .laser_self .control_self  shifted curves normalized to EACH OWN peak
%     .ratio             laser ./ (control + ratio_eps)
%     .peak0Val          laser response at peak0 (windowed, control-aligned)
%     .OSI_laser_global  laser OSI using the global max as preferred
%     .OSI_laser_peak0   laser OSI using peak0 as preferred (Visualizer_01)
%     .OSI_control       control OSI (= global, since control peak is the anchor)
%     .HBW_laser .HBW_control    half-bandwidth (deg); always >=0 (NaN if not computable)
%     .FWHM_laser .FWHM_control  half-width at half-max (deg); always >=0 (NaN if not computable)
%     .HBW_L_nan .HBW_NL_nan     true if HBW is not computable (laser / control side)
%     .HBW_pair_ok               true if both HBW computable AND unit aligned (~bad)
%     .bad               true if peak0 is too far from center (laser not aligned to control)
%     .peak0Ori .peak0DistDeg    laser peak0 angle and its distance from center
%     .shift0 .shift1    control->center shift, and the extra laser peak0 shift
%     .ctrlPeak .laserPeak       peak response of each shifted curve
%
%   See also: analysis.tuningMetrics, analysis.deltaRatio, analysis.computeMetrics

    arguments
        grid double
        laserCurve double
        controlCurve double
        opts.target_center  (1,1) double = 180                    % 179 -> sample-180 center
        opts.HBW_level      (1,1) double {mustBePositive, mustBeLessThanOrEqual(opts.HBW_level,1)} = 1/sqrt(2)
        opts.peak0WindowDeg (1,1) double {mustBePositive} = 45     % 3/8..5/8 of 360
        opts.badLoDeg       (1,1) double {mustBeNonnegative} = 30
        opts.badHiDeg       (1,1) double {mustBePositive} = 150
        opts.ratio_eps      (1,1) double {mustBePositive} = 1e-9
        opts.HBWQuantize    (1,1) logical = false                 % integer-sample crossings (Visualizer_01)
    end

    x  = grid(:)';
    yL = laserCurve(:)';
    yC = controlCurve(:)';
    M  = numel(x);

    A = nanOut(M);
    if M < 2 || ~any(isfinite(yC)) || ~any(isfinite(yL))
        return;
    end

    [base, period, center] = domainFromGrid(x, opts.target_center);

    % --- Step 1: control peak -> center; Step 2: same shift applied to laser ---
    [~, iC]  = max(yC);

    shift0   = center - x(iC);
    [xs, yC0] = applyCircularShift(x, yC, shift0, base, period);
    [~,  yL0] = applyCircularShift(x, yL, shift0, base, period);

    % --- Step 3: laser peak0 within center +/- window, recenter laser on it ---
    inWin = circDistDeg(xs, center, period) <= opts.peak0WindowDeg;
    yw = yL0; yw(~inWin | ~isfinite(yw)) = -inf;
    [peak0Val, ip0] = max(yw);                  % windowed (control-aligned) laser peak
    peak0Ori  = xs(ip0);
    peak0Dist = circDistDeg(peak0Ori, center, period);

    shift1   = center - peak0Ori;
    [~, yL1] = applyCircularShift(xs, yL0, shift1, base, period);

    % --- Step 4: bad-unit flag (peak0 too far from center) ---
    bad = peak0Dist > opts.badLoDeg && peak0Dist < opts.badHiDeg;

    ctrlPeak  = max(yC0);
    laserPeak = max(yL1);

    % --- aligned tuning curves + delta / ratio ---
    A.grid    = xs;
    A.laser   = yL1;
    A.control = yC0;
    A.delta   = yL1 - yC0;

    A.laser_nc   = yL1 / max(ctrlPeak, eps);
    A.control_nc = yC0 / max(ctrlPeak, eps);
    A.delta_nc   = A.laser_nc - A.control_nc;

    A.laser_self   = yL1 / max(laserPeak, eps);
    A.control_self = yC0 / max(ctrlPeak,  eps);

    A.ratio = yL1 ./ (yC0 + opts.ratio_eps);

    % --- OSI = (pref - nonpref)/(pref + nonpref), pref/nonpref = max/min ------
    %  laser "preferred" can be the GLOBAL max (this project's default) or the
    %  windowed control-aligned peak0 (Visualizer_01). Control uses its own peak,
    %  which equals its global max.
    laserMin = min(yL1);
    ctrlMin  = min(yC0);
    A.peak0Val          = peak0Val;
    A.OSI_laser_global  = osiFrom(laserPeak, laserMin);
    A.OSI_laser_peak0   = osiFrom(peak0Val,  laserMin);
    A.OSI_control       = osiFrom(ctrlPeak,  ctrlMin);

    % --- half-bandwidths measured about the center (peak0 / control peak) ---
    A.HBW_laser    = hbwAboutCenter(xs, yL1, center, opts.HBW_level, period, opts.HBWQuantize);
    A.HBW_control  = hbwAboutCenter(xs, yC0, center, opts.HBW_level, period, opts.HBWQuantize);
    A.FWHM_laser   = hbwAboutCenter(xs, yL1, center, 0.5,            period, opts.HBWQuantize);
    A.FWHM_control = hbwAboutCenter(xs, yC0, center, 0.5,            period, opts.HBWQuantize);
    % --- HBW pair validity (widths are kept POSITIVE) ----------------------
    %  A "bad" (peak0 off-center) unit NO LONGER negates HBW/FWHM. Instead the
    %  flags below record why an HBW pair may be unusable; HBW_pair_ok is true
    %  only when BOTH sides are computable AND the unit is aligned (~bad).
    A.HBW_L_nan   = ~isfinite(A.HBW_laser);     % laser HBW not computable
    A.HBW_NL_nan  = ~isfinite(A.HBW_control);   % control HBW not computable
    A.HBW_pair_ok = ~(A.HBW_L_nan || A.HBW_NL_nan || bad);

    A.bad          = bad;
    A.peak0Ori     = peak0Ori;
    A.peak0DistDeg = peak0Dist;
    A.shift0       = shift0;
    A.shift1       = shift1;
    A.ctrlPeak     = ctrlPeak;
    A.laserPeak    = laserPeak;
end

% ===================== orientation selectivity =====================
function osi = osiFrom(pref, nonpref)
%OSIFROM  (pref - nonpref) / (pref + nonpref), guarded.
    osi = abs(pref - nonpref) / max(pref + nonpref, eps);
end

% ===================== half-bandwidth about a fixed center =====================
function hbw = hbwAboutCenter(x, y, center, level, period, quantize)
%HBWABOUTCENTER  One-sided half-width from `center` to the nearest threshold
%   crossing on the side toward the curve minimum (Visualizer_01 style).
%   level is a fraction of (valueAtCenter - min); HBW uses 1/sqrt(2), FWHM 0.5.
%   quantize=true uses integer-sample crossings (no interpolation).

    x = x(:)'; y = y(:)';
    hbw = NaN;
    if numel(y) < 2, return; end
    if nargin < 6, quantize = false; end

    Pc = interp1_periodic(x, y, center, min(x), period);   % value at center
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
        hbw = period/2; return;                 % min at center (degenerate)
    end
    if isempty(sel), return; end
    hbw = min(abs(sel - center));
end

function cr = thresholdCrossings(x, y, level, period, quantize)
%THRESHOLDCROSSINGS  Angles where y crosses `level` (circular). quantize=true
%   returns the left integer-sample angle (Visualizer_01); else linear interp.
    x = x(:)'; y = y(:)';
    xE = [x, x(1)+period];
    yE = [y, y(1)];
    above = yE > level;
    idx = find(diff(above) ~= 0);
    cr = zeros(1, numel(idx));
    for k = 1:numel(idx)
        i1 = idx(k); i2 = idx(k)+1;
        if quantize
            cr(k) = xE(i1);                                 % integer-sample crossing
        else
            cr(k) = linCross(xE(i1), yE(i1), xE(i2), yE(i2), level);
        end
    end
    cr = mod(cr - min(x), period) + min(x);     % wrap into the grid range
end

function tc = linCross(t1, y1, t2, y2, level)
    if y2 == y1
        tc = t1;
    else
        a  = max(min((level - y1) / (y2 - y1), 1), 0);
        tc = t1 + a*(t2 - t1);
    end
end

% ===================== periodic / geometry helpers =====================
function [base, period, center] = domainFromGrid(x, targetCenterPref)
    x = x(:)'; span = max(x) - min(x);
    if isfinite(span) && span > 300 && span < 380
        base = 0; period = 360; center = targetCenterPref;
    else
        base = min(x); period = span; center = base + period/2;
    end
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

function d = circDistDeg(x, c, period)
    d = abs(mod((x - c) + period/2, period) - period/2);
end

% ===================== empty / NaN output =====================
function A = nanOut(M)
    z = NaN(1, max(M,0));
    A = struct('grid',z, 'laser',z, 'control',z, 'delta',z, ...
        'laser_nc',z, 'control_nc',z, 'delta_nc',z, ...
        'laser_self',z, 'control_self',z, 'ratio',z, ...
        'peak0Val',NaN, 'OSI_laser_global',NaN, 'OSI_laser_peak0',NaN, 'OSI_control',NaN, ...
        'HBW_laser',NaN, 'HBW_control',NaN, 'FWHM_laser',NaN, 'FWHM_control',NaN, ...
        'HBW_L_nan',true, 'HBW_NL_nan',true, 'HBW_pair_ok',false, ...
        'bad',false, 'peak0Ori',NaN, 'peak0DistDeg',NaN, ...
        'shift0',NaN, 'shift1',NaN, 'ctrlPeak',NaN, 'laserPeak',NaN);
end
