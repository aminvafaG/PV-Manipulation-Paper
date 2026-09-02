function reg = defineDatasets()
%DEFINEDATASETS  Registry of selectable datasets (single source of truth).
%
%   reg = data.defineDatasets()
%
%   Each element describes ONE dataset you can load. main.m / loadData pick one
%   by its KEY; data.makeDataManager turns the chosen entry into a DataManager.
%   This is the ONE place to edit when adding a dataset (see "ADD A DATASET").
%
%   Fields (per entry)
%     key      char   short id used in main.m / loadData('Dataset',key). Unique.
%     label    char   human-readable name (shown in messages).
%     mapping  fn     data-dictionary function handle. It is called as
%                     mapping(fileName) -- so the mapping MUST accept an optional
%                     file-name argument (see data.defineUnitsMapping).
%     file     char   default .mat file NAME for this dataset (the mapping
%                     resolves it inside its own data folder under +data).
%
%   The FIRST entry is the project default (used when main.m / loadData get an
%   empty dataset key).
%
%   THE SHIPPED DATASET
%     'example' -> data/Units_example.mat, a SAMPLE of the recordings analysed in
%     the paper (621 units from 35 recordings, both manipulation directions and
%     all three layer groups). It is there so the app can be run and reviewed
%     end to end; the complete dataset is available from the authors on request.
%
%   ADD YOUR OWN DATASET (e.g. data/MyData.mat)
%     1) Drop the .mat file into the repository's data/ folder.
%     2) If it uses the same 'Unit' structure, nothing else is needed -- just
%        pass its name:  loadData([], 'SourceFile', 'MyData.mat').
%     3) If the structure differs, copy +data/defineUnitsMapping.m to
%        +data/defineMyMapping.m and edit:
%          - spec.sourceVar (the variable name INSIDE the .mat),
%          - the v(...) rows that translate your struct's fields to project names.
%        Keep its optional FILE argument so a file override still works.
%     4) Add one row below: key / label / @data.defineMyMapping / default file.
%     5) In main.m set  dataset = 'mykey';   -- nothing else to change.
%
%   See also: data.makeDataManager, data.defineUnitsMapping, loadData

    reg = struct( ...
        'key',     {'example'}, ...
        'label',   {'PV paper sample (data/Units_example.mat)'}, ...
        'mapping', {@data.defineUnitsMapping}, ...
        'file',    {'Units_example.mat'} ...
    );
end
