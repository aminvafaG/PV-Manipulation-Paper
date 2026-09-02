function [mask, info] = tuningGroupMask(D, groupName, varargin)
%TUNINGGROUPMASK  Logical Nx1 membership mask for a Visualizer_01 "TuningG" group.
%
%   mask = analysis.tuningGroupMask(D, groupName)
%   [mask, info] = analysis.tuningGroupMask(D, groupName, 'PV_cell',1, ...)
%
%   Faithful port of Visualizer_01.m's includeExcitatoryUnit /
%   includeInhibitoryUnit predicates (the old unit-group selector). It derives
%   the group purely from fields already produced by analysis.computeMetrics, so
%   NO model re-fitting is needed:
%       FrMax_L/FrMax_NL  (old FrPL/FrPNL peak rate gate)
%       fitCV_L/fitCV_NL  (old Cv gate)
%       FrMean_L/FrMean_NL(old Fr -> raw delta_Fr_2 sign gate)
%       G_type            (old multiplicative/non-linear/unknown shape class;
%                          1=Linear -> MD, 2=Non-linear -> NL, 3=Unknown -> U)
%       EI                (old experiment phase: P34=excitation, P12=inhibition)
%       HBW_pair_ok       good-HBW-pair gate for every ORI_* / NO_ORI_* group:
%                         both HBW sides computable AND laser aligned to control
%                         (analysis.computeMetrics; absent in older D -> no gate)
%
%   GROUPS (groupName, case-insensitive)
%       ALL_UNITS       every unit
%       NO_ORI_ON_PV    base FR gate AND a good HBW pair, with NEITHER the
%                       orientation-selectivity gate (fitCV_* < ThCV) NOR the
%                       dFr sign gate -- ORI_ON_PV without the Ori limit
%       NO_ORI_NO_PV    NO_ORI_ON_PV WITH the dFr sign gate back on, i.e. the
%                       PV-like units removed -- ORI_NON_PV without the Ori limit
%       ORI_ON_PV       base FR/CV gate AND a good HBW pair, WITHOUT the dFr
%                       sign gate -- ORI_NON_PV without the PV limit, so the
%                       PV-like units it excludes are kept in
%       ORI_NON_PV      base FR/CV gate AND dFr sign gate AND a good HBW pair
%                       (HBW_pair_ok == true)
%       OUTLIER         ~(base FR/CV gate AND dFr sign gate)  (NOT HBW-pair
%                       gated; unchanged inverse of the old base+sign gate)
%       ORI_NON_PV_MD   ORI_NON_PV & G_type==1  (multiplicative, Linearity in band)
%       ORI_NON_PV_NL   ORI_NON_PV & G_type==2  (non-linear)
%       ORI_NON_PV_U    ORI_NON_PV & G_type==3  (multiplicative, Linearity out of band)
%
%   The four make a 2x2 of the two limits (Ori = fitCV_* < ThCV, PV = dFr sign):
%                       PV limit ON      PV limit OFF
%       Ori limit ON    ORI_NON_PV       ORI_ON_PV
%       Ori limit OFF   NO_ORI_NO_PV     NO_ORI_ON_PV
%   Nesting: NO_ORI_ON_PV > {ORI_ON_PV, NO_ORI_NO_PV} > ORI_NON_PV. Dropping the "Ori limit"
%   means dropping ONLY the fitCV_* < ThCV upper bound (the "is this unit
%   orientation selective" test); the fitCV_* > CVlo lower bound is kept, so a
%   unit still needs a finite, fitted CV on both sides. Dropping the "PV limit"
%   means dropping the dFr sign gate, which ADMITS the units whose laser
%   response goes the PV-cell direction (it does not select them).
%
%   The base/shape thresholds match the old defaults; override via name/value:
%       PV_cell (1)  ThFrPE (5)  ThFrPI (1)  ThCV (0.96)  CVlo (0)
%
%   'ClassGrouping' ('any' | 'majority', default 'any') controls how the three
%   class groups (ORI_NON_PV_MD/NL/U) read G_type:
%       'any'      per-observation labels (the historical behavior): a recording
%                  belongs to the class it showed at that laser intensity, so a
%                  class-straddling neuron contributes recordings to BOTH the
%                  _MD and _NL groups (the manuscript's Figs. 4-5 "any-intensity
%                  populations").
%       'majority' one class per NEURON by the majority rule
%                  (viz.plots.V01util.classPerNeuron, resolved over the
%                  ORI_NON_PV population): the manuscript's Fig. 3 partition.
%                  _MD = majority D/M, _NL = majority NL, _U = Mix + Uct
%                  (equal evidence, or no NL/D-M evidence at all).
%   Non-class groups are unaffected.
%
%   info returns the building blocks (passBase, passBaseNoOSI, frGate, cvHi,
%   cvLo, signGate, isI, dFr2, oriNonPV, goodPair, oriNonPVg, oriOnPV,
%   noOriOnPV, noOriNoPV) for reuse/inspection.
%
%   See also: analysis.computeMetrics, viz.plots.Dashboard01Tab

    p = inputParser;
    p.addParameter('PV_cell', 1);
    p.addParameter('ThFrPE', 5);
    p.addParameter('ThFrPI', 1);
    p.addParameter('ThCV', 0.96);
    p.addParameter('CVlo', 0);
    p.addParameter('ClassGrouping', 'any', @(s) any(strcmpi(s, {'any','majority'})));
    p.parse(varargin{:});
    o = p.Results;

    N = localUnitCount(D);

    % --- E/I experiment label (inhibition = EI=="I"; anything else -> E) ------
    isI = false(N,1);
    if isfield(D, 'EI')
        for k = 1:N
            isI(k) = strcmpi(strtrim(string(D.EI(k))), "I");
        end
    end

    % --- base fields (NaN-filled if a metric is missing) ---------------------
    FrMaxL  = col(D, 'FrMax_L',  N);  FrMaxNL = col(D, 'FrMax_NL', N);
    cvL     = col(D, 'fitCV_L',  N);  cvNL    = col(D, 'fitCV_NL', N);
    FrL     = col(D, 'FrMean_L', N);  FrNL    = col(D, 'FrMean_NL',N);
    G       = col(D, 'G_type',   N);

    % --- base quality gate (old passesBaseSelection) -------------------------
    %  Split into its parts so the *_Good groups can drop the orientation-
    %  selectivity half (cvHi) while keeping everything else identical:
    %      frGate  peak firing rate above the E/I threshold, both conditions
    %      cvHi    fitCV_* < ThCV  -> the unit IS orientation selective
    %      cvLo    fitCV_* > CVlo  -> a finite, fitted CV exists on both sides
    thr        = o.ThFrPE * ones(N,1);  thr(isI) = o.ThFrPI;
    frGate     = FrMaxL > thr & FrMaxNL > thr;
    cvHi       = cvL < o.ThCV & cvNL < o.ThCV;
    cvLo       = cvL > o.CVlo & cvNL > o.CVlo;
    passBase      = frGate & cvHi & cvLo;   % ORI_* groups (orientation selective)
    passBaseNoOSI = frGate & cvLo;          % NO_ORI_* groups (no OSI requirement)

    % --- dFr sign gate (old PV_cell * delta_Fr_2 </> 0) ----------------------
    dFr2 = 100 * (FrL - FrNL) ./ FrNL;          % raw delta firing rate (%)
    signGate        = false(N,1);
    signGate(~isI)  = o.PV_cell * dFr2(~isI) < 0;   % excitation block
    signGate(isI)   = o.PV_cell * dFr2(isI)  > 0;   % inhibition block
    oriNonPV        = passBase & signGate;

    % --- good-HBW-pair gate (HBW_pair_ok from analysis.computeMetrics): both
    %     HBW sides computable AND laser aligned to control. Required by the
    %     ORI_* / NO_ORI_* groups; OUTLIER stays the inverse of the base+sign
    %     gate. Absent field (older D) -> no gating (goodPair all true). -------
    if isfield(D, 'HBW_pair_ok') && ~isempty(D.HBW_pair_ok)
        goodPair = col(D, 'HBW_pair_ok', N) == 1;
    else
        goodPair = true(N,1);
    end
    oriNonPVg       = oriNonPV & goodPair;        % ORI_NON_PV   with a good HBW pair
    oriOnPV         = passBase      & goodPair;  % ORI_ON_PV    (no sign gate)
    noOriOnPV       = passBaseNoOSI & goodPair;  % NO_ORI_ON_PV (no sign gate, no OSI)
    noOriNoPV       = noOriOnPV     & signGate;  % NO_ORI_NO_PV (sign gate back on, no OSI)

    % --- class labels for the _MD/_NL/_U groups: per-observation ('any') or
    %     resolved to one class per neuron by the majority rule ('majority').
    %     Resolution runs over the ORI_NON_PV rows (the classified population);
    %     without U_unity the labels stay per-observation. ---------------------
    Gcls = G; isMaj = strcmpi(o.ClassGrouping, 'majority');
    if isMaj && isfield(D, 'U_unity')
        uu = col(D, 'U_unity', N);
        Gcls = viz.plots.V01util.classPerNeuron(G, uu, find(oriNonPVg));
    end

    switch upper(strtrim(char(groupName)))
        case 'ALL_UNITS',     mask = true(N,1);
        case 'NO_ORI_ON_PV',  mask = noOriOnPV;
        case 'NO_ORI_NO_PV',  mask = noOriNoPV;
        case 'ORI_ON_PV',     mask = oriOnPV;
        case 'ORI_NON_PV',    mask = oriNonPVg;
        case 'OUTLIER',       mask = ~oriNonPV;
        case 'ORI_NON_PV_MD', mask = oriNonPVg & (Gcls == 1);
        case 'ORI_NON_PV_NL', mask = oriNonPVg & (Gcls == 2);
        case 'ORI_NON_PV_U'
            if isMaj, mask = oriNonPVg & (Gcls == 3 | Gcls == 0);  % Uct + Mix
            else,     mask = oriNonPVg & (Gcls == 3);
            end
        otherwise
            error('analysis:tuningGroupMask:unknownGroup', ...
                'Unknown TuningG group "%s".', char(groupName));
    end
    mask = logical(mask(:));

    info = struct('passBase', passBase, 'passBaseNoOSI', passBaseNoOSI, ...
                  'frGate', frGate, 'cvHi', cvHi, 'cvLo', cvLo, ...
                  'signGate', signGate, ...
                  'isI', isI, 'dFr2', dFr2, 'oriNonPV', oriNonPV, ...
                  'goodPair', goodPair, 'oriNonPVg', oriNonPVg, ...
                  'oriOnPV', oriOnPV, 'noOriOnPV', noOriOnPV, ...
                  'noOriNoPV', noOriNoPV);
end

% ----------------------------------------------------------------------- %
function v = col(D, name, N)
%COL  D.name as an Nx1 double, or NaN(N,1) if the field is absent.
    if isfield(D, name) && ~isempty(D.(name))
        v = double(D.(name)(:));
        if numel(v) ~= N, v = nan(N,1); end
    else
        v = nan(N,1);
    end
end

% ----------------------------------------------------------------------- %
function N = localUnitCount(D)
%LOCALUNITCOUNT  Number of units, robust to which fields are present.
    N = 0;
    try
        N = filter.unitCount(D);
    catch
        f = fieldnames(D);
        for i = 1:numel(f)
            x = D.(f{i});
            if (isnumeric(x) || islogical(x) || iscell(x) || isstring(x)) ...
                    && ~strcmp(f{i},'Meta')
                N = size(x, 1); if N > 1, break; end
            end
        end
    end
end
