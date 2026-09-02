function [D, info] = mergeCorrectedFits(D, sourceFile)
%MERGECORRECTEDFITS  Add corrected tuning fits (as SEPARATE fields) to D.
%
%   [D, info] = data.mergeCorrectedFits(D, sourceFile)
%
%   Looks for the sidecar tunefit.correctionPath(sourceFile) (written by the
%   tuning fitter). If present, it adds two NEW fields to D WITHOUT touching the
%   originals:
%       D.fit_NL_corr  = D.fit_NL with accepted no-laser corrections overlaid
%       D.fit_L_corr   = D.fit_L  with accepted laser   corrections overlaid
%   Rows the fitter did not accept keep the original fit. loadData decides
%   whether to make the corrected curves ACTIVE (see loadData 'UseCorrected').
%
%   Matching: each saved row re-binds to the D row at its original index when the
%   identity still matches there; otherwise to the unique row with the same
%   identity tuple (U_unity/Dataset/Penetration/ch/EI/Tasknumb). Ambiguous or
%   missing matches are skipped (counted in info).
%
%   QUALITY (good/bad): if the sidecar carries a per-row UnitGood flag (the
%   tuning fitter marks units bad), this also writes D.UnitGood (logical Nx1,
%   default true) so the main app can filter on it. Unmatched units stay good.
%
%   info  struct .merged .file .nNL .nL .nSkipped .nBad
%
%   See also: tunefit.saveCorrection, tunefit.correctionPath, loadData

    info = struct('merged',false, 'file','', 'nNL',0, 'nL',0, 'nSkipped',0, 'nBad',0);
    if ~isfield(D,'fit_NL') || ~isfield(D,'fit_L'), return; end

    corrFile = tunefit.correctionPath(sourceFile);
    info.file = corrFile;
    if exist(corrFile, 'file') ~= 2, return; end

    S = load(corrFile, 'FitCorrection');
    if ~isfield(S, 'FitCorrection'), return; end
    FC = S.FitCorrection;

    N = size(D.fit_NL, 2);
    D.fit_NL_corr = D.fit_NL;          % start from the originals
    D.fit_L_corr  = D.fit_L;

    % Quality flag (good/bad): only when the sidecar carries it. Default all good
    % (so unmatched units stay good); matched rows take their saved flag. Init
    % here so a D without UnitGood (e.g. mergeCorrectedFits called standalone)
    % still gains the field.
    hasQual = isfield(FC, 'UnitGood');
    if hasQual && (~isfield(D,'UnitGood') || numel(D.UnitGood) ~= N)
        D.UnitGood = true(N, 1);
    end

    K = numel(FC.rows);
    rowMap = data.matchCorrectionRows(D, FC);     % saved row j -> D row (NaN if unmatched)
    for j = 1:K
        u = rowMap(j);
        if isnan(u), info.nSkipped = info.nSkipped + 1; continue; end
        if FC.acceptNL(j) && all(isfinite(FC.fit_NL_corr(:, j)))
            D.fit_NL_corr(:, u) = FC.fit_NL_corr(:, j); info.nNL = info.nNL + 1;
        end
        if FC.acceptL(j) && all(isfinite(FC.fit_L_corr(:, j)))
            D.fit_L_corr(:, u) = FC.fit_L_corr(:, j);   info.nL = info.nL + 1;
        end
        if hasQual
            D.UnitGood(u) = logical(FC.UnitGood(j));
            if ~D.UnitGood(u), info.nBad = info.nBad + 1; end
        end
    end
    info.merged = true;
end
