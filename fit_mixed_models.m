function fit_mixed_models
%FIT_MIXED_MODELS Trial-level mixed-effects models of the choice task.
%
%   Fits all mixed-effects models reported in the paper (Tables 3, 4 and S1)
%   with one common set of rules.
%
%   Common rules
%     Unit of analysis  single choice trials; trials with tied ratings are excluded.
%     Predictors        ASRS, BIS, BAS and SSS-AE z-standardized across participants;
%                       actual rating difference z-standardized across trials (Model 2);
%                       distance effects-coded as two numeric columns
%                         C_far    : far = 1, medium = 0, near = -1
%                         C_medium : far = 0, medium = 1, near = -1
%                       sex coded female = +0.5, male = -0.5.
%     Random effects    by-participant intercepts and slopes for the within-participant
%                       predictor (distance or rating difference) and by-category
%                       intercepts. If this model fails or does not converge, it is
%                       refitted with intercepts only (reported in the ModelInfo sheet).
%     Estimation        GLMM (consistency): binomial, logit link, Laplace approximation.
%                       LMM (rating difference, log RT): maximum likelihood.
%     Tests             likelihood-ratio tests comparing the full model with the model
%                       without the tested term(s), keeping the same random effects;
%                       the two distance terms and the two interaction terms are
%                       tested jointly.
%     Coefficients      estimates, SE and Wald 95% CI (odds ratios for GLMMs).
%
%   Models
%     Model 1   Consistent ~ distance + ASRS + ASRS x distance                (Table 3)
%     Model 2   Consistent ~ rating difference + ASRS + ASRS x rating diff.   (Table 3)
%     Model 3   Consistent ~ distance + ASRS, trials with rating diff. = 1    (Table 3)
%     Model 4   Model 1 + sex                                                 (Table S1)
%     Model 5   Model 1 + BIS + BAS + SSS-AE                                  (Table S1)
%     LMM rating difference  Diff (points) ~ distance + ASRS + ASRS x distance (Table 4)
%     LMM log RT             log(RT) ~ distance + ASRS + ASRS x distance       (Table 4)
%
%   Input   Input/*_Analysis02.xlsx  trial files, one per participant (see README)
%           Questionnaire.xlsx       questionnaire scores (see README)
%   Output  Results/mixed_models.xlsx
%             ModelInfo, LRT, Coefficients, SimpleSlopes_RatingDiff, RandomEffects
%           Results/mixed_models_log.txt
%
%   Run from the folder that contains Input/ and Questionnaire.xlsx.
%   Requires the Statistics and Machine Learning Toolbox (fitglme, fitlme).

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
logFile = fullfile(CFG.resultDir, 'mixed_models_log.txt');
outFile = fullfile(CFG.resultDir, 'mixed_models.xlsx');
if exist(logFile, 'file'); delete(logFile); end
if exist(outFile, 'file'); delete(outFile); end
warning('off', 'MATLAB:xlswrite:AddSheet');
diary(logFile);
cleanupObj = onCleanup(@() close_log(logFile)); %#ok<NASGU>
feature('hotlinks', false);
fprintf('fit_mixed_models  %s\n\n', datestr(now));

%% ---- data -----------------------------------------------------------------
Q = read_questionnaire(CFG.questFile, CFG.questSheet);
idDigits = regexprep(Q.ID, '\D', '');
files = dir(fullfile(CFG.trialDir, CFG.trialPattern));
if isempty(files); error('No files matching %s in %s', CFG.trialPattern, CFG.trialDir); end
D = table();
for f = 1:numel(files)
    T = readtable(fullfile(CFG.trialDir, files(f).name), 'Sheet', CFG.trialSheet);
    need = {'Consistensy', 'Distance', 'Category', 'rt', CFG.condVar};
    if ~all(ismember(need, T.Properties.VariableNames))
        error('%s: expected columns not found. Columns read: %s', files(f).name, ...
            strjoin(T.Properties.VariableNames, ', '));
    end
    qi = match_subject(files(f).name, T, idDigits);
    if isempty(qi); warning('No questionnaire match for %s - skipped.', files(f).name); continue; end
    P = one_row_per_trial(T, CFG.nTrials, files(f).name);
    n = height(P);
    S = table(repmat(Q.ID(qi), n, 1), to_cellstr(P.Category), P.(CFG.condVar), P.Consistensy, P.Distance, P.rt, ...
        repmat(Q.ASRS_Total(qi), n, 1), repmat(Q.BIS(qi), n, 1), repmat(Q.BAS(qi), n, 1), ...
        repmat(Q.SSS_Total(qi), n, 1), repmat(Q.Sex(qi), n, 1), ...
        'VariableNames', {'Subj','Category','Label','ConsCode','Diff','RT','ASRS','BIS','BAS','SSS','Sex'});
    D = [D; S]; %#ok<AGROW>
end
fprintf('Participants: %d, trials: %d\n', numel(unique(D.Subj)), height(D));
D.Cond = assign_conditions(D.Label, D.Diff, CFG.condVar);

% analysed trials (ties excluded) and predictors
% ConsCode: 1 = higher-rated item chosen, 2 = lower-rated item chosen, 3 = tied ratings
M = D(D.ConsCode ~= 3, :);
fprintf('Analysed trials (ties excluded): %d of %d\n\n', height(M), height(D));
M.Consistent = double(M.ConsCode == 1);
M.C_far    = double(strcmp(M.Cond, 'far'))    - double(strcmp(M.Cond, 'near'));
M.C_medium = double(strcmp(M.Cond, 'medium')) - double(strcmp(M.Cond, 'near'));
M.ASRS_z = zSubj(M, 'ASRS');
M.BIS_z  = zSubj(M, 'BIS');
M.BAS_z  = zSubj(M, 'BAS');
M.SSS_z  = zSubj(M, 'SSS');
M.SexF   = 0.5 * strcmp(M.Sex, 'F') - 0.5 * strcmp(M.Sex, 'M');
M.Diff_z = (M.Diff - mean(M.Diff)) ./ std(M.Diff);
M.ASRSxFar    = M.ASRS_z .* M.C_far;
M.ASRSxMedium = M.ASRS_z .* M.C_medium;
M.ASRSxDiff   = M.ASRS_z .* M.Diff_z;
M.logRT = log(M.RT);
M.Subj = categorical(M.Subj);
M.Category = categorical(M.Category);

ranCond = '(1 + C_far + C_medium | Subj) + (1 | Category)';
ranDiff = '(1 + Diff_z | Subj) + (1 | Category)';
ranInt  = '(1 | Subj) + (1 | Category)';
dist = {'C_far', 'C_medium'};
intx = {'ASRSxFar', 'ASRSxMedium'};

R = struct('Coef', table(), 'LRT', table(), 'Info', table(), 'Ran', table());

%% ---- Model 1: distance x ASRS --------------------------------------------------
fx = [dist, {'ASRS_z'}, intx];
[R, m1] = runModel(R, 'Model 1', M, 'Consistent', fx, ranCond, ranInt, true, ...
    {'Distance', dist; 'ASRS', {'ASRS_z'}; 'ASRS x distance', intx});
predicted(m1, 'Model 1');

%% ---- Model 2: actual rating difference x ASRS ------------------------------------
fx = {'Diff_z', 'ASRS_z', 'ASRSxDiff'};
R = runModel(R, 'Model 2', M, 'Consistent', fx, ranDiff, ranInt, true, ...
    {'Rating difference', {'Diff_z'}; 'ASRS', {'ASRS_z'}; 'ASRS x rating difference', {'ASRSxDiff'}});

%% ---- Model 3: trials with a rating difference of 1 (all distance conditions) -----
M3 = M(M.Diff == 1, :);
reportSubset(M3, 'Model 3');
[R, m3] = runModel(R, 'Model 3', M3, 'Consistent', [dist, {'ASRS_z'}], ranCond, ranInt, true, ...
    {'Distance', dist; 'ASRS', {'ASRS_z'}});
predicted(m3, 'Model 3');

%% ---- Model 4: Model 1 + sex --------------------------------------------------------
fx = [dist, {'ASRS_z'}, intx, {'SexF'}];
R = runModel(R, 'Model 4', M, 'Consistent', fx, ranCond, ranInt, true, ...
    {'ASRS', {'ASRS_z'}; 'Sex', {'SexF'}});

%% ---- Model 5: Model 1 + BIS, BAS, SSS-AE -------------------------------------------
fx = [dist, {'ASRS_z'}, intx, {'BIS_z', 'BAS_z', 'SSS_z'}];
R = runModel(R, 'Model 5', M, 'Consistent', fx, ranCond, ranInt, true, ...
    {'ASRS', {'ASRS_z'}; 'BIS', {'BIS_z'}; 'BAS', {'BAS_z'}; 'SSS-AE', {'SSS_z'}});

%% ---- LMM: actual rating difference (points) ----------------------------------------
fx = [dist, {'ASRS_z'}, intx];
[R, mD] = runModel(R, 'LMM rating difference', M, 'Diff', fx, ranCond, ranInt, false, ...
    {'Distance', dist; 'ASRS', {'ASRS_z'}; 'ASRS x distance', intx});
Slopes = simpleSlopes(mD, 'LMM rating difference');

%% ---- LMM: log response time ------------------------------------------------------
R = runModel(R, 'LMM log RT', M, 'logRT', fx, ranCond, ranInt, false, ...
    {'Distance', dist; 'ASRS', {'ASRS_z'}; 'ASRS x distance', intx});

%% ---- write -----------------------------------------------------------------------
writetable(R.Info, outFile, 'Sheet', 'ModelInfo');
writetable(R.LRT,  outFile, 'Sheet', 'LRT');
writetable(R.Coef, outFile, 'Sheet', 'Coefficients');
writetable(Slopes, outFile, 'Sheet', 'SimpleSlopes_RatingDiff');
if ~isempty(R.Ran); writetable(R.Ran, outFile, 'Sheet', 'RandomEffects'); end
fprintf('Done. Results: %s\n', outFile);
end

%% ========================= local functions ===============================
function [R, mdl] = runModel(R, name, D, y, fx, ranFull, ranSimple, isGLMM, tests)
% Fit the full model (fallback to intercepts-only random effects if needed),
% then likelihood-ratio tests for each set of terms in TESTS.
fprintf('==================== %s ====================\n', name);
pat = 'converge|Hessian|singular|positive definite';
ran = ranFull; fallback = false;
lastwarn('');
try
    mdl = fitModel(D, y, fx, ran, isGLMM);
    msg = lastwarn;
    if ~isempty(regexpi(msg, pat, 'once'))
        if strcmp(ranFull, ranSimple)
            fprintf('NOTE: convergence warning with the simplest random structure: %s\n', msg);
        else
            error('convergence: %s', msg);
        end
    end
catch ME
    if strcmp(ranFull, ranSimple); rethrow(ME); end
    fprintf('Full random structure failed (%s)\n -> refitted with %s\n', ME.message, ranSimple);
    ran = ranSimple; fallback = true;
    mdl = fitModel(D, y, fx, ran, isGLMM);
end
disp(mdl);

R.Info = [R.Info; table({name}, {sprintf('%s ~ 1 + %s', y, strjoin(fx, ' + '))}, {ran}, fallback, ...
    mdl.NumObservations, mdl.ModelCriterion.AIC, mdl.LogLikelihood, ...
    'VariableNames', {'Model','Fixed','Random','Fallback','nObs','AIC','LogLik'})];

C = mdl.Coefficients;
nC = numel(C.Estimate);
T = table(repmat({name}, nC, 1), cellstr(C.Name), C.Estimate, C.SE, C.tStat, C.DF, C.pValue, C.Lower, C.Upper, ...
    'VariableNames', {'Model','Term','Estimate','SE','Wald_stat','DF','Wald_p','CI_low','CI_high'});
if isGLMM
    T.OR = exp(T.Estimate); T.OR_low = exp(T.CI_low); T.OR_high = exp(T.CI_high);
else
    T.OR = nan(nC, 1); T.OR_low = nan(nC, 1); T.OR_high = nan(nC, 1);
end
R.Coef = [R.Coef; T];

for k = 1:size(tests, 1)
    drop = tests{k, 2};
    red = fitModel(D, y, setdiff(fx, drop, 'stable'), ran, isGLMM);
    L = compare(red, mdl);
    if L.deltaDF(2) ~= numel(drop)
        warning('%s / %s: deltaDF = %d, expected %d', name, tests{k, 1}, L.deltaDF(2), numel(drop));
    end
    R.LRT = [R.LRT; table({name}, tests(k, 1), L.LRStat(2), L.deltaDF(2), L.pValue(2), ...
        'VariableNames', {'Model','Test','ChiSq','df','p'})];
    fprintf('LRT %-26s chi2(%d) = %7.3f, p = %.4f\n', tests{k, 1}, L.deltaDF(2), L.LRStat(2), L.pValue(2));
end

try
    [~, ~, st] = covarianceParameters(mdl);
    for g = 1:numel(st)
        G = dataset2table(st{g});
        nG = height(G);
        getc = @(v) iff(ismember(v, G.Properties.VariableNames), G, v, nG);
        R.Ran = [R.Ran; table(repmat({name}, nG, 1), getc('Group'), getc('Name1'), getc('Name2'), getc('Type'), G.Estimate, ...
            'VariableNames', {'Model','Group','Name1','Name2','Type','Estimate'})];
    end
catch ME
    fprintf('(random-effect table not written for %s: %s)\n', name, ME.message);
end
fprintf('\n');
end

function out = iff(cond, G, v, n)
if cond
    x = G.(v);
    if iscell(x); out = x; else; out = cellstr(string(x)); end
else
    out = repmat({''}, n, 1);
end
end

function mdl = fitModel(D, y, fx, ran, isGLMM)
formula = sprintf('%s ~ 1 + %s + %s', y, strjoin(fx, ' + '), ran);
if isempty(fx); formula = sprintf('%s ~ 1 + %s', y, ran); end
if isGLMM
    mdl = fitglme(D, formula, 'Distribution', 'Binomial', 'Link', 'logit', 'FitMethod', 'Laplace');
else
    mdl = fitlme(D, formula, 'FitMethod', 'ML');
end
end

function predicted(mdl, name)
C = mdl.Coefficients;
b0 = C.Estimate(strcmp(cellstr(C.Name), '(Intercept)'));
b  = C.Estimate(strcmp(cellstr(C.Name), 'ASRS_z'));
pr = @(x) 100 ./ (1 + exp(-x));
fprintf('%s predicted consistency: ASRS -1 SD %.1f%%, mean %.1f%%, +1 SD %.1f%%\n\n', ...
    name, pr(b0 - b), pr(b0), pr(b0 + b));
end

function reportSubset(S, name)
subj = unique(S.Subj);
n = arrayfun(@(s) sum(S.Subj == s), subj);
fprintf('%s subset: %d trials from %d participants (per participant median %g, range %d-%d)\n', ...
    name, height(S), numel(subj), median(n), min(n), max(n));
end

function T = simpleSlopes(mdl, name)
% ASRS slope within each distance condition (rating points per SD of ASRS), Wald SE and 95% CI
C = mdl.Coefficients; V = mdl.CoefficientCovariance; nm = cellstr(C.Name);
idx = @(s) find(strcmp(nm, s));
w = zeros(3, numel(nm));
w(:, idx('ASRS_z')) = 1;
w(1, idx('ASRSxFar')) = 1;                                 % far
w(2, idx('ASRSxMedium')) = 1;                              % medium
w(3, idx('ASRSxFar')) = -1; w(3, idx('ASRSxMedium')) = -1; % near
est = w * C.Estimate; se = sqrt(diag(w * V * w'));
T = table(repmat({name}, 3, 1), {'far'; 'medium'; 'near'}, est, se, est - 1.96 * se, est + 1.96 * se, ...
    'VariableNames', {'Model','Condition','ASRS_slope','SE','CI_low','CI_high'});
fprintf('Simple slopes of ASRS (%s):\n', name); disp(T);
end

function z = zSubj(D, var)
[~, first] = unique(D.Subj, 'first');
v = D.(var)(first);
z = (D.(var) - mean(v)) ./ std(v);
end

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
