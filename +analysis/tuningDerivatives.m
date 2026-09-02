function out = tuningDerivatives(curve, centerIdx)
%TUNINGDERIVATIVES  Circular derivatives + lobe count of a (delta-)tuning curve.
%
%   out = analysis.tuningDerivatives(curve)
%   out = analysis.tuningDerivatives(curve, centerIdx)
%
%   Ported from the derivative block of Visualizer_01: a curve is circularly
%   padded with its last sample and differenced, so each derivative keeps the
%   curve's length. Typically applied to the control-aligned, control-peak-
%   normalized delta tuning (laser - control), i.e. D.Delta_tun_nc.
%
%   curve      1xM (or Mx1) tuning / delta-tuning curve on a periodic grid.
%   centerIdx  sample index of the curve center (e.g. 180 when the peak sits at
%              179 deg on a 0:359 grid). If omitted, the *_center fields are NaN.
%
%   out fields:
%     .d1 .d2 .d3 .d4   1xM 1st..4th circular derivatives (Visualizer_01 style)
%     .nExtrema         number of local maxima+minima (sign changes of d1) = Lo_N
%     .d2_center        2nd derivative at centerIdx (curvature at center)
%     .d4_center        4th derivative at centerIdx
%
%   See also: analysis.computeMetrics, analysis.alignTunings, analysis.deltaRatio

    y = curve(:)';
    M = numel(y);
    out = struct('d1',nan(1,M), 'd2',nan(1,M), 'd3',nan(1,M), 'd4',nan(1,M), ...
                 'nExtrema',NaN, 'd2_center',NaN, 'd4_center',NaN);
    if M < 2 || ~any(isfinite(y)), return; end

    d1 = circDiff(y);
    d2 = circDiff(d1);
    d3 = circDiff(d2);
    d4 = circDiff(d3);
    out.d1 = d1; out.d2 = d2; out.d3 = d3; out.d4 = d4;

    % local extrema = sign changes of the 1st derivative (circular)
    p  = d1 > 0;
    out.nExtrema = nnz(diff([p(end) p]) ~= 0);

    if nargin >= 2 && ~isempty(centerIdx) && centerIdx >= 1 && centerIdx <= M
        out.d2_center = d2(centerIdx);
        out.d4_center = d4(centerIdx);
    end
end

function dd = circDiff(y)
%CIRCDIFF  Backward difference with circular wrap: dd(k)=y(k)-y(k-1), dd(1)=
%   y(1)-y(end). Equivalent to diff([y(end) y]) and keeps length(y).
    y  = y(:)';
    dd = diff([y(end) y]);
end
