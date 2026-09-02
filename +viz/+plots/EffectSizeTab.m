classdef EffectSizeTab < viz.PlotTab
%EFFECTSIZETAB  Compact effect-size summary by cortical layer and manipulation.
%
%   Rows = layer (SG / G / IG [/ Deep]) x manipulation (PVA excitation / PVI
%   inhibition), with a pooled "All" row per manipulation. Columns:
%     dFr (%)             : median [IQR] % firing-rate change (ratio; robust to
%                           near-zero-control outliers);
%     dHBW (deg) dOSI dCV : mean +/- s.e.m of the laser-minus-control change;
%     Units    : number of recorded units (unit x laser-intensity observations);
%     Neurons  : number of distinct cells (U_unity);
%     Penetr.  : number of distinct penetrations (unique Dataset x Penetration);
%     Animals  : number of distinct animals (unique Dataset / DS).
%
%   The report is the page (no separate plot window). Use the controls to pick the
%   unit group (TuningG) and the number of layers. Like the rest of the app,
%   PVA = EI 'E' (excitation), PVI = EI 'I' (inhibition); layers SG/G/IG = LG 1/2/3.
%   dFr = 100*Delta_Fr; HBW drops not-aligned (Align_bad) units.
%
%   See also: viz.plots.StatsReport, analysis.tuningGroupMask

    properties
        groupDD; layersDD
        LastD = []; LastMask = []
    end
    properties (Constant)
        GROUPS = {'ALL_UNITS','NO_ORI_ON_PV','NO_ORI_NO_PV','ORI_ON_PV','ORI_NON_PV','ORI_NON_PV_MD','ORI_NON_PV_NL','ORI_NON_PV_U','OUTLIER'};
        LAY_LAB = {'SG','G','IG','Deep'};
        MANIP   = {'PVA (excitation)', false; 'PVI (inhibition)', true};
    end

    methods
        function obj = EffectSizeTab()
            obj@viz.PlotTab('Effect sizes');
        end

        function buildControls(obj, parent)
            g = uigridlayout(parent, [6 1]);
            g.RowHeight = repmat({'fit'}, 1, 6); g.RowHeight{end} = '1x';
            g.RowSpacing = 4; g.Padding = [8 8 8 8];
            uilabel(g, 'Text', 'Unit group (TuningG)');
            obj.groupDD = uidropdown(g, 'Items', obj.GROUPS, 'Value', 'ALL_UNITS', ...
                'ValueChangedFcn', @(s,e) obj.requestRefresh());
            uilabel(g, 'Text', 'Layers');
            obj.layersDD = uidropdown(g, 'Items', {'3 (SG/G/IG)','4 (+Deep)'}, ...
                'ItemsData', [3 4], 'Value', 3, 'ValueChangedFcn', @(s,e) obj.requestRefresh());
            uilabel(g, 'Text', '');
            uilabel(g, 'Text', sprintf(['Compact effect-size table: laser-minus-control change in firing ' ...
                'rate / HBW / OSI / CV (mean +/- s.e.m) for each layer and manipulation, with unit, ' ...
                'neuron, penetration and animal counts.']), ...
                'WordWrap', 'on', 'FontSize', 11, 'VerticalAlignment', 'top');
            obj.addDataSelectors(g);
        end

        function buildView(obj, parent)
            g = uigridlayout(parent, [1 1]); g.Padding = [0 0 0 0];
            obj.Report = viz.plots.StatsReport(g);
            obj.Report.Panel.Layout.Row = 1; obj.Report.Panel.Layout.Column = 1;
            obj.Report.setVisible(true);
        end

        function update(obj, D, mask)
            obj.LastD = D; obj.LastMask = mask;
            if isempty(obj.Report), return; end
            try
                out = obj.effectTable(D, mask(:));
                obj.Report.update(out, sprintf('Effect sizes by layer x manipulation - group %s.  %s', ...
                    obj.groupDD.Value, out.Summary));
                obj.Report.setLegend(['dFr = median % change [IQR] (ratio, heavy-tailed);  ' ...
                    'dHBW/dOSI/dCV = mean +/- s.e.m (laser - control).   ' ...
                    'Units = unit x intensity observations;  Neurons = distinct cells (U_unity);  ' ...
                    'Animals = unique DS;  Penetr. = unique DS x penetration x hemisphere (E/I).  ' ...
                    'Per row counts only units of that opsin (each animal = one hemisphere per opsin); overall totals in the header.']);
            catch err
                obj.Report.update(struct('ColumnName', {{'error'}}, 'Data', {{err.message}}, 'modes', {{}}));
            end
        end

        function s = getControlState(obj)
            s = struct('group', obj.groupDD.Value, 'layers', obj.layersDD.Value);
        end
        function setControlState(obj, s)
            if isfield(s,'group'),  obj.setCtrl(obj.groupDD,  s.group);  end
            if isfield(s,'layers'), obj.setCtrl(obj.layersDD, s.layers); end
        end
    end

    methods (Access = private)
        function out = effectTable(obj, D, mask)
            colv = @viz.plots.V01util.colv;
            grpMask = analysis.tuningGroupMask(D, obj.groupDD.Value); grpMask = grpMask(:);
            isI = viz.plots.V01util.isInhib(D); isI = isI(:);
            LGn = viz.plots.V01util.layerNum(D); LGn = LGn(:);
            sel0 = mask(:) & grpMask;

            dFr = 100 * colv(D,'Delta_Fr');
            dH  = colv(D,'Delta_HBW'); dO = colv(D,'Delta_OSI'); dC = colv(D,'Delta_CV');
            bad = colv(D,'Align_bad') == 1; dH(bad) = NaN;        % drop not-aligned for HBW
            uu  = colv(D,'U_unity');
            haveID = isfield(D,'Dataset') && isfield(D,'Penetration');
            if haveID
                % DS = animal (DS1..DS4); E/I = hemisphere within an animal.
                ds = colv(D,'Dataset'); pp = colv(D,'Penetration');
                penKey  = (ds*100 + pp)*10 + double(isI);   % unique penetration = animal x penetration x hemisphere
                hemiKey = ds*10 + double(isI);              % unique hemisphere   = animal x E/I
            else
                ds = nan(numel(sel0),1); penKey = ds; hemiKey = ds;
            end

            % overall counts for the header (this group, both manipulations)
            gi = find(sel0);
            if haveID
                summ = sprintf('Overall: %d animals, %d hemispheres, %d penetrations, %d neurons / %d units', ...
                    i_nu(ds(gi)), i_nu(hemiKey(gi)), i_nu(penKey(gi)), i_nu(uu(gi)), numel(gi));
            else
                summ = sprintf('%d neurons / %d units (no animal/penetration ids loaded)', i_nu(uu(gi)), numel(gi));
            end

            nL = obj.layersDD.Value;
            R = {};
            for mi = 1:2
                want = obj.MANIP{mi,2}; man = obj.MANIP{mi,1};
                base = sel0 & (isI == want);
                for L = 1:nL
                    idx = find(base & LGn == L);
                    R(end+1,:) = i_row(obj.LAY_LAB{L}, man, idx, dFr,dH,dO,dC,uu,ds,penKey,haveID); %#ok<AGROW>
                end
                R(end+1,:) = i_row('All', man, find(base), dFr,dH,dO,dC,uu,ds,penKey,haveID); %#ok<AGROW>
            end
            ColumnName = {'Layer','Manipulation','dFr (%) med[IQR]','dHBW (deg)','dOSI','dCV', ...
                          'Units','Neurons','Penetr.','Animals'};
            out = struct('ColumnName', {ColumnName}, 'Data', {R}, 'modes', {{}}, 'Summary', summ);
        end
    end
end

% ----------------------------------------------------------------------- %
function r = i_row(lay, man, idx, dFr, dH, dO, dC, uu, ds, penKey, haveID)
    if haveID, nP = i_nu(penKey(idx)); nA = i_nu(ds(idx)); else, nP = '-'; nA = '-'; end
    % dFr is a percent change (ratio) with heavy tails (near-zero control) -> median[IQR];
    % the bounded tuning deltas use mean +/- s.e.m.
    r = {lay, man, i_med(dFr(idx)), i_ms(dH(idx)), i_ms(dO(idx)), i_ms(dC(idx)), ...
         numel(idx), i_nu(uu(idx)), nP, nA};
end

function s = i_ms(v)
    v = v(isfinite(v));
    if isempty(v), s = '-'; return; end
    s = sprintf('%.3g +/- %.3g', mean(v), std(v)/sqrt(numel(v)));   % mean +/- s.e.m
end

function s = i_med(v)
    v = v(isfinite(v));
    if isempty(v), s = '-'; return; end
    q = quantile(v, [.25 .75]);
    s = sprintf('%.3g [%.3g, %.3g]', median(v), q(1), q(2));
end

function n = i_nu(v)
    v = v(isfinite(v)); n = numel(unique(v));
end
