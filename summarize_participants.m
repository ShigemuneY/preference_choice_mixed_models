function summarize_participants
%SUMMARIZE_PARTICIPANTS Participant-level summary of the preference and choice tasks.
%
%   Computes, for each participant and distance condition (far, medium, near),
%   the descriptive measures reported in Table 2, and for each participant the
%   rating-spread indices (within- and between-category SD). The output is merged with the questionnaire
%   scores and used for the correlations and t-test (run in SPSS).
%
%   Per participant x condition
%     nTrials    number of choice trials
%     nTies      trials in which the two items had identical ratings
%                (excluded from ConsPct, MeanDiff and MeanRT)
%     nAnalysed  nTrials - nTies
%     ConsPct    % of analysed trials in which the higher-rated item was chosen
%     MeanDiff   mean actual rating difference of the analysed trials
%     MeanRT     mean choice response time of the analysed trials (ms)
%   Per participant (all 144 ratings of the preference task)
%     WithinSD   SD of the 12 ratings within each category, averaged over the 12 categories
%     BetweenSD  SD of the 12 category mean ratings
%
%   Input   Input/*_Analysis02.xlsx  trial files, one per participant (see README)
%           Questionnaire.xlsx       questionnaire scores (see README)
%   Output  Results/participant_summary.xlsx
%             Long        one row per participant x condition
%             Wide        one row per participant, with questionnaire scores
%             LabelCoding which code of the distance label is far / medium / near
%           Results/participant_summary_log.txt
%
%   Run from the folder that contains Input/ and Questionnaire.xlsx.

%% ===================== SETTINGS =====================================
CFG.trialDir     = fullfile(pwd, 'Input');
CFG.trialPattern = '*_Analysis02.xlsx';
CFG.trialSheet   = 'Sheet1';
CFG.questFile    = fullfile(pwd, 'Questionnaire.xlsx');
CFG.questSheet   = 'Sheet1';
CFG.resultDir    = fullfile(pwd, 'Results');
CFG.nTrials      = 72;               % choice trials per participant
CFG.condVar      = 'Preference03';   % column coding the distance condition of each pair
%% ====================================================================

if ~exist(CFG.resultDir, 'dir'); mkdir(CFG.resultDir); end
logFile = fullfile(CFG.resultDir, 'participant_summary_log.txt');
outFile = fullfile(CFG.resultDir, 'participant_summary.xlsx');
if exist(logFile, 'file'); delete(logFile); end
if exist(outFile, 'file'); delete(outFile); end
warning('off', 'MATLAB:xlswrite:AddSheet');
diary(logFile);
cleanupObj = onCleanup(@() close_log(logFile)); %#ok<NASGU>
feature('hotlinks', false);
fprintf('summarize_participants  %s\n\n', datestr(now));

%% ---- questionnaire ------------------------------------------------------
Q = read_questionnaire(CFG.questFile, CFG.questSheet);
idDigits = regexprep(Q.ID, '\D', '');

%% ---- trial files --------------------------------------------------------
files = dir(fullfile(CFG.trialDir, CFG.trialPattern));
if isempty(files); error('No files matching %s in %s', CFG.trialPattern, CFG.trialDir); end
D = table();   % one row per choice trial
R = table();   % rating spread, one row per participant
for f = 1:numel(files)
    T = readtable(fullfile(CFG.trialDir, files(f).name), 'Sheet', CFG.trialSheet);
    need = {'Consistensy', 'Distance', 'Category', 'rt', 'Preference', CFG.condVar};
    if ~all(ismember(need, T.Properties.VariableNames))
        error('%s: expected columns not found. Columns read: %s', files(f).name, ...
            strjoin(T.Properties.VariableNames, ', '));
    end
    qi = match_subject(files(f).name, T, idDigits);
    if isempty(qi); warning('No questionnaire match for %s - skipped.', files(f).name); continue; end

    % choice trials
    P = one_row_per_trial(T, CFG.nTrials, files(f).name);
    n = height(P);
    D = [D; table(repmat(Q.ID(qi), n, 1), P.(CFG.condVar), P.Consistensy, P.Distance, P.rt, ...
        'VariableNames', {'Subj', 'Label', 'ConsCode', 'Diff', 'RT'})]; %#ok<AGROW>

    % spread of the preference ratings (all 144 items, one row per item)
    r = T.Preference;
    if any(~ismember(r, 1:7)); warning('%s: ratings outside 1-7 found.', files(f).name); end
    itemCat = to_cellstr(T.Category);
    cats = unique(itemCat);
    cSD = zeros(numel(cats), 1); cM = zeros(numel(cats), 1);
    for k = 1:numel(cats)
        rc = r(strcmp(itemCat, cats{k}));
        cSD(k) = std(rc); cM(k) = mean(rc);
    end
    R = [R; table(Q.ID(qi), numel(r), mean(cSD), std(cM), ...
        'VariableNames', {'ID', 'nRatedItems', 'WithinSD', 'BetweenSD'})]; %#ok<AGROW>
    fprintf('  %-45s -> %s (%d trials)\n', files(f).name, Q.ID{qi}, n);
end
fprintf('\n');

%% ---- far / medium / near -------------------------------------------------
[D.Cond, LabelCoding] = assign_conditions(D.Label, D.Diff, CFG.condVar);
conds = {'far', 'medium', 'near'};

%% ---- per participant x condition ----------------------------------------
% ConsCode: 1 = higher-rated item chosen, 2 = lower-rated item chosen, 3 = tied ratings
subj = unique(D.Subj, 'stable');
Long = table();
for s = 1:numel(subj)
    for c = 1:3
        i  = strcmp(D.Subj, subj{s}) & strcmp(D.Cond, conds{c});
        iA = i & D.ConsCode ~= 3;
        Long = [Long; table(subj(s), conds(c), sum(i), sum(i & D.ConsCode == 3), sum(iA), ...
            100 * mean(D.ConsCode(iA) == 1), mean(D.Diff(iA)), mean(D.RT(iA)), ...
            'VariableNames', {'Subj','Cond','nTrials','nTies','nAnalysed','ConsPct','MeanDiff','MeanRT'})]; %#ok<AGROW>
    end
end

%% ---- wide format + questionnaire -----------------------------------------
% columns grouped by measure: ConsPct_far, ConsPct_medium, ConsPct_near, ConsPct_all, MeanDiff_far, ...
Wide = table(subj, 'VariableNames', {'ID'});
vars = {'ConsPct','MeanDiff','MeanRT','nTrials','nTies','nAnalysed'};
for v = 1:numel(vars)
    for c = 1:3
        x = zeros(numel(subj), 1);
        for s = 1:numel(subj)
            x(s) = Long.(vars{v})(strcmp(Long.Subj, subj{s}) & strcmp(Long.Cond, conds{c}));
        end
        Wide.([vars{v} '_' conds{c}]) = x;
    end
    % all conditions combined
    x = zeros(numel(subj), 1);
    for s = 1:numel(subj)
        i = strcmp(D.Subj, subj{s}); iA = i & D.ConsCode ~= 3;
        switch vars{v}
            case 'ConsPct',   x(s) = 100 * mean(D.ConsCode(iA) == 1);
            case 'MeanDiff',  x(s) = mean(D.Diff(iA));
            case 'MeanRT',    x(s) = mean(D.RT(iA));
            case 'nTrials',   x(s) = sum(i);
            case 'nTies',     x(s) = sum(i & D.ConsCode == 3);
            case 'nAnalysed', x(s) = sum(iA);
        end
    end
    Wide.([vars{v} '_all']) = x;
end
Wide = innerjoin(Wide, R, 'Keys', 'ID');
Wide = innerjoin(Q, Wide, 'Keys', 'ID');

%% ---- checks -----------------------------------------------------------------
if any(Wide.nRatedItems ~= 144)
    fprintf('NOTE: some participants do not have 144 rated items (see nRatedItems).\n');
end
fprintf('Participants in the merged table: %d (questionnaire %d, trial files %d)\n', ...
    height(Wide), height(Q), numel(subj));
missingQ = setdiff(Q.ID, subj);
if ~isempty(missingQ); fprintf('Questionnaire IDs without trial data: %s\n', strjoin(missingQ', ', ')); end
fprintf('\nWithinSD  M = %.2f (SD %.2f); BetweenSD M = %.2f (SD %.2f)\n\n', ...
    mean(Wide.WithinSD), std(Wide.WithinSD), mean(Wide.BetweenSD), std(Wide.BetweenSD));

fprintf('Condition means across participants (Table 2):\n');
for c = 1:3
    i = strcmp(Long.Cond, conds{c});
    fprintf('  %-6s ConsPct %.2f (SD %.2f)  MeanDiff %.2f (SD %.2f)  MeanRT %.1f (SD %.1f)  nAnalysed %.2f (SD %.2f)  ties %d\n', ...
        conds{c}, mean(Long.ConsPct(i)), std(Long.ConsPct(i)), mean(Long.MeanDiff(i)), std(Long.MeanDiff(i)), ...
        mean(Long.MeanRT(i)), std(Long.MeanRT(i)), mean(Long.nAnalysed(i)), std(Long.nAnalysed(i)), sum(Long.nTies(i)));
end
fprintf('\n');

%% ---- write ------------------------------------------------------------------
writetable(Long, outFile, 'Sheet', 'Long');
writetable(Wide, outFile, 'Sheet', 'Wide');
writetable(LabelCoding, outFile, 'Sheet', 'LabelCoding');
fprintf('Done. Results: %s\n', outFile);
end

%% ========================= local functions ===============================

%% ---- data helpers ----------------------------------------------------------

function close_log(logFile)
%CLOSE_LOG Stop the diary and convert the log file to UTF-8.
%   The diary is written in the system encoding (Shift_JIS on Japanese Windows).
%   The file is converted to UTF-8 with BOM, and MATLAB's HTML formatting tags
%   (<strong>, <a href>) are removed so that the log reads as plain text.

diary('off');
feature('hotlinks', true);   % restore normal Command Window display
if ~exist(logFile, 'file'); return; end
fid = fopen(logFile, 'r'); bytes = fread(fid, '*uint8')'; fclose(fid);
txt = native2unicode(bytes, 'Shift_JIS');
txt = regexprep(txt, '</?strong>', '');
txt = regexprep(txt, '<a href="[^"]*"[^>]*>(.*?)</a>', '$1');
fid = fopen(logFile, 'w');
fwrite(fid, uint8([239 187 191]));
fwrite(fid, unicode2native(txt, 'UTF-8'));
fclose(fid);
end

function Q = read_questionnaire(file, sheet)
%READ_QUESTIONNAIRE Read questionnaire scores (one row per participant).
%   The sheet is read as raw cells. The header row is the first row that
%   contains both 'ID' and 'ASRS'; columns are then selected by header name:
%     ID, Age, Sex (F/M), BIS, BAS, SSS (SSS-AE total),
%     A (ASRS Part A), B (ASRS Part B), ASRS (ASRS total)
%   Optional subscale columns (Drive, Rew Res, Fun Seek, TAS, Dis, ES) are read
%   if present. If TAS, Dis and ES are present, their sum is checked against SSS.

[~, ~, raw] = xlsread(file, sheet);
raw(cellfun(@(x) isnumeric(x) && isscalar(x) && isnan(x), raw)) = {''};
txt = cellfun(@(x) strtrim(num2str(x)), raw, 'UniformOutput', false);
hdrRow = find(any(strcmp(txt, 'ID'), 2) & any(strcmp(txt, 'ASRS'), 2), 1);
if isempty(hdrRow); error('Header row with "ID" and "ASRS" not found in %s (%s).', file, sheet); end
hdr = txt(hdrRow, :);
body = raw(hdrRow+1:end, :);
idCol = find(strcmp(hdr, 'ID'), 1);
body = body(cellfun(@(x) ischar(x) && ~isempty(strtrim(x)), body(:, idCol)), :);

% header in the sheet -> variable name used in the scripts (1 = required)
map = {'ID','ID',1; 'Age','Age',1; 'Sex','Sex',1; 'BIS','BIS',1; 'BAS','BAS',1; ...
       'Drive','Drive',0; 'Rew Res','RewRes',0; 'Fun Seek','FunSeek',0; ...
       'TAS','TAS',0; 'Dis','Dis',0; 'ES','ES',0; 'SSS','SSS_Total',1; ...
       'A','ASRS_A',1; 'B','ASRS_B',1; 'ASRS','ASRS_Total',1};
Q = table();
for k = 1:size(map, 1)
    col = find(strcmp(hdr, map{k, 1}), 1);
    if isempty(col)
        if map{k, 3}; error('Column "%s" not found in the header row of %s.', map{k, 1}, sheet); end
        continue
    end
    v = body(:, col);
    if any(strcmp(map{k, 2}, {'ID', 'Sex'}))
        Q.(map{k, 2}) = cellfun(@(x) strtrim(num2str(x)), v, 'UniformOutput', false);
    else
        Q.(map{k, 2}) = cellfun(@(x) str2double(num2str(x)), v);
    end
end
if all(ismember({'TAS','Dis','ES'}, Q.Properties.VariableNames)) && any(Q.SSS_Total ~= Q.TAS + Q.Dis + Q.ES)
    warning('SSS differs from TAS + Dis + ES for: %s', strjoin(Q.ID(Q.SSS_Total ~= Q.TAS + Q.Dis + Q.ES)', ', '));
end
fprintf('Questionnaire: %d participants read from %s (%s), header row %d\n\n', height(Q), file, sheet, hdrRow);
end

function qi = match_subject(fname, T, idDigits)
%MATCH_SUBJECT Find the questionnaire row that belongs to a trial file.
%   First, the digits of each questionnaire ID are searched for in the file
%   name. If this does not give exactly one match, the subjectID column of the
%   trial file (if present) is compared with the digits of the IDs.
%   Returns [] if no unique match is found.

qi = find(cellfun(@(d) ~isempty(d) && ~isempty(strfind(fname, d)), idDigits)); %#ok<STREMP>
if numel(qi) == 1; return; end
qi = [];
if ismember('subjectID', T.Properties.VariableNames)
    sid = T.subjectID(1);
    if iscell(sid); sid = str2double(regexprep(sid{1}, '\D', '')); end
    qi = find(str2double(idDigits) == sid);
    if numel(qi) ~= 1; qi = []; end
end
end

function P = one_row_per_trial(T, nTrials, fname)
%ONE_ROW_PER_TRIAL Keep one row for each choice trial.
%   In the trial files, each choice trial occupies two rows (one per item).
%   The function looks for a column (or combination of columns) that pairs the
%   two rows of each trial: counter, number, or Category + rt. A key is accepted
%   if it yields exactly nTrials pairs whose two rows have the same Consistensy
%   code. The first row of each pair is returned.

keys = {{'counter'}, {'number'}, {'Category', 'rt'}};
for k = 1:numel(keys)
    kv = keys{k};
    if ~all(ismember(kv, T.Properties.VariableNames)); continue; end
    args = cellfun(@(v) T.(v), kv, 'UniformOutput', false);
    G = findgroups(args{:});
    cnt = accumarray(G, 1);
    if numel(cnt) == nTrials && all(cnt == 2)
        sameCons = accumarray(G, T.Consistensy, [], @(x) numel(unique(x)) == 1);
        if all(sameCons)
            [~, first] = unique(G, 'first');
            P = T(sort(first), :);
            return
        end
    end
end
error('%s: could not identify %d trial pairs (tried counter, number, Category+rt).', fname, nTrials);
end

function [cond, coding] = assign_conditions(label, diff, labelVar)
%ASSIGN_CONDITIONS Map the codes of the distance label to far / medium / near.
%   The code with the largest mean rating difference is 'far', the next
%   'medium' and the smallest 'near'. Returns a cell array of condition names
%   (one per row) and a table showing which code was assigned to which condition.

lv = unique(label(~isnan(label)));
if numel(lv) ~= 3; error('%s has %d levels (expected 3).', labelVar, numel(lv)); end
m = arrayfun(@(v) mean(diff(label == v)), lv);
[~, ord] = sort(m, 'descend');
names = {'far', 'medium', 'near'};
cond = cell(numel(label), 1);
coding = table();
for k = 1:3
    cond(label == lv(ord(k))) = names(k);
    coding = [coding; table({labelVar}, lv(ord(k)), names(k), m(ord(k)), ...
        'VariableNames', {'LabelVar', 'Code', 'Condition', 'MeanRatingDiff'})]; %#ok<AGROW>
    fprintf('%s code %g = %s (mean rating difference %.2f)\n', labelVar, lv(ord(k)), names{k}, m(ord(k)));
end
fprintf('\n');
end

function c = to_cellstr(x)
%TO_CELLSTR Convert a numeric, string or cell column to a cell array of char.
if iscell(x); c = cellfun(@(v) num2str(v), x, 'UniformOutput', false);
else; c = cellstr(string(x)); end
end
