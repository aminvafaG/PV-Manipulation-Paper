classdef DataManager < handle
%DATAMANAGER  Central registry + converter for the project's datasets.
%
%   A DataManager holds a *data dictionary*: for every variable it tracks
%       project name  ->  source field (in the raw .mat struct)  ->  definition
%   plus how that field should be arranged for the project (matrix / cell /
%   3-D stack / string) and, for computed quantities, how to derive them.
%
%   The engine itself is dataset-agnostic. Everything specific to a dataset
%   lives in a small "mapping" function (e.g. data.defineUnitsMapping) that
%   returns the source file, the variable name inside it, and the list of
%   variable definitions. To support a new dataset, write a new mapping file
%   and point a DataManager at it -- no changes to this class.
%
%   QUICK USE
%       dm = data.DataManager;                 % bare default: the Units (paper)
%                                              % mapping. NOTE the project default
%                                              % is the pixel dataset -- prefer
%                                              % data.makeDataManager() to honor
%                                              % main.m's dataset selection.
%       dm.list                                % view the data dictionary
%       D  = dm.convert({'id','ch','Fr','RasL'});
%       %   -> D.id  1332x1, D.Fr 1332x2, D.RasL 1332x1 cell, ...
%
%       dm.info('Fr')                          % definition of one variable
%       D  = dm.convert('all');                % every registered source var
%
%   ADD A DERIVED VARIABLE (computed from already-converted data)
%       dm.addVariable('FrPrefLaser','derived', ...
%           'dependsOn',{'FrPL'}, 'compute',@(D) D.FrPL(:,1), ...
%           'description','Pref-ori firing rate, laser on');
%       D = dm.convert({'FrPL','FrPrefLaser'});
%
%   TRACK A VARIABLE YOU COMPUTED ELSEWHERE
%       D = dm.attach(D, 'myMetric', someVector, 'what it is');
%
%   See also: data.defineUnitsMapping, example_dataManager

    properties
        IncludeMeta (1,1) logical = true   % attach a D.Meta dictionary to outputs
    end

    properties (SetAccess = private)
        DatasetName char = ''     % label for this dataset, e.g. 'Units'
        SourceFile  char = ''     % full path to the .mat file
        SourceVar   char = ''     % variable name inside the .mat file
        Names       cell = {}     % project variable names, in registration order
    end

    properties (Access = private)
        Defs                      % containers.Map: name -> definition struct
        RawCache = []             % cached raw struct array (lazy-loaded)
    end

    methods
        function obj = DataManager(mapping)
            %DATAMANAGER  Construct from a mapping function/spec.
            %   dm = data.DataManager;                       % default: Units
            %   dm = data.DataManager(@data.defineXxxMapping)
            obj.Defs = containers.Map('KeyType','char','ValueType','any');
            if nargin < 1 || isempty(mapping)
                mapping = @data.defineUnitsMapping;
            end
            obj.loadMapping(mapping);
        end

        function loadMapping(obj, mapping)
            %LOADMAPPING  Populate the registry from a mapping function/spec.
            if isa(mapping, 'function_handle')
                spec = mapping();
            else
                spec = mapping;
            end
            obj.DatasetName = char(spec.dataset);
            obj.SourceFile  = char(spec.file);
            obj.SourceVar   = char(spec.sourceVar);
            for k = 1:numel(spec.vars)
                obj.register(spec.vars(k));
            end
        end

        % ----------------------------------------------------------------- %
        %  Registry management
        % ----------------------------------------------------------------- %
        function addVariable(obj, name, kind, varargin)
            %ADDVARIABLE  Register (or overwrite) a variable definition.
            %   addVariable(name,'source','source','Fr','description',...)
            %   addVariable(name,'derived','dependsOn',{..},'compute',@f,...)
            %   addVariable(name,'computed','description',...)   % external value
            %
            %   Name/value options: source, description, units,
            %                       transform, collect, dependsOn, compute
            d      = obj.defaultDef();
            d.name = char(name);
            d.kind = char(kind);

            p = inputParser;
            p.FunctionName = 'DataManager.addVariable';
            p.addParameter('source',      d.source);
            p.addParameter('description', d.description);
            p.addParameter('units',       d.units);
            p.addParameter('transform',   d.transform);
            p.addParameter('collect',     d.collect);
            p.addParameter('dependsOn',   d.dependsOn);
            p.addParameter('compute',     d.compute);
            p.parse(varargin{:});
            r = p.Results;

            d.source      = r.source;
            d.description = r.description;
            d.units       = r.units;
            d.transform   = r.transform;
            d.collect     = r.collect;
            d.dependsOn   = r.dependsOn;
            d.compute     = r.compute;

            obj.register(d);
        end

        function removeVariable(obj, name)
            %REMOVEVARIABLE  Delete a variable from the registry.
            name = char(name);
            if obj.Defs.isKey(name)
                obj.Defs.remove(name);
                obj.Names(strcmp(obj.Names, name)) = [];
            end
        end

        function tf = has(obj, name)
            %HAS  True if NAME is a registered variable.
            tf = obj.Defs.isKey(char(name));
        end

        % ----------------------------------------------------------------- %
        %  Conversion (the main entry point)
        % ----------------------------------------------------------------- %
        function D = convert(obj, names, src)
            %CONVERT  Build a project struct from the requested variables.
            %   D = convert(names)        names: cellstr | char | string
            %                             special: 'all' | 'source' | 'derived'
            %   D = convert(names, raw)   use a supplied raw struct array
            %                             instead of loading the source file.
            %
            %   Each requested variable becomes one field of D, arranged across
            %   units per its 'collect' rule. Dependencies of derived variables
            %   are pulled in automatically. If IncludeMeta is true, D.Meta is
            %   a table documenting every field that was produced.
            if nargin < 2 || isempty(names)
                names = 'all';
            end
            names = obj.resolveNames(names);
            need  = obj.expandDeps(names);
            order = obj.topoOrder(need);

            if nargin < 3 || isempty(src)
                raw = obj.getRaw();
            else
                raw = src;
            end

            D = struct();
            for i = 1:numel(order)
                nm = order{i};
                d  = obj.Defs(nm);
                switch d.kind
                    case 'source'
                        D.(nm) = obj.collectSource(raw, d);
                    case 'derived'
                        D.(nm) = d.compute(D);
                    case 'computed'
                        error('data:DataManager:computedVar', ...
                            ['"%s" is a computed/external variable; it has no ' ...
                             'source or compute fn. Use dm.attach to add its ' ...
                             'values, do not request it in convert.'], nm);
                end
            end

            if obj.IncludeMeta
                D.Meta = obj.metaFor(order);
            end
        end

        function D = attach(obj, D, name, value, description)
            %ATTACH  Add an externally-computed value to D and track it.
            %   D = attach(D, name, value)
            %   D = attach(D, name, value, description)
            if nargin < 5, description = ''; end
            name = char(name);
            if ~obj.has(name)
                obj.addVariable(name, 'computed', 'description', description);
            elseif ~isempty(description)
                d = obj.Defs(name);
                d.description = description;
                obj.register(d);
            end
            D.(name) = value;
            if isfield(D, 'Meta')
                have = setdiff(fieldnames(D), {'Meta'}, 'stable');
                have = have(cellfun(@(n) obj.has(n), have));
                D.Meta = obj.metaFor(have);
            end
        end

        % ----------------------------------------------------------------- %
        %  Inspection
        % ----------------------------------------------------------------- %
        function T = list(obj, kind)
            %LIST  Return (and, if no output, print) the data dictionary.
            %   T = dm.list           all variables
            %   T = dm.list('source') only source / 'derived' / 'computed'
            if nargin < 2
                order = obj.Names;
            else
                order = obj.filterKind(kind);
            end
            T = obj.dictTable(order);
            if nargout == 0
                fprintf('\n  %s dataset -- %d variables (%s, var "%s")\n\n', ...
                    obj.DatasetName, numel(order), obj.SourceFile, obj.SourceVar);
                disp(T);
                clear T;
            end
        end

        function d = info(obj, name)
            %INFO  Show the full definition of one variable.
            name = char(name);
            if ~obj.has(name)
                error('data:DataManager:unknownVar', ...
                    'Unknown variable "%s". See dm.list.', name);
            end
            d = obj.Defs(name);
            if nargout == 0
                fprintf('\n  project     : %s\n', d.name);
                fprintf(  '  kind        : %s\n', d.kind);
                if ~isempty(d.source),   fprintf('  source field: %s\n', d.source); end
                if ~isempty(d.units),    fprintf('  units       : %s\n', d.units); end
                fprintf(  '  collect     : %s\n', d.collect);
                if ~isempty(d.dependsOn),fprintf('  depends on  : %s\n', strjoin(d.dependsOn, ', ')); end
                if ~isempty(d.transform),fprintf('  transform   : %s\n', func2str(d.transform)); end
                if ~isempty(d.compute),  fprintf('  compute     : %s\n', func2str(d.compute)); end
                fprintf(  '  description : %s\n\n', d.description);
                clear d;
            end
        end

        function raw = getRaw(obj)
            %GETRAW  Load (once, cached) and return the raw struct array.
            if isempty(obj.RawCache)
                if exist(obj.SourceFile, 'file') ~= 2
                    error('data:DataManager:noFile', ...
                        'Source file not found: %s', obj.SourceFile);
                end
                S = load(obj.SourceFile, obj.SourceVar);
                obj.RawCache = S.(obj.SourceVar);
            end
            raw = obj.RawCache;
        end

        function clearCache(obj)
            %CLEARCACHE  Drop the cached raw struct (free memory / force reload).
            obj.RawCache = [];
        end
    end

    % ===================================================================== %
    %  Internals
    % ===================================================================== %
    methods (Access = private)
        function d = defaultDef(~)
            % Canonical definition struct (field order + defaults).
            d.name        = '';
            d.kind        = 'source';     % 'source' | 'derived' | 'computed'
            d.source      = '';           % raw field name (source vars)
            d.description = '';
            d.units       = '';
            d.collect     = 'auto';       % auto|rows|cell|stack|string
            d.transform   = [];           % @(perUnitValue) ...  (source vars)
            d.dependsOn   = {};           % cellstr           (derived vars)
            d.compute     = [];           % @(D) ...          (derived vars)
        end

        function register(obj, d)
            d = obj.normalizeDef(d);
            if ~obj.Defs.isKey(d.name)
                obj.Names{end+1} = d.name;
            end
            obj.Defs(d.name) = d;
        end

        function d = normalizeDef(obj, d)
            % Coerce an incoming def to the canonical shape and validate it.
            def = obj.defaultDef();
            nd  = def;
            fn  = fieldnames(def);
            for i = 1:numel(fn)
                if isfield(d, fn{i})
                    nd.(fn{i}) = d.(fn{i});
                end
            end
            d = nd;

            if isempty(d.name)
                error('data:DataManager:noName', 'A variable needs a name.');
            end
            d.name = char(d.name);
            d.kind = lower(char(d.kind));
            if ~ismember(d.kind, {'source','derived','computed'})
                error('data:DataManager:badKind', ...
                    'kind must be source|derived|computed (got "%s").', d.kind);
            end
            if ischar(d.dependsOn) || isstring(d.dependsOn)
                d.dependsOn = cellstr(d.dependsOn);
            end
            switch d.kind
                case 'source'
                    if isempty(d.source), d.source = d.name; end
                case 'derived'
                    if isempty(d.compute)
                        error('data:DataManager:noCompute', ...
                            'Derived variable "%s" needs a compute function.', d.name);
                    end
            end
        end

        function out = collectSource(obj, raw, d)
            % Pull d.source from every unit, transform, and arrange.
            if ~isfield(raw, d.source)
                error('data:DataManager:noField', ...
                    'Source field "%s" (for "%s") not found in the raw struct.', ...
                    d.source, d.name);
            end
            vals = {raw.(d.source)};               % 1xN cell, one per unit
            if ~isempty(d.transform)
                vals = cellfun(d.transform, vals, 'UniformOutput', false);
            end
            out = obj.collectField(vals, d.collect);
        end

        function out = collectField(obj, vals, mode)
            % Arrange a 1xN cell of per-unit values into a project array.
            vals = reshape(vals, 1, []);
            N    = numel(vals);
            if strcmpi(mode, 'auto')
                mode = obj.autoMode(vals);
            end
            switch lower(mode)
                case 'rows'        % scalars -> Nx1; equal 1xk rows -> Nxk
                    out = cell2mat(reshape(vals, N, 1));
                case 'cell'        % one cell per unit (variable-size data)
                    out = reshape(vals, N, 1);
                case 'stack'       % equal-size arrays -> cat on a new last dim
                    if N == 0, out = []; return; end
                    out    = cat(ndims(vals{1}) + 1, vals{:});
                    elemSz = size(vals{1});
                    elemSz = elemSz(elemSz ~= 1);   % drop singleton element dims
                    if isempty(elemSz), elemSz = 1; end
                    out    = reshape(out, [elemSz, N]);  % e.g. 360x1xN -> 360xN
                case 'string'      % char/string per unit -> Nx1 string (trimmed)
                    out = strings(N, 1);
                    for i = 1:N
                        out(i) = strtrim(string(vals{i}));
                    end
                otherwise
                    error('data:DataManager:badCollect', ...
                        'Unknown collect mode "%s".', mode);
            end
        end

        function mode = autoMode(~, vals)
            % Choose an arrangement automatically from the data shapes.
            if isempty(vals), mode = 'cell'; return; end
            if all(cellfun(@(v) ischar(v) || isstring(v), vals))
                mode = 'string'; return;
            end
            if ~all(cellfun(@(v) isnumeric(v) || islogical(v), vals))
                mode = 'cell'; return;
            end
            if all(cellfun(@isscalar, vals))
                mode = 'rows'; return;          % -> column vector
            end
            if all(cellfun(@isrow, vals))
                k = cellfun(@numel, vals);
                if all(k == k(1)), mode = 'rows'; return; end   % -> Nxk matrix
            end
            mode = 'cell';                      % matrices / ragged -> cell
        end

        function names = resolveNames(obj, names)
            % Normalize a request to a cellstr of project names.
            if isstring(names)
                if isscalar(names), names = char(names); else, names = cellstr(names); end
            end
            if ischar(names)
                switch lower(names)
                    case 'all',     names = obj.Names;
                    case 'source',  names = obj.filterKind('source');
                    case 'derived', names = obj.filterKind('derived');
                    case 'computed',names = obj.filterKind('computed');
                    otherwise,      names = {names};
                end
            elseif iscell(names)
                names = cellfun(@char, names(:)', 'UniformOutput', false);
            else
                error('data:DataManager:badNames', ...
                    'names must be char, string, or cellstr.');
            end
        end

        function need = expandDeps(obj, names)
            % Transitive closure over derived-variable dependencies.
            need  = {};
            stack = names;
            while ~isempty(stack)
                nm = stack{end};
                stack(end) = [];
                if any(strcmp(need, nm)), continue; end
                if ~obj.has(nm)
                    error('data:DataManager:unknownVar', ...
                        'Unknown variable "%s". See dm.list.', nm);
                end
                need{end+1} = nm; %#ok<AGROW>
                d = obj.Defs(nm);
                if strcmp(d.kind, 'derived') && ~isempty(d.dependsOn)
                    stack = [stack, d.dependsOn]; %#ok<AGROW>
                end
            end
        end

        function order = topoOrder(obj, need)
            % Order so every variable comes after the deps it needs.
            order   = {};
            pending = need;
            while ~isempty(pending)
                keep       = {};
                progressed = false;
                for i = 1:numel(pending)
                    nm = pending{i};
                    d  = obj.Defs(nm);
                    if strcmp(d.kind, 'derived')
                        deps = d.dependsOn;
                    else
                        deps = {};
                    end
                    if all(ismember(deps, order))
                        order{end+1} = nm; %#ok<AGROW>
                        progressed   = true;
                    else
                        keep{end+1}  = nm; %#ok<AGROW>
                    end
                end
                pending = keep;
                if ~progressed
                    error('data:DataManager:cycle', ...
                        'Cannot resolve dependencies (cycle or missing) for: %s', ...
                        strjoin(pending, ', '));
                end
            end
        end

        function nm = filterKind(obj, kind)
            kind = lower(char(kind));
            nm   = {};
            for i = 1:numel(obj.Names)
                if strcmp(obj.Defs(obj.Names{i}).kind, kind)
                    nm{end+1} = obj.Names{i}; %#ok<AGROW>
                end
            end
        end

        function T = metaFor(obj, order)
            T = obj.dictTable(order(:)');
        end

        function T = dictTable(obj, order)
            n = numel(order);
            [proj, src, kind, coll, unit, desc] = deal(cell(n, 1));
            for i = 1:n
                d = obj.Defs(order{i});
                proj{i} = d.name;        src{i}  = d.source;
                kind{i} = d.kind;        coll{i} = d.collect;
                unit{i} = d.units;       desc{i} = d.description;
            end
            T = table(proj, src, kind, coll, unit, desc, ...
                'VariableNames', {'project','source','kind','collect','units','description'});
        end
    end
end
