function tf = paperStyle(newVal)
%PAPERSTYLE  Master on/off key for every paper-figure modification.
%
%   viz.paperStyle()        -> current state (logical)
%   viz.paperStyle(true)    -> plots MATCH the published paper figures (default)
%   viz.paperStyle(false)   -> the ORIGINAL appearance (as it was before the
%                              paper-matching edits)
%
%   Every paper-specific drawing tweak (raster onset/offset lines, photostim
%   bars, baseline color, ...) checks this ONE flag, so the whole app flips
%   between "as it was before" and "matches the paper" from a single key. The
%   toolbar "Original style" checkbox toggles it (checked = original); the state
%   is saved with the session (viz.Visualizer get/setState).
%
%   Implemented as a persistent global so the static drawers (viz.plots.UnitPanels)
%   can read it without threading a flag through every call. It is app-wide: if
%   the main and Examples windows are both open they share one setting.
%
%   See also: viz.Visualizer.setOriginalStyle, viz.plots.Dashboard01Tab, viz.Colors

    persistent VAL
    if isempty(VAL), VAL = true; end                 % default: match the paper
    if nargin >= 1 && ~isempty(newVal), VAL = logical(newVal); end
    tf = VAL;
end
