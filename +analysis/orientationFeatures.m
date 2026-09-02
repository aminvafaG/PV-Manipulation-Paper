function feats = orientationFeatures(oriN, rangeDeg)
%ORIENTATIONFEATURES  Stimulus orientations/directions for a unit.
%
%   feats = analysis.orientationFeatures(oriN)            % over [0,360)
%   feats = analysis.orientationFeatures(oriN, rangeDeg)  % over [0,rangeDeg)
%
%   The dataset stores only Ori_N (the count, 24 or 36), not the angle list.
%   Per the experiment, directions are evenly spaced over [0,360):
%       oriN = 24  ->  0, 15, 30, ..., 345
%       oriN = 36  ->  0, 10, 20, ..., 350
%   Returned as a 1xoriN row vector (degrees).

    if nargin < 2 || isempty(rangeDeg), rangeDeg = 360; end
    oriN  = round(oriN);
    feats = (0:oriN-1) * (rangeDeg / max(oriN, 1));
end
