%% =========================================================================
%  M21_LDT_measure_amp.m
%  Measures mean amplitude across a specified time window for each bin,
%  channel, and subject.  Outputs a long-format CSV ready for R/lme4.
%
%  Output: <studyID>_mea_<start>_<end>_bl_<blStart>_<blEnd>.csv
% =========================================================================

clear; clc;
[ALLEEG, EEG, CURRENTSET, ALLCOM] = eeglab;
ALLERP     = buildERPstruct([]);
CURRENTERP = 0;

prompt = { ...
    'StudyID:', ...
    'TaskID (leave blank if none):', ...
    'Data collection location (pc | hc):', ...
    'Subject list file:', ...
    'ERP filename extension after subject/task IDs (leave blank if none):', ...
    'Bins to measure (MATLAB expression, e.g.  9:10  or  [9 10]):', ...
    'Measurement window in ms (e.g.  [300 500]):', ...
    'Baseline window in ms (e.g.  [-200 0]):'};
dlgtitle = 'Amplitude measurement parameters';
dims     = [1 72];
definput = {'M21', 'VSL2', 'hc', 'm21_subjectlist1_all.txt', 'binop', '25:40', '[300 500]', '[-200 0]'};
my_input = inputdlg(prompt, dlgtitle, dims, definput);
if isempty(my_input), error('Cancelled by user.'); end

DIR      = pwd;
studyID  = strtrim(my_input{1});
taskID   = strtrim(my_input{2});
location = lower(strtrim(my_input{3}));
subj_list_fname = strtrim(my_input{4});
erp_ext  = strtrim(my_input{5});

% Validate and parse numeric inputs
try
    bins     = eval(strtrim(my_input{6}));
    interval = eval(strtrim(my_input{7}));
    baseline = eval(strtrim(my_input{8}));
catch ME
    error('Could not parse numeric inputs: %s', ME.message);
end

if ~isnumeric(bins) || any(bins < 1)
    error('Bin numbers must be positive integers.');
end
if numel(interval) ~= 2 || interval(1) >= interval(2)
    error('Measurement window must be [start end] with start < end.');
end
if numel(baseline) ~= 2 || baseline(1) >= baseline(2)
    error('Baseline window must be [start end] with start < end.');
end

if ~isfile(subj_list_fname)
    error('Subject list file "%s" not found.', subj_list_fname);
end
subj_list = importdata(subj_list_fname);
nsubj     = length(subj_list);

if strcmp(location, 'hc')
    chan_num = 27;
else
    chan_num = 31;
end
channels = 1:chan_num;

if isempty(taskID), task_pfx = ''; else, task_pfx = ['_' taskID]; end

% Auto-build output filename
fmt = @(x) strrep(num2str(x), '-', 'n');
output_fname = fullfile(DIR, sprintf('%s_mea_%s_%s_bl_%s_%s.csv', ...
    studyID, fmt(interval(1)), fmt(interval(2)), fmt(baseline(1)), fmt(baseline(2))));
erp_list_fname = fullfile(DIR, 'erp_file_list.txt');

fprintf('Output will be saved to:\n  %s\n', output_fname);

%% Build ERP file list
fid = fopen(erp_list_fname, 'w');
if fid == -1, error('Cannot open erp_file_list.txt for writing.'); end

erp_file_list = {};
missing       = {};

for s = 1:nsubj
    subjID      = strtrim(subj_list{s});
    subject_DIR = fullfile(DIR,'DATA', subjID);

    if ~isempty(taskID) && ~isempty(erp_ext)
        fname = sprintf('%s%s_%s.erp', subjID, task_pfx, erp_ext);
    elseif isempty(taskID) && ~isempty(erp_ext)
        fname = sprintf('%s_%s.erp', subjID, erp_ext);
    elseif ~isempty(taskID) && isempty(erp_ext)
        fname = sprintf('%s%s.erp', subjID, task_pfx);
    else
        fname = sprintf('%s.erp', subjID);
    end

    fpath = fullfile(subject_DIR, fname);
    if ~isfile(fpath)
        fprintf(' *** WARNING: %s not found — skipping ***\n', fpath);
        missing{end+1} = subjID; %#ok<AGROW>
    else
        fprintf(fid, '%s\n', fpath);
        erp_file_list{end+1} = fpath; %#ok<AGROW>
    end
end
fclose(fid);

if isempty(erp_file_list)
    error('No valid ERP files found.');
end
if ~isempty(missing)
    fprintf('\n*** Missing ERP files for %d subject(s): %s ***\n\n', ...
        numel(missing), strjoin(missing, ', '));
end

%% Measure amplitude
fprintf('\nMeasuring mean amplitude [%d %d] ms, baseline [%d %d] ms...\n', ...
    interval(1), interval(2), baseline(1), baseline(2));

try
    ALLERP = pop_geterpvalues(erp_list_fname, ...
        interval, bins, channels, ...
        'Baseline',     baseline, ...
        'Binlabel',     'on', ...
        'FileFormat',   'long', ...
        'Filename',     output_fname, ...
        'Fracreplace',  'NaN', ...
        'InterpFactor', 1, ...
        'Measure',      'meanbl', ...
        'Mlabel',       'mean_amp', ...
        'Resolution',   3);
catch ME
    error('pop_geterpvalues failed: %s', ME.message);
end

fprintf('\nDone. Results saved to:\n  %s\n', output_fname);
