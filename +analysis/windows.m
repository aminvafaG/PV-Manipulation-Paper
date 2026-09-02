function [baseWin, stimWin] = windows(timing, avoidMs)
%WINDOWS  Baseline / stimulus sample windows from raster timing.
%
%   [baseWin, stimWin] = analysis.windows(timing)
%   [baseWin, stimWin] = analysis.windows(timing, avoidMs)
%
%   timing  = [start_s, stim_dur_s, end_s]  (D.Rast_time row for a unit;
%             start_s is negative = pre-stimulus baseline, e.g. [-0.5 1 2]).
%   avoidMs = ms trimmed at each stim edge to avoid laser onset/offset
%             artifacts (default 5, matching the old Fit_Function/viewer).
%
%   Returns 1x2 [startIdx endIdx] sample windows (rasters are 1 kHz / 1 ms bins):
%     baseWin = [1, 1000*(-start_s) - avoidMs]
%     stimWin = [1 + 1000*(-start_s) + avoidMs, 1000*stim_dur + 1000*(-start_s) - avoidMs]
%
%   For timing [-0.5 1 2] with avoidMs 5 this gives baseWin [1 495], stimWin [506 1495].

    if nargin < 2 || isempty(avoidMs), avoidMs = 5; end
    pre_ms = 1000 * (-timing(1));
    baseWin = [1,            round(pre_ms - avoidMs)];
    stimWin = [round(1 + pre_ms + avoidMs), round(1000*timing(2) + pre_ms - avoidMs)];
end
