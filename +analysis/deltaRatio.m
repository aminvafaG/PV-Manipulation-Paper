function D = deltaRatio(gridC, curveC, gridL, curveL, opts)
%DELTARATIO  Aligned laser-vs-control tuning difference / ratio.
%
%   D = analysis.deltaRatio(gridC, curveC, gridL, curveL)
%   D = analysis.deltaRatio(..., 'target_center',180, 'deltaPeakWindowDeg',20)
%
%   Ported from Compute_Tuning_Metrics_05/ComputeDeltaRatioAligned.
%     Step A: shift the control peak to center; shift laser by the same amount.
%     Step B: if a local laser peak sits within center +/- windowDeg, apply a
%             small extra laser shift to align the laser peak too.
%
%   Inputs are the two fitted curves (e.g. grid 0:359 with D.fit_NL(:,i) for
%   control and D.fit_L(:,i) for laser).
%
%   Output struct D:
%     .grid     common (shifted-control) grid
%     .curve    laser - control   (aligned)
%     .ratio    laser ./ (control + eps)
%     .d2/.d4   2nd / 4th circular derivative of .curve
%     .small_extra_laser_shift  1 if Step B was applied, else 0
%     .align    struct with the shift bookkeeping
%
%   This is a paired (population) quantity; it is provided for completeness and
%   is not one of the per-unit scalar metrics in analysis.computeMetrics.

    arguments
        gridC double
        curveC double
        gridL double
        curveL double
        opts.target_center (1,1) double = 180
        opts.deltaPeakWindowDeg (1,1) double {mustBePositive} = 20
        opts.ratio_eps (1,1) double {mustBePositive} = 1e-9
    end

    D = struct('grid',[], 'curve',[], 'ratio',[], 'd2',[], 'd4',[], ...
        'small_extra_laser_shift',0, 'align',struct());

    xC = gridC(:)'; yC = curveC(:)';
    xL = gridL(:)'; yL = curveL(:)';
    okC = numel(xC) >= 2 && any(isfinite(yC));
    okL = numel(xL) >= 2 && any(isfinite(yL));
    if ~okC && ~okL, return; end

    if okC && okL
        [base, period, center] = domainFromGrid(xC, opts.target_center);

        % Step A: shift control peak to center; shift laser by same amount
        [~, iPkC] = max(yC);
        shift0 = center - xC(iPkC);
        [xC0, yC0] = applyCircularShift(xC, yC, shift0, base, period);
        [xL0, yL0] = applyCircularShift(xL, yL, shift0, base, period);

        x = xC0;
        yL_on = interp1_periodic(xL0, yL0, x, base, period);

        % Step B: optional small extra laser shift
        [hasPeak, oriLaserPk] = localPeakNearCenter(x, yL_on, center, ...
                                    opts.deltaPeakWindowDeg, base, period);
        shift1 = 0;
        if hasPeak
            shift1 = center - oriLaserPk;
            [xL1, yL1] = applyCircularShift(xL0, yL0, shift1, base, period);
            yL_on = interp1_periodic(xL1, yL1, x, base, period);
            D.small_extra_laser_shift = 1;
        end

        D.grid  = x;
        D.curve = yL_on - yC0;
        D.ratio = yL_on ./ (yC0 + opts.ratio_eps);
        D.align = struct('base',base,'period',period,'center',center, ...
            'shift0_deg',shift0,'shift1_deg',shift1, ...
            'windowDeg',opts.deltaPeakWindowDeg);
    elseif okC
        D.grid = xC; D.curve = yC; D.ratio = NaN(size(xC));
    else
        D.grid = xL; D.curve = -yL; D.ratio = NaN(size(xL));
    end

    h = meanStep(D.grid);
    D.d2 = circDiff2(D.curve, h);
    D.d4 = circDiff4(D.curve, h);
end

% ===================== helpers =====================
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

function [hasPeak, oriPeak] = localPeakNearCenter(xDeg, y, center, windowDeg, ~, period)
    hasPeak = false; oriPeak = NaN;
    if isempty(xDeg) || isempty(y), return; end
    xDeg = xDeg(:)'; y = y(:)';
    dist = circDistDeg(xDeg, center, period);
    inWin = dist <= windowDeg;
    if ~any(inWin), return; end
    N0 = numel(y);
    isPeak = (y >= y([N0 1:N0-1])) & (y > y([2:N0 1]));
    cand = find(inWin & isPeak & isfinite(y));
    if isempty(cand), return; end
    cc = cand(y(cand) == max(y(cand)));
    if numel(cc) > 1, [~, k] = min(dist(cc)); cc = cc(k); end
    oriPeak = xDeg(cc); hasPeak = true;
end

function d = circDistDeg(x, c, period)
    d = abs(mod((x - c) + period/2, period) - period/2);
end

function h = meanStep(x)
    x = x(:)';
    if numel(x) < 2, h = 1; else, h = mean(diff(x)); end
    if ~isfinite(h) || h == 0, h = 1; end
end

function d2 = circDiff2(y, h)
    y = y(:)'; N0 = numel(y);
    d2 = (y([N0 1:N0-1]) - 2*y + y([2:N0 1])) / (h^2);
end

function d4 = circDiff4(y, h)
    y = y(:)'; N0 = numel(y);
    d4 = (y([N0-1 N0 1:N0-2]) - 4*y([N0 1:N0-1]) + 6*y - 4*y([2:N0 1]) + y([3:N0 1 2])) / (h^4);
end
