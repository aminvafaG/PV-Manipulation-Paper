function u = matchCorrectionRows(D, FC)
%DATA.MATCHCORRECTIONROWS  Bind each saved correction row to a D row.
%
%   u = data.matchCorrectionRows(D, FC)
%
%   For each saved row j in a FitCorrection struct FC (see tunefit.saveCorrection),
%   returns the D row index u(j) it binds to: its original index when the identity
%   still matches there, otherwise the unique row with the same identity tuple
%   (U_unity / Dataset / Penetration / ch / EI / Tasknumb); NaN when the match is
%   ambiguous or missing. Shared by data.mergeCorrectedFits and the fit-corrector
%   app's "load corrected file" so both bind saved rows to D identically.
%
%   See also: data.mergeCorrectedFits, tunefit.saveCorrection, tunefit.correctionPath

    u = [];
    if ~isstruct(FC) || ~isfield(FC, 'rows'), return; end
    N = 0;
    if isfield(D, 'fit_NL'),  N = size(D.fit_NL, 2);
    elseif isfield(D, 'EI'),  N = numel(D.EI);
    end
    K = numel(FC.rows);
    u = nan(1, K);
    for j = 1:K
        u(j) = matchRow(D, FC, j, N);
    end
end

% ----------------------------------------------------------------------- %
function u = matchRow(D, FC, j, N)
%MATCHROW  D row for saved column j: original index if its identity still
%   matches, else the unique identity match, else NaN.
    u = NaN;
    u0 = FC.rows(j);
    if u0 >= 1 && u0 <= N && identityMatches(D, u0, FC, j)
        u = u0; return;
    end
    hits = find(identityMatchesAll(D, FC, j, N));
    if isscalar(hits), u = hits; end
end

function tf = identityMatches(D, u, FC, j)
    tf = eqNum(D,'U_unity',u, FC,'U_unity',j) ...
       && eqNum(D,'Dataset',u, FC,'Dataset',j) ...
       && eqNum(D,'Penetration',u, FC,'Penetration',j) ...
       && eqNum(D,'ch',u, FC,'ch',j) ...
       && eqStr(D,'EI',u, FC,'EI',j) ...
       && eqStr(D,'Tasknumb',u, FC,'Tasknumb',j);
end

function m = identityMatchesAll(D, FC, j, N)
    m = true(N, 1);
    m = m & colEqNum(D,'U_unity', FC,'U_unity',j, N);
    m = m & colEqNum(D,'Dataset', FC,'Dataset',j, N);
    m = m & colEqNum(D,'Penetration', FC,'Penetration',j, N);
    m = m & colEqNum(D,'ch', FC,'ch',j, N);
    m = m & colEqStr(D,'EI', FC,'EI',j, N);
    m = m & colEqStr(D,'Tasknumb', FC,'Tasknumb',j, N);
end

function tf = eqNum(D,df,u, FC,ff,j)
    if ~isfield(D,df) || ~isfield(FC,ff), tf = true; return; end    % field absent -> ignore
    a = double(D.(df)(u)); b = double(FC.(ff)(j));
    tf = (isnan(a) && isnan(b)) || a == b;
end

function tf = eqStr(D,df,u, FC,ff,j)
    if ~isfield(D,df) || ~isfield(FC,ff), tf = true; return; end
    tf = strcmp(strtrim(string(D.(df)(u))), strtrim(string(FC.(ff)(j))));
end

function m = colEqNum(D,df, FC,ff,j, N)
    if ~isfield(D,df) || ~isfield(FC,ff), m = true(N,1); return; end
    a = double(D.(df)(:)); b = double(FC.(ff)(j));
    if isnan(b), m = isnan(a); else, m = (a == b); end
    m = m(:);
end

function m = colEqStr(D,df, FC,ff,j, N)
    if ~isfield(D,df) || ~isfield(FC,ff), m = true(N,1); return; end
    m = (strtrim(string(D.(df)(:))) == strtrim(string(FC.(ff)(j))));
    m = m(:);
end
