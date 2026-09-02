function out = tuningExtrema(grid, curve)
%TUNINGEXTREMA  Local maxima / minima of a periodic tuning curve, value-sorted.
%
%   out = analysis.tuningExtrema(grid, curve)
%
%   An orientation tuning curve over 0:359 deg typically has two upward peaks
%   (the two directions of the preferred orientation, ~180 deg apart) and two
%   downward troughs. This finds every local maximum and minimum from slope-sign
%   changes on the CIRCULAR curve and sorts them so index 1 is the most extreme:
%
%     .maxOri / .maxVal   local maxima, value DESCENDING (1 = highest peak)
%     .minOri / .minVal   local minima, value ASCENDING  (1 = deepest trough)
%
%   Each is a 1xK row (K = number of detected extrema, often 2). A curve with
%   fewer extrema (e.g. a shoulder instead of a true 2nd peak) returns shorter
%   vectors; callers pad the missing slots with NaN. Orientations are in the
%   input grid's units (deg), on the ORIGINAL (unshifted) curve.
%
%   See also: analysis.tuningMetrics, analysis.computeMetrics

    x = grid(:)'; y = curve(:)';
    out = struct('maxOri',[], 'maxVal',[], 'minOri',[], 'minVal',[]);
    m = isfinite(x) & isfinite(y); x = x(m); y = y(m);
    n = numel(y);
    if n < 3, return; end
    [x, ord] = sort(x); y = y(ord);

    slope = diff([y(end) y]) > 0;       % rising into each sample (circular)
    ds    = diff([slope slope(1)]);     % -1 = peak (rising->falling), +1 = trough
    iMax  = find(ds == -1);
    iMin  = find(ds ==  1);

    [out.maxVal, k] = sort(y(iMax), 'descend'); out.maxOri = x(iMax(k));
    [out.minVal, k] = sort(y(iMin), 'ascend');  out.minOri = x(iMin(k));
end
