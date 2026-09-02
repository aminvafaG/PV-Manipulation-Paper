function D = computeMetrics(D, dm, opts)
%COMPUTEMETRICS  Per-unit scalar metrics from the rasters + fitted tuning.
%
%   D = analysis.computeMetrics(D)
%   D = analysis.computeMetrics(D, dm)   % dm = the DataManager from loadData
%   D = analysis.computeMetrics(D, dm, 'OSIPref',"peak0", 'HBWQuantize',true, ...
%                                      'target_center',179)
%
%   Options (to optionally match Visualizer_01; all default to current behavior):
%     OSIPref       "global" (laser OSI from the global max) | "peak0" (from the
%                   windowed control-aligned peak0)                 [default "peak0"]
%     HBWQuantize   false interpolates HBW crossings; true uses integer-sample
%                   crossings (no interpolation)                    [default true]
%     target_center peak-center angle; 179 centers on sample index 180 [default 179]
%     D_ori         nonpref offset (deg) for Linearity_M nonpref points [default 20]
%     MthE          Linearity_M "Linear" band for excitation (EI~="I") [default [-0.02 0.02]]
%     MthI          Linearity_M "Linear" band for inhibition (EI=="I") [default [-0.02 0.02]]
%
%   Computes, for every unit, the parameters used by the old pipeline
%   (Fit_Function_05 + Compute_Tuning_Metrics_05) and adds them as Nx1 fields
%   of D, so they are immediately plottable and filterable. Naming: _L = laser
%   (RasL / fit_L), _NL = no-laser/control (RasNL / fit_NL).
%
%   NAMING by provenance:  Fr* = MEASURED from rasters, fit* = from the FITTED
%   tuning curve.  So FrMax_L (measured peak rate) is distinct from fitMax_L
%   (peak of the fit). Orientation metrics (fitOSI/fitCV/fitHBW/fitFWHM/
%   fitPrefOri/fitMax/fitMin) come from fit_L/fit_NL on a 0:359 deg grid.
%   F1/F0 is taken from the dataset's precomputed F1F0 field (needs the original
%   DataManager `dm`; pass it from loadData).
%
%   Added fields:
%     FrMean_L/_NL  FrBase_L/_NL  FrMax_L/_NL  FrMin_L/_NL   (MEASURED, rasters)
%     fitOSI_L/_NL  fitCV_L/_NL   fitHBW_L/_NL  fitFWHM_L/_NL (FIT)
%     fitPrefOri1/2_L/_NL  fitMax1/2_L/_NL   (two upward peaks: ori + value)
%     fitMinOri1/2_L/_NL   fitMin1/2_L/_NL   (two troughs: ori + value; 1=most extreme)
%     dTun_d1..d4 (360xN derivatives of Delta_tun_nc)  dTun_nExtrema  dTun_d2_center  dTun_d4_center
%     Delta_Fr  Delta_Fr_I  Delta_CV  Delta_OSI  Delta_HBW  Delta_FWHM
%     Delta_HBW_rel_E  Delta_HBW_rel_I
%     Linearity_M  (Visualizer_01 "MMM" = MDM_NL - MDM_L on the centered curves)
%     G_type   (1=Linear / 2=Non-linear / 3=Unknown; Delta_tun_nc curvature at
%              center + Linearity_M vs MthE/MthI, per E/I; NaN if unclassifiable)
%     F1F0_L/_NL   Rsq_L/_NL (gof)   Simp_Comp (1=simple,0=complex)  -- need dm
%
%   E/I CONVENTION: for inhibition units (EI=="I") Delta_tun / Delta_tun_nc /
%   Ratio_tun and the dTun_* derivatives use control-minus-laser (control/laser
%   for the ratio) so the I effect points like an E unit; E units keep laser
%   minus control. This flip makes one G_type rule reproduce Visualizer_01's
%   separate E-block and I-block classifications.
%
%   PROVENANCE: every field added here is registered with the DataManager as a
%   calculated variable, so D.Meta.kind tells loaded from calculated:
%       loaded     -> kind "source"   (e.g. ch, fit_L, F1F0_L, Rsq_L)
%       calculated -> kind "computed" (e.g. fitOSI_L, Delta_Fr, G_type)
%   Query:  D.Meta(D.Meta.kind=="computed", :)   % all calculated variables
%   This needs `dm`; without it the values are still added to D but untracked.
%
%   To add a metric: compute an Nx1 vector, then register it with one line:
%       D = reg(D, dm, hasDM, 'MyMetric', value, 'what it is');
%
%   See also: analysis.tuningFromRaster, analysis.tuningMetrics, analysis.windows

    arguments
        D
        dm = []                            % so `reg` can always take dm
        opts.OSIPref (1,1) string {mustBeMember(opts.OSIPref,["global","peak0"])} = "peak0"
        opts.HBWQuantize (1,1) logical = true
        opts.target_center (1,1) double = 179
        opts.D_ori (1,1) double {mustBePositive, mustBeInteger} = 20   % nonpref offset (deg) for Linearity_M
        opts.MthE (1,2) double = [-0.02 0.02]   % Linearity_M "Linear" band, excitation (EI=="E")
        opts.MthI (1,2) double = [-0.02 0.02]   % Linearity_M "Linear" band, inhibition (EI=="I")
        % Extra name/value pairs forwarded verbatim to analysis.exponentialModel
        % for the per-unit I/O fit, e.g.
        %   {'freeFloor',true}
        %   {'offsetBounds',[-Inf Inf],'exponentBounds',[-Inf Inf]}   % remove bounds
        %   {'multiStart',false}  /  {'Algorithm','levenberg-marquardt'}
        % Default {} reproduces the validated fit. Affects every ExpM_* field (and
        % thus the I/O-model figures). Part of the computeMetricsCached cache key,
        % so changing it auto-invalidates the cache.
        opts.ExpMArgs cell = {}
        % Extra name/value pairs forwarded to analysis.linearThresholdModel for the
        % per-unit threshold-linear (LTM) fit, e.g. {'floorAtZero',true} to lock the
        % PVA floor at 0 (2-param). Default {} = the validated free-floor fit.
        % Affects every LTM_* field; also part of the cache key.
        opts.LTMArgs cell = {}
    end
    hasDM = ~isempty(dm);
    N     = filter.unitCount(D);
    grid  = 0:359;                         % degrees; matches fit_L/fit_NL rows
    ratio_eps = 1e-9;                      % guard for the laser/control ratio

    % measured firing rates (from rasters): 'Fr*'
    [FrMean_L, FrMean_NL, FrBase_L, FrBase_NL] = deal(nan(N,1));
    [FrMax_L, FrMax_NL, FrMin_L, FrMin_NL] = deal(nan(N,1));
    % fitted-curve metrics: 'fit*'
    [fitOSI_L, fitOSI_NL, fitCV_L, fitCV_NL, fitHBW_L, fitHBW_NL, fitFWHM_L, fitFWHM_NL, G_type] = deal(nan(N,1));
    % two upward peaks (1 = higher) and two troughs (1 = deeper) of each fit,
    % with their orientations (deg) and values; NaN if a curve lacks one.
    [fitPrefOri1_L, fitPrefOri2_L, fitPrefOri1_NL, fitPrefOri2_NL, ...
     fitMax1_L, fitMax2_L, fitMax1_NL, fitMax2_NL, ...
     fitMinOri1_L, fitMinOri2_L, fitMinOri1_NL, fitMinOri2_NL, ...
     fitMin1_L, fitMin2_L, fitMin1_NL, fitMin2_NL] = deal(nan(N,1));

    % control-aligned (Visualizer_01 strategy) tuning curves + flags
    [fit_mid_L, fit_mid_NL, fit_mid_nc_L, fit_mid_nc_NL, fit_mid_self_L, ...
     fit_mid_self_NL, Delta_tun, Delta_tun_nc, Ratio_tun] = deal(nan(numel(grid), N));
    [Align_bad, Align_peak0_dist] = deal(nan(N,1));
    % HBW pair validity flags as 0/1 (widths are kept POSITIVE; see analysis.alignTunings)
    [HBW_L_nan, HBW_NL_nan, HBW_pair_ok] = deal(nan(N,1));

    % delta-tuning derivatives (Visualizer_01) from the control-peak-normalized delta
    [dTun_d1, dTun_d2, dTun_d3, dTun_d4] = deal(nan(numel(grid), N));
    [dTun_nExtrema, dTun_d2_center, dTun_d4_center] = deal(nan(N,1));
    Linearity_M = nan(N,1);                % Visualizer_01 "MMM" (MDM_NL - MDM_L)

    % linear-threshold model (faithful F2_5_3 LTM fit): E = free-floor
    % piecewise threshold-linear; I = plain linear (+ reversed). Control-peak-
    % normalized aligned curves; parameters in 100x ("percent") units.
    [LTM_slope, LTM_intercept, LTM_floor, LTM_breakpoint, LTM_slope_rev, ...
     LTM_intercept_rev, LTM_R2, LTM_R2adj, LTM_RMSE, LTM_SSE, LTM_n] = deal(nan(N,1));
    LTM_fit_L = nan(numel(grid), N);       % predicted laser tuning (360xN)

    % exponential model  target/max(start) = exp(exponent*x - offset), where
    % x is the Sin5_3 transform of the start curve. start->target by E/I:
    % E start=control reach laser; I start=laser reach control.
    [ExpM_exponent, ExpM_offset, ExpM_scale, ExpM_theta, ExpM_R2, ExpM_R2adj, ...
     ExpM_RMSE, ExpM_SSE, ExpM_n, ExpM_dFR] = deal(nan(N,1));
    ExpM_fit = nan(numel(grid), N);        % predicted target tuning (360xN)

    % HBW / OSI / CV measured on each model's control- and laser-condition
    % curves (one actual input, one model prediction); delta = L - NL.
    [LTM_HBW_NL,  LTM_HBW_L,  LTM_OSI_NL,  LTM_OSI_L,  LTM_CV_NL,  LTM_CV_L]  = deal(nan(N,1));
    [ExpM_HBW_NL, ExpM_HBW_L, ExpM_OSI_NL, ExpM_OSI_L, ExpM_CV_NL, ExpM_CV_L] = deal(nan(N,1));
    hasOri    = isfield(D, 'Ori_N');
    hasEI     = isfield(D, 'EI');
    centerIdx = mod(round(opts.target_center), 360) + 1;   % sample index of the center
    if ~hasEI
        warning('computeMetrics:noEI', ...
            ['No EI field in D: treating every unit as the excitation ' ...
             'convention (Delta_tun = laser - control) for Delta_tun / ' ...
             'Delta_tun_nc / Ratio_tun / dTun_* / G_type.']);
    end

    for i = 1 :N
        timing = D.Rast_time(i,:);
        [bW, sW] = analysis.windows(timing,0);

        % --- firing rates from the rasters (pooled + per-orientation max/min) ---
        oriN = NaN; if hasOri, oriN = D.Ori_N(i); end
        cNL = rates(D.RasNL{i}, sW, bW, oriN);   % [FrMean FrBase FrMax FrMin]
        cL  = rates(D.RasL{i},  sW, bW, oriN);
        FrMean_NL(i)=cNL(1); FrBase_NL(i)=cNL(2); FrMax_NL(i)=cNL(3); FrMin_NL(i)=cNL(4);
        FrMean_L(i) =cL(1);  FrBase_L(i) =cL(2);  FrMax_L(i) =cL(3);  FrMin_L(i) =cL(4);

        % --- orientation metrics from the fitted curves ---
        %  CV/extrema are shift-invariant -> taken per side. HBW/FWHM (and,
        %  with OSIPref="peak0", the laser OSI) are measured on the CONTROL-
        %  ALIGNED curves (analysis.alignTunings) so the laser is referenced to
        %  the control's preferred orientation, not its own global peak.
        mNL = analysis.tuningMetrics(grid, D.fit_NL(:,i), ...
                  'target_center', opts.target_center, 'HBWQuantize', opts.HBWQuantize);
        mL  = analysis.tuningMetrics(grid, D.fit_L(:,i), ...
                  'target_center', opts.target_center, 'HBWQuantize', opts.HBWQuantize);
        fitOSI_NL(i)=mNL.OSI; fitCV_NL(i)=mNL.CV; fitCV_L(i)=mL.CV;

        % two upward peaks (1=higher) and two troughs (1=deeper) of each fit
        exNL = analysis.tuningExtrema(grid, D.fit_NL(:,i));
        exL  = analysis.tuningExtrema(grid, D.fit_L(:,i));
        [fitPrefOri1_NL(i), fitPrefOri2_NL(i), fitMax1_NL(i), fitMax2_NL(i)] = pick2(exNL.maxOri, exNL.maxVal);
        [fitMinOri1_NL(i),  fitMinOri2_NL(i),  fitMin1_NL(i), fitMin2_NL(i)] = pick2(exNL.minOri, exNL.minVal);
        [fitPrefOri1_L(i),  fitPrefOri2_L(i),  fitMax1_L(i),  fitMax2_L(i)]  = pick2(exL.maxOri,  exL.maxVal);
        [fitMinOri1_L(i),   fitMinOri2_L(i),   fitMin1_L(i),  fitMin2_L(i)]  = pick2(exL.minOri,  exL.minVal);

        % control-aligned tuning (laser = 1st, control = 2nd) -> HBW + curves
        A = analysis.alignTunings(grid, D.fit_L(:,i), D.fit_NL(:,i), ...
                  'target_center', opts.target_center, 'HBWQuantize', opts.HBWQuantize);
        if opts.OSIPref == "peak0"
            fitOSI_L(i) = A.OSI_laser_peak0;  % laser preferred = windowed peak0
        else
            fitOSI_L(i) = mL.OSI;             % laser preferred = global max
        end
        fitHBW_NL(i)  = A.HBW_control;  fitHBW_L(i)  = A.HBW_laser;
        fitFWHM_NL(i) = A.FWHM_control; fitFWHM_L(i) = A.FWHM_laser;
        fit_mid_L(:,i)      = A.laser(:);        fit_mid_NL(:,i)      = A.control(:);
        fit_mid_nc_L(:,i)   = A.laser_nc(:);     fit_mid_nc_NL(:,i)   = A.control_nc(:);
        fit_mid_self_L(:,i) = A.laser_self(:);   fit_mid_self_NL(:,i) = A.control_self(:);
        Align_bad(i)        = A.bad;             Align_peak0_dist(i)  = A.peak0DistDeg;
        HBW_L_nan(i)        = A.HBW_L_nan;       HBW_NL_nan(i)        = A.HBW_NL_nan;
        HBW_pair_ok(i)      = A.HBW_pair_ok;     % good HBW pair: both computable & aligned

        % E/I label (excitation default; inhibition = EI=="I")
        isI = hasEI && strcmpi(strtrim(string(D.EI(i))), "I");

        % --- linear-threshold model (faithful F2_5_3 LTM fit) on the
        %     control-peak-normalized aligned curves. E: free-floor piecewise
        %     threshold-linear (vertical fminsearch). I: plain linear (polyfit)
        %     + reversed linear. x = 100*control, y = 100*laser.
        LTM = analysis.linearThresholdModel(A.control_nc, A.laser_nc, 'isInhibitory', isI, opts.LTMArgs{:});
        LTM_slope(i)=LTM.slope;          LTM_intercept(i)=LTM.intercept;
        LTM_floor(i)=LTM.floor;          LTM_breakpoint(i)=LTM.breakpoint;
        LTM_slope_rev(i)=LTM.slope_rev;  LTM_intercept_rev(i)=LTM.intercept_rev;
        LTM_R2(i)=LTM.R2; LTM_R2adj(i)=LTM.R2adj; LTM_RMSE(i)=LTM.RMSE; LTM_SSE(i)=LTM.SSE;
        LTM_n(i)=LTM.n;   LTM_fit_L(:,i)=LTM.predicted(:);

        % --- E/I delta-tuning convention --------------------------------------
        %  Excitation (default): delta = laser - control,  ratio = laser/control.
        %  Inhibition (EI=="I"): delta = control - laser,  ratio = control/laser,
        %  so the I-unit laser effect points the SAME way as an E unit. This
        %  flips the sign of the delta curves AND their derivatives for I units.
        if isI
            deltaVec   = -A.delta;                            % control - laser
            deltaNcVec = -A.delta_nc;                         % control_nc - laser_nc
            ratioVec   = A.control ./ (A.laser + ratio_eps);  % control ./ laser
        else
            deltaVec   = A.delta;                             % laser - control
            deltaNcVec = A.delta_nc;
            ratioVec   = A.ratio;                             % laser ./ control
        end
        Delta_tun(:,i)    = deltaVec(:);
        Delta_tun_nc(:,i) = deltaNcVec(:);
        Ratio_tun(:,i)    = ratioVec(:);

        % --- delta-tuning derivatives (Visualizer_01) on the (E/I) nc delta ---
        dv = analysis.tuningDerivatives(deltaNcVec, centerIdx);
        dTun_d1(:,i)=dv.d1(:); dTun_d2(:,i)=dv.d2(:);
        dTun_d3(:,i)=dv.d3(:); dTun_d4(:,i)=dv.d4(:);
        dTun_nExtrema(i)=dv.nExtrema; dTun_d2_center(i)=dv.d2_center; dTun_d4_center(i)=dv.d4_center;

        % --- Linearity_M (Visualizer_01 "MMM"), from the shifted tuning curves
        Linearity_M(i) = linearityM(A.control, A.laser, centerIdx, opts.D_ori);

        % --- G-type: Linear(1)/Non-linear(2)/Unknown(3) from the delta curvature
        %     at center + Linearity_M, thresholded per E/I (Visualizer_01). The
        %     task-1 flip aligns I to E, so one shape rule reproduces the V01
        %     E-block (E) and I-block (I) classifications exactly.
        if isI, Mth = opts.MthI; else, Mth = opts.MthE; end
        G_type(i) = classifyG(dv.d2_center, dv.d4_center, Linearity_M(i), Mth);
    end

    % --- direction selectivity index (Visualizer_01 lines 936-978): from the
    %     two opposite-direction peaks of the raw fitted curve, DSi = |P1-P2| /
    %     (P1+P2). Laser uses fit_L, control uses fit_NL.
    DSiL = nan(N,1); DSiNL = nan(N,1);
    for i = 1:N
        DSiL(i)  = dirSelectivity(D.fit_L(:,i));
        DSiNL(i) = dirSelectivity(D.fit_NL(:,i));
    end

    % --- exponential model (start -> target tuning transformation) --------
    %  E: start=control reach laser;  I: start=laser reach control. Uses the
    %  Sin5_3 input transform = log(start_n)*(1+dFR*cratio) + SPlus*dFR*cratio,
    %  with per-unit dFR (Delta_Fr for E, Delta_Fr_I for I), SPlus=-log(FrBase/
    %  FrMax), and cratio = DFRML2/DFRML_LG. The correction is applied ONLY to
    %  NON-LINEAR units (G_type==2) and only for LG 1/2/3 (F2_5_3 I_*_g row 3);
    %  every other unit gets pure log(start_n). DFRML_k = mean over LG==k of the
    %  SIGN-based DeltaFR_N (Delta_Fr if suppressed, else Delta_Fr_I).
    Delta_Fr_vec   = (FrMean_L - FrMean_NL) ./ FrMean_NL;     % E convention
    Delta_Fr_I_vec = (FrMean_NL - FrMean_L) ./ FrMean_L;      % I convention (reverse)
    isIvec = false(N,1);
    if hasEI
        for k = 1:N, isIvec(k) = strcmpi(strtrim(string(D.EI(k))), "I"); end
    end
    ExpM_dFR(isIvec)  = Delta_Fr_I_vec(isIvec);              % per-unit Dlt_fr (E/I-based)
    ExpM_dFR(~isIvec) = Delta_Fr_vec(~isIvec);
    % DFRML layer means use F2_5_3's SIGN-based DeltaFR_N over ALL units:
    % Delta_Fr where the laser suppressed firing, Delta_Fr_I where it enhanced.
    deltaFR_N = Delta_Fr_vec;
    deltaFR_N(Delta_Fr_vec > 0) = Delta_Fr_I_vec(Delta_Fr_vec > 0);
    % LG arrives as a string layer label ("SG"/"G"/"IG"/"Deep"); map it to the
    % numeric layer group F2_5_3 used (SG=1, G=2, IG=3, Deep=4). double() on the
    % string is NaN, which would silently disable the cratio correction below
    % (no unit would ever match LG 1/2/3). Already-numeric LG is passed through.
    LGv = nan(N,1);
    if isfield(D,'LG')
        LGstr = strtrim(string(D.LG(:)));
        LGv(LGstr=="SG")   = 1;
        LGv(LGstr=="G")    = 2;
        LGv(LGstr=="IG")   = 3;
        LGv(LGstr=="Deep") = 4;
        numLG = double(LGstr);                       % accept already-numeric LG
        take  = isnan(LGv) & ~isnan(numLG);
        LGv(take) = numLG(take);
    end
    dfrml1 = mean(deltaFR_N(LGv==1 & isfinite(deltaFR_N)));
    dfrml2 = mean(deltaFR_N(LGv==2 & isfinite(deltaFR_N)));
    dfrml3 = mean(deltaFR_N(LGv==3 & isfinite(deltaFR_N)));

    for i = 1:N
        if isIvec(i)
            startC = fit_mid_nc_L(:,i);  targetC = fit_mid_nc_NL(:,i);
        else
            startC = fit_mid_nc_NL(:,i); targetC = fit_mid_nc_L(:,i);
        end
        % Sin5_3 firing-rate correction applies ONLY to NON-LINEAR units
        % (F2_5_3 I_ext_g/I_inh_g row 3 = "d2<0 | d4>0" = G_type==2); linear /
        % multiplicative / unclassified units get pure log(start_n) (cratio=0).
        if G_type(i) == 2
            switch LGv(i)
                case 1,    cr = safediv(dfrml2, dfrml1);
                case 2,    cr = 1;
                case 3,    cr = safediv(dfrml2, dfrml3);
                otherwise, cr = 0;      % deep units (LG 4) / unknown layer: no correction
            end
        else
            cr = 0;
        end
        SPlus = -log(FrBase_NL(i) / FrMax_NL(i));
        if ~isfinite(SPlus), SPlus = 0; end
        EM = analysis.exponentialModel(startC, targetC, ...
                'dFR', ExpM_dFR(i), 'cratio', cr, 'SPlus', SPlus, opts.ExpMArgs{:});
        ExpM_exponent(i)=EM.exponent; ExpM_offset(i)=EM.offset; ExpM_scale(i)=EM.scale;
        ExpM_theta(i)=EM.offset / EM.exponent;     % old F2_5_3 expp1 = b2/b3 (offset/exponent)
        ExpM_R2(i)=EM.R2; ExpM_R2adj(i)=EM.R2adj; ExpM_RMSE(i)=EM.RMSE; ExpM_SSE(i)=EM.SSE;
        ExpM_n(i)=EM.n;   ExpM_fit(:,i)=EM.predicted(:);

        % HBW / OSI / CV on each model's control- and laser-condition curves,
        % computed the SAME way as the actual fit metrics: HBW (+ laser OSI) from
        % analysis.alignTunings (control-aligned, same target_center/HBWQuantize,
        % bad-unit flag); control OSI = peak-trough ratio; CV = circular variance.
        %  LTM: control = actual control (fit_mid_nc_NL), laser = predicted (LTM_fit_L).
        Altm = analysis.alignTunings(grid, LTM_fit_L(:,i), fit_mid_nc_NL(:,i), ...
                   'target_center', opts.target_center, 'HBWQuantize', opts.HBWQuantize);
        LTM_HBW_NL(i)=Altm.HBW_control;  LTM_HBW_L(i)=Altm.HBW_laser;
        LTM_OSI_NL(i)=Altm.OSI_control;
        if opts.OSIPref=="peak0", LTM_OSI_L(i)=Altm.OSI_laser_peak0; else, LTM_OSI_L(i)=Altm.OSI_laser_global; end
        LTM_CV_NL(i)=circVar(fit_mid_nc_NL(:,i));  LTM_CV_L(i)=circVar(LTM_fit_L(:,i));
        %  ExpM: start = actual input, ExpM_fit = predicted target. E reaches the
        %  laser, I reaches the control, so the predicted curve is the laser (E)
        %  or control (I) condition.
        predC = ExpM_fit(:,i);
        if isIvec(i)
            expCtrlC = predC;   expLasC = startC;        % I: predicted control, actual laser
        else
            expCtrlC = startC;  expLasC = predC;         % E: actual control, predicted laser
        end
        Aexp = analysis.alignTunings(grid, expLasC, expCtrlC, ...
                   'target_center', opts.target_center, 'HBWQuantize', opts.HBWQuantize);
        ExpM_HBW_NL(i)=Aexp.HBW_control;  ExpM_HBW_L(i)=Aexp.HBW_laser;
        ExpM_OSI_NL(i)=Aexp.OSI_control;
        if opts.OSIPref=="peak0", ExpM_OSI_L(i)=Aexp.OSI_laser_peak0; else, ExpM_OSI_L(i)=Aexp.OSI_laser_global; end
        ExpM_CV_NL(i)=circVar(expCtrlC);  ExpM_CV_L(i)=circVar(expLasC);
    end

    % --- register calculated metrics (kind "computed" in D.Meta) ----------
    D = reg(D, dm, hasDM, 'FrMean_L',  FrMean_L,  'Mean stimulus firing rate, laser (Hz; measured from rasters).');
    D = reg(D, dm, hasDM, 'FrMean_NL', FrMean_NL, 'Mean stimulus firing rate, control (Hz; measured from rasters).');
    D = reg(D, dm, hasDM, 'FrBase_L',  FrBase_L,  'Baseline firing rate, laser (Hz; measured from rasters).');
    D = reg(D, dm, hasDM, 'FrBase_NL', FrBase_NL, 'Baseline firing rate, control (Hz; measured from rasters).');
    D = reg(D, dm, hasDM, 'FrMax_L',   FrMax_L,   'Max MEASURED firing rate across orientations, laser (Hz; cf fitMax_L).');
    D = reg(D, dm, hasDM, 'FrMax_NL',  FrMax_NL,  'Max MEASURED firing rate across orientations, control (Hz; cf fitMax_NL).');
    D = reg(D, dm, hasDM, 'FrMin_L',   FrMin_L,   'Min MEASURED firing rate across orientations, laser (Hz; cf fitMin_L).');
    D = reg(D, dm, hasDM, 'FrMin_NL',  FrMin_NL,  'Min MEASURED firing rate across orientations, control (Hz; cf fitMin_NL).');
    D = reg(D, dm, hasDM, 'fitOSI_L',  fitOSI_L,  'Orientation selectivity, laser (fit; global max or peak0 per OSIPref).');
    D = reg(D, dm, hasDM, 'fitOSI_NL', fitOSI_NL, 'Orientation selectivity, control (fit).');
    D = reg(D, dm, hasDM, 'fitCV_L',   fitCV_L,   'Circular variance, laser (fit).');
    D = reg(D, dm, hasDM, 'fitCV_NL',  fitCV_NL,  'Circular variance, control (fit).');
    D = reg(D, dm, hasDM, 'fitHBW_L',  fitHBW_L,  'Half-bandwidth deg, laser (fit, control-aligned; always >=0, NaN if not computable; see HBW_pair_ok/Align_bad).');
    D = reg(D, dm, hasDM, 'fitHBW_NL', fitHBW_NL, 'Half-bandwidth deg, control (fit, peak-centered; always >=0, NaN if not computable; see HBW_pair_ok/Align_bad).');
    D = reg(D, dm, hasDM, 'fitFWHM_L', fitFWHM_L, 'Half-width at half-max deg, laser (fit, control-aligned; always >=0, NaN if not computable).');
    D = reg(D, dm, hasDM, 'fitFWHM_NL',fitFWHM_NL,'Half-width at half-max deg, control (fit, peak-centered; always >=0, NaN if not computable).');
    % two upward peaks (1 = higher, 2 = second) and two troughs (1 = deeper,
    % 2 = second) of each FITTED curve: orientations (deg) + values. NaN if the
    % curve has fewer than two of that extremum.
    D = reg(D, dm, hasDM, 'fitPrefOri1_L', fitPrefOri1_L, 'Orientation of the higher fit peak, laser (deg).');
    D = reg(D, dm, hasDM, 'fitPrefOri1_NL',fitPrefOri1_NL,'Orientation of the higher fit peak, control (deg).');
    D = reg(D, dm, hasDM, 'fitPrefOri2_L', fitPrefOri2_L, 'Orientation of the 2nd fit peak, laser (deg; NaN if none).');
    D = reg(D, dm, hasDM, 'fitPrefOri2_NL',fitPrefOri2_NL,'Orientation of the 2nd fit peak, control (deg; NaN if none).');
    D = reg(D, dm, hasDM, 'fitMax1_L',  fitMax1_L,  'Fit value at the higher peak, laser (cf FrMax_L = measured).');
    D = reg(D, dm, hasDM, 'fitMax1_NL', fitMax1_NL, 'Fit value at the higher peak, control (cf FrMax_NL = measured).');
    D = reg(D, dm, hasDM, 'fitMax2_L',  fitMax2_L,  'Fit value at the 2nd peak, laser (NaN if none).');
    D = reg(D, dm, hasDM, 'fitMax2_NL', fitMax2_NL, 'Fit value at the 2nd peak, control (NaN if none).');
    D = reg(D, dm, hasDM, 'fitMinOri1_L', fitMinOri1_L, 'Orientation of the deeper fit trough, laser (deg).');
    D = reg(D, dm, hasDM, 'fitMinOri1_NL',fitMinOri1_NL,'Orientation of the deeper fit trough, control (deg).');
    D = reg(D, dm, hasDM, 'fitMinOri2_L', fitMinOri2_L, 'Orientation of the 2nd fit trough, laser (deg; NaN if none).');
    D = reg(D, dm, hasDM, 'fitMinOri2_NL',fitMinOri2_NL,'Orientation of the 2nd fit trough, control (deg; NaN if none).');
    D = reg(D, dm, hasDM, 'fitMin1_L',  fitMin1_L,  'Fit value at the deeper trough, laser (cf FrMin_L = measured).');
    D = reg(D, dm, hasDM, 'fitMin1_NL', fitMin1_NL, 'Fit value at the deeper trough, control (cf FrMin_NL = measured).');
    D = reg(D, dm, hasDM, 'fitMin2_L',  fitMin2_L,  'Fit value at the 2nd trough, laser (NaN if none).');
    D = reg(D, dm, hasDM, 'fitMin2_NL', fitMin2_NL, 'Fit value at the 2nd trough, control (NaN if none).');
    D = reg(D, dm, hasDM, 'G_type',    G_type,    'Shape class 1=Linear / 2=Non-linear / 3=Unknown (Visualizer_01), from the Delta_tun_nc 2nd/4th derivative at center + Linearity_M vs MthE/MthI; NaN if unclassifiable.');
    D = reg(D, dm, hasDM, 'Linearity_M', Linearity_M, 'Visualizer_01 "MMM" linearity index: MDM_NL - MDM_L, where MDM = nonpref/pref on the peak-centered fit_mid curves (nonpref = mean at +/-D_ori deg). >0 = laser sharpens tuning.');

    % --- laser-vs-control changes (laser minus control) ---
    D = reg(D, dm, hasDM, 'Delta_Fr',   (FrMean_L-FrMean_NL)./FrMean_NL, 'Mean-rate change (L-NL)/NL.');
    D = reg(D, dm, hasDM, 'Delta_Fr_I', (FrMean_NL-FrMean_L)./FrMean_L,  'Inverse mean-rate change (NL-L)/L.');
    % Sign-based delta-FR (F2_5_3 "DeltaFR_N"): Delta_Fr where the laser suppressed
    % firing, Delta_Fr_I where it enhanced. Registered so it is filterable/plottable
    % like any other metric (was only an internal var used for the DFRML layer means).
    D = reg(D, dm, hasDM, 'Delta_FR_N', deltaFR_N, 'Sign-based mean-rate change: Delta_Fr where the laser suppressed firing (Delta_Fr<=0), Delta_Fr_I where it enhanced. Nx1.');
    D = reg(D, dm, hasDM, 'Delta_CV',   fitCV_L-fitCV_NL,     'fitCV change (L-NL).');
    D = reg(D, dm, hasDM, 'Delta_OSI',  fitOSI_L-fitOSI_NL,   'fitOSI change (L-NL).');
    D = reg(D, dm, hasDM, 'Delta_HBW',  fitHBW_L-fitHBW_NL,   'fitHBW change (L-NL).');
    D = reg(D, dm, hasDM, 'DSiL',       DSiL,  'Direction selectivity index, laser (|P1-P2|/(P1+P2) from the two opposite-direction fit peaks; Visualizer_01).');
    D = reg(D, dm, hasDM, 'DSiNL',      DSiNL, 'Direction selectivity index, control.');
    D = reg(D, dm, hasDM, 'Delta_DSi',  DSiL-DSiNL, 'Direction selectivity index change (L-NL).');
    D = reg(D, dm, hasDM, 'Delta_FWHM', fitFWHM_L-fitFWHM_NL, 'fitFWHM change (L-NL).');
    D = reg(D, dm, hasDM, 'Delta_HBW_rel_E', (fitHBW_L-fitHBW_NL)./fitHBW_NL, 'Relative fitHBW change vs control.');
    D = reg(D, dm, hasDM, 'Delta_HBW_rel_I', -(fitHBW_L-fitHBW_NL)./fitHBW_L, 'Relative fitHBW change vs laser.');

    % --- precomputed file columns (kept kind "source" = loaded) + Simp_Comp ---
    if hasDM
        try
            fc = dm.convert({'F1F0_L','F1F0_NL','Rsq_L','Rsq_NL'});  % cached raw
            D = reg(D, dm, hasDM, 'F1F0_L',  fc.F1F0_L,  '');   % '' keeps the
            D = reg(D, dm, hasDM, 'F1F0_NL', fc.F1F0_NL, '');   % mapping's source
            D = reg(D, dm, hasDM, 'Rsq_L',   fc.Rsq_L,   '');   % description + kind
            D = reg(D, dm, hasDM, 'Rsq_NL',  fc.Rsq_NL,  '');
            D = reg(D, dm, hasDM, 'Simp_Comp', double(D.F1F0_NL > 1), ...
                'Simple(1)/complex(0) cell from control F1/F0 > 1.');
        catch err
            warning('computeMetrics:precomputed', 'Could not pull F1F0/Rsq: %s', err.message);
        end
    end

    % --- control-aligned tuning curves (Visualizer_01 shift) -------------
    %  360 x N: control peak shifted to 180 deg, laser shifted by the same
    %  amount and then re-centered on its peak within +/-45 deg of center.
    D = reg(D, dm, hasDM, 'fit_mid_L',      fit_mid_L,      'Shifted tuning, laser (control-aligned). 360xN.');
    D = reg(D, dm, hasDM, 'fit_mid_NL',     fit_mid_NL,     'Shifted tuning, control (peak at 180 deg). 360xN.');
    D = reg(D, dm, hasDM, 'Delta_tun',      Delta_tun,      'Shifted delta-tuning. E (EI~="I"): fit_mid_L - fit_mid_NL; I (EI=="I"): fit_mid_NL - fit_mid_L. 360xN.');
    D = reg(D, dm, hasDM, 'fit_mid_nc_L',   fit_mid_nc_L,   'Shifted laser tuning / control peak. 360xN.');
    D = reg(D, dm, hasDM, 'fit_mid_nc_NL',  fit_mid_nc_NL,  'Shifted control tuning / control peak. 360xN.');
    D = reg(D, dm, hasDM, 'Delta_tun_nc',   Delta_tun_nc,   'Control-peak-normalized delta-tuning. E: laser_nc - control_nc; I (EI=="I"): control_nc - laser_nc. 360xN.');
    D = reg(D, dm, hasDM, 'fit_mid_self_L', fit_mid_self_L, 'Shifted laser tuning / its own peak. 360xN.');
    D = reg(D, dm, hasDM, 'fit_mid_self_NL',fit_mid_self_NL,'Shifted control tuning / its own peak. 360xN.');
    D = reg(D, dm, hasDM, 'Ratio_tun',      Ratio_tun,      'Shifted tuning ratio. E: fit_mid_L ./ fit_mid_NL; I (EI=="I"): fit_mid_NL ./ fit_mid_L. 360xN.');
    D = reg(D, dm, hasDM, 'Align_bad',      Align_bad,      'Bad-alignment flag: laser peak0 30-150 deg off center, i.e. laser NOT aligned to control (Nx1).');
    D = reg(D, dm, hasDM, 'Align_peak0_dist', Align_peak0_dist, 'Laser peak0 distance from center, deg (Nx1).');
    D = reg(D, dm, hasDM, 'HBW_L_nan',      HBW_L_nan,      'HBW not computable for laser: 1 where fitHBW_L is NaN (Nx1, 0/1).');
    D = reg(D, dm, hasDM, 'HBW_NL_nan',     HBW_NL_nan,     'HBW not computable for control: 1 where fitHBW_NL is NaN (Nx1, 0/1).');
    D = reg(D, dm, hasDM, 'HBW_pair_ok',    HBW_pair_ok,    'Good HBW pair: 1 when both HBW computable AND laser/control aligned (~HBW_L_nan & ~HBW_NL_nan & ~Align_bad) (Nx1, 0/1).');
    D = reg(D, dm, hasDM, 'LTM_fit_L',      LTM_fit_L,      'Linear-threshold model prediction of laser tuning: max(0, LTM_slope*fit_mid_nc_NL + LTM_intercept). Overlays fit_mid_nc_L. 360xN.');
    D = reg(D, dm, hasDM, 'ExpM_fit',       ExpM_fit,       'Exponential model prediction of the TARGET tuning (E: laser, overlays fit_mid_nc_L; I: control, overlays fit_mid_nc_NL). Control-peak-normalized. 360xN.');

    % --- delta-tuning derivatives (Visualizer_01) of Delta_tun_nc ---------
    D = reg(D, dm, hasDM, 'dTun_d1', dTun_d1, '1st circular derivative of Delta_tun_nc. 360xN.');
    D = reg(D, dm, hasDM, 'dTun_d2', dTun_d2, '2nd circular derivative of Delta_tun_nc. 360xN.');
    D = reg(D, dm, hasDM, 'dTun_d3', dTun_d3, '3rd circular derivative of Delta_tun_nc. 360xN.');
    D = reg(D, dm, hasDM, 'dTun_d4', dTun_d4, '4th circular derivative of Delta_tun_nc. 360xN.');
    D = reg(D, dm, hasDM, 'dTun_nExtrema',  dTun_nExtrema,  'Delta-tuning local extrema count (Visualizer Lo_N) (Nx1).');
    D = reg(D, dm, hasDM, 'dTun_d2_center', dTun_d2_center, 'Delta-tuning 2nd derivative at center (curvature) (Nx1).');
    D = reg(D, dm, hasDM, 'dTun_d4_center', dTun_d4_center, 'Delta-tuning 4th derivative at center (Nx1).');

    % --- linear-threshold model fit (laser = max(0, slope*control + intercept);
    %     orthogonal/TLS on the control-peak-normalized aligned curves) -------
    D = reg(D, dm, hasDM, 'LTM_slope',        LTM_slope,        'Linear-threshold model slope = F2_5_3 Ma (E: piecewise ramp slope; I: line slope; scale-invariant) (Nx1).');
    D = reg(D, dm, hasDM, 'LTM_intercept',    LTM_intercept,    'Linear-threshold model intercept = F2_5_3 Mb (E: floor-bp*slope; I: line intercept; 100x/percent units) (Nx1).');
    D = reg(D, dm, hasDM, 'LTM_floor',        LTM_floor,        'Linear-threshold model free floor, excitatory piecewise fit (100x units; NaN for I) (Nx1).');
    D = reg(D, dm, hasDM, 'LTM_breakpoint',   LTM_breakpoint,   'Linear-threshold model breakpoint, excitatory piecewise fit (100x control units; NaN for I) (Nx1).');
    D = reg(D, dm, hasDM, 'LTM_slope_rev',    LTM_slope_rev,    'Linear-threshold model reversed-fit slope = F2_5_3 Mar (control vs laser; inhibitory only; NaN for E) (Nx1).');
    D = reg(D, dm, hasDM, 'LTM_intercept_rev',LTM_intercept_rev,'Linear-threshold model reversed-fit intercept = F2_5_3 Mbr (inhibitory only; NaN for E) (Nx1).');
    D = reg(D, dm, hasDM, 'LTM_R2',           LTM_R2,           'Linear-threshold model goodness of fit R^2 (predicted vs laser, full curve; <0 = worse than mean) (Nx1).');
    D = reg(D, dm, hasDM, 'LTM_R2adj',        LTM_R2adj,        'Linear-threshold model adjusted R^2 (p=3 for E piecewise, 2 for I linear) (Nx1).');
    D = reg(D, dm, hasDM, 'LTM_RMSE',         LTM_RMSE,         'Linear-threshold model RMSE (predicted vs laser, control-peak units) (Nx1).');
    D = reg(D, dm, hasDM, 'LTM_SSE',          LTM_SSE,          'Linear-threshold model residual sum of squares (full curve) (Nx1).');
    D = reg(D, dm, hasDM, 'LTM_n',            LTM_n,            'Linear-threshold model: number of finite samples used in the fit (Nx1).');

    % --- exponential model fit (target/max(start) = exp(exponent*x - offset);
    %     Sin5_3 input transform; start->target by E/I convention) -----------
    D = reg(D, dm, hasDM, 'ExpM_exponent', ExpM_exponent, 'Exponential model exponent (x coefficient; ~power-law exponent start->target). Headline E-vs-I parameter (Nx1).');
    D = reg(D, dm, hasDM, 'ExpM_offset',   ExpM_offset,   'Exponential model offset (subtracted in the exponent) (Nx1).');
    D = reg(D, dm, hasDM, 'ExpM_scale',    ExpM_scale,    'Exponential model scale = exp(-offset): predicted target at the start peak (Nx1).');
    D = reg(D, dm, hasDM, 'ExpM_theta',    ExpM_theta,    'Exponential model theta = offset/exponent (= old F2_5_3 expp1 = b2/b3); Inf where exponent is 0 (Nx1).');
    D = reg(D, dm, hasDM, 'ExpM_R2',       ExpM_R2,       'Exponential model goodness of fit R^2 (predicted vs actual target, full curve; <0 = worse than mean) (Nx1).');
    D = reg(D, dm, hasDM, 'ExpM_R2adj',    ExpM_R2adj,    'Exponential model adjusted R^2 (p=2 params) (Nx1).');
    D = reg(D, dm, hasDM, 'ExpM_RMSE',     ExpM_RMSE,     'Exponential model RMSE (predicted vs actual target, ctrl-peak-normalized units) (Nx1).');
    D = reg(D, dm, hasDM, 'ExpM_SSE',      ExpM_SSE,      'Exponential model residual sum of squares (full curve) (Nx1).');
    D = reg(D, dm, hasDM, 'ExpM_n',        ExpM_n,        'Exponential model: number of finite samples used in the fit (Nx1).');
    D = reg(D, dm, hasDM, 'ExpM_dFR',      ExpM_dFR,      'Convention-aware firing-rate change used by the exponential model: Delta_Fr for E, Delta_Fr_I for I. Plot ExpM params vs this (Nx1).');

    % --- HBW / OSI / CV on the model curves (control, laser, delta = L-NL) ---
    %  LTM control = actual control, laser = predicted. ExpM laser/control =
    %  predicted target for E/I respectively (the other side is the actual input).
    D = reg(D, dm, hasDM, 'LTM_HBW_NL',  LTM_HBW_NL,  'Half-bandwidth deg, LTM control curve (fit_mid_nc_NL) (Nx1).');
    D = reg(D, dm, hasDM, 'LTM_HBW_L',   LTM_HBW_L,   'Half-bandwidth deg, LTM-predicted laser curve (Nx1).');
    D = reg(D, dm, hasDM, 'LTM_Delta_HBW', LTM_HBW_L-LTM_HBW_NL, 'LTM HBW change (L-NL) (Nx1).');
    D = reg(D, dm, hasDM, 'LTM_OSI_NL',  LTM_OSI_NL,  'OSI, LTM control curve (Nx1).');
    D = reg(D, dm, hasDM, 'LTM_OSI_L',   LTM_OSI_L,   'OSI, LTM-predicted laser curve (Nx1).');
    D = reg(D, dm, hasDM, 'LTM_Delta_OSI', LTM_OSI_L-LTM_OSI_NL, 'LTM OSI change (L-NL) (Nx1).');
    D = reg(D, dm, hasDM, 'LTM_CV_NL',   LTM_CV_NL,   'Circular variance (CV), LTM control curve (Nx1).');
    D = reg(D, dm, hasDM, 'LTM_CV_L',    LTM_CV_L,    'Circular variance (CV), LTM-predicted laser curve (Nx1).');
    D = reg(D, dm, hasDM, 'LTM_Delta_CV', LTM_CV_L-LTM_CV_NL, 'LTM CV change (L-NL) (Nx1).');
    D = reg(D, dm, hasDM, 'ExpM_HBW_NL', ExpM_HBW_NL, 'Half-bandwidth deg, Exp model control curve (E: actual control; I: predicted control) (Nx1).');
    D = reg(D, dm, hasDM, 'ExpM_HBW_L',  ExpM_HBW_L,  'Half-bandwidth deg, Exp model laser curve (E: predicted laser; I: actual laser) (Nx1).');
    D = reg(D, dm, hasDM, 'ExpM_Delta_HBW', ExpM_HBW_L-ExpM_HBW_NL, 'Exp model HBW change (L-NL) (Nx1).');
    D = reg(D, dm, hasDM, 'ExpM_OSI_NL', ExpM_OSI_NL, 'OSI, Exp model control curve (Nx1).');
    D = reg(D, dm, hasDM, 'ExpM_OSI_L',  ExpM_OSI_L,  'OSI, Exp model laser curve (Nx1).');
    D = reg(D, dm, hasDM, 'ExpM_Delta_OSI', ExpM_OSI_L-ExpM_OSI_NL, 'Exp model OSI change (L-NL) (Nx1).');
    D = reg(D, dm, hasDM, 'ExpM_CV_NL',  ExpM_CV_NL,  'Circular variance (CV), Exp model control curve (Nx1).');
    D = reg(D, dm, hasDM, 'ExpM_CV_L',   ExpM_CV_L,   'Circular variance (CV), Exp model laser curve (Nx1).');
    D = reg(D, dm, hasDM, 'ExpM_Delta_CV', ExpM_CV_L-ExpM_CV_NL, 'Exp model CV change (L-NL) (Nx1).');

    % === ADD MORE METRICS HERE ===========================================
    %  D = reg(D, dm, hasDM, 'MyMetric', value, 'what it is');   % (Nx1)
    % =====================================================================
end

% ----------------------------------------------------------------------- %
function D = reg(D, dm, hasDM, name, value, desc)
%REG  Add a calculated field to D, registering it with the DataManager so its
%     provenance shows up in D.Meta. Falls back to a plain field if no dm.
    if ~hasDM
        D.(name) = value;
        return;
    end
    D = dm.attach(D, name, value, desc);   % registers (kind 'computed' if new) + refreshes D.Meta
end

% ----------------------------------------------------------------------- %
function v = safediv(a, b)
%SAFEDIV  a/b, guarded: 0 when b is zero/non-finite or the result is non-finite.
    if isfinite(a) && isfinite(b) && b ~= 0
        v = a / b;
        if ~isfinite(v), v = 0; end
    else
        v = 0;
    end
end

% ----------------------------------------------------------------------- %
function cv = circVar(curve)
%CIRCVAR  Orientation circular variance, matching analysis.tuningMetrics
%   (computeCV with CV_def="orientation"): 1 - |sum(r*exp(2i*theta))|/sum(r),
%   theta = grid degrees (0:N-1). Shift-invariant, so no centering is needed.
    y  = curve(:);
    m  = isfinite(y);
    if nnz(m) < 2, cv = NaN; return; end
    y  = y(m);
    th = (find(m) - 1) * (pi/180);          % grid index 0:N-1 -> degrees -> rad
    cv = 1 - abs(sum(y .* exp(2i*th))) / max(sum(y), eps);
end

% ----------------------------------------------------------------------- %
function [o1, o2, v1, v2] = pick2(ori, val)
%PICK2  First two (orientation, value) pairs from a value-sorted extrema list,
%       NaN-padded when fewer than two extrema exist.
    o1 = NaN; o2 = NaN; v1 = NaN; v2 = NaN;
    if numel(ori) >= 1, o1 = ori(1); v1 = val(1); end
    if numel(ori) >= 2, o2 = ori(2); v2 = val(2); end
end

% ----------------------------------------------------------------------- %
function Lm = linearityM(ctrlCurve, laserCurve, centerIdx, dOri)
%LINEARITYM  Visualizer_01 "MMM" linearity index from the peak-centered curves.
%   MDM = nonpref/pref, with pref = curve value at the center peak and nonpref =
%   mean of the two samples dOri deg either side of center (both fit_mid curves
%   are already peak-centered). Lm = MDM_control - MDM_laser. Numerator and
%   denominator are rounded to 3 decimals, exactly as in Visualizer_01.
    Lm = NaN;
    c = ctrlCurve(:)'; l = laserCurve(:)';
    M = numel(c);
    if M < 2 || centerIdx < 1 || centerIdx > M || numel(l) ~= M, return; end
    ip = mod(centerIdx-1 + dOri, M) + 1;          % +dOri deg (circular)
    im = mod(centerIdx-1 - dOri, M) + 1;          % -dOri deg (circular)
    Pc  = round(c(centerIdx), 3);  NPc = round(mean([c(ip) c(im)]), 3);
    Pl  = round(l(centerIdx), 3);  NPl = round(mean([l(ip) l(im)]), 3);
    Lm  = (NPc / Pc) - (NPl / Pl);                % MDM_NL - MDM_L
end

% ----------------------------------------------------------------------- %
function g = classifyG(d2, d4, Lm, Mth)
%CLASSIFYG  G-type shape class from the delta-tuning 2nd/4th derivative at center
%   plus the Linearity_M index (Visualizer_01 lines 683-823, E/I blocks unified
%   onto the task-1 E-pointing convention):
%       Non-linear (2) : d2 < 0  OR  d4 > 0
%       Linear     (1) : d2 > 0 AND d4 < 0  AND  Mth(1) < Lm < Mth(2)
%       Unknown    (3) : d2 > 0 AND d4 < 0  AND  Lm outside the band
%   NaN if the derivatives are non-finite, Lm is NaN, or d2/d4 sit exactly on 0
%   (matches V01: such units fall into no group).

    g = NaN;
    if ~isfinite(d2) || ~isfinite(d4), return; end
    lo = min(Mth); hi = max(Mth);
    if (d2 < 0) || (d4 > 0)
        g = 2;                                    % Non-linear
    elseif (d2 > 0) && (d4 < 0)
        if isnan(Lm)
            g = NaN;                              % undefined linearity -> unclassified
        elseif Lm > lo && Lm < hi
            g = 1;                                % Linear
        else
            g = 3;                                % Unknown (incl. +/-Inf, as in V01)
        end
    end

    % g = NaN;
    % if ~isfinite(d2) || ~isfinite(d4), return; end
    % lo = min(Mth); hi = max(Mth);
    % 
    % if isnan(Lm)
    %         g = NaN;                              % undefined linearity -> unclassified
    %     elseif Lm > lo && Lm < hi
    %         g = 1;                                % Linear
    %     elseif         (d2 < 0) || (d4 > 0)
    %         g = 2;                                    % Non-linear
    %     else
    %         g = 3;                                % Unknown (incl. +/-Inf, as in V01)
    % end




    
end

% ----------------------------------------------------------------------- %
function d = dirSelectivity(tun)
%DIRSELECTIVITY  Direction selectivity index from a raw fitted tuning curve.
%   Faithful port of Visualizer_01.m (lines 936-978): take the local maxima of
%   the curve; DSi = |P1 - P2| / (P1 + P2) using the first two. If only one
%   maximum, the second point is a local minimum (or the value 180 deg opposite).
    d = NaN; tun = tun(:);
    if isempty(tun) || ~any(isfinite(tun)), return; end
    n = numel(tun);
    idxMax = find(diff(diff(tun) > 0) == -1);     % local maxima (peaks)
    P12 = tun(idxMax);
    if isempty(P12)
        tun = circshift(tun, 90);
        P12 = tun(find(diff(diff(tun) > 0) == -1)); %#ok<FNDSB>
    end
    if numel(P12) == 1
        pn = min(tun(find(diff(diff(tun) > 0) == 1))); %#ok<FNDSB>  % a local min
        if isempty(pn) && ~isempty(idxMax)
            pn = tun(mod(idxMax(1) + 180 - 1, n) + 1);  % 180 deg opposite
        end
        if ~isempty(pn), P12(2) = pn(1); end
    end
    if numel(P12) >= 2 && (P12(1) + P12(2)) ~= 0
        d = abs(P12(1) - P12(2)) / (P12(1) + P12(2));
    end
end

% ----------------------------------------------------------------------- %
function c = rates(R, sW, bW, oriN)
%RATES  [FrMean FrBase FrMax FrMin] from one raster over the given windows.
%   FrMean/FrBase pool all trials; FrMax/FrMin are the max/min of the per-
%   orientation MEASURED tuning (blocked trials), or NaN if oriN is unavailable.
    c = [NaN NaN NaN NaN];
    if isempty(R), return; end
    R = double(R);
    T = size(R,2);
    sW = [max(1,sW(1)), min(T,sW(2))];
    bW = [max(1,bW(1)), min(T,bW(2))];
    tS = (sW(2)-sW(1)+1)/1000;
    tB = (bW(2)-bW(1)+1)/1000;
    stimCounts = sum(R(:, sW(1):sW(2)), 2);
    c(1) = mean(stimCounts) / max(tS, eps);
    c(2) = mean(sum(R(:, bW(1):bW(2)), 2)) / max(tB, eps);
    if nargin >= 4 && isfinite(oriN) && oriN >= 1
        nTr = size(R,1); tr = floor(nTr / oriN);
        if tr >= 1 && tr*oriN <= nTr
            Tun  = mean(reshape(stimCounts(1:tr*oriN), tr, oriN), 1) / max(tS, eps);
            c(3) = max(Tun); c(4) = min(Tun);
        end
    end
end
