function p = correctionPath(sourceFile)
%TUNEFIT.CORRECTIONPATH  Sidecar path for corrected fits next to a dataset.
%
%   p = tunefit.correctionPath(sourceFile)
%
%   Maps   .../Units_example.mat  ->  .../Units_example_Fit_correction.mat
%   (same folder, original base name + "_Fit_correction"). This single rule is
%   shared by the saver (tunefit.saveCorrection / the app) and the loader merge
%   (data.mergeCorrectedFits) so they always agree on the file name.
%
%   See also: tunefit.saveCorrection, data.mergeCorrectedFits, loadData

    [d, n] = fileparts(char(sourceFile));
    p = fullfile(d, [n '_Fit_correction.mat']);
end
