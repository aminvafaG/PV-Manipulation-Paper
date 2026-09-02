function [dm, entry] = makeDataManager(dataset, sourceFile)
%MAKEDATAMANAGER  Build a DataManager for a registered dataset.
%
%   dm          = data.makeDataManager()              project-default dataset
%   dm          = data.makeDataManager(dataset)       by key (see registry)
%   dm          = data.makeDataManager(dataset, file) + a file-name override
%   [dm, entry] = data.makeDataManager(...)           also return the registry
%                                                      entry that was used
%
%   DATASET   key from data.defineDatasets ('pixel','paper',...). []/'' picks the
%             FIRST registered dataset (the project default).
%   FILE      optional .mat file NAME inside that dataset's data folder; []/''
%             uses the dataset's default file. Lets you swap between same-format
%             files (e.g. data/Units_example.mat vs data/MyUnits.mat)
%             without editing the mapping.
%
%   This is the single bridge from a dataset KEY to a live DataManager, shared by
%   loadData and tunefit.FitCorrectorApp, so "which dataset/file" is decided in exactly
%   one way everywhere. To add a dataset, edit data.defineDatasets (not here).
%
%   See also: data.defineDatasets, data.DataManager, loadData

    reg = data.defineDatasets();

    if nargin < 1 || isempty(dataset)
        entry = reg(1);                                   % project default
    else
        idx = find(strcmpi({reg.key}, char(dataset)), 1);
        if isempty(idx)
            error('data:makeDataManager:unknownDataset', ...
                'Unknown dataset "%s". Registered keys: %s.', ...
                char(dataset), strjoin({reg.key}, ', '));
        end
        entry = reg(idx);
    end

    if nargin < 2 || isempty(sourceFile)
        fileName = entry.file;                            % dataset's default file
    else
        fileName = char(sourceFile);
    end

    % Bake the chosen file into a zero-arg closure DataManager can call.
    dm = data.DataManager(@() entry.mapping(fileName));
end
