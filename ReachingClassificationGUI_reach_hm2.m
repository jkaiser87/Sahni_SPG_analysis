function ReachingClassificationGUI_reach()

% Create main UI
handles = struct();
handles.baseDir = pwd;

handles.colors.errorRed = [0.8 0.2 0.2];      % For error messages
handles.colors.statusPending = [0.62 0.64 0.70];
handles.colors.successColor = [0.35 0.75 0.45];  % success green #59BF73

outDir = fullfile(handles.baseDir,'OUT');
if ~exist(outDir) mkdir(outDir); end

fig = uifigure('Name', 'Single Pellet Reaching Processing', ...
    'Position', [100, 100, 1000, 600]);

% Define simple grid layout
gl = uigridlayout(fig, [4,5]);
gl.RowHeight = {30, '1x',50, 50, 100};
gl.ColumnWidth = {'1x', '1x', '1x', '1x'};

% --- Row 1: Folder Selection + Animal Dropdown + Alignment Button ---
headerLabel = uilabel(gl, 'Text', 'Single Pellet Reaching Assessment', ...
    'FontSize', 18, ...
    'FontWeight', 'bold', ...
    'HorizontalAlignment', 'left');

headerLabel.Layout.Row = 1;
headerLabel.Layout.Column = [1 5];

[~,lblFolder] = fileparts(handles.baseDir); % stores foldername

% Add table to show video pair status
tblStatus = uitable(gl, ...
    'Data', {}, ...
    'FontSize', 12, ...
    'ColumnName', { ...
    'coreID', ...
    'SideVideo', ...
    'FrontVideo', ...
    'SideDLC', ...
    'FrontDLC', ...
    'OffsetStart', ...
    'OffsetEnd', ...
    'TotalReaches', ...
    'Exclude'}, ...
    'ColumnFormat', { ...
    'char', ...
    'logical', ...
    'logical', ...
    'logical', ...
    'logical', ...
    'numeric', ...
    'numeric', ...
    'numeric', ...
    'logical'}, ...
    'ColumnEditable', [false false false false false false false false true]);

tblStatus.Layout.Row = 2;
tblStatus.Layout.Column = [1 5];

% New row for likelihood input above buttons
likelihoodLabel = uilabel(gl, ...
    'Text', 'Paw Likelihood Threshold:', ...
    'HorizontalAlignment', 'right', ...
    'FontWeight', 'bold', ...
    'Tooltip', 'Set minimum likelihood threshold for paw detection (0 to 1)', ...
    'FontSize', 12);
likelihoodLabel.Layout.Row = 3;
likelihoodLabel.Layout.Column = 1;

defaultLikelihood = getLatestPawLikelihoodFromLog(handles.baseDir);

likelihoodEdit = uieditfield(gl, 'numeric', ...
    'Limits', [0 1], ...
    'Value', defaultLikelihood, ...        % default value
    'RoundFractionalValues', false, ...
    'Tooltip', 'Enter a value between 0 (low) and 1 (high likelihood)', ...
    'FontSize', 12);
likelihoodEdit.Layout.Row = 3;
likelihoodEdit.Layout.Column = 2;

% Store in handles for access in callbacks
handles.likelihoodEdit = likelihoodEdit;
guidata(fig, handles);


btnAlignVideos = uibutton(gl, 'Text', '🛠 Calculate Offset (front/side)');
btnAlignVideos.Layout.Row = 4;
btnAlignVideos.Layout.Column = 1;

btnCalibratePole = uibutton(gl, 'Text', '🛠 Calculate Pole Width (Calibrate)');
btnCalibratePole.Layout.Row = 4;
btnCalibratePole.Layout.Column = 2;

btnDetectReaches = uibutton(gl, 'Text', '🐾 Detect Reaches');
btnDetectReaches.Layout.Row = 4;
btnDetectReaches.Layout.Column = 3;

btnClassifyReaches = uibutton(gl, 'Text', '🎯 Classify Reaches');
btnClassifyReaches.Layout.Row = 4;
btnClassifyReaches.Layout.Column = 4;

btnAnalyzeReaches = uibutton(gl, 'Text', '📊 Analyze Paw Kinematics');
btnAnalyzeReaches.Layout.Row = 4;
btnAnalyzeReaches.Layout.Column = 5;

msgLayout = uigridlayout(gl, [1, 1]); % One cell grid layout
msgLayout.RowHeight = {'1x'};
msgLayout.ColumnWidth = {'1x'};
msgLayout.Padding = [0 0 0 0];  % No padding
msgLayout.Layout.Row = 5;
msgLayout.Layout.Column = [1 5];

msgLabel = uilabel(msgLayout, ...
    'Text', 'No errors in the setup', ...
    'FontWeight', 'bold', ...
    'FontSize', 13, ...
    'HorizontalAlignment', 'center', ...  % Center horizontally
    'VerticalAlignment', 'center', ...  % Center vertically
    'FontColor', '#000000', ...
    'BackgroundColor', '#ffffff', ...
    'WordWrap', 'on');


% --- Store Handles for Later Use ---
handles.fig = fig;
handles.outDir = outDir;
% handles.btnFolder = btnFolder;
handles.btnAlignVideos = btnAlignVideos;
handles.btnCalibratePole = btnCalibratePole;
handles.btnDetectReaches = btnDetectReaches;
handles.btnClassifyReaches = btnClassifyReaches;
handles.btnAnalyzeReaches = btnAnalyzeReaches;
handles.lblFolder = lblFolder;
handles.tblStatus = tblStatus;
handles.msgLabel = msgLabel;

guidata(fig, handles);

% --- Callbacks ---
btnFolder.ButtonPushedFcn = @(src, evt) selectFolderCallback(fig);
% btnConvertVideos.ButtonPushedFcn = @(src, evt) precomputeStacksCallback(fig);
btnAlignVideos.ButtonPushedFcn = @(src, evt) alignVideosCallback(fig);
btnCalibratePole.ButtonPushedFcn = @(src,evt) calibratePoleByClick(fig);
btnDetectReaches.ButtonPushedFcn = @(src, evt) detectReachesCallback(fig);
btnClassifyReaches.ButtonPushedFcn = @(src, evt) classifyReachesCallback(fig);
btnAnalyzeReaches.ButtonPushedFcn = @(src, evt) analyzeReachesCallback(fig);
handles.tblStatus.CellEditCallback = @(src, evt) excludeCellEditCallback(fig, src, evt);

% Immediately try loading current folder
LoadFolder(fig);
end


%% GUI table and interaction functions
function LoadFolder(fig)
handles = guidata(fig);

% Cache directories
baseDir  = handles.baseDir;
outDir   = handles.outDir;
sideDir  = fullfile(baseDir, 'Side');
frontDir = fullfile(baseDir, 'Front');

% Show status
handles.msgLabel.Text = 'Scanning video files...';
handles.msgLabel.FontColor = handles.colors.statusPending;
drawnow;

% Scan for videos
sideFiles  = dir(fullfile(sideDir, '*_Side_*.mp4'));
frontFiles = dir(fullfile(frontDir, '*_Front_*.mp4'));

% Load alignment if it exists
alignmentFile = fullfile(outDir, 'alignment_table.mat');
alignmentData = table();
if exist(alignmentFile, 'file')
    S = load(alignmentFile);
    if isfield(S, 'results')
        alignmentData = S.results;
    elseif isfield(S, 'allResults')
        alignmentData = S.allResults;
    end
    % Normalize CoreID case
    if ~ismember('CoreID', alignmentData.Properties.VariableNames)
        if ismember('coreID', alignmentData.Properties.VariableNames)
            alignmentData.Properties.VariableNames{'coreID'} = 'CoreID';
        end
    end
end

% Find video pairs
filePairs = findVideoPairs(sideFiles, sideDir, frontFiles, frontDir, handles);

% --- Map GUI column names into valid struct field names ---
colNamesGUI = { ...
    'coreID', ...
    'SideVideo', ...
    'FrontVideo', ...
    'SideDLC', ...
    'FrontDLC', ...
    'OffsetStart', ...
    'OffsetEnd', ...
    'TotalReaches', ...
    'Exclude'};

% Preallocate struct array
emptyRow = cell2struct(cell(1,numel(colNamesGUI)), colNamesGUI, 2);
emptyRow.OffsetStart  = NaN;
emptyRow.OffsetEnd    = NaN;
emptyRow.TotalReaches = 0;
emptyRow.Exclude      = false;

pairStruct = repmat(emptyRow, 1, numel(filePairs));

% Fill values
parfor i = 1:numel(filePairs)
    pair   = filePairs(i);
    coreID = pair.coreID;

    row = pairStruct(i); % template row with all fields

    % Fill known columns (must match colNamesGUI)
    row.coreID      = coreID;
    row.SideVideo   = isfile(pair.sideVideo);
    row.FrontVideo  = isfile(pair.frontVideo);
    row.SideDLC     = ~isempty(fastReadDLC(pair.sideVideo, 'Side', 'existsonly'));
    row.FrontDLC    = ~isempty(fastReadDLC(pair.frontVideo, 'Front', 'existsonly'));

    % Alignment lookup from MAT
    if ~isempty(alignmentData) && ismember('CoreID', alignmentData.Properties.VariableNames)
        matchIdx = strcmp(alignmentData.CoreID, coreID);
        if any(matchIdx)
            if ismember('OffsetStart', alignmentData.Properties.VariableNames)
                row.OffsetStart = alignmentData.OffsetStart(matchIdx);
            elseif ismember('Offset', alignmentData.Properties.VariableNames)
                row.OffsetStart = alignmentData.Offset(matchIdx); % fallback
            end
            if ismember('OffsetEnd', alignmentData.Properties.VariableNames)
                row.OffsetEnd = alignmentData.OffsetEnd(matchIdx);
            end
        end
    end

    % Reach stats
    reachFile = fullfile(outDir, sprintf('%s_reaches.mat', coreID));
    if exist(reachFile, 'file')
        R = load(reachFile, 'reaches');
        if isfield(R, 'reaches')
            row.TotalReaches = numel(R.reaches);
        end
    end

    pairStruct(i) = row;
end

% Convert to table
pairSummary = struct2table(pairStruct, 'AsArray', true);

excludeFile = fullfile(outDir, 'exclude_table.mat');
if exist(excludeFile, 'file')
    S = load(excludeFile);
    if isfield(S, 'excludeTable')
        [tf, loc] = ismember(pairSummary.coreID, S.excludeTable.CoreID);
        pairSummary.Exclude(tf) = S.excludeTable.Exclude(loc(tf));
    end
end

% Push into GUI
handles.tblStatus.Data = pairSummary;
handles.msgLabel.Text = 'Pipeline ready for processing';
handles.msgLabel.FontColor = handles.colors.statusPending;
drawnow;
% Store pairs
handles.pairs = filePairs;
guidata(fig, handles);
end

function filePairs = findVideoPairs(sideFiles, sideDir, frontFiles, frontDir, handles)

filePairs = struct('coreID', {}, 'sideVideo', {}, 'frontVideo', {}); % initialize

for i = 1:length(sideFiles)
    sideName = sideFiles(i).name;

    % Extract animal + condition from the side filename
    tokens = regexp(sideName, '(.*)_Side_(.*)\.mp4', 'tokens', 'once');
    if isempty(tokens)
        fprintf('⚠️ Could not parse: %s\n', sideName);
        continue;
    end

    animal = tokens{1};
    condition = tokens{2};
    coreID = sprintf('%s_%s', animal, condition);

    % Rebuild the expected front filename pattern
    frontPattern = sprintf('%s_Front_%s.mp4', animal, condition);
    matchIdx = find(strcmp({frontFiles.name}, frontPattern), 1);

    if isempty(matchIdx)
        fprintf('❌ Skipping %s: No exact match for %s\n', sideName, frontPattern);
        handles.msgLabel.Text = sprintf('❌ Skipping %s: No exact match for %s\n', sideName, frontPattern);
        handles.msgLabel.FontColor = handles.colors.errorRed;
        drawnow;
        continue;
    end

    newPair = struct();
    newPair.coreID = coreID;
    newPair.sideVideo = fullfile(sideDir, sideName);
    newPair.frontVideo = fullfile(frontDir, frontFiles(matchIdx).name);

    filePairs(end+1) = newPair; %#ok<AGROW>
end
end

function logMsg(msg, showInCommand, fid)
try
    if showInCommand
        handles.msgLabel.Text = msg;
        handles.msgLabel.FontColor = handles.colors.statusPending;
        drawnow;
        fprintf('%s\n', msg);
    end
catch
    % If handles doesn't exist, just print to command window
    if showInCommand
        fprintf('%s\n', msg);
    end
end
fprintf(fid, '%s\n', msg);
end

function defaultLikelihood = getLatestPawLikelihoodFromLog(outDir)
% Default fallback value if no file or value found
defaultLikelihood = 0.6;

% Find log files matching pattern
logFiles = dir(fullfile(outDir, 'reach_detection_log_*.txt'));
if isempty(logFiles)
    fprintf('No reach detection log files found, using default likelihood %.2f\n', defaultLikelihood);
    return;
end

% Sort files by date, latest first
[~, idx] = sort([logFiles.datenum], 'descend');
newestLogFile = fullfile(logFiles(idx(1)).folder, logFiles(idx(1)).name);

% Open the newest log file
fid = fopen(newestLogFile, 'r');
if fid == -1
    fprintf('Failed to open log file, using default likelihood %.2f\n', defaultLikelihood);
    return;
end

% Read line by line to find "paw likelihood:"
while ~feof(fid)
    tline = fgetl(fid);
    if contains(tline, 'paw likelihood:', 'IgnoreCase', true)
        tokens = regexp(tline, 'paw likelihood:\s*([0-9.]+)', 'tokens', 'once');
        if ~isempty(tokens)
            val = str2double(tokens{1});
            if ~isnan(val) && val >= 0 && val <= 1
                defaultLikelihood = val;
                fprintf('Loaded paw likelihood threshold %.2f from %s\n', val, newestLogFile);
                fclose(fid);
                return;
            end
        end
    end
end
fclose(fid);

fprintf('paw likelihood line not found, using default value %.2f\n', defaultLikelihood);
end


function excludeCellEditCallback(fig, src, evt)
handles = guidata(fig);

% Get the row and new value
row = evt.Indices(1);
newVal = evt.NewData;

% Update table data in handles
handles.tblStatus.Data.Exclude(row) = newVal;

% Save to file immediately
excludeTable = table(handles.tblStatus.Data.coreID, ...
    handles.tblStatus.Data.Exclude, ...
    'VariableNames', {'CoreID','Exclude'});

outDir = handles.outDir;
save(fullfile(outDir, 'exclude_table.mat'), 'excludeTable');

% Push updated handles back
guidata(fig, handles);

excludeTable = table( ...
    handles.tblStatus.Data.coreID, ...
    handles.tblStatus.Data.Exclude, ...
    'VariableNames', {'CoreID','Exclude'} );

outDir = handles.outDir;
save(fullfile(outDir, 'exclude_table.mat'), 'excludeTable');

% Also save CSV for Fiji
writetable(excludeTable, fullfile(outDir, 'exclude_table.csv'));

% Optional: show status message
handles.msgLabel.Text = sprintf('Updated Exclude for %s', ...
    handles.tblStatus.Data.coreID{row});
end


%% ---- Read DLC data

function dlcData = fastReadDLC(videoPath, viewType, varargin)

% Cache DLC data in memory to avoid repeated file reads
% Optional third parameter: 'existsonly' to just check if file exists

% Parse optional parameter
checkExistsOnly = false;
if nargin > 2 && strcmpi(varargin{1}, 'existsonly')
    checkExistsOnly = true;
end

% If just checking existence, use same logic as readDLCcsv
if checkExistsOnly
    % Extract base path and coreID (filename without extension)
    [videoFolder, videoNameNoExt, ~] = fileparts(videoPath);

    % Construct path to expected subfolder (Front or Side)
    expectedFolder = fullfile(videoFolder, '..', viewType);
    expectedFolder = fullfile(expectedFolder); % resolve any relative paths

    % Look for DLC CSVs in the expected folder
    allCSV = dir(fullfile(expectedFolder, '*.csv'));

    % Match by video core name
    matches = contains({allCSV.name}, videoNameNoExt) & ...
        endsWith({allCSV.name}, '.csv') & ...
        ~contains({allCSV.name}, 'meta');

    dlcData = any(matches); % Return true if any matches found
    return;
end

persistent dlcCache
if isempty(dlcCache)
    dlcCache = containers.Map();
end

[~, fname] = fileparts(videoPath);
cacheKey = [fname '_' viewType];

if dlcCache.isKey(cacheKey)
    dlcData = dlcCache(cacheKey);
    return;
end

% Original DLC reading logic here
dlcData = readDLCcsv(videoPath, viewType);

% Cache the result
dlcCache(cacheKey) = dlcData;
end

function data_table = readDLCcsv(videoFile, expectedView)
% Validate expectedView input
if ~ischar(expectedView) || ~ismember(expectedView, {'Front', 'Side'})
    error('expectedView must be ''Front'' or ''Side''.');
end

% Extract base path and coreID (filename without extension)
[videoFolder, videoNameNoExt, ~] = fileparts(videoFile);

% Construct path to expected subfolder (Front or Side)
expectedFolder = fullfile(videoFolder, '..', expectedView);
expectedFolder = fullfile(expectedFolder); % resolve any relative paths

% Look for DLC CSVs in the expected folder
allCSV = dir(fullfile(expectedFolder, '*.csv'));

% Match by video core name
matches = contains({allCSV.name}, videoNameNoExt) & ...
    endsWith({allCSV.name}, '.csv') & ...
    ~contains({allCSV.name}, 'meta');

if ~any(matches)
    warning('No DLC file found for %s in folder %s', videoNameNoExt, expectedView);
    data_table = [];
    return;
end


% Read the first match
csv_file = fullfile(allCSV(find(matches, 1)).folder, allCSV(find(matches, 1)).name);
%fprintf('Loaded DLC file: %s\n', csv_file);

% --- DLC-specific parsing ---

opts = detectImportOptions(csv_file); %#ok
opts.DataLine = 4;  % DLC data starts at line 4

% Read header lines 2 and 3
header_lines = readcell(csv_file, 'Range', '2:3');
header_names = strcat(header_lines(1,:), '.', header_lines(2,:));
header_names{1} = 'frames';  % Rename first column

opts.VariableNames = header_names;

% Read final table
warnState = warning('off', 'MATLAB:table:ModifiedAndSavedVarnames');
data_table = readtable(csv_file, opts);
warning(warnState);  % restore original warning state

% Normalize column names to lowercase
data_table.Properties.VariableNames = lower(data_table.Properties.VariableNames);
end

%% alignment of videos (FIJI based)

function alignVideosCallback(fig)
handles = guidata(fig);
fijiPath = 'C:\Fiji.app\fiji-win64.exe';
dataDir  = handles.baseDir;

% Double-escape backslashes for the dir argument
dirArg   = sprintf('dir=%s', strrep(dataDir, '\', '\\'));

% Build Fiji system call
cmd = sprintf('"%s" --ij2 --run "SPG_VideoSyncTool " "%s"', fijiPath, dirArg);

system(cmd);

results = loadAlignmentResults(dataDir);

% Match CoreIDs
if istable(handles.tblStatus.Data)
    guiCoreIDs = handles.tblStatus.Data.coreID; % if stored as a table with variable coreID
else
    guiCoreIDs = handles.tblStatus.Data(:,1);   % if it's still a cell array
end

% Force everything to cell array of char
if isstring(guiCoreIDs)
    guiCoreIDs = cellstr(guiCoreIDs);
elseif iscell(guiCoreIDs)
    guiCoreIDs = cellfun(@char, guiCoreIDs, 'UniformOutput', false);
elseif isnumeric(guiCoreIDs)
    guiCoreIDs = cellstr(string(guiCoreIDs));
end

fijiCoreIDs = cellstr(results.CoreID);

[tf, loc] = ismember(guiCoreIDs, fijiCoreIDs);

% Column indices
colStart = find(strcmp(handles.tblStatus.ColumnName, 'OffsetStart'));
colEnd   = find(strcmp(handles.tblStatus.ColumnName, 'OffsetEnd'));

% Update GUI table
for i = 1:numel(guiCoreIDs)
    if tf(i)
        handles.tblStatus.Data{i,colStart} = results.OffsetStart(loc(i));
        handles.tblStatus.Data{i,colEnd}   = results.OffsetEnd(loc(i));
    end
end

guidata(fig, handles);

end

function results = loadAlignmentResults(baseDir)
outDir = fullfile(baseDir, 'OUT');
csvFile = fullfile(outDir, 'alignment_table.csv');

if ~isfile(csvFile)
    warning('⚠️ No alignment_table.csv found in %s', outDir);
    results = table(); % return empty table
    return;
end

results = readtable(csvFile);

% --- Normalize column names ---
if ~ismember('CoreID', results.Properties.VariableNames)
    error('alignment_table.csv missing CoreID column');
end

% Handle old format (single Offset column)
if ismember('Offset', results.Properties.VariableNames)
    results.OffsetStart = results.Offset;
    results.OffsetEnd   = results.Offset;
    results.Offset = []; % drop old col
end

% Handle new format (Offset1/Offset2)
if ismember('Offset1', results.Properties.VariableNames)
    results.Properties.VariableNames{'Offset1'} = 'OffsetStart';
end
if ismember('Offset2', results.Properties.VariableNames)
    results.Properties.VariableNames{'Offset2'} = 'OffsetEnd';
end

% Ensure columns exist even if missing
if ~ismember('OffsetStart', results.Properties.VariableNames)
    results.OffsetStart = NaN(height(results),1);
end
if ~ismember('OffsetEnd', results.Properties.VariableNames)
    results.OffsetEnd = NaN(height(results),1);
end

% Save MAT version for speed
save(fullfile(outDir, 'alignment_table.mat'), 'results');

fprintf('✅ Loaded %d entries from alignment_table.csv\n', height(results));
end

% ----------- Offset calculation on these alignments


function offset = getDynamicOffset(results, coreID, sideFrame)
%GETDYNAMICOFFSET Interpolates offset for a given frame
%   results   = table from alignment_table.csv
%   coreID    = string identifying the trial
%   sideFrame = the frame number in Side video

rowIdx = find(strcmpi(results.CoreID, coreID), 1);
if isempty(rowIdx)
    error('CoreID %s not found in results.', coreID);
end

r = results(rowIdx,:);

% If only one offset exists, return it
if isnan(r.OffsetEnd) || r.OffsetEnd == r.OffsetStart
    offset = r.OffsetStart;
    return;
end

% Linear interpolation between the two anchor points
offset = r.OffsetStart + ...
    (r.OffsetEnd - r.OffsetStart) * ...
    ( (sideFrame - r.SideFrame1) / (r.SideFrame2 - r.SideFrame1) );

offset = round(offset); % return integer frame offset
end


function offset = getRangeOffset(results, coreID, fStart, fEnd)
%GETRANGEOFFSET Average offset across a frame range

ofs1 = getDynamicOffset(results, coreID, fStart);
ofs2 = getDynamicOffset(results, coreID, fEnd);

% Use average offset across the reach
offset = round(mean([ofs1 ofs2]));
end


%% ---- Define Reaching Frames and store

function detectReachesCallback(fig)
rerunFrontOnly = true;   % <--- set to true if you want to recompute only front-mapping

handles = guidata(fig);
baseDir = handles.baseDir;
outDir = handles.outDir;
pairs = handles.pairs;

% Load alignment info
alignmentFile = fullfile(outDir, 'alignment_table.mat');
if ~isfile(alignmentFile)
    uialert(fig, 'No alignment_table.mat found. Please run alignment first.', 'Missing File');
    return;
end
results = load(alignmentFile, 'results').results;

% Setup log
logFile = fullfile(baseDir, sprintf('reach_detection_log_%s.txt', datestr(now, 'yyyymmdd_HHMMSS')));
fid = fopen(logFile, 'w');
cleanupObj = onCleanup(@() fclose(fid));

% --- Reach Detection Parameters ---
params = struct( ...
    'paw_likelihood', handles.likelihoodEdit.Value,... %get user input
    'seq_likelihood', 0.3, ...
    'pellet_likelihood_threshold', 0.4, ...
    'pellet_check_frames', 10, ...
    'min_frames', 10, ...
    'frame_buffer', 15, ...
    'gap_tolerance', 5, ...
    'gauss_smooth', 50 ...
    );
logParams(params, fid);

% Prepare table
tblData = handles.tblStatus.Data;
tblData = ensureReachColumns(tblData);

% --- Loop through animals ---
for pairIdx = 1:numel(pairs)
    coreID = pairs(pairIdx).coreID;

    % Skip if reach output already exists
    reachMatFile = fullfile(outDir, sprintf('%s_reaches.mat', coreID));

    if isfile(reachMatFile) && ~rerunFrontOnly
        logMsg(sprintf('⏩ Skipping %s (reach files already exist)', coreID), true, fid);
        continue;
    end

    %%% NEW: load BOTH DLC tables for alignment model
    sideCSV  = readDLCcsv(pairs(pairIdx).sideVideo,  'Side');
    frontCSV = readDLCcsv(pairs(pairIdx).frontVideo, 'Front');

    rowIdx = find(strcmpi(results.CoreID, coreID), 1);
    if ~isempty(rowIdx)
        OffsetStart = results.OffsetStart(rowIdx);
        OffsetEnd   = results.OffsetEnd(rowIdx);

        SideFrame1  = results.SideFrame1(rowIdx);
        FrontFrame1 = results.FrontFrame1(rowIdx);
        SideFrame2  = results.SideFrame2(rowIdx);
        FrontFrame2 = results.FrontFrame2(rowIdx);

        % initOffset = coarse hint for candidate search
        initOffset  = mean([OffsetStart, OffsetEnd], 'omitnan');
        if isnan(initOffset), initOffset = 0; end

        % If anything is missing, set to NaN
        if isnan(OffsetStart), OffsetStart = []; end
        if isnan(OffsetEnd),   OffsetEnd   = []; end
    else
        OffsetStart = [];
        OffsetEnd   = [];
        SideFrame1  = [];
        FrontFrame1 = [];
        SideFrame2  = [];
        FrontFrame2 = [];
    end

    alignOpts = struct( ...
        'hi', 0.90, ...
        'prom', 0.20, ...
        'minSep', 350, ...
        'minWidth', 12, ...
        'medianFront', 11, ...
        'nnWindow', 1500, ...
        'initOffset', round(initOffset), ...
        'OffsetStart', OffsetStart, ...
        'OffsetEnd',   OffsetEnd, ...
        'SideFrame1',  SideFrame1, ...
        'FrontFrame1', FrontFrame1, ...
        'SideFrame2',  SideFrame2, ...
        'FrontFrame2', FrontFrame2, ...
        'alignMode', 'segmented', ... % 'segmented', 'affine_weighted', 'piecewise', or 'pchip'
        'anchorWeight', 15, ...
        'minPairs', 3);

    alignOpts.fp.MinPeakHeight = 'auto';
    alignOpts.fp.MinPeakProminence = 'auto';


    model = fitAlignmentByPeaksAUC(sideCSV, frontCSV, coreID, outDir, alignOpts, fid);

    % --- rerun front only ---
    if rerunFrontOnly && isfile(reachMatFile)
        S = load(reachMatFile, 'reaches');
        reaches = S.reaches;

        % Remap using the NEW model
        for j = 1:numel(reaches)
            oldFront = reaches(j).frontFrames;                % store original
            newFront = model.mapSide2Front(reaches(j).sideFrames);  % recompute

            % Print first/last few values to avoid flooding log
            logMsg(sprintf('Reach %d: oldFront(1:3)=%s ... %s | newFront(1:3)=%s ... %s', ...
                j, mat2str(oldFront(1:min(3,end))), mat2str(oldFront(max(end-2,1):end)), ...
                mat2str(newFront(1:min(3,end))), mat2str(newFront(max(end-2,1):end))), ...
                true, fid);

            reaches(j).frontFrames = newFront;  % overwrite
        end

        save(reachMatFile, 'reaches');
        logMsg(sprintf('🔄 Updated front frames for %s with new alignment model', coreID), true, fid);
        continue;
    end

    logMsg(sprintf('🐾 Detecting reaches for %s...', coreID), true, fid);

    if isempty(sideCSV) || isempty(frontCSV)
        logMsg('Missing DLC tables for this pair. Skipping.', true, fid);
        continue;
    end

    % Define slit threshold
    params.slit_threshold = getSlitThreshold(sideCSV, fid);
    params.pellet_merge_gap = 40;

    % Find reaches using sideView only
    [starts, ends, isReach, reachID] = detectReaches(sideCSV, params, fid, coreID, outDir);


    % Pack reach structs
    reaches = struct('startFrame', {}, 'endFrame', {}, 'sideFrames', {}, 'frontFrames', {}, 'label', {});
    for j = 1:length(starts)
        reaches(j).startFrame = starts(j);
        reaches(j).endFrame   = ends(j);
        reaches(j).sideFrames = starts(j):ends(j);
        reaches(j).frontFrames = model.mapSide2Front(reaches(j).sideFrames);

        % --- Pellet presence check ---
        f1 = starts(j);
        f2 = ends(j);
        len = f2 - f1 + 1;
        if len > 0
            checkFrames = f1 : f1 + floor(len/4);  % first quarter of reach
            checkFrames = checkFrames(checkFrames <= height(sideCSV));

            if ismember('pellet_likelihood', sideCSV.Properties.VariableNames)
                pelLh = sideCSV.pellet_likelihood(checkFrames);
                pelLh = pelLh(~isnan(pelLh));
                if isempty(pelLh) || mean(pelLh) < 0.2   % threshold adjustable
                    reaches(j).label = 'Attempt - No Pellet';
                else
                    reaches(j).label = '';
                end
            else
                reaches(j).label = '';  % pellet not tracked
            end
        else
            reaches(j).label = '';
        end



    end

    save(fullfile(outDir, sprintf('%s_reaches.mat', coreID)), 'reaches');
    tblData.TotalReaches(pairIdx) = numel(reaches);
end

% Final update
handles.tblStatus.Data = tblData;
handles.msgLabel.Text = 'Reach detection completed!';
handles.msgLabel.FontColor = handles.colors.successColor;
guidata(fig, handles);

% ===== Helper Functions =====

    function logParams(p, fid)
        logMsg('--- Reach Detection Parameters ---', false, fid);
        fns = fieldnames(p);
        for i = 1:numel(fns)
            logMsg(sprintf('%s: %s', strrep(fns{i}, '_', ' '), num2str(p.(fns{i}))), false, fid);
        end
    end

    function slit_x = getSlitThreshold(data, fid)
        if all(ismember({'slit_bottom__x', 'slit_top__x'}, data.Properties.VariableNames))
            slit_x_all = [data.slit_bottom__x; data.slit_top__x];
            slit_lh_all = [data.slit_bottom__likelihood; data.slit_top__likelihood];
            [~, idx] = sort(slit_lh_all, 'descend');
            topX = slit_x_all(idx(1:max(10, round(0.05 * numel(idx)))));
            slit_x = mean(topX, 'omitnan');
            logMsg(sprintf('Slit threshold: %.2f', slit_x), true, fid);
        else
            error('Missing slit coordinates');
        end
    end


    function [starts, ends, isReach, reachID] = detectReaches(data, p, fid, coreID, outDir)

        % ---------------------------
        % Step 0: parameter defaults
        % ---------------------------
        if ~isfield(p,'gauss_smooth')       || isempty(p.gauss_smooth),       p.gauss_smooth       = 5;  end
        if ~isfield(p,'slit_threshold')     || isempty(p.slit_threshold),     p.slit_threshold     = 240;end
        if ~isfield(p,'min_frames')         || isempty(p.min_frames),         p.min_frames         = 6;  end
        if ~isfield(p,'gap_tolerance')      || isempty(p.gap_tolerance),      p.gap_tolerance      = 5;  end
        if ~isfield(p,'pellet_contact_dist')|| isempty(p.pellet_contact_dist),p.pellet_contact_dist= 15; end
        if ~isfield(p,'pellet_merge_gap')   || isempty(p.pellet_merge_gap),   p.pellet_merge_gap   = 20; end
        if ~isfield(p,'overshoot_margin')   || isempty(p.overshoot_margin),   p.overshoot_margin   = 10; end
        if ~isfield(p,'frame_buffer')       || isempty(p.frame_buffer),       p.frame_buffer       = 0;  end
        % peak-finding (for overshoot inside reaches)
        if ~isfield(p,'pk_min_prom')        || isempty(p.pk_min_prom),        p.pk_min_prom        = 5;  end
        if ~isfield(p,'pk_min_dist')        || isempty(p.pk_min_dist),        p.pk_min_dist        = 15; end

        % ---------------------------
        % Step 1: Extract variables
        % ---------------------------
        pt_x  = data.paw_tip__x;
        pc_x  = data.paw_center__x;
        pt_lh = data.paw_tip__likelihood;
        pc_lh = data.paw_center__likelihood;

        % ---------------------------
        % Step 2: Smooth trajectories
        % ---------------------------
        pt_x_smooth = smoothdata(pt_x, 'gaussian', p.gauss_smooth);
        pc_x_smooth = smoothdata(pc_x, 'gaussian', p.gauss_smooth);

        % ---------------------------
        % Step 3: Candidate (above slit)
        % ---------------------------
        above_tip    = pt_x_smooth > p.slit_threshold;
        above_center = pc_x_smooth > p.slit_threshold;
        isCandidate  = above_tip | above_center;

        % Likelihood threshold (dynamic)
        lh_all  = max(pt_lh, pc_lh);
        lh_cand = lh_all(isCandidate);
        lh_cand = lh_cand(~isnan(lh_cand));
        if ~isempty(lh_cand)
            pL = prctile(lh_cand, 5);
            pH = prctile(lh_cand, 99);
            lh_win = lh_cand;
            lh_win(lh_win < pL) = pL;
            lh_win(lh_win > pH) = pH;
        else
            lh_win = lh_all(~isnan(lh_all));
        end
        t_otsu = graythresh(lh_win);
        t_q    = prctile(lh_win, 80);
        dyn_lh_thresh = max([(t_otsu + t_q)/2, 0.25]);
        p.paw_likelihood = dyn_lh_thresh;
        logMsg(sprintf('Dynamic paw likelihood: Otsu=%.3f, Q80=%.3f, chosen=%.3f', ...
            t_otsu, t_q, dyn_lh_thresh), true, fid);

        % ---------------------------
        % Step 3.5: Pellet contact heuristic
        % ---------------------------
        if ismember('pellet_x', data.Properties.VariableNames)
            dx = pt_x_smooth - data.pellet_x;

            if ismember('pellet_y', data.Properties.VariableNames) && ...
                    ismember('paw_tip__y', data.Properties.VariableNames)
                dy = data.paw_tip__y - data.pellet_y;
                dist_tip = hypot(dx, dy);
            else
                dist_tip = abs(dx);
            end

            if ismember('pellet_likelihood', data.Properties.VariableNames)
                valid_lh = (pt_lh >= p.paw_likelihood) & (data.pellet_likelihood >= 0.3);
            else
                valid_lh = (pt_lh >= p.paw_likelihood);
            end

            pellet_contact = (dist_tip < p.pellet_contact_dist) & valid_lh;
        else
            pellet_contact = false(height(data),1);
        end


        % ---------------------------
        % Step 4: Likelihood & length filtering
        % ---------------------------
        [starts_raw, ends_raw] = getSegments(isCandidate);
        isReach = false(height(data), 1);
        too_short = []; too_short_e = [];
        low_lh = [];   low_lh_e   = [];
        for i = 1:numel(starts_raw)
            s = starts_raw(i);
            e = ends_raw(i);
            len = e - s + 1;

            if len < p.min_frames
                too_short(end+1) = s; %#ok<AGROW>
                too_short_e(end+1) = e;
                continue;
            end

            frames_above_lh = (pt_lh(s:e) >= p.paw_likelihood) | ...
                (pc_lh(s:e) >= p.paw_likelihood);
            if sum(frames_above_lh) >= p.min_frames
                isReach(s:e) = true;
            else
                low_lh(end+1) = s; %#ok<AGROW>
                low_lh_e(end+1) = e;
            end
        end

        % ---------------------------
        % Step 5: Morphological cleanup
        % ---------------------------
        se = ones(max(1, round(p.gap_tolerance)), 1);
        isReach = imclose(isReach, se);

        % ---------------------------
        % Step 6: Split reaches if several peaks with overshoot/pellet contact
        % ---------------------------
        [starts, ends] = getSegments(isReach);
        nFrames = height(data);   % total number of frames, needed for buffer clamping

        % Precompute pellet anchors (merge contacts into areas)

        [pc_s_all, pc_e_all] = getSegments(pellet_contact);

        if ~isempty(pc_s_all)
            merged_s = pc_s_all(1);
            merged_e = pc_e_all(1);
            new_pc_s = []; new_pc_e = [];
            for k = 2:numel(pc_s_all)
                if pc_s_all(k) - merged_e <= p.pellet_merge_gap
                    merged_e = pc_e_all(k);
                else
                    new_pc_s(end+1) = merged_s; %#ok<AGROW>
                    new_pc_e(end+1) = merged_e;
                    merged_s = pc_s_all(k);
                    merged_e = pc_e_all(k);
                end
            end
            new_pc_s(end+1) = merged_s; %#ok<AGROW>
            new_pc_e(end+1) = merged_e; %#ok<AGROW>
            pc_s_all = new_pc_s;
            pc_e_all = new_pc_e;
        end

        % Center of each pellet area = pellet anchors
        pellet_anchors_all = round((pc_s_all + pc_e_all)/2);

        % ---------------------------
        % Step 6b: Refine reaches by anchors (pellet + overshoot)
        % ---------------------------
        new_starts = [];
        new_ends   = [];
        overshoot_anchor_list = [];

        for r = 1:numel(starts)
            s = starts(r);
            e = ends(r);

            % ---- pellet anchors (merged areas, already computed globally) ----
            pel_here = pellet_anchors_all(pellet_anchors_all >= s & pellet_anchors_all <= e);

            % ---- overshoot anchors (true peaks beyond pellet) ----
            seg_x = pt_x_smooth(s:e);

            if ismember('pellet_x', data.Properties.VariableNames)
                pellet_here = nanmedian(data.pellet_x(s:e));
            else
                pellet_here = prctile(seg_x,95); % fallback if pellet not tracked
            end

            segLen = numel(seg_x);
            if segLen < 2
                % Too short for peak detection
                continue; % skip this segment
            end

            baseDist = 60;
            minDist = min(baseDist, segLen - 1);

            if minDist >= (segLen - 1)
                minDist = segLen - 2;
            end

            if minDist < 1
                minDist = 1;
            end

            fprintf('segLen: %.2f, minDist: %.2f\n',segLen, minDist);

            [pks, locs] = findpeaks(seg_x, 'MinPeakProminence', 0.15, 'MinPeakHeight', 0.6, 'MinPeakDistance', minDist);
            keep = pks > (pellet_here + p.overshoot_margin);
            over_here = s + locs(keep) - 1;

            overshoot_anchor_list = [overshoot_anchor_list, over_here(:)']; %#ok<AGROW>

            % ---- combine anchors ----
            anchors = unique([pel_here(:); over_here(:)]);

            % ---- refine: find local minima around each anchor ----
            if isempty(anchors)
                % no anchors → keep full reach
                new_starts(end+1) = s;
                new_ends(end+1)   = e;
            else
                for a = 1:numel(anchors)
                    this_anchor = anchors(a);

                    % find nearest local minimum to left
                    left_idx = this_anchor-1;
                    while left_idx > s+1 && seg_x(left_idx-s+1) > seg_x(left_idx-s)
                        left_idx = left_idx-1;
                    end

                    % find nearest local minimum to right
                    right_idx = this_anchor+1;
                    while right_idx < e-1 && seg_x(right_idx-s+1) > seg_x(right_idx-s+2)
                        right_idx = right_idx+1;
                    end

                    % add refined segment
                    new_starts(end+1) = max(s,left_idx);
                    new_ends(end+1)   = min(e,right_idx);
                end
            end
        end

        % replace
        starts = new_starts(:)';
        ends   = new_ends(:)';

        % ============================================================
        % Step 6c: Merge overlapping/adjacent segments
        % ============================================================
        if ~isempty(starts)
            % sort just in case
            [starts, sortIdx] = sort(starts);
            ends = ends(sortIdx);

            merged_s = starts(1);
            merged_e = ends(1);

            clean_starts = [];
            clean_ends   = [];

            for k = 2:numel(starts)
                if starts(k) <= merged_e   % overlap or touching
                    merged_e = max(merged_e, ends(k));
                else
                    clean_starts(end+1) = merged_s; %#ok<AGROW>
                    clean_ends(end+1)   = merged_e; %#ok<AGROW>
                    merged_s = starts(k);
                    merged_e = ends(k);
                end
            end

            % add last segment
            clean_starts(end+1) = merged_s;
            clean_ends(end+1)   = merged_e;

            starts = clean_starts;
            ends   = clean_ends;
        end

        % ---------------------------
        % Step 7: Apply buffer (playback only)
        % ---------------------------
        starts = max(starts - p.frame_buffer, 1);
        ends   = min(ends   + p.frame_buffer, nFrames);

        % ---------------------------
        % Step 8: Assign reachID
        % ---------------------------
        reachID = zeros(nFrames, 1);
        for i = 1:numel(starts)
            reachID(starts(i):ends(i)) = i;
        end

        % ==========================
        % === FINAL QC FIGURE ===
        % ==========================
        qcDir = fullfile(outDir, 'QC'); if ~exist(qcDir,'dir'), mkdir(qcDir); end
        qcFile = fullfile(qcDir, sprintf('REACH_pawlikelihood_cutoff_%s.png', coreID));

        % ---- Summary plot ----
        f = figure('Visible','on','Name',sprintf('QC Summary — %s',coreID));
        tiledlayout(f,1,1,'Padding','compact','TileSpacing','compact');
        ax = nexttile; hold(ax,'on');

        % Smoothed tip (colored by likelihood)
        scatter(ax, 1:height(data), pt_x_smooth, 12, pt_lh, 'filled');
        colormap(ax, parula);
        cb = colorbar(ax); cb.Label.String = 'Tip likelihood';

        % Highlights (kept reaches with border)
        highlightSegments(ax, too_short, too_short_e, [1 0 0]); % too short (red)
        highlightSegments(ax, low_lh,    low_lh_e,    [1 0.5 0]); % low likelihood (orange)
        highlightSegments(ax, starts,    ends,        'c');       % final kept (cyan)
        uistack(findobj(ax,'Type','patch'),'bottom');

        % --- Pellet contact dots (magenta circles) ---
        if exist('pellet_contact','var') && any(pellet_contact)
            scatter(ax, find(pellet_contact), pt_x_smooth(pellet_contact), ...
                25, 'mo', 'filled', 'MarkerFaceAlpha', 0.7, 'DisplayName','Pellet contact');
        end

        % --- Pellet anchors (black triangles) ---
        if exist('pellet_anchors_all','var') && ~isempty(pellet_anchors_all)
            scatter(ax, pellet_anchors_all, pt_x_smooth(pellet_anchors_all), ...
                40, 'k^', 'filled', 'MarkerFaceAlpha', 0.9, 'DisplayName','Pellet anchor');
        end

        % --- Overshoot anchors (green diamonds) ---
        if exist('overshoot_anchor_list','var') && ~isempty(overshoot_anchor_list)
            scatter(ax, overshoot_anchor_list, pt_x_smooth(overshoot_anchor_list), ...
                40, 'gd', 'filled', 'MarkerFaceAlpha', 0.9, 'DisplayName','Overshoot anchor');
        end

        % Legend stubs
        hShort = plot(ax,nan,nan,'s','MarkerFaceColor',[1 0 0],'MarkerEdgeColor','none');
        hLow   = plot(ax,nan,nan,'s','MarkerFaceColor',[1 0.5 0],'MarkerEdgeColor','none');
        hFinal = plot(ax,nan,nan,'s','MarkerFaceColor','c','MarkerEdgeColor','none');
        hPel   = plot(ax,nan,nan,'o','MarkerFaceColor','m','MarkerEdgeColor','none');
        hPelA  = plot(ax,nan,nan,'^','MarkerFaceColor','k','MarkerEdgeColor','none');
        hOver  = plot(ax,nan,nan,'d','MarkerFaceColor','g','MarkerEdgeColor','none');

        legend(ax,[hShort hLow hFinal hPel hPelA hOver], ...
            {'Too short','Low likelihood','Final','Pellet contact','Pellet anchor','Overshoot anchor'}, ...
            'Location','bestoutside');

        % Save
        qcFileSummary_png = fullfile(qcDir, sprintf('REACH_%s_QC_summary.png', coreID));
        saveas(f, qcFileSummary_png);
        qcFileSummary_fig = fullfile(qcDir, sprintf('REACH_%s_QC_summary.fig', coreID));
        saveas(f, qcFileSummary_fig);
        close(f);

        logMsg(sprintf('Num Reaches detected (side): %d', numel(starts)), true, fid);


        % ---- helper for colored patches with border ----
        function highlightSegments(ax, s, e, color)
            yl = ylim(ax);
            for k = 1:numel(s)
                patch(ax, [s(k) e(k) e(k) s(k)], ...
                    [yl(1) yl(1) yl(2) yl(2)], ...
                    color, 'FaceAlpha', 0.20, ...
                    'EdgeColor', 'k', 'LineWidth', 0.5, ...
                    'HandleVisibility','off');
            end
        end

    end

end




function [s, e] = getSegments(logicalVec)
s = []; e = []; in = false;
for i = 1:length(logicalVec)
    if ~in && logicalVec(i), s(end+1) = i; in = true;
    elseif in && ~logicalVec(i), e(end+1) = i-1; in = false; end
end
if in, e(end+1) = length(logicalVec); end
end

function tbl = ensureReachColumns(tbl)
if ~ismember('TotalReaches', tbl.Properties.VariableNames)
    tbl.TotalReaches = zeros(height(tbl),1);
elseif iscell(tbl.TotalReaches)
    tbl.TotalReaches = cellfun(@(x) ifempty(x,0), tbl.TotalReaches);
end
end
%
% function val = ifempty(x, def)
% if isempty(x), val = def; else, val = x; end
% end


function v = getField(T, preferName, altName)
% grab T.(preferName) if present, else T.(altName). Returns zeros if missing.
v = [];
if istable(T)
    if ismember(preferName, T.Properties.VariableNames)
        v = T.(preferName);
    elseif ismember(altName, T.Properties.VariableNames)
        v = T.(altName);
    end
end
if isempty(v)
    v = zeros(height(T),1);
end
end

function model = fitAlignmentByPeaksAUC(Tside, Tfront, coreID, outDir, alignOpts, fid)
% fitAlignmentByPeaksAUC  (anchors = plateau starts; peaks only for QC)
% Robust to missing fields in alignOpts (fills sane defaults).

if nargin < 6 || isempty(fid), fid = 1; end

% ---------- defaults (filled if missing) ----------
DEF.initOffset      = 0;        % hint only (coarse offset overrides)
DEF.sideSmooth      = 101;      % Gaussian win (numeric); struct ok (see getSmoothWin)
DEF.frontSmooth     = 401;
DEF.timeWindow      = 2000;     % initial candidate window (frames)
DEF.alpha           = 1.0;      % timing weight
DEF.beta            = 0.7;      % area weight (z-diff)
DEF.maxAllow        = 1.2;      % initial max matching cost
DEF.minMatchesWant  = 6;        % target pairs before fitting
DEF.maxRelaxIters   = 3;        % relax rounds
DEF.coarseLagMax    = 10000;    % coarse xcorr max lag (frames)
DEF.downsample      = 20;       % downsample for coarse xcorr
DEF.plateauThresh   = 0.4;     % passed into buildPelletEvents (also adapts inside)
DEF.plateauMinDur   = 100;

if nargin < 5 || isempty(alignOpts), alignOpts = struct(); end
fn = fieldnames(DEF);
for k=1:numel(fn)
    if ~isfield(alignOpts, fn{k}) || isempty(alignOpts.(fn{k}))
        alignOpts.(fn{k}) = DEF.(fn{k});
    end
end

% Peak detection thresholds (fill missing subfields)
FPDEF = struct('MinPeakHeight',0.6,'MinPeakProminence',0.15, ...
    'MinPeakDistance',1500,'MinPeakWidth',20);
if ~isfield(alignOpts,'fp') || isempty(alignOpts.fp), alignOpts.fp = FPDEF; end
sub = fieldnames(FPDEF);
for k=1:numel(sub)
    if ~isfield(alignOpts.fp, sub{k}) || isempty(alignOpts.fp.(sub{k}))
        alignOpts.fp.(sub{k}) = FPDEF.(sub{k});
    end
end

% Allow smoothing window as numeric or struct with .gauss
sideWin  = getSmoothWin(alignOpts.sideSmooth, 201);
frontWin = getSmoothWin(alignOpts.frontSmooth, 401);

% ---------- extract pellet likelihoods ----------
pelSide  = getField(Tside,'pellet__likelihood','pellet_likelihood');
pelFront = getField(Tfront,'pellet__likelihood','pellet_likelihood');

% ---------- build events (your buildPelletEvents does dynamic tuning) ----------
[eSide,  fpSideEff,  plSideEff]  = buildPelletEvents(pelSide, sideWin, alignOpts.fp, alignOpts.plateauThresh, alignOpts.plateauMinDur, 'Side', fid);
[eFront, fpFrontEff, plFrontEff] = buildPelletEvents(pelFront, frontWin, alignOpts.fp, alignOpts.plateauThresh, alignOpts.plateauMinDur, 'Front', fid);

logMsg(sprintf('[%s] Side dynThr=%.3f (base=%.2f) | kept plateaus=%d (minDur=%d)', ...
    coreID, plSideEff.plateauThresh, alignOpts.plateauThresh, size(eSide.plat.se,1), alignOpts.plateauMinDur), true, fid);

logMsg(sprintf('[%s] Side: peaks=%d, plateaus=%d', ...
    coreID, numel(eSide.peak.idx), size(eSide.plat.se,1)), true, fid);

logMsg(sprintf('[%s] Front: peaks=%d, plateaus=%d', ...
    coreID, numel(eFront.peak.idx), size(eFront.plat.se,1)), true, fid);


% ---------- choose anchors = plateau STARTS (fallback to peaks) ----------
if ~isempty(eSide.plat.se),  anchorS = eSide.plat.se(:,1);  else, anchorS = eSide.peak.idx;  end
if ~isempty(eFront.plat.se), anchorF = eFront.plat.se(:,1); else, anchorF = eFront.peak.idx; end

% ---------- coarse offset (front->side) from xcorr of smoothed signals ----------
rough = estimate_coarse_offset(eSide.sig, eFront.sig, alignOpts.downsample, alignOpts.coarseLagMax);
logMsg(sprintf('[%s] Coarse offset (front->side): %+d frames', coreID, rough), true, fid);

% ---------- restrict anchors to manual boundaries ----------
if isfield(alignOpts,'FrontFrame1') && isfield(alignOpts,'FrontFrame2') && ...
        isfield(alignOpts,'SideFrame1')  && isfield(alignOpts,'SideFrame2')

    manualFront = [alignOpts.FrontFrame1, alignOpts.FrontFrame2];
    manualSide  = [alignOpts.SideFrame1,  alignOpts.SideFrame2];

    % Sort in case user provided out of order
    [manualFront, order] = sort(manualFront);
    manualSide = manualSide(order);

    fMin = manualFront(1); fMax = manualFront(end);
    sMin = manualSide(1);  sMax = manualSide(end);

    keepF = anchorF >= fMin & anchorF <= fMax;
    keepS = anchorS >= sMin & anchorS <= sMax;

    anchorF = anchorF(keepF);
    anchorS = anchorS(keepS);

    logMsg(sprintf('Restricted auto anchors to manual window: Front[%d..%d], Side[%d..%d]', ...
        fMin,fMax,sMin,sMax), true, fid);
end

% ---------- matching with relaxation cascade ----------
[a,b, matchPairs, usedCost, matchparam, model] = match_with_relax( ...
    eSide, eFront, anchorS, anchorF, rough, alignOpts, fid);

% Ensure matchPairs indices are valid for the restricted anchor arrays
valid = matchPairs(:,1) <= numel(anchorS) & matchPairs(:,2) <= numel(anchorF);
matchPairs = matchPairs(valid,:);

model.frontN = height(Tfront);
model.sideN  = height(Tside);


% ---------- QC ----------
figDir = fullfile(outDir,'QC'); if ~exist(figDir,'dir'), mkdir(figDir); end
cmap = lines(max(1,size(matchPairs,1)));

% (1) events + matched anchors (colored)
f = figure('Visible','off','Name',sprintf('Matched anchors — %s',coreID));
tiledlayout(2,1,'Padding','compact','TileSpacing','compact');

% --- SIDE ---
ax1 = nexttile; hold(ax1,'on');
plot(ax1, eSide.sig, 'm');  % raw signal in Side time
for k=1:size(eSide.plat.se,1)
    S=eSide.plat.se(k,1); E=eSide.plat.se(k,2);
    patch(ax1,[S E E S],[0 0 1 1],'m','FaceAlpha',0.1,'EdgeColor','none');
end
scatter(ax1, eSide.peak.idx, eSide.sig(eSide.peak.idx), 16,'k','filled');
if ~isempty(matchPairs)
    for p = 1:size(matchPairs,1)
        i = matchPairs(p,1);
        if i <= numel(anchorS)
            scatter(ax1, anchorS(i), eSide.sig(anchorS(i)), 36, cmap(p,:), 'filled');
        end
        text(anchorS(i), min(0.95, eSide.sig(anchorS(i))+0.06), sprintf('%d',p), ...
            'Color', cmap(p,:), 'FontWeight','bold','HorizontalAlignment','center');
    end
end
title(ax1,'Side: matched anchors (original time)'); ylabel(ax1,'Lh');
ylim(ax1,[0 1]); xlim(ax1,[1 numel(eSide.sig)]);

% --- FRONT ---
ax2 = nexttile; hold(ax2,'on');
plot(ax2, eFront.sig, 'g');
for k=1:size(eFront.plat.se,1)
    S=eFront.plat.se(k,1); E=eFront.plat.se(k,2);
    patch(ax2,[S E E S],[0 0 1 1],'g','FaceAlpha',0.1,'EdgeColor','none');
end
scatter(ax2, eFront.peak.idx, eFront.sig(eFront.peak.idx), 16,'k','filled');
if ~isempty(matchPairs)
    for p = 1:size(matchPairs,1)
        j = matchPairs(p,2);
        scatter(ax2, anchorF(j), eFront.sig(anchorF(j)), 36, cmap(p,:), 'filled');
        text(anchorF(j), min(0.95, eFront.sig(anchorF(j))+0.06), sprintf('%d',p), ...
            'Color', cmap(p,:), 'FontWeight','bold','HorizontalAlignment','center');
    end
end

% --- Boundary anchors (blue stars) ---
if isfield(alignOpts,'OffsetStart') && ~isnan(alignOpts.OffsetStart) ...
        && isfield(alignOpts,'SideFrame1') && isfield(alignOpts,'FrontFrame1')
    scatter(ax1, alignOpts.SideFrame1, eSide.sig(min(end, alignOpts.SideFrame1)), ...
        60, 'b*', 'LineWidth',1.5);
    scatter(ax2, alignOpts.FrontFrame1, eFront.sig(min(end, alignOpts.FrontFrame1)), ...
        60, 'b*', 'LineWidth',1.5);
end
if isfield(alignOpts,'OffsetEnd') && ~isnan(alignOpts.OffsetEnd) ...
        && isfield(alignOpts,'SideFrame2') && isfield(alignOpts,'FrontFrame2')
    scatter(ax1, alignOpts.SideFrame2, eSide.sig(min(end, alignOpts.SideFrame2)), ...
        60, 'b*', 'LineWidth',1.5);
    scatter(ax2, alignOpts.FrontFrame2, eFront.sig(min(end, alignOpts.FrontFrame2)), ...
        60, 'b*', 'LineWidth',1.5);
end

title(ax2,'Front: matched anchors (original time)');
xlabel(ax2,'Frame'); ylabel(ax2,'Lh');
ylim(ax2,[0 1]); xlim(ax2,[1 numel(eFront.sig)]);
saveas(f, fullfile(figDir, sprintf('ALIGN_EVENT-MATCH_%s.png', coreID)));
close(f);

% (2) Frame mapping QC
if ~isempty(matchPairs)
    fQC = figure('Visible','off','Name',sprintf('Frame Mapping QC — %s', coreID));
    hold on; grid on;

    % --- Anchors driving the mapping ---
    usedF = model.tF_sorted(:);
    usedS = model.tS_sorted(:);

    % --- Mapping curve ---
    modeStr = lower(alignOpts.alignMode);
    if any(strcmpi(modeStr, {'piecewise','segmented'}))
        % broken-stick polyline through anchors
        plot(usedF, usedS, 'r-', 'LineWidth',1.5, 'MarkerSize',4, ...
            'DisplayName',[upper(modeStr(1)) modeStr(2:end) ' mapping']);
    else
        % dense sample for affine/pchip
        xx = linspace(0, model.frontN, 400);
        yy = model.mapFront2Side(xx);
        plot(xx, yy, 'r-', 'LineWidth',1.5, 'DisplayName','Mapping curve');
        % overlay polyline through used anchors for context
        plot(usedF, usedS, 'r--o', 'LineWidth',1.0, 'MarkerSize',4, ...
            'DisplayName','Anchor polyline');
    end

    % Dropped anchors
    if isfield(model,'tF_all')

        droppedMask = ~ismember(model.tF_all, model.tF_sorted);
        droppedManual = droppedMask & model.w_all > 1;
        droppedAuto   = droppedMask & model.w_all == 1;
        scatter(model.tF_all(droppedAuto), model.tS_all(droppedAuto), ...
            60, 'rx', 'LineWidth',1.5, 'DisplayName','Dropped auto anchors');
        scatter(model.tF_all(droppedManual), model.tS_all(droppedManual), ...
            70, 'ms','filled','LineWidth',1.5,'DisplayName','Dropped manual anchors');
    end

    % Kept anchors
    if isfield(model,'isManual')
        scatter(model.tF_sorted(~model.isManual), model.tS_sorted(~model.isManual), ...
            50, 'b*','LineWidth',1.5,'DisplayName','Kept auto anchors');
        scatter(model.tF_sorted(model.isManual), model.tS_sorted(model.isManual), ...
            70, 'gd','filled','LineWidth',1.5,'DisplayName','Kept manual anchors');
    end

    % --- Axis formatting ---
    xlim([0 model.frontN*1.05]);
    ylim([0 model.sideN*1.05]);
    xlabel('Front anchor frame (video)');
    ylabel('Side anchor frame (video)');
    title(sprintf('Frame mapping with %s fit', alignOpts.alignMode));

    xline(model.frontN,'g--','End Front');
    yline(model.sideN,'m--','End Side');

    legend('show','Location','best');
    saveas(fQC, fullfile(figDir, sprintf('ALIGN_FRAMEMAP_%s.png', coreID)));
    close(fQC);
end


% (3) Offset drift QC
if ~isempty(matchPairs)
    f5 = figure('Visible','off','Name',sprintf('Offset Drift — %s', coreID));
    hold on; grid on;

    offsets = model.tS_sorted(:) - model.tF_sorted(:);
    plot(model.tF_sorted, offsets, 'o-','LineWidth',1.5,'MarkerSize',8);

    xx = linspace(min(model.tF_sorted), max(model.tF_sorted), 300);
    yy = model.mapFront2Side(xx) - xx;
    plot(xx, yy, 'r-','LineWidth',1.5,'DisplayName','Spline-predicted');


    % Manual anchors
    if isfield(alignOpts,'FrontFrame1') && isfield(alignOpts,'SideFrame1')
        off1 = alignOpts.SideFrame1 - alignOpts.FrontFrame1;
        scatter(alignOpts.FrontFrame1, off1, 60,'b*','LineWidth',1.5);
        text(alignOpts.FrontFrame1, off1, 'Start anchor', ...
            'VerticalAlignment','top','HorizontalAlignment','left','Color','b');
    end

    if isfield(alignOpts,'FrontFrame2') && isfield(alignOpts,'SideFrame2')
        off2 = alignOpts.SideFrame2 - alignOpts.FrontFrame2;
        scatter(alignOpts.FrontFrame2, off2, 60,'b*','LineWidth',1.5);
        text(alignOpts.FrontFrame2, off2, 'End anchor', ...
            'VerticalAlignment','bottom','HorizontalAlignment','right','Color','b');
    end


    xlabel('Front anchor frame'); ylabel('Offset (Side - Front)');
    title('Offset drift across video');
    saveas(f5, fullfile(figDir, sprintf('ALIGN_OFFSET_%s.png', coreID)));
    close(f5);
end

% (4) Local slope QC
if ~isempty(matchPairs)
    fSlope = figure('Visible','off','Name',sprintf('Local Slope — %s', coreID));
    xx = linspace(model.tF_sorted(1), model.tF_sorted(end), 300);
    yy = model.mapFront2Side(xx);
    slope = gradient(yy) ./ gradient(xx);

    plot(xx, slope, 'o-','LineWidth',1.5); grid on
    xlabel('Front frame'); ylabel('dSide/dFront');
    title('Local slope (effective rate drift)');
    saveas(fSlope, fullfile(figDir, sprintf('ALIGN_SLOPE_%s.png', coreID)));
    close(fSlope);
end


end

% ============================ helpers ==============================
function w = getSmoothWin(val, def)
if isstruct(val)
    if isfield(val,'gauss') && ~isempty(val.gauss), w = val.gauss; else, w = def; end
elseif isnumeric(val) && ~isempty(val)
    w = val;
else
    w = def;
end
if w < 1, w = 1; end
end

function off = estimate_coarse_offset(sigSide, sigFront, ds, maxLag)
if ds < 1, ds = 1; end
s1 = downsample(double(sigSide), max(1,ds));
s2 = downsample(double(sigFront), max(1,ds));
% focus on dips (pellet disappearing)
s1 = 1 - (s1 - min(s1))/max(eps, (max(s1)-min(s1)));
s2 = 1 - (s2 - min(s2))/max(eps, (max(s2)-min(s2)));
L = min(numel(s1), numel(s2));
s1 = s1(1:L); s2 = s2(1:L);
ml = min(maxLag, L-5);
[c,lags] = xcorr(s1 - mean(s1), s2 - mean(s2), ml, 'coeff');
[~,idx] = max(c);
off = lags(idx) * ds; % frames front->side
end


function [a,b,matchPairs,usedCost,matchparam,model] = match_with_relax(eSide,eFront,anchorS,anchorF,initOff,opts,fid)
% Defaults
a = 1; b = initOff; matchPairs = []; usedCost = opts.maxAllow;
alpha0 = opts.alpha; beta  = opts.beta; win = opts.timeWindow; maxAllow = opts.maxAllow;

% --- Candidate matching loop ---
for attempt = 0:opts.maxRelaxIters
    [cI,cJ,cost,m,n] = candidates(eSide,eFront,anchorS,anchorF,initOff,win,alpha0,beta);
    logMsg(sprintf('  attempt %d: candidates=%d (m=%d,n=%d) | win=%d | beta=%.2f | maxAllow=%.2f', ...
        attempt,numel(cost),m,n,win,beta,maxAllow), true,fid);

    if isempty(cost)
        matchPairs = [];
    else
        C = inf(m,n); C(sub2ind([m n],cI,cJ)) = cost;
        try
            [ai,aj] = matchpairs(C,maxAllow);
            matchPairs = [ai,aj];
        catch
            [~,order] = sort(cost,'ascend');
            usedI = false(m,1); usedJ = false(n,1); tmp = [];
            for k = 1:numel(order)
                ii = cI(order(k)); jj = cJ(order(k));
                if ~usedI(ii) && ~usedJ(jj) && cost(order(k)) <= maxAllow
                    tmp(end+1,:) = [ii jj]; %#ok<AGROW>
                    usedI(ii) = true; usedJ(jj) = true;
                end
            end
            matchPairs = tmp;
        end
    end

    logMsg(sprintf('  attempt %d: matched=%d',attempt,size(matchPairs,1)), true,fid);
    if size(matchPairs,1) >= opts.minMatchesWant, usedCost = maxAllow; break; end

    % relax constraints
    beta     = max(0.2,beta*0.6);
    win      = round(win*1.5);
    maxAllow = maxAllow + 0.3;

    if attempt==1 && size(matchPairs,1) <= 1 && ...
            ~isempty(eSide.peak.idx) && ~isempty(eFront.peak.idx)
        logMsg('  switching to PEAK MAXIMA anchors for matching', true,fid);
        anchorS = eSide.peak.idx;
        anchorF = eFront.peak.idx;
        matchPairs = [];
    end
end

% --- Gather matched anchors ---
if ~isempty(matchPairs)
    tS = anchorS(matchPairs(:,1));
    tF = anchorF(matchPairs(:,2));
else
    tS = []; tF = [];
end

weights = ones(numel(tF),1);

% Inject manual anchors directly
if isfield(opts,'FrontFrame1') && isfield(opts,'SideFrame1')
    tF = [opts.FrontFrame1; tF(:)];
    tS = [opts.SideFrame1; tS(:)];
    weights = [opts.anchorWeight; weights];
end

if isfield(opts,'FrontFrame2') && isfield(opts,'SideFrame2')
    tF = [opts.FrontFrame2; tF(:)];
    tS = [opts.SideFrame2; tS(:)];
    weights = [opts.anchorWeight; weights];
end

% ---------- SAVE RAW ANCHORS HERE ----------
model.tF_all = tF(:);
model.tS_all = tS(:);
model.w_all  = weights(:);

% before the gate
pinManuals = isfield(opts,'alignMode') && strcmpi(opts.alignMode,'segmented');

% ================== CONSISTENCY GATE (diagnostic-only if segmented) ==================
autoMask = (weights == 1);
tF_auto  = tF(autoMask); tS_auto = tS(autoMask);

if numel(tF_auto) >= 3
    ab0 = lscov([tF_auto(:) ones(numel(tF_auto),1)], tS_auto(:), ones(numel(tF_auto),1));
    a0  = ab0(1); b0 = ab0(2);
    r   = (a0 .* tF(:) + b0) - tS(:);      % residuals vs. auto-only line
    madR = mad(r,1);
    tau  = max(6*max(madR,1), 400);

    isManual = weights > 1;

    % Always log residuals for manuals
    if any(isManual)
        for k = find(isManual)'
            logMsg(sprintf('Manual anchor: F=%d | S_meas=%d | S_calc=%.0f | resid=%.0f', ...
                tF(k), tS(k), a0*tF(k)+b0, r(k)), true, fid);
        end
    end

    if ~pinManuals
        % original behavior (allowed to change manual weights)
        badMan = isManual & abs(r) > tau;
        if any(badMan)
            % Softer penalty but still >1 keeps them as manuals (optional):
            weights(badMan) = max(weights(badMan) * 0.5, 1.1);
            % Or: weights(badMan) = 0.1;  % hard drop (NOT used for segmented)
            logMsg(sprintf('Manual anchor(s) softened by gate: idx=%s', ...
                mat2str(find(badMan)')), true, fid);
        end
    else
        % segmented mode: diagnostics only, don't touch weights
        model.flaggedManual = isManual & abs(r) > tau;  % for QC highlighting
        if any(model.flaggedManual)
            logMsg('Segmented mode: manual anchors flagged by residuals (kept).', true, fid);
        end
    end
end
% =====================================================================

%%% 1) Prune automatic anchors too close to manual ones
distThresh = 1000;   % distance in frames, adjust to taste
isManual = weights > 1;
keepMask = true(size(tF));
for k = find(isManual)'   % loop over manual anchors
    closeIdx = abs(tF - tF(k)) < distThresh & ~isManual;
    if any(closeIdx)
        logMsg(sprintf('Dropping %d auto anchors near manual anchor F=%d', ...
            sum(closeIdx), tF(k)), true, fid);
    end
    keepMask(closeIdx) = false;
end

%%% 2) Drop manual–manual conflicts (if r available)
if exist('r','var')
    manualIdx = find(isManual);
    for k = 1:numel(manualIdx)
        i = manualIdx(k);
        if ~keepMask(i), continue; end

        tooClose = abs(tF(manualIdx) - tF(i)) < distThresh;
        tooClose(manualIdx==i) = false;

        if any(tooClose)
            closeMans = manualIdx(tooClose);
            group = [i; closeMans(:)];
            [~,bestIdx] = min(abs(r(group)));
            keepMask(group) = false;
            keepMask(group(bestIdx)) = true;
            logMsg(sprintf('Dropping %d manual anchors near F=%d (kept best residual)', ...
                numel(group)-1, tF(group(bestIdx))), true, fid);
        end
    end
else
    logMsg('Warning: residuals r not found, skipping manual–manual pruning', true, fid);
end

%%% 3) Apply pruning
tF = tF(keepMask);
tS = tS(keepMask);
weights = weights(keepMask);
isManual = isManual(keepMask);

%%% 4) NOW add Manual-line gating + slope guard
% ---------------------------------------------------------------
% MANUAL-LINE GATING + SLOPE GUARD
% ---------------------------------------------------------------

haveTwoManuals = isfield(opts,'FrontFrame1') && isfield(opts,'SideFrame1') && ...
    isfield(opts,'FrontFrame2') && isfield(opts,'SideFrame2');

if haveTwoManuals
    aM = (opts.SideFrame2 - opts.SideFrame1) / max(eps, (opts.FrontFrame2 - opts.FrontFrame1));
    bM = opts.SideFrame1 - aM*opts.FrontFrame1;

    res = tS - (aM*tF + bM);
    tauRes = max(4*mad(res(~isManual),1), 600);
    keepR = isManual | abs(res) <= tauRes;

    if any(~keepR & ~isManual)
        logMsg(sprintf('Pruned %d auto anchors by manual-line residual (|res|>%d)', ...
            sum(~keepR & ~isManual), round(tauRes)), true, fid);
    end

    tF = tF(keepR);
    tS = tS(keepR);
    weights = weights(keepR);
    isManual = isManual(keepR);
end


% If too few anchors left, we'll fall back later anyway
if numel(tF) < 2
    a = NaN; b = NaN; usedCost = [];
    params = struct('beta',beta,'win',win,'maxAllow',maxAllow);
    model  = struct();
    return
end

% --- Final fit depending on opts.alignMode ---
if ~isfield(opts,'alignMode') || isempty(opts.alignMode)
    opts.alignMode = 'affine_weighted';
end

% sort and dedup
[tF,ord] = sort(tF(:)); tS = tS(ord); weights = weights(ord);
[tF,ia] = unique(tF,'stable'); tS = tS(ia); weights = weights(ia);

%%% DEBUG: how many anchors survived
nAnchors = numel(tF);
logMsg(sprintf('Final anchors used in model: %d', nAnchors), true, fid);
logMsg(sprintf('Manual anchors kept: %d / %d', sum(isManual), sum(weights>1)), true, fid);

% Save final pruned set
[tF_sorted, ord] = sort(tF(:));
tS_sorted = tS(ord);
w_sorted  = weights(ord);

[tF_sorted, ia] = unique(tF_sorted,'stable');
tS_sorted = tS_sorted(ia);
w_sorted  = w_sorted(ia);

model.tF_sorted = tF_sorted;
model.tS_sorted = tS_sorted;
model.w_sorted  = w_sorted;
model.isManual  = w_sorted > 1;   % manual anchors in final set

switch lower(opts.alignMode)
    case 'affine_weighted'
        X  = [tF(:), ones(size(tF(:)))];
        ab = lscov(X,tS(:),weights(:));
        a = ab(1); b = ab(2);
        model.mapFront2Side = @(tf) a*tf + b;
        model.mapSide2Front = @(ts) (ts - b)./max(a,eps);
        model.a=a; model.b=b;

    case 'piecewise'
        %%% NEW: multi-segment piecewise linear fit
        % Sort anchors by front-frame time
        [tF_sorted, ord] = sort(tF(:));
        tS_sorted = tS(ord);
        w_sorted  = weights(ord);

        % Deduplicate
        [tF_sorted, ia] = unique(tF_sorted,'stable');
        tS_sorted = tS_sorted(ia);
        w_sorted  = w_sorted(ia);

        % Build a piecewise-linear map by interpolation
        model.mapFront2Side = @(tf) interp1(tF_sorted, tS_sorted, tf, 'linear','extrap');
        model.mapSide2Front = @(ts) interp1(tS_sorted, tF_sorted, ts, 'linear','extrap');

        % For consistency with affine, also return an average slope
        if numel(tF_sorted) >= 2
            a = (tS_sorted(end)-tS_sorted(1)) / max(eps,(tF_sorted(end)-tF_sorted(1)));
            b = tS_sorted(1) - a*tF_sorted(1);
        else
            a = NaN; b = NaN;
        end

        model.a = a;
        model.b = b;
        model.tF_sorted = tF_sorted;
        model.tS_sorted = tS_sorted;
        model.w_sorted  = w_sorted;
        model.isManual  = w_sorted > 1;   % flag manual anchors


    case 'pchip'
        keep = [true; diff(tF)>0] & [true; diff(tS)>0];
        tf2=tF(keep); ts2=tS(keep);
        ppF2S = pchip(tf2,ts2);
        ppS2F = pchip(ts2,tf2);
        model.mapFront2Side=@(tf) ppval(ppF2S,tf);
        model.mapSide2Front=@(ts) ppval(ppS2F,ts);
        a=(ts2(end)-ts2(1))/max(eps,(tf2(end)-tf2(1)));
        b=ts2(1)-a*tf2(1);
        model.a=a; model.b=b;
    case 'segmented'
        % Sort anchors by front time
        [tF_sorted, ord] = sort(tF(:));
        tS_sorted = tS(ord);
        w_sorted  = weights(ord);

        % Need >=2 anchors
        if numel(tF_sorted) < 2
            warning('Segmented mode requires >=2 anchors; reverting to affine.');
            a = (tS_sorted(end)-tS_sorted(1)) / max(eps,(tF_sorted(end)-tF_sorted(1)));
            b = tS_sorted(1) - a*tF_sorted(1);
            model.mapFront2Side = @(tf) a.*tf + b;
            model.mapSide2Front = @(ts) (ts-b)./max(a,eps);
            segSlopes = a; segIntercepts = b;
        else
            % Local helper functions with safety rails
            mapFront2Side_local = @(x) localMapFront2Side(x, tF_sorted, tS_sorted);
            mapSide2Front_local = @(y) localMapSide2Front(y, tS_sorted, tF_sorted);

            % Vectorized
            model.mapFront2Side = @(tf) arrayfun(mapFront2Side_local, tf);
            model.mapSide2Front = @(ts) arrayfun(mapSide2Front_local, ts);

            % Segment info for debugging/QC
            segSlopes     = diff(tS_sorted) ./ max(diff(tF_sorted), eps);
            segIntercepts = tS_sorted(1:end-1) - segSlopes .* tF_sorted(1:end-1);
        end

        % Global slope for summary
        if numel(tF_sorted) >= 2
            a = (tS_sorted(end)-tS_sorted(1)) / max(eps,(tF_sorted(end)-tF_sorted(1)));
            b = tS_sorted(1) - a*tF_sorted(1);
        else
            a = NaN; b = NaN;
        end

        % Save for QC
        model.a = a; model.b = b;
        model.tF_sorted = tF_sorted;
        model.tS_sorted = tS_sorted;
        model.w_sorted  = w_sorted;
        model.isManual  = w_sorted > 1;
        model.segSlopes = segSlopes;
        model.segIntercepts = segIntercepts;

    otherwise
        error('Unknown opts.alignMode: %s',opts.alignMode);
end



% --- normalize model fields for QC (ALL MODES) ---
if ~isfield(model, 'tF_sorted') || ~isfield(model, 'tS_sorted')
    [tF_sorted_plot, ord_plot] = sort(tF(:));
    tS_sorted_plot = tS(ord_plot);
    w_sorted_plot  = weights(ord_plot);

    model.tF_sorted = tF_sorted_plot;
    model.tS_sorted = tS_sorted_plot;
    model.w_sorted  = w_sorted_plot;
    model.isManual  = w_sorted_plot > 1;
end
model.mode = lower(opts.alignMode);   % for QC titles

% Verify mapping passes through the anchors the model uses
if isfield(model,'tF_sorted') && isfield(model,'tS_sorted')
    err_used = max(abs(model.mapFront2Side(model.tF_sorted) - model.tS_sorted));
    logMsg(sprintf('Model/anchor consistency: max |F2S(used anchors)-S| = %.3f frames', err_used), true, fid);
end


% return everything needed for QC
matchparam = struct( ...
    'beta',beta, ...
    'win',win, ...
    'maxAllow',maxAllow, ...
    'tF_sorted',tF, ...
    'tS_sorted',tS, ...
    'weights',weights);

end

% ---------- helper ----------
function ys = localMapFront2Side(x, tF_sorted, tS_sorted)
if x <= tF_sorted(1)
    % Extrapolate using first two anchors
    slope = (tS_sorted(2)-tS_sorted(1)) / max(eps,(tF_sorted(2)-tF_sorted(1)));
    intercept = tS_sorted(1) - slope*tF_sorted(1);
    ys = slope*x + intercept;
elseif x >= tF_sorted(end)
    % Extrapolate using last two anchors
    slope = (tS_sorted(end)-tS_sorted(end-1)) / max(eps,(tF_sorted(end)-tF_sorted(end-1)));
    intercept = tS_sorted(end) - slope*tF_sorted(end);
    ys = slope*x + intercept;
else
    % Inside range → find segment
    idx = find(tF_sorted(1:end-1) <= x & x <= tF_sorted(2:end), 1, 'last');
    slope = (tS_sorted(idx+1)-tS_sorted(idx)) / max(eps,(tF_sorted(idx+1)-tF_sorted(idx)));
    intercept = tS_sorted(idx) - slope*tF_sorted(idx);
    ys = slope*x + intercept;
end
end

function xf = localMapSide2Front(y, tS_sorted, tF_sorted)
if y <= tS_sorted(1)
    slope = (tF_sorted(2)-tF_sorted(1)) / max(eps,(tS_sorted(2)-tS_sorted(1)));
    intercept = tF_sorted(1) - slope*tS_sorted(1);
    xf = slope*y + intercept;
elseif y >= tS_sorted(end)
    slope = (tF_sorted(end)-tF_sorted(end-1)) / max(eps,(tS_sorted(end)-tS_sorted(end-1)));
    intercept = tF_sorted(end) - slope*tS_sorted(end);
    xf = slope*y + intercept;
else
    idx = find(tS_sorted(1:end-1) <= y & y <= tS_sorted(2:end), 1, 'last');
    slope = (tF_sorted(idx+1)-tF_sorted(idx)) / max(eps,(tS_sorted(idx+1)-tS_sorted(idx)));
    intercept = tF_sorted(idx) - slope*tS_sorted(idx);
    xf = slope*y + intercept;
end
end

function tf = piecewise_inv(ts,a,b,c,k)
tf=zeros(size(ts));
yk = a*k + b;
idx1 = ts <= yk;
tf(idx1) = (ts(idx1)-b)./max(a,eps);
idx2 = ~idx1;
tf(idx2) = (ts(idx2)-(b-c*k))./max(a+c,eps);
end


function [cI,cJ,cost,m,n] = candidates(eSide,eFront,anchorS,anchorF,initOff,win,alpha,beta)
m = numel(anchorS); n = numel(anchorF);
cI=[]; cJ=[]; cost=[];
if ~m || ~n, return; end

for i = 1:m
    s_t = anchorS(i);
    expF = s_t - initOff;
    JJ = find(abs(anchorF - expF) <= win);
    if isempty(JJ), continue; end

    dt = abs((anchorF(JJ) + initOff) - s_t);  % timing cost

    % area z for this side anchor
    kS  = map_idx(eSide, s_t);
    aZs = 0; if kS>0 && kS<=numel(eSide.areaZ) && ~isnan(eSide.areaZ(kS)), aZs = eSide.areaZ(kS); end

    % area z for each candidate front anchor
    kF  = map_idx(eFront, anchorF(JJ));
    aZf = zeros(size(kF));
    good = kF>0 & kF<=numel(eFront.areaZ);
    aZf(good) = eFront.areaZ(kF(good));
    aZf(~good) = 0;

    dA = abs(aZf - aZs);
    dA = min(dA, 2.5);               % cap extremes

    c  = alpha*(dt./win) + beta*dA;

    cI  = [cI; i*ones(numel(JJ),1)];
    cJ  = [cJ; JJ(:)];
    cost = [cost; c(:)];
end
end

function k = map_idx(E, anchorIdx)
% map anchor time(s) to indices in E.idx (unified event list)
[~,k] = ismember(anchorIdx, E.idx);
end


% =====================================================================
% ========================== HELPER FUNCTIONS ==========================
% =====================================================================
function [events, fpEff, plEff] = buildPelletEvents(sig, smoothWin, fp, plateauThresh, plateauMinDur, viewName, fid)

% Build peaks + plateaus from a pellet-likelihood trace.
% - Peaks via findpeaks (prominence*width area proxy)
% - Plateaus via dynamic high-threshold; anchor at START of plateau
% Returns per-class areas and z-scores, plus unified arrays.

if nargin < 6 || isempty(viewName), viewName = 'View'; end

sig = sig(:);
sig(isnan(sig)) = 0;

if smoothWin > 1
    sig = smoothdata(sig,'gaussian',smoothWin);
end

% ---------------- Normalization ----------------
% Robustly stretch so tallest peak is ~1
if any(sig > 0)
    lo = prctile(sig,1);
    hi = prctile(sig,99);
    sig = (sig - lo) ./ max(eps, hi-lo);
    sig = min(max(sig,0),1);   % clamp to [0,1]
end

% Effective fp struct we may overwrite adaptively
fpEff = fp;

% Collect candidate local maxima for adaptive thresholds
isLM = islocalmax(sig);
LMamp = sig(isLM);
if isempty(LMamp), LMamp = sig; end
base   = median(sig);
spread = mad(sig,1);

% Adaptive MinPeakHeight
if ~isfield(fpEff,'MinPeakHeight') || isempty(fpEff.MinPeakHeight) || ...
        (ischar(fpEff.MinPeakHeight) && strcmpi(fpEff.MinPeakHeight,'auto'))
    k      = 2.0;   % MAD multiplier
    q      = 0.70;  % percentile of local maxima
    thrMAD = base + k*spread;
    thrQ   = quantile(LMamp,q);
    mpHeight = max(thrMAD, thrQ);
    fpEff.MinPeakHeight = min(mpHeight,0.95);
end

% Adaptive MinPeakProminence
if ~isfield(fpEff,'MinPeakProminence') || isempty(fpEff.MinPeakProminence) || ...
        (ischar(fpEff.MinPeakProminence) && strcmpi(fpEff.MinPeakProminence,'auto'))
    promMAD = 1.5*spread;
    tailGap = max(0, quantile(LMamp,0.85)-base);
    mpProm  = max(promMAD, 0.5*tailGap);
    fpEff.MinPeakProminence = min(mpProm,0.5);
end

% -------- peaks --------
[pks, locs, widths, prom] = findpeaks(sig, ...
    'MinPeakHeight',     fpEff.MinPeakHeight, ...
    'MinPeakProminence', fpEff.MinPeakProminence, ...
    'MinPeakDistance',   fpEff.MinPeakDistance, ...
    'MinPeakWidth',      fpEff.MinPeakWidth);

area_pk     = prom .* widths;
areaZ_pk    = zscore_robust(area_pk);

% -------- adaptive plateau threshold (baseline-aware) --------
nz = sig(sig > 0);                       % nonzero samples
if isempty(nz)
    thrDyn = plateauThresh;              % degenerate fallback
    hi=0;base=0;sLow=0;minFracHi=0;kMAD=0;
else
    hi    = prctile(nz,95);              % robust "high"
    base  = prctile(nz,30);              % baseline-ish level
    sLow  = mad(nz(nz <= hi), 1);        % robust spread below hi

    % Candidates:
    minFracHi = 0.70;    % try 0.65–0.75
    kMAD      = 2.0;     % try 1.5–2.5

    cand1 = minFracHi * hi;
    cand2 = base + kMAD * sLow;

    thrDyn = max(cand1, cand2);          % pick the more conservative
    thrDyn = min(thrDyn, 0.98*hi);       % don't exceed the very top
end

above = sig >= thrDyn;

% bridge small dips
gap = 40;
above = imclose(above, ones(gap,1));

logMsg(sprintf('%s: plateau thr=%.3f | hi=%.3f base=%.3f MAD=%.3f (take=max(%.2f*hi, base+%.1f*MAD))', ...
    viewName, thrDyn, hi, base, sLow, minFracHi, kMAD), true, fid);

d = diff([0; above; 0]);
S = find(d==1);
E = find(d==-1) - 1;

% keep only long-enough plateaus
keep = (E - S + 1) >= plateauMinDur;
S = S(keep); E = E(keep);

% plateau area proxy and anchor = START
nP = numel(S);
area_pl  = zeros(nP,1);
idx_pl   = zeros(nP,1);
for k=1:nP
    seg = sig(S(k):E(k));
    area_pl(k) = sum(seg);
    idx_pl(k)  = S(k);
end
areaZ_pl = zscore_robust(area_pl);

% -------- unify for "both" mode --------
idx_all_raw   = [locs(:); idx_pl(:)];
area_all_raw  = [area_pk(:); area_pl(:)];
type_all      = [ones(numel(locs),1); 2*ones(numel(idx_pl),1)];
areaZ_all     = zscore_robust(area_all_raw);

% -------- package --------
events.sig = sig;

events.peak.idx   = locs(:);
events.peak.area  = area_pk(:);
events.peak.areaZ = areaZ_pk(:);

events.plat.se       = [S(:) E(:)];
events.plat.idxStart = idx_pl(:);
events.plat.area     = area_pl(:);
events.plat.areaZ    = areaZ_pl(:);
events.plat.thresh   = thrDyn;

[events.idx, sortOrder] = sort(idx_all_raw(:));
events.area  = area_all_raw(sortOrder);
events.areaZ = areaZ_all(sortOrder);
events.type  = type_all(sortOrder);

% effective thresholds for logging
plEff.plateauThresh = thrDyn;
plEff.plateauMinDur = plateauMinDur;

end

% ---- utils ----
function z = zscore_robust(x)
x = x(:);
if isempty(x), z = x; return; end
medx = median(x,'omitnan');
madx = mad(x,1);
z = (x - medx) ./ max(madx, eps);
end


%% Classify reaches manually

function classifyReachesCallback(fig)
handles = guidata(fig);


handles.msgLabel.Text = 'Starting Classification Pipeline in FIJI.';
handles.msgLabel.FontColor = handles.colors.statusPending;
drawnow;

fijiPath = 'C:\Fiji.app\fiji-win64.exe';
dataDir  = handles.baseDir;

% Double-escape backslashes for the dir argument
dirArg   = sprintf('dir=%s', strrep(dataDir, '\', '\\'));

% Build Fiji system call
cmd = sprintf('"%s" --ij2 --run "SPG_ClassifyReaches " "%s"', fijiPath, dirArg);

system(cmd);

handles.msgLabel.Text = 'Classification pipeline shutdown. After classifying all, continue with analysis';
handles.msgLabel.FontColor = handles.colors.successColor;
drawnow;
return
end


%% Calibration
function calibratePoleByClick(fig)
% CALIBRATEPOLEBYCLICK Interactively calibrates pole widths in side/front videos.
% Assumes known pole width = 12.7 mm and computes px, mm/px, and mm.
% Saves results to pole_calibration.mat

% --- Setup ---
handles = guidata(fig);
baseDir = handles.baseDir;
outDir = handles.outDir;
pairs = handles.pairs;
known_mm = 12.7; % Known physical pole width in mm
calibrationFile = fullfile(outDir, 'pole_calibration.mat');

if isfile(calibrationFile)
    load(calibrationFile, 'poleCal');
else
    poleCal = struct();
end

% --- Loop through animals ---
for idx = 1:numel(pairs)
    coreID = pairs(idx).coreID;
    fprintf('\n📏 Calibrating pole width for %s...\n', coreID);
    sideVid = pairs(idx).sideVideo;
    frontVid = pairs(idx).frontVideo;

    data = struct();

    % === SIDE VIDEO ===
    if isfile(sideVid)
        v = VideoReader(sideVid);
        frameNum = 50; %load frame nr 50 in case video starts blacl
        for i = 1:frameNum
            f = readFrame(v);
        end
        figure('Name', sprintf('%s - SIDE View', coreID));
        imshow(f); axis on; hold on;
        title('SIDE view: Click LEFT and RIGHT edges of pole');

        [x, y] = getTwoClicks();
        px_width = abs(x(2) - x(1));
        mm_per_pixel = known_mm / px_width;

        data.side.px_width = px_width;
        data.side.mm_per_pixel = mm_per_pixel;
        data.side.mm_width = px_width * mm_per_pixel;

        close;
    else
        warning('⚠️ Side video for %s not found.', coreID);
    end

    % === FRONT VIDEO ===
    if isfile(frontVid)
        v = VideoReader(frontVid);
        f = readFrame(v);
        figure('Name', sprintf('%s - FRONT View', coreID));
        imshow(f); axis on; hold on;
        title('FRONT view: Click LEFT and RIGHT edges of pole');

        [x, y] = getTwoClicks();
        px_width = abs(x(2) - x(1));
        mm_per_pixel = known_mm / px_width;

        data.front.px_width = px_width;
        data.front.mm_per_pixel = mm_per_pixel;
        data.front.mm_width = px_width * mm_per_pixel;

        close;
    else
        warning('⚠️ Front video for %s not found.', coreID);
    end

    field = matlab.lang.makeValidName(coreID);
    poleCal.(field) = data;

    save(calibrationFile, 'poleCal');
    side_px = NaN;
    front_px = NaN;

    if isfield(data, 'side') && isfield(data.side, 'px_width')
        side_px = data.side.px_width;
    end
    if isfield(data, 'front') && isfield(data.front, 'px_width')
        front_px = data.front.px_width;
    end

    fprintf('✅ Side: %.1f px | Front: %.1f px\n', side_px, front_px);

end

% --- Finalize ---
handles.msgLabel.Text = 'Pole calibration completed!';
handles.msgLabel.FontColor = handles.colors.successColor;
guidata(fig, handles);
end

% === Helper: Clicks with feedback ===
function [x, y] = getTwoClicks()
x = zeros(1,2); y = zeros(1,2);
for i = 1:2
    [x(i), y(i)] = ginput(1);
    plot(x(i), y(i), 'ro', 'MarkerSize', 10, 'LineWidth', 2);
    drawnow;
end
plot(x, y, 'r--', 'LineWidth', 2); % Connect clicks
pause(0.2);
end

%% -------- Analysis

%interpolate outliers from trajectory (not many but some) - if in
%completely different space! - average trace needs some more thinking
%about...

function analyzeReachesCallback(fig)
handles = guidata(fig);
outDir = handles.outDir;
pairs = handles.pairs;
handles.msgLabel.Text = 'Starting analysis...';
handles.msgLabel.FontColor = handles.colors.statusPending;
drawnow;

% --- Exclusions ---
excludeFile = fullfile(outDir,'exclude_table.csv');
if isfile(excludeFile)
    T_excl = readtable(excludeFile);

    % Only keep rows marked with Exclude == 1
    if any(strcmpi(T_excl.Properties.VariableNames,'Exclude'))
        excludeCoreIDs = T_excl.CoreID(T_excl.Exclude == 1);
    else
        warning('Exclude column not found, excluding none.');
        excludeCoreIDs = {};
    end

elseif isfile(fullfile(outDir,'exclude_table.mat'))
    S_excl = load(fullfile(outDir,'exclude_table.mat'));
    T_excl = S_excl.exclude_table;

    if any(strcmpi(T_excl.Properties.VariableNames,'Exclude'))
        excludeCoreIDs = T_excl.CoreID(T_excl.Exclude == 1);
    else
        warning('Exclude column not found in MAT, excluding none.');
        excludeCoreIDs = {};
    end

else
    warning('No exclusion file found, not excluding any animals.');
    excludeCoreIDs = {};
end


animalData = struct([]);

%% ----------- Pass 1: Build animalData & collect global info ----------
fprintf('[%s] Starting Pass 1 (building animalData)\n', datestr(now,'HH:MM:SS.FFF'));

% Temporary storage (parfor-safe)
animalDataCell = cell(numel(pairs),1);
allGroupsScan   = cell(numel(pairs),1);
allTestDaysScan = cell(numel(pairs),1);
allLabelsCollect= cell(numel(pairs),1);

NewLabelMap = containers.Map( ...
    string({ "Attempt - No Touch", "Miss - Targeting", "Miss - Knock", ...
             "Error - During Grasp", "Error - Retrieve Failure", "Success After Many" }), ...
    string({ "Error - Approach", "Error - Approach", "Error - Approach", ...
             "Error - Grasp", "Error - Retrieval", "Success" }));


parfor i = 1:numel(pairs)
    coreID = pairs(i).coreID;

    % Skip excluded IDs
    if ismember(coreID, excludeCoreIDs)
        fprintf('Excluding %s\n', coreID);
        continue;
    end

    % --- Load reachLabels.csv ---
    labelFile = fullfile(outDir, sprintf('%s_reachLabels.csv', coreID));
    if ~isfile(labelFile)
        fprintf('Missing reachLabels for %s\n', coreID);
        continue;
    end
    T_labels = readtable(labelFile);
    T_labels.Label = strrep(T_labels.Label,"–","-");

    if ~ismember('Label', T_labels.Properties.VariableNames)
        warning('File %s missing Label column, skipping.', coreID);
        continue;
    end

    % rename labels to new error approach / grasp / retrieve
    oldLabels = string(T_labels.Label);
    newLabels = oldLabels;
    
    for k = 1:numel(oldLabels)
        if NewLabelMap.isKey(oldLabels(k))
            newLabels(k) = NewLabelMap(oldLabels(k));
        end
    end
    
    T_labels.Label = newLabels;

    % --- Exclude unwanted labels ---
    excludeLabels = ["Skip (Not a Reach)", "Attempt - No Pellet", "Unknown / Hard to Say"];
    T_labels(ismember(string(T_labels.Label), excludeLabels), :) = [];

    % --- DLC load ---
    dlc_side  = readDLCcsv(pairs(i).sideVideo,'Side');
    dlc_front = readDLCcsv(pairs(i).frontVideo,'Front');
    if isempty(dlc_side) || isempty(dlc_front)
        warning('Missing DLC data for %s', coreID);
        continue;
    end

    % --- Calibration ---
    poleCalibrationStruct = load(fullfile(outDir,'pole_calibration.mat'));
    poleCalibrationStruct = poleCalibrationStruct.poleCal;
    coreID_field = strrep(coreID,'-','_');
    if ~isfield(poleCalibrationStruct, coreID_field)
        warning('No pole calibration for %s', coreID);
        continue;
    end
    poleCalibration = poleCalibrationStruct.(coreID_field);

    % Side calibration
    mmPerPixel_side = poleCalibration.side.mm_per_pixel;
    varNames = dlc_side.Properties.VariableNames;
    xyCols = contains(varNames,'_x') | contains(varNames,'_y');
    for c = find(xyCols)
        dlc_side.(varNames{c}) = dlc_side.(varNames{c}) * mmPerPixel_side;
    end

    % Front calibration (fallback to side)
    if isfield(poleCalibration,'front') && isfield(poleCalibration.front,'mm_per_pixel')
        mmPerPixel_front = poleCalibration.front.mm_per_pixel;
    else
        mmPerPixel_front = mmPerPixel_side;
    end
    varNamesF = dlc_front.Properties.VariableNames;
    xyColsF = contains(varNamesF,'_x') | contains(varNamesF,'_y');
    for c = find(xyColsF)
        dlc_front.(varNamesF{c}) = dlc_front.(varNamesF{c}) * mmPerPixel_front;
    end

    % --- Parse metadata ---
    [group, animal, test_day] = parseCoreID(coreID);

    % --- Build struct ---
    s = struct( ...
        'coreID',     coreID, ...
        'group',      group, ...
        'animal',     animal, ...
        'test_day',   test_day, ...
        'reaches',    T_labels, ...
        'offsetVals', T_labels.Offset, ...
        'dlc_side',   dlc_side, ...
        'dlc_front',  dlc_front ...
    );

    % Save into cell
    animalDataCell{i} = s;
    allGroupsScan{i}    = group;
    allTestDaysScan{i}  = test_day;
    allLabelsCollect{i} = unique(string(T_labels.Label));
end

% Collapse cells → struct array
animalData = [animalDataCell{~cellfun('isempty',animalDataCell)}];
allGroupsScan   = allGroupsScan(~cellfun('isempty',allGroupsScan));
allTestDaysScan = allTestDaysScan(~cellfun('isempty',allTestDaysScan));
allLabelsCollect= vertcat(allLabelsCollect{~cellfun('isempty',allLabelsCollect)});

% Unique lists
uniqueGroups       = unique(allGroupsScan,'stable');
uniqueTestDays     = unique(allTestDaysScan,'stable');
uniqueLabelsGlobal = unique(allLabelsCollect,'stable');

% Precompute fast maps for lookups
groupMap = containers.Map(uniqueGroups, 1:numel(uniqueGroups));
dayMap   = containers.Map(uniqueTestDays, 1:numel(uniqueTestDays));

fprintf('[%s] Pass 1 complete: %d animals retained\n', ...
    datestr(now,'HH:MM:SS.FFF'), numel(animalData));

nGroups = numel(uniqueGroups);
nTestdays = numel(uniqueTestDays);
nLabels = numel(uniqueLabelsGlobal);

% ---------- Pass 2: Analyze and accumulate heatmaps ----------

for i = 1:numel(animalData)
    coreID   = animalData(i).coreID;
    group    = animalData(i).group;
    animal   = animalData(i).animal;
    test_day = animalData(i).test_day;
    coreID = animalData(i).coreID;
    reaches = animalData(i).reaches;
    dlc_side = animalData(i).dlc_side;
    dlc_front = animalData(i).dlc_front;
    offsets = animalData(i).offsetVals;

    % Thresholds
    likelihoodThresh_side  = 0.3;
    likelihoodThresh_front = 0.2;

    % --- progress bar update ---
    nBlocks = 20;
    progress = i / numel(animalData);
    filledBlocks = round(progress * nBlocks);
    barStr = [repmat('█', 1, filledBlocks), repmat('░', 1, nBlocks - filledBlocks)];
    handles.msgLabel.Text = sprintf('Computing trajectories for animal %d of %d [%s]...', ...
        i, numel(animalData), barStr);
    handles.msgLabel.FontColor = handles.colors.statusPending;
    drawnow;

    % Storage for this animal
    perReachRows   = table();    % merged per-reach metrics
    allFields      = {};         % running superset of metrics
    perReachTrajSide  = struct('coreID', {}, 'reachID', {}, 'label', {}, 'broadLabel', {}, 'traj', {});
    perReachTrajFront = struct('coreID', {}, 'reachID', {}, 'label', {}, 'broadLabel', {}, 'traj', {});

    failedReaches  = table('Size',[0 5], ...
        'VariableTypes', {'string','double','string','string','string'}, ...
        'VariableNames', {'coreID','reachID','label','view','reason'});

    % Skip animals with too few reaches
    if height(reaches) < 2
        warning('Skipping %s: not enough reaches (%d).', coreID, height(reaches));
        continue;
    end

for r = 1:height(reaches)
        reachID = reaches.ReachIndex(r);
        label   = string(reaches.Label(r));

        % --- Broad label grouping (success vs error only) ---
        if startsWith(lower(label), "success")
            broadLabel = "success";
        else
            broadLabel = "error";
        end

        % --- SIDE ---
        [sideMetrics, sideTraj, failReason_side, sStartRef, sEndRef] = ...
            analyzeReach_Side(coreID, reaches(r,:), dlc_side, likelihoodThresh_side, 'tip', outDir);

        if strlength(failReason_side) > 0
            failedReaches = [failedReaches; {coreID, reachID, label, "side", failReason_side}];
        end


        % --- FRONT ---
        [frontMetrics, frontTraj, failReason_front] = ...
            analyzeReach_Front(coreID, reaches(r,:), dlc_front, offsets(r), likelihoodThresh_front, sStartRef, sEndRef);

        if strlength(failReason_front) > 0
            failedReaches = [failedReaches; {coreID, reachID, label, "front", failReason_front}];
        end
        %save CSV for traj in R

        % Paths to source CSVs (handy in R)
        sideCSVPath  = pairs(i).sideVideo;   % absolute or relative, as stored
        frontCSVPath = pairs(i).frontVideo;
        labelsCSVPath = fullfile(outDir, sprintf('%s_reachLabels.csv', coreID));
        
        % Save per-reach smoothed trajectories and remember the file paths
        sideTrajPath  = "";
        frontTrajPath = "";
        if ~isempty(sideTraj) && ~isempty(fieldnames(sideTraj))
            sideTrajPath = saveTrajectoryCSV(sideTraj, coreID, 'Side', outDir);
        end
        if ~isempty(frontTraj) && ~isempty(fieldnames(frontTraj))
            frontTrajPath = saveTrajectoryCSV(frontTraj, coreID, 'Front', outDir);
        end
        
        % derive start/end frames (cropped) for convenience columns
        sideStartFrame  = NaN; sideEndFrame  = NaN;
        frontStartFrame = NaN; frontEndFrame = NaN;
        if ~isempty(sideTraj) && isfield(sideTraj,'frames') && ~isempty(sideTraj.frames)
            sideStartFrame = sideTraj.frames(1);
            sideEndFrame   = sideTraj.frames(end);
        end
        if ~isempty(frontTraj) && isfield(frontTraj,'frames') && ~isempty(frontTraj.frames)
            frontStartFrame = frontTraj.frames(1);
            frontEndFrame   = frontTraj.frames(end);
        end
        

       % --- Merge metrics into one table row ---
    metaStruct = struct( ...
        'coreID', coreID, ...
        'group', group, ...
        'animal', animal, ...
        'test_day', test_day, ...
        'label', label, ...
        'broadLabel', broadLabel, ...
        'reachID', reachID, ...
        'sideStartFrame',  sideStartFrame, ...
    'sideEndFrame',    sideEndFrame, ...
    'frontStartFrame', frontStartFrame, ...
    'frontEndFrame',   frontEndFrame, ...
    'sideTrajCSV',     string(sideTrajPath), ...
    'frontTrajCSV',    string(frontTrajPath), ...
    'sideCSVPath',     string(sideCSVPath), ...
    'frontCSVPath',    string(frontCSVPath), ...
    'reachLabelsCSV',  string(labelsCSVPath));

    [perReachRows, allFields] = joinStructsFlexible( ...
        perReachRows, sideMetrics, frontMetrics, metaStruct, allFields);


    if ~isempty(sideTraj) && ~isempty(fieldnames(sideTraj))
            perReachTrajSide(end+1) = struct( ...
                'coreID', coreID, ...
                'reachID', reachID, ...
                'label', label, ...
                'broadLabel', broadLabel, ...
                'traj', sideTraj ...
            );
        end

        if ~isempty(frontTraj) && ~isempty(fieldnames(frontTraj))
            perReachTrajFront(end+1) = struct( ...
                'coreID', coreID, ...
                'reachID', reachID, ...
                'label', label, ...
                'broadLabel', broadLabel, ...
                'traj', frontTraj ...
            );
        end


       %  --- debug ---
       if strlength(failReason_side) > 0
        fprintf('[DEBUG] %s Reach %d (%s): side fail (%s)\n', ...
            coreID, reachID, label, failReason_side);
        end
        if strlength(failReason_front) > 0
            fprintf('[DEBUG] %s Reach %d (%s): front fail (%s)\n', ...
                coreID, reachID, label, failReason_front);
        end

end

    % ---- Save per animal ----
    csvDir = fullfile(outDir,'CSV');
    if ~exist(csvDir,'dir'), mkdir(csvDir); end
    writetable(perReachRows, fullfile(csvDir, sprintf('Params_%s.csv', coreID)));

    matDir = fullfile(outDir,'MAT');
    if ~exist(matDir,'dir'), mkdir(matDir); end

    results = struct( ...
        'coreID', coreID, ...
        'group', group, ...
        'animal', animal, ...
        'test_day', test_day, ...
        'perReachRows', perReachRows, ...
        'failedReaches', failedReaches, ...
        'side', struct( ...
            'metrics', perReachRows(:, contains(perReachRows.Properties.VariableNames,'side','IgnoreCase',true)), ...
            'trajectories', perReachTrajSide ...
        ), ...
        'front', struct( ...
            'metrics', perReachRows(:, contains(perReachRows.Properties.VariableNames,'front','IgnoreCase',true)), ...
            'trajectories', perReachTrajFront ...
        ) ...
    );

save(fullfile(matDir, sprintf('%s_results.mat', coreID)), 'results','-v7.3');

fprintf('[%s] Finished %s (%d reaches, %d fails)\n', ...
    datestr(now,'HH:MM:SS.FFF'), coreID, height(reaches), height(failedReaches));

end

handles.msgLabel.Text = sprintf('Computation done and saved, moving on to visualization');
handles.msgLabel.FontColor = handles.colors.statusPending;
drawnow;

%% Pass 3 - Trajectory and Heatmap

% -------- Load MAT files --------
matDir = fullfile(outDir,'MAT');
figDir = fullfile(outDir,'FIG');
if ~exist(figDir,'dir'), mkdir(figDir); end

matFiles = dir(fullfile(matDir,'*_results.mat'));
if isempty(matFiles)
    error('No *_results.mat files found in %s',matDir);
end

allResults = cell(numel(matFiles),1);
for i = 1:numel(matFiles)
    tmp = load(fullfile(matDir,matFiles(i).name));
    if isfield(tmp,'results')
        allResults{i} = tmp.results;
    else
        warning('File %s missing results struct, skipping',matFiles(i).name);
    end
end
allResults = [allResults{~cellfun('isempty',allResults)}];
unifiedParams = vertcat(allResults.perReachRows);  % now consistent

% -------- Merge parameter tables into one Masterfile--------
csvDir = fullfile(outDir,'CSV');
writetable(unifiedParams, fullfile(csvDir,'All_Params.csv'));

handles.msgLabel.Text = sprintf('Master Parameter table (Front/Side) saved in /CSV.%sProceeding with visualization', newline);
handles.msgLabel.FontColor = handles.colors.statusPending;
drawnow;

% Collect metadata
allGroups   = string({allResults.group});
allDays     = string({allResults.test_day});
allCoreIDs  = string({allResults.coreID});

uniqueGroups       = unique(allGroups,'stable');
uniqueDays         = unique(allDays,'stable');
uniqueLabelsGlobal = unique(unifiedParams.label,'stable');

% --- enforce custom ordering (optional) --- (I dont think this is being
% used in the functions but thats ok)
desiredLabelOrder = ["Success","Error - Approach","Error - Grasp", "Error - Retrieval"];
desiredDayOrder   = ["Baseline","Drug","Washout"];

% Reorder groups
[~, idxG] = ismember(desiredLabelOrder, uniqueLabelsGlobal);
idxG = idxG(idxG>0);  % keep only those that exist
uniqueLabelsGlobal = uniqueLabelsGlobal(idxG);

% Reorder days
[~, idxD] = ismember(desiredDayOrder, uniqueDays);
idxD = idxD(idxD>0);  % keep only those that exist
uniqueDays = uniqueTestDays(idxD);
% 
% % -------- Per animal plots --------
% for i = 1:numel(allResults)
%     R = allResults(i);
%     coreID = R.coreID;
% 
%     % SIDE trajectories per label
%     if isfield(R,'side') && ~isempty(R.side.trajectories)
%         plotPerAnimalTraj(R.side.trajectories,coreID,'Side',figDir, 'label');
%         plotPerAnimalHeatmap(R.side.trajectories,coreID,'Side',figDir, 'label');
%         plotPerAnimalTraj(R.side.trajectories,coreID,'Side',figDir, 'broadLabel');
%         plotPerAnimalHeatmap(R.side.trajectories,coreID,'Side',figDir, 'broadLabel');
%     end
% 
%     % FRONT trajectories per label
%     if isfield(R,'front') && ~isempty(R.front.trajectories)
%         plotPerAnimalTraj(R.front.trajectories,coreID,'Front',figDir, 'label');
%         plotPerAnimalHeatmap(R.front.trajectories,coreID,'Front',figDir, 'label');
%         plotPerAnimalTraj(R.front.trajectories,coreID,'Front',figDir, 'broadLabel');
%         plotPerAnimalHeatmap(R.front.trajectories,coreID,'Front',figDir, 'broadLabel');
%     end
% end
% 
% handles.msgLabel.Text = sprintf([ ...
%     'Per-animal trajectories and heatmaps complete.' newline ...
%     'Proceeding with group-level visualizations...' ]);
% handles.msgLabel.FontColor = handles.colors.statusPending;
% drawnow;

% -------- Group-level heatmaps (side + front) --------
for g = 1:numel(uniqueGroups)
    grpName = uniqueGroups(g);
    grpMask = strcmp(allGroups,grpName);
    Rgrp = allResults(grpMask);

    if ~isempty(Rgrp)
        % plotGroupHeatmaps(Rgrp, grpName, 'Side', figDir, 'label');
        % plotGroupHeatmaps(Rgrp, grpName, 'Side', figDir, 'broadLabel');
        % plotGroupHeatmaps(Rgrp, grpName, 'Front', figDir,'label');
        % plotGroupHeatmaps(Rgrp, grpName, 'Front', figDir,'broadLabel');
        % plotGroupTraj(Rgrp, grpName, 'Side', figDir, 'label');
        % plotGroupTraj(Rgrp, grpName, 'Side', figDir, 'broadLabel');
        % plotGroupTraj(Rgrp, grpName, 'Front', figDir, 'label');
        % plotGroupTraj(Rgrp, grpName, 'Front', figDir, 'broadLabel');

    end
end

handles.msgLabel.Text = sprintf([ ...
    'Group-level heatmaps complete.' newline ...
    'Proceeding with global label × group × day visualizations...' ]);
handles.msgLabel.FontColor = handles.colors.statusPending;
drawnow;

% -------- Global heatmaps grid (rows=test_day, cols=group) --------
allParams = vertcat(allResults.perReachRows);
uniqueLabelsGlobal = unique(allParams.label, 'stable');
uniqueBroadGlobal  = unique(allParams.broadLabel, 'stable');

% % label-level
% for l = uniqueLabelsGlobal'
%     plotGlobalLabelHeatmaps(allResults, uniqueGroups, uniqueDays, l, 'Side',  figDir, 'label');
%     plotGlobalLabelHeatmaps(allResults, uniqueGroups, uniqueDays, l, 'Front', figDir, 'label');
% end
% 
% 
% % broadLabel-level
% for bl = uniqueBroadGlobal'
%     plotGlobalLabelHeatmaps(allResults, uniqueGroups, uniqueDays, bl, 'Side',  figDir, 'broadLabel');
%     plotGlobalLabelHeatmaps(allResults, uniqueGroups, uniqueDays, bl, 'Front', figDir, 'broadLabel');
% end

% label-level
plotDifferenceHeatmaps(allResults, uniqueGroups, uniqueDays, uniqueLabelsGlobal, [], 'Side', figDir, 'label');
plotDifferenceHeatmaps(allResults, uniqueGroups, uniqueDays, uniqueLabelsGlobal, [], 'Front', figDir, 'label');

% % broadLabel-level
% plotDifferenceHeatmaps(allResults, uniqueGroups, uniqueDays, [], uniqueBroadGlobal, 'Side', figDir, 'broadLabel');
% plotDifferenceHeatmaps(allResults, uniqueGroups, uniqueDays, [], uniqueBroadGlobal, 'Front', figDir, 'broadLabel');
% 
% 
% %over all reaches
% plotGlobalAndDifferenceHeatmaps(allResults, uniqueGroups, 'Side', figDir);
% plotGlobalAndDifferenceHeatmaps(allResults, uniqueGroups, 'Front', figDir);

handles.msgLabel.Text = '✅ Kinematic analysis complete, check output files in CSV and FIG folder.';
handles.msgLabel.FontColor = handles.colors.successColor;
guidata(fig,handles);

end

function [perReachRows, allFields] = joinStructsFlexible(perReachRows, sideMetrics, frontMetrics, metaStruct, allFields)

    % ---- Step 1: merge metrics ----
    unified = sideMetrics;
    if ~isempty(frontMetrics)
        f2 = fieldnames(frontMetrics);
        for k = 1:numel(f2)
            unified.(f2{k}) = frontMetrics.(f2{k});
        end
    end

    % ---- Step 2: add metadata ----
    unified.coreID     = string(metaStruct.coreID);
    unified.group      = string(metaStruct.group);
    unified.animal     = string(metaStruct.animal);
    unified.test_day    = string(metaStruct.test_day);
    unified.label      = string(metaStruct.label);
    unified.broadLabel = string(metaStruct.broadLabel);
    unified.reachID    = double(metaStruct.reachID);

    % ---- Step 3: update running field list ----
    fn = fieldnames(unified);
    allFields = union(allFields, fn, 'stable');

    % ---- Step 4: patch unified struct with NaN where needed ----
    for k = 1:numel(allFields)
        fld = allFields{k};
        if ~isfield(unified,fld)
            unified.(fld) = NaN;
        end
    end

    % ---- Step 5: convert to table ----
    rowT = struct2table(unified);

    % ---- Step 6: harmonize existing table with new row ----
    if ~isempty(perReachRows)
        % Add missing vars to existing table
        missingInExisting = setdiff(rowT.Properties.VariableNames, perReachRows.Properties.VariableNames);
        for m = missingInExisting
            perReachRows.(m{1}) = NaN(height(perReachRows),1);
        end

        % Add missing vars to new row
        missingInNew = setdiff(perReachRows.Properties.VariableNames, rowT.Properties.VariableNames);
        for m = missingInNew
            rowT.(m{1}) = NaN(height(rowT),1);
        end

        % Reorder rowT to match perReachRows
        rowT = rowT(:, perReachRows.Properties.VariableNames);
    end

    % ---- Step 7: append ----
    perReachRows = [perReachRows; rowT];
end


function [metrics, traj, failReason, sideStartRefined, sideEndRefined] = ...
    analyzeReach_Side(coreID, reachRow, dlc_side, likelihoodThresh, pawPart, outDir)


if nargin < 5 || isempty(pawPart), pawPart = 'tip'; end
if nargin < 6, outDir = ''; end

metrics = struct();
traj    = struct();
failReason = "";
sideStartRefined = NaN; 
sideEndRefined   = NaN;

% ----------- basic guards -----------
if isempty(reachRow) || ~istable(reachRow) || height(reachRow)~=1
    failReason = "reachRow must be a single table row";
    return;
end
needVars = {'SideStart','SideEnd','Label'};
if ~all(ismember(needVars, reachRow.Properties.VariableNames))
    failReason = "reachRow missing SideStart/SideEnd/Label";
    return;
end

startF = double(reachRow.SideStart);
endF   = double(reachRow.SideEnd);

if isnan(startF) || isnan(endF) || endF <= startF
    failReason = "invalid SideStart/SideEnd window";
    return;
end

% normalize label (fix en-dash artifact & make string)
label = string(reachRow.Label);

% figure out reachID field
if ismember('ReachID', reachRow.Properties.VariableNames)
    reachID = reachRow.ReachID;
elseif ismember('ReachIndex', reachRow.Properties.VariableNames)
    reachID = reachRow.ReachIndex;
else
    reachID = startF; % fallback (not ideal, but stable)
end

% --- Paw selection ---
switch lower(pawPart)
    case 'center'
        xAll = dlc_side.paw_center__x;
        yAll = dlc_side.paw_center__y;
        likelihoods = dlc_side.paw_center__likelihood;
    case 'tip'
        xAll = dlc_side.paw_tip__x;
        yAll = dlc_side.paw_tip__y;
        likelihoods = dlc_side.paw_tip__likelihood;
    otherwise
        error('Unknown pawPart: choose either "center" or "tip".');
end

% likelihood filtering → NaN
xAll(likelihoods < likelihoodThresh) = NaN;
yAll(likelihoods < likelihoodThresh) = NaN;

%jumping outliers)
vel = hypot(diff(xAll), diff(yAll));
zscoreVel = (vel - mean(vel,'omitnan'))/std(vel,'omitnan');
outlierIdx = [false; abs(zscoreVel) > 5];  % mark crazy jumps
xAll(outlierIdx) = NaN;
yAll(outlierIdx) = NaN;

%filling in those gaps
maxGap = 5; % frames
xAll = fillmissing(xAll, 'linear', 'MaxGap',maxGap,'EndValues','nearest');
yAll = fillmissing(yAll, 'linear', 'MaxGap',maxGap,'EndValues','nearest');

nFrames = height(dlc_side);
frames = max(1,startF):min(endF,nFrames);
frames = frames(frames>0 & frames<=nFrames);
if isempty(frames)
    failReason = "empty clipped frame window";
    return;
end

% slit mean position (mm)
slitX = mean([mean(dlc_side.slit_bottom__x,'omitnan'), mean(dlc_side.slit_top__x,'omitnan')]);

% Parameters for segmentation
par.frame_buffer = 100; %to extend trajectory if necessary
par.rightwardVelocityThreshold = 2;
par.minSustainFrames = 3;
par.velocityStopThresh = 1;
par.windowLen = 3;
par.minPeakDistance = 40; %Only peaks at least 10 frames apart will be considered separate; closer peaks are merged.
par.minPeakProminence = 1; %A detected peak must rise at least 0.5 mm above surrounding troughs to be considered valid.
par.peakTolerance = 1.0;           % mm tolerance for equivalent peaks
par.showQCplot = false;
par.gauss_smooth = 20;
par.pelletContactTolerance = 2; 
if ~isfield(par,'plateauTol'),     par.plateauTol     = 1.0; end   % mm range above min-dist to count as plateau
if ~isfield(par,'boundarySlack'),  par.boundarySlack  = 2;   end   % +/- frames to pad the crop

% ----------- extract/crop, compute metrics -----------
try
    [xPlot, yPlot, pelletXreach, pelletYreach, slitX_norm, m, sStart, sEnd, croppedFrames] = ...
        extractReachTrajectory(frames, xAll, yAll, dlc_side, slitX, par, reachID, coreID, outDir, label);

    sideStartRefined = sStart;
    sideEndRefined   = sEnd;

    if isempty(xPlot)
        failReason = "Empty trajectory after extraction";
        return;
    end

    % Ensure required scalar fields are present (mirror your original guards)
    scalarFields = {'peakOutwardVelocity','meanOutwardVelocity','outwardMovementDuration', ...
        'initialReachAngle','y_at_1_3','y_at_2_3','y_at_pellet','corrections','pauseCount', ...
        'totalPauseDuration','retrievalDuration','peakRetrievalVelocity','meanRetrievalVelocity', ...
        'retrievalStraightness','endpoint_x','endpoint_y','timeSlitToContact_frames', ...
        'timeSlitToContact_sec','slitToPelletDistance_mm','normReachTime_s_per_mm','meanOutwardSpeed_mm_per_s', ...
        'peakAcceleration','peakDeceleration','meanAbsJerk','peakJerk','accelSignChanges', ...
        'trajectoryLength_outward','retrievalArc','retrievalReversals','reachDuration','maxHeight', ...
        'trajectoryLength','trajectoryStraightness','pathTortuosity','nPelletContactPeaks','contactDuration'};
    for f = 1:numel(scalarFields)
        fld = scalarFields{f};
        if ~isfield(m,fld) || isempty(m.(fld))
            m.(fld) = NaN;
        end
    end
    if ~isfield(m,'pelletContactPeakFrames') || ~iscell(m.pelletContactPeakFrames)
        m.pelletContactPeakFrames = {[]};
    end
    if ~isfield(m,'peakOutwardVelocityFrame'), m.peakOutwardVelocityFrame = NaN; end
    if ~isfield(m,'timeToPelletContact'),      m.timeToPelletContact      = m.timeSlitToContact_frames; end

    % ----------- build outputs -----------
    metrics = m;  % full struct from extractReachTrajectory

    traj = struct( ...
        'reachID',  reachID, ...
        'label',    label, ...
        'frames',   croppedFrames, ...
        'x',        xPlot, ...
        'y',        yPlot, ...
        'pelletX',  pelletXreach, ...
        'pelletY',  pelletYreach, ...
        'slitX_norm', slitX_norm, ...
        'sideStartRefined', sideStartRefined, ...
        'sideEndRefined',   sideEndRefined ...
    );

catch ME
    failReason = sprintf('error: %s', ME.message);
end
end

function outPath = saveTrajectoryCSV(traj, coreID, viewStr, outDir)
% Save a per-reach trajectory CSV with global frames + smoothed x/y
% Returns full file path.
    trajDir = fullfile(outDir,'CSV','Trajectories',viewStr);
    if ~exist(trajDir,'dir'), mkdir(trajDir); end
    fn = sprintf('%s_reach%04d_%s_traj.csv', coreID, round(double(traj.reachID)), lower(viewStr));
    outPath = fullfile(trajDir, fn);

    % build table: one row per sample in the cropped, smoothed trajectory
    T = table( ...
        repmat(string(coreID), numel(traj.frames), 1), ...
        repmat(double(traj.reachID), numel(traj.frames), 1), ...
        repmat(string(viewStr), numel(traj.frames), 1), ...
        traj.frames(:), ...
        traj.x(:), ...
        traj.y(:), ...
        repmat(traj.pelletX, numel(traj.frames), 1), ...
        repmat(traj.pelletY, numel(traj.frames), 1), ...
        repmat(traj.slitX_norm, numel(traj.frames), 1), ...
        'VariableNames', {'coreID','reachID','view','frame','x_mm','y_mm','pelletX_mm','pelletY_mm','slitX_norm_mm'} ...
    );

    writetable(T, outPath);
end


function [xPlot, yPlot, pelletXreach, pelletYreach, slitX_norm, metrics, sideStartFrame, sideEndFrame, croppedFrames] = ...
    extractReachTrajectory(frames, xAll, yAll, dlc_side, slitX, par, reachID, coreID, outDir, label)

nFrames = length(xAll);
sideStartFrame = NaN;
sideEndFrame   = NaN;

%% -----------------------
% PREPROCESSING
% -----------------------
extendedFrames = max(frames(1)-par.frame_buffer,1):min(frames(end)+par.frame_buffer,nFrames);
pawX = xAll(extendedFrames);
pawY = yAll(extendedFrames);
validMask = ~isnan(pawX) & ~isnan(pawY);
pawX = pawX(validMask);
pawY = pawY(validMask);
framesFiltered = extendedFrames(validMask);

if length(framesFiltered) < 10
    return;
end

% Pellet position
pelletFrames = framesFiltered(dlc_side.pellet_likelihood(framesFiltered) > 0.8);
if ~isempty(pelletFrames)
    pelletXreach = median(dlc_side.pellet_x(pelletFrames),'omitnan');
    pelletYreach = median(dlc_side.pellet_y(pelletFrames),'omitnan');
else
    pelletXreach = median(dlc_side.pellet_x(dlc_side.pellet_likelihood > 0.8),'omitnan');
    pelletYreach = median(dlc_side.pellet_y(dlc_side.pellet_likelihood > 0.8),'omitnan');
end
slitX_norm = slitX - pelletXreach;

% Normalize paw coords
pawX_norm = pawX - pelletXreach;
pawY_norm = pawY - pelletYreach;

% Smooth
if length(pawX_norm) > 5
    pawX_smooth = smoothdata(pawX_norm,'gaussian',par.gauss_smooth);
    pawY_smooth = smoothdata(pawY_norm,'gaussian',par.gauss_smooth);
else
    pawX_smooth = pawX_norm;
    pawY_smooth = pawY_norm;
end

%% -----------------------
% GLOBAL CONTACT PHASE
% -----------------------
distToPellet_global = sqrt(pawX_smooth.^2 + pawY_smooth.^2);
% -----------------------
% CONTACT PHASE (based on X beyond pellet)
% -----------------------
contactMask_global = pawX_smooth >= 0;   % paw passes pellet's x-position
contactRuns_global = bwconncomp(contactMask_global);

if contactRuns_global.NumObjects > 0
    % keep each bout separately
    pelletContactPhaseIdx_global = contactRuns_global.PixelIdxList;

    % count individual bouts
    nPeaks = contactRuns_global.NumObjects;
else
    pelletContactPhaseIdx_global = {};
    nPeaks = 0;
end

%% -----------------------
% REACH BOUNDARIES (global)
% -----------------------

if ~isempty(pelletContactPhaseIdx_global)
    % --- pick bout depending on label ---
    boutLengths = cellfun(@numel, pelletContactPhaseIdx_global);

    if strcmpi(label,'Success') || strcmpi(label,'SuccessAfterMany')
        chosenBoutIdx = numel(pelletContactPhaseIdx_global);  % last bout
    else
        chosenBoutIdx = 1;                                   % first bout
    end

    chosenBout_global = pelletContactPhaseIdx_global{chosenBoutIdx};

else
    % --- fallback: no contact bouts found ---
    [~, peakIdx] = max(pawX_smooth);
    chosenBout_global = peakIdx; % treat peak as 1-frame bout
end

% Convenience handles
firstContactIdx = chosenBout_global(1);   % start of chosen bout
searchStart     = chosenBout_global(end); % end of chosen bout

% --- slit hysteresis ---
if ~isfield(par,'slitHyst'), par.slitHyst = 0.5; end
slitLower = slitX_norm - par.slitHyst;
slitUpper = slitX_norm + par.slitHyst;
%% -----------------------
% REACH BOUNDARIES (bout-local)
% -----------------------
if ~isempty(pelletContactPhaseIdx_global)
    % --- choose bout depending on label ---
    if strcmpi(label,'Success') || strcmpi(label,'SuccessAfterMany')
        chosenIdx = numel(pelletContactPhaseIdx_global);   % last bout
    else
        chosenIdx = 1;                                     % first bout
    end
    chosenBout = pelletContactPhaseIdx_global{chosenIdx};

    firstContactIdx = chosenBout(1);
    searchStart     = chosenBout(end);

    % --- define left/right windows around chosen bout ---
    if chosenIdx > 1
        leftBound = pelletContactPhaseIdx_global{chosenIdx-1}(end);
    else
        leftBound = 1;
    end
    if chosenIdx < numel(pelletContactPhaseIdx_global)
        rightBound = pelletContactPhaseIdx_global{chosenIdx+1}(1);
    else
        rightBound = numel(pawX_smooth);
    end

else
    % --- fallback: no contact bouts at all ---
    [~, peakIdx] = max(pawX_smooth);
    chosenBout = peakIdx;
    firstContactIdx = peakIdx;
    searchStart     = peakIdx;
    leftBound  = 1;
    rightBound = numel(pawX_smooth);
end

% --- slit hysteresis thresholds ---
if ~isfield(par,'slitHyst'), par.slitHyst = 0.5; end
slitLower = slitX_norm - par.slitHyst;
slitUpper = slitX_norm + par.slitHyst;

%% Start boundary: only within [leftBound … firstContactIdx]
lastInside = find(pawX_smooth(leftBound:firstContactIdx) <= slitLower, 1, 'last');
if ~isempty(lastInside)
    firstOutside = find(pawX_smooth(leftBound-1+lastInside:firstContactIdx) >= slitUpper, 1, 'first');
    if ~isempty(firstOutside)
        slitCrossStartIdx = (leftBound-1) + lastInside + firstOutside - 1;
    else
        slitCrossStartIdx = (leftBound-1) + lastInside;
    end
else
    % fallback = local minimum in that window
    [~, relMin] = min(pawX_smooth(leftBound:firstContactIdx));
    slitCrossStartIdx = (leftBound-1) + relMin;
end

%% End boundary: only within [searchStart … rightBound]
crossBackSlit = find(pawX_smooth(searchStart:rightBound) <= slitX_norm, 1, 'first');
if ~isempty(crossBackSlit)
    reachEndIdx = searchStart + crossBackSlit - 1;
else
    % fallback = local minimum in that window
    [~, relMin] = min(pawX_smooth(searchStart:rightBound));
    reachEndIdx = searchStart + relMin - 1;
end

%% Apply slack
reachStartIdx = max(1, slitCrossStartIdx - par.boundarySlack);
reachEndIdx   = min(numel(pawX_smooth), reachEndIdx + par.boundarySlack);

%% -----------------------
% METRICS based on chosen bout
% -----------------------
metrics.nPelletContactPeaks = numel(pelletContactPhaseIdx_global);
if ~isempty(chosenBout_global)
    metrics.yAtContact      = pawY(chosenBout_global(1));
    metrics.xErrorAtContact = pawX(chosenBout_global(1));
else
    metrics.yAtContact      = NaN;
    metrics.xErrorAtContact = NaN;
end


%% -----------------------
% CROP SEGMENT
% -----------------------
reachSegment   = reachStartIdx:reachEndIdx;
xPlot = pawX_norm(reachSegment);
yPlot = pawY_norm(reachSegment);
xPlot_raw          = pawX(reachSegment);
yPlot_raw          = pawY(reachSegment);
croppedFrames  = framesFiltered(reachSegment);

if numel(xPlot) < 3
    [xPlot,yPlot,pelletXreach,pelletYreach,slitX_norm,metrics] = deal([]);
    return;
end

sideStartFrame = croppedFrames(1);
sideEndFrame   = croppedFrames(end);

%% -----------------------
% CROPPED CONTACT
% -----------------------
distToPellet_crop = sqrt(xPlot.^2 + yPlot.^2);
contactMask_crop  = distToPellet_crop <= par.pelletContactTolerance;
contactRuns_crop  = bwconncomp(contactMask_crop);

if contactRuns_crop.NumObjects > 0
    firstContactCrop = contactRuns_crop.PixelIdxList{1}(1);
    lastContactCrop  = contactRuns_crop.PixelIdxList{end}(end);
    pelletContactPhaseIdx = firstContactCrop:lastContactCrop;
    
    % store the peak frames (e.g. first frame of each bout)
    peakFrames = cellfun(@(idxs) idxs(1), contactRuns_crop.PixelIdxList);
    metrics.pelletContactPeakFrames = {peakFrames};   % always a cell
else
    pelletContactPhaseIdx = [];
    metrics.pelletContactPeakFrames = {[]};           % still a cell
end

%% -----------------------
% ROBUST ENDPOINT (max X within chosen bout; de-spiked)
% -----------------------
% Work on pellet-centered cropped X
xForArgmax = xPlot;
if ~isfield(par,'endpointSmoothWin'), par.endpointSmoothWin = 5; end
if numel(xForArgmax) >= par.endpointSmoothWin && par.endpointSmoothWin > 1
    xForArgmax = movmedian(xForArgmax, par.endpointSmoothWin);
end

% Simply take the global max X in the cropped range
[~, relIdx] = max(xForArgmax);
endpointIdx = relIdx;   % index into cropped arrays

metrics.endpoint_x = xPlot(endpointIdx);
metrics.endpoint_y = yPlot(endpointIdx);


%% -----------------------
% SLIT → CONTACT TIMING
% -----------------------
slitStartInCropped = max(1, min(slitCrossStartIdx - reachStartIdx + 1, numel(xPlot)));
if ~isempty(pelletContactPhaseIdx)
    contactIdx = pelletContactPhaseIdx(1);   % first frame of chosen band
else
    contactIdx = slitStartInCropped;         % fallback
end
metrics.timeSlitToContact_frames = max(0, contactIdx - slitStartInCropped);

metrics.slitToPelletDistance_mm = abs(slitX_norm);
if isfield(par,'fps') && par.fps > 0
    metrics.timeSlitToContact_sec   = metrics.timeSlitToContact_frames / par.fps;
    if metrics.slitToPelletDistance_mm > 0
        metrics.normReachTime_s_per_mm   = metrics.timeSlitToContact_sec / metrics.slitToPelletDistance_mm;
        metrics.meanOutwardSpeed_mm_per_s = metrics.slitToPelletDistance_mm / metrics.timeSlitToContact_sec;
    else
        metrics.normReachTime_s_per_mm   = NaN;
        metrics.meanOutwardSpeed_mm_per_s = NaN;
    end
else
    metrics.timeSlitToContact_sec   = NaN;
    metrics.normReachTime_s_per_mm  = NaN;
    metrics.meanOutwardSpeed_mm_per_s = NaN;
end

%% -----------------------
% QC PLOT
% -----------------------
if isfield(par,'showQCplot') && par.showQCplot
    figQC = figure('Visible','off', ...
                   'Name', sprintf('QC Reach %s - %d [%s]', coreID, reachID, label), ...
                   'Color','w','Position',[100 100 1200 500]); 
    hold on;

    % Trajectory colored by distance
    cmap = flipud(jet(256));
    normDist = (distToPellet_global - min(distToPellet_global)) / ...
               (max(distToPellet_global) - min(distToPellet_global) + eps);
    for i = 1:(numel(framesFiltered)-1)
        cIdx = max(1,min(256,round(normDist(i)*255)+1));
        plot(framesFiltered(i:i+1), pawX_smooth(i:i+1), ...
             'Color', cmap(cIdx,:), 'LineWidth',2,'HandleVisibility','off');
    end


    % Overlay raw pawX (gray, thin)
    plot(framesFiltered, pawX_norm, 'Color',[0.5 0.5 0.5 0.6], ...
     'LineWidth',1, 'DisplayName','Raw pawX (norm)');

    % Colorbar
    cb = colorbar; 
    caxis([0 max(distToPellet_global)]);
    ylabel(cb,'Distance to pellet (mm)');
    legend('show');

    % Y-limits
    ylo = min(pawX_smooth)-5; 
    yhi = max(pawX_smooth)+5;

    % --- Shade ALL contact bouts (global detection) ---
    for r = 1:contactRuns_global.NumObjects
        boutIdx = contactRuns_global.PixelIdxList{r};
        x0 = framesFiltered(boutIdx(1));
        x1 = framesFiltered(boutIdx(end));
        patch([x0 x1 x1 x0], [ylo ylo yhi yhi], [0.2 0.8 0.2], ...
              'FaceAlpha',0.2,'EdgeColor','none','HandleVisibility','off');
    end

    % --- Shade the CHOSEN contact bout (global -> full green band) ---
    if ~isempty(chosenBout_global)
        x0 = framesFiltered(chosenBout_global(1));
        x1 = framesFiltered(chosenBout_global(end));
        patch([x0 x1 x1 x0], [ylo ylo yhi yhi], [0.2 0.2 0.9], ...
              'FaceAlpha',0.25,'EdgeColor','none','DisplayName','Chosen contact');
    end
                
    % --- Endpoint marker (in cropped indices) ---
    plot(croppedFrames(endpointIdx), xPlot(endpointIdx), 'ro', ...
         'MarkerFaceColor','r','DisplayName','Endpoint');

    % Boundaries
    xline(framesFiltered(reachStartIdx),'--m','LineWidth',1.75,'DisplayName','Slit start');
    xline(framesFiltered(reachEndIdx),'--r','LineWidth',1.75,'DisplayName','Retrieval end');
    yline(0,'-k','LineWidth',2,'DisplayName','Pellet (x=0)');
    yline(slitX_norm,':k','LineWidth',1.5,'DisplayName','Slit');

    xlabel('Frame'); ylabel('Paw X [mm] (pellet-centered)');
    title(sprintf('%s - Reach %d [%s]', coreID, reachID, label));
    xlim([framesFiltered(1) framesFiltered(end)]);
    ylim([ylo yhi]);

    % --- Save QC plot ---
    if exist('outDir','var') && ~isempty(outDir)
        qcDir = fullfile(outDir,'QC','Reach');
        if ~exist(qcDir,'dir'), mkdir(qcDir); end
        saveas(figQC, fullfile(qcDir, sprintf('%s_%d.png', coreID, reachID)));
    end

    close(figQC); % prevent too many open figs
end


% -----------------------
% METRICS (all expected fields)
% -----------------------

% Outward movement
xOut   = xPlot(1:contactIdx);
yOut   = yPlot(1:contactIdx);
velOut = diff(xOut);

metrics.outwardMovementDuration = numel(xOut)-1;
metrics.peakOutwardVelocity     = max(velOut, [], 'omitnan');
metrics.meanOutwardVelocity     = mean(velOut, 'omitnan');

if ~isempty(velOut)
    [~, pOut] = max(velOut);
    metrics.timeToPeakVelocity      = pOut;
    metrics.timeToPeakVelocity_norm = pOut / max(1,numel(xPlot));
    metrics.peakOutwardVelocityFrame = pOut;
else
    metrics.timeToPeakVelocity      = NaN;
    metrics.timeToPeakVelocity_norm = NaN;
    metrics.peakOutwardVelocityFrame = NaN;
end

accOut = diff(velOut);
if ~isempty(accOut)
    metrics.peakAcceleration = max(accOut, [], 'omitnan');
    metrics.peakDeceleration = min(accOut, [], 'omitnan');
    jerkOut = diff(accOut);
    metrics.meanAbsJerk = mean(abs(jerkOut), 'omitnan');
    if ~isempty(jerkOut)
        metrics.peakJerk = max(abs(jerkOut), [], 'omitnan');
    else
        metrics.peakJerk = NaN;
    end
    metrics.accelSignChanges = sum(diff(sign(accOut))~=0);
else
    metrics.peakAcceleration = NaN;
    metrics.peakDeceleration = NaN;
    metrics.meanAbsJerk      = NaN;
    metrics.peakJerk         = NaN;
    metrics.accelSignChanges = 0;
end

metrics.trajectoryLength_outward = sum(hypot(diff(xOut), diff(yOut)), 'omitnan');
if numel(xOut) >= 2
    metrics.initialReachAngle = atan2d(yOut(2)-yOut(1), xOut(2)-xOut(1));
else
    metrics.initialReachAngle = NaN;
end

% Y positions at fractions of slit→pellet
dist3    = slitX_norm/3;
x_points = [slitX_norm + dist3, slitX_norm + 2*dist3, 0];
[xUnique, uniqueIdx] = unique(xOut, 'stable');
yUnique = yOut(uniqueIdx);
if numel(xUnique) >= 2
    y_interp = interp1(xUnique, yUnique, x_points, 'linear','extrap');
else
    y_interp = [NaN NaN NaN];
end
metrics.y_at_1_3    = y_interp(1);
metrics.y_at_2_3    = y_interp(2);
metrics.y_at_pellet = y_interp(3);

% Contact-related
metrics.nPelletContactPeaks = nPeaks;
if exist('pelletContactPhaseIdx','var') && ~isempty(pelletContactPhaseIdx)
    metrics.contactDuration = numel(pelletContactPhaseIdx);
else
    metrics.contactDuration = 0;
end

% Pauses & corrections
velX = diff(xPlot);
metrics.corrections = sum(velX < 0);
velThreshold = 0.5;
lowVel = abs(velX) < velThreshold;
dLow   = diff([0; lowVel; 0]);
pauseS = find(dLow == 1);
pauseE = find(dLow == -1) - 1;
metrics.pauseCount        = numel(pauseS);
metrics.totalPauseDuration= sum(max(0, pauseE - pauseS + 1));

% Retrieval
xRetr   = xPlot(contactIdx:end);
yRetr   = yPlot(contactIdx:end);
velRetr = diff(xRetr);

metrics.retrievalDuration     = numel(xRetr)-1;
metrics.peakRetrievalVelocity = min(velRetr, [], 'omitnan');
metrics.meanRetrievalVelocity = mean(velRetr, 'omitnan');

if numel(xRetr) >= 2
    retrDiffs = diff([xRetr(:), yRetr(:)]);
    retrLen   = sum(hypot(retrDiffs(:,1), retrDiffs(:,2)),'omitnan');
    retrEuc   = norm([xRetr(end)-xRetr(1), yRetr(end)-yRetr(1)]);
    metrics.retrievalStraightness = retrEuc / max(retrLen, eps);
    metrics.retrievalArc          = max(yRetr) - min(yRetr);
    metrics.retrievalReversals    = sum(diff(xRetr) > 0);
    accRetr  = diff(velRetr);
    metrics.retrievalMeanAbsJerk  = mean(abs(diff(accRetr)), 'omitnan');
else
    metrics.retrievalStraightness = NaN;
    metrics.retrievalArc          = NaN;
    metrics.retrievalReversals    = 0;
    metrics.retrievalMeanAbsJerk  = NaN;
end

% Global
metrics.reachDuration     = sideEndFrame - sideStartFrame + 1;
metrics.maxHeight         = max(yPlot);
metrics.trajectoryLength  = sum(hypot(diff(xPlot), diff(yPlot)), 'omitnan');
metrics.trajectoryStraightness = norm([xPlot(end)-xPlot(1), yPlot(end)-yPlot(1)]) / ...
                                 max(metrics.trajectoryLength, eps);

diffVecs = diff([xPlot(:), yPlot(:)]);
angles   = atan2(diffVecs(:,2), diffVecs(:,1));
metrics.pathTortuosity = sum(abs(diff(angles)), 'omitnan');

% Attempts (helper function required)
metrics.reachAttempts = computeReachAttempts(pawX_smooth, slitX, 0);

% Placeholder fields if missing
if ~isfield(metrics,'timeToPelletContact')
    metrics.timeToPelletContact = metrics.timeSlitToContact_frames; % keep in frames
end
if ~isfield(metrics,'pelletContactPeakFrames')
    metrics.pelletContactPeakFrames = [];
end

% Ensure scalar values for metrics
scalarFields = {'peakOutwardVelocity','meanOutwardVelocity','outwardMovementDuration', ...
                'initialReachAngle','y_at_1_3','y_at_2_3','y_at_pellet', ...
                'overshootDistance','corrections','pauseCount','totalPauseDuration', ...
                'retrievalDuration','peakRetrievalVelocity','meanRetrievalVelocity', ...
                'retrievalStraightness','endpoint_x','endpoint_y', ...
                'timeSlitToContact_frames','timeSlitToContact_sec', ...
                'slitToPelletDistance_mm','normReachTime_s_per_mm','meanOutwardSpeed_mm_per_s'};

for f = 1:numel(scalarFields)
    fld = scalarFields{f};
    if ~isfield(metrics,fld) || isempty(metrics.(fld))
        metrics.(fld) = NaN;
    end
end

% Cell fields (must always be a cell, even if empty)
cellFields = {'pelletContactPeakFrames'};
for f = 1:numel(cellFields)
    fld = cellFields{f};
    if ~isfield(metrics,fld)
        metrics.(fld) = {[]};
    elseif ~iscell(metrics.(fld))
        metrics.(fld) = {metrics.(fld)};
    end
end


end


function attempts = computeReachAttempts(pawX_smooth, slitX, pelletXreach)
isOutsideSlit = pawX_smooth > slitX;
dSlit = diff([0; isOutsideSlit; 0]);
slitStarts = find(dSlit == 1);
slitEnds   = find(dSlit == -1) - 1;

attemptsPerBout = zeros(length(slitStarts),1);
for b = 1:length(slitStarts)
    seg = pawX_smooth(slitStarts(b):slitEnds(b));
    contactMaskBout = seg > pelletXreach;
    dBout = diff([0; contactMaskBout; 0]);
    attemptsPerBout(b) = sum(dBout == 1);
end

if isempty(attemptsPerBout)
    attempts = 0;
else
    attempts = max(attemptsPerBout);
end
end

function idx = lastLocalMinBefore(sig, idxPeak)
% Return index of the last local minimum BEFORE idxPeak (>=1).
% Robust to short segments; falls back to global min if needed.

if idxPeak <= 1
    idx = 1;
    return;
end

seg = sig(1:idxPeak-1);
n = numel(seg);

if n >= 3
    [~, locs] = findpeaks(-seg);       % minima = peaks on inverted signal
    if ~isempty(locs)
        idx = locs(end);               % last minimum before peak
        return;
    end
    % fallback: global min in segment
    [~, idx] = min(seg);
elseif n >= 1
    [~, idx] = min(seg);               % too short for findpeaks → pick min
else
    idx = 1;                           % no samples
end
end

function idx = firstLocalMinAfter(sig, idxPeak)
% Return index of the first local minimum AFTER idxPeak (<= length(sig)).
% Robust to short segments; falls back to global min if needed.

nSig = numel(sig);
if idxPeak >= nSig
    idx = nSig;
    return;
end

seg = sig(idxPeak+1:end);
n = numel(seg);

if n >= 3
    [~, locs] = findpeaks(-seg);
    if ~isempty(locs)
        idx = idxPeak + locs(1);      % map back to full-signal index
        return;
    end
    % fallback: global min after peak
    [~, rel] = min(seg);
    idx = idxPeak + rel;
elseif n >= 1
    [~, rel] = min(seg);              % too short for findpeaks → pick min
    idx = idxPeak + rel;
else
    idx = nSig;                        % no samples
end
end

%%
function [metrics, traj, failReason] = analyzeReach_Front( ...
    coreID, reachRow, dlc_front, offsetVal, likelihoodThresh, sideStartRef, sideEndRef)

metrics = struct();
traj = struct();
failReason = "";

% Parameters
par.showQCplot   = false;
par.frame_buffer = 200;   % extend ± buffer
par.boundarySlack= 10;    % slack around peaks
par.minLik       = 0.6;   % high likelihood threshold
par.minRun       = 5;     % min consecutive high-likelihood frames
par.minRunKeep   = 4;     % minimum run length to keep after crop

% ----- pellet reference -----
pelletMask = dlc_front.pellet_likelihood > 0.9;
pelletX = median(dlc_front.pellet_x(pelletMask), 'omitnan');
pelletY = median(dlc_front.pellet_y(pelletMask), 'omitnan');

% Paw = mean of digit2 + digit5
pawX  = mean([dlc_front.digit2_x, dlc_front.digit5_x], 2, 'omitnan') - pelletX;
pawY  = mean([dlc_front.digit2_y, dlc_front.digit5_y], 2, 'omitnan') - pelletY;
pawLik= mean([dlc_front.digit2_likelihood, dlc_front.digit5_likelihood], 2, 'omitnan');

% Digit coords relative to pellet
digit2X = dlc_front.digit2_x - pelletX;
digit2Y = dlc_front.digit2_y - pelletY;
digit5X = dlc_front.digit5_x - pelletX;
digit5Y = dlc_front.digit5_y - pelletY;

% ----- reach window mapping -----
if isnan(sideStartRef) || isnan(sideEndRef) || sideEndRef <= sideStartRef
    failReason = "invalid side refined window";
    return;
end

frontStart = sideStartRef + offsetVal;
frontEnd   = sideEndRef   + offsetVal;
frontStart = max(1, min(frontStart, height(dlc_front)));
frontEnd   = max(1, min(frontEnd, height(dlc_front)));

frames = max(1, frontStart - par.frame_buffer) : ...
         min(frontEnd + par.frame_buffer, height(dlc_front));

% ----- digit spread for peak detection -----
d2x = dlc_front.digit2_x(frames) - pelletX;
d2y = dlc_front.digit2_y(frames) - pelletY;
d5x = dlc_front.digit5_x(frames) - pelletX;
d5y = dlc_front.digit5_y(frames) - pelletY;
spreadRaw = sqrt((d2x - d5x).^2 + (d2y - d5y).^2);

spreadLik = min(dlc_front.digit2_likelihood(frames), dlc_front.digit5_likelihood(frames));
spread = spreadRaw;
spread(spreadLik < likelihoodThresh) = NaN;

% --- peak detection ---
[pkVals, locs] = findpeaks(spread, ...
    'MinPeakProminence', 0.5, ...
    'MinPeakDistance', 8);
peakLik = arrayfun(@(i) mean(pawLik(frames(max(1,i-2):min(end,i+2))), 'omitnan'), locs);

if isempty(locs)
    failReason = "No spread peaks found";
    return;
end

score = pkVals .* peakLik;
[~, bestIdx] = max(score);
idxMaxSpread = locs(bestIdx);

% --- smoothing and run segmentation ---
spreadSm = smoothdata(spread, 'sgolay', 17, 'omitnan');  
likSm    = smoothdata(spreadLik, 'movmean', 7, 'omitnan');
validMask = ~isnan(spreadSm);
edges = diff([false; validMask; false]);
runStarts = find(edges == 1);
runEnds   = find(edges == -1) - 1;
r = find(idxMaxSpread >= runStarts & idxMaxSpread <= runEnds, 1, 'first');
thisRun = runStarts(r):runEnds(r);

% Restrict valley search
valleyMask = false(size(spreadSm));
valleyMask(thisRun) = islocalmin(spreadSm(thisRun));
valleyLocs = find(valleyMask);

% Score valleys
peakVal = spreadSm(idxMaxSpread);
scoreValley = @(i, signFlip) ...
    (peakVal - spreadSm(i)) / max(peakVal, eps) + ...
    0.5 * max(0, signFlip * (likSm(min(i+4,end)) - likSm(max(i-4,1))));

leftCands = valleyLocs(valleyLocs < idxMaxSpread - 5);
if ~isempty(leftCands)
    scores = arrayfun(@(i) scoreValley(i,+1), leftCands);
    [~,k] = max(scores);
    leftValley = leftCands(k);
else
    leftValley = thisRun(1);
end

rightCands = valleyLocs(valleyLocs > idxMaxSpread + 5);
if ~isempty(rightCands)
    scores = arrayfun(@(i) scoreValley(i,-1), rightCands);
    [~,k] = max(scores);
    rightValley = rightCands(k);
else
    rightValley = thisRun(end);
end

% redefine reach window
reachStartFrame = frames(leftValley);
reachEndFrame   = frames(rightValley);
frames = reachStartFrame:reachEndFrame;

% ----- build cropped signals -----
xTraj = pawX(frames);
yTraj = pawY(frames);
d2Traj = [digit2X(frames), digit2Y(frames)];
d5Traj = [digit5X(frames), digit5Y(frames)];

% ----- post-crop cleanup -----
% 1) Remove jumps
dx = diff(xTraj); dy = diff(yTraj);
stepDist = hypot(dx,dy);
medStep = median(stepDist,'omitnan');
madStep = mad(stepDist,1);
jumpThresh = medStep + 10*madStep;
jumps = [false; stepDist > jumpThresh];
xTraj(jumps) = NaN; yTraj(jumps) = NaN;

% 2) Remove spikes
vel = hypot(diff(xTraj), diff(yTraj));
zv  = (vel - mean(vel,'omitnan'))/std(vel,'omitnan');
spike = [false; abs(zv) > 5];
xTraj(spike) = NaN; yTraj(spike) = NaN;

% 3) Interpolate short gaps
maxGap = 5;
xTraj = fillmissing(xTraj,'linear','MaxGap',maxGap,'EndValues','nearest');
yTraj = fillmissing(yTraj,'linear','MaxGap',maxGap,'EndValues','nearest');

% 4) Remove short runs (≤3 frames)
validMask = ~isnan(xTraj);
edges = diff([false; validMask; false]);
runStarts = find(edges==1);
runEnds   = find(edges==-1)-1;
for rr = 1:numel(runStarts)
    if runEnds(rr) - runStarts(rr) + 1 <= par.minRunKeep
        xTraj(runStarts(rr):runEnds(rr)) = NaN;
        yTraj(runStarts(rr):runEnds(rr)) = NaN;
    end
end
xTraj = fillmissing(xTraj,'linear','MaxGap',maxGap,'EndValues','nearest');
yTraj = fillmissing(yTraj,'linear','MaxGap',maxGap,'EndValues','nearest');

% recompute spread
spread = sqrt((d2Traj(:,1)-d5Traj(:,1)).^2 + (d2Traj(:,2)-d5Traj(:,2)).^2);

if sum(~isnan(xTraj)) < 5
    failReason = "Not enough valid paw points after cleanup";
    return;
end

% ------------------ INDEX CONVERSIONS ------------------
idxMax_c   = idxMaxSpread  - leftValley + 1;        
idxMax_c   = max(1, min(idxMax_c, numel(frames)));  
pelletContactIdx_c = max(1, min(idxMax_c + 1, numel(frames)));  

absMaxFrame     = frames(idxMax_c);
absClosureFrame = frames(pelletContactIdx_c);
absLeftFrame    = frames(1);
absRightFrame   = frames(end);

% ----- metrics -----
trajLen    = sum(sqrt(diff(xTraj).^2 + diff(yTraj).^2), 'omitnan');
trajWidth  = range(xTraj);
trajHeight = range(yTraj);

lineVec = [0 0] - [xTraj(1), yTraj(1)];
normLine = norm(lineVec);
if normLine > 0
    proj = (xTraj - xTraj(1))*lineVec(1) + (yTraj - yTraj(1))*lineVec(2);
    proj = proj / normLine^2 * lineVec;
    dev  = sqrt((xTraj - (xTraj(1)+proj(:,1))).^2 + (yTraj - (yTraj(1)+proj(:,2))).^2);
    frontDeviation = mean(dev,'omitnan');
else
    frontDeviation = NaN;
end

vx = diff(xTraj);
frontZigZags = sum(diff(sign(vx))~=0);

distToPellet = sqrt(xTraj.^2 + yTraj.^2);
minDistToPellet = min(distToPellet,[],'omitnan');
[~, minDistIdx] = min(distToPellet);

digitSpreadMean        = mean(spread,'omitnan');
digitSpreadPeak        = max(spread,[],'omitnan');
digitSpreadAtContact   = spread(1);
digitSpreadAtRetrieval = spread(end);
digitSpreadTiming      = idxMax_c / numel(spread);

metrics.frontTrajLen          = trajLen;
metrics.frontTrajWidth        = trajWidth;
metrics.frontTrajHeight       = trajHeight;
metrics.frontDeviation        = frontDeviation;
metrics.frontZigZags          = frontZigZags;
metrics.minDistToPellet       = minDistToPellet;
metrics.digitSpreadMean       = digitSpreadMean;
metrics.digitSpreadPeak       = digitSpreadPeak;
metrics.digitSpreadAtContact  = digitSpreadAtContact;
metrics.digitSpreadAtRetrieval= digitSpreadAtRetrieval;
metrics.digitSpreadTiming     = digitSpreadTiming;
metrics.digitSpreadAtClosure  = spread(pelletContactIdx_c);
metrics.distToPelletAtClosure = hypot(xTraj(pelletContactIdx_c), yTraj(pelletContactIdx_c));
metrics.closureFrameNorm      = pelletContactIdx_c / numel(spread);



traj = struct( ...
    'reachID', reachRow.ReachIndex, ...
    'label',   string(reachRow.Label), ...
    'frames',  frames, ...
    'x',       xTraj, ...
    'y',       yTraj, ...
    'digit2',  d2Traj, ...
    'pelletX', 0, ...   % you computed these above
    'pelletY', 0, ...
    'slitX_norm', 0, ...
    'digit5',  d5Traj, ...
    'spread',  spread);


% ---------- QC PLOT ----------
if par.showQCplot
    figQC = figure('Visible','on', ...
        'Name', sprintf('Front QC Reach %s - %s [%s]', ...
        coreID, string(reachRow.ReachIndex), string(reachRow.Label)), ...
        'Color','w','Position',[100 100 1200 500]);

    fullFrames = max(1, frontStart - par.frame_buffer) : ...
                 min(frontEnd + par.frame_buffer, height(dlc_front));

    d2x_full = dlc_front.digit2_x(fullFrames) - pelletX;
    d2y_full = dlc_front.digit2_y(fullFrames) - pelletY;
    d5x_full = dlc_front.digit5_x(fullFrames) - pelletX;
    d5y_full = dlc_front.digit5_y(fullFrames) - pelletY;
    spreadFull_raw = sqrt((d2x_full - d5x_full).^2 + (d2y_full - d5y_full).^2);

    likFull = min(dlc_front.digit2_likelihood(fullFrames), ...
                  dlc_front.digit5_likelihood(fullFrames));

    spreadFull = spreadFull_raw;
    spreadFull(likFull < likelihoodThresh) = NaN;
    dS = diff(spreadFull);
    medD = median(dS,'omitnan');
    madD = mad(dS,1);
    jump = [false; abs(dS - medD) > 8*madD];
    spreadFull(jump) = NaN;
    spreadFull = fillmissing(spreadFull,'linear','MaxGap',5,'EndValues','nearest');
    spreadFullSm = smoothdata(spreadFull,'sgolay',11);

    toFullIdx = @(absF) max(1, min(numel(fullFrames), absF - fullFrames(1) + 1));
    iMax     = toFullIdx(absMaxFrame);
    iClosure = toFullIdx(absClosureFrame);
    iLeft    = toFullIdx(absLeftFrame);
    iRight   = toFullIdx(absRightFrame);

    yMax     = spreadFullSm(iMax);
    yClosure = spreadFullSm(iClosure);

    subplot(1,2,1); hold on;
    cmap = jet(256);
    likNorm = round(1 + 255*max(0,min(1,likFull)));
    likNorm(isnan(likNorm)) = 1;

    for i = 1:(numel(fullFrames)-1)
        if any(isnan(spreadFullSm(i:i+1))), continue; end
        cIdx = min(max(likNorm(i),1),256);
        plot(fullFrames(i:i+1), spreadFullSm(i:i+1), '-', ...
            'Color', cmap(cIdx,:), 'LineWidth', 2, 'HandleVisibility','off');
    end

    plot(absMaxFrame, yMax, 'bo','MarkerFaceColor','b','MarkerSize',8,'DisplayName','Chosen max spread');
    plot(absClosureFrame, yClosure, 'ro','MarkerFaceColor','r','MarkerSize',8,'DisplayName','Closure');
    xline(absLeftFrame,  '--k','Left valley');
    xline(absRightFrame, '--k','Right valley');

    text(absMaxFrame, yMax, sprintf(' Max @ %d', absMaxFrame), ...
         'VerticalAlignment','bottom','Color','b','FontWeight','bold');
    text(absClosureFrame, yClosure, sprintf(' Closure @ %d', absClosureFrame), ...
         'VerticalAlignment','top','Color','r','FontWeight','bold');

    xlabel('Frame'); ylabel('Digit 2–5 spread (mm)');
    title('Digit spread QC (colored by likelihood)');
    legend('show');
    cb1 = colorbar; caxis([0 1]); ylabel(cb1,'Tracking likelihood');

    subplot(1,2,2); hold on;
    likCrop = pawLik(frames);
    likCrop(isnan(likCrop)) = 0;
    likCropNorm = round(1 + 255*max(0,min(1,likCrop)));
    for i = 1:(numel(xTraj)-1)
        if any(isnan([xTraj(i:i+1); yTraj(i:i+1)])), continue; end
        cIdx = min(max(likCropNorm(i),1),256);
        plot(xTraj(i:i+1), yTraj(i:i+1), '-', ...
            'Color', cmap(cIdx,:), 'LineWidth', 2, 'HandleVisibility','off');
    end
    scatter(xTraj(1), yTraj(1), 60, 'g', 'filled', 'DisplayName','Start');
    scatter(xTraj(end), yTraj(end), 60, 'm', 'filled', 'DisplayName','End');
    scatter(xTraj(pelletContactIdx_c), yTraj(pelletContactIdx_c), ...
        60, 'r', 'filled','DisplayName','Closure');
    text(xTraj(pelletContactIdx_c), yTraj(pelletContactIdx_c), ...
        sprintf(' %d', absClosureFrame), ...
        'VerticalAlignment','bottom','Color','r');

    xlabel('X (pellet-centered)'); ylabel('Y (pellet-centered)');
    title('Paw trajectory QC (colored by likelihood)');
    legend('show');
    cb2 = colorbar; caxis([0 1]); ylabel(cb2,'Tracking likelihood');

    qcDir = fullfile(pwd,'OUT','QC','FrontReaches');
    if ~exist(qcDir,'dir'), mkdir(qcDir); end
    saveas(figQC, fullfile(qcDir, sprintf('%s_front_%s.png', ...
        coreID, string(reachRow.ReachIndex))));
    pause;
    close(figQC);
end

end


%%
function [group, animal, test_day] = parseCoreID(coreID)
    % Split by both '-' and '_'
    parts = regexp(coreID, '[-_]', 'split');
    
    if numel(parts) < 4
        error('coreID format error: expected four parts split by "-" and "_".');
    end
    
    group = parts{1};
    % Combine parts 2 and 3 for animal (with hyphen)
    animal = strcat(parts{2}, '-', parts{3});
    test_day = parts{4};
end

%% Graph functions
function params = getViewParams(viewType)
% Returns x/y limits, binning and edges/centers for the two views
switch lower(viewType)
    case 'side'
        params.xlim   = [-15 10];
        params.ylim   = [-10 15];
        params.bin    = 1;          % mm
        params.xEdges = params.xlim(1):params.bin:params.xlim(2);
        params.yEdges = params.ylim(1):params.bin:params.ylim(2);
    
        % centers
        params.xCtr   = (params.xEdges(1:end-1)+params.xEdges(2:end))/2;
        params.yCtr   = (params.yEdges(1:end-1)+params.yEdges(2:end))/2;
        params.showSlit = true;
    case 'front'
        params.xlim   = [-8 8];
        params.ylim   = [-7 1];
        params.bin    = 0.5;        % mm
        
        params.xEdges = params.xlim(1):params.bin:params.xlim(2);
        params.yEdges = params.ylim(1):params.bin:params.ylim(2);
    
        % centers from edges
        params.xCtr   = (params.xEdges(1:end-1)+params.xEdges(2:end))/2;
        params.yCtr   = (params.yEdges(1:end-1)+params.yEdges(2:end))/2;
        params.showSlit = false;    % no slit for front view
    otherwise
        error('Unknown viewType: %s', viewType);
end
end


function plotPerAnimalTraj(trajArray, coreID, viewType, figDir, groupBy)
   if nargin < 5
        groupBy = "label";   % default if not specified
    end

    if isempty(trajArray), return; end
    P = getViewParams(viewType);

    % --- Choose which field to group on ---
    switch lower(groupBy)
        case "label"
            labelsAll = string({trajArray.label});
        case "broadlabel"
            labelsAll = string({trajArray.broadLabel});
        otherwise
            error("Unknown groupBy option: %s (must be 'label' or 'broadLabel')", groupBy);
    end

    uLabels = unique(labelsAll,'stable');

    % --- reorder: Success first, then Errors alphabetically ---
    isSuccess = strcmpi(uLabels, "Success");
    isError   = startsWith(uLabels, "Error", 'IgnoreCase', true);

    if ~any(isSuccess | isError)
        warning('No Success or Error labels found, keeping original order');
        % keep uLabels as-is
    else
        errorLabels = sort(uLabels(isError));
        uLabels = [uLabels(isSuccess), errorLabels, uLabels(~(isSuccess | isError))];
    end

    nLabels = numel(uLabels);
    nRows   = 1;
    nCols   = nLabels;
    cols = lines(nLabels);

panelSize = 300; % px per subplot, adjust as needed
f = figure('Visible','off','Color','w','Name',sprintf('%s %s Traj',coreID,viewType), ...
    'Position', [100 100 panelSize*nCols panelSize*nRows]);

for k = 1:nLabels
    L = uLabels(k);
    sel = strcmp(labelsAll, L);
    T = [trajArray(sel).traj];

    subplot(nRows,nCols,k); hold on; grid on;
    title(sprintf('%s (%d)', L, numel(T)), 'Interpreter','none');
    xlabel('X (mm)'); ylabel('Y (mm)');
    xlim(P.xlim); ylim(P.ylim);
    set(gca,'YDir','reverse');     % <-- restore flipped Y
    base = cols(k,:);

    % individual trajectories
    for t = 1:numel(T)
        c = base * (t/numel(T));
        plot(T(t).x, T(t).y, 'LineWidth',1.5, 'Color', [c 0.20]);
    end

    % --- average trace (median) ---
        if ~isempty(T)
            nPts = 100; % number of resample points
            Xrs = nan(numel(T), nPts);
            Yrs = nan(numel(T), nPts);
            nIncluded = 0;
            nExcluded = 0;

            for t = 1:numel(T)
                x = T(t).x(:); % force column
                y = T(t).y(:); % force column
 

                if numel(x) < 2
                    nExcluded = nExcluded + 1;
                    continue; % skip too-short trajectories
                end


                % find NaN runs
                mask = isnan(x) | isnan(y);
                d = diff([0; mask; 0]);
                starts = find(d == 1);
                ends   = find(d == -1);
                if isempty(starts)
                    maxRun = 0;
                else
                    runLengths = ends - starts;
                    maxRun = max(runLengths);
                end
            
                if maxRun > 2  % threshold: reject if longest NaN run > 3 samples
                    nExcluded = nExcluded + 1;
                    continue;
                end

                % patch small NaNs by interpolation
                x = fillmissing(x,'linear','EndValues','extrap');
                y = fillmissing(y,'linear','EndValues','extrap');


                % safety: if still non-finite, skip
                if any(~isfinite(x)) || any(~isfinite(y))
                    nExcluded = nExcluded + 1;
                    continue;
                end
                dx = diff(x);
                dy = diff(y);
                arc = [0; cumsum(sqrt(dx.^2 + dy.^2))];
                if arc(end) == 0
                    nExcluded = nExcluded + 1;
                    continue; % skip degenerate
                end

                arcNorm = arc ./ arc(end);

                % remove duplicates in arcNorm
                [arcNormUnique, ia] = unique(arcNorm, 'stable');
                xUnique = x(ia);
                yUnique = y(ia);

                if numel(arcNormUnique) < 2
                    nExcluded = nExcluded + 1;
                    continue;
                end
                arcGrid = linspace(0,1,nPts);

                Xrs(t,:) = interp1(arcNormUnique, xUnique, arcGrid, 'linear', 'extrap');
                Yrs(t,:) = interp1(arcNormUnique, yUnique, arcGrid, 'linear', 'extrap');
                nIncluded = nIncluded + 1;
            end

            xMed = median(Xrs,1,'omitnan');
            yMed = median(Yrs,1,'omitnan');

            plot(xMed, yMed, 'k-', 'LineWidth',1.0);
        end
    fprintf('Label %s: included %d trajectories, excluded %d\n', string(L), nIncluded, nExcluded);

    % pellet at origin
    scatter(0,0,60,'o','MarkerEdgeColor','k','MarkerFaceColor',[0.5 0.5 0.5],'LineWidth',1.25);

    % mean slit (side only)
    if P.showSlit
        slitVals = [T.slitX_norm];
        if ~isempty(slitVals)
            mSlit = mean(slitVals,'omitnan');
            plot([mSlit mSlit], get(gca,'YLim'), ':', 'LineWidth',1.5, 'Color',[0.7 0.7 0.7]);
        end
    end
end
outDir = fullfile(figDir, char(groupBy), viewType);
if ~exist(outDir, 'dir'), mkdir(outDir); end

pos = get(f,'Position');
fprintf('Figure position: width=%.1f, height=%.1f\n', pos(3), pos(4));


% build stub without extension
savename = fullfile(outDir, sprintf('RAW_%s_Traj_%s_%s', ...
    upper(viewType(1)), coreID, char(groupBy)));
set(f, 'Color', 'w');          % figure background
export_fig(savename, '-pdf', '-png', '-r300', f);
close(f);

end


function plotGroupTraj(Rgrp, grpName, viewType, figDir, groupBy)
    if nargin < 5
        groupBy = "label";   % default
    end

    % --- smoothing options (tunable) ---
S.smoothIndividuals = true;     % smooth rainbow traces?
S.smoothAverage     = true;     % smooth black median path?
S.method            = 'movmean'; % 'sgolay' preserves shape; 'movmean' also fine
S.windowPtsRaw      = 10;        % window for raw (per-frame) smoothing
S.sgOrder           = 2;        % sgolay poly order
S.windowPtsAvg      = 10;        % window for the resampled average (nPts-grid)

% local helper
smoothXY = @(x,y,w,method,ord) deal( ...
    smoothdata(x, method, w, 'SamplePoints', 1:numel(x), 'sgolaydegree', ord), ...
    smoothdata(y, method, w, 'SamplePoints', 1:numel(y), 'sgolaydegree', ord) );

    if isempty(Rgrp), return; end
    P = getViewParams(viewType);

    % --- Collect wrappers with test_day + animal ID ---
    trajArray = [];
    for r = 1:numel(Rgrp)
        if isfield(Rgrp(r), lower(viewType)) && ...
           isfield(Rgrp(r).(lower(viewType)), 'trajectories')
            W = Rgrp(r).(lower(viewType)).trajectories;
            [W.test_day] = deal(Rgrp(r).test_day);
            [W.animal]   = deal(Rgrp(r).animal);
            trajArray = [trajArray W]; %#ok<AGROW>
        end
    end
    if isempty(trajArray), return; end

    % --- Days and labels ---
    switch lower(groupBy)
        case "label"
            labelsAll = string({trajArray.label});
        case "broadlabel"
            labelsAll = string({trajArray.broadLabel});
        otherwise
            error("Unknown groupBy option: %s", groupBy);
    end

    uDays   = string(unique({trajArray.test_day}, 'stable'));
    nDays = numel(uDays);
    labelsAll = string(labelsAll);  % enforce string array
    uLabels = string(unique(labelsAll, 'stable'));
    
    % --- reorder: Success first, then Errors alphabetically ---
    isSuccess = strcmpi(uLabels, "Success");
    isError   = startsWith(uLabels, "Error", 'IgnoreCase', true);
    
    if any(isSuccess | isError)
        errorLabels = sort(uLabels(isError));
        others      = uLabels(~(isSuccess | isError));
        uLabels     = [uLabels(isSuccess), errorLabels, others];
    end

    nLabels = numel(uLabels);

    % --- Animals for coloring ---
    uAnimals = unique({trajArray.animal}, 'stable');
    nAnimals = numel(uAnimals);
    animalColors = lines(nAnimals);

    % --- Subplot grid: rows = labels, cols = days ---
    [LL, DD] = ndgrid(string(uLabels), string(uDays));
    labelsGrid = strcat(LL," / ",DD);
    nRows = nLabels;
    nCols = nDays;

    f = figure('Visible','off','Color','w', ...
        'Name', sprintf('%s %s GroupTraj', grpName, viewType), ...
        'Position', [100 100 300*nCols 300*nRows]);

    for d = 1:nDays
        daySel = strcmpi({trajArray.test_day}, uDays(d));
        for k = 1:nLabels
            labSel = strcmpi(labelsAll, uLabels(k));
            sel = daySel & labSel;

            T = [trajArray(sel).traj];
            A = {trajArray(sel).animal};

            idx = (k-1)*nCols + d;   % manual linear index, column-major to row-major fix
            
            subplot(nRows,nCols,idx); hold on; grid on;
            title(sprintf('%s / %s (%d)', string(uLabels(k)), uDays(d), numel(T)), 'Interpreter','none');
            xlabel('X (mm)'); ylabel('Y (mm)');
            xlim(P.xlim); ylim(P.ylim);
            set(gca,'YDir','reverse');
             
                        % --- plot individual trajectories ---
            for t = 1:numel(T)
                % pick animal color
                aIdx = find(strcmp(uAnimals, A{t}));
                col  = animalColors(aIdx,:);

                % grab raw coords
                x = T(t).x(:);
                y = T(t).y(:);

                % optional smoothing
                if exist('S','var') && isfield(S,'smoothIndividuals') && S.smoothIndividuals
                    switch lower(S.method)
                        case 'sgolay'
                            % direct Savitzky–Golay filter
                            x = sgolayfilt(x, 2, S.windowPtsRaw);
                            y = sgolayfilt(y, 2, S.windowPtsRaw);
                        otherwise
                            % smoothdata with movmean or other methods
                            x = smoothdata(x, S.method, S.windowPtsRaw);
                            y = smoothdata(y, S.method, S.windowPtsRaw);
                    end
                end

                % plot (with transparency)
                plot(x, y, 'Color', [col 0.2], 'LineWidth', 1.0);
            end


            % --- compute average trajectory across this subset ---

            if ~isempty(T)
                nPts = 100; % number of normalized points
                Xrs = nan(numel(T), nPts);
                Yrs = nan(numel(T), nPts);
                nIncluded = 0;
                nExcluded = 0;
                
                for t = 1:numel(T)
                    x = T(t).x(:); % force column
                    y = T(t).y(:); % force column
                
                    if numel(x) < 2
                        continue; % skip too-short trajectories
                    end
                
                % find NaN runs
                mask = isnan(x) | isnan(y);
                dMask = diff([0; mask; 0]);
                starts = find(dMask  == 1);
                ends   = find(dMask  == -1);
                if isempty(starts)
                    maxRun = 0;
                else
                    runLengths = ends - starts;
                    maxRun = max(runLengths);
                end
            
                if maxRun > 2  % threshold: reject if longest NaN run > 3 samples
                    nExcluded = nExcluded + 1;
                    continue;
                end

                % patch small NaNs by interpolation
                x = fillmissing(x,'linear','EndValues','extrap');
                y = fillmissing(y,'linear','EndValues','extrap');


                % safety: if still non-finite, skip
                if any(~isfinite(x)) || any(~isfinite(y))
                    nExcluded = nExcluded + 1;
                    continue;
                end
                dx = diff(x);
                dy = diff(y);
                arc = [0; cumsum(sqrt(dx.^2 + dy.^2))];
                if arc(end) == 0
                    nExcluded = nExcluded + 1;
                    continue; % skip degenerate
                end
                    arcNorm = arc ./ arc(end);

                    % remove duplicates in arcNorm
                    [arcNormUnique, ia] = unique(arcNorm, 'stable');
                    xUnique = x(ia);
                    yUnique = y(ia);

                if numel(arcNormUnique) < 2
                    nExcluded = nExcluded + 1;
                    continue;
                end


                    arcGrid = linspace(0,1,nPts);
    
                    Xrs(t,:) = interp1(arcNormUnique, xUnique, arcGrid, 'linear', 'extrap');
                    Yrs(t,:) = interp1(arcNormUnique, yUnique, arcGrid, 'linear', 'extrap');
                    nIncluded = nIncluded + 1;
                end
    
                xAvg = median(Xrs,1,'omitnan');
                yAvg = median(Yrs,1,'omitnan');


                plot(xAvg, yAvg, 'c-', 'LineWidth', 1); %plot unsmoothed
            
                                % optional smoothing of the median path
                if exist('S','var') && isfield(S,'smoothAverage') && S.smoothAverage
                    switch lower(S.method)
                        case 'sgolay'
                            % direct Savitzky–Golay filter
                            xAvg = sgolayfilt(xAvg, S.sgOrder, S.windowPtsAvg);
                            yAvg = sgolayfilt(yAvg, S.sgOrder, S.windowPtsAvg);
                        otherwise
                            % smoothdata for movmean, gaussian, etc.
                            xAvg = smoothdata(xAvg, S.method, S.windowPtsAvg);
                            yAvg = smoothdata(yAvg, S.method, S.windowPtsAvg);
                    end
                end


                plot(xAvg, yAvg, 'k-', 'LineWidth', 1); %plot smoothed

            end

            % pellet marker
            scatter(0,0,60,'o','MarkerEdgeColor','k','MarkerFaceColor',[0.5 0.5 0.5],'LineWidth',1.25);

            % slit line (side view only)
            if P.showSlit && isfield(T, 'slitX_norm')
                slitVals = [T.slitX_norm];
                if ~isempty(slitVals)
                    mSlit = mean(slitVals,'omitnan');
                    plot([mSlit mSlit], get(gca,'YLim'), ':','LineWidth',1.5,'Color',[0.7 0.7 0.7]);
                end
            end
        end
        
    end

    % --- Legend (one for all animals, top right outside grid) ---
    ax = axes(f,'Visible','off'); %#ok<LAXES>
    hold(ax,'on');
    h = gobjects(nAnimals,1);
    for a = 1:nAnimals
        h(a) = plot(ax, nan, nan, 'Color', animalColors(a,:), 'LineWidth',2); %#ok<AGROW>
    end
    legend(ax, h, uAnimals, 'Location','northeastoutside', 'Box','off');
    title(ax, 'Animals', 'FontWeight','bold');

    % --- Save ---
    outDir = fullfile(figDir, char(groupBy), viewType);
    if ~exist(outDir, 'dir'), mkdir(outDir); end
    outName = fullfile(outDir, sprintf('%s_%s_GroupTraj_%s', grpName, upper(viewType(1)), lower(groupBy)));
    % saveas(f, fullfile(outDir, outName));
    set(f, 'Color', 'w');          % figure background
    export_fig(outName, '-pdf', '-png', '-r300', f);
    close(f);
end

function plotPerAnimalHeatmap(trajArray, coreID, viewType, figDir, groupBy)

   if nargin < 5
        groupBy = "label";   % default if not specified
    end

    if isempty(trajArray), return; end
    P = getViewParams(viewType);

    % --- Choose which field to group on ---
    switch lower(groupBy)
        case "label"
            labelsAll = string({trajArray.label});
        case "broadlabel"
            labelsAll = string({trajArray.broadLabel});
        otherwise
            error("Unknown groupBy option: %s (must be 'label' or 'broadLabel')", groupBy);
    end

if isempty(trajArray), return; end
P = getViewParams(viewType);

uLabels   = unique(labelsAll,'stable');
nLabels   = numel(uLabels);
nRows = 1;             % force one row
nCols = nLabels;       % one column per label


% -------- accumulate heatmaps per label --------
Hraw = cell(nLabels,1);
nReaches = zeros(nLabels,1);

for k = 1:nLabels
    L = uLabels(k);
    sel = strcmp(labelsAll, L);
    T = [trajArray(sel).traj];
    nReaches(k) = numel(T);

   Hk = zeros(numel(P.yEdges)-1, numel(P.xEdges)-1);
    slitVals = [];   % collect slit positions
    for t = 1:numel(T)
        if isempty(T(t).x) || isempty(T(t).y), continue; end
        Hk = Hk + histcounts2(T(t).y, T(t).x, P.yEdges, P.xEdges);
        if isfield(T(t),'slitX_norm')
            slitVals(end+1) = T(t).slitX_norm; %#ok<AGROW>
        end
    end
    Hraw{k} = struct('data', Hk, 'slitVals', slitVals);
end

% -------- derived heatmaps --------
Hnorm = cell(nLabels,1); % normalized per reach
Hprob = cell(nLabels,1); % normalized to probability

for k = 1:nLabels
    Hk = Hraw{k};  % struct with fields .data and .slitVals

    if nReaches(k) > 0
        Hnorm{k} = struct('data', Hk.data ./ nReaches(k), ...
                          'slitVals', Hk.slitVals);
    else
        Hnorm{k} = Hk; % just copy the struct
    end

    s = sum(Hk.data(:));
    if s > 0
        Hprob{k} = struct('data', Hk.data ./ s, ...
                          'slitVals', Hk.slitVals);
    else
        Hprob{k} = Hk;
    end
end

% -------- generate outputs --------
baseName = sprintf('RAW_%s_Heatmap_%s_%s', upper(viewType(1)), coreID, lower(groupBy));

plotHeatmapSet(Hnorm, uLabels, viewType, figDir, baseName, 'HM', P, groupBy, [1 nLabels]);
% plotHeatmapSet(Hprob, uLabels, viewType, figDir, baseName, 'PROB', P, groupBy);

end

function plotGroupHeatmaps(GrArray, grpName, viewType, figDir, groupBy)
    if nargin < 5
        groupBy = "label";   % default if not specified
    end
    if isempty(GrArray), return; end

    P = getViewParams(viewType);

    % --- Collect wrappers, attach test_day ---
    trajArray = [];
    for r = 1:numel(GrArray)
        if isfield(GrArray(r), lower(viewType)) && ...
           isfield(GrArray(r).(lower(viewType)), 'trajectories')
            W = GrArray(r).(lower(viewType)).trajectories;
            [W.test_day] = deal(GrArray(r).test_day);  % attach test_day
            trajArray = [trajArray W]; %#ok<AGROW>
        end
    end
    if isempty(trajArray), return; end

    % --- Unique days and labels ---
    uDays   = string(unique(string({trajArray.test_day}), 'stable'));
    nDays   = numel(uDays);

    switch lower(groupBy)
        case "label"
            labelsAll = string({trajArray.label});
        case "broadlabel"
            labelsAll = string({trajArray.broadLabel});
        otherwise
            error("Unknown groupBy option: %s (must be 'label' or 'broadLabel')", groupBy);
    end
    uLabels = string(unique(string(labelsAll), 'stable'));
    nLabels = numel(uLabels);

    % allocate
    Hraw     = cell(nDays, nLabels);
    nReaches = zeros(nDays, nLabels);

    % --- accumulate heatmaps per (day,label) ---
    for d = 1:nDays
        daySel = strcmp({trajArray.test_day}, uDays(d));
        for k = 1:nLabels
            labSel = strcmp(labelsAll, uLabels(k));
            sel = daySel & labSel;
        
            T = [trajArray(sel).traj];
            nReaches(d,k) = numel(T);
        
            Hk = zeros(numel(P.yEdges)-1, numel(P.xEdges)-1);
            slitVals = [];   % collect slit positions
        
            for t = 1:numel(T)
                if isempty(T(t).x) || isempty(T(t).y), continue; end
                Hk = Hk + histcounts2(T(t).y, T(t).x, P.yEdges, P.xEdges);
        
                % collect slit positions if available
                if isfield(T(t), 'slitX_norm')
                    slitVals(end+1) = T(t).slitX_norm; %#ok<AGROW>
                end
            end
        
            % wrap into struct so plotHeatmapSet can handle slitVals
            Hraw{d,k} = struct('data', Hk, 'slitVals', slitVals);
        end

    end
% --- derived heatmaps ---
Hnorm = cell(size(Hraw));
Hprob = cell(size(Hraw));

for d = 1:nDays
    for k = 1:nLabels
        Hk = Hraw{d,k};   % struct with fields .data and .slitVals
        if isempty(Hk), continue; end

        % Normalize per reach
        if nReaches(d,k) > 0
            Hnorm{d,k} = struct('data', Hk.data ./ nReaches(d,k), ...
                                'slitVals', Hk.slitVals);
        else
            Hnorm{d,k} = Hk;  % just carry forward struct
        end

        % Normalize to probability
        s = sum(Hk.data(:));
        if s > 0
            Hprob{d,k} = struct('data', Hk.data ./ s, ...
                                'slitVals', Hk.slitVals);
        else
            Hprob{d,k} = Hk;
        end
    end
end

    % --- label grid ---
    [DD, LL] = ndgrid(string(uDays), string(uLabels));   % days-major
    labelsGrid = strcat(LL, " / ", DD);
    labelsGrid = labelsGrid(:)';

    % --- plot ---
    baseName = sprintf('%s_%s_GroupHeatmap_%s', grpName, upper(viewType(1)), lower(groupBy));

    % Now reshape heatmap array in day-major order
    Hflat = reshape(Hnorm,1,[]);   % transpose to flip orientation
    plotHeatmapSet(Hflat, labelsGrid, viewType, figDir, baseName, 'HM', P, groupBy, [nDays nLabels]);

    % Hflat = reshape(Hprob,1,[]);
    % plotHeatmapSet(Hflat, labelsGrid, viewType, figDir, baseName, 'PROB', P, groupBy, [nDays nLabels]);
end


function plotGlobalLabelHeatmaps(allResults, uniqueGroups, uniqueDays, labelName, viewType, figDir, groupBy)

if nargin < 7
    groupBy = "label";   % default
end

P = getViewParams(viewType);

nGroups = numel(uniqueGroups);
nDays   = numel(uniqueDays);

% -------- accumulate per (day, group) --------
Hraw = cell(nDays, nGroups);
nReaches = zeros(nDays, nGroups);

for d = 1:nDays
    for g = 1:nGroups
        sel = strcmp({allResults.test_day}, uniqueDays(d)) & ...
              strcmp({allResults.group},    uniqueGroups(g));

        Rsub = allResults(sel);

        if isempty(Rsub), continue; end

        % collect trajectories with the given label/broadLabel
        allTraj = [];  % <-- will store the *inner* traj structs with x/y
        for r = 1:numel(Rsub)
            if isfield(Rsub(r), lower(viewType)) && ...
               isfield(Rsub(r).(lower(viewType)), 'trajectories')
            
                Wrappers = Rsub(r).(lower(viewType)).trajectories;   % wrapper structs: coreID/reachID/label/broadLabel/traj

                % filter the wrappers by groupBy
                switch lower(groupBy)
                    case "label"
                        keep = strcmp(string({Wrappers.label}), string(labelName));
                    case "broadlabel"
                        if isfield(Wrappers, 'broadLabel')
                            keep = strcmp(string({Wrappers.broadLabel}), string(labelName));
                        else
                            keep = false(size(Wrappers));
                        end
                    otherwise
                        error("Unknown groupBy option: %s", groupBy);
                end
                Wrappers = Wrappers(keep);

                if ~isempty(Wrappers)
                    % unwrap to inner traj structs (with x/y)
                    inner = [Wrappers.traj];  % this is now an array of structs with fields x,y,(maybe slitX_norm)
                    allTraj = [allTraj inner];
                    
                end
            end
        end
        if isempty(allTraj), continue; end

      % build heatmap for this (day, group)
        Hk = zeros(numel(P.yEdges)-1, numel(P.xEdges)-1);
        slitVals = [];   % collect slit positions
        
        for t = 1:numel(allTraj)
            if isempty(allTraj(t).x) || isempty(allTraj(t).y), continue; end
            Hk = Hk + histcounts2(allTraj(t).y, allTraj(t).x, P.yEdges, P.xEdges);
        
            % collect slit positions if available
            if isfield(allTraj(t), 'slitX_norm')
                slitVals(end+1) = allTraj(t).slitX_norm; %#ok<AGROW>
            end
        end
        
        Hraw{d,g} = struct('data', Hk, 'slitVals', slitVals);
        nReaches(d,g) = numel(allTraj);

    end
end

% -------- derived sets --------
Hnorm = cell(size(Hraw));
Hprob = cell(size(Hraw));

groupMax = zeros(1, nGroups);
for g = 1:nGroups
    vals = [];
    for d = 1:nDays
        if ~isempty(Hnorm{d,g})
            % unwrap struct if needed
            if isstruct(Hnorm{d,g})
                vals = [vals; Hnorm{d,g}.data(:)];
            else
                vals = [vals; Hnorm{d,g}(:)];
            end
        end
    end
    if ~isempty(vals)
        groupMax(g) = max(vals);
    else
        groupMax(g) = 0;
    end
end

for d = 1:nDays
    for g = 1:nGroups
        Hk = Hraw{d,g};   % struct with fields .data and .slitVals
        if isempty(Hk), continue; end

        % norm per reach
        if nReaches(d,g) > 0
            Hnorm{d,g} = struct('data', Hk.data ./ nReaches(d,g), ...
                                'slitVals', Hk.slitVals);
        else
            Hnorm{d,g} = Hk;
        end

        % probability density
        s = sum(Hk.data(:));
        if s > 0
            Hprob{d,g} = struct('data', Hk.data ./ s, ...
                                'slitVals', Hk.slitVals);
        else
            Hprob{d,g} = Hk;
        end
    end
end

[GG, DD] = ndgrid(string(uniqueGroups), string(uniqueDays));  % group-major
labelsGrid = strcat(GG, " / ", DD);
labelsGrid = labelsGrid(:)';

% -------- Global heatmaps (grid: rows=test_day, cols=group) --------
baseName = sprintf('RAW_%s_GlobalHeatmap_%s_%s', upper(viewType(1)), labelName, lower(groupBy));

% NORM
Hflat = reshape(Hnorm,1,[]);
plotHeatmapSet(Hflat, labelsGrid, viewType, figDir, baseName, 'HM', P, groupBy, [nDays nGroups], 'pergroup');

% % PROB
% Hflat = reshape(Hprob,1,[]);
% plotHeatmapSet(Hflat, labelsGrid, viewType, figDir, baseName, 'PROB', P, groupBy, [nDays nGroups], 'pergroup');
end


function plotHeatmapSet(Hcell, labels, viewType, figDir, outName, tag, P, groupBy, varargin)
% --- default groupBy ---
if nargin < 8 || isempty(groupBy)
    groupBy = "label"; % fallback
end
cmap = load('C:\Users\juk4004\Documents\MATLAB\myColormaps.mat', 'jet2'); 
jet2 = cmap.jet2;
% --- reorder labels (Success first, then Errors alphabetically) ---
isSuccess = strcmpi(labels, "Success");   % case-insensitive
isError   = startsWith(labels, "Error", 'IgnoreCase', true);
others    = ~(isSuccess | isError);

if ~any(isSuccess | isError)
    % Fallback: keep original order
    warning('plotHeatmapSet: no Success/Error labels found, keeping original order');
    % do nothing, labels and Hcell stay as they are
else
    successLabels = labels(isSuccess);
    errorLabels   = sort(labels(isError));
    otherLabels   = labels(others);

    labels = [successLabels, errorLabels, otherLabels];

    % Reorder Hcell to match new label order
    newIdx = [find(isSuccess), find(isError), find(others)];
    Hcell  = Hcell(newIdx);
end


% grid size
if nargin >= 9 && ~isempty(varargin) && ~isempty(varargin{1}) && isnumeric(varargin{1})
    nRows = varargin{1}(1);
    nCols = varargin{1}(2);
    varargin(1) = []; % pop it off so later args shift down
else
    nLabels = numel(labels);
    nCols = min(3, nLabels);
    nRows = ceil(nLabels/nCols);
end

% scaling mode
if ~isempty(varargin) && ischar(varargin{1}) && strcmpi(varargin{1}, 'pergroup')
    scaleMode = 'pergroup';
else
    scaleMode = 'global';
end

% compute global/group maxima for caxis scaling
if strcmp(scaleMode, 'pergroup')
    groupMax = zeros(1, nRows);
    for r = 1:nRows
        vals = [];
        for c = 1:nCols
            idx = (r-1)*nCols + c;
            if idx <= numel(Hcell) && ~isempty(Hcell{idx})
                if isstruct(Hcell{idx})
                    vals = [vals; Hcell{idx}.data(:)];
                else
                    vals = [vals; Hcell{idx}(:)];
                end
            end
        end
        if ~isempty(vals)
            groupMax(r) = max(vals);
        end
    end
else
    nonempty = Hcell(~cellfun('isempty',Hcell));
    if all(cellfun(@isstruct, nonempty))
        groupMax = max(cellfun(@(m) max(m.data(:)), nonempty));
    else
        groupMax = max(cellfun(@(m) max(m(:)), nonempty));
    end
end


% Each subplot ~250 px wide, ~250 px tall
figW = 250 * nCols;
figH = 250 * nRows;

f = figure('Visible','off','Color','w', ...
    'Name', sprintf('%s Heatmaps (%s)', outName, tag), ...
    'Position', [100 100 figW figH]);

for k = 1:numel(labels)
     % compute row, col in column-major order
    r = mod(k-1, nRows) + 1;          % row index
    c = floor((k-1)/nRows) + 1;       % col index

    subplot(nRows, nCols, (r-1)*nCols + c);

    if isempty(Hcell{k})
        axis off; continue;
    end


    % unwrap struct vs numeric
    if isstruct(Hcell{k})
        Hdata = Hcell{k}.data;
    else
        Hdata = Hcell{k};
    end

    % Pad Hdata by repeating last row and col
    Hpad = [Hdata, Hdata(:,end)];      % add last column again
    Hpad = [Hpad; Hpad(end,:)];        % add last row again
    
    [X,Y] = meshgrid(P.xEdges, P.yEdges);   % 51x51 if Hdata is 50x50
    pcolor(X, Y, Hpad);

    shading flat; % avoid grid lines
    
    axis xy; set(gca,'YDir','reverse');
    xlim(P.xlim); ylim(P.ylim);
    colormap(jet2); colorbar;
    
    % scaling
    [r,c] = ind2sub([nRows nCols], k);
    if strcmp(scaleMode, 'pergroup')
        if groupMax(r) > 0, caxis([0 groupMax(r)]); end
    else
        if groupMax > 0, caxis([0 groupMax]); end
    end
    
    title(sprintf('%s - %s', tag, labels(k)), 'Interpreter','none'); hold on;
    
    % pellet marker
    scatter(0,0,60,'o','MarkerEdgeColor','w','MarkerFaceColor','w','LineWidth',1.25);
    
    % slit line (Side view only)
    if P.showSlit && isstruct(Hcell{k}) && isfield(Hcell{k},'slitVals')
        mSlit = mean(Hcell{k}.slitVals,'omitnan');
        if ~isnan(mSlit)
            plot([mSlit mSlit], get(gca,'YLim'), ':','LineWidth',1.5,'Color',[0.7 0.7 0.7]);
        end
    end

end

outDir= fullfile(figDir, char(groupBy), viewType, tag);
if ~exist(outDir, 'dir'), mkdir(outDir); end
savename = fullfile(outDir, outName);
set(f, 'PaperUnits', 'inches', 'PaperPosition', [0 0 nCols*3 nRows*3]); 
set(f, 'Color', 'w');          % figure background

export_fig(savename, '-png','-pdf', '-r300', f);

close(f);
end

function plotDifferenceHeatmaps(allResults, uniqueGroups, uniqueDays, uniqueLabels, uniqueBroadLabels, viewType, figDir, groupBy)
% Plot difference heatmaps (Drug - Baseline) for broadLabel, label, and global levels
%
% Debugging version: prints info about groups, labels, counts, and skips.

P = getViewParams(viewType);

dayBaseline = "Baseline";
dayDrug     = "Drug";
cmap = load('C:\Users\juk4004\Documents\MATLAB\myColormaps.mat', 'jet2');
jet2 = cmap.jet2;

% normalize label inputs
if ischar(uniqueLabels) || isstring(uniqueLabels)
    uniqueLabels = string(uniqueLabels);
end
if ischar(uniqueBroadLabels) || isstring(uniqueBroadLabels)
    uniqueBroadLabels = cellstr(uniqueBroadLabels);
end

% decide which set of categories to use
switch lower(groupBy)
    case 'label'
        labelSet  = uniqueLabels;
        fieldName = 'label';

        % Custom reordering: "Success" first, then Errors alphabetically
        isSuccess     = strcmp(labelSet, "Success");
        isError       = startsWith(labelSet, "Error");
        successLabels = labelSet(isSuccess);
        errorLabels   = sort(labelSet(isError));

        % force row orientation to avoid horzcat dimension mismatch
        successLabels = successLabels(:).';
        errorLabels   = errorLabels(:).';

        % Preserve "Success" first, then sorted Errors
        labelSet = [successLabels, errorLabels];

    case 'broadlabel'
        labelSet  = uniqueBroadLabels;
        fieldName = 'broadLabel';

        % For broadLabel: "Success" first if present, then the rest sorted
        isSuccess     = strcmp(labelSet, "Success");
        successLabels = labelSet(isSuccess);
        rest          = labelSet(~isSuccess);

        successLabels = successLabels(:).';
        rest          = rest(:).';

        labelSet = [successLabels, sort(rest)];

    otherwise
        error('groupBy must be ''label'' or ''broadLabel''');
end

% Prepare storage
heatmapsBase = cell(numel(uniqueGroups), numel(labelSet));
heatmapsDrug = cell(numel(uniqueGroups), numel(labelSet));

% -------- Build per-group, per-label histograms --------
for g = 1:numel(uniqueGroups)
    grpName = uniqueGroups(g);

    for l = 1:numel(labelSet)
        labelName = labelSet{l};

        % Initialize
        Hbase = zeros(numel(P.yEdges)-1, numel(P.xEdges)-1);
        Hdrug = zeros(size(Hbase));
        slitBase = [];
        slitDrug = [];
        countBase = 0;
        countDrug = 0;

        % Walk through results
        for i = 1:numel(allResults)
            R = allResults(i);
            if string(R.group) ~= string(grpName), continue; end

            viewField = lower(viewType);
            if ~isfield(R, viewField) || ~isfield(R.(viewField), 'trajectories')
                continue;
            end
            trajArray = R.(viewField).trajectories;
            if isempty(trajArray), continue; end

            selIdx = strcmp(string({trajArray.(fieldName)}), string(labelName));
            trajArray = trajArray(selIdx);
            if isempty(trajArray), continue; end

            if string(R.test_day) == dayBaseline
                for t = 1:numel(trajArray)
                    xt = trajArray(t).traj.x;
                    yt = trajArray(t).traj.y;
                    if isempty(xt) || isempty(yt), continue; end
                    Hk = histcounts2(yt, xt, P.yEdges, P.xEdges);
                    Hbase = Hbase + Hk;
                    countBase = countBase + 1;
                    if isfield(trajArray(t).traj, 'slitX_norm')
                        slitBase(end+1) = trajArray(t).traj.slitX_norm; %#ok<AGROW>
                    end
                end
            elseif string(R.test_day) == dayDrug
                for t = 1:numel(trajArray)
                    xt = trajArray(t).traj.x;
                    yt = trajArray(t).traj.y;
                    if isempty(xt) || isempty(yt), continue; end
                    Hk = histcounts2(yt, xt, P.yEdges, P.xEdges);
                    Hdrug = Hdrug + Hk;
                    countDrug = countDrug + 1;
                    if isfield(trajArray(t).traj, 'slitX_norm')
                        slitDrug(end+1) = trajArray(t).traj.slitX_norm; %#ok<AGROW>
                    end
                end
            end
        end

        % Normalize
        if countBase > 0, Hbase = Hbase / countBase; end
        if countDrug > 0, Hdrug = Hdrug / countDrug; end

        % Pack into structs for later use
        heatmapsBase{g,l} = struct('data', Hbase, 'slitVals', slitBase);
        heatmapsDrug{g,l} = struct('data', Hdrug, 'slitVals', slitDrug);
    end
end

% -------- Compute and plot differences --------
for g = 1:numel(uniqueGroups)
    grpName = string(uniqueGroups(g));

    % Precompute shared scale across all labels for Baseline/Drug
    allMaxVals = [];
    for l = 1:numel(labelSet)
        tmpBase = heatmapsBase{g, l}.data;
        tmpDrug = heatmapsDrug{g, l}.data;
        allMaxVals = [allMaxVals; tmpBase(:); tmpDrug(:)];
    end
    sharedMaxVal = max(allMaxVals);
    if sharedMaxVal == 0, sharedMaxVal = 1; end

    % ===== 1) Individual per-label figs =====
    for l = 1:numel(labelSet)
        labelName = string(labelSet{l});

        % Peel struct into numeric + slit arrays
        tmp     = heatmapsBase{g, l};
        Hbase   = tmp.data;
        slitBase = tmp.slitVals;

        tmp     = heatmapsDrug{g, l};
        Hdrug   = tmp.data;
        slitDrug = tmp.slitVals;

        diffHeatmap = Hdrug - Hbase;

        % Skip if trivial
        if all(diffHeatmap(:) == 0)
            fprintf('    WARNING: diffHeatmap all zeros for group=%s, label=%s\n', char(grpName), char(labelName));
            continue;
        end

        % shared scale for baseline & drug
        maxVal = max([Hbase(:); Hdrug(:)]);
        if maxVal == 0, maxVal = 1; end

        % Custom diverging colormap: blue (#2596be) → white → red (#be2525)
        nColors = 256;
        mid = round(nColors/2);
        blueRGB = [37 150 190] / 255;  % #2596be
        redRGB  = [190 37 37] / 255;   % #be2525

        blue2white = [linspace(blueRGB(1),1,mid)', ...
                      linspace(blueRGB(2),1,mid)', ...
                      linspace(blueRGB(3),1,mid)'];
        white2red = [linspace(1,redRGB(1),mid)', ...
                     linspace(1,redRGB(2),mid)', ...
                     linspace(1,redRGB(3),mid)'];
        cmapDiff = [blue2white; white2red];

        % figure with 3 panels
        figure('Visible','off');
        tiledlayout(1,3);

        [X, Y] = meshgrid(P.xEdges, P.yEdges);

        % Baseline
        nexttile;
        Hpad = [Hbase, Hbase(:,end)];
        Hpad = [Hpad; Hpad(end,:)];
        pcolor(X, Y, Hpad);
        shading flat;
        axis xy; set(gca,'YDir','reverse');
        colormap(gca, jet2); colorbar; caxis([0 maxVal]);
        if P.showSlit
            mSlitBase = mean(slitBase, 'omitnan'); %#ok<NASGU>
        end
        title('Baseline'); 

        % Drug
        nexttile;
        Hpad = [Hdrug, Hdrug(:,end)];
        Hpad = [Hpad; Hpad(end,:)];
        pcolor(X, Y, Hpad);
        shading flat;
        axis xy; set(gca,'YDir','reverse');
        colormap(gca, jet2); colorbar; caxis([0 maxVal]);
        if P.showSlit
            mSlitDrug = mean(slitDrug, 'omitnan'); %#ok<NASGU>
        end
        title('Drug'); 

        % Difference
        nexttile;
        Hpad = [diffHeatmap, diffHeatmap(:,end)];
        Hpad = [Hpad; Hpad(end,:)];
        pcolor(X, Y, Hpad);
        shading flat;
        axis xy; set(gca,'YDir','reverse');
        colormap(gca, cmapDiff); colorbar;
        clim = max(abs(diffHeatmap(:))); if clim==0, clim=1; end
        caxis([-clim clim]);
        title('Drug - Baseline'); 

        % overlay average slit (if side view)
        if P.showSlit
            allSlits = [slitBase, slitDrug];
            if ~isempty(allSlits)
                mSlit = mean(allSlits, 'omitnan');
                hold on;
                plot([mSlit mSlit], get(gca,'YLim'), ':', 'LineWidth', 1.5, 'Color', [0.7 0.7 0.7]);
                hold off;
            end
        end

        sgtitle(sprintf('Group: %s | Label: %s | View: %s', grpName, labelName, viewType));

        outDir = fullfile(figDir, 'DifferenceHeatmaps', groupBy, char(viewType));
        if ~exist(outDir, 'dir'), mkdir(outDir); end

        savename = fullfile(outDir, sprintf('DiffHeatmap_%s_%s_%s', char(grpName), char(labelName), viewType));
        set(gcf, 'Color', 'w');
        export_fig(savename, '-pdf', '-png', '-r300', gcf);
        close;
    end

    % ===== 2) Group-level combined fig =====
    figure('Visible','off'); tiledlayout(3, numel(labelSet), 'TileSpacing','compact');

    % Reuse the same diverging cmap for consistency
    nColors = 256;
    mid = round(nColors/2);
    blueRGB = [37 150 190] / 255;  % #2596be
    redRGB  = [190 37 37] / 255;   % #be2525
    blue2white = [linspace(blueRGB(1),1,mid)', ...
                  linspace(blueRGB(2),1,mid)', ...
                  linspace(blueRGB(3),1,mid)'];
    white2red = [linspace(1,redRGB(1),mid)', ...
                 linspace(1,redRGB(2),mid)', ...
                 linspace(1,redRGB(3),mid)'];
    cmapDiff = [blue2white; white2red];

    for l = 1:numel(labelSet)
        labelName = string(labelSet{l});

        % Peel struct into numeric + slit arrays
        tmp      = heatmapsBase{g, l};
        Hbase    = tmp.data;
        tmp      = heatmapsDrug{g, l};
        Hdrug    = tmp.data;

        diffHeatmap = Hdrug - Hbase;

        maxVal = sharedMaxVal;
        clim = max(abs(diffHeatmap(:)));    if clim==0,   clim=1;   end

        [X, Y] = meshgrid(P.xEdges, P.yEdges);

        % row 1 = Baseline
        nexttile(l);
        Hpad = [Hbase, Hbase(:,end)];
        Hpad = [Hpad; Hpad(end,:)];
        pcolor(X, Y, Hpad);
        shading flat;
        axis xy; set(gca,'YDir','reverse');
        colormap(gca, jet2); colorbar; caxis([0 maxVal]);
        if l==1, ylabel('Baseline'); end
        title(labelName);

        % row 2 = Drug
        nexttile(l+numel(labelSet));
        Hpad = [Hdrug, Hdrug(:,end)];
        Hpad = [Hpad; Hpad(end,:)];
        pcolor(X, Y, Hpad);
        shading flat;
        axis xy; set(gca,'YDir','reverse');
        colormap(gca, jet2); colorbar; caxis([0 maxVal]);
        if l==1, ylabel('Drug'); end

        % row 3 = Difference
        nexttile(l+2*numel(labelSet));
        Hpad = [diffHeatmap, diffHeatmap(:,end)];
        Hpad = [Hpad; Hpad(end,:)];
        pcolor(X, Y, Hpad);
        shading flat;
        axis xy; set(gca,'YDir','reverse');
        colormap(gca, cmapDiff); colorbar; caxis([-clim clim]);
        if l==1, ylabel('Drug - Baseline'); end
    end

    sgtitle(sprintf('Group: %s | View: %s (%s)', grpName, viewType, groupBy));

    outDir = fullfile(figDir, 'DifferenceHeatmaps', groupBy, char(viewType));
    if ~exist(outDir, 'dir'), mkdir(outDir); end

    savename = fullfile(outDir, sprintf('DiffHeatmapSet_ALLLABELS_%s_%s', grpName, viewType));
    set(gcf, 'Color', 'w');
    export_fig(savename, '-pdf', '-png', '-r300', gcf);

    close; % combined fig
end

end

function plotGlobalAndDifferenceHeatmaps(allResults, uniqueGroups, viewType, figDir)
% Plot per-group global heatmaps (Baseline, Drug, Difference) in one figure
% with consistent scaling, colormaps, and slit overlays.

P = getViewParams(viewType);
dayBaseline = "Baseline";
dayDrug     = "Drug";
cmap = load('C:\Users\juk4004\Documents\MATLAB\myColormaps.mat', 'jet2'); 
jet2 = cmap.jet2;

for g = 1:numel(uniqueGroups)
    grpName = string(uniqueGroups(g));

    % Initialize
    Hbase = zeros(numel(P.yEdges)-1, numel(P.xEdges)-1);
    Hdrug = zeros(size(Hbase));
    slitBase = [];
    slitDrug = [];
    countBase = 0;
    countDrug = 0;

    % Collect all reaches for this group
    for i = 1:numel(allResults)
        R = allResults(i);
        if string(R.group) ~= grpName
            continue;
        end

        viewField = lower(viewType);
        if ~isfield(R, viewField) || ~isfield(R.(viewField), 'trajectories')
            continue;
        end
        trajArray = R.(viewField).trajectories;
        if isempty(trajArray), continue; end

        thisDay = string(R.test_day);
        if thisDay == dayBaseline
            for t = 1:numel(trajArray)
                xt = trajArray(t).traj.x;
                yt = trajArray(t).traj.y;
                if isempty(xt) || isempty(yt), continue; end
                Hk = histcounts2(yt, xt, P.yEdges, P.xEdges);
                Hbase = Hbase + Hk;
                countBase = countBase + 1;
                if isfield(trajArray(t).traj,'slitX_norm')
                    slitBase(end+1) = trajArray(t).traj.slitX_norm; %#ok<AGROW>
                end
            end
        elseif thisDay == dayDrug
            for t = 1:numel(trajArray)
                xt = trajArray(t).traj.x;
                yt = trajArray(t).traj.y;
                if isempty(xt) || isempty(yt), continue; end
                Hk = histcounts2(yt, xt, P.yEdges, P.xEdges);
                Hdrug = Hdrug + Hk;
                countDrug = countDrug + 1;
                if isfield(trajArray(t).traj,'slitX_norm')
                    slitDrug(end+1) = trajArray(t).traj.slitX_norm; %#ok<AGROW>
                end
            end
        end
    end

    % Normalize
    if countBase > 0, Hbase = Hbase / countBase; end
    if countDrug > 0, Hdrug = Hdrug / countDrug; end
    diffMap = Hdrug - Hbase;

    % Shared scale for Baseline/Drug
    maxVal = max([Hbase(:); Hdrug(:)]);
    if maxVal == 0, maxVal = 1; end

    % Custom red-white-blue colormap for differences
    n = 128;
    blue = [37 150 190] / 255;  % #2596be
    red  = [190 37 37] / 255;   % #be2525
    white = [1 1 1];
    cmapDiff = [linspace(blue(1),white(1),n)' linspace(blue(2),white(2),n)' linspace(blue(3),white(3),n)';
                linspace(white(1),red(1),n)'  linspace(white(2),red(2),n)'  linspace(white(3),red(3),n)'];

    % Create one figure with 3 panels
    figure('Visible','off');
    tiledlayout(1,3);

    [X, Y] = meshgrid(P.xEdges, P.yEdges);

    % Panel 1: Baseline
    nexttile;
    Hpad = [Hbase, Hbase(:,end)];
    Hpad = [Hpad; Hpad(end,:)];
    pcolor(X, Y, Hpad);
    shading flat;
    axis xy; set(gca,'YDir','reverse');
    colorbar; colormap(gca, jet2);
    caxis([0 maxVal]);
    title('Baseline');
    if P.showSlit && ~isempty(slitBase)
        mSlitBase = mean(slitBase,'omitnan');
        plot([mSlitBase mSlitBase], get(gca,'YLim'), ':','LineWidth',1.5,'Color',[0.7 0.7 0.7]);
    end

    % Panel 2: Drug
    nexttile;
    Hpad = [Hdrug, Hdrug(:,end)];
    Hpad = [Hpad; Hpad(end,:)];
    pcolor(X, Y, Hpad);
        shading flat;
    axis xy; set(gca,'YDir','reverse');
    colorbar; colormap(gca, jet2);
    caxis([0 maxVal]);
    title('Drug');
    if P.showSlit && ~isempty(slitDrug)
        mSlitDrug = mean(slitDrug,'omitnan');
        plot([mSlitDrug mSlitDrug], get(gca,'YLim'), ':','LineWidth',1.5,'Color',[0.7 0.7 0.7]);
    end

    % Panel 3: Difference
    nexttile;
    Hpad = [diffMap, diffMap(:,end)];
    Hpad = [Hpad; Hpad(end,:)];
    pcolor(X, Y, Hpad);    
    shading flat;
    axis xy; set(gca,'YDir','reverse');
    colorbar; colormap(gca, cmapDiff);
    clim = max(abs(diffMap(:))); if clim==0, clim=1; end
    caxis([-clim clim]);
    title('Drug - Baseline');
    if P.showSlit
        allSlits = [slitBase slitDrug];
        if ~isempty(allSlits)
            mSlit = mean(allSlits,'omitnan');
            plot([mSlit mSlit], get(gca,'YLim'), ':','LineWidth',1.5,'Color',[0.7 0.7 0.7]);
        end
    end

    sgtitle(sprintf('Group: %s | View: %s', grpName, viewType));

    % Save per-group figure
    outDir = fullfile(figDir, 'DifferenceHeatmaps', char(viewType));
    if ~exist(outDir,'dir'), mkdir(outDir); end
    savename = fullfile(outDir, sprintf('AllReaches_%s_%s', grpName, viewType));
    set(gcf, 'Color', 'w');          % figure background
    export_fig(savename, '-pdf', '-png', '-r300', gcf);
    close;
end
end
