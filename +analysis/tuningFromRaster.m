function out = tuningFromRaster(R, stimWin, baseWin, oriN, psthWin)
%TUNINGFROMRASTER  Per-orientation tuning + PSTH from one unit's spike raster.
%
%   out = analysis.tuningFromRaster(R, stimWin, baseWin, oriN)
%   out = analysis.tuningFromRaster(R, stimWin, baseWin, oriN, psthWin)
%
%   Ported from Fit_Function_05 / Raster_viewer_08 (tuning_from_window + PSTH).
%
%   R        trials x timebins spike raster (logical/numeric), 1 ms bins.
%   stimWin  [s e] stimulus sample window   (see analysis.windows)
%   baseWin  [s e] baseline sample window
%   oriN     number of orientations; trials are assumed BLOCKED:
%            the first tr=floor(nTrials/oriN) trials are orientation 1, etc.
%   psthWin  movmean smoothing window for the PSTH in ms (default 1 = none).
%
%   out fields:
%     .T            1xOriN per-orientation firing rate (Hz)  = mean over repeats
%     .FrHz         overall mean stimulus rate (Hz) = mean over all stim trials
%     .baseHz       mean baseline rate (Hz)
%     .PSTH         1xT all-trials PSTH  (matches old: sum over trials / (T/1000))
%     .PSTH_single  1xOriN cell, per-orientation PSTH (same normalization)
%     .trialRepeat  tr
%     .features     1xOriN orientation values (deg)
%
%   NOTE on PSTH scaling: kept identical to the old pipeline (column-sum divided
%   by total raster duration in seconds). It is a consistent relative measure,
%   not a per-trial Hz rate.

    if nargin < 5 || isempty(psthWin), psthWin = 1; end

    out = struct('T',[], 'FrHz',NaN, 'baseHz',NaN, 'PSTH',[], ...
                 'PSTH_single',{{}}, 'trialRepeat',NaN, ...
                 'features', analysis.orientationFeatures(oriN));
    if isempty(R), return; end

    R = double(R);
    T = size(R,2);
    sW = [max(1, stimWin(1)), min(T, stimWin(2))];
    bW = [max(1, baseWin(1)), min(T, baseWin(2))];
    tS = (sW(2)-sW(1)+1) / 1000;
    tB = (bW(2)-bW(1)+1) / 1000;

    stimCounts = sum(R(:, sW(1):sW(2)), 2);
    baseCounts = sum(R(:, bW(1):bW(2)), 2);
    out.baseHz = mean(baseCounts) / max(tB, eps);
    out.FrHz   = mean(stimCounts) / max(tS, eps);

    nTr = size(R,1);
    tr  = floor(nTr / max(oriN, 1));
    out.trialRepeat = tr;

    % --- per-orientation tuning (blocked trials) ---
    if tr >= 1 && tr*oriN <= nTr
        sMat  = reshape(stimCounts(1:tr*oriN), tr, oriN);
        out.T = mean(sMat, 1) / max(tS, eps);
    else
        out.T = out.FrHz;     % fallback if the layout doesn't divide evenly
    end

    % --- PSTHs (faithful to the old normalization) ---
    out.PSTH = smoothdata(sum(R,1) / (T/1000), 'movmean', psthWin);
    ps = cell(1, oriN);
    if tr >= 1 && tr*oriN <= nTr
        for ii = 1:oriN
            rows = (1+(ii-1)*tr) : (ii*tr);
            ps{ii} = smoothdata(sum(R(rows,:),1) / (T/1000), 'movmean', psthWin);
        end
    end
    out.PSTH_single = ps;
end
