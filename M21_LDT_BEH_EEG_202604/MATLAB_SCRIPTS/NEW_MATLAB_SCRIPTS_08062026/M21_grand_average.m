%% =========================================================================
%  M21_LDT_grand_average.m
%  Creates grand-average ERP file from individual .erp files.
%  Run this after reviewing individual ERPs and finalising your subject list.
%
%  Output: <ga_name>.erp  saved to the current directory
% =========================================================================

clear; clc;
[ALLEEG, EEG, CURRENTSET, ALLCOM] = eeglab;
ALLERP     = buildERPstruct([]);
CURRENTERP = 0;

prompt   = { ...
    'StudyID:', ...
    'TaskID (leave blank if none):', ...
    'Subject list file:', ...
    'Filename extension after subject/task IDs (leave blank if none):', ...
    'Grand-average output name (no extension):'};
dlgtitle = 'Grand average parameters';
dims     = [1 72];
definput = {'M21', 'VSL2', 'm21_subjectlist1_insensitive.txt', 'binop', 'M21_VSL2_GA1_insensitive'};
my_input = inputdlg(prompt, dlgtitle, dims, definput);
if isempty(my_input), error('Cancelled by user.'); end

DIR       = pwd;
studyID   = strtrim(my_input{1});
taskID    = strtrim(my_input{2});
subj_list = importdata(strtrim(my_input{3}));
f_ext     = strtrim(my_input{4});
ga_name   = strtrim(my_input{5});
nsubj     = length(subj_list);

if isempty(taskID), task_pfx = ''; else, task_pfx = ['_' taskID]; end
if isempty(f_ext),  f_sfx   = ''; else, f_sfx   = ['_' f_ext]; end

valid_erpsets = [];

for subject = 1:nsubj
    subjID      = strtrim(subj_list{subject});
    subject_DIR = fullfile(DIR,'DATA', subjID);
    fname       = [subjID task_pfx f_sfx '.erp'];
    fpath       = fullfile(subject_DIR, fname);

    if ~isfile(fpath)
        fprintf(' *** WARNING: %s not found — skipping ***\n', fpath);
        continue
    end

    fprintf('Loading %s\n', fname);
    ERP = pop_loaderp('filename', fname, 'filepath', subject_DIR);
    CURRENTERP         = CURRENTERP + 1;
    ALLERP(CURRENTERP) = ERP;
    valid_erpsets      = [valid_erpsets, CURRENTERP]; %#ok<AGROW>
    erplab redraw;
end

if isempty(valid_erpsets)
    error('No valid ERP files found.');
end

fprintf('\nCreating grand average from %d ERP sets...\n', length(valid_erpsets));

ERP = pop_gaverager(ALLERP, ...
    'Erpsets',  valid_erpsets, ...
    'Criterion', 100, ...
    'SEM',      'on', ...
    'Warning',  'on', ...
    'Weighted', 'on');

ERP = pop_savemyerp(ERP, ...
    'erpname',  ga_name, ...
    'filename', [ga_name '.erp'], ...
    'filepath', DIR, ...
    'Warning',  'on');

CURRENTERP         = CURRENTERP + 1;
ALLERP(CURRENTERP) = ERP;
erplab redraw;

fprintf('\nGrand average saved: %s/%s.erp\n', DIR, ga_name);
